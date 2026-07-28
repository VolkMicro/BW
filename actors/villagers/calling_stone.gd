extends StaticBody3D
class_name CallingStone
## Package G — the Calling Stone. A fixed cairn with a liftable dial on top;
## the dial's height (0..1 ratio) sets how many villagers, across every
## linked village, are pulled off their jobs into the praying state.
##
## Intended integration point for actors/hand/ (package E, not yet built at
## the time this was written): call `hand_drag(delta_ratio)` once per frame
## while the Hand is gripping the dial, with delta_ratio derived from however
## far the Hand moved the grip point that frame. Until the Hand exists this
## script also supports a standalone left-click-and-drag-vertically mouse
## fallback so the mechanic is testable/screenshot-able on its own.
##
## Public API:
##   calling_stone.target_ratio (float 0..1, use set_target_ratio to write)
##   calling_stone.set_target_ratio(r: float) -> void
##   calling_stone.hand_drag(delta_ratio: float) -> void
##   calling_stone.get_kneel_spot(villager: Villager) -> Vector3

@export var village_ids: Array[StringName] = []
@export var drag_sensitivity: float = 0.004 # ratio change per screen pixel of vertical drag

const RETARGET_INTERVAL := 0.5
const KNEEL_BASE_RADIUS := 1.8
const KNEEL_RADIUS_GROWTH := 0.35

var target_ratio: float = 0.0

var _praying_by_village: Dictionary = {} # StringName -> Array[Villager]
var _retarget_timer: float = 0.0
var _dragging: bool = false

@onready var _dial: Node3D = $Dial


func _ready() -> void:
	input_ray_pickable = true
	get_viewport().physics_object_picking = true
	for id in village_ids:
		_praying_by_village[id] = []
	_update_dial_visual()


## Sets the summon ratio directly (0..1) and propagates each linked village's
## calling_stone_target = round(ratio * population), per core/village.gd.
func set_target_ratio(r: float) -> void:
	target_ratio = clampf(r, 0.0, 1.0)
	for id in village_ids:
		var v: Village = GameState.get_village(id)
		if v:
			v.calling_stone_target = int(round(target_ratio * v.population))
	_update_dial_visual()


## Called by whatever is dragging the stone's dial (the Hand, or this
## script's own mouse fallback) with a signed ratio delta for this frame.
func hand_drag(delta_ratio: float) -> void:
	set_target_ratio(target_ratio + delta_ratio)


func get_kneel_spot(villager: Villager) -> Vector3:
	var list: Array = _praying_by_village.get(villager.village_id, [])
	var idx := list.find(villager)
	if idx == -1:
		idx = list.size()
	var count := maxi(list.size(), 1)
	var angle := TAU * float(idx) / float(count)
	var radius := KNEEL_BASE_RADIUS + KNEEL_RADIUS_GROWTH * float(count) / 6.0
	return global_position + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)


func _process(delta: float) -> void:
	_retarget_timer -= delta
	if _retarget_timer <= 0.0:
		_retarget_timer = RETARGET_INTERVAL
		for id in village_ids:
			_update_assignment(id)


## Utility-AI-ish priority pass: keep already-praying villagers first, then
## pull idle, then family, then working villagers off their jobs to fill the
## target. Only once every healthy villager is already praying does the
## stone start forcing already-collapsed villagers back up — the
## deliberate, documented risk/consequence path (see villager.gd
## force_praying_while_collapsed).
func _update_assignment(village_id: StringName) -> void:
	var village: Village = GameState.get_village(village_id)
	if village == null:
		return
	var target: int = clampi(village.calling_stone_target, 0, village.population)

	var all: Array = get_tree().get_nodes_in_group(&"villager").filter(
		func(v): return v.village_id == village_id
	)
	var praying: Array = all.filter(func(v): return v.current_state == Villager.State.PRAYING)
	var collapsed: Array = all.filter(func(v): return v.current_state == Villager.State.COLLAPSED)
	var idle_first: Array = all.filter(func(v): return v.current_state == Villager.State.IDLE)
	var family_next: Array = all.filter(func(v): return v.current_state == Villager.State.FAMILY)
	var working_last: Array = all.filter(func(v): return v.current_state in [
		Villager.State.FISHING, Villager.State.FIELD, Villager.State.WOODCUTTING, Villager.State.BUILDING,
	])

	while praying.size() > target:
		var released: Villager = praying.pop_back()
		released.stop_praying()

	var slot := praying.size()
	for v in idle_first + family_next + working_last:
		if slot >= target:
			break
		v.start_praying(self)
		slot += 1

	if slot < target:
		for v in collapsed:
			if slot >= target:
				break
			v.force_praying_while_collapsed()
			slot += 1

	_praying_by_village[village_id] = all.filter(func(v): return v.current_state == Villager.State.PRAYING)


func _update_dial_visual() -> void:
	if _dial:
		_dial.position.y = 0.4 + target_ratio * 1.4


func _input_event(_camera: Camera3D, event: InputEvent, _event_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed


func _input(event: InputEvent) -> void:
	if _dragging and event is InputEventMouseMotion:
		hand_drag(-event.relative.y * drag_sensitivity)
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = false
