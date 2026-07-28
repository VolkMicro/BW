extends Node
class_name VillageEconomy
## Package H — the economy manager. Instantiate this once, anywhere in the
## scene tree (it self-registers against every village GameState already
## knows about, and picks up new ones live via `village_registered`), and
## it drives, for every non-lost village:
##
##   - passive resource production (wood/food/stone) from job assignments
##     and standing buildings, each tick, via Stockpile;
##   - construction queues (pay-up-front, wait build_time_seconds, then the
##     id lands in village.buildings or village.wonders);
##   - the Tithing Stone Wonder's devotion bonus, by listening to
##     GameState.devotion_changed (see `_on_devotion_changed`).
##
## This package owns no scene under world/ or actors/ to attach itself to
## automatically (see docs/systems/economy.md, "Integration"), so for now
## it's wired into systems/economy/economy_demo.tscn as a standalone proof;
## whichever package next wires the real Sanctum/HUD-less build menu should
## add one VillageEconomy node to the live scene tree the same way.
##
## Public API:
##   start_construction(village_id, building_id) -> bool
##   cancel_construction(village_id) -> bool         # refunds half the cost
##   queue_for(village_id) -> Array[ConstructionSite]
##   resource_amount(village_id, resource) -> float
##   resource_capacity(village_id, resource) -> float
##
## Signals:
##   construction_started(village_id, building_id)
##   construction_completed(village_id, building_id)
##   construction_cancelled(village_id, building_id)
##   resources_changed(village_id)

signal construction_started(village_id: StringName, building_id: StringName)
signal construction_completed(village_id: StringName, building_id: StringName)
signal construction_cancelled(village_id: StringName, building_id: StringName)
signal resources_changed(village_id: StringName)

## -- production tuning --------------------------------------------------
const FOOD_PER_WORKER_PER_SEC: float = 0.9   # per villager in "fishing" or "field"
const WOOD_PER_WORKER_PER_SEC: float = 0.7   # per villager in "woodcutting"
const STONE_PER_HEAD_PER_SEC: float = 0.04   # ambient quarrying/beachcombing, whole population
const FOOD_PER_GATHERING_HOUSE_PER_SEC: float = 0.5
const WORKYARD_PRODUCTION_BONUS: float = 0.25 # additive, per Workyard, applied to wood+stone
const FOOD_UPKEEP_PER_HEAD_PER_SEC: float = 0.05

var _queues: Dictionary = {} # StringName -> Array[ConstructionSite]
var _last_known_devotion: Dictionary = {} # StringName -> float
var _applying_devotion_bonus: bool = false
var _warned_overflow: Dictionary = {} # StringName -> {resource: bool}, one Voices line per village/resource


func _ready() -> void:
	GameState.village_registered.connect(_on_village_registered)
	GameState.devotion_changed.connect(_on_devotion_changed)
	for village in GameState.villages.values():
		_on_village_registered(village)


func _on_village_registered(village: Village) -> void:
	if not _queues.has(village.id):
		_queues[village.id] = []
	Stockpile.ensure(village)
	_last_known_devotion[village.id] = village.devotion


func _process(delta: float) -> void:
	for village in GameState.villages.values():
		if village.loyal_to_rival:
			continue
		_tick_production(village, delta)
		_tick_construction(village, delta)


## -- production ----------------------------------------------------------

func _tick_production(village: Village, delta: float) -> void:
	var jobs: Dictionary = village.jobs
	var fishing: int = int(jobs.get("fishing", 0))
	var field: int = int(jobs.get("field", 0))
	var woodcutting: int = int(jobs.get("woodcutting", 0))

	var structure_bonus := 1.0 + float(_count_building(village, &"workyard")) * WORKYARD_PRODUCTION_BONUS
	if SwiftYardsWonder.is_present(village):
		structure_bonus += SwiftYardsWonder.PRODUCTION_BONUS_MULTIPLIER

	var food_gain := (float(fishing + field) * FOOD_PER_WORKER_PER_SEC
		+ float(_count_building(village, &"gathering_house")) * FOOD_PER_GATHERING_HOUSE_PER_SEC) * delta
	var wood_gain := float(woodcutting) * WOOD_PER_WORKER_PER_SEC * structure_bonus * delta
	var stone_gain := float(village.population) * STONE_PER_HEAD_PER_SEC * structure_bonus * delta
	var food_upkeep := float(village.population) * FOOD_UPKEEP_PER_HEAD_PER_SEC * delta

	_apply_delta(village, &"food", food_gain - food_upkeep)
	_apply_delta(village, &"wood", wood_gain)
	_apply_delta(village, &"stone", stone_gain)
	resources_changed.emit(village.id)


func _apply_delta(village: Village, resource: StringName, amount: float) -> void:
	if amount == 0.0:
		return
	var result := Stockpile.add(village, resource, amount)
	if result.get("overflowed", false):
		var warned: Dictionary = _warned_overflow.get(village.id, {})
		if not warned.get(resource, false):
			warned[resource] = true
			_warned_overflow[village.id] = warned
			Voices.react(&"stockpile_overflow", {
				"village_id": village.id,
				"village_name": village.display_name,
				"resource": String(resource),
			})


func _count_building(village: Village, id: StringName) -> int:
	var n := 0
	for b in village.buildings:
		if b == id:
			n += 1
	return n


## -- devotion bonus hook (Tithing Stone Wonder) --------------------------
## GameState.add_devotion() is the foundation's single entry point for
## crediting a village with devotion, and it always emits devotion_changed
## right after updating Village.devotion. We track the last value we saw
## per village so we can compute the delta a caller just added, then, if
## the Tithing Stone Wonder is standing, top it up by
## TithingStoneWonder.DEVOTION_BONUS_MULTIPLIER. The _applying_devotion_bonus
## guard stops our own top-up call from re-triggering itself.
func _on_devotion_changed(village_id: StringName, new_amount: float) -> void:
	if _applying_devotion_bonus:
		_last_known_devotion[village_id] = new_amount
		return
	var previous: float = _last_known_devotion.get(village_id, new_amount)
	var delta := new_amount - previous
	_last_known_devotion[village_id] = new_amount
	if delta <= 0.0:
		return
	var village: Village = GameState.get_village(village_id)
	if not TithingStoneWonder.is_present(village):
		return
	var bonus := delta * TithingStoneWonder.DEVOTION_BONUS_MULTIPLIER
	if bonus <= 0.0:
		return
	_applying_devotion_bonus = true
	GameState.add_devotion(village_id, bonus)
	_applying_devotion_bonus = false
	_last_known_devotion[village_id] = GameState.get_village(village_id).devotion


## -- construction ----------------------------------------------------------

func queue_for(village_id: StringName) -> Array:
	return _queues.get(village_id, [])


func start_construction(village_id: StringName, building_id: StringName) -> bool:
	var village: Village = GameState.get_village(village_id)
	if village == null:
		return false
	var building := BuildingCatalog.get_type(building_id)
	if building == null:
		return false
	if building.has_reached_limit(village):
		return false
	if not Stockpile.spend(village, building.cost):
		return false
	if not _queues.has(village_id):
		_queues[village_id] = []
	var site := ConstructionSite.new(village_id, building)
	_queues[village_id].append(site)
	construction_started.emit(village_id, building_id)
	Voices.react(&"construction_started", {
		"village_id": village_id,
		"village_name": village.display_name,
		"building_id": String(building_id),
		"building_name": building.display_name,
	})
	return true


## Cancels the currently-active (front-of-queue) site for a village and
## refunds half its resource cost. Returns false if nothing is building.
func cancel_construction(village_id: StringName) -> bool:
	var queue: Array = _queues.get(village_id, [])
	if queue.is_empty():
		return false
	var site: ConstructionSite = queue[0]
	queue.remove_at(0)
	var village: Village = GameState.get_village(village_id)
	if village != null:
		var refund := {}
		for resource in site.building.cost.keys():
			refund[resource] = float(site.building.cost[resource]) * 0.5
		for resource in refund.keys():
			Stockpile.add(village, resource, refund[resource])
	construction_cancelled.emit(village_id, site.building.id)
	return true


func _tick_construction(village: Village, delta: float) -> void:
	var queue: Array = _queues.get(village.id, [])
	if queue.is_empty():
		return
	var site: ConstructionSite = queue[0]
	site.elapsed += delta
	if site.is_complete():
		queue.pop_front()
		_finish_construction(village, site.building)


func _finish_construction(village: Village, building: BuildingType) -> void:
	building.on_complete(village)
	if building.is_wonder:
		village.wonders.append(building.id)
	else:
		village.buildings.append(building.id)
	construction_completed.emit(village.id, building.id)
	Voices.react(&"construction_completed" if not building.is_wonder else &"wonder_completed", {
		"village_id": village.id,
		"village_name": village.display_name,
		"building_id": String(building.id),
		"building_name": building.display_name,
	})


## -- read-only helpers for UI/other packages -----------------------------

func resource_amount(village_id: StringName, resource: StringName) -> float:
	return Stockpile.get_amount(GameState.get_village(village_id), resource)


func resource_capacity(village_id: StringName, resource: StringName) -> float:
	return Stockpile.capacity(GameState.get_village(village_id), resource)
