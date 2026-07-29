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
## Rebalanced when villagers stopped being a stand-in dictionary and became
## real people whose count the economy charges upkeep for. At the old 0.9 a
## single field hand fed eighteen people, so every village sat pinned at its
## storage cap and no shortage could ever occur — the ledger existed but never
## said anything. At 0.22 a village of twenty-five needs roughly six people on
## food to break even, which is about a quarter of its adults: enough that
## losing hands to a storm or a rebuild is felt.
const FOOD_PER_WORKER_PER_SEC: float = 0.22  # per villager in "fishing" or "field"
const WOOD_PER_WORKER_PER_SEC: float = 0.16  # per villager in "woodcutting"
const STONE_PER_HEAD_PER_SEC: float = 0.04   # ambient quarrying/beachcombing, whole population
const FOOD_PER_GATHERING_HOUSE_PER_SEC: float = 0.5

## -- hunting ---------------------------------------------------------------
##
## A hunter is worth more than a field hand, and unlike a field the hillside
## can be emptied. Every so often a village's hunting party actually takes an
## animal out of the real wildlife population, so hunting the same ground every
## day stops paying until it recovers (WildlifeManager.respawn_interval). That
## is the difference between animals and a food button.
const FOOD_PER_HUNTER_PER_SEC: float = 0.34
## How far from the hunting ground game still counts.
const HUNT_RANGE: float = 70.0
## Seconds of hunting work that add up to one animal taken.
const HUNT_SECONDS_PER_KILL: float = 26.0
const WORKYARD_PRODUCTION_BONUS: float = 0.25 # additive, per Workyard, applied to wood+stone
const FOOD_UPKEEP_PER_HEAD_PER_SEC: float = 0.05

## -- warmth and hunger ----------------------------------------------------
##
## Firewood is the second daily need, and the one that makes weather matter to
## people rather than only to the sky. Wood is not just a build material any
## more: a village burns it to stay warm, more of it when the night is cold,
## and a village that runs out is a village whose woodcutters stop being
## optional.
##
## COMFORT_TEMPERATURE is the point above which nothing is burnt at all.
## Weather's baseline is 14 C swinging +/-4 C over the day, minus cloud and
## rain, so a clear noon costs nothing and a wet night costs the most — which
## is the seasonal rhythm the villagers' job choice reads.
const COMFORT_TEMPERATURE_C: float = 15.0
const WOOD_BURN_PER_HEAD_PER_SEC: float = 0.012
## Cold below comfort is scaled by this before it multiplies the burn, so a
## 10 C night burns about 1.4x what a 14 C evening does rather than ten times.
const COLD_TO_BURN_SCALE: float = 0.07
## Night costs more than the same temperature by day: people are indoors, the
## fires are actually lit, and this is what makes a night visibly different in
## the ledger and not only on screen.
const NIGHT_BURN_MULTIPLIER: float = 1.6

## What going without does. Both are per second, applied only while the
## village is actually short, and deliberately small: this is meant to be
## pressure the player can answer with a rite, not a death spiral. A village
## that has been hungry for a minute has lost about 3 devotion and a little
## faith, which is noticeable and recoverable.
const HUNGER_DEVOTION_LOSS_PER_SEC: float = 0.05
const HUNGER_FAITH_LOSS_PER_SEC: float = 0.004
## Being cold is milder than being hungry — you can survive a cold night.
const COLD_DEVOTION_LOSS_PER_SEC: float = 0.02

## Seconds a village must go without before the Voices say anything about it.
## Without this every village narrates a one-frame dip in the stores.
const NEED_REMARK_DELAY: float = 6.0

var _queues: Dictionary = {} # StringName -> Array[ConstructionSite]
var _last_known_devotion: Dictionary = {} # StringName -> float
var _applying_devotion_bonus: bool = false
var _warned_overflow: Dictionary = {} # StringName -> {resource: bool}, one Voices line per village/resource
## StringName -> {"hungry": float, "cold": float}: how long this village has
## been going without, in seconds. Reset the moment the shortage ends.
var _need_time: Dictionary = {}
var _crowd: Node = null
var _wildlife: Node = null
## village_id -> accumulated hunter-seconds not yet spent on an animal.
var _hunt_progress: Dictionary = {}

## Which VillagerCrowd to read job counts from. Left empty, the first one in
## the scene is used, so a scene needs no wiring.
@export var crowd_path: NodePath


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
	# WHO IS ACTUALLY WORKING, not who was authored as working.
	#
	# `Village.jobs` is a hand-written dictionary that nothing updates at
	# runtime — it was the economy demo's stand-in from before there were
	# villagers on the island. The crowd knows what its six hundred people are
	# really doing, so ask it. The dictionary stays as the fallback for the
	# standalone economy demo, which has a village and no crowd.
	var counts := _job_counts(village)
	var fishing: int = counts.fishing
	var field: int = counts.field
	var woodcutting: int = counts.woodcutting
	var hunting: int = counts.hunting

	var structure_bonus := 1.0 + float(_count_building(village, &"workyard")) * WORKYARD_PRODUCTION_BONUS
	if SwiftYardsWonder.is_present(village):
		structure_bonus += SwiftYardsWonder.PRODUCTION_BONUS_MULTIPLIER

	var food_gain := (float(fishing + field) * FOOD_PER_WORKER_PER_SEC
		+ _hunt_yield(village, hunting, delta)
		+ float(_count_building(village, &"gathering_house")) * FOOD_PER_GATHERING_HOUSE_PER_SEC) * delta
	var wood_gain := float(woodcutting) * WOOD_PER_WORKER_PER_SEC * structure_bonus * delta
	var stone_gain := float(village.population) * STONE_PER_HEAD_PER_SEC * structure_bonus * delta
	var food_upkeep := float(village.population) * FOOD_UPKEEP_PER_HEAD_PER_SEC * delta

	# Firewood. Cold below comfort and the night both raise the burn; a warm
	# clear afternoon costs nothing at all.
	var temperature: float = float(Weather.current.get("temperature_c", COMFORT_TEMPERATURE_C))
	var cold: float = maxf(COMFORT_TEMPERATURE_C - temperature, 0.0)
	var burn_rate: float = WOOD_BURN_PER_HEAD_PER_SEC * (1.0 + cold * COLD_TO_BURN_SCALE)
	if bool(Weather.current.get("is_night", false)):
		burn_rate *= NIGHT_BURN_MULTIPLIER
	var wood_burn := float(village.population) * burn_rate * delta

	# Whether the village could actually pay is decided BEFORE the stores are
	# touched: once _apply_delta has clamped a negative delta at zero the
	# shortfall is gone and there is nothing left to notice.
	var had_food := Stockpile.get_amount(village, &"food")
	var had_wood := Stockpile.get_amount(village, &"wood")
	var hungry := had_food + food_gain < food_upkeep
	var freezing := had_wood + wood_gain < wood_burn

	_apply_delta(village, &"food", food_gain - food_upkeep)
	_apply_delta(village, &"wood", wood_gain - wood_burn)
	_apply_delta(village, &"stone", stone_gain)
	_tick_needs(village, delta, hungry, freezing)
	resources_changed.emit(village.id)


## Reads live job counts from the VillagerCrowd, falling back to the authored
## `Village.jobs` dictionary when there is no crowd (the standalone economy
## demo scene).
func _job_counts(village: Village) -> Dictionary:
	var crowd := _resolve_crowd()
	if crowd == null:
		var jobs: Dictionary = village.jobs
		return {
			"fishing": int(jobs.get("fishing", 0)),
			"field": int(jobs.get("field", 0)),
			"woodcutting": int(jobs.get("woodcutting", 0)),
			"hunting": 0,
		}
	return {
		"fishing": crowd.count_job(village.id, VillagerCrowd.Job.FISHING),
		"field": crowd.count_job(village.id, VillagerCrowd.Job.FIELD),
		"woodcutting": crowd.count_job(village.id, VillagerCrowd.Job.WOODCUTTING),
		"hunting": crowd.count_job(village.id, VillagerCrowd.Job.HUNTING),
	}


## What going without costs. Hunger takes devotion and a little faith; cold
## takes devotion only. Both are gentle by design — this is pressure the
## player answers with a rite, not a death spiral they watch happen.
func _tick_needs(village: Village, delta: float, hungry: bool, freezing: bool) -> void:
	var timers: Dictionary = _need_time.get(village.id, {"hungry": 0.0, "cold": 0.0})

	if hungry:
		timers.hungry += delta
		GameState.add_devotion(village.id, -HUNGER_DEVOTION_LOSS_PER_SEC * delta)
		village.faith_fraction = maxf(village.faith_fraction - HUNGER_FAITH_LOSS_PER_SEC * delta, 0.0)
		if timers.hungry >= NEED_REMARK_DELAY and not timers.get("said_hungry", false):
			timers["said_hungry"] = true
			Voices.react(&"village_hungry", {
				"village_id": village.id, "village_name": village.display_name,
			})
	else:
		timers.hungry = 0.0
		timers["said_hungry"] = false

	if freezing:
		timers.cold += delta
		GameState.add_devotion(village.id, -COLD_DEVOTION_LOSS_PER_SEC * delta)
		if timers.cold >= NEED_REMARK_DELAY and not timers.get("said_cold", false):
			timers["said_cold"] = true
			Voices.react(&"village_cold", {
				"village_id": village.id, "village_name": village.display_name,
			})
	else:
		timers.cold = 0.0
		timers["said_cold"] = false

	_need_time[village.id] = timers


## Food per second from this village's hunters — zero if the hillside they
## work is empty of game. Also spends their effort: every
## HUNT_SECONDS_PER_KILL worth of hunting takes one real animal out of the
## population, through the same path a predator's kill takes, so the
## scavengers and the Voices hear about it.
func _hunt_yield(village: Village, hunters: int, delta: float) -> float:
	if hunters <= 0:
		return 0.0
	var crowd := _resolve_crowd()
	var wildlife := _resolve_wildlife()
	if crowd == null or wildlife == null:
		# No wildlife in this scene (the standalone economy demo): hunters are
		# just slower gatherers rather than silently producing nothing.
		return float(hunters) * FOOD_PER_HUNTER_PER_SEC * 0.5
	var ground: Vector2 = crowd.hunting_ground(village.id)
	if wildlife.prey_near(ground, HUNT_RANGE) <= 0:
		return 0.0

	var progress: float = float(_hunt_progress.get(village.id, 0.0)) + float(hunters) * delta
	while progress >= HUNT_SECONDS_PER_KILL:
		progress -= HUNT_SECONDS_PER_KILL
		if not wildlife.take_prey(ground, HUNT_RANGE):
			break
	_hunt_progress[village.id] = progress
	return float(hunters) * FOOD_PER_HUNTER_PER_SEC


func _resolve_wildlife() -> Node:
	if _wildlife != null and is_instance_valid(_wildlife):
		return _wildlife
	_wildlife = _search_wildlife(get_tree().current_scene)
	return _wildlife


func _search_wildlife(n: Node) -> Node:
	if n == null:
		return null
	if n is WildlifeManager:
		return n
	for child in n.get_children():
		var found := _search_wildlife(child)
		if found != null:
			return found
	return null


func _resolve_crowd() -> Node:
	if _crowd != null and is_instance_valid(_crowd):
		return _crowd
	if not crowd_path.is_empty():
		_crowd = get_node_or_null(crowd_path)
		if _crowd != null:
			return _crowd
	var root := get_tree().current_scene
	_crowd = _search_crowd(root)
	return _crowd


func _search_crowd(n: Node) -> Node:
	if n == null:
		return null
	if n is VillagerCrowd:
		return n
	for child in n.get_children():
		var found := _search_crowd(child)
		if found != null:
			return found
	return null


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
