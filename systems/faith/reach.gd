extends Node
## Autoload. Reach = the radius around converted villages where the god can
## touch anything at all (Hand grabs, rites resolve, sigils are even legible
## to the world). Reach grows with total converted population. This node
## also owns per-village, per-method conversion fatigue: hammering a village
## with the same miracle over and over should visibly stop working.

const BASE_REACH_PER_HEAD := 0.6 # meters of radius per convert, tuned against island scale in world/terrain
const FATIGUE_RISE_PER_USE := 0.28
const FATIGUE_DECAY_PER_SECOND := 0.015 # ~65s to fully forget a method if left alone

func _process(delta: float) -> void:
	for village in GameState.villages.values():
		_decay_fatigue(village, delta)

func _decay_fatigue(village: Village, delta: float) -> void:
	for method_id in village.method_fatigue.keys():
		var entry: Dictionary = village.method_fatigue[method_id]
		entry.fatigue = maxf(0.0, entry.fatigue - FATIGUE_DECAY_PER_SECOND * delta)
		village.method_fatigue[method_id] = entry

## Returns 0..1 multiplier applied to a conversion method's effectiveness on
## a given village. 1.0 = fresh (full effect), approaching 0 = "they glance
## up without putting down their tools."
func effectiveness(village_id: StringName, method_id: StringName) -> float:
	var v: Village = GameState.get_village(village_id)
	if v == null:
		return 0.0
	var entry: Dictionary = v.method_fatigue.get(method_id, {"uses": 0, "fatigue": 0.0})
	return 1.0 - entry.fatigue

## Call after resolving a conversion-relevant miracle (fire from clear sky,
## a healed plague, a missionary sermon, the Avatar simply being seen).
func register_use(village_id: StringName, method_id: StringName) -> void:
	var v: Village = GameState.get_village(village_id)
	if v == null:
		return
	var entry: Dictionary = v.method_fatigue.get(method_id, {"uses": 0, "fatigue": 0.0})
	entry.uses += 1
	entry.fatigue = clampf(entry.fatigue + FATIGUE_RISE_PER_USE * (1.0 - entry.fatigue), 0.0, 1.0)
	v.method_fatigue[method_id] = entry

## Total radius, in meters, the god can currently act within. Territory
## rendering (world/terrain/reach_border.gdshader) reads this per village
## rather than drawing any UI overlay, per design brief.
func radius_for_village(village_id: StringName) -> float:
	var v: Village = GameState.get_village(village_id)
	if v == null or v.loyal_to_rival:
		return 0.0
	var converts := v.population * v.faith_fraction
	return 8.0 + converts * BASE_REACH_PER_HEAD

func can_act_at(world_pos: Vector3) -> bool:
	for village in GameState.villages.values():
		if village.loyal_to_rival:
			continue
		var origin := Vector3(village.position_on_island.x, 0.0, village.position_on_island.y)
		if origin.distance_to(Vector3(world_pos.x, 0.0, world_pos.z)) <= radius_for_village(village.id):
			return true
	return false
