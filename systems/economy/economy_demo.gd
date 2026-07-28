extends Node3D
## Package H demo/validation harness. Registers one small test Village,
## seeds it with job assignments directly (this package doesn't spawn
## Villager actors — that's package G's actors/villagers/villager_demo.gd —
## so job counts are set by hand here to exercise the production formula
## end to end without needing a live crowd), queues three buildings and,
## once the Workyard finishes, a Wonder — proving construction, resource
## spend/production, storage caps, and a Wonder's persistent effect all
## work against the real Stockpile/VillageEconomy code, not a mock.
##
## Not meant to be the real campaign map; world/terrain (package B) and
## world/sanctum (package I) own the actual island and build-menu UI this
## system is meant to eventually sit behind.

const VILLAGE_ID: StringName = &"kettlebrook_economy_demo"

@onready var _economy: VillageEconomy = $VillageEconomy
@onready var _label: Label3D = $StatusLabel


func _ready() -> void:
	_ensure_village()
	var village: Village = GameState.get_village(VILLAGE_ID)
	village.jobs["fishing"] = 3
	village.jobs["field"] = 2
	village.jobs["woodcutting"] = 4
	village.jobs["idle"] = 3

	_economy.construction_completed.connect(_on_construction_completed)
	_economy.start_construction(VILLAGE_ID, &"gathering_house")
	_economy.start_construction(VILLAGE_ID, &"storehouse")
	_economy.start_construction(VILLAGE_ID, &"workyard")


func _process(_delta: float) -> void:
	var village: Village = GameState.get_village(VILLAGE_ID)
	if village == null:
		return
	var stock := Stockpile.snapshot(village)
	var queue: Array = _economy.queue_for(VILLAGE_ID)
	var building_line := "(nothing queued)"
	if not queue.is_empty():
		var site: ConstructionSite = queue[0]
		building_line = "%s — %d%%" % [site.building.display_name, int(site.progress() * 100.0)]

	var wonders_text := ""
	for i in range(village.wonders.size()):
		if i > 0:
			wonders_text += ", "
		wonders_text += String(village.wonders[i])
	if wonders_text == "":
		wonders_text = "none yet"

	_label.text = "Kettlebrook\nWood %d/%d   Food %d/%d   Stone %d/%d\nBuilding: %s\nWonders: %s" % [
		int(stock.get(&"wood", 0.0)), int(_economy.resource_capacity(VILLAGE_ID, &"wood")),
		int(stock.get(&"food", 0.0)), int(_economy.resource_capacity(VILLAGE_ID, &"food")),
		int(stock.get(&"stone", 0.0)), int(_economy.resource_capacity(VILLAGE_ID, &"stone")),
		building_line,
		wonders_text,
	]


func _ensure_village() -> void:
	if GameState.get_village(VILLAGE_ID) != null:
		return
	var v := Village.new()
	v.id = VILLAGE_ID
	v.display_name = "Kettlebrook"
	v.culture_id = &"sankiln"
	v.position_on_island = Vector2.ZERO
	v.population = 12
	v.children = 3
	v.faith_fraction = 0.3
	GameState.register_village(v)


## Once the Workyard finishes, queue the Swift Yards Wonder on top of it so
## the demo also proves the Wonder-tier construction path and its
## production-multiplier effect, not just the three base building types.
func _on_construction_completed(village_id: StringName, building_id: StringName) -> void:
	if village_id != VILLAGE_ID:
		return
	if building_id == &"workyard":
		_economy.start_construction(VILLAGE_ID, &"wonder_swift_yards")
