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
## Group membership: every live villager is in group &"villager".

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
		else:
			target_position = partner.global_position + Vector3(0.6, 0.0, 0.0)

	prayer_fatigue -= FATIGUE_RECOVERY_PER_SEC * delta
	_ambient_devotion_tick(delta)
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
	_wander_tick(delta)
	if current_state == State.IDLE:
		_idle_reconsider_timer -= delta
		if _idle_reconsider_timer <= 0.0:
			_idle_reconsider_timer = IDLE_RECONSIDER_TIME
			_reconsider_idle_job()


func _reconsider_idle_job() -> void:
	var village: Village = GameState.get_village(village_id)
	if village == null:
		return
	var best: StringName = JOB_KEYS[0]
	var best_count: int = int(village.jobs.get(best, 0))
	for key in JOB_KEYS:
		var c := int(village.jobs.get(key, 0))
		if c < best_count:
			best = key
			best_count = c
	_assign_job(best)


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
	var offset := Vector3(randf_range(-WANDER_RADIUS, WANDER_RADIUS), 0.0, randf_range(-WANDER_RADIUS, WANDER_RADIUS))
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
			_body_mesh.rotation = Vector3.ZERO
			_body_mesh.scale = Vector3.ONE
			_body_mesh.position.y = 0.9
	if _label:
		_label.text = _state_label_text()


func _state_label_text() -> String:
	var names := {
		State.IDLE: "idle", State.FISHING: "fishing", State.FIELD: "field",
		State.WOODCUTTING: "woodcutting", State.BUILDING: "building",
		State.FAMILY: "family", State.PRAYING: "praying",
		State.COLLAPSED: "collapsed", State.DEAD: "dead",
	}
	return String(names.get(current_state, "?"))


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

	var speed := 0.0 if current_state in [State.PRAYING, State.COLLAPSED] else WALK_SPEED
	var flat_target := target_position
	flat_target.y = global_position.y
	var to_target := flat_target - global_position
	var dist := to_target.length()

	if speed > 0.0 and dist > ARRIVE_EPSILON:
		var dir := to_target.normalized()
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
