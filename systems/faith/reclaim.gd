extends RefCounted
class_name Reclaim
## Winning back a village Louhi has taken.
##
## ---------------------------------------------------------------------------
## WHY THIS EXISTS
## ---------------------------------------------------------------------------
## The design is a contest between two gods that ends with one of them left.
## Until now it could only ever end one way. `LouhiDirector._escalate_to_tier2`
## sets `Village.loyal_to_rival = true`, and from that moment
## `Reach.radius_for_village()` returns 0 and every conversion method in
## `reach.gd` short-circuits on the same flag — that file's own comment says
## it plainly: "there is currently no reclaim mechanic anywhere in the
## codebase for the player to contest this with, so tier 2 is a one-way door".
##
## A one-way door is not a war. Every village Louhi took was gone for good,
## the player's ceiling fell every time she acted, and the only ending the
## island could actually reach was hers. This is the other direction.
##
## ---------------------------------------------------------------------------
## WHY IT IS NOT JUST "CONVERT IT AGAIN"
## ---------------------------------------------------------------------------
## Faith and grip are different things and must not share a number. Faith is
## what a village feels about you; grip is what Louhi has on it. Rites cast at
## a taken village do not persuade anybody — nobody there is listening any
## more — they pry her fingers loose one at a time. Only when the grip is gone
## do the people get to have an opinion again, and they come back at a LOW
## faith, not at the number they left with: being taken and freed is not the
## same as never having left.
##
## Kept out of `systems/faith/reach.gd` on purpose. That file is package J's
## and the netcode carries a mirrored copy of it (`net/network_manager.gd`),
## so a new rule bolted into it has to be right in two places at once. This
## is a separate, additive layer that reads and writes only `Village`.

## Meta key on the Village. Grip lives on the resource rather than in a
## dictionary here so it survives whatever holds a reference to the village,
## exactly like Stockpile's store does.
const META_KEY: StringName = &"louhi_grip"

## Faith a village comes back with. Deliberately low — they have spent a long
## time being told you are nothing, and the player has to finish the job the
## ordinary way.
const FAITH_ON_RETURN: float = 0.18

## Devotion the god gains the moment a village is torn back. This is the
## "grow stronger by taking villages" half of the design, from the player's
## side: a reclaim is worth materially more than a first conversion, because
## it also costs Louhi one.
const DEVOTION_ON_RETURN: float = 12.0

## How far from a taken village a rite still counts. `Reach.radius_for_village`
## returns 0 for it — that is the whole point of her holding it — so contesting
## needs its own radius. Generous, because the player is reaching into
## somebody else's territory and should not have to hit a pinhead.
const CONTEST_RADIUS: float = 46.0


## Louhi's remaining hold, 1 (just taken) .. 0 (about to break). A village
## she does not hold has no grip and returns 0.
static func grip_of(v: Village) -> float:
	if v == null or not v.loyal_to_rival:
		return 0.0
	if not v.has_meta(META_KEY):
		v.set_meta(META_KEY, 1.0)
	return float(v.get_meta(META_KEY))


## Applies one rite's worth of prying. `amount` is on the same scale as
## `Reach.convert_via_help`'s amount — roughly 4..6 for a clean sigil.
##
## Returns {"grip": float, "released": bool}. `released` is true on the single
## call that breaks her hold, so the caller can narrate it once.
static func press(v: Village, amount: float) -> Dictionary:
	if v == null or not v.loyal_to_rival:
		return {"grip": 0.0, "released": false}
	# Divided by 40 rather than tuned freely: a 4.4-amount rite is worth about
	# 0.11 of her grip, so nine or ten clean rites take a village back. That is
	# deliberately more work than the ~fifteen casts a fresh conversion needs
	# only in cost per point — a taken village is a smaller, harder target and
	# the player has to keep coming back to it while she works elsewhere.
	var grip: float = maxf(grip_of(v) - maxf(amount, 0.0) / 40.0, 0.0)
	v.set_meta(META_KEY, grip)
	if grip > 0.0:
		return {"grip": grip, "released": false}
	_release(v)
	return {"grip": 0.0, "released": true}


## Hands the village back. Routed through GameState so every existing listener
## — the Reach ring, the campaign's quests, the Sanctum's own skin — reacts
## through the path it already knows, rather than through a new signal nobody
## is connected to.
static func _release(v: Village) -> void:
	v.loyal_to_rival = false
	v.remove_meta(META_KEY)
	GameState.set_faith_fraction(v.id, FAITH_ON_RETURN)
	GameState.add_devotion(v.id, DEVOTION_ON_RETURN)
	Voices.react(&"village_reclaimed", {
		"village_id": v.id, "village_name": v.display_name,
	})


## True if `world_pos` is close enough to a village Louhi holds for a rite to
## count as contesting it. Returns the village, or null.
static func contested_village_at(world_pos: Vector3) -> Village:
	var flat := Vector2(world_pos.x, world_pos.z)
	var best: Village = null
	var best_d := INF
	for value in GameState.villages.values():
		var v: Village = value
		if not v.loyal_to_rival:
			continue
		var d: float = v.position_on_island.distance_to(flat)
		if d <= CONTEST_RADIUS and d < best_d:
			best_d = d
			best = v
	return best
