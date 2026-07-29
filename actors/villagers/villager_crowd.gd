extends Node3D
class_name VillagerCrowd
## Every villager on the island, as data — not as scene nodes.
##
## ---------------------------------------------------------------------------
## WHY THIS EXISTS
## ---------------------------------------------------------------------------
## `actors/villagers/villager.gd` makes a villager a `CharacterBody3D` running
## `move_and_slide()` every physics frame. That is a perfectly good way to have
## fifteen of them, which is what the game had. The design calls for **fifteen
## villages of about forty people**, i.e. ~600, on a laptop with integrated
## Intel graphics and no discrete GPU.
##
## 600 is not "40x more of the same". It is a different shape of program:
##
##   * 600 scene nodes is 600 lots of tree overhead, transform propagation and
##     per-node bookkeeping before any game logic runs at all.
##   * 600 physics bodies is 600 broadphase entries and 600 `move_and_slide()`
##     solves per physics tick, for agents that only ever need to stand on a
##     heightmap — the physics engine is solving a problem nobody has.
##   * 600 `MeshInstance3D`s is 600 draw calls, which is the whole frame budget
##     on this hardware.
##
## So: villagers live in packed arrays, are drawn by ONE `MultiMeshInstance3D`
## (one draw call for the entire island's population), stand on the ground by
## sampling the terrain heightmap rather than by colliding with it, and think
## on a stagger rather than all in the same frame.
##
## ---------------------------------------------------------------------------
## WHAT THIS DELIBERATELY DOES NOT DO
## ---------------------------------------------------------------------------
## No pathfinding. `NavigationServer` with 600 agents would cost more than
## everything else in the game combined, and villagers walking around an island
## do not need optimal paths — they need to not walk into the sea and to
## generally end up where they were going. They steer toward their target and
## refuse steps that would take them below the waterline or up a cliff, which
## is enough at this scale and costs four height samples.
##
## No per-agent collision. Villagers pass through each other. At god-view
## distance nobody can tell, and the alternative is a broadphase over 600
## bodies to prevent something the player will never look closely enough to
## see.
##
## ---------------------------------------------------------------------------
## LEVEL OF DETAIL
## ---------------------------------------------------------------------------
## Agents near the camera run the full decision loop. Beyond
## `detail_distance` a village is simulated in aggregate: its economy still
## ticks (that lives in `systems/economy/`, which works off `Village.jobs`
## counts, not off individual bodies), and its people still walk their routes,
## but they stop *deciding* — a distant village's figures are motion, not
## agents. The player cannot tell, and it is the difference between this
## running and not.
##
## Nothing here has a `_physics_process`. Everything is on `_process` with an
## explicit budget: at most `agents_per_tick` agents re-decide per frame.

signal villager_died(village_id: StringName, cause: StringName)

const TerrainScatterMeshes := preload("res://world/terrain/scatter/scatter_meshes.gd")

enum Job { IDLE, FISHING, FIELD, WOODCUTTING, BUILDING, FAMILY }
enum State { WALKING, WORKING, RESTING }

@export var terrain_path: NodePath
## Villagers per village. The design target is ~40.
@export var per_village: int = 40
## Off by default. Godot runs a child's _ready() BEFORE its parent's, so a
## crowd that populated itself on ready would always find GameState empty —
## the villages are registered by world/god_view.gd's own _ready(), which runs
## afterwards. The scene owner calls populate() once the villages exist.
@export var auto_populate_on_ready: bool = false

@export_group("Simulation budget")
## How many agents re-decide their job/target each frame. With 600 agents and
## 20 per frame every agent thinks roughly once per 30 frames — about twice a
## second at 60 fps, which is far more often than a person changes their mind
## about what they are doing today.
@export var agents_per_tick: int = 20
## Past this distance from the camera, a village's people stop deciding and
## just walk. See "LEVEL OF DETAIL" above.
@export var detail_distance: float = 260.0

@export_group("Movement")
@export var walk_speed: float = 2.1
@export var speed_variation: float = 0.35
## A step that would drop the villager below this is refused — they will not
## walk into the sea.
@export var min_walk_height: float = 0.6
## A step that climbs more than this in one stride is refused, so nobody walks
## up a cliff face.
@export var max_step_climb: float = 1.4
## How close counts as arrived.
@export var arrive_radius: float = 2.5

@export_group("Look")
@export var villager_scale: float = 1.0
@export var visibility_range_end: float = 900.0

# --- Agent data. One entry per villager, index-aligned across every array. ---
var _pos := PackedVector3Array()
var _target := PackedVector3Array()
var _village := PackedInt32Array()   # index into _village_ids
var _job := PackedInt32Array()
var _state := PackedInt32Array()
var _timer := PackedFloat32Array()
var _speed := PackedFloat32Array()
var _yaw := PackedFloat32Array()

var _village_ids: Array[StringName] = []
var _village_centre: Array = []      # Vector2 per village
## Named work sites per village: {job -> Vector3}. Found once, at populate
## time, by looking at the real terrain — see _find_work_sites().
var _village_sites: Array = []

var _terrain: Node = null
var _mm: MultiMeshInstance3D = null
var _rng := RandomNumberGenerator.new()
var _cursor: int = 0                 # round-robin position for the tick budget
var _camera: Camera3D = null

func _ready() -> void:
	if auto_populate_on_ready:
		populate()

## Builds the crowd from whatever villages are registered in GameState.
func populate() -> void:
	_terrain = _resolve_terrain()
	if _terrain == null:
		push_warning("VillagerCrowd: no terrain with sample_height(); no villagers spawned.")
		return
	_rng.seed = hash("villager_crowd") ^ 0x5157

	_clear()
	for v in GameState.villages.values():
		_add_village(v)
	_build_multimesh()

func get_population() -> int:
	return _pos.size()

## Live count of villagers currently doing `job` in `village_id`. This is what
## `systems/economy/` should read instead of the authored `Village.jobs`
## dictionary once the crowd is the source of truth — the numbers are then
## actual people rather than a designer's intention.
func count_job(village_id: StringName, job: int) -> int:
	var vi := _village_ids.find(village_id)
	if vi < 0:
		return 0
	var n := 0
	for i in _village.size():
		if _village[i] == vi and _job[i] == job:
			n += 1
	return n

# ---------------------------------------------------------------------------
# Populating
# ---------------------------------------------------------------------------

func _add_village(v: Village) -> void:
	var vi := _village_ids.size()
	_village_ids.append(v.id)
	var centre: Vector2 = v.position_on_island
	_village_centre.append(centre)
	_village_sites.append(_find_work_sites(centre))

	for _n in per_village:
		# Scatter around the village centre, but only onto ground a person
		# could stand on; a few rejected attempts is cheaper than spawning
		# somebody in the surf and dealing with it later.
		var xz := centre
		for _try in 12:
			var a := _rng.randf() * TAU
			var r := sqrt(_rng.randf()) * 16.0   # sqrt for uniform area, not clumped centre
			var candidate := centre + Vector2(cos(a), sin(a)) * r
			if _height(candidate) >= min_walk_height:
				xz = candidate
				break
		var p := Vector3(xz.x, _height(xz), xz.y)
		_pos.append(p)
		_target.append(p)
		_village.append(vi)
		_job.append(Job.IDLE)
		_state.append(State.RESTING)
		_timer.append(_rng.randf() * 4.0)
		_speed.append(walk_speed * _rng.randf_range(1.0 - speed_variation, 1.0 + speed_variation))
		_yaw.append(_rng.randf() * TAU)

## Finds a real place on the terrain for each kind of work, so villagers walk
## somewhere meaningful instead of milling about the village centre.
##
## Deliberately crude: one representative site per job, found by sampling a
## ring around the village and scoring cells for what that job wants. A
## woodcutter wants the nearest high ground where trees grow, a fisher wants
## the nearest shoreline. That is enough for people to have somewhere to go;
## Phase 2 replaces the representative point with the actual tree being felled.
func _find_work_sites(centre: Vector2) -> Dictionary:
	var sites := {
		Job.IDLE: Vector3(centre.x, _height(centre), centre.y),
		Job.FAMILY: Vector3(centre.x, _height(centre), centre.y),
		Job.BUILDING: Vector3(centre.x, _height(centre), centre.y),
	}
	var best_shore := centre
	var best_shore_score := -1e9
	var best_wood := centre
	var best_wood_score := -1e9
	var best_field := centre
	var best_field_score := -1e9

	for ring: float in [28.0, 48.0, 72.0, 100.0]:
		for i in 16:
			var a := TAU * float(i) / 16.0
			var p := centre + Vector2(cos(a), sin(a)) * ring
			var h := _height(p)
			var dist := centre.distance_to(p)

			# Shore: as close to the waterline as possible without being in it.
			if h > 0.2 and h < 4.0:
				var s := -absf(h - 1.5) * 4.0 - dist * 0.05
				if s > best_shore_score:
					best_shore_score = s
					best_shore = p
			# Woodcutting: higher ground, where the scatter puts forest.
			if h > 6.0:
				var w := h - dist * 0.08
				if w > best_wood_score:
					best_wood_score = w
					best_wood = p
			# Fields: gentle, mid-height ground close to home.
			if h > 3.0 and h < 18.0:
				var f := -absf(h - 9.0) - dist * 0.12
				if f > best_field_score:
					best_field_score = f
					best_field = p

	sites[Job.FISHING] = Vector3(best_shore.x, _height(best_shore), best_shore.y)
	sites[Job.WOODCUTTING] = Vector3(best_wood.x, _height(best_wood), best_wood.y)
	sites[Job.FIELD] = Vector3(best_field.x, _height(best_field), best_field.y)
	return sites

# ---------------------------------------------------------------------------
# Ticking
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _pos.is_empty():
		return
	_ensure_camera()
	_decide_slice()
	_move_all(delta)
	_push_transforms()

## Re-decides a bounded slice of agents. Round-robin over the whole population
## so every agent is reached at a predictable rate regardless of population.
func _decide_slice() -> void:
	var n := mini(agents_per_tick, _pos.size())
	for _k in n:
		var i := _cursor
		_cursor = (_cursor + 1) % _pos.size()
		if not _is_detailed(i):
			continue      # distant village: keeps walking, stops deciding
		_decide(i)

func _decide(i: int) -> void:
	var vid := _village_ids[_village[i]]
	var v: Village = GameState.get_village(vid)
	if v == null:
		return

	# Weather and the state of the village choose the work, in that order:
	# nobody fishes in a storm, and a half-burnt Sanctum pulls hands onto
	# rebuilding it whatever else they had planned.
	var storm: bool = bool(Weather.current.get("is_storm", false))
	var precip: float = float(Weather.current.get("precipitation", 0.0))
	var hurt := v.sanctum_hp < v.sanctum_hp_max * 0.75

	var job := Job.IDLE
	if storm:
		job = Job.FAMILY          # indoors
	elif hurt and _rng.randf() < 0.5:
		job = Job.BUILDING
	else:
		var roll := _rng.randf()
		if precip > 0.4:
			# Rain is good for fields and bad for everything else.
			job = Job.FIELD if roll < 0.55 else Job.FAMILY
		elif roll < 0.30:
			job = Job.WOODCUTTING
		elif roll < 0.58:
			job = Job.FIELD
		elif roll < 0.80:
			job = Job.FISHING
		elif roll < 0.92:
			job = Job.FAMILY
		else:
			job = Job.IDLE

	_job[i] = job
	var sites: Dictionary = _village_sites[_village[i]]
	var site: Vector3 = sites.get(job, sites[Job.IDLE])
	# Spread the crowd out around the work site rather than stacking everyone
	# on one point — without this a job site looks like a single flickering
	# person however many are working it.
	var a := _rng.randf() * TAU
	var r := sqrt(_rng.randf()) * 9.0
	var want := Vector2(site.x + cos(a) * r, site.z + sin(a) * r)
	if _height(want) < min_walk_height:
		want = Vector2(site.x, site.z)
	_target[i] = Vector3(want.x, _height(want), want.y)
	_state[i] = State.WALKING

func _move_all(delta: float) -> void:
	for i in _pos.size():
		if _state[i] != State.WALKING:
			continue
		var p: Vector3 = _pos[i]
		var t: Vector3 = _target[i]
		var to := Vector2(t.x - p.x, t.z - p.z)
		if to.length() <= arrive_radius:
			_state[i] = State.WORKING
			continue
		var dir := to.normalized()
		var stride: float = _speed[i] * delta
		var next := Vector2(p.x, p.z) + dir * stride
		var nh := _height(next)
		# Refuse the sea and refuse cliffs. A refused step just means standing
		# still this frame; the next decision will usually pick a new target,
		# which is a cheap and adequate substitute for real pathfinding at this
		# scale (see the header).
		if nh < min_walk_height or nh - p.y > max_step_climb:
			continue
		_pos[i] = Vector3(next.x, nh, next.y)
		_yaw[i] = atan2(dir.x, dir.y)

func _push_transforms() -> void:
	if _mm == null:
		return
	var mm := _mm.multimesh
	for i in _pos.size():
		var b := Basis(Vector3.UP, float(_yaw[i])).scaled(Vector3.ONE * villager_scale)
		var ip: Vector3 = _pos[i]
		mm.set_instance_transform(i, Transform3D(b, ip))

# ---------------------------------------------------------------------------

func _is_detailed(i: int) -> bool:
	if _camera == null:
		return true
	var ip: Vector3 = _pos[i]
	return _camera.global_position.distance_squared_to(ip) <= detail_distance * detail_distance

func _ensure_camera() -> void:
	if _camera == null or not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_3d()

func _height(xz: Vector2) -> float:
	return float(_terrain.call("sample_height", xz))

func _build_multimesh() -> void:
	if _pos.is_empty():
		return
	var mesh := TerrainScatterMeshes.build_villager()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = _pos.size()
	_mm = MultiMeshInstance3D.new()
	_mm.name = "Crowd"
	_mm.multimesh = mm
	_mm.visibility_range_end = visibility_range_end
	_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mm)
	_push_transforms()

func _clear() -> void:
	_pos.clear(); _target.clear(); _village.clear(); _job.clear()
	_state.clear(); _timer.clear(); _speed.clear(); _yaw.clear()
	_village_ids.clear(); _village_centre.clear(); _village_sites.clear()
	if _mm != null and is_instance_valid(_mm):
		_mm.queue_free()
	_mm = null
	_cursor = 0

func _resolve_terrain() -> Node:
	if not terrain_path.is_empty():
		var explicit := get_node_or_null(terrain_path)
		if explicit != null and explicit.has_method("sample_height"):
			return explicit
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return null
	return _search(tree.current_scene)

func _search(n: Node) -> Node:
	if n != self and n.has_method("sample_height"):
		return n
	for c in n.get_children():
		var f := _search(c)
		if f != null:
			return f
	return null
