extends Node3D
class_name Hand
## PACKAGE E — The Hand: the game's only cursor.
##
## The player never gets a mouse arrow. This IS the mouse: a stylized,
## low-poly god-hand built entirely from primitive meshes (no Skeleton3D —
## see docs/systems/hand.md for the tradeoff) that chases a world-space
## target point with a damped spring (never teleports), curls its fingers
## to grip, and can pick up / carry / throw any RigidBody3D within reach.
##
## Integration points other packages rely on:
## - signals `grabbed(node)`, `released(node, velocity)`, `action_refused(reason, world_pos)`
## - `is_holding() -> bool`, `get_held() -> Node3D`
## - `can_act_here() -> bool` and `request_refusal_flash(reason)` so other
##   systems (sigil casting, rites) that ALSO gate on Reach.can_act_at can
##   reuse the same visible-refusal language the Hand uses for grabbing.
## - reads Naklon.unit() every physics frame to drive skin color/emission
##   and the trail particle color. Package D's global shader uniform had
##   not landed in shaders/ at the time this was built (that directory was
##   still empty) so this reads Naklon directly rather than a global
##   uniform; see docs/systems/hand.md for the documented swap-over note.

signal grabbed(node: Node3D)
signal released(node: Node3D, velocity: Vector3)
signal action_refused(reason: StringName, world_pos: Vector3)

## -- Targeting -----------------------------------------------------------
@export var use_own_mouse_raycast: bool = true ## if false, some external
	## controller must call set_target_position() every frame instead.
@export var camera_path: NodePath = ^"" ## optional explicit camera; if
	## empty, falls back to get_viewport().get_camera_3d() each _ready().
@export var ray_length: float = 200.0
@export var hover_height: float = 0.35 ## fallback plane height (world Y)
	## used when the raycast hits nothing (looking at open sky).

## -- Spring/damper motion (the "weight" of the hand) ---------------------
## Deliberately UNDER-damped relative to critical (critical damping for
## stiffness k is 2*sqrt(k)) so the hand overshoots slightly and settles —
## it reads as a heavy, physical thing arriving, not an instant snap.
@export var spring_stiffness: float = 90.0
@export var spring_damping: float = 14.0
@export var max_speed: float = 40.0

## -- Grabbing --------------------------------------------------------------
@export var grab_radius: float = 0.4
@export var grip_response: float = 9.0 ## how fast fingers chase grip target
@export var throw_impulse_multiplier: float = 1.0
@export var throw_spin_factor: float = 0.4

## -- Carry sway: a held object lags/swings behind the hand's own motion
## instead of rigidly following it, so carrying something reads as carrying
## real weight rather than gluing a prop to a socket. Purely a visual
## offset on the held socket (see _update_sway()) — never touches the held
## body's physics state, so release/throw velocity is unaffected. -------
@export var sway_amount: float = 0.32 ## meters of lag per m/s of hand speed
@export var sway_stiffness: float = 46.0
@export var sway_damping: float = 9.0

## -- Naklon-reactive palette (mirrors the shader's defaults; exposed here
## so a designer can retune from the Inspector without editing the shader) --
@export var mercy_color: Color = Color(0.82, 0.85, 0.92, 1.0)
@export var cruelty_color: Color = Color(0.34, 0.05, 0.07, 1.0)

var _camera: Camera3D
var _model: Node3D
var _palm: MeshInstance3D
var _grab_zone: Area3D
var _held_socket: Node3D
var _trail: GPUParticles3D
var _trail_process_material: ParticleProcessMaterial
var _hand_material: ShaderMaterial

var _target_position: Vector3
var _velocity: Vector3 = Vector3.ZERO

var _grip_target: float = 0.0 ## 1.0 while hand_grip is held down
var _grip: float = 0.0 ## smoothed, what the fingers actually show

var _refusal_flash: float = 0.0
var _out_of_reach_amount: float = 0.0

var _held: Node3D = null
var _held_original_parent: Node = null
var _held_was_rigid: bool = false
var _held_grab_offset: Transform3D = Transform3D.IDENTITY ## body's transform relative to _held_socket, captured at grab time
var _held_socket_base_position: Vector3 = Vector3.ZERO
var _sway_offset: Vector3 = Vector3.ZERO
var _sway_velocity: Vector3 = Vector3.ZERO

# Each entry: {mcp: Node3D, pip: Node3D, mcp_max_deg: float, pip_max_deg: float}
var _fingers: Array[Dictionary] = []


func _ready() -> void:
	_target_position = global_position
	_resolve_camera()
	_build_hand_model()


func _resolve_camera() -> void:
	if camera_path != ^"":
		_camera = get_node_or_null(camera_path) as Camera3D
	if _camera == null:
		_camera = get_viewport().get_camera_3d()


func _physics_process(delta: float) -> void:
	if _camera == null and use_own_mouse_raycast:
		_resolve_camera()

	if use_own_mouse_raycast:
		_target_position = _raycast_mouse_target()

	_integrate_spring(delta)
	_handle_grip_input()

	var reach_ok := can_act_here()
	_out_of_reach_amount = move_toward(_out_of_reach_amount, 0.0 if reach_ok else 1.0, delta * 3.0)
	_refusal_flash = maxf(0.0, _refusal_flash - delta * 2.2)

	# Fingers can't fully close outside Reach even if the player is holding
	# the grip button down — a visible "can't grab here" rather than a
	# silent no-op.
	var effective_grip_target := _grip_target
	if not reach_ok:
		effective_grip_target = minf(_grip_target, 0.18)
	_grip = move_toward(_grip, effective_grip_target, delta * grip_response)

	_apply_finger_curl()
	_update_material()
	_update_trail()
	_update_sway(delta)


## -- Targeting -------------------------------------------------------------

func _raycast_mouse_target() -> Vector3:
	if _camera == null:
		return _target_position
	var mouse_pos := get_viewport().get_mouse_position()
	var from := _camera.project_ray_origin(mouse_pos)
	var dir := _camera.project_ray_normal(mouse_pos)
	var to := from + dir * ray_length

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var result := space_state.intersect_ray(query)
	if result.has("position"):
		return result.position

	var plane := Plane(Vector3.UP, hover_height)
	var hit = plane.intersects_ray(from, dir)
	if hit != null:
		return hit
	return _target_position


## Lets an external controller (a future camera rig, a cutscene, a test)
## drive the hand instead of its own mouse raycast.
func set_target_position(pos: Vector3) -> void:
	_target_position = pos


func get_target_position() -> Vector3:
	return _target_position


## -- Spring motion -----------------------------------------------------------

func _integrate_spring(delta: float) -> void:
	var disp := _target_position - global_position
	var accel := disp * spring_stiffness - _velocity * spring_damping
	_velocity += accel * delta
	if _velocity.length() > max_speed:
		_velocity = _velocity.limit_length(max_speed)
	global_position += _velocity * delta


func get_hand_velocity() -> Vector3:
	return _velocity


## -- Reach gating (shared language other packages can reuse) ----------------

func can_act_here() -> bool:
	return Reach.can_act_at(global_position)


## Lets another system (e.g. package F's sigil casting, which also gates on
## Reach.can_act_at) play the same visible refusal the Hand uses, so the
## player gets one consistent "no" language instead of two.
func request_refusal_flash(reason: StringName = &"generic_out_of_reach") -> void:
	_refusal_flash = 1.0
	action_refused.emit(reason, global_position)


## -- Grabbing / carrying / throwing ------------------------------------------

func _handle_grip_input() -> void:
	if Input.is_action_pressed(&"hand_grip"):
		_grip_target = 1.0
	else:
		_grip_target = 0.0

	if Input.is_action_just_pressed(&"hand_grip"):
		_try_grab()
	elif Input.is_action_just_released(&"hand_grip"):
		_release_held()


func _try_grab() -> void:
	if _held != null:
		return
	if not can_act_here():
		request_refusal_flash(&"grab_out_of_reach")
		return

	var candidate := _find_nearest_grabbable()
	if candidate != null:
		_do_grab(candidate)


func _find_nearest_grabbable() -> Node3D:
	var best: Node3D = null
	var best_dist := INF
	for body in _grab_zone.get_overlapping_bodies():
		if body == self or body is StaticBody3D:
			continue
		if not (body is RigidBody3D or body.is_in_group(&"grabbable")):
			continue
		var d := global_position.distance_to((body as Node3D).global_position)
		if d < best_dist:
			best_dist = d
			best = body
	return best


func _do_grab(body: Node3D) -> void:
	_held = body
	_held_original_parent = body.get_parent()
	_held_was_rigid = body is RigidBody3D

	# Preserve exactly where/how the object was grabbed (position AND
	# rotation, relative to the socket) rather than snapping it to a fixed
	# identity pose — replaces the earlier documented simplification (see
	# docs/systems/hand.md's old "Scoped out" note on this). Captured
	# BEFORE reparenting, while body.global_transform still reflects its
	# real pre-grab pose.
	_held_grab_offset = _held_socket.global_transform.affine_inverse() * body.global_transform

	if _held_was_rigid:
		var rb := body as RigidBody3D
		rb.freeze = true
		rb.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO

	if _held_original_parent != null:
		_held_original_parent.remove_child(body)
	_held_socket.add_child(body)
	body.transform = _held_grab_offset

	grabbed.emit(body)
	Voices.react(&"hand_grabbed_object", {"node_name": body.name})


func _release_held() -> void:
	if _held == null:
		return
	var body := _held
	var throw_velocity := _velocity * throw_impulse_multiplier

	var world_xform := body.global_transform
	_held_socket.remove_child(body)
	var target_parent: Node = _held_original_parent if is_instance_valid(_held_original_parent) else get_tree().current_scene
	target_parent.add_child(body)
	body.global_transform = world_xform

	if _held_was_rigid:
		var rb := body as RigidBody3D
		rb.freeze = false
		rb.linear_velocity = throw_velocity
		rb.angular_velocity = throw_velocity.cross(Vector3.UP) * throw_spin_factor

	_held = null
	_held_original_parent = null
	released.emit(body, throw_velocity)
	Voices.react(&"hand_threw_object", {"node_name": body.name, "speed": throw_velocity.length()})


func is_holding() -> bool:
	return _held != null


func get_held() -> Node3D:
	return _held


## -- Procedural model --------------------------------------------------------
## Built entirely from PrimitiveMesh instances at runtime rather than an
## authored/skinned mesh — see docs/systems/hand.md, "Skeleton3D vs rigid
## primitive chain" for the tradeoff. Fingers extend along local +Z at
## rest; curling rotates each joint by a NEGATIVE angle around local X,
## which (single-axis Euler rotation, so composition order doesn't matter)
## tilts +Z toward -Y — i.e. downward, under the palm, exactly the
## direction a closing fist should curl toward, derived from the standard
## right-hand rotation matrix, not guessed.

func _build_hand_model() -> void:
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)

	_hand_material = ShaderMaterial.new()
	_hand_material.shader = preload("res://actors/hand/hand_material.gdshader")
	_hand_material.set_shader_parameter("naklon_unit", Naklon.unit())
	_hand_material.set_shader_parameter("grip", 0.0)
	_hand_material.set_shader_parameter("refusal", 0.0)
	_hand_material.set_shader_parameter("out_of_reach", 0.0)
	_hand_material.set_shader_parameter("mercy_color", mercy_color)
	_hand_material.set_shader_parameter("cruelty_color", cruelty_color)

	# Palm: flattened box, thin along Y, so it already reads as a
	# hand-hovering-palm-down shape without any extra rotation.
	var palm_mesh := BoxMesh.new()
	palm_mesh.size = Vector3(0.10, 0.032, 0.11)
	_palm = MeshInstance3D.new()
	_palm.name = "Palm"
	_palm.mesh = palm_mesh
	_palm.material_override = _hand_material
	_model.add_child(_palm)

	# Wrist stub, purely cosmetic, gives the palm somewhere to "attach" to.
	var wrist_mesh := CapsuleMesh.new()
	wrist_mesh.radius = 0.028
	wrist_mesh.height = 0.09
	var wrist := MeshInstance3D.new()
	wrist.name = "Wrist"
	wrist.mesh = wrist_mesh
	wrist.material_override = _hand_material
	wrist.rotation_degrees = Vector3(90, 0, 0)
	wrist.position = Vector3(0, 0, -0.09)
	_model.add_child(wrist)

	var finger_defs := [
		{"name": "Index", "pos": Vector3(-0.033, 0.006, 0.05), "rot": Vector3.ZERO, "l1": 0.045, "l2": 0.032, "r": 0.011, "mcp_max": 80.0, "pip_max": 95.0},
		{"name": "Middle", "pos": Vector3(-0.011, 0.006, 0.052), "rot": Vector3.ZERO, "l1": 0.050, "l2": 0.036, "r": 0.011, "mcp_max": 85.0, "pip_max": 100.0},
		{"name": "Ring", "pos": Vector3(0.011, 0.006, 0.05), "rot": Vector3.ZERO, "l1": 0.046, "l2": 0.033, "r": 0.010, "mcp_max": 82.0, "pip_max": 97.0},
		{"name": "Pinky", "pos": Vector3(0.033, 0.004, 0.046), "rot": Vector3.ZERO, "l1": 0.036, "l2": 0.026, "r": 0.009, "mcp_max": 78.0, "pip_max": 90.0},
	]
	for def in finger_defs:
		_build_finger(def)

	# Thumb: angled outward/forward from the side of the palm so it reads
	# as opposable rather than a fifth identical finger.
	_build_finger({
		"name": "Thumb",
		"pos": Vector3(0.052, -0.004, -0.01),
		"rot": Vector3(0, -55.0, 30.0),
		"l1": 0.040, "l2": 0.030, "r": 0.013,
		"mcp_max": 50.0, "pip_max": 60.0,
	})

	_grab_zone = Area3D.new()
	_grab_zone.name = "GrabZone"
	var grab_shape := SphereShape3D.new()
	grab_shape.radius = grab_radius
	var grab_col := CollisionShape3D.new()
	grab_col.shape = grab_shape
	_grab_zone.add_child(grab_col)
	_grab_zone.position = Vector3(0, -0.05, 0.06)
	_model.add_child(_grab_zone)

	_held_socket = Node3D.new()
	_held_socket.name = "HeldSocket"
	_held_socket_base_position = Vector3(0, -0.05, 0.06)
	_held_socket.position = _held_socket_base_position
	_model.add_child(_held_socket)

	_build_trail()


func _build_finger(def: Dictionary) -> void:
	var mcp := Node3D.new()
	mcp.name = "MCP_%s" % def.name
	mcp.position = def.pos
	mcp.rotation_degrees = def.rot
	_model.add_child(mcp)

	var seg1_mesh := CapsuleMesh.new()
	seg1_mesh.radius = def.r
	seg1_mesh.height = maxf(def.l1, def.r * 2.0 + 0.004)
	var seg1 := MeshInstance3D.new()
	seg1.name = "Seg1"
	seg1.mesh = seg1_mesh
	seg1.material_override = _hand_material
	seg1.rotation_degrees = Vector3(90, 0, 0)
	seg1.position = Vector3(0, 0, def.l1 * 0.5)
	mcp.add_child(seg1)

	var pip := Node3D.new()
	pip.name = "PIP_%s" % def.name
	pip.position = Vector3(0, 0, def.l1)
	mcp.add_child(pip)

	var seg2_mesh := CapsuleMesh.new()
	seg2_mesh.radius = def.r * 0.85
	seg2_mesh.height = maxf(def.l2, seg2_mesh.radius * 2.0 + 0.004)
	var seg2 := MeshInstance3D.new()
	seg2.name = "Seg2"
	seg2.mesh = seg2_mesh
	seg2.material_override = _hand_material
	seg2.rotation_degrees = Vector3(90, 0, 0)
	seg2.position = Vector3(0, 0, def.l2 * 0.5)
	pip.add_child(seg2)

	_fingers.append({
		"mcp": mcp,
		"pip": pip,
		"mcp_max_deg": def.mcp_max,
		"pip_max_deg": def.pip_max,
	})


func _apply_finger_curl() -> void:
	for f in _fingers:
		var mcp: Node3D = f.mcp
		var pip: Node3D = f.pip
		mcp.rotation.x = -deg_to_rad(f.mcp_max_deg) * _grip
		pip.rotation.x = -deg_to_rad(f.pip_max_deg) * _grip


func _build_trail() -> void:
	_trail = GPUParticles3D.new()
	_trail.name = "Trail"
	_trail.amount = 24
	_trail.lifetime = 0.6
	_trail.local_coords = false # particles stay in world space -> a real trail behind hand motion
	_trail.emitting = true

	_trail_process_material = ParticleProcessMaterial.new()
	_trail_process_material.direction = Vector3(0, 1, 0)
	_trail_process_material.spread = 20.0
	_trail_process_material.gravity = Vector3(0, 0.04, 0)
	_trail_process_material.initial_velocity_min = 0.03
	_trail_process_material.initial_velocity_max = 0.12
	_trail_process_material.scale_min = 0.35
	_trail_process_material.scale_max = 0.85
	_trail_process_material.color = mercy_color
	_trail.process_material = _trail_process_material

	var trail_mesh := SphereMesh.new()
	trail_mesh.radius = 0.014
	trail_mesh.height = 0.028
	var trail_mat := StandardMaterial3D.new()
	trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_mat.vertex_color_use_as_albedo = true
	trail_mat.albedo_color = Color(1, 1, 1, 0.55)
	trail_mesh.material = trail_mat
	_trail.draw_pass_1 = trail_mesh

	_model.add_child(_trail)
	_trail.position = Vector3(0, -0.02, 0.08)


func _update_material() -> void:
	var unit := Naklon.unit()
	_hand_material.set_shader_parameter("naklon_unit", unit)
	_hand_material.set_shader_parameter("grip", _grip)
	_hand_material.set_shader_parameter("refusal", _refusal_flash)
	_hand_material.set_shader_parameter("out_of_reach", _out_of_reach_amount)


func _update_trail() -> void:
	var unit := Naklon.unit()
	_trail_process_material.color = mercy_color.lerp(cruelty_color, unit)
	_trail.emitting = _velocity.length() > 0.15


## Held objects lag behind the hand's own spring motion instead of rigidly
## tracking it — a damped spring pulling _sway_offset toward
## `-_velocity * sway_amount` (so a fast hand motion drags whatever it's
## carrying backward/behind it, like real inertia) that relaxes back to
## zero once nothing is held. Purely visual (offsets _held_socket's local
## position only) — never touches the held RigidBody3D's own physics state,
## so _release_held()'s throw velocity is computed from the hand's own
## _velocity exactly as before, unaffected by this.
func _update_sway(delta: float) -> void:
	var target := Vector3.ZERO
	if _held != null:
		target = -_velocity * sway_amount
	var accel := (target - _sway_offset) * sway_stiffness - _sway_velocity * sway_damping
	_sway_velocity += accel * delta
	_sway_offset += _sway_velocity * delta
	_held_socket.position = _held_socket_base_position + _sway_offset
