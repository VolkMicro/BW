extends RefCounted
class_name SaveGame
## Writing an island down and reading it back.
##
## ---------------------------------------------------------------------------
## WHAT IS SAVED, AND WHY SO LITTLE
## ---------------------------------------------------------------------------
## A game here runs for tens of minutes, so losing it to a closed window is
## not acceptable. But almost nothing in this world needs to be written down,
## because almost nothing in it is authored:
##
##   * the island is a pure function of `island_seed` and the generation
##     parameters, and it is already cached to disk by hash
##     (island_generator.gd), so saving a heightmap would be storing a
##     megabyte to avoid recomputing something that takes 538 ms;
##   * the villages' POSITIONS and NAMES are a pure function of the same seed
##     through SettlementPlanner, for the same reason;
##   * six hundred villagers are mid-errand agents whose exact footfalls
##     nobody could tell from a fresh scatter a second later.
##
## What genuinely cannot be recomputed is what the PLAYER changed: who
## believes, who is hungry, what Louhi holds and how hard, what the god has
## been called, and which rites they have learned. That is this file.
##
## ---------------------------------------------------------------------------
## FORMAT
## ---------------------------------------------------------------------------
## JSON, not `ResourceSaver`. A `.tres` of a Village array would be smaller to
## write and would also be a script-bearing resource loaded from user://,
## which is a way to hand arbitrary code execution to anything that can drop a
## file in a user directory. JSON parses to plain dictionaries and cannot do
## that.
##
## `version` is checked on load and a mismatch is refused rather than
## best-guessed: a save that half-applies is worse than one that says no.

const SAVE_PATH := "user://tithe_and_terror.save.json"
const VERSION := 1


static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## Writes the current world. Returns true on success.
static func save() -> bool:
	var villages: Array = []
	for value in GameState.villages.values():
		var v: Village = value
		villages.append({
			"id": String(v.id),
			"faith_fraction": v.faith_fraction,
			"devotion": v.devotion,
			"loyal_to_rival": v.loyal_to_rival,
			"grip": Reclaim.grip_of(v),
			"population": v.population,
			"children": v.children,
			"sanctum_built": v.sanctum_built,
			"sanctum_hp": v.sanctum_hp,
			"food": Stockpile.get_amount(v, &"food"),
			"wood": Stockpile.get_amount(v, &"wood"),
			"stone": Stockpile.get_amount(v, &"stone"),
			"buildings": _to_strings(v.buildings),
			"wonders": _to_strings(v.wonders),
		})

	var data := {
		"version": VERSION,
		"naklon": Naklon.value,
		"epithets": GameState.epithets.duplicate(),
		"relics_held": _to_strings(GameState.relics_held),
		"scrolls_known": _to_strings(GameState.scrolls_known),
		"avatar_species": String(GameState.avatar_species),
		"villages": villages,
	}

	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("SaveGame: could not open %s for writing (%d)"
			% [SAVE_PATH, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true


## Applies a save over the world the scene has already built.
##
## Deliberately NOT a scene reload. The island, the villages' positions and
## the crowd all come back identically from the same seed, so the load path
## is: let the scene boot normally, then overwrite the handful of numbers the
## player changed. That also means a save cannot leave the game in a state the
## scene could not have produced on its own.
##
## Returns true if a save was found, was the right version, and was applied.
static func load_into_world() -> bool:
	if not has_save():
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var raw := f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SaveGame: %s is not readable as a save." % SAVE_PATH)
		return false
	var data: Dictionary = parsed
	if int(data.get("version", -1)) != VERSION:
		# Refused rather than best-guessed. A save that half-applies leaves a
		# world that looks fine and is quietly wrong, which is much harder to
		# notice than a load that says no.
		push_warning("SaveGame: save is version %s, this build reads %d. Not loading."
			% [str(data.get("version", "?")), VERSION])
		return false

	Naklon.value = float(data.get("naklon", Naklon.value))
	GameState.epithets = _to_string_array(data.get("epithets", []))
	GameState.relics_held = _to_stringname_array(data.get("relics_held", []))
	GameState.scrolls_known = _to_stringname_array(data.get("scrolls_known", []))
	var species: String = str(data.get("avatar_species", ""))
	if not species.is_empty():
		GameState.avatar_species = StringName(species)

	for entry_value in data.get("villages", []):
		var entry: Dictionary = entry_value
		var v: Village = GameState.get_village(StringName(str(entry.get("id", ""))))
		if v == null:
			# A village in the save that this island did not generate. Happens
			# if the seed or the planner changed under the save; skip it rather
			# than inventing a settlement with no ground under it.
			continue
		v.population = int(entry.get("population", v.population))
		v.children = int(entry.get("children", v.children))
		v.sanctum_built = bool(entry.get("sanctum_built", v.sanctum_built))
		v.sanctum_hp = float(entry.get("sanctum_hp", v.sanctum_hp))
		v.buildings = _to_stringname_array(entry.get("buildings", []))
		v.wonders = _to_stringname_array(entry.get("wonders", []))
		v.loyal_to_rival = bool(entry.get("loyal_to_rival", false))
		if v.loyal_to_rival:
			v.set_meta(Reclaim.META_KEY, float(entry.get("grip", 1.0)))
		else:
			v.remove_meta(Reclaim.META_KEY)

		# Stores are set absolutely, not added: Stockpile.add clamps to
		# capacity, and a village registered with a 55% opening stock would
		# otherwise keep it on top of whatever the save says.
		var store := Stockpile.ensure(v)
		store[&"food"] = float(entry.get("food", 0.0))
		store[&"wood"] = float(entry.get("wood", 0.0))
		store[&"stone"] = float(entry.get("stone", 0.0))
		v.set_meta(Stockpile.META_KEY, store)

		# Faith and devotion go through GameState so every listener — the Reach
		# ring, the campaign, the Sanctum skin, the markers — reacts the way it
		# would if the change had happened in play.
		v.devotion = 0.0
		GameState.add_devotion(v.id, float(entry.get("devotion", 0.0)))
		GameState.set_faith_fraction(v.id, float(entry.get("faith_fraction", 0.0)))

	return true


static func delete() -> void:
	if has_save():
		DirAccess.remove_absolute(SAVE_PATH)


static func _to_strings(items) -> Array:
	var out: Array = []
	for i in items:
		out.append(String(i))
	return out


static func _to_string_array(items) -> Array[String]:
	var out: Array[String] = []
	for i in items:
		out.append(str(i))
	return out


static func _to_stringname_array(items) -> Array[StringName]:
	var out: Array[StringName] = []
	for i in items:
		out.append(StringName(str(i)))
	return out
