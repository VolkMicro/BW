extends Node3D
class_name CameraRig
## Package T — one real Camera3D plus a Tween-driven transition helper that
## cuts or eases between god-view, a Sanctum-interior framing, and
## (defensively) a duel-arena framing, all within one running scene tree —
## nothing in this file calls `get_tree().change_scene_to_file()` or loads a
## PackedScene, per core/game_state.gd's own stated constraint: "the camera
## jumps from god-view to Sanctum-interior to duel arena without a loading
## screen and everything has to already agree on the world state."
##
## DELIBERATELY GENERIC: this script does not import or type-check against
## `Sanctum` or any duel-arena class. Every framing is ultimately just a
## `Transform3D` (or a `Node3D` whose global position/children are sampled
## once to build one). The `frame_*` convenience wrappers below read a
## couple of well-known node NAMES (`InteriorAnchor`, `EntranceMarker`) off
## whatever `Node3D` is handed to them, duck-typed, so this rig works
## whether or not `actors/avatar/combat/` (package L) happens to be
## instanced in the current scene at all — see docs/systems/
## sanctum_interior_ui.md "Scoped out" for exactly what that does and
## doesn't guarantee.
##
## INTERIOR "WALKING": while in SANCTUM_INTERIOR mode, ui_up/ui_down/
## ui_left/ui_right (Godot's built-in default UI actions, arrow keys —
## deliberately NOT a new custom InputMap action, since project.godot is
## foundation-owned per docs/systems/OWNERSHIP.md) strafe/move the camera on
## the floor plane, clamped to the Sanctum's own interior box (read from the
## `Node3D` passed to `frame_sanctum_interior`, in ITS local space, so the
## clamp still works regardless of where in the world that Sanctum sits).
##
## PROXY BODY FOR TRIGGER DETECTION: this rig has no player-character body,
## only a flying Camera3D — but Sanctum's own OfferingTrigger
## (world/sanctum/sanctum.gd) and this package's own RepairPoint
## (world/sanctum_interior/interior_dressing.gd) are both physics `Area3D`s
## that fire `body_entered`/`body_exited` for a real `PhysicsBody3D`, not for
## an arbitrary `Node3D`. `PlayerProxy` (an `AnimatableBody3D` — the node
## type Godot intends for a collider that's moved by script rather than by
## the physics engine) is kept glued to the camera's position every physics
## frame purely so those two triggers actually fire; it has no gameplay
## meaning of its own.

signal mode_changed(old_mode: StringName, new_mode: StringName)
signal transition_started(mode: StringName)
signal transition_finished(mode: StringName)

const MODE_GOD_VIEW := &"god_view"
const MODE_SANCTUM_INTERIOR := &"sanctum_interior"
const MODE_DUEL_ARENA := &"duel_arena"

const DEFAULT_TRANSITION_SECONDS := 0.9
const INTERIOR_MOVE_SPEED := 1.6 # m/s — a slow deliberate walk, not a sprint
const INTERIOR_BOUNDS_MARGIN := 0.4 # meters kept clear of the interior box's own edge
## Sanctum-local floor/ceiling the walk clamp keeps the camera between —
## see world/sanctum/sanctum.gd's InteriorAnchor doc comment and
## docs/systems/sanctum.md "floor height y≈0.6 local-y, ceiling ≈1.9m
## above that" (so ceiling ≈ 2.5 local-y); kept with a small margin here.
const INTERIOR_FLOOR_Y := 0.6
const INTERIOR_CEILING_Y := 2.3
const INTERIOR_HALF_EXTENT := 3.1 # the ~6.2m x/z interior square, half-width

@onready var camera: Camera3D = $Camera3D
@onready var _player_proxy: AnimatableBody3D = $PlayerProxy

var mode: StringName = MODE_GOD_VIEW
var _tween: Tween
var _interior_bounds_node: Node3D = null # local-space reference for the walk clamp

func _ready() -> void:
	camera.current = true

func _physics_process(delta: float) -> void:
	if mode == MODE_SANCTUM_INTERIOR:
		_process_interior_movement(delta)
	_player_proxy.global_position = camera.global_position

func _process_interior_movement(delta: float) -> void:
	var move := Vector3.ZERO
	if Input.is_action_pressed(&"ui_up"):
		move.z -= 1.0
	if Input.is_action_pressed(&"ui_down"):
		move.z += 1.0
	if Input.is_action_pressed(&"ui_left"):
		move.x -= 1.0
	if Input.is_action_pressed(&"ui_right"):
		move.x += 1.0
	if move == Vector3.ZERO:
		return
	move = move.normalized() * INTERIOR_MOVE_SPEED * delta
	var new_pos := camera.global_position + camera.global_transform.basis * move
	if _interior_bounds_node:
		new_pos = _clamp_to_interior(new_pos)
	camera.global_position = new_pos

func _clamp_to_interior(world_pos: Vector3) -> Vector3:
	var local := _interior_bounds_node.global_transform.affine_inverse() * world_pos
	var half := INTERIOR_HALF_EXTENT - INTERIOR_BOUNDS_MARGIN
	local.x = clampf(local.x, -half, half)
	local.z = clampf(local.z, -half, half)
	local.y = clampf(local.y, INTERIOR_FLOOR_Y, INTERIOR_CEILING_Y)
	return _interior_bounds_node.global_transform * local

## Instant cut — no tween, no loading screen, one frame.
func cut_to(xform: Transform3D, new_mode: StringName = &"") -> void:
	_kill_tween()
	camera.global_transform = xform
	_set_mode(new_mode)

## Eased cut over `duration` seconds via a real, running Tween on
## `camera`'s `global_transform` (Godot 4's Tween interpolates Transform3D
## properties directly — origin lerp + basis slerp — so this is a real
## interpolated move+look, not a manually hand-rolled one).
func transition_to(xform: Transform3D, new_mode: StringName = &"", duration: float = DEFAULT_TRANSITION_SECONDS) -> void:
	_kill_tween()
	var target_mode: StringName = new_mode if new_mode != &"" else mode
	transition_started.emit(target_mode)
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(camera, "global_transform", xform, duration)
	_tween.tween_callback(_on_transition_done.bind(new_mode))

func _on_transition_done(new_mode: StringName) -> void:
	_set_mode(new_mode)
	transition_finished.emit(mode)

func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()

func _set_mode(new_mode: StringName) -> void:
	if new_mode == &"" or new_mode == mode:
		return
	var old := mode
	mode = new_mode
	mode_changed.emit(old, mode)

# ---------------------------------------------------------------------------
# Convenience framings. Still generic: no hard class dependency on Sanctum
# or DuelArena, only duck-typed child-node lookups by name.
# ---------------------------------------------------------------------------

## Frames a static overview shot. Caller supplies the transform (e.g. copied
## from world/god_view.tscn's own GodCamera, or anything a future
## campaign/ pass wants) — this rig doesn't instance or depend on
## world/god_view.tscn itself.
func frame_god_view(xform: Transform3D, instant: bool = false, duration: float = DEFAULT_TRANSITION_SECONDS) -> void:
	_interior_bounds_node = null
	if instant:
		cut_to(xform, MODE_GOD_VIEW)
	else:
		transition_to(xform, MODE_GOD_VIEW, duration)

## Frames just inside a Sanctum's doorway, looking toward its
## InteriorAnchor. Reads the real `InteriorAnchor`/`EntranceMarker` child
## nodes off whatever Node3D is passed (world/sanctum/sanctum.gd's own
## Marker3D names, sanctum.gd:38-50) rather than deriving an offset from
## the building's root transform. `sanctum` is typed Node3D, not `Sanctum`
## — this still works given any node that happens to have children with
## those two names.
func frame_sanctum_interior(sanctum: Node3D, instant: bool = false, duration: float = DEFAULT_TRANSITION_SECONDS) -> void:
	var anchor := sanctum.get_node_or_null("InteriorAnchor") as Node3D
	if anchor == null:
		push_warning("CameraRig.frame_sanctum_interior: no InteriorAnchor child on %s" % sanctum.name)
		return
	var entrance := sanctum.get_node_or_null("EntranceMarker") as Node3D
	var eye: Vector3 = entrance.global_position if entrance else anchor.global_position + Vector3(0, 0.5, 2.0)
	eye.y = anchor.global_position.y + 1.1 # a standing eye height above the interior floor
	var xform := Transform3D(Basis.IDENTITY, eye).looking_at(anchor.global_position, Vector3.UP)
	_interior_bounds_node = sanctum
	if instant:
		cut_to(xform, MODE_SANCTUM_INTERIOR)
	else:
		transition_to(xform, MODE_SANCTUM_INTERIOR, duration)

## Frames a duel from a generic "focus" Node3D. Deliberately does not
## assume `actors/avatar/combat/`'s `DuelArena` shape (package L) — that
## directory may or may not be instanced in the current scene at all. Backs
## the camera off `distance` meters (and `height` meters up) from the
## focus node's own position and looks back at it, so a real `DuelArena`
## node, one of its fighters, or a bare stand-in `Marker3D` all work
## identically. See docs/systems/sanctum_interior_ui.md "Scoped out."
func frame_duel_arena_focus(focus: Node3D, distance: float = 9.0, height: float = 5.0, instant: bool = false, duration: float = DEFAULT_TRANSITION_SECONDS) -> void:
	var origin := focus.global_position
	var eye := origin + Vector3(0, height, distance)
	var xform := Transform3D(Basis.IDENTITY, eye).looking_at(origin, Vector3.UP)
	_interior_bounds_node = null
	if instant:
		cut_to(xform, MODE_DUEL_ARENA)
	else:
		transition_to(xform, MODE_DUEL_ARENA, duration)
