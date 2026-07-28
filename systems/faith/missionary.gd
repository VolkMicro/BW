extends CharacterBody3D
class_name Missionary
## Package J — a sendable mortal missionary. Walks from a converted "home"
## village toward an unconverted "target" village, then stands there
## ("stationed") slowly raising the target's faith_fraction via
## Reach.convert_via_missionary(), which itself runs through
## Reach.effectiveness()/register_use() under method_id &"missionary" —
## so a village that has heard the same missionary drone on for too long
## fatigues exactly like it would against a repeated miracle.
##
## Deliberately a separate, minimal mover rather than a Villager subclass:
## Villager (actors/villagers/, package G) is a job/family/prayer state
## machine tied tightly to Village.jobs bookkeeping, and a missionary is
## conceptually a villager who has left the job rotation entirely to
## travel. Reusing Villager would mean either faking a job bucket for
## "missionary" that core/village.gd's jobs Dictionary has no slot for
## (the same problem G's own docs note for PRAYING/COLLAPSED), or editing
## village.gd, which is foundation-owned. This file copies Villager's
## flat-ground steering pattern (no NavigationAgent3D — see "Scoped out" in
## docs/systems/reach_faith.md) rather than importing it, so package J
## isn't blocked on package G's file.
##
## Public API other packages can rely on:
##   Missionary.spawn(home_village_id, target_village_id, parent) -> Missionary
##   missionary.home_village_id / missionary.target_village_id : StringName
##   missionary.current_state : State
##   missionary.send_to(new_target_village_id: StringName) -> void
##   missionary.recall() -> void
## Signals: arrived(missionary, village_id), recalled(missionary, village_id)
## Group membership: every live missionary is in group &"missionary".

signal arrived(missionary: Missionary, village_id: StringName)
signal recalled(missionary: Missionary, village_id: StringName)

enum State {
	WALKING,   # en route to target_village_id
	STATIONED, # arrived, preaching in place
	RETURNING, # recalled or target lost to Louhi; walking home to be freed
	DONE,      # reached home after a recall; about to queue_free
}

# --- Tuning constants -------------------------------------------------------
const GRAVITY := 9.8
const WALK_SPEED := 1.8
const ARRIVE_RADIUS := 4.0        # stands near the village edge, not on top of the calling stone
const RETURN_ARRIVE_EPSILON := 0.6
const STATION_TICK_INTERVAL := 3.0
const STATION_GAIN_PER_TICK := 0.018 # requested faith_fraction gain per tick, before effectiveness/headroom

# --- Config ------------------------------------------------------------------
@export var home_village_id: StringName = &""
@export var target_village_id: StringName = &""
@export var show_debug_label: bool = true

# --- Runtime state -----------------------------------------------------------
var current_state: State = State.WALKING
var _station_timer: float = 0.0

const MISSIONARY_SCENE: PackedScene = preload("res://systems/faith/missionary.tscn")

@onready var _body_mesh: MeshInstance3D = $Body
@onready var _label: Label3D = $DebugLabel


## Convenience constructor: instantiate, wire up, and add to `parent` in one
## call. `home_village_id` should already be a converted village (not
## enforced here — a missionary sent from an unconverted village just has
## nothing useful to say, which is its own kind of joke Voices can make).
static func spawn(home_id: StringName, target_id: StringName, parent: Node) -> Missionary:
	var m: Missionary = MISSIONARY_SCENE.instantiate()
	m.home_village_id = home_id
	m.target_village_id = target_id
	parent.add_child(m)
	return m


func _ready() -> void:
	add_to_group(&"missionary")
	var home: Village = GameState.get_village(home_village_id)
	if home != null:
		global_position = Vector3(home.position_on_island.x, 0.0, home.position_on_island.y)
		_apply_culture_tint(home.culture_id)
	else:
		push_warning("Missionary spawned with unknown home_village_id: %s" % home_village_id)
	_update_label()
	if _label:
		_label.visible = show_debug_label
	Voices.react(&"missionary_sent", {"village_id": home_village_id, "target_village_id": target_village_id})


func _apply_culture_tint(culture_id: StringName) -> void:
	var culture: Culture = GameState.cultures.get(culture_id) if GameState.cultures.has(culture_id) else null
	var mat := StandardMaterial3D.new()
	mat.albedo_color = culture.color_accent if culture else Color.GAINSBORO
	mat.roughness = 0.7
	_body_mesh.material_override = mat


## (Re)target an already-spawned missionary — e.g. their original target
## converted fully or was lost, and a caller wants to redirect them without
## despawning/respawning.
func send_to(new_target_village_id: StringName) -> void:
	target_village_id = new_target_village_id
	current_state = State.WALKING
	_update_label()


## Recall the missionary home. They walk back to home_village_id and are
## freed on arrival (see "Scoped out": no persistent roster/reassignment
## UI in this pass — callers that want to keep using the same unit should
## call send_to() instead of recall() while it is still WALKING/STATIONED).
func recall() -> void:
	if current_state == State.DONE or current_state == State.RETURNING:
		return
	var prev_target := target_village_id
	current_state = State.RETURNING
	recalled.emit(self, prev_target)
	Voices.react(&"missionary_recalled", {"village_id": prev_target, "home_village_id": home_village_id})
	_update_label()


func _physics_process(delta: float) -> void:
	match current_state:
		State.WALKING:
			_steer_toward(target_village_id, delta)
			if _within_arrival(target_village_id, ARRIVE_RADIUS):
				_arrive()
		State.STATIONED:
			_hold_station(delta)
		State.RETURNING:
			_steer_toward(home_village_id, delta)
			if _within_arrival(home_village_id, RETURN_ARRIVE_EPSILON + ARRIVE_RADIUS):
				_finish_return()
		State.DONE:
			velocity = Vector3.ZERO
	move_and_slide()


func _steer_toward(id: StringName, delta: float) -> void:
	_apply_gravity(delta)
	var v: Village = GameState.get_village(id)
	if v == null:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var target_pos := Vector3(v.position_on_island.x, global_position.y, v.position_on_island.y)
	var to_target := target_pos - global_position
	to_target.y = 0.0
	var dist := to_target.length()
	if dist > 0.15:
		var dir := to_target.normalized()
		velocity.x = dir.x * WALK_SPEED
		velocity.z = dir.z * WALK_SPEED
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), delta * 4.0)
	else:
		velocity.x = 0.0
		velocity.z = 0.0


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0


func _within_arrival(id: StringName, radius: float) -> bool:
	var v: Village = GameState.get_village(id)
	if v == null:
		return false
	var target_pos := Vector3(v.position_on_island.x, 0.0, v.position_on_island.y)
	var flat := global_position
	flat.y = 0.0
	return flat.distance_to(target_pos) <= radius


func _arrive() -> void:
	current_state = State.STATIONED
	_station_timer = 0.0
	velocity = Vector3.ZERO
	arrived.emit(self, target_village_id)
	Voices.react(&"missionary_arrived", {"village_id": target_village_id})
	_update_label()


func _hold_station(delta: float) -> void:
	_apply_gravity(delta)
	velocity.x = move_toward(velocity.x, 0.0, WALK_SPEED * 4.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, WALK_SPEED * 4.0 * delta)

	var v: Village = GameState.get_village(target_village_id)
	if v == null or v.loyal_to_rival:
		# The village fell to Louhi (or vanished) out from under them.
		recall()
		return
	if v.is_fully_converted():
		return # nothing left to do here; caller may recall()/send_to() elsewhere

	_station_timer -= delta
	if _station_timer <= 0.0:
		_station_timer = STATION_TICK_INTERVAL
		Reach.convert_via_missionary(target_village_id, STATION_GAIN_PER_TICK)


func _finish_return() -> void:
	current_state = State.DONE
	velocity = Vector3.ZERO
	queue_free()


func _update_label() -> void:
	if _label == null:
		return
	var names := {
		State.WALKING: "walking to %s" % String(target_village_id),
		State.STATIONED: "preaching at %s" % String(target_village_id),
		State.RETURNING: "returning to %s" % String(home_village_id),
		State.DONE: "done",
	}
	_label.text = String(names.get(current_state, "?"))
