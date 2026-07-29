extends MeshInstance3D
class_name OceanSurface
## Open-ocean surface for an island scene: a subdivided PlaneMesh whose
## vertices are displaced by a sum of Gerstner waves entirely on the GPU
## (world/ocean/ocean.gdshader). Also keeps the same wave data on the CPU
## (GerstnerWaveSet) so other packages can query wave height/normal at a
## world position for buoyancy-style logic without a GPU readback — see
## get_height()/sample_surface() below.
##
## Usage: add an OceanSurface (or a MeshInstance3D with this script) to any
## scene; it builds its own mesh and material in _ready(). See
## world/ocean/ocean_demo.tscn for a worked example, and
## docs/systems/ocean.md for every exposed uniform.
##
## LOW-SPEC BEHAVIOUR (see docs/systems/performance_lowspec.md): this node
## defaults to the CHEAP water path — no screen-texture/depth-texture reads,
## a reduced mesh density, fewer Gerstner waves, and no shadow casting.
## `set_water_quality_high(true)` — which environment/graphics_preset.gd
## calls for you at MEDIUM/HIGH — restores the full, expensive path for real
## GPU hardware.

## Group every OceanSurface joins on _ready(), so a graphics-preset node can
## find them without a hard NodePath — same lookup pattern
## environment/weather_environment_driver.gd uses for NaklonEnvironmentDriver.
const GROUP_NAME := &"ocean_surface"

@export var size: Vector2 = Vector2(700.0, 700.0)
## Quads per side. ~5m/quad at the default size — coarser than that will
## visibly alias the shortest (2-3m) wind-chop wave in the default set.
## NOTE: on the low-spec path this is clamped to `low_spec_subdivisions`
## (see _effective_subdivisions()), so a scene may ask for more than it gets.
@export var subdivisions: int = 140
@export var wave_set: GerstnerWaveSet
@export var shader_path: String = "res://world/ocean/ocean.gdshader"

@export_group("Quality")
## OFF (default) = the cheap path: ocean.gdshader is loaded as-is, which
## compiles WITHOUT hint_screen_texture/hint_depth_texture, so the renderer
## never performs the per-frame back-buffer and depth copies those hints
## request. ON = the full path (screen-space refraction + real scene-depth
## shoreline fade), for machines with a discrete GPU.
@export var high_quality_water: bool = false
## Subdivision cap applied when high_quality_water is false. 64 over an
## 800 m plane is 12.5 m/quad: too coarse to render the 2.4 m and 5 m
## wind-chop waves in GerstnerWaveSet.default_ocean() (which is exactly why
## low_spec_wave_count drops them), but ample for the 15-42 m swell that is
## all a god-view camera can actually resolve.
## Raised from 64. At the shipping 2400 m plane, 64 subdivisions meant 37 m
## between ocean vertices — coarser than a third of the island — so the
## per-vertex "is there land under me" mask (_bake_shore_mask) could not
## resolve the island at all: only 32 of 4356 vertices came out dry and only
## 44 triangles could be dropped, leaving the water sheeted across the whole
## interior. 160 gives ~15 m spacing, fine enough to actually cut the island
## out. The extra vertices are a startup cost (one sample_height per vertex,
## once) plus vertex-shader work on a mesh that is still smaller than the
## terrain's own.
@export var low_spec_subdivisions: int = 160
## How many of the wave set's waves are sent to the GPU on the low-spec
## path (longest-wavelength first, i.e. the order they are authored in).
## The rest are sent as inert zero-amplitude entries, which the shader's
## own `continue` already skips. CPU-side get_height()/sample_surface()
## deliberately still use the FULL set, so buoyancy physics is unchanged —
## the two disagree by the dropped waves' combined amplitude, which for
## default_ocean() is 0.12 m + 0.06 m = under 20 cm.
@export var low_spec_wave_count: int = 4
## The ocean plane casting shadows is close to pure waste: it is a flat
## sheet at sea level lit from above, so its shadow lands on the sea floor
## nobody sees, and every shadow split re-runs the full six-wave Gerstner
## vertex program over the whole mesh. Leave off unless something genuinely
## needs water shadows.
@export var cast_water_shadows: bool = false

@export_group("Cheap shoreline")
## Drives the depth-texture-free shoreline in ocean.gdshader's low-spec
## path: instead of reading the depth buffer every frame, the sea-floor
## depth under every ocean vertex is sampled ONCE here on the CPU and baked
## into the mesh's vertex colours. Ignored when high_quality_water is true
## (that path uses the real depth buffer).
##
## Optional. Left empty, this node searches the current scene for the first
## node exposing `sample_height(Vector2) -> float` (world/terrain/island_terrain.gd's
## IslandTerrain does), so world/god_view.tscn needs no extra wiring. Set it
## explicitly if a scene has more than one terrain and the wrong one wins.
@export var shore_terrain_path: NodePath
## Water depth (metres) that a fully-saturated vertex colour represents.
## Must match the shader uniform of the same name. Vertex colour is 8 bits
## per channel, so this also sets the quantisation: 8 m / 255 ~= 3 cm.
@export var shore_depth_reference: float = 8.0
## Skip the bake entirely (every vertex reads as deep water, no shore band).
@export var bake_shore_mask: bool = true

## Convenience overrides forwarded straight to the shader's uniforms of
## the same name at build time; see docs/systems/ocean.md for the rest
## (tune those on the material directly, or extend this script).
@export var color_shallow: Color = Color(0.263, 0.616, 0.576)
@export var color_deep: Color = Color(0.016, 0.078, 0.153)

const _HIGH_QUALITY_DEFINE := "#define OCEAN_HIGH_QUALITY"

var _material: ShaderMaterial
var _elapsed_time: float = 0.0

func _ready() -> void:
	if wave_set == null:
		wave_set = GerstnerWaveSet.default_ocean()
	add_to_group(GROUP_NAME)
	_apply_shadow_setting()
	_build_mesh()
	_build_material()
	# Deferred: the terrain the shore mask is baked against generates its
	# heightmap in its own _ready(), and sibling _ready() order is a scene
	# layout detail this node should not depend on. One frame of
	# uniformly-deep water before the mask lands is invisible.
	_bake_shore_mask.call_deferred()
	set_process(true)

func _process(delta: float) -> void:
	# Tracked independently of the shader's own TIME so CPU-side height
	# queries stay in sync without reading anything back from the GPU.
	# This will drift slightly from the shader's TIME over a very long
	# session (different accumulation source); fine for buoyancy, not
	# meant for frame-exact visual sync.
	_elapsed_time += delta

# ---------------------------------------------------------------------------
# Public quality API (used by environment/graphics_preset.gd)
# ---------------------------------------------------------------------------

## Switch between the cheap and the full water path at runtime. Idempotent:
## calling it with the value already in effect does nothing, so a graphics
## preset node can re-apply its whole preset every time without rebuilding
## the ocean mesh and recompiling a shader for no reason.
func set_water_quality_high(enabled: bool) -> void:
	if enabled == high_quality_water and is_node_ready():
		return
	high_quality_water = enabled
	if not is_node_ready():
		return
	_apply_shadow_setting()
	_build_mesh()
	_build_material()
	_bake_shore_mask()

func is_water_quality_high() -> bool:
	return high_quality_water

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

func _apply_shadow_setting() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_water_shadows \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## Quads per side actually used. The low-spec cap is a *cap*, never an
## increase — a scene that already asks for fewer keeps its own number.
func _effective_subdivisions() -> int:
	if high_quality_water:
		return maxi(subdivisions, 1)
	return maxi(mini(subdivisions, low_spec_subdivisions), 1)

func _build_mesh() -> void:
	var plane := PlaneMesh.new()
	plane.size = size
	var subdiv: int = _effective_subdivisions()
	plane.subdivide_width = subdiv
	plane.subdivide_depth = subdiv
	mesh = plane

func _build_material() -> void:
	var shader: Shader = _resolve_shader()
	_material = ShaderMaterial.new()
	_material.shader = shader
	_push_wave_uniforms()
	_material.set_shader_parameter("color_shallow", color_shallow)
	_material.set_shader_parameter("color_deep", color_deep)
	_material.set_shader_parameter("shore_depth_reference", shore_depth_reference)
	set_surface_override_material(0, _material)

# ---------------------------------------------------------------------------
# Shore mask bake
# ---------------------------------------------------------------------------

## Replaces the PlaneMesh with an ArrayMesh carrying the same geometry plus a
## per-vertex colour whose RED channel is "how deep is the sea floor here",
## normalised against shore_depth_reference. This is the cheap path's entire
## substitute for a per-frame depth-texture read.
##
## Cost: one terrain height query per ocean vertex, ONCE. At the low-spec
## 64 subdivisions that is 65 x 65 = 4225 queries at startup and zero
## per-frame work thereafter. Nothing here runs in _process().
##
## No-ops (leaving the plain PlaneMesh, whose absent colour attribute Godot
## feeds to the shader as opaque white = "deep everywhere") when baking is
## disabled, when the high-quality depth-buffer path is active, or when no
## terrain can be found.
func _bake_shore_mask() -> void:
	if not bake_shore_mask or high_quality_water:
		return
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var source: Node = _find_height_source()
	if source == null:
		return

	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if verts.is_empty():
		return

	var origin: Vector3 = global_position
	var reference: float = maxf(shore_depth_reference, 0.001)
	var colors := PackedColorArray()
	colors.resize(verts.size())
	for i in range(verts.size()):
		var v: Vector3 = verts[i]
		var world_xz := Vector2(v.x + origin.x, v.z + origin.z)
		# sample_height returns the terrain surface height in world Y.
		# Depth of water at this point = sea surface (this node's Y) minus
		# the sea floor; negative (land above water) clamps to 0, which the
		# shader reads as "full foam", correctly, for the vertices that sit
		# under the island and are never visible anyway.
		var floor_y: float = source.call("sample_height", world_xz)
		var depth: float = clampf((origin.y - floor_y) / reference, 0.0, 1.0)
		colors[i] = Color(depth, depth, depth, 1.0)

	arrays[Mesh.ARRAY_COLOR] = colors

	# DROP THE TRIANGLES THAT ARE ENTIRELY INLAND.
	#
	# The comment above reasons that vertices sitting under the island are
	# "never visible anyway". That was wrong, and it was the single most
	# expensive wrong assumption in this project's rendering history: those
	# triangles were drawn straight over the island's interior, and because
	# their baked depth is 0 — which the shader reads as maximum foam — they
	# painted it flat white. For several passes that white sheet was mistaken
	# for the terrain itself, and time went into "why is the island grey"
	# when the island was not what was on screen. It was finally pinned by
	# forcing the OCEAN shader's ALBEDO to red and watching the "island" turn
	# red.
	#
	# A triangle is dropped only when ALL THREE of its vertices are dry, so
	# the water still runs in under the coastline and the shoreline itself is
	# untouched — the hole left behind is strictly interior to the island and
	# cannot expose a seam. At the shipping tessellation this removes a few
	# hundred triangles and gains a little fill rate; the point is
	# correctness, not the saving.
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if not indices.is_empty():
		var kept := PackedInt32Array()
		var dry := 0.002
		for t in range(0, indices.size(), 3):
			var a := indices[t]
			var b := indices[t + 1]
			var c := indices[t + 2]
			if colors[a].r <= dry and colors[b].r <= dry and colors[c].r <= dry:
				continue
			kept.append(a)
			kept.append(b)
			kept.append(c)
		arrays[Mesh.ARRAY_INDEX] = kept

	var baked := ArrayMesh.new()
	baked.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = baked
	if _material != null:
		set_surface_override_material(0, _material)

## Explicit path first, then the first node in the current scene exposing
## `sample_height`. Duck-typed rather than typed against IslandTerrain so
## world/ocean/ stays free of a hard dependency on world/terrain/ (they are
## separate packages — see docs/systems/OWNERSHIP.md).
func _find_height_source() -> Node:
	if not shore_terrain_path.is_empty():
		var explicit: Node = get_node_or_null(shore_terrain_path)
		if explicit != null and explicit.has_method("sample_height"):
			return explicit
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return null
	return _search_for_height_source(tree.current_scene)

func _search_for_height_source(node: Node) -> Node:
	if node != self and node.has_method("sample_height"):
		return node
	for child: Node in node.get_children():
		var found: Node = _search_for_height_source(child)
		if found != null:
			return found
	return null

## Low-spec (the default) just loads the .gdshader, which compiles to the
## cheap path. High quality re-compiles the SAME source with the
## OCEAN_HIGH_QUALITY preprocessor symbol defined; there is no way to hand a
## per-material `#define` to a shared Shader resource in Godot 4, and a
## runtime `uniform bool` would not help because the renderer decides
## whether to run the back-buffer/depth copies from the compiled shader's
## declared samplers, not from a uniform's value.
##
## If the source cannot be read for any reason the plainly-loaded (cheap)
## shader is returned rather than erroring — worst case you get low-spec
## water on a high-spec machine, which is a visual downgrade, not a break.
func _resolve_shader() -> Shader:
	var base: Shader = load(shader_path) as Shader
	if not high_quality_water:
		return base
	var source: String = _read_shader_source()
	if source.is_empty():
		push_warning("OceanSurface: could not read '%s' to build the high-quality water variant; using the low-spec path instead." % shader_path)
		return base
	var generated := Shader.new()
	generated.code = source
	return generated

## Reads the shader file and inserts the `#define` immediately after the
## `shader_type` line. It has to go *after* that line, not before it:
## `shader_type` must be the first real statement in a Godot shader.
func _read_shader_source() -> String:
	var file := FileAccess.open(shader_path, FileAccess.READ)
	if file == null:
		return ""
	var raw: String = file.get_as_text()
	file.close()
	if raw.is_empty():
		return ""
	var lines: PackedStringArray = raw.split("\n")
	var out := PackedStringArray()
	var inserted: bool = false
	for i in range(lines.size()):
		var line: String = lines[i]
		out.append(line)
		if not inserted and line.strip_edges().begins_with("shader_type"):
			out.append(_HIGH_QUALITY_DEFINE)
			inserted = true
	if not inserted:
		return ""
	return "\n".join(out)

## Waves actually sent to the GPU. On the low-spec path the tail of the set
## is zeroed out: at 12.5 m/quad the shortest waves cannot be represented by
## the mesh at all, so paying for them in the vertex shader buys nothing but
## aliasing.
func _push_wave_uniforms() -> void:
	if _material == null or wave_set == null:
		return
	var dirs: Array = wave_set.to_shader_dir_len_steep()
	var amps: Array = wave_set.to_shader_amp_speed()
	if not high_quality_water:
		var keep: int = maxi(low_spec_wave_count, 1)
		for i in range(amps.size()):
			if i >= keep:
				amps[i] = Vector2.ZERO
	_material.set_shader_parameter("wave_dir_len_steep", dirs)
	_material.set_shader_parameter("wave_amp_speed", amps)

## World-space wave height (meters) at an XZ position — `world_pos.y` is
## ignored on input. For buoyancy: add this to your floating object's rest
## height at (x, z). Always uses the FULL wave set, including waves the
## low-spec render path drops — see `low_spec_wave_count`.
func get_height(world_pos: Vector3) -> float:
	var s := wave_set.sample(Vector2(world_pos.x, world_pos.z), _elapsed_time)
	return (s.displacement as Vector3).y

## Full displaced position + surface normal at an XZ position, for
## anything that needs to orient to the water surface (a floating boat,
## drifting debris). See GerstnerWaveSet.sample() for the buoyancy
## simplification this relies on.
func sample_surface(world_pos: Vector3) -> Dictionary:
	var s := wave_set.sample(Vector2(world_pos.x, world_pos.z), _elapsed_time)
	var disp: Vector3 = s.displacement
	return {
		"position": Vector3(world_pos.x + disp.x, disp.y, world_pos.z + disp.z),
		"normal": s.normal,
	}

## Re-pushes the current wave_set to the material — call after mutating
## wave_set.waves at runtime (e.g. a storm system raising amplitude).
func refresh_waves() -> void:
	_push_wave_uniforms()
