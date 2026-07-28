extends Node3D
## Package G demo harness. Registers three small test Village resources (one
## per culture, so the capsule tint variety actually shows up in one frame),
## spawns ~12 villagers total, and drops one CallingStone in the middle of
## them. Not meant to be the real campaign map — world/terrain (package B)
## owns real island geometry; this is a self-contained proving ground for
## the villager AI and the Calling Stone mechanic, run directly or embedded.

const VILLAGER_SCENE: PackedScene = preload("res://actors/villagers/villager.tscn")
const CALLING_STONE_SCENE: PackedScene = preload("res://actors/villagers/calling_stone.tscn")

const DEMO_VILLAGES := [
	{"id": &"aldenmire_fenrayt", "culture": &"fenrayt", "display": "Aldenmire", "pos": Vector2(-9.0, -9.0), "population": 4},
	{"id": &"ashterrace_sankiln", "culture": &"sankiln", "display": "Ashterrace", "pos": Vector2(9.0, -9.0), "population": 4},
	{"id": &"driftholm_raimborn", "culture": &"raimborn", "display": "Driftholm", "pos": Vector2(0.0, 11.0), "population": 4},
]

@onready var _villagers_root: Node3D = $Villagers


func _ready() -> void:
	var village_ids: Array[StringName] = []
	for entry in DEMO_VILLAGES:
		var id: StringName = entry["id"]
		village_ids.append(id)
		_ensure_village(entry)
		_spawn_villagers(id, entry["population"])

	var stone: CallingStone = CALLING_STONE_SCENE.instantiate()
	stone.village_ids = village_ids
	stone.position = Vector3(0.0, 0.0, 0.0)
	add_child(stone)
	# Preset the dial partway up so a screenshot taken moments after load
	# already shows villagers praying, not just an idle tableau. Drag the
	# dial (left-click + vertical mouse drag on it) to change this live.
	stone.set_target_ratio(0.4)


func _ensure_village(entry: Dictionary) -> void:
	var id: StringName = entry["id"]
	if GameState.get_village(id) != null:
		return
	var v := Village.new()
	v.id = id
	v.display_name = entry["display"]
	v.culture_id = entry["culture"]
	v.position_on_island = entry["pos"]
	v.population = entry["population"]
	v.children = 1
	v.faith_fraction = 0.15
	GameState.register_village(v)


func _spawn_villagers(village_id: StringName, count: int) -> void:
	var village: Village = GameState.get_village(village_id)
	if village == null:
		return
	var base := Vector3(village.position_on_island.x, 0.0, village.position_on_island.y)
	for i in range(count):
		var villager: Villager = VILLAGER_SCENE.instantiate()
		villager.village_id = village_id
		villager.global_position = base + Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0))
		_villagers_root.add_child(villager)
