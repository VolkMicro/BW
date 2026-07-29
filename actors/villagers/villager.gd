extends CharacterBody3D
class_name Villager
## Package G — a single mortal. Utility-AI-lite state machine: works a job,
## pairs up and raises children, or walks to a Calling Stone and prays.
## Reads/writes its owning Village resource's `jobs` Dictionary (core/village.gd)
## so population bookkeeping never drifts, and integrates with
## systems/faith/reach.gd (effectiveness/register_use) and systems/voices/voices.gd
## (Voices.react) for the fatigue/miracle-fatigue and commentary loops.
##
## Public API other packages can rely on:
##   villager.village_id, villager.culture_id, villager.current_state (State)
##   villager.start_praying(stone: CallingStone) -> void
##   villager.stop_praying() -> void
##   villager.force_praying_while_collapsed() -> void   (called only by CallingStone)
##   villager.prayer_willingness() -> float             (read by CallingStone)
##   villager.current_alert() -> Alert
##   villager.job_scores() -> Dictionary                (debug/inspection)
## Group membership: every live villager is in group &"villager".
##
## --- 2nd pass: villagers that actually think ------------------------------
## Three staggered per-villager timers replace what used to be a fixed job
## assignment plus a "least crowded bucket wins" idle reconsider:
##
##   _utility_timer (4.5-7.0s, random phase)  full job re-score against real
##       world state: stockpile levels (systems/economy/stockpile.gd's meta
##       convention, read-only), Village.jobs crowding, children/population
##       ratio, Weather.current harshness, Village.sanctum_hp, faith_fraction
##       and Naklon. See _score_jobs().
##   _sense_timer (~0.4s, random phase)       one distance check each to the
##       Hand and the Avatar; drives fear/avoidance steering and flinching.
##   _alert_timer (event-driven)              a transient reaction to a real
##       event (storm, Sanctum damaged/destroyed, a village lost, Naklon
##       crossing a pole) that moves the villager somewhere and changes how
##       they stand — not just a variable being set.
##
## Nothing here adds a NavigationAgent3D, a raycast, or a pathfinding query.
## Per-frame cost per villager is three float subtractions and (only when a
## threat is actually near) one extra Vector3 add + normalize. See
## docs/systems/villagers.md "Per-frame cost".

enum State {
	IDLE,
	FISHING,
	FIELD,
	WOODCUTTING,
	BUILDING,
	FAMILY,
	PRAYING,
	COLLAPSED,
	DEAD,
}

## Transient behavioural reactions, layered *over* State rather than added to
## it — deliberately, so actors/villagers/calling_stone.gd's priority buckets
## and core/village.gd's jobs-sum invariant both keep working untouched.
enum Alert {
	NONE,
	SHELTER,  ## storm broke: get off the water/fields, huddle at the village
	RALLY,    ## Sanctum damaged: drop everything, take the building job, run to it
	GATHER,   ## something happened nearby: crowd toward our own Sanctum
	FLEE,     ## Sanctum destroyed: scatter away from it
	MOURN,    ## our village is lost: kneel where we stand
	DREAD,    ## the god turned cruel: cower, keep away from the Hand
}

## Job-bucket keys that actually exist on Village.jobs. PRAYING/COLLAPSED are
## deliberately folded into the "idle" bucket (see docs/systems/villagers.md
## "Job-bucket mapping") since core/village.gd's jobs Dictionary has no
## dedicated "praying" key and we cannot add one to a foundation file.
const JOB_KEYS: Array[StringName] = [&"fishing", &"field", &"woodcutting", &"building", &"family"]

const STATE_TO_JOB_KEY := {
	State.FISHING: &"fishing",
	State.FIELD: &"field",
	State.WOODCUTTING: &"woodcutting",
	State.BUILDING: &"building",
	State.FAMILY: &"family",
	State.IDLE: &"idle",
}

# --- Tuning constants -------------------------------------------------------
const GRAVITY := 9.8
const WALK_SPEED := 2.2
const ARRIVE_EPSILON := 0.2
const WANDER_MIN := 3.5
const WANDER_MAX := 7.5
const WANDER_RADIUS := 2.4
const IDLE_RECONSIDER_TIME := 5.0

const PRAYER_FATIGUE_RISE_PER_SEC := 0.045      # ~22s of kneeling to hit 1.0
const FATIGUE_RECOVERY_PER_SEC := 0.03          # recovers slower than it rises
const COLLAPSE_RECOVERY_FATIGUE_BONUS := 1.5    # lying down recovers a bit faster than idling
const COLLAPSE_FATIGUE_THRESHOLD := 0.7
const COLLAPSE_CHANCE_PER_SEC_AT_MAX := 0.35
const COLLAPSE_RECOVERY_TIME := 14.0
const DEATH_CHANCE_ON_FORCED_PRAYER := 0.18

const PRAYER_TICK_INTERVAL := 2.5
const DEVOTION_RATE_PRAYING := 0.6     # devotion/sec at full Reach effectiveness
const DEVOTION_RATE_WORKING := 0.08    # ambient faith trickle while laboring
const AMBIENT_TICK_INTERVAL := 4.0

const GESTATION_TIME := 20.0
const MATURATION_TIME := 40.0
const FAMILY_COOLDOWN := 30.0
const FAMILY_PAIR_RADIUS := 6.0

# --- Utility-AI tuning ------------------------------------------------------
## Personal re-evaluation window. Each villager rolls its own interval inside
## this range AND starts with a random phase offset (see _ready), so 15
## villagers spread ~15 job re-scores over ~6 seconds instead of all doing it
## on the same frame, and they never switch jobs in lockstep.
const UTILITY_INTERVAL_MIN := 4.5
const UTILITY_INTERVAL_MAX := 7.0
## A new job must beat the current one by this much before anyone actually
## moves — hysteresis, so a village doesn't oscillate between two near-equal
## options every few seconds.
const UTILITY_SWITCH_MARGIN := 0.35
const UTILITY_JITTER := 0.12          # per-evaluation noise: breaks ties differently per villager
const CROWDING_WEIGHT := 1.6          # how hard an already-crowded job bucket is penalised
const FOOD_COMFORT_FRACTION := 0.5    # stores above half the cap read as "we have enough"
const SUPPLY_COMFORT_FRACTION := 0.4
const CHILD_COMFORT_RATIO := 0.35     # children per head above this and nobody feels the pull

# --- Senses / demeanour -----------------------------------------------------
const SENSE_INTERVAL := 0.4           # how often one villager checks the Hand/Avatar distance
const FEAR_RADIUS_CRUEL := 10.0
const FEAR_RADIUS_NEUTRAL := 5.5
const FEAR_RADIUS_MERCIFUL := 2.0     # under mercy they barely mind the Hand at all
const AVOID_STRENGTH := 1.3           # weight of the away-from-threat steering blend
const FLINCH_TIME := 1.1
const BACK_OFF_DISTANCE := 7.0

## Shared, class-level lookups: all villagers reuse one resolved Hand/Avatar
## reference and one village_id -> Sanctum map instead of each searching the
## tree. Refreshed at most this often, across the whole population.
const SHARED_THREAT_LOOKUP_MSEC := 5000
const SHARED_SANCTUM_SCAN_MSEC := 8000

# --- Alert durations --------------------------------------------------------
const SHELTER_TIME := 14.0
const RALLY_TIME := 12.0
const GATHER_TIME := 9.0
const FLEE_TIME := 7.0
const MOURN_TIME := 12.0
const DREAD_TIME := 6.0
const FLEE_DISTANCE := 16.0
const GATHER_RING_RADIUS := 4.0

const SPEED_SCALE_CRUEL := 1.15       # skittish
const SPEED_SCALE_MERCIFUL := 0.92    # unhurried
const SPEED_SCALE_SHELTER := 1.3
const SPEED_SCALE_RALLY := 1.35
const SPEED_SCALE_FLEE := 1.6
const SPEED_SCALE_DREAD := 1.25

const JOB_OFFSETS := {
	&"fishing": Vector3(7.0, 0.0, -5.0),
	&"field": Vector3(-7.0, 0.0, 6.0),
	&"woodcutting": Vector3(-9.0, 0.0, -7.0),
	&"building": Vector3(4.0, 0.0, 8.0),
	&"family": Vector3(0.0, 0.0, -1.5),
	&"idle": Vector3(0.0, 0.0, 3.0),
}

# --- Config ------------------------------------------------------------------
@export var village_id: StringName = &""
@export var initial_job: StringName = &"" # empty = pick randomly at spawn
@export var show_debug_label: bool = true

# --- Runtime state -------------------------------------------------------------
var culture_id: StringName = &""
var current_state: State = State.IDLE
var current_job: StringName = &"idle" # which Village.jobs bucket this villager currently occupies
var target_position: Vector3 = Vector3.ZERO
var prayer_fatigue: float = 0.0:
	set(v):
		prayer_fatigue = clampf(v, 0.0, 1.0)
var calling_stone_ref: CallingStone = null

var partner: Villager = null
var _is_family_leader: bool = false
var gestation_timer: float = 0.0
var family_cooldown_timer: float = 0.0
var _maturation_queue: Array[float] = []

var collapse_timer: float = 0.0
var _wander_timer: float = 0.0
var _prayer_tick_timer: float = 0.0
var _ambient_tick_timer: float = 0.0
var _idle_reconsider_timer: float = 0.0

# --- 2nd-pass AI runtime ----------------------------------------------------
var _utility_timer: float = 0.0
var _sense_timer: float = 0.0
var _alert: Alert = Alert.NONE
var _alert_timer: float = 0.0
var _alert_point: Vector3 = Vector3.ZERO
var _ring_angle: float = 0.0          # stable personal angle, so a gathered crowd forms a ring
var _demeanour: int = 0               # -1 merciful, 0 neutral, +1 cruel (mirrors Naklon's pole)
var _speed_scale: float = 1.0
var _avoid_vector: Vector3 = Vector3.ZERO
var _flinch_timer: float = 0.0
var _last_threat_point: Vector3 = Vector3.ZERO
var _has_threat_point: bool = false
var _weather_harshness: float = 0.0   # 0..1, cached from the last Weather.weather_changed
var _weather_severity: int = 0        # 0 calm / 1 rough / 2 storm — only transitions cause reactions
var _willingness: float = 0.5         # cached prayer willingness, read by CallingStone
var _last_scores: Dictionary = {}
var _sanctum_node: Node = null

static var _shared_hand: Node3D = null
static var _shared_avatar: Node3D = null
static var _shared_threat_msec: int = -1000000
static var _shared_sanctums: Dictionary = {}
static var _shared_sanctum_msec: int = -1000000

const VILLAGER_SCENE: PackedScene = preload("res://actors/villagers/villager.tscn")

@onready var _body_mesh: MeshInstance3D = $Body
@onready var _head_mesh: MeshInstance3D = $Body/Head
@onready var _label: Label3D = $DebugLabel


func _ready() -> void:
	add_to_group(&"villager")
	target_position = global_position
	var village: Village = GameState.get_village(village_id)
	if village == null:
		push_warning("Villager spawned with unknown village_id: %s" % village_id)
		_label.visible = false
		return
	culture_id = village.culture_id
	_apply_culture_tint()
	if initial_job == &"":
		initial_job = JOB_KEYS.pick_random()
	_assign_job(initial_job, true)
	_pick_wander_target()
	_label.visible = show_debug_label

	# Staggered phases: every timer starts at a random point in its own cycle
	# so the population's thinking is spread across frames from the first
	# second, not synchronised by a shared spawn moment.
	_ring_angle = randf() * TAU
	_utility_timer = randf_range(0.4, UTILITY_INTERVAL_MAX)
	_sense_timer = randf_range(0.0, SENSE_INTERVAL)
	_demeanour = _pole_of_naklon()
	_refresh_speed_scale()
	_connect_world_signals()
	_read_weather_now()


func _apply_culture_tint() -> void:
	var culture: Culture = GameState.cultures.get(culture_id, null)
	var primary := Color.GRAY
	var accent := Color.WHITE
	if culture:
		primary = culture.color_primary
		accent = culture.color_accent
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = primary
	body_mat.roughness = 0.85
	_body_mesh.material_override = body_mat
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = accent
	head_mat.roughness = 0.6
	_head_mesh.material_override = head_mat


# ---------------------------------------------------------------------------
# World signal wiring — real events, real reactions.
#
# Every connection here is to a signal that already existed before this pass:
# GameState.village_lost, Weather.weather_changed, Naklon.pole_crossed
# (all autoloads), plus the owning Sanctum's sanctum_damaged /
# sanctum_destroyed once one can be found in the tree. Connections to
# autoload signals are dropped automatically by the engine when this node is
# freed, so _die()/queue_free() needs no extra teardown.
# ---------------------------------------------------------------------------
func _connect_world_signals() -> void:
	if not GameState.village_lost.is_connected(_on_village_lost):
		GameState.village_lost.connect(_on_village_lost)
	if not Weather.weather_changed.is_connected(_on_weather_changed):
		Weather.weather_changed.connect(_on_weather_changed)
	if not Naklon.pole_crossed.is_connected(_on_pole_crossed):
		Naklon.pole_crossed.connect(_on_pole_crossed)
	_try_bind_sanctum()


## Finds this villager's own Sanctum (if one exists in the scene at all — the
## standalone village_demo.tscn has none) and subscribes to its damage
## signals. Duck-typed on the two signal names rather than on the Sanctum
## class so this package keeps no hard parse-time dependency on package I.
func _try_bind_sanctum() -> void:
	if is_instance_valid(_sanctum_node):
		return
	_sanctum_node = _resolve_sanctum(get_tree(), village_id)
	if _sanctum_node == null:
		return
	if not _sanctum_node.is_connected(&"sanctum_damaged", _on_sanctum_damaged):
		_sanctum_node.connect(&"sanctum_damaged", _on_sanctum_damaged)
	if not _sanctum_node.is_connected(&"sanctum_destroyed", _on_sanctum_destroyed):
		_sanctum_node.connect(&"sanctum_destroyed", _on_sanctum_destroyed)


static func _resolve_sanctum(tree: SceneTree, id: StringName) -> Node:
	if id == &"" or tree == null:
		return null
	var cached: Node = _shared_sanctums.get(id, null)
	if is_instance_valid(cached):
		return cached
	var now := Time.get_ticks_msec()
	if now - _shared_sanctum_msec < SHARED_SANCTUM_SCAN_MSEC:
		return null
	_shared_sanctum_msec = now
	_shared_sanctums.clear()
	_collect_sanctums(tree.root)
	var found: Node = _shared_sanctums.get(id, null)
	return found if is_instance_valid(found) else null


## One shared tree walk, at most once per SHARED_SANCTUM_SCAN_MSEC across the
## whole villager population, and only while some villager still has no
## Sanctum bound. Not per villager, not per frame.
static func _collect_sanctums(node: Node) -> void:
	if node.has_signal(&"sanctum_damaged") and node.has_signal(&"sanctum_destroyed"):
		var raw: Variant = node.get(&"village_id")
		if raw != null:
			var vid := StringName(str(raw))
			if vid != &"":
				_shared_sanctums[vid] = node
	for child in node.get_children():
		_collect_sanctums(child)


static func _refresh_shared_threats(tree: SceneTree) -> void:
	if tree == null:
		return
	var now := Time.get_ticks_msec()
	if now - _shared_threat_msec < SHARED_THREAT_LOOKUP_MSEC:
		return
	_shared_threat_msec = now
	if not is_instance_valid(_shared_avatar):
		_shared_avatar = tree.get_first_node_in_group(&"avatar") as Node3D
	if not is_instance_valid(_shared_hand):
		var hand_node: Node = tree.get_first_node_in_group(&"hand")
		if hand_node == null and tree.current_scene != null:
			hand_node = tree.current_scene.find_child("Hand", true, false)
		_shared_hand = hand_node as Node3D


# ---------------------------------------------------------------------------
# Event reactions. Each one MOVES the villager and/or changes what they are
# doing — none of them merely sets a flag.
# ---------------------------------------------------------------------------
func _on_weather_changed(state: Dictionary) -> void:
	if current_state == State.DEAD:
		return
	_weather_harshness = clampf(maxf(
		float(state.get("storm_intensity", 0.0)),
		float(state.get("precipitation", 0.0)) * 0.7), 0.0, 1.0)
	var severity := 0
	if bool(state.get("is_storm", false)) or _weather_harshness > 0.55:
		severity = 2
	elif _weather_harshness > 0.25:
		severity = 1
	if severity == _weather_severity:
		return # Weather re-emits every 1.5s; only a real change costs anything
	var rose := severity > _weather_severity
	_weather_severity = severity
	if severity == 2 and rose and _can_react():
		# Off the water, off the fields, back to the huts — and re-score jobs
		# immediately, where fishing/field now carry a heavy storm penalty.
		_begin_alert(Alert.SHELTER, SHELTER_TIME, _village_center())
		_evaluate_jobs(true)
	elif severity == 0 and _alert == Alert.SHELTER:
		_alert_timer = minf(_alert_timer, 0.75) # the weather broke; drift back to work


func _read_weather_now() -> void:
	# Weather is an autoload that is already running before this villager
	# spawned, so its last emit is missed. Sample it once at spawn instead of
	# waiting up to 1.5s for the next tick.
	_weather_harshness = clampf(maxf(
		float(Weather.current.get("storm_intensity", 0.0)),
		float(Weather.current.get("precipitation", 0.0)) * 0.7), 0.0, 1.0)
	if bool(Weather.current.get("is_storm", false)) or _weather_harshness > 0.55:
		_weather_severity = 2
	elif _weather_harshness > 0.25:
		_weather_severity = 1


func _on_sanctum_damaged(vid: StringName, _new_hp: float, _max_hp: float) -> void:
	if vid != village_id or not _can_react():
		return
	if current_job != &"building":
		_assign_job(&"building")
	_begin_alert(Alert.RALLY, RALLY_TIME, _sanctum_position())


func _on_sanctum_destroyed(vid: StringName) -> void:
	if vid != village_id or not _can_react(true):
		return
	_break_off_prayer()
	_release_job_bucket_to_idle()
	current_state = State.IDLE
	_begin_alert(Alert.FLEE, FLEE_TIME, _sanctum_position())


func _on_village_lost(vid: StringName) -> void:
	if vid == village_id:
		if not _can_react(true):
			return
		_break_off_prayer()
		_release_job_bucket_to_idle()
		current_state = State.IDLE
		_begin_alert(Alert.MOURN, MOURN_TIME, global_position)
		return
	# Someone else's village went dark. Crowd toward our own Sanctum.
	if _can_react():
		_begin_alert(Alert.GATHER, GATHER_TIME, _sanctum_position())


func _on_pole_crossed(pole: int) -> void:
	_demeanour = pole
	_refresh_speed_scale()
	if not _can_react():
		return
	if pole > 0:
		_begin_alert(Alert.DREAD, DREAD_TIME, _threat_or_center())
	elif pole < 0:
		_begin_alert(Alert.GATHER, GATHER_TIME, _sanctum_position())
	elif _alert == Alert.DREAD or _alert == Alert.GATHER:
		_alert_timer = minf(_alert_timer, 0.75)
	_evaluate_jobs(true)


## COLLAPSED villagers are owned by the fatigue loop and never react to
## anything — they are face-down. PRAYING villagers are owned by the Calling
## Stone, so ordinary events (a storm, a Naklon pole crossing, a dent in the
## Sanctum wall) do NOT pull them off their knees. Only a `hard` event does:
## the Sanctum actually falling, or their own village being lost. Those two
## break prayer outright (see _break_off_prayer) — a worshipper whose temple
## just collapsed on top of them does not keep kneeling politely.
func _can_react(hard: bool = false) -> bool:
	if current_state == State.DEAD or current_state == State.COLLAPSED:
		return false
	if current_state == State.PRAYING:
		return hard
	return true


func _break_off_prayer() -> void:
	if current_state == State.PRAYING:
		stop_praying()


# ---------------------------------------------------------------------------
# Alerts
# ---------------------------------------------------------------------------
func _begin_alert(kind: Alert, duration: float, point: Vector3) -> void:
	_alert = kind
	_alert_timer = duration
	_alert_point = point
	_refresh_speed_scale()
	_apply_alert_target()
	_update_posture()


func _apply_alert_target() -> void:
	var ring := Vector3(cos(_ring_angle), 0.0, sin(_ring_angle))
	match _alert:
		Alert.SHELTER:
			target_position = _alert_point + ring * randf_range(1.5, 3.0)
		Alert.RALLY:
			target_position = _alert_point + ring * GATHER_RING_RADIUS
		Alert.GATHER:
			target_position = _alert_point + ring * (GATHER_RING_RADIUS + 1.5)
		Alert.FLEE:
			var away := global_position - _alert_point
			away.y = 0.0
			if away.length() < 0.5:
				away = ring
			target_position = global_position + away.normalized() * FLEE_DISTANCE
		Alert.MOURN:
			target_position = global_position
		Alert.DREAD:
			var out := global_position - _alert_point
			out.y = 0.0
			if out.length() < 0.5:
				out = ring
			target_position = global_position + out.normalized() * BACK_OFF_DISTANCE
		_:
			pass


func _tick_alert(delta: float) -> void:
	if _alert == Alert.NONE:
		return
	_alert_timer -= delta
	if _alert_timer > 0.0:
		return
	var was := _alert
	_alert = Alert.NONE
	_refresh_speed_scale()
	_update_posture()
	if was == Alert.FLEE or was == Alert.SHELTER or was == Alert.MOURN:
		_evaluate_jobs(true) # after the panic, take stock of what the village needs
	_pick_wander_target()


func _refresh_speed_scale() -> void:
	var s := 1.0
	if _demeanour > 0:
		s = SPEED_SCALE_CRUEL
	elif _demeanour < 0:
		s = SPEED_SCALE_MERCIFUL
	match _alert:
		Alert.SHELTER: s = maxf(s, SPEED_SCALE_SHELTER)
		Alert.RALLY: s = maxf(s, SPEED_SCALE_RALLY)
		Alert.FLEE: s = maxf(s, SPEED_SCALE_FLEE)
		Alert.DREAD: s = maxf(s, SPEED_SCALE_DREAD)
		Alert.GATHER: s = maxf(s, 1.1)
		Alert.MOURN: s = 0.0
		_: pass
	_speed_scale = s


# ---------------------------------------------------------------------------
# Senses — one distance check each to the Hand and the Avatar, every
# SENSE_INTERVAL (0.4s), phase-offset per villager. No raycasts, no physics
# queries, no navigation.
# ---------------------------------------------------------------------------
func _tick_senses(delta: float) -> void:
	if _flinch_timer > 0.0:
		_flinch_timer -= delta
		if _flinch_timer <= 0.0:
			_update_posture()
	_sense_timer -= delta
	if _sense_timer > 0.0:
		return
	_sense_timer = SENSE_INTERVAL
	_refresh_shared_threats(get_tree())
	var radius := _fear_radius()
	var push := Vector3.ZERO
	var nearest_sq := INF
	var nearest_point := Vector3.ZERO
	var threats: Array[Node3D] = [_shared_hand, _shared_avatar]
	for threat: Node3D in threats:
		if not is_instance_valid(threat):
			continue
		var to_me: Vector3 = global_position - threat.global_position
		to_me.y = 0.0
		var d_sq: float = to_me.length_squared()
		if d_sq < nearest_sq:
			nearest_sq = d_sq
			nearest_point = threat.global_position
		if d_sq > radius * radius or d_sq < 0.0001:
			continue
		push += to_me.normalized() * (1.0 - sqrt(d_sq) / radius)
	if nearest_sq < INF:
		_last_threat_point = nearest_point
		_has_threat_point = true
	if push == Vector3.ZERO:
		_avoid_vector = Vector3.ZERO
		return
	_avoid_vector = push.normalized() * AVOID_STRENGTH
	if _demeanour <= 0:
		return
	# Under a cruel god this is not just a steering nudge: they actually back
	# away and flinch.
	if _flinch_timer <= 0.0 and _alert != Alert.MOURN and _can_react():
		_flinch_timer = FLINCH_TIME
		_update_posture()
	if _alert == Alert.NONE and _can_react():
		target_position = global_position + _avoid_vector.normalized() * BACK_OFF_DISTANCE


func _fear_radius() -> float:
	if _demeanour > 0:
		return FEAR_RADIUS_CRUEL
	if _demeanour < 0:
		return FEAR_RADIUS_MERCIFUL
	return FEAR_RADIUS_NEUTRAL


func _pole_of_naklon() -> int:
	if Naklon.is_cruel():
		return 1
	if Naklon.is_merciful():
		return -1
	return 0


# ---------------------------------------------------------------------------
# Utility job choice. Runs once per _utility_timer expiry per villager, NOT
# per frame and NOT village-wide in one pass. Reads only already-existing
# state; writes nothing outside this villager and its own jobs bucket.
# ---------------------------------------------------------------------------
func _tick_utility(delta: float) -> void:
	_utility_timer -= delta
	if _utility_timer > 0.0:
		return
	_utility_timer = randf_range(UTILITY_INTERVAL_MIN, UTILITY_INTERVAL_MAX)
	if not is_instance_valid(_sanctum_node):
		_try_bind_sanctum()
	_evaluate_jobs()


## Scores every real job bucket against real world state. Higher is better.
## Every input below is read from a system that already exists; nothing here
## invents a number.
func _score_jobs(village: Village) -> Dictionary:
	var pop := maxf(1.0, float(village.population))

	# --- economy (systems/economy/stockpile.gd's documented meta convention,
	# read straight off the Village resource — no economy file is written) ---
	var stock: Dictionary = village.get_meta(Stockpile.META_KEY, {})
	var food: float = float(stock.get(&"food", 0.0))
	var wood: float = float(stock.get(&"wood", 0.0))
	var stone: float = float(stock.get(&"stone", 0.0))
	var cap := maxf(1.0, Stockpile.capacity(village, &"food"))
	var need_food := clampf(1.0 - food / (cap * FOOD_COMFORT_FRACTION), 0.0, 1.0)
	var need_wood := clampf(1.0 - wood / (cap * SUPPLY_COMFORT_FRACTION), 0.0, 1.0)
	var supply := clampf(minf(wood, stone) / (cap * SUPPLY_COMFORT_FRACTION), 0.0, 1.0)

	# --- weather, Sanctum, demography, faith, Naklon ---
	var storm := _weather_harshness
	var cruel := maxf(0.0, Naklon.value)
	var merciful := maxf(0.0, -Naklon.value)
	var hp_frac := 1.0
	if village.sanctum_hp_max > 0.0:
		hp_frac = clampf(village.sanctum_hp / village.sanctum_hp_max, 0.0, 1.0)
	var damage := 1.0 - hp_frac
	var need_children := clampf(1.0 - (float(village.children) / pop) / CHILD_COMFORT_RATIO, 0.0, 1.0)
	var faith := village.faith_fraction

	var scores: Dictionary = {
		# Fishing feeds best but is the most exposed thing anyone can be doing
		# in a storm, and the loneliest place to be under a cruel god.
		&"fishing": 0.35 + need_food * 1.50 - storm * 2.20 - cruel * 0.35,
		&"field": 0.35 + need_food * 1.25 - storm * 1.50 - cruel * 0.10,
		&"woodcutting": 0.30 + need_wood * 1.40 - storm * 0.90,
		# A damaged Sanctum is the strongest single pull in the whole table.
		&"building": 0.20 + damage * 2.40 + supply * 0.70 - storm * 0.60 + cruel * 0.35 + faith * 0.20,
		# Shelter/family: the one job that gets *better* in foul weather.
		&"family": 0.25 + need_children * 1.10 + storm * 1.30 + merciful * 0.35 + cruel * 0.20,
	}

	# Crowding: a bucket that already holds most of the workforce scores worse,
	# so the village spreads itself instead of stampeding one job.
	#
	# The denominator is the sum of the jobs buckets, NOT Village.population:
	# those two are only equal when every counted head has a spawned body, and
	# in world/god_view.tscn they are not (population 12, five bodies). Using
	# population there would divide by 12 and make crowding almost invisible.
	var workforce := 0
	for count in village.jobs.values():
		workforce += int(count)
	var head_count := maxf(1.0, float(workforce))
	for key in JOB_KEYS:
		var occupancy := float(int(village.jobs.get(key, 0))) / head_count
		scores[key] = float(scores[key]) - occupancy * CROWDING_WEIGHT + randf_range(-UTILITY_JITTER, UTILITY_JITTER)
	return scores


func _evaluate_jobs(force: bool = false) -> void:
	if not _can_react():
		return
	if _alert == Alert.RALLY and not force:
		return # a rallied villager stays on the repair until the alert lapses
	var village: Village = GameState.get_village(village_id)
	if village == null:
		return
	var scores := _score_jobs(village)
	_last_scores = scores
	_refresh_willingness(village)
	var best: StringName = JOB_KEYS[0]
	var best_score: float = -INF
	for key in JOB_KEYS:
		var s: float = float(scores[key])
		if s > best_score:
			best_score = s
			best = key
	# &"idle" is not a scored job, so an idle villager always takes work.
	var current_score: float = float(scores.get(current_job, -INF))
	if best == current_job:
		return
	if force or best_score > current_score + UTILITY_SWITCH_MARGIN:
		_assign_job(best)


## How readily this villager would go to the Calling Stone right now, given
## faith, fatigue, Reach's own miracle-fatigue on the prayer method, and the
## god's current temper. Cached (recomputed on this villager's own utility
## tick) so CallingStone can sort by it every 0.5s for free.
func _refresh_willingness(village: Village) -> void:
	var eff := Reach.effectiveness(village_id, &"calling_stone_prayer")
	var cruel := maxf(0.0, Naklon.value)
	var merciful := maxf(0.0, -Naklon.value)
	var dread_bonus := 0.30 if _alert == Alert.DREAD else 0.0
	_willingness = clampf(
		0.40
		+ village.faith_fraction * 0.80
		+ cruel * 0.60          # fear drives people to the stone hardest
		+ merciful * 0.25
		+ dread_bonus
		- prayer_fatigue * 0.90
		- (1.0 - eff) * 0.30,
		0.0, 2.0)


## Public, read-only. CallingStone orders its pull by this.
func prayer_willingness() -> float:
	return _willingness


func current_alert() -> Alert:
	return _alert


## Public, read-only. Last computed utility table — for debugging/inspection,
## nothing in the game loop reads it.
func job_scores() -> Dictionary:
	return _last_scores.duplicate()


func _village_center(village: Village = null) -> Vector3:
	var v: Village = village if village != null else GameState.get_village(village_id)
	if v == null:
		return global_position
	return Vector3(v.position_on_island.x, 0.0, v.position_on_island.y)


func _sanctum_position() -> Vector3:
	if is_instance_valid(_sanctum_node) and _sanctum_node is Node3D:
		return (_sanctum_node as Node3D).global_position
	return _village_center()


func _threat_or_center() -> Vector3:
	if _has_threat_point:
		return _last_threat_point
	if is_instance_valid(_shared_hand):
		return _shared_hand.global_position
	return _village_center()


# ---------------------------------------------------------------------------
# Job bucket bookkeeping — this is the ONLY place jobs Dictionary is touched
# so Village.jobs sums always equal Village.population.
# ---------------------------------------------------------------------------
func _assign_job(job_key: StringName, is_initial_spawn: bool = false) -> void:
	var village: Village = GameState.get_village(village_id)
	if village == null:
		return
	if not is_initial_spawn:
		village.jobs[current_job] = maxi(0, int(village.jobs.get(current_job, 0)) - 1)
	village.jobs[job_key] = int(village.jobs.get(job_key, 0)) + 1
	current_job = job_key
	current_state = _state_for_job(job_key)
	if current_state != State.FAMILY and partner != null:
		# Leaving the family bucket dissolves the pair from this side; the
		# other partner's own _handle_family already clears its half on the
		# next tick when it sees this one is no longer FAMILY.
		partner = null
		gestation_timer = 0.0
	_update_posture()
	_pick_wander_target()


func _state_for_job(job_key: StringName) -> State:
	for state in STATE_TO_JOB_KEY:
		if STATE_TO_JOB_KEY[state] == job_key:
			return state
	return State.IDLE


func _release_job_bucket_to_idle() -> void:
	var village: Village = GameState.get_village(village_id)
	if village == null:
		return
	if current_job != &"idle":
		village.jobs[current_job] = maxi(0, int(village.jobs.get(current_job, 0)) - 1)
		village.jobs["idle"] = int(village.jobs.get("idle", 0)) + 1
		current_job = &"idle"


# ---------------------------------------------------------------------------
# Calling Stone integration (public API, called by CallingStone)
# ---------------------------------------------------------------------------
func start_praying(stone: CallingStone) -> void:
	if current_state == State.PRAYING or current_state == State.DEAD or current_state == State.COLLAPSED:
		return
	_release_job_bucket_to_idle()
	calling_stone_ref = stone
	current_state = State.PRAYING
	prayer_fatigue = maxf(prayer_fatigue, 0.05)
	_prayer_tick_timer = randf_range(0.0, PRAYER_TICK_INTERVAL)
	_update_posture()


func stop_praying() -> void:
	if current_state != State.PRAYING:
		return
	calling_stone_ref = null
	current_state = State.IDLE
	current_job = &"idle"
	_update_posture()
	_pick_wander_target()


## Called only by CallingStone when it must drag an already-collapsed
## villager back to prayer because demand exceeds the healthy population.
## This is the deliberate risk/consequence path: real chance of death.
func force_praying_while_collapsed() -> void:
	if current_state != State.COLLAPSED:
		return
	if randf() < DEATH_CHANCE_ON_FORCED_PRAYER:
		_die()
		return
	Voices.react(&"villager_forced_to_kneel", {"village_id": village_id, "culture_id": culture_id})
	current_state = State.PRAYING
	_update_posture()


# ---------------------------------------------------------------------------
# Per-frame logic
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if current_state == State.DEAD:
		return
	# Three staggered timers. Per frame this is three float subtractions and
	# three comparisons; the actual work behind each only runs on expiry.
	_tick_senses(delta)
	_tick_alert(delta)
	_tick_utility(delta)
	match current_state:
		State.PRAYING:
			_handle_praying(delta)
		State.COLLAPSED:
			_handle_collapsed(delta)
		State.FAMILY:
			_handle_family(delta)
		State.DEAD:
			pass
		_:
			_handle_working_or_idle(delta)


func _handle_praying(delta: float) -> void:
	if calling_stone_ref and is_instance_valid(calling_stone_ref):
		target_position = calling_stone_ref.get_kneel_spot(self)
	prayer_fatigue += PRAYER_FATIGUE_RISE_PER_SEC * delta

	_prayer_tick_timer -= delta
	if _prayer_tick_timer <= 0.0:
		_prayer_tick_timer = PRAYER_TICK_INTERVAL
		var eff := Reach.effectiveness(village_id, &"calling_stone_prayer")
		GameState.add_devotion(village_id, DEVOTION_RATE_PRAYING * PRAYER_TICK_INTERVAL * eff)
		Reach.register_use(village_id, &"calling_stone_prayer")

	if prayer_fatigue >= COLLAPSE_FATIGUE_THRESHOLD:
		var over := (prayer_fatigue - COLLAPSE_FATIGUE_THRESHOLD) / (1.0 - COLLAPSE_FATIGUE_THRESHOLD)
		if randf() < COLLAPSE_CHANCE_PER_SEC_AT_MAX * over * delta:
			_collapse()


func _handle_collapsed(delta: float) -> void:
	collapse_timer -= delta
	prayer_fatigue -= FATIGUE_RECOVERY_PER_SEC * COLLAPSE_RECOVERY_FATIGUE_BONUS * delta
	if collapse_timer <= 0.0:
		current_state = State.IDLE
		current_job = &"idle"
		_update_posture()
		_pick_wander_target()


func _handle_family(delta: float) -> void:
	if partner == null or not is_instance_valid(partner):
		_find_family_partner()
	elif partner.current_state != State.FAMILY:
		partner = null
	else:
		# Only the lower-instance-id partner ticks gestation/maturation so a
		# pair doesn't double-count children.
		_is_family_leader = get_instance_id() < partner.get_instance_id()
		if _is_family_leader:
			_tick_family_leader(delta)
		elif _alert == Alert.NONE:
			target_position = partner.global_position + Vector3(0.6, 0.0, 0.0)

	prayer_fatigue -= FATIGUE_RECOVERY_PER_SEC * delta
	_ambient_devotion_tick(delta)
	if _alert == Alert.NONE:
		_wander_tick(delta)


func _find_family_partner() -> void:
	partner = null
	var candidates := get_tree().get_nodes_in_group(&"villager")
	for node in candidates:
		if node == self:
			continue
		var other := node as Villager
		if other == null:
			continue
		if other.village_id != village_id:
			continue
		if other.current_state != State.FAMILY:
			continue
		if other.partner != null:
			continue
		if global_position.distance_to(other.global_position) > FAMILY_PAIR_RADIUS:
			continue
		partner = other
		other.partner = self
		break


func _tick_family_leader(delta: float) -> void:
	if family_cooldown_timer > 0.0:
		family_cooldown_timer -= delta
	else:
		gestation_timer += delta
		if gestation_timer >= GESTATION_TIME:
			gestation_timer = 0.0
			family_cooldown_timer = FAMILY_COOLDOWN
			_birth_child()

	for i in range(_maturation_queue.size() - 1, -1, -1):
		_maturation_queue[i] -= delta
		if _maturation_queue[i] <= 0.0:
			_maturation_queue.remove_at(i)
			_mature_child()


func _birth_child() -> void:
	var village: Village = GameState.get_village(village_id)
	if village == null:
		return
	village.children += 1
	_maturation_queue.append(MATURATION_TIME)
	Voices.react(&"village_child_born", {"village_id": village_id, "culture_id": culture_id})


func _mature_child() -> void:
	var village: Village = GameState.get_village(village_id)
	if village == null:
		return
	village.children = maxi(0, village.children - 1)
	village.population += 1
	var child: Villager = VILLAGER_SCENE.instantiate()
	child.village_id = village_id
	child.initial_job = &"idle" # child's own _ready()->_assign_job bumps jobs["idle"] by exactly 1
	child.global_position = global_position + Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	get_parent().add_child(child)
	Voices.react(&"village_child_matured", {"village_id": village_id, "culture_id": culture_id})


func _handle_working_or_idle(delta: float) -> void:
	prayer_fatigue -= FATIGUE_RECOVERY_PER_SEC * delta
	_ambient_devotion_tick(delta)
	if _alert == Alert.NONE:
		_wander_tick(delta) # an alert owns the target while it lasts
	if current_state == State.IDLE:
		_idle_reconsider_timer -= delta
		if _idle_reconsider_timer <= 0.0:
			_idle_reconsider_timer = IDLE_RECONSIDER_TIME
			_reconsider_idle_job()


## An idle villager doesn't wait out its full utility interval — it takes the
## best-scoring job immediately (force = true skips the switch margin, since
## there is nothing to switch away from).
func _reconsider_idle_job() -> void:
	_evaluate_jobs(true)


func _ambient_devotion_tick(delta: float) -> void:
	_ambient_tick_timer -= delta
	if _ambient_tick_timer <= 0.0:
		_ambient_tick_timer = AMBIENT_TICK_INTERVAL
		GameState.add_devotion(village_id, DEVOTION_RATE_WORKING * AMBIENT_TICK_INTERVAL)


func _wander_tick(delta: float) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0 or global_position.distance_to(target_position) < ARRIVE_EPSILON:
		_pick_wander_target()


func _pick_wander_target() -> void:
	var village: Village = GameState.get_village(village_id)
	if village == null:
		_wander_timer = WANDER_MAX
		return
	var anchor := _job_anchor(village, current_job)
	# Naklon-reactive demeanour, expressed purely as where they choose to
	# stand: under mercy they drift toward the Sanctum, under cruelty they
	# keep the width of the village between themselves and wherever the Hand
	# or the Avatar last was.
	if _demeanour < 0:
		anchor = anchor.lerp(_sanctum_position(), 0.35)
	elif _demeanour > 0 and _has_threat_point:
		var away := anchor - _last_threat_point
		away.y = 0.0
		if away.length() < FEAR_RADIUS_CRUEL:
			anchor += (away.normalized() if away.length() > 0.01 else Vector3.FORWARD) * 5.0
	var radius := WANDER_RADIUS * (1.25 if _demeanour > 0 else 1.0)
	var offset := Vector3(randf_range(-radius, radius), 0.0, randf_range(-radius, radius))
	target_position = anchor + offset
	_wander_timer = randf_range(WANDER_MIN, WANDER_MAX)


func _job_anchor(village: Village, job_key: StringName) -> Vector3:
	var base := Vector3(village.position_on_island.x, 0.0, village.position_on_island.y)
	return base + JOB_OFFSETS.get(job_key, Vector3.ZERO)


# ---------------------------------------------------------------------------
# Collapse / death
# ---------------------------------------------------------------------------
func _collapse() -> void:
	current_state = State.COLLAPSED
	collapse_timer = COLLAPSE_RECOVERY_TIME
	calling_stone_ref = null
	velocity = Vector3.ZERO
	_update_posture()
	Voices.react(&"villager_collapsed", {"village_id": village_id, "culture_id": culture_id})


func _die() -> void:
	current_state = State.DEAD
	var village: Village = GameState.get_village(village_id)
	if village:
		village.jobs["idle"] = maxi(0, int(village.jobs.get("idle", 0)) - 1)
		village.population = maxi(0, village.population - 1)
		if village.population <= 0:
			GameState.village_lost.emit(village_id)
	Naklon.shift(0.03, 1.0) # forcing worshippers to death is a small, real cruelty
	Voices.react(&"villager_died_praying", {"village_id": village_id, "culture_id": culture_id})
	# GameState.earn_epithet() is itself idempotent (no-op if already earned),
	# so this is safe to call on every prayer-death without a local guard flag.
	GameState.earn_epithet(
		"The One Who Prayed Them to Death",
		"a villager died after being forced back to the calling stone while already collapsed from prayer"
	)
	set_physics_process(false)
	set_process(false)
	queue_free()


# ---------------------------------------------------------------------------
# Posture (purely visual — capsule tilt/scale, no skeletal animation in this pass)
# ---------------------------------------------------------------------------
func _update_posture() -> void:
	match current_state:
		State.PRAYING:
			_body_mesh.rotation = Vector3.ZERO
			_body_mesh.scale = Vector3(1.0, 0.65, 1.0)
			_body_mesh.position.y = 0.55
		State.COLLAPSED:
			_body_mesh.rotation = Vector3(0.0, 0.0, deg_to_rad(85.0))
			_body_mesh.scale = Vector3(1.0, 1.0, 1.0)
			_body_mesh.position.y = 0.35
		_:
			if _is_cowering():
				# Flinching / kneeling in the open: the same cheap squash the
				# prayer posture uses, slightly wider, so "afraid" reads at a
				# glance without a single new animation.
				_body_mesh.rotation = Vector3.ZERO
				_body_mesh.scale = Vector3(1.08, 0.7, 1.08)
				_body_mesh.position.y = 0.6
			else:
				_body_mesh.rotation = Vector3.ZERO
				_body_mesh.scale = Vector3.ONE
				_body_mesh.position.y = 0.9
	if _label:
		_label.text = _state_label_text()


func _is_cowering() -> bool:
	return _flinch_timer > 0.0 or _alert == Alert.DREAD or _alert == Alert.MOURN


func _state_label_text() -> String:
	var names := {
		State.IDLE: "idle", State.FISHING: "fishing", State.FIELD: "field",
		State.WOODCUTTING: "woodcutting", State.BUILDING: "building",
		State.FAMILY: "family", State.PRAYING: "praying",
		State.COLLAPSED: "collapsed", State.DEAD: "dead",
	}
	var base: String = String(names.get(current_state, "?"))
	var alerts := {
		Alert.SHELTER: " · sheltering", Alert.RALLY: " · rallying",
		Alert.GATHER: " · gathering", Alert.FLEE: " · fleeing",
		Alert.MOURN: " · mourning", Alert.DREAD: " · dread",
	}
	return base + String(alerts.get(_alert, ""))


# ---------------------------------------------------------------------------
# Movement (no NavigationAgent3D: no baked navmesh exists yet in this build —
# see docs/systems/villagers.md "Scoped out". Flat-ground direct steering.)
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if current_state == State.DEAD:
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	var speed := 0.0 if current_state in [State.PRAYING, State.COLLAPSED] else WALK_SPEED * _speed_scale
	var flat_target := target_position
	flat_target.y = global_position.y
	var to_target := flat_target - global_position
	var dist := to_target.length()

	if speed > 0.0 and dist > ARRIVE_EPSILON:
		var dir := to_target.normalized()
		# One extra add + normalize, and only while something frightening is
		# actually inside this villager's fear radius (see _tick_senses).
		if _avoid_vector != Vector3.ZERO:
			dir = (dir + _avoid_vector).normalized()
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), delta * 4.0)
	else:
		velocity.x = move_toward(velocity.x, 0.0, WALK_SPEED * 4.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, WALK_SPEED * 4.0 * delta)
		if current_state == State.PRAYING and calling_stone_ref and is_instance_valid(calling_stone_ref):
			var to_stone: Vector3 = calling_stone_ref.global_position - global_position
			if to_stone.length() > 0.1:
				rotation.y = lerp_angle(rotation.y, atan2(to_stone.x, to_stone.z), delta * 4.0)

	move_and_slide()
