extends Node3D
class_name TerrainScatter
## Populates an island with grass, forest and boulders, by rule, from a seed.
##
## Drop this node into any scene that already has an `IslandTerrain` (or
## anything else exposing `sample_height(Vector2) -> float`), point
## `terrain_path` at it, and on the first frame it builds three
## MultiMeshInstance3D children:
##
##   Grass  — dense low tufts on gentle, mid-elevation ground.
##   Trees  — a clustered forest: woods and clearings, never an even lawn.
##   Rocks  — sparse, favouring steep faces and the shoreline.
##
## Everything is placed against the terrain's REAL height and a normal derived
## from it, so nothing floats and nothing sinks, and everything is a pure
## function of `scatter_seed` + the terrain's own seed, so the same island
## always looks the same.
##
## ---------------------------------------------------------------------------
## WHY MULTIMESH, AND WHAT THE DISTANCE CULLING ACTUALLY DOES
## ---------------------------------------------------------------------------
## Target hardware is a laptop with integrated Intel graphics and no discrete
## GPU (docs/systems/performance_lowspec.md). Thousands of Node3Ds would be
## thousands of draw calls, thousands of culling entries and thousands of
## transform updates; a MultiMesh is ONE draw call per surface no matter how
## many instances it holds. So: one MultiMeshInstance3D per kind, three draw
## calls for the whole island, and the meshes are built with one surface each
## (scatter_meshes.gd) precisely to keep that true.
##
## `visibility_range_end` is set on each of those nodes — but be honest about
## what that buys. Godot evaluates visibility range against the *instance's*
## position (the centre of its AABB), not per MultiMesh instance. With one
## island-wide node per kind that is the island's centre, so the range is an
## all-or-nothing "has the god zoomed far enough out that grass is not worth
## drawing" switch, not a per-tuft LOD. That is genuinely the behaviour you
## want here — the god camera orbits at 25..420 m (ui/camera_rig.gd) and grass
## is worthless past a couple of hundred metres — but it is not per-instance
## culling and this file will not pretend otherwise.
##
## If you DO want real per-region culling, set `grass_chunk_divisions` (and
## the tree/rock equivalents) above 1: the kind is then split into an NxN grid
## of MultiMeshInstance3Ds, each with its own AABB and its own range test, at
## the cost of N*N draw calls instead of one. Default is 1 everywhere. Note
## the trade-off is visible, not just numeric: chunked grass pops in and out in
## square patches as the camera moves, which at god-view altitude reads worse
## than simply drawing all of it.
##
## ---------------------------------------------------------------------------
## COST
## ---------------------------------------------------------------------------
## Per frame, this node does NOTHING. There is no _process, no _physics_process
## and no polling — placement happens once, on build. The only runtime work is
## three shader-uniform writes when `Naklon.naklon_changed` fires.
##
## Call `get_stats()` after building (or set `log_stats`) for the real,
## measured-from-the-built-meshes instance and triangle counts.

signal scatter_ready(scatter: TerrainScatter)

const SHADER_PATH := "res://world/terrain/scatter/scatter_foliage.gdshader"

enum Kind { GRASS, TREE, ROCK }

# --- wiring ---------------------------------------------------------------
## The IslandTerrain (or any node with `sample_height(Vector2) -> float`).
## Left empty, the first sibling/parent-child that has the method is used.
@export var terrain_path: NodePath
## Village anchors whose immediate footprint stays clear of trees. In
## world/god_view.tscn these are Villages/FenraytVillage, Villages/SankilnVillage
## and Villages/RaimbornVillage — the same nodes VILLAGE_DEFS points at.
@export var village_anchor_paths: Array[NodePath] = []
@export var village_clear_radius: float = 18.0
@export var auto_scatter_on_ready: bool = true
@export var log_stats: bool = false

# --- determinism ----------------------------------------------------------
## Same seed + same terrain => byte-identical placement, every run.
@export var scatter_seed: int = 1

# --- counts ---------------------------------------------------------------
## Defaults are sized for a 320 m island on integrated Intel graphics; see
## docs/systems/scatter.md for what each thousand instances costs.
@export var grass_count: int = 5000
@export var tree_count: int = 620
@export var rock_count: int = 320
## Rejection sampling gives up after count * this many candidate points, so a
## terrain where (say) nothing is flat enough for grass cannot spin forever.
@export var max_attempts_per_instance: int = 10

# --- distance culling -----------------------------------------------------
@export var grass_visibility_end: float = 420.0
@export var tree_visibility_end: float = 1400.0
@export var rock_visibility_end: float = 1000.0
## 1 = one MultiMeshInstance3D (one draw call) for the whole kind. >1 splits it
## into an NxN grid for real per-region distance culling at N*N draw calls.
@export var grass_chunk_divisions: int = 1
@export var tree_chunk_divisions: int = 1
@export var rock_chunk_divisions: int = 1

# --- placement rules ------------------------------------------------------
## Metres above sea level. Grass starts above the beach and stops below the
## bare peaks; `*_min_normal_y` is the cosine of the steepest slope allowed
## (0.86 ~= 30 degrees, 0.80 ~= 37 degrees).
@export_group("Grass rule")
@export var grass_min_height: float = 1.2
@export var grass_max_height: float = 40.0
@export var grass_min_normal_y: float = 0.86
@export var grass_patch_frequency: float = 0.035
@export var grass_patch_floor: float = 0.35 ## 1.0 = ignore the patchiness noise

@export_group("Forest rule")
@export var tree_min_height: float = 2.2
@export var tree_max_height: float = 34.0
@export var tree_min_normal_y: float = 0.80
## Low-frequency mask that makes woods and clearings instead of even sprinkle.
## ~0.012 gives clumps roughly 40-90 m across on a 320 m island.
@export var forest_frequency: float = 0.012
@export var forest_threshold: float = 0.50
@export var forest_falloff: float = 0.20

@export_group("Rock rule")
@export var rock_min_height: float = -1.0
@export var rock_steep_normal_y: float = 0.90 ## at/below this, fully "steep"
@export var rock_shore_band: float = 3.5 ## metres above sea level that count as shore
@export var rock_base_chance: float = 0.06 ## a few erratics out on open ground

@export_group("Appearance")
@export var grass_scale_range := Vector2(0.75, 1.45)
@export var tree_scale_range := Vector2(0.72, 1.35)
@export var rock_scale_range := Vector2(0.5, 2.2)
@export var wind_strength: float = 0.06
## How far each instance tips toward the terrain normal (0 = dead vertical).
@export var grass_normal_align: float = 0.55
@export var tree_normal_align: float = 0.20
@export var rock_normal_align: float = 1.0

## Step, in metres, between the height samples used to derive the terrain
## normal. Should be about the terrain's grid step (320/160 = 2.0 m in
## world/god_view.tscn) — much smaller and it just reads smoothing noise.
@export var normal_sample_step: float = 2.0

var _materials: Dictionary = {}         # Kind -> ShaderMaterial
var _meshes: Dictionary = {}            # Kind -> ArrayMesh
var _placed: Dictionary = {}            # Kind -> int (instances actually placed)
var _draw_calls: Dictionary = {}        # Kind -> int (MultiMeshInstance3D nodes)
var _extra_exclusions: Array = []       # Array[Vector3]: x, z, radius
var _terrain: Node = null
var _built: bool = false

func _ready() -> void:
	if not Naklon.naklon_changed.is_connected(_on_naklon_changed):
		Naklon.naklon_changed.connect(_on_naklon_changed)
	if not auto_scatter_on_ready:
		return
	var terrain := _resolve_terrain()
	# IslandTerrain builds its mesh in its own _ready(); if this node happens
	# to be readied first, wait for terrain_ready rather than scattering onto
	# a generator that does not exist yet.
	if terrain != null and terrain.has_signal("terrain_ready") \
			and not terrain.is_connected("terrain_ready", _on_terrain_ready):
		terrain.connect("terrain_ready", _on_terrain_ready)
	if not _built:
		rebuild.call_deferred()

func _exit_tree() -> void:
	if Naklon.naklon_changed.is_connected(_on_naklon_changed):
		Naklon.naklon_changed.disconnect(_on_naklon_changed)

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Excludes a circle from tree placement, on top of `village_anchor_paths`.
## Call before rebuild(); positions are world-space XZ.
func add_exclusion(center_xz: Vector2, radius: float) -> void:
	_extra_exclusions.append(Vector3(center_xz.x, center_xz.y, radius))

func clear_exclusions() -> void:
	_extra_exclusions.clear()

## Throws away every placed instance and re-places everything from the current
## seed and rules. Safe at runtime (a debug "reroll" key, or a terrain that
## regenerated under it).
func rebuild() -> void:
	var terrain := _resolve_terrain()
	if terrain == null:
		push_warning("TerrainScatter: no terrain with sample_height(Vector2) found; nothing scattered.")
		return
	_terrain = terrain
	_clear_children()
	_ensure_assets()

	var radius := _island_radius(terrain)
	var center := Vector2(terrain.global_position.x, terrain.global_position.z)
	var exclusions := _collect_exclusions()

	var patch_noise := _make_noise(scatter_seed + 91, grass_patch_frequency)
	var forest_noise := _make_noise(scatter_seed + 4242, forest_frequency)

	# One RNG stream per kind, each seeded independently, so changing
	# tree_count can never shuffle where the grass went.
	_build_kind(Kind.GRASS, grass_count, scatter_seed + 11, terrain, center, radius,
		patch_noise, exclusions, grass_chunk_divisions, grass_visibility_end)
	_build_kind(Kind.TREE, tree_count, scatter_seed + 22, terrain, center, radius,
		forest_noise, exclusions, tree_chunk_divisions, tree_visibility_end)
	_build_kind(Kind.ROCK, rock_count, scatter_seed + 33, terrain, center, radius,
		null, exclusions, rock_chunk_divisions, rock_visibility_end)

	_apply_naklon(Naklon.unit())
	_built = true
	if log_stats:
		print("TerrainScatter: ", get_stats())
	scatter_ready.emit(self)

## Honest, measured-after-the-fact numbers: how many instances of each kind
## actually landed (rejection sampling can fall short of the requested count
## on a terrain with little qualifying ground), the triangle count of one
## instance, the resulting total, and how many draw calls were spent.
func get_stats() -> Dictionary:
	var out := {}
	var total_tris := 0
	var total_calls := 0
	for kind in [Kind.GRASS, Kind.TREE, Kind.ROCK]:
		var placed: int = _placed.get(kind, 0)
		var mesh: Mesh = _meshes.get(kind, null)
		var tris: int = ScatterMeshes.triangle_count(mesh)
		var calls: int = _draw_calls.get(kind, 0)
		out[_kind_name(kind)] = {
			"instances": placed,
			"triangles_per_instance": tris,
			"triangles_total": placed * tris,
			"draw_calls": calls,
		}
		total_tris += placed * tris
		total_calls += calls
	out["triangles_total"] = total_tris
	out["draw_calls_total"] = total_calls
	return out

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

func _build_kind(kind: Kind, count: int, seed_value: int, terrain: Node,
		center: Vector2, radius: float, noise: FastNoiseLite,
		exclusions: Array, divisions: int, range_end: float) -> void:
	_placed[kind] = 0
	_draw_calls[kind] = 0
	if count <= 0:
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var transforms: Array[Transform3D] = []
	var colors := PackedColorArray()
	var inv := global_transform.affine_inverse()
	var budget: int = count * maxi(max_attempts_per_instance, 1)
	var attempts: int = 0

	while transforms.size() < count and attempts < budget:
		attempts += 1
		# Uniform sample over the island disc (sqrt keeps it area-uniform
		# rather than piling everything at the centre).
		var ang: float = rng.randf() * TAU
		var r: float = sqrt(rng.randf()) * radius
		var xz := center + Vector2(cos(ang) * r, sin(ang) * r)

		var h: float = terrain.sample_height(xz)
		if not _height_ok(kind, h):
			continue
		# Slope costs four more height samples, so it is only paid for
		# candidates that already passed the (one-sample) height test.
		var n: Vector3 = _terrain_normal(terrain, xz)
		var chance: float = _accept_chance(kind, xz, h, n, noise, exclusions)
		if chance <= 0.0 or rng.randf() > chance:
			continue

		var world_pos := Vector3(xz.x, h, xz.y)
		var yaw: float = rng.randf() * TAU
		var scale_vec: Vector3
		var align: float
		match kind:
			Kind.GRASS:
				var s: float = rng.randf_range(grass_scale_range.x, grass_scale_range.y)
				scale_vec = Vector3(s, s * rng.randf_range(0.85, 1.2), s)
				align = grass_normal_align
			Kind.TREE:
				var s2: float = rng.randf_range(tree_scale_range.x, tree_scale_range.y)
				scale_vec = Vector3(s2 * rng.randf_range(0.88, 1.12), s2, s2 * rng.randf_range(0.88, 1.12))
				align = tree_normal_align
			_:
				var s3: float = rng.randf_range(rock_scale_range.x, rock_scale_range.y)
				scale_vec = Vector3(s3 * rng.randf_range(0.8, 1.35), s3 * rng.randf_range(0.6, 1.0),
					s3 * rng.randf_range(0.8, 1.35))
				align = rock_normal_align
				# Bury the boulder a little so it sits IN the ground, not on it.
				world_pos.y -= scale_vec.y * 0.22

		transforms.append(inv * _oriented(world_pos, n, align, yaw, scale_vec))
		colors.append(_instance_color(kind, rng))

	_placed[kind] = transforms.size()
	if transforms.is_empty():
		return
	_emit_multimeshes(kind, transforms, colors, maxi(divisions, 1), range_end)

## Turns the collected transforms into one (or divisions^2) MultiMeshInstance3D
## children. Chunking buckets by XZ so each node has a tight AABB.
func _emit_multimeshes(kind: Kind, transforms: Array[Transform3D],
		colors: PackedColorArray, divisions: int, range_end: float) -> void:
	var buckets: Dictionary = {}
	if divisions <= 1:
		buckets[0] = range(transforms.size())
	else:
		var minv := Vector2(INF, INF)
		var maxv := Vector2(-INF, -INF)
		for t in transforms:
			minv.x = minf(minv.x, t.origin.x)
			minv.y = minf(minv.y, t.origin.z)
			maxv.x = maxf(maxv.x, t.origin.x)
			maxv.y = maxf(maxv.y, t.origin.z)
		var span := (maxv - minv).max(Vector2(0.001, 0.001))
		for i in transforms.size():
			var t2: Transform3D = transforms[i]
			var cx: int = clampi(int((t2.origin.x - minv.x) / span.x * float(divisions)), 0, divisions - 1)
			var cz: int = clampi(int((t2.origin.z - minv.y) / span.y * float(divisions)), 0, divisions - 1)
			var key: int = cz * divisions + cx
			if not buckets.has(key):
				buckets[key] = []
			buckets[key].append(i)

	var kind_name := _kind_name(kind)
	var made: int = 0
	for key in buckets.keys():
		var idx_list: Array = buckets[key]
		if idx_list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _meshes[kind]
		mm.instance_count = idx_list.size()
		for i in idx_list.size():
			var src: int = idx_list[i]
			mm.set_instance_transform(i, transforms[src])
			mm.set_instance_color(i, colors[src])

		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s%s" % [kind_name, "" if divisions <= 1 else "_%d" % int(key)]
		mmi.multimesh = mm
		mmi.material_override = _materials[kind]
		mmi.visibility_range_end = range_end
		# Fade mode stays DISABLED on purpose: FADE_SELF forces alpha-hash
		# transparency on the material, which loses early-Z on thousands of
		# small overlapping quads — the wrong trade on a fragment-bound part.
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		# Only trees are worth a shadow-map pass. Grass shadows at god-view
		# altitude are sub-pixel; rocks are small and mostly on slopes.
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if kind == Kind.TREE \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		made += 1
	_draw_calls[kind] = made

# ---------------------------------------------------------------------------
# Placement rules
# ---------------------------------------------------------------------------

func _height_ok(kind: Kind, h: float) -> bool:
	match kind:
		Kind.GRASS:
			return h >= grass_min_height and h <= grass_max_height
		Kind.TREE:
			return h >= tree_min_height and h <= tree_max_height
		_:
			return h >= rock_min_height

## 0.0 rejects outright; 1.0 always accepts. Everything in between is the
## per-kind density field, sampled against the kind's own RNG stream.
func _accept_chance(kind: Kind, xz: Vector2, h: float, n: Vector3,
		noise: FastNoiseLite, exclusions: Array) -> float:
	match kind:
		Kind.GRASS:
			if n.y < grass_min_normal_y:
				return 0.0
			# Thin the grass out as it approaches the slope limit and the
			# beach, so the edges of the meadow are a gradient, not a line.
			var slope_fade: float = smoothstep(grass_min_normal_y, minf(grass_min_normal_y + 0.08, 1.0), n.y)
			var shore_fade: float = smoothstep(grass_min_height, grass_min_height + 2.5, h)
			var patch: float = 1.0
			if noise != null:
				patch = lerpf(grass_patch_floor, 1.0, _noise01(noise, xz))
			return clampf(slope_fade * shore_fade * patch, 0.0, 1.0)
		Kind.TREE:
			if n.y < tree_min_normal_y:
				return 0.0
			for e in exclusions:
				var ex: Vector3 = e
				if xz.distance_squared_to(Vector2(ex.x, ex.y)) < ex.z * ex.z:
					return 0.0
			# The clustering: a low-frequency mask thresholded with a soft
			# edge. Below the threshold there are simply no trees — that is
			# what makes clearings instead of an even sprinkle.
			var mask: float = _noise01(noise, xz) if noise != null else 1.0
			var forest: float = smoothstep(forest_threshold, forest_threshold + forest_falloff, mask)
			if forest <= 0.0:
				return 0.0
			var slope_fade2: float = smoothstep(tree_min_normal_y, minf(tree_min_normal_y + 0.10, 1.0), n.y)
			var tree_line: float = 1.0 - smoothstep(tree_max_height - 8.0, tree_max_height, h)
			return clampf(forest * slope_fade2 * tree_line, 0.0, 1.0)
		_:
			# Steep ground OR the shoreline, whichever argues harder for a rock.
			var steep: float = 1.0 - smoothstep(rock_steep_normal_y, minf(rock_steep_normal_y + 0.09, 1.0), n.y)
			var shore: float = 1.0 - smoothstep(0.5, rock_shore_band, absf(h))
			return clampf(maxf(maxf(steep, shore * 0.85), rock_base_chance), 0.0, 1.0)

## Terrain normal from four height samples around the point. IslandTerrain has
## no normal API, and its sample_height() reads the SMOOTHED grid that the
## visible mesh and the collision shape are both built from — so a normal
## derived from it agrees with the surface a player can see and walk on,
## which a normal derived from the raw analytic height_at() would not.
func _terrain_normal(terrain: Node, xz: Vector2) -> Vector3:
	var d: float = maxf(normal_sample_step, 0.01)
	var hl: float = terrain.sample_height(xz + Vector2(-d, 0.0))
	var hr: float = terrain.sample_height(xz + Vector2(d, 0.0))
	var hb: float = terrain.sample_height(xz + Vector2(0.0, -d))
	var hf: float = terrain.sample_height(xz + Vector2(0.0, d))
	var dx: float = (hr - hl) / (2.0 * d)
	var dz: float = (hf - hb) / (2.0 * d)
	return Vector3(-dx, 1.0, -dz).normalized()

func _oriented(pos: Vector3, n: Vector3, align: float, yaw: float, scale_vec: Vector3) -> Transform3D:
	var up: Vector3 = Vector3.UP.lerp(n, clampf(align, 0.0, 1.0))
	if up.length_squared() < 1e-8:
		up = Vector3.UP
	up = up.normalized()
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	var right: Vector3 = fwd.cross(up)
	if right.length_squared() < 1e-8:
		right = Vector3.RIGHT
	right = right.normalized()
	var forward: Vector3 = up.cross(right).normalized()
	return Transform3D(Basis(right * scale_vec.x, up * scale_vec.y, forward * scale_vec.z), pos)

func _instance_color(kind: Kind, rng: RandomNumberGenerator) -> Color:
	# Multiplied into the mesh's own vertex colours by the renderer, so this is
	# per-instance variety for free: no extra mesh, no extra draw call. Alpha
	# stays 1.0 because the mesh uses COLOR.a as its wind sway mask.
	match kind:
		Kind.GRASS:
			var g: float = rng.randf_range(0.82, 1.20)
			return Color(g * rng.randf_range(0.9, 1.05), g, g * rng.randf_range(0.85, 1.0), 1.0)
		Kind.TREE:
			var t: float = rng.randf_range(0.80, 1.22)
			return Color(t * rng.randf_range(0.9, 1.1), t, t * rng.randf_range(0.85, 1.05), 1.0)
		_:
			var s: float = rng.randf_range(0.78, 1.22)
			return Color(s, s * rng.randf_range(0.97, 1.03), s * rng.randf_range(0.95, 1.05), 1.0)

# ---------------------------------------------------------------------------
# Assets, terrain resolution, Naklon
# ---------------------------------------------------------------------------

func _ensure_assets() -> void:
	var mesh_rng := RandomNumberGenerator.new()
	mesh_rng.seed = scatter_seed + 777
	_meshes[Kind.GRASS] = ScatterMeshes.build_grass_clump(mesh_rng)
	_meshes[Kind.TREE] = ScatterMeshes.build_tree()
	_meshes[Kind.ROCK] = ScatterMeshes.build_boulder()

	var shader: Shader = load(SHADER_PATH)
	var tuning := {
		Kind.GRASS: {"rough": 0.95, "wind": wind_strength},
		Kind.TREE: {"rough": 0.90, "wind": wind_strength * 0.7},
		Kind.ROCK: {"rough": 0.82, "wind": 0.0},
	}
	for kind in tuning.keys():
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("surface_roughness", tuning[kind]["rough"])
		mat.set_shader_parameter("wind_strength", tuning[kind]["wind"])
		mat.set_shader_parameter("wind_speed", 1.3 if kind == Kind.GRASS else 0.9)
		mat.set_shader_parameter("ash_strength", 0.45 if kind == Kind.ROCK else 0.85)
		_materials[kind] = mat

func _clear_children() -> void:
	for child in get_children():
		if child is MultiMeshInstance3D:
			remove_child(child)
			child.queue_free()

func _resolve_terrain() -> Node:
	if _terrain != null and is_instance_valid(_terrain):
		return _terrain
	if not terrain_path.is_empty():
		var explicit := get_node_or_null(terrain_path)
		if explicit != null and explicit.has_method("sample_height"):
			return explicit
		if explicit != null:
			push_warning("TerrainScatter: terrain_path node has no sample_height(); ignoring it.")
	# Duck-typed fallback, same convention world/ocean/ocean_surface.gd uses:
	# look for a sibling that answers sample_height(), so this node has no hard
	# dependency on the IslandTerrain class.
	var parent := get_parent()
	if parent != null:
		for sibling in parent.get_children():
			if sibling != self and sibling.has_method("sample_height"):
				return sibling
	return null

## Radius of the disc candidate points are drawn from. Reads the terrain's own
## `size_meters` when it has one (IslandTerrain does), so a bigger island
## automatically gets scattered across all of it.
func _island_radius(terrain: Node) -> float:
	var size_value: Variant = terrain.get("size_meters")
	if size_value is float or size_value is int:
		return float(size_value) * 0.5
	return 160.0

func _collect_exclusions() -> Array:
	var out: Array = []
	for path in village_anchor_paths:
		if path.is_empty():
			continue
		var node := get_node_or_null(path)
		if node is Node3D:
			var p: Vector3 = (node as Node3D).global_position
			out.append(Vector3(p.x, p.z, village_clear_radius))
	for e in _extra_exclusions:
		out.append(e)
	return out

func _make_noise(seed_value: int, frequency: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = maxf(frequency, 0.0001)
	n.fractal_octaves = 2
	n.fractal_gain = 0.45
	return n

func _noise01(noise: FastNoiseLite, xz: Vector2) -> float:
	return clampf(noise.get_noise_2d(xz.x, xz.y) * 0.5 + 0.5, 0.0, 1.0)

func _on_terrain_ready(_terrain_node: Variant) -> void:
	if auto_scatter_on_ready:
		rebuild.call_deferred()

func _on_naklon_changed(_old_value: float, new_value: float) -> void:
	_apply_naklon((new_value + 1.0) * 0.5)

## Three shader-uniform writes, only when the god's alignment actually moves.
## No per-instance work, no per-frame work: the MultiMesh buffers are never
## touched again after the build.
func _apply_naklon(unit_value: float) -> void:
	for kind in _materials.keys():
		var mat: ShaderMaterial = _materials[kind]
		mat.set_shader_parameter("naklon_unit", unit_value)

func _kind_name(kind: Kind) -> String:
	match kind:
		Kind.GRASS:
			return "Grass"
		Kind.TREE:
			return "Trees"
		_:
			return "Rocks"
