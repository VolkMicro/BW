extends Node3D
class_name RiverNetwork
## Traces watercourses down an IslandTerrain and builds a RiverSurface ribbon
## along each one.
##
## WHY THE COURSES ARE NOT AUTHORED
##
## The obvious way to put a river on an island is to hand-draw a spline and
## drop water on it. That reads wrong immediately, because a real river is not
## a shape laid over terrain — it is the terrain's own drainage, and the eye
## knows the difference even when it cannot say why. Water that crosses a
## ridge, or runs along a contour instead of down it, looks painted on.
##
## So the courses here are found, not drawn. `IslandGenerator` already
## simulates hydraulic erosion (see its own header) and records, per cell, how
## much water crossed it — the flow map. That map is exactly "where the water
## went", so:
##
##   1. Seed at the highest-flow cells that are well inland and above a
##      minimum height — the places the erosion pass itself decided were
##      catchments.
##   2. Walk downhill from each seed by steepest descent, sampling the same
##      smoothed heightmap the visible mesh is built from, so the course
##      follows the ground the player can actually see.
##   3. Stop at sea level. The river ends where the island does.
##
## The result is guaranteed consistent with the valleys carved into the mesh,
## because both come from the same simulation. A river runs in a valley here
## not because it was placed there but because the valley is where the water
## ran.
##
## COST: entirely at startup. Tracing is a few hundred height samples per
## river; each RiverSurface then builds one static ribbon mesh. Nothing here
## has a _process(). Target hardware is a laptop with integrated graphics
## (docs/systems/performance_lowspec.md), so the counts are deliberately
## small — two or three real rivers read as "this island has rivers" far
## better than a dozen thin ones.

signal rivers_built(count: int)

const RIVER_SURFACE := preload("res://world/ocean/river_surface.gd")

@export var terrain_path: NodePath
@export var auto_build_on_ready: bool = true

@export_group("How many, and where they start")
## Rivers to attempt. Each needs its own catchment, so asking for more than
## the island has valleys simply yields fewer.
@export var river_count: int = 3
## A seed must be at least this high, so rivers start in the uplands rather
## than trickling out of a beach.
@export var min_source_height: float = 12.0
## And no closer than this to an existing river's source, so all three do not
## come out of the same gully.
@export var min_source_separation: float = 70.0
## Flow-map value a cell needs to be considered a catchment at all.
@export_range(0.0, 1.0) var min_source_flow: float = 0.12

@export_group("Course")
## Metres per tracing step. Smaller follows the ground more closely and costs
## more samples; the ribbon is smoothed by a Catmull-Rom afterwards anyway.
@export var step_length: float = 4.0
@export var max_steps: int = 400
## How much of the previous direction is kept at each step. Without this the
## course zig-zags between adjacent cells on gentle ground.
@export_range(0.0, 0.99) var course_inertia: float = 0.55
## Consecutive uphill steps tolerated before a course is abandoned. See the
## note in _trace_course(): this is what lets a river cross a sediment lip
## instead of dying in the first one the erosion pass left behind.
@export var max_climb_steps: int = 14
## Every Nth traced point becomes a ribbon control point.
@export var control_point_stride: int = 2

@export_group("Ribbon")
## Width at the source and at the mouth — a river widens as it goes.
@export var source_width: float = 4.0
@export var mouth_width: float = 15.0
## Lifted this far above the terrain. This is NOT just z-fight insurance:
## RiverSurface smooths the control points with a Catmull-Rom, and a spline
## cuts corners, so through a tight valley bend the ribbon's centre passes
## INSIDE the turn — i.e. below the ground it is supposed to lie on. At 0.35 m
## the rivers were being buried by their own smoothing and were invisible from
## god view. A denser control_point_stride helps too, but some lift is the
## honest fix; the surface reads as water in a channel rather than floating.
@export var surface_lift: float = 1.1

var _terrain: Node = null
var _rivers: Array[Node] = []

func _ready() -> void:
	if auto_build_on_ready:
		build()

## Rebuilds every river from scratch. Safe to call again at runtime.
func build() -> void:
	_clear()
	_terrain = _resolve_terrain()
	if _terrain == null:
		push_warning("RiverNetwork: no terrain with sample_height() found; no rivers built.")
		return
	var generator = _terrain.get("generator")
	if generator == null or not generator.has_method("flow_at"):
		push_warning("RiverNetwork: terrain has no erosion flow map; no rivers built.")
		return

	var sources := _find_sources(generator)
	for src in sources:
		var course := _trace_course(src)
		# A course that gave up after a few metres is a puddle, not a river.
		if course.size() < 8:
			continue
		_build_ribbon(course)
	rivers_built.emit(_rivers.size())

func get_river_count() -> int:
	return _rivers.size()

# ---------------------------------------------------------------------------
# Finding catchments
# ---------------------------------------------------------------------------

## Scans the flow map on a coarse grid and picks the strongest cells that are
## high enough, far enough apart, and not already below the waterline.
func _find_sources(generator: Object) -> Array[Vector2]:
	var size: float = float(_terrain.get("size_meters"))
	var half := size * 0.5
	# Coarse scan: the flow map is smooth enough that sampling every few
	# metres finds the same catchments as sampling every cell, for a fraction
	# of the calls.
	var scan_step := maxf(size / 96.0, 2.0)
	var candidates: Array = []
	var x := -half
	while x <= half:
		var z := -half
		while z <= half:
			var h: float = _terrain.call("sample_height", Vector2(x, z))
			if h >= min_source_height:
				var f: float = generator.call("flow_at", x, z)
				if f >= min_source_flow:
					# Prefer high flow, but break ties toward higher ground so
					# rivers get a decent run rather than starting mid-slope.
					candidates.append({"xz": Vector2(x, z), "score": f + h * 0.004})
			z += scan_step
		x += scan_step

	candidates.sort_custom(func(a, b): return a.score > b.score)

	var chosen: Array[Vector2] = []
	for c in candidates:
		if chosen.size() >= river_count:
			break
		var ok := true
		for taken in chosen:
			if taken.distance_to(c.xz) < min_source_separation:
				ok = false
				break
		if ok:
			chosen.append(c.xz)
	return chosen

# ---------------------------------------------------------------------------
# Tracing a course
# ---------------------------------------------------------------------------

## Steepest descent from `start`, with inertia, sampling the real smoothed
## terrain. Returns world-space points; stops at the sea, at the map edge, or
## when the ground stops going down.
func _trace_course(start: Vector2) -> PackedVector3Array:
	var out := PackedVector3Array()
	var size: float = float(_terrain.get("size_meters"))
	var half := size * 0.5
	var pos := start
	var dir := Vector2.ZERO
	var climbing := 0
	var last_h: float = _terrain.call("sample_height", pos)

	for _i in max_steps:
		var h: float = _terrain.call("sample_height", pos)
		if h <= 0.0:
			# Reached the sea. Add one last point at the waterline so the
			# ribbon actually meets the ocean instead of stopping short.
			out.append(Vector3(pos.x, 0.0, pos.y))
			break
		if absf(pos.x) > half or absf(pos.y) > half:
			break
		out.append(Vector3(pos.x, h + surface_lift, pos.y))

		# Gradient from four samples around the current point.
		var e := step_length * 0.75
		var hx1: float = _terrain.call("sample_height", pos + Vector2(e, 0.0))
		var hx0: float = _terrain.call("sample_height", pos - Vector2(e, 0.0))
		var hz1: float = _terrain.call("sample_height", pos + Vector2(0.0, e))
		var hz0: float = _terrain.call("sample_height", pos - Vector2(0.0, e))
		var grad := Vector2(hx1 - hx0, hz1 - hz0)
		if grad.length() < 0.0001:
			# Dead flat — a lake, in effect. Keep drifting on inertia for a
			# few steps; if nothing changes the loop's downhill check ends it.
			if dir == Vector2.ZERO:
				break
		else:
			dir = (dir * course_inertia - grad.normalized() * (1.0 - course_inertia)).normalized()

		if dir == Vector2.ZERO:
			break
		pos += dir * step_length

		var new_h: float = _terrain.call("sample_height", pos)
		# Rivers must be allowed to cross small rises. The erosion pass
		# deposits sediment, which leaves shallow lips and closed pits all
		# over an otherwise perfectly drained surface; a tracer that stops at
		# the first uphill step dies in the first one it meets. Measured: with
		# a hard break, all three courses ended after 60-90 m on a 320 m
		# island. So climbing is tolerated and only a SUSTAINED climb ends the
		# river — the same reasoning real hydrology solvers use when they
		# flood a pit and carry on from its outlet, done cheaply here by just
		# coasting on inertia until the ground falls away again.
		if new_h > last_h + 0.05:
			climbing += 1
			if climbing > max_climb_steps:
				break
		else:
			climbing = 0
		last_h = new_h

	return out

# ---------------------------------------------------------------------------
# Building the ribbon
# ---------------------------------------------------------------------------

func _build_ribbon(course: PackedVector3Array) -> void:
	var controls := PackedVector3Array()
	for i in range(0, course.size(), maxi(control_point_stride, 1)):
		controls.append(course[i])
	# Always include the mouth, whatever the stride worked out to.
	if controls.is_empty() or controls[controls.size() - 1] != course[course.size() - 1]:
		controls.append(course[course.size() - 1])
	if controls.size() < 4:
		return # RiverSurface's Catmull-Rom needs at least four

	var river := MeshInstance3D.new()
	river.set_script(RIVER_SURFACE)
	river.name = "River%d" % (_rivers.size() + 1)
	river.width = mouth_width
	# A river should be a thread at its source and broad at the sea. The
	# width curve is authored here rather than exported so a scene cannot
	# accidentally ship a river that is uniformly wide, which reads as a canal.
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, source_width / mouth_width))
	curve.add_point(Vector2(1.0, 1.0))
	river.width_curve = curve
	river.control_points = controls
	add_child(river)
	_rivers.append(river)

# ---------------------------------------------------------------------------

func _clear() -> void:
	for r in _rivers:
		if is_instance_valid(r):
			r.queue_free()
	_rivers.clear()

## Duck-typed on sample_height() rather than typed against IslandTerrain, so
## world/terrain/waterways/ carries no hard dependency on a specific terrain
## class — the same convention world/ocean/ocean_surface.gd already uses.
func _resolve_terrain() -> Node:
	if not terrain_path.is_empty():
		var explicit := get_node_or_null(terrain_path)
		if explicit != null and explicit.has_method("sample_height"):
			return explicit
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return null
	return _search(tree.current_scene)

func _search(node: Node) -> Node:
	if node != self and node.has_method("sample_height"):
		return node
	for c in node.get_children():
		var found := _search(c)
		if found != null:
			return found
	return null
