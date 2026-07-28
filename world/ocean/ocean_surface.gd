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

@export var size: Vector2 = Vector2(700.0, 700.0)
## Quads per side. ~5m/quad at the default size — coarser than that will
## visibly alias the shortest (2-3m) wind-chop wave in the default set.
@export var subdivisions: int = 140
@export var wave_set: GerstnerWaveSet
@export var shader_path: String = "res://world/ocean/ocean.gdshader"

## Convenience overrides forwarded straight to the shader's uniforms of
## the same name at build time; see docs/systems/ocean.md for the rest
## (tune those on the material directly, or extend this script).
@export var color_shallow: Color = Color(0.263, 0.616, 0.576)
@export var color_deep: Color = Color(0.016, 0.078, 0.153)

var _material: ShaderMaterial
var _elapsed_time: float = 0.0

func _ready() -> void:
	if wave_set == null:
		wave_set = GerstnerWaveSet.default_ocean()
	_build_mesh()
	_build_material()
	set_process(true)

func _process(delta: float) -> void:
	# Tracked independently of the shader's own TIME so CPU-side height
	# queries stay in sync without reading anything back from the GPU.
	# This will drift slightly from the shader's TIME over a very long
	# session (different accumulation source); fine for buoyancy, not
	# meant for frame-exact visual sync.
	_elapsed_time += delta

func _build_mesh() -> void:
	var plane := PlaneMesh.new()
	plane.size = size
	plane.subdivide_width = subdivisions
	plane.subdivide_depth = subdivisions
	mesh = plane

func _build_material() -> void:
	var shader: Shader = load(shader_path)
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("wave_dir_len_steep", wave_set.to_shader_dir_len_steep())
	_material.set_shader_parameter("wave_amp_speed", wave_set.to_shader_amp_speed())
	_material.set_shader_parameter("color_shallow", color_shallow)
	_material.set_shader_parameter("color_deep", color_deep)
	set_surface_override_material(0, _material)

## World-space wave height (meters) at an XZ position — `world_pos.y` is
## ignored on input. For buoyancy: add this to your floating object's rest
## height at (x, z).
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
	if _material == null:
		return
	_material.set_shader_parameter("wave_dir_len_steep", wave_set.to_shader_dir_len_steep())
	_material.set_shader_parameter("wave_amp_speed", wave_set.to_shader_amp_speed())
