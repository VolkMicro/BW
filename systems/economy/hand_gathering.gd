extends RefCounted
class_name HandGathering
## The god's Hand pulling things out of the world and putting them in a
## village's stores.
##
## ---------------------------------------------------------------------------
## WHY THIS IS A VERB THE GAME NEEDED
## ---------------------------------------------------------------------------
## Everything the player could do until now went through a rite: draw a shape,
## a number moves. That is a spell system, not a pair of hands. The thing this
## genre is actually about is reaching down and moving the world — pulling up
## a tree because the woodpile is empty, prising out a boulder because the
## forge has gone cold — and then watching the people react to a world that
## changed under them.
##
## Mechanically it is also the answer to a real gap: a village whose
## woodcutters are all dead, or whose forest has been cleared, previously had
## no way back. The god's own hands are that way back, at a price.
##
## ---------------------------------------------------------------------------
## THE PRICE, AND WHY IT IS NOT FREE
## ---------------------------------------------------------------------------
## Every take is a real thing removed from the island. A hillside pulled bare
## stops producing: villagers' woodcutting work is scored against the trees
## that are actually there, and `count_remaining()` is how the game tells the
## player they have stripped it.
##
## Feeding a village shifts Naklon toward mercy — this IS the karma the brief
## asks for, expressed through the axis the game already has rather than
## through a second invisible number. Uprooting a tree INSIDE a village's own
## Reach shifts a little further than doing it out in the wild, because that
## is the difference between a god providing and a god tidying.

## How close to the Hand a thing has to be for the Hand to find it.
const GRAB_RADIUS := 26.0
## How far a village can be and still receive what was picked up. Generous:
## the god is carrying it, not the villagers.
const DELIVER_RADIUS := 130.0

## What one of each yields. Deliberately close to a minute of one worker's
## output — enough that a handful of trees rescues a village, not so much that
## a god with a spare afternoon makes the economy irrelevant.
const WOOD_PER_TREE := 9.0
const STONE_PER_ROCK := 7.0
const FOOD_PER_FIELD := 8.0

## Mercy per take. Small: this is a kindness done a dozen times, and it should
## take a dozen of them to visibly move a god's reputation.
const NAKLON_MERCY_PER_GIFT := -0.012
const NAKLON_WEIGHT := 0.35

## What the Hand can pick up, and what it becomes.
enum Harvest { TREE, ROCK, FIELD }


## Tries to take whatever is under `world_pos` and give it to the nearest
## village that can receive it.
##
## Returns a result dictionary the caller can narrate:
##   {"ok": bool, "reason": StringName, "kind": int, "village": Village,
##    "resource": StringName, "amount": float, "position": Vector3}
##
## `reason` on failure is one of &"nothing_here", &"no_village",
## &"stores_full" — three different failures that must be told apart, because
## "there is no tree there" and "the barn is already full" ask the player for
## completely different next moves.
static func take_at(scatter: Node, world_pos: Vector3) -> Dictionary:
	var fail := {"ok": false, "reason": &"nothing_here", "position": world_pos}
	if scatter == null or not scatter.has_method("find_nearest"):
		return fail

	var xz := Vector2(world_pos.x, world_pos.z)
	# Trees first, then rocks. Grass is not a resource — a god harvesting
	# individual tufts is a worse game, not a richer one.
	var candidates := [
		{"kind": Harvest.TREE, "scatter_kind": 1, "resource": &"wood", "amount": WOOD_PER_TREE},
		{"kind": Harvest.ROCK, "scatter_kind": 2, "resource": &"stone", "amount": STONE_PER_ROCK},
	]
	for c in candidates:
		var hit: Dictionary = scatter.call("find_nearest", c.scatter_kind, xz, GRAB_RADIUS)
		if hit.is_empty():
			continue
		var village := _nearest_receiver(Vector2(hit.position.x, hit.position.z))
		if village == null:
			return {"ok": false, "reason": &"no_village", "position": hit.position}
		# Checked BEFORE taking: pulling up a tree and then discovering the
		# barn is full would destroy it for nothing, which reads as the game
		# punishing the player for a thing it did not warn them about.
		if Stockpile.get_amount(village, c.resource) >= Stockpile.capacity(village, c.resource) - 0.5:
			return {"ok": false, "reason": &"stores_full", "village": village,
				"resource": c.resource, "position": hit.position}
		if not scatter.call("take", c.scatter_kind, hit):
			continue
		Stockpile.add(village, c.resource, float(c.amount))
		Naklon.shift(NAKLON_MERCY_PER_GIFT, NAKLON_WEIGHT)
		return {"ok": true, "reason": &"taken", "kind": c.kind, "village": village,
			"resource": c.resource, "amount": float(c.amount), "position": hit.position}

	# Nothing to pull up. If the Hand is over a village's own fields, the god
	# can gather the harvest directly instead.
	var field_village := _village_field_at(xz)
	if field_village != null:
		if Stockpile.get_amount(field_village, &"food") >= Stockpile.capacity(field_village, &"food") - 0.5:
			return {"ok": false, "reason": &"stores_full", "village": field_village,
				"resource": &"food", "position": world_pos}
		Stockpile.add(field_village, &"food", FOOD_PER_FIELD)
		Naklon.shift(NAKLON_MERCY_PER_GIFT, NAKLON_WEIGHT)
		return {"ok": true, "reason": &"taken", "kind": Harvest.FIELD, "village": field_village,
			"resource": &"food", "amount": FOOD_PER_FIELD, "position": world_pos}

	return fail


## The village a gathered thing goes to: the nearest one that is not Louhi's.
## Her villages do not accept gifts from you — that is what her holding them
## means, and handing them firewood would be a way to feed the other side.
static func _nearest_receiver(world_xz: Vector2) -> Village:
	var best: Village = null
	var best_d := DELIVER_RADIUS
	for value in GameState.villages.values():
		var v: Village = value
		if v.loyal_to_rival:
			continue
		var d: float = v.position_on_island.distance_to(world_xz)
		if d < best_d:
			best_d = d
			best = v
	return best


## The fields belong to whichever village is close enough to be working them.
## Tighter than DELIVER_RADIUS because this is standing IN somebody's crop,
## not carrying a log to them.
const FIELD_RADIUS := 52.0

static func _village_field_at(world_xz: Vector2) -> Village:
	for value in GameState.villages.values():
		var v: Village = value
		if v.loyal_to_rival:
			continue
		if v.position_on_island.distance_to(world_xz) <= FIELD_RADIUS:
			return v
	return null


## Trees left standing near a point. The caller warns the player with this
## before the hillside is bare rather than after.
static func count_remaining(scatter: Node, world_xz: Vector2, radius: float) -> int:
	if scatter == null or not scatter.has_method("count_near"):
		return -1
	return int(scatter.call("count_near", 1, world_xz, radius))
