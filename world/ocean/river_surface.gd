extends MeshInstance3D
class_name RiverSurface
## Narrow flowing-water surface generated from an array of Vector3 control
## points — a Catmull-Rom-smoothed spline turned into a tapering ribbon
## mesh — for coastline inlets, river mouths, and streams cutting through
## package B's terrain. Reuses the same Gerstner-wave math as OceanSurface
## (short, steep, fast ripples instead of open-sea swell) plus a
## flow-direction UV scroll and bank foam in world/ocean/river.gdshader.
##
## Standalone by design: this script only reads the control points it's
## given at the node level (or via rebuild()), so a terrain script in
## world/terrain/ can construct a RiverSurface and hand it a spline
## without either package writing into the other's directory. See
## world/ocean/ocean_demo.tscn for a worked example.

@export var control_points: PackedVector3Array = PackedVector3Array()
@export var width: float = 6.0
## Optional: sampled 0..1 along the spline, multiplies `width` — e.g. taper
## a river mouth wider where it meets the sea. Left null = constant width.
@export var width_curve: Curve
@export var segments_per_span: int = 12
@export var wave_set: GerstnerWaveSet
@export var shader_path: String = "res://world/ocean/river.gdshader"
## UV-scroll speed along the flow direction (roughly meters/second-equivalent).
@export var flow_speed: float = 1.4

var _material: ShaderMaterial
var _elapsed_time: float = 0.0
var _flow_direction: Vector2 = Vector2(0.0, 1.0)

func _ready() -> void:
	if control_points.size() >= 2:
		var a: Vector3 = control_points[0]
		var b: Vector3 = control_points[control_points.size() - 1]
		var flow := Vector2(b.x - a.x, b.z - a.z)
		if flow.length_squared() > 0.0001:
			_flow_direction = flow.normalized()
	if wave_set == null:
		wave_set = GerstnerWaveSet.default_river(_flow_direction)
	_build_mesh()
	_build_material()
	set_process(true)

func _process(delta: float) -> void:
	_elapsed_time += delta
	if _material:
		_material.set_shader_parameter("flow_time", _elapsed_time * flow_speed)

## Rebuild after changing control_points/width at runtime (e.g. terrain
## carving a new inlet, or a spline edited in the editor).
func rebuild(new_points: PackedVector3Array) -> void:
	control_points = new_points
	_build_mesh()

func _catmull_rom(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * (
		2.0 * p1
		+ (p2 - p0) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (3.0 * p1 - 3.0 * p2 + p3 - p0) * t3
	)

func _width_at(t01: float) -> float:
	if width_curve:
		return width_curve.sample(clampf(t01, 0.0, 1.0))
	return 1.0

func _build_mesh() -> void:
	if control_points.size() < 2:
		mesh = null
		return

	var sampled: Array[Vector3] = []
	var n := control_points.size()
	for i in range(n - 1):
		var p0: Vector3 = control_points[maxi(i - 1, 0)]
		var p1: Vector3 = control_points[i]
		var p2: Vector3 = control_points[i + 1]
		var p3: Vector3 = control_points[mini(i + 2, n - 1)]
		var is_last_span := i == n - 2
		var steps: int = (segments_per_span + 1) if is_last_span else segments_per_span
		for s in range(steps):
			var t := float(s) / float(segments_per_span)
			sampled.append(_catmull_rom(p0, p1, p2, p3, t))

	var total := sampled.size()
	if total < 2:
		mesh = null
		return

	var lengths: Array[float] = [0.0]
	for i in range(1, total):
		lengths.append(lengths[i - 1] + sampled[i].distance_to(sampled[i - 1]))
	var total_length: float = maxf(lengths[total - 1], 0.001)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in range(total - 1):
		var a := sampled[i]
		var b := sampled[i + 1]
		var dir := b - a
		dir.y = 0.0
		if dir.length_squared() < 0.0001:
			continue
		dir = dir.normalized()
		var side := Vector3(-dir.z, 0.0, dir.x)

		var w_a := width * _width_at(lengths[i] / total_length)
		var w_b := width * _width_at(lengths[i + 1] / total_length)

		var a_l := a - side * w_a * 0.5
		var a_r := a + side * w_a * 0.5
		var b_l := b - side * w_b * 0.5
		var b_r := b + side * w_b * 0.5

		var v_a := lengths[i] / width
		var v_b := lengths[i + 1] / width

		st.set_uv(Vector2(0.0, v_a))
		st.add_vertex(a_l)
		st.set_uv(Vector2(1.0, v_a))
		st.add_vertex(a_r)
		st.set_uv(Vector2(0.0, v_b))
		st.add_vertex(b_l)

		st.set_uv(Vector2(1.0, v_a))
		st.add_vertex(a_r)
		st.set_uv(Vector2(1.0, v_b))
		st.add_vertex(b_r)
		st.set_uv(Vector2(0.0, v_b))
		st.add_vertex(b_l)

	st.generate_normals()
	st.generate_tangents()
	mesh = st.commit()

func _build_material() -> void:
	var shader: Shader = load(shader_path)
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("wave_dir_len_steep", wave_set.to_shader_dir_len_steep())
	_material.set_shader_parameter("wave_amp_speed", wave_set.to_shader_amp_speed())
	_material.set_shader_parameter("flow_direction", _flow_direction)
	set_surface_override_material(0, _material)

## World-space wave height (meters) at an XZ position — same caveat as
## OceanSurface.get_height() (samples at undisplaced XZ).
func get_height(world_pos: Vector3) -> float:
	var s := wave_set.sample(Vector2(world_pos.x, world_pos.z), _elapsed_time)
	return (s.displacement as Vector3).y
