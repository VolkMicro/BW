class_name RiteVFX
extends RefCounted
## Per-rite one-shot particle presets, built procedurally at runtime from
## built-in primitive meshes (SphereMesh/BoxMesh/TorusMesh) and a
## ParticleProcessMaterial configured in code — no textures, no imported
## art. Any package can react to `SigilCaster.rite_cast(rite_id, confidence)`
## with:
##
##   RiteVFX.spawn(rite_id, world_position, some_parent_node)
##
## and get a real, working GPUParticles3D burst appropriate to that rite,
## which frees itself once its particles finish. This keeps the preset
## table in one place (this file) rather than nine hand-authored .tscn
## files whose ParticleProcessMaterial resource blocks would be easy to
## typo and impossible for this pass to visually verify against a GPU.

const DEFAULT_LIFETIME := 1.4
const DEFAULT_AMOUNT := 48

class Preset:
	var color: Color
	var direction: Vector3
	var spread_deg: float
	var velocity_min: float
	var velocity_max: float
	var gravity: Vector3
	var scale_min: float
	var scale_max: float
	var mesh_kind: StringName # &"sphere", &"box", &"torus"
	var lifetime: float
	var amount: int

	func _init(
		p_color: Color, p_direction: Vector3, p_spread_deg: float,
		p_velocity_min: float, p_velocity_max: float, p_gravity: Vector3,
		p_scale_min: float, p_scale_max: float, p_mesh_kind: StringName,
		p_lifetime: float = DEFAULT_LIFETIME, p_amount: int = DEFAULT_AMOUNT
	) -> void:
		color = p_color
		direction = p_direction
		spread_deg = p_spread_deg
		velocity_min = p_velocity_min
		velocity_max = p_velocity_max
		gravity = p_gravity
		scale_min = p_scale_min
		scale_max = p_scale_max
		mesh_kind = p_mesh_kind
		lifetime = p_lifetime
		amount = p_amount

static func _presets() -> Dictionary:
	return {
		&"rain_call": Preset.new(
			Color(0.42, 0.62, 0.86, 0.9), Vector3.DOWN, 18.0,
			0.6, 1.4, Vector3(0.0, -2.4, 0.0), 0.05, 0.12, &"sphere"
		),
		&"path_gate": Preset.new(
			Color(0.55, 0.85, 0.78, 0.85), Vector3.UP, 25.0,
			0.8, 1.6, Vector3(0.0, 0.3, 0.0), 0.06, 0.14, &"torus", 1.8, 32
		),
		&"harvest": Preset.new(
			Color(0.86, 0.72, 0.28, 0.9), Vector3.UP, 30.0,
			0.5, 1.1, Vector3(0.0, -0.6, 0.0), 0.05, 0.1, &"box"
		),
		&"lumber": Preset.new(
			Color(0.47, 0.33, 0.2, 0.95), Vector3.UP, 55.0,
			0.7, 1.8, Vector3(0.0, -3.0, 0.0), 0.04, 0.09, &"box"
		),
		&"repair": Preset.new(
			Color(0.95, 0.88, 0.6, 0.9), Vector3.UP, 15.0,
			0.2, 0.5, Vector3(0.0, 0.1, 0.0), 0.03, 0.07, &"sphere", 1.6, 40
		),
		&"ward": Preset.new(
			Color(0.72, 0.9, 0.95, 0.85), Vector3.UP, 10.0,
			0.1, 0.3, Vector3.ZERO, 0.08, 0.16, &"torus", 2.0, 24
		),
		&"fire_arrow": Preset.new(
			Color(0.95, 0.42, 0.12, 1.0), Vector3.UP, 12.0,
			2.0, 3.6, Vector3(0.0, 1.0, 0.0), 0.05, 0.11, &"sphere", 0.9, 56
		),
		&"lightning": Preset.new(
			Color(0.82, 0.9, 1.0, 1.0), Vector3.UP, 60.0,
			3.0, 5.0, Vector3.ZERO, 0.03, 0.07, &"box", 0.4, 64
		),
		&"storm": Preset.new(
			Color(0.55, 0.58, 0.63, 0.85), Vector3.UP, 70.0,
			1.2, 2.4, Vector3(0.0, -0.4, 0.0), 0.07, 0.15, &"sphere", 2.2, 72
		),
	}

## Colors are exposed separately so other packages (a UI cursor glow, the
## Two Voices' subtitle color) can match a rite's VFX without spawning it.
static func color_for(rite_id: StringName) -> Color:
	var presets := _presets()
	if presets.has(rite_id):
		return (presets[rite_id] as Preset).color
	return Color.WHITE

## Spawns a real, working one-shot GPUParticles3D under `parent` at
## `world_position` for `rite_id`, and frees it automatically once its
## particles finish. Returns the node (or null if `rite_id` has no preset
## or `parent` is null) in case the caller wants to keep a reference.
static func spawn(rite_id: StringName, world_position: Vector3, parent: Node) -> GPUParticles3D:
	if parent == null:
		return null
	var presets := _presets()
	var preset: Preset = presets.get(rite_id, null)
	if preset == null:
		return null

	var particles := GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.direction = preset.direction
	mat.spread = preset.spread_deg
	mat.initial_velocity_min = preset.velocity_min
	mat.initial_velocity_max = preset.velocity_max
	mat.gravity = preset.gravity
	mat.scale_min = preset.scale_min
	mat.scale_max = preset.scale_max
	mat.color = preset.color
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.35

	particles.process_material = mat
	particles.draw_pass_1 = _make_mesh(preset.mesh_kind, preset.color)
	particles.amount = preset.amount
	particles.lifetime = preset.lifetime
	particles.one_shot = true
	particles.explosiveness = 0.6
	particles.emitting = true

	parent.add_child(particles)
	particles.global_position = world_position

	var tree := parent.get_tree()
	if tree != null:
		var timer := tree.create_timer(preset.lifetime + 0.5)
		# `particles` frees itself once its burst finishes; nothing else in
		# this file queues it free earlier, so a direct bound-method connect
		# (no freed-instance guard needed) is enough here.
		timer.timeout.connect(particles.queue_free)
	return particles

static func _make_mesh(mesh_kind: StringName, color: Color) -> Mesh:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b)
	mat.emission_energy_multiplier = 1.6

	# PrimitiveMesh (Box/Sphere/Torus) carries its material as the `material`
	# property, not via Mesh.surface_set_material (that's ArrayMesh-only).
	var mesh: PrimitiveMesh
	if mesh_kind == &"box":
		var box := BoxMesh.new()
		box.size = Vector3(1.0, 1.0, 1.0)
		mesh = box
	elif mesh_kind == &"torus":
		var torus := TorusMesh.new()
		torus.inner_radius = 0.6
		torus.outer_radius = 1.0
		mesh = torus
	else:
		var sphere := SphereMesh.new()
		sphere.radius = 0.5
		sphere.height = 1.0
		mesh = sphere
	mesh.material = mat
	return mesh
