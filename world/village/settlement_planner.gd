extends RefCounted
class_name SettlementPlanner
## Decides where the island's villages stand, and what they are called.
##
## ---------------------------------------------------------------------------
## WHY THIS IS NOT AUTHORED IN THE SCENE
## ---------------------------------------------------------------------------
## Three villages could be dropped on the map by hand. Fifteen cannot — not
## because typing fifteen anchors is hard, but because the island is generated:
## `island_generator.gd` builds a different lobed, eroded landmass for every
## seed, so an authored X/Z is a guess that the next seed invalidates. Hand
## placement would mean re-authoring the whole layout every time anyone touched
## a generation parameter.
##
## So placement is derived from the terrain instead. The planner reads the real
## heightmap, keeps the sites that a village could actually stand on, and
## spreads them out. Change the seed and you get a different, still-sensible
## settlement pattern for free.
##
## ---------------------------------------------------------------------------
## HOW SITES ARE CHOSEN
## ---------------------------------------------------------------------------
## Blue-noise by rejection, not a grid: candidates are drawn at random and kept
## only if they clear every site already accepted by `min_separation`. A grid
## would put villages in rows, which reads as machine-made from the air — the
## one thing a god-sim island cannot afford, since the player spends the whole
## game looking down at it.
##
## Candidates must also be above the surf, level across the village footprint,
## and not too high up the mountain. `score_site()` then ranks the survivors so
## the good ground (gentle, low, near the coast — where people actually settle)
## fills up before the marginal ground does.
##
## ---------------------------------------------------------------------------
## NAMES
## ---------------------------------------------------------------------------
## A village is named from its own site: a culture stem plus a landform word
## picked by measuring the ground it stands on. "Sankiln Ford" is on a river,
## "Raimborn Scarp" is genuinely up high. This costs almost nothing and means
## the name is never at odds with what the player sees, which is what makes a
## generated name stop reading as generated.
##
## Every stem here is invented, per `docs/audit/respect_audit.md`. They are not
## words from any real language, and the landform suffixes are ordinary English
## geography (Shore, Hollow, Ford), which belongs to no one.

## Per-culture name stems. Four cultures, matching data/cultures/*.tres.
const CULTURE_STEMS := {
	&"fenrayt": ["Fenrayt", "Ederhal", "Mournsel", "Kelvray", "Otterlin"],
	&"sankiln": ["Sankiln", "Vespergrad", "Tulmere", "Ashkeld", "Sarnavy"],
	&"raimborn": ["Raimborn", "Halvenreach", "Drumsey", "Coldharrow", "Merrowfen"],
	&"vainkeeper": ["Vainkeeper", "Grimsalt", "Weyhollow", "Tarnbright", "Sedgewick"],
}

const CULTURE_ORDER: Array[StringName] = [&"fenrayt", &"sankiln", &"raimborn", &"vainkeeper"]

# Landform words, chosen by measuring the site. See `_landform()`.
const NAMES_COAST := ["Shore", "Landing", "Strand", "Quay", "Cove"]
const NAMES_WATER := ["Ford", "Race", "Mill", "Wash", "Weir"]
const NAMES_HIGH := ["Scarp", "Height", "Crag", "Beacon", "Watch"]
const NAMES_HOLLOW := ["Hollow", "Bottom", "Dell", "Bower", "Wend"]
const NAMES_PLAIN := ["Terrace", "Field", "Rest", "Green", "Croft", "Row"]

## Above the surf. Below this a village is standing in the shoreline foam.
const MIN_HEIGHT := 3.0
## Villages are not built on the peaks. This is a fraction of `max_height`.
const MAX_HEIGHT_FRACTION := 0.55
## Largest height spread tolerated across the footprint.
const MAX_RELIEF := 5.0
## Roughly the Sanctum's worship yard, so "level" is measured over the area the
## village actually occupies rather than at a single point.
const FOOTPRINT := 11.0
## Below this, "near the coast" for naming purposes.
const COAST_HEIGHT := 9.0


## Plans `count` villages on `terrain`.
##
## Returns an array of dictionaries in the shape `world/god_view.gd` wants:
## id / culture / display / xz / population / children / devotion /
## faith_fraction / sanctum_hp. Deterministic for a given seed, so two runs of
## the same island produce the same settlements — which is what makes the
## erosion disk cache worth having.
##
## `reserved` sites (the hand-authored villages that carry scene wiring) are
## honoured first: they are returned unchanged at the head of the list and
## every generated site keeps clear of them.
static func plan(terrain: IslandTerrain, count: int, seed_value: int,
		min_separation: float, reserved: Array[Dictionary] = []) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var out: Array[Dictionary] = []
	var taken: Array[Vector2] = []
	for r in reserved:
		out.append(r)
		taken.append(r.xz)

	var half: float = terrain.size_meters * 0.5
	var max_h: float = terrain.max_height * MAX_HEIGHT_FRACTION

	# Oversample, score, then take the best. Drawing exactly `count` sites and
	# keeping whatever passes gives you villages clinging to whatever marginal
	# ledge happened to come up first; drawing many and ranking them puts the
	# settlements on the good ground the way real ones are.
	var wanted: int = count - out.size()
	if wanted <= 0:
		return out

	var candidates: Array[Dictionary] = []
	var attempts: int = maxi(2000, wanted * 400)
	for i in attempts:
		if candidates.size() >= wanted * 12:
			break
		var xz := Vector2(rng.randf_range(-half, half), rng.randf_range(-half, half))
		var relief := _relief(terrain, xz)
		if relief.centre < MIN_HEIGHT or relief.centre > max_h:
			continue
		if relief.spread > MAX_RELIEF:
			continue
		candidates.append({"xz": xz, "centre": relief.centre, "spread": relief.spread})

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _score(a) > _score(b))

	for c in candidates:
		if out.size() >= count:
			break
		var xz: Vector2 = c.xz
		var clear := true
		for t in taken:
			if t.distance_to(xz) < min_separation:
				clear = false
				break
		if not clear:
			continue
		taken.append(xz)

		var culture: StringName = CULTURE_ORDER[out.size() % CULTURE_ORDER.size()]
		var named: Dictionary = _name_for(culture, terrain, xz, c.centre, rng)
		out.append({
			# Always from the ENGLISH name: the id ends up in save files, and
			# one that changed with the locale would make a save written in
			# Russian unloadable in English.
			"id": StringName("isle_%s" % String(named.en).to_snake_case()),
			"culture": culture,
			"display": named.display,
			"xz": xz,
			# Population varies with how good the ground is: the flat, low,
			# sheltered sites support more people, which gives the player a
			# reason to care which villages they take first.
			"population": int(round(lerpf(14.0, 34.0, clampf(_score(c) / 1.4, 0.0, 1.0)))),
			"children": rng.randi_range(2, 7),
			# Nobody starts converted. Faith is what the game is about; handing
			# it out at boot would spend the whole arc before the player acts.
			"devotion": rng.randf_range(4.0, 16.0),
			"faith_fraction": rng.randf_range(0.05, 0.22),
			"sanctum_built": true,
			"sanctum_hp": rng.randf_range(70.0, 100.0),
		})

	if out.size() < count:
		# Say so rather than quietly shipping a half-empty island. Usually means
		# the island shrank, min_separation grew, or a generation parameter made
		# the landmass steeper than MAX_RELIEF tolerates.
		push_warning("SettlementPlanner: wanted %d villages, the terrain only had room for %d." % [count, out.size()])
	return out


## Higher is better ground: level, low, but still comfortably above the surf.
static func _score(c: Dictionary) -> float:
	var level: float = 1.0 - clampf(float(c.spread) / MAX_RELIEF, 0.0, 1.0)
	var lowland: float = 1.0 - clampf((float(c.centre) - MIN_HEIGHT) / 40.0, 0.0, 1.0)
	return level * 1.0 + lowland * 0.55


## Centre height and the height spread around the footprint, in one pass.
static func _relief(terrain: IslandTerrain, xz: Vector2) -> Dictionary:
	var centre: float = terrain.sample_height(xz)
	var lo: float = centre
	var hi: float = centre
	for i in 8:
		var a: float = TAU * float(i) / 8.0
		var h: float = terrain.sample_height(xz + Vector2(cos(a), sin(a)) * FOOTPRINT)
		lo = minf(lo, h)
		hi = maxf(hi, h)
	return {"centre": centre, "spread": hi - lo}


## Returns {"en": ..., "display": ...}.
##
## The English name is what the village's ID is built from, so it has to be
## stable whatever language the game is being played in — an id that changed
## with the locale would make every save unloadable in the other language.
## The display name goes through the translation table twice, once for the
## culture stem and once for the landform word, so a Russian player gets
## "Фенрайт-Лощина" rather than "Fenrayt Hollow".
static func _name_for(culture: StringName, terrain: IslandTerrain, xz: Vector2,
		centre: float, rng: RandomNumberGenerator) -> Dictionary:
	var stems: Array = CULTURE_STEMS.get(culture, CULTURE_STEMS[&"fenrayt"])
	var stem: String = stems[rng.randi() % stems.size()]
	var words: Array = _landform(terrain, xz, centre)
	var word: String = words[rng.randi() % words.size()]
	return {
		"en": "%s %s" % [stem, word],
		# The join itself is translated: Russian settlement names of this shape
		# take a hyphen, English a space.
		# TranslationServer, not tr(): tr() is an Object method and this is a
		# static function on a RefCounted that is never instanced.
		"display": TranslationServer.translate("%s %s") % [
			TranslationServer.translate(stem), TranslationServer.translate(word)],
	}


## Which family of landform words fits this ground. Measured, not guessed.
static func _landform(terrain: IslandTerrain, xz: Vector2, centre: float) -> Array:
	if centre < COAST_HEIGHT:
		return NAMES_COAST
	if centre > terrain.max_height * 0.34:
		return NAMES_HIGH

	# A hollow is ground that sits below its own surroundings — sampled wider
	# than the footprint, because a village-sized dip is not a valley.
	var around := 0.0
	for i in 6:
		var a: float = TAU * float(i) / 6.0
		around += terrain.sample_height(xz + Vector2(cos(a), sin(a)) * 34.0)
	around /= 6.0
	if around - centre > 4.0:
		return NAMES_HOLLOW

	# Water: the generator's flow map is what carved the rivers, so asking it
	# is the same question the river tracer asked.
	if terrain.generator != null and terrain.generator.has_method("flow_at"):
		var local: Vector3 = terrain.to_local(Vector3(xz.x, 0.0, xz.y))
		if terrain.generator.flow_at(local.x, local.z) > 0.42:
			return NAMES_WATER

	return NAMES_PLAIN
