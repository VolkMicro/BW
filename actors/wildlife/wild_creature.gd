extends CharacterBody3D
class_name WildCreature
## PACKAGE W (wildlife) — one wild animal. A real state machine that makes
## real decisions from real world state, not a scripted animation loop.
##
## States: GRAZE (stationary, feeding/resting), WANDER (walking a leg of its
## home range), FLEE (running from a god or a predator), HUNT (predator
## pursuing a chosen target), FEED (predator standing over a kill),
## SCAVENGE (walking to someone else's kill), DEAD.
##
## Public API other packages can rely on:
##   creature.species          : WildlifeSpecies
##   creature.species_id()     -> StringName
##   creature.state_name()     -> String
##   creature.is_alive()       -> bool
##   creature.place_at(pos)    -> void      (call AFTER add_child, never before)
##   creature.kill_by(killer)  -> void      (fires `killed`, then despawns)
##   creature.set_fear_scale(f)-> void      (Naklon hook, see WildlifeManager)
##   signal killed(creature, killer)
##   signal alarmed(creature, threat_position)
## Group membership: every live creature is in &"wildlife" and in a
## per-species group (&"wildlife_rimefleece", etc).
##
## ---------------------------------------------------------------------------
## PERFORMANCE CONTRACT (target hardware: Dell Latitude 5411, integrated
## Intel graphics only, ~5-6 fps baseline — see docs/systems/performance_notes.md)
##
## - There is NO `_process()`. Everything — the decision timer and the
##   movement — runs in a single `_physics_process()` callback, so a creature
##   costs ONE script callback per physics tick, not two. (villager.gd uses
##   both; this is deliberately cheaper.)
## - Decisions run on a personal timer (`species.think_interval`, ~0.35s) whose
##   phase is randomized at spawn, so a herd of twelve never thinks on the
##   same frame. Amortized, a creature makes ~3 decisions/second, not 60.
## - A resting creature (GRAZE/FEED, already on the floor, already stopped)
##   sets `_resting` and its `_physics_process` returns immediately after
##   decrementing the think timer: no gravity integration, no `move_and_slide()`,
##   no steering math. In practice half to two-thirds of the herd is resting
##   at any moment.
## - ZERO raycasts, ever. Ground contact is CharacterBody3D's own floor
##   detection (identical to actors/villagers/villager.gd) and "is this spot
##   dry land" is answered by `IslandTerrain.sample_height()`, which is a
##   bilinear lookup in an already-built PackedFloat32Array
##   (`island_generator.gd:265`), not a physics query — and it is only called
##   when choosing a new wander target (every 3-8s), never per frame.
## - ZERO `.distance_to()` / `.length()` in any hot path. Every proximity
##   test is `length_squared()` against a pre-squared radius cached in
##   `_flee_r2` / `_calm_r2` / `_kill_r2` / `_cohesion_r2`.
## - The creature never searches the scene tree. All threat positions come
##   pre-collected from WildlifeManager's shared cache (rebuilt once every
##   0.5s for the WHOLE population, not once per creature).

signal killed(creature: WildCreature, killer: WildCreature)
signal alarmed(creature: WildCreature, threat_position: Vector3)

enum State { GRAZE, WANDER, FLEE, HUNT, FEED, SCAVENGE, DEAD }

const GRAVITY := 9.8
const ARRIVE_EPSILON_SQ := 0.36        # 0.6m, squared
const CORPSE_SECONDS := 6.0            # how long a kill stays visible before despawn
const WANDER_TARGET_TRIES := 4
const HUNT_RETRY_SECONDS := 5.0        # cooldown after a failed/abandoned hunt

## Species data. Either assign this directly before add_child(), or set
## `species_id` and let _ready() load actors/wildlife/species/<id>.tres.
@export var species: WildlifeSpecies
@export var species_id_hint: StringName = &""
@export var show_debug_label: bool = false

## Set by WildlifeManager. Left null when a creature is dropped into a scene
## by hand — it then simply has no threat cache and no herd, and falls back to
## wandering its home range forever. That degradation is deliberate: a
## hand-placed creature must never crash, it just gets dumber.
##
## DELIBERATELY UNTYPED. `wildlife_manager.gd` statically references
## `WildCreature` everywhere (typed arrays, typed signal args, typed
## returns); annotating this as `WildlifeManager` closes that into a
## class_name cycle, which Godot 4.3 rejects at parse time with
## "Could not resolve external class member". Verified by actually running
## actors/wildlife/wildlife_demo.tscn headless, not assumed. The static
## dependency therefore runs one way only — manager -> creature — and the
## handful of calls back the other way are dynamic. They all happen on the
## think tick (~3/sec/creature), never per frame, so the dynamic-dispatch
## cost is irrelevant here.
var manager = null

var home_center: Vector3 = Vector3.ZERO
var current_state: State = State.GRAZE

var _move_target: Vector3 = Vector3.ZERO
var _think_timer: float = 0.0
var _since_think: float = 0.0
var _state_timer: float = 0.0
var _calm_timer: float = 0.0
var _hunger: float = 0.0
var _resting: bool = false
var _hunt_target: WildCreature = null
var _hunt_retry_timer: float = 0.0
var _scavenge_point: Vector3 = Vector3.ZERO
var _scavenge_arrived: bool = false
var _fear_scale: float = 1.0

# Pre-squared radii, recomputed only when species or fear scale changes.
var _flee_r2: float = 0.0
var _calm_r2: float = 0.0
var _kill_r2: float = 0.0
var _cohesion_r2: float = 0.0
var _hunt_r2: float = 0.0
var _home_r2: float = 0.0

@onready var _collider: CollisionShape3D = $CollisionShape3D
@onready var _mesh: MeshInstance3D = $BodyMesh
@onready var _label: Label3D = $DebugLabel


func _ready() -> void:
	if species == null and species_id_hint != &"":
		species = load("res://actors/wildlife/species/%s.tres" % species_id_hint) as WildlifeSpecies
	if species == null:
		push_warning("WildCreature spawned without a WildlifeSpecies; it will stand still.")
		set_physics_process(false)
		return
	add_to_group(&"wildlife")
	add_to_group(StringName("wildlife_" + String(species.id)))
	_build_body()
	_recompute_radii()
	# Randomized phase: a herd spawned in one frame must not all think in the
	# same frame forever after.
	_think_timer = randf_range(0.0, species.think_interval)
	_hunger = randf_range(0.0, 0.6) if species.is_predator else 0.0
	_move_target = global_position
	home_center = global_position
	_enter(State.GRAZE)


## Called by WildlifeManager AFTER add_child() — never before. Setting
## global_position on a node that is not yet inside the SceneTree silently
## discards the write (see docs/systems/integration.md's villager-spawn bug),
## and _ready() has already run by the time add_child() returns, so the home
## range has to be (re)anchored here rather than in _ready().
func place_at(world_position: Vector3) -> void:
	global_position = world_position
	home_center = world_position
	_move_target = world_position
	_pick_wander_target()


func species_id() -> StringName:
	return species.id if species else &"unknown"


func is_alive() -> bool:
	return current_state != State.DEAD


func state_name() -> String:
	match current_state:
		State.GRAZE: return "graze"
		State.WANDER: return "wander"
		State.FLEE: return "flee"
		State.HUNT: return "hunt"
		State.FEED: return "feed"
		State.SCAVENGE: return "scavenge"
		State.DEAD: return "dead"
	return "?"


# ---------------------------------------------------------------------------
# Body — one shared, cached ArrayMesh per species (see wildlife_body.gd).
# ---------------------------------------------------------------------------
func _build_body() -> void:
	var mesh := WildlifeBody.mesh_for(species)
	if mesh == null:
		# Never leave an invisible animal in the world: fall back to a plain
		# tinted capsule rather than pretending the build succeeded.
		var fallback := CapsuleMesh.new()
		fallback.radius = species.collider_radius
		fallback.height = species.collider_height
		fallback.radial_segments = 8
		fallback.rings = 2
		var mat := StandardMaterial3D.new()
		mat.albedo_color = species.color_primary
		fallback.surface_set_material(0, mat)
		_mesh.mesh = fallback
		_mesh.position.y = species.collider_center_y()
		push_warning("WildlifeBody.mesh_for(%s) returned null; using fallback capsule." % species.id)
	else:
		_mesh.mesh = mesh
		_mesh.position.y = 0.0
	_mesh.scale = Vector3.ONE * species.body_scale

	var shape := CapsuleShape3D.new()
	shape.radius = species.collider_radius
	shape.height = maxf(species.collider_height, species.collider_radius * 2.0 + 0.01)
	_collider.shape = shape
	_collider.position.y = species.collider_center_y()

	_label.position.y = species.label_height
	_label.visible = show_debug_label


func _recompute_radii() -> void:
	var fr := species.flee_radius * _fear_scale
	var cr := maxf(species.calm_radius * _fear_scale, fr + 1.0)
	_flee_r2 = fr * fr
	_calm_r2 = cr * cr
	_kill_r2 = species.kill_range * species.kill_range
	_cohesion_r2 = species.cohesion_radius * species.cohesion_radius
	_hunt_r2 = species.hunt_radius * species.hunt_radius
	_home_r2 = species.home_range_radius * species.home_range_radius


## Naklon hook, pushed by WildlifeManager when Naklon.naklon_changed fires.
## >1 = spookier (cruel god), <1 = calmer (merciful god). Costs nothing per
## frame: it only re-derives six cached squared radii, on a signal that only
## fires when the player actually does something.
func set_fear_scale(f: float) -> void:
	_fear_scale = maxf(f, 0.05)
	if species:
		_recompute_radii()


# ---------------------------------------------------------------------------
# The single per-frame callback. Everything lives here (see the performance
# contract in this file's header for why there is no _process()).
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if current_state == State.DEAD:
		return

	_think_timer -= delta
	_since_think += delta
	_state_timer -= delta
	if _think_timer <= 0.0:
		_think()
		_since_think = 0.0
		_think_timer = species.think_interval * randf_range(0.85, 1.15)

	if _resting:
		return

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	var speed := _current_speed()
	var to_target := _move_target - global_position
	to_target.y = 0.0
	var dist_sq := to_target.length_squared()

	if speed > 0.0 and dist_sq > ARRIVE_EPSILON_SQ:
		var inv := 1.0 / sqrt(dist_sq)
		velocity.x = to_target.x * inv * speed
		velocity.z = to_target.z * inv * speed
		rotation.y = lerp_angle(rotation.y, atan2(to_target.x, to_target.z), delta * species.turn_rate)
	else:
		var brake := species.walk_speed * 5.0 * delta
		velocity.x = move_toward(velocity.x, 0.0, brake)
		velocity.z = move_toward(velocity.z, 0.0, brake)

	move_and_slide()


func _current_speed() -> float:
	match current_state:
		State.FLEE:
			return species.flee_speed
		State.HUNT:
			return species.hunt_speed
		State.WANDER, State.SCAVENGE:
			return species.walk_speed
		_:
			return 0.0


# ---------------------------------------------------------------------------
# THE DECISION PASS. Runs ~3x/second per creature, phase-staggered.
# Order matters: fear overrides everything except being dead.
# ---------------------------------------------------------------------------
func _think() -> void:
	if species.is_predator:
		_hunger += _since_think / maxf(species.seconds_to_hunger, 0.01)

	# --- 1. Fear. Nearest threat wins; squared distances only. -------------
	var threat := _nearest_threat()
	var threat_pos: Vector3 = threat[0]
	var threat_d2: float = threat[1]

	if threat_d2 < _flee_r2:
		if current_state != State.FLEE:
			_enter(State.FLEE)
			alarmed.emit(self, threat_pos)
			if manager:
				manager.report_alarm(self, threat_pos)
		_calm_timer = species.calm_seconds * _fear_scale
		_aim_away_from(threat_pos)
		return

	if current_state == State.FLEE:
		if threat_d2 > _calm_r2:
			_calm_timer -= _since_think
			if _calm_timer <= 0.0:
				_enter(State.WANDER)
				_pick_wander_target()
			else:
				_aim_away_from(threat_pos)
		else:
			# In the hysteresis band: keep moving, but stop panicking harder.
			_aim_away_from(threat_pos)
		return

	# --- 2. Predator business ---------------------------------------------
	if current_state == State.FEED:
		if _state_timer <= 0.0:
			_enter(State.WANDER)
			_pick_wander_target()
		else:
			_maybe_rest()
		return

	if _hunt_retry_timer > 0.0:
		_hunt_retry_timer -= _since_think
	elif species.is_predator and species.hunt_speed > 0.0 and _hunger >= 1.0:
		_tick_hunt()
		return

	# --- 3. Scavenging (snagbill walking to someone else's kill) -----------
	if current_state == State.SCAVENGE:
		if _scavenge_arrived:
			if _state_timer <= 0.0:
				_enter(State.WANDER)
				_pick_wander_target()
			else:
				_maybe_rest()
			return
		var to_kill := _scavenge_point - global_position
		to_kill.y = 0.0
		if to_kill.length_squared() <= ARRIVE_EPSILON_SQ * 4.0:
			# Only now does the feeding clock start — the walk there must not
			# eat the time it spends there.
			_scavenge_arrived = true
			_state_timer = species.scavenge_seconds
			_move_target = global_position
		elif _state_timer <= -20.0:
			# Could not reach the carcass in a reasonable time (blocked, or a
			# predator kept scaring it off). Give up rather than orbit forever.
			_enter(State.WANDER)
			_pick_wander_target()
		return

	# --- 4. Ordinary life: alternate grazing and wandering -----------------
	if _state_timer > 0.0 and current_state == State.GRAZE:
		_maybe_rest()
		return

	if current_state == State.WANDER:
		var to_wander := _move_target - global_position
		to_wander.y = 0.0
		if to_wander.length_squared() <= ARRIVE_EPSILON_SQ or _state_timer <= 0.0:
			_enter(State.GRAZE)
		return

	_enter(State.WANDER)
	_pick_wander_target()


## A resting creature skips gravity + move_and_slide entirely. Only entered
## once the body has genuinely settled (on the floor, velocity ~0), so it can
## never freeze an animal in mid-air.
func _maybe_rest() -> void:
	if _resting:
		return
	if not is_on_floor():
		return
	if absf(velocity.x) > 0.02 or absf(velocity.z) > 0.02 or absf(velocity.y) > 0.02:
		return
	velocity = Vector3.ZERO
	_resting = true


# ---------------------------------------------------------------------------
# Threat evaluation. Reads WildlifeManager's shared cache — the creature
# itself never touches the scene tree or the physics server for this.
# ---------------------------------------------------------------------------
## Returns [position, squared_distance]. INF distance means "nothing near".
func _nearest_threat() -> Array:
	var best_pos := Vector3.ZERO
	var best_d2 := INF
	if manager == null:
		return [best_pos, best_d2]
	var here := global_position

	# One dynamic property read each, then a tight typed loop over at most a
	# handful of cached Vector3s. No tree walks, no group queries, no
	# .distance_to() — squared distances only.
	var gods: PackedVector3Array = manager.god_threats
	for p in gods:
		var d := p - here
		d.y = 0.0
		var d2 := d.length_squared()
		if d2 < best_d2:
			best_d2 = d2
			best_pos = p

	# Predators fear gods but not each other, and never themselves.
	if species.is_prey:
		var preds: PackedVector3Array = manager.predator_points
		for p in preds:
			var d := p - here
			d.y = 0.0
			var d2 := d.length_squared()
			if d2 < best_d2:
				best_d2 = d2
				best_pos = p

	return [best_pos, best_d2]


func _aim_away_from(threat_pos: Vector3) -> void:
	var away := global_position - threat_pos
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	away = away.normalized()

	# A panicking animal runs away, but not into the sea and not off the
	# edge of the world: bias the escape vector back toward the home range
	# once it has been pushed twice the range's radius out.
	var from_home := global_position - home_center
	from_home.y = 0.0
	if from_home.length_squared() > _home_r2 * 4.0:
		away = (away - from_home.normalized() * 0.9).normalized()

	var candidate := global_position + away * species.flee_step
	# One terrain lookup, only on a think tick while fleeing. If the escape
	# route is underwater, veer along the shore instead of into it.
	if manager and not manager.is_walkable(Vector2(candidate.x, candidate.z), species.min_ground_height):
		var side := Vector3(-away.z, 0.0, away.x)
		var alt := global_position + (away * 0.35 + side).normalized() * species.flee_step
		if manager.is_walkable(Vector2(alt.x, alt.z), species.min_ground_height):
			candidate = alt
		else:
			candidate = global_position - (global_position - home_center).normalized() * species.flee_step
	_move_target = candidate


# ---------------------------------------------------------------------------
# Hunting
# ---------------------------------------------------------------------------
func _tick_hunt() -> void:
	if _hunt_target != null and not is_instance_valid(_hunt_target):
		_hunt_target = null
	if _hunt_target != null and not _hunt_target.is_alive():
		_hunt_target = null

	if _hunt_target == null:
		if manager:
			var found: WildCreature = manager.find_prey_for(self)
			_hunt_target = found
		if _hunt_target == null:
			# Nothing worth chasing in range. Back off for a few seconds and
			# go back to prowling — re-running the prey scan every 0.35s
			# forever on an empty island would be pure wasted work.
			_hunt_retry_timer = HUNT_RETRY_SECONDS
			return
		_enter(State.HUNT)

	var to_prey := _hunt_target.global_position - global_position
	to_prey.y = 0.0
	var d2 := to_prey.length_squared()

	if d2 > _hunt_r2 * 2.25:
		# Lost it. Give up rather than chasing across the whole island.
		_hunt_target = null
		_hunt_retry_timer = HUNT_RETRY_SECONDS
		_enter(State.WANDER)
		_pick_wander_target()
		return

	if d2 <= _kill_r2:
		var victim := _hunt_target
		_hunt_target = null
		_hunger = 0.0
		_enter(State.FEED)
		_state_timer = species.feed_seconds
		_move_target = global_position
		victim.kill_by(self)
		return

	if current_state != State.HUNT:
		_enter(State.HUNT)
	_move_target = _hunt_target.global_position


# ---------------------------------------------------------------------------
# Scavenging — driven by WildlifeManager relaying its `prey_killed` signal.
# Event-driven: costs exactly nothing until something actually dies.
# ---------------------------------------------------------------------------
func notify_carcass(world_position: Vector3) -> void:
	if not species.scavenges or current_state == State.DEAD or current_state == State.FLEE:
		return
	var d := world_position - global_position
	d.y = 0.0
	if d.length_squared() > species.scavenge_radius * species.scavenge_radius:
		return
	_scavenge_point = world_position
	_move_target = world_position
	_scavenge_arrived = false
	_enter(State.SCAVENGE)
	_state_timer = species.scavenge_seconds


# ---------------------------------------------------------------------------
# Death
# ---------------------------------------------------------------------------
## Kills this creature. Fires `killed` (and, through the manager,
## `WildlifeManager.prey_killed`) BEFORE despawning, so other systems can
## read the position and species while the node is still valid.
func kill_by(killer: WildCreature) -> void:
	if current_state == State.DEAD:
		return
	current_state = State.DEAD
	_resting = true
	velocity = Vector3.ZERO
	_hunt_target = null
	if is_in_group(&"wildlife"):
		remove_from_group(&"wildlife")
	if species and is_in_group(StringName("wildlife_" + String(species.id))):
		remove_from_group(StringName("wildlife_" + String(species.id)))
	# Lie down. Purely visual, no skeletal animation in this pass — the same
	# capsule-tilt convention actors/villagers/villager.gd uses for COLLAPSED.
	_mesh.rotation.z = deg_to_rad(84.0)
	_mesh.position.y = maxf(species.collider_radius * 0.6, 0.15) if species else 0.2
	if _label:
		_label.text = "dead"
	killed.emit(self, killer)
	if manager:
		manager.report_kill(self, killer)
	# Disable collision so a feeding predator doesn't get shoved off the
	# carcass by its own physics body while the corpse lingers.
	_collider.set_deferred("disabled", true)
	set_physics_process(false)
	get_tree().create_timer(CORPSE_SECONDS).timeout.connect(queue_free)


# ---------------------------------------------------------------------------
# State entry + wandering
# ---------------------------------------------------------------------------
func _enter(new_state: State) -> void:
	current_state = new_state
	_resting = false
	match new_state:
		State.GRAZE:
			_state_timer = randf_range(species.graze_min_seconds, species.graze_max_seconds)
			_move_target = global_position
		State.WANDER:
			_state_timer = randf_range(species.wander_min_seconds, species.wander_max_seconds)
		State.FLEE:
			_state_timer = 0.0
			_calm_timer = species.calm_seconds * _fear_scale
		_:
			pass
	if _label and _label.visible:
		_label.text = "%s %s" % [species.display_name, state_name()]


## QA hook (mirrors LouhiDirector.debug_force_evaluate()'s convention):
## makes a predator hungry right now instead of waiting out seconds_to_hunger.
func debug_make_hungry() -> void:
	_hunger = 1.0
	_hunt_retry_timer = 0.0
	_think_timer = 0.0


## Picks the next walking destination inside the home range, rejecting spots
## below the species' min_ground_height (that's how nothing walks into the
## sea without a single raycast). Up to 4 tries; if all fail, it just stays
## where it is and tries again next state change.
func _pick_wander_target() -> void:
	var herd_center := home_center
	var use_herd := false
	if species.is_herd and manager:
		var c: Vector3 = manager.herd_centroid(species.id, home_center)
		var to_c := c - global_position
		to_c.y = 0.0
		if to_c.length_squared() > _cohesion_r2:
			herd_center = c
			use_herd = true

	for _i in range(WANDER_TARGET_TRIES):
		var angle := randf() * TAU
		var radius := randf_range(species.wander_step * 0.35, species.wander_step)
		var candidate := global_position + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)

		# Stay inside the home range.
		var from_home := candidate - home_center
		from_home.y = 0.0
		if from_home.length_squared() > _home_r2:
			candidate = home_center + from_home.normalized() * species.home_range_radius * 0.85

		# Loose herd cohesion: one lerp, only when already too far out.
		if use_herd:
			candidate = candidate.lerp(herd_center, species.cohesion_weight)

		if manager == null or manager.is_walkable(Vector2(candidate.x, candidate.z), species.min_ground_height):
			_move_target = candidate
			return
	_move_target = global_position
