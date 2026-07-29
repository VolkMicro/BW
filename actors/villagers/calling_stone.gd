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
## Note: `_update_assignment` resolves the ratio against the villagers that
## actually exist as bodies in the scene rather than against this field — see
## the long comment there, and docs/systems/villagers.md "Dial target vs.
## spawned bodies". The field is still written exactly as documented so any
## future reader of it sees what core/village.gd promises.
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


## Utility-AI priority pass: keep already-praying villagers first, then
## pull idle, then family, then working villagers off their jobs to fill the
## target. Only once every healthy villager is already praying does the
## stone start forcing already-collapsed villagers back up — the
## deliberate, documented risk/consequence path (see villager.gd
## force_praying_while_collapsed).
##
## 2nd pass: within each of those tiers, candidates are ordered by
## `Villager.prayer_willingness()` (faith, prayer fatigue, Reach's own
## miracle-fatigue on the &"calling_stone_prayer" method, and Naklon's
## current temper — see villager.gd `_refresh_willingness`), so the people
## who actually come first are the ones who most want (or most fear) to.
## The value is cached on each villager and recomputed on its own staggered
## utility tick, so this sort costs three ~5-element comparisons per village
## per 0.5s and never re-derives anything.
func _update_assignment(village_id: StringName) -> void:
	var village: Village = GameState.get_village(village_id)
	if village == null:
		return
	var all: Array = get_tree().get_nodes_in_group(&"villager").filter(
		func(v): return v.village_id == village_id
	)
	# The dial's ratio applies to the villagers who actually EXIST as bodies in
	# the scene, not to Village.population.
	#
	# Why this changed (honest note, see docs/systems/villagers.md "Dial target
	# vs. spawned bodies"): world/god_view.tscn registers each village with
	# population 12 but spawns 5 real Villager nodes. The old line —
	# `clampi(village.calling_stone_target, 0, village.population)` — therefore
	# asked for round(0.3 * 12) = 4 worshippers out of 5 living bodies, pinned
	# almost the entire visible village to the cairn permanently, and every
	# time one collapsed the shortfall routed straight into
	# force_praying_while_collapsed() — i.e. a slow death spiral nobody asked
	# for. Village.calling_stone_target is still written by set_target_ratio()
	# exactly as core/village.gd documents it (nothing else in the project
	# reads that field); this is only how the stone resolves it against
	# reality each tick.
	var bodies := all.size()
	var target: int = int(round(target_ratio * float(bodies))) if bodies > 0 \
		else clampi(village.calling_stone_target, 0, village.population)
	target = clampi(target, 0, bodies)
	# A villager who is actively fleeing a collapsed Sanctum, or kneeling in
	# mourning over a lost village, cannot be summoned at all for as long as
	# that reaction lasts — and the stone's effective target drops by that
	# many heads rather than reaching deeper into the collapsed pool to make
	# up the difference. Without this, a village would be dragged straight
	# back to the stone half a second after the temple fell on it, and the
	# shortfall would silently route into the force-the-collapsed death path.
	var panicking: Array = all.filter(func(v): return _is_panicking(v))
	target = mini(target, all.size() - panicking.size())

	var praying: Array = all.filter(func(v): return v.current_state == Villager.State.PRAYING)
	var collapsed: Array = all.filter(func(v): return v.current_state == Villager.State.COLLAPSED)
	var idle_first: Array = all.filter(func(v): return v.current_state == Villager.State.IDLE and not _is_panicking(v))
	var family_next: Array = all.filter(func(v): return v.current_state == Villager.State.FAMILY and not _is_panicking(v))
	var working_last: Array = all.filter(func(v): return v.current_state in [
		Villager.State.FISHING, Villager.State.FIELD, Villager.State.WOODCUTTING, Villager.State.BUILDING,
	] and not _is_panicking(v))

	_sort_by_willingness(idle_first)
	_sort_by_willingness(family_next)
	_sort_by_willingness(working_last)
	# Released first = least willing first, so a lowered dial lets go of the
	# most reluctant/most exhausted worshipper rather than an arbitrary one.
	_sort_by_willingness(praying)
	praying.reverse()

	while praying.size() > target:
		var released: Villager = praying.pop_front()
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


## Most willing first.
func _sort_by_willingness(list: Array) -> void:
	if list.size() < 2:
		return
	list.sort_custom(func(a, b): return _pull_priority(a) > _pull_priority(b))


func _pull_priority(v: Villager) -> float:
	var score := v.prayer_willingness()
	if v.current_alert() == Villager.Alert.SHELTER:
		score -= 0.35 # mid-storm they'd rather be under a roof than out at the cairn
	return score


func _is_panicking(v: Villager) -> bool:
	var alert := v.current_alert()
	return alert == Villager.Alert.FLEE or alert == Villager.Alert.MOURN


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
