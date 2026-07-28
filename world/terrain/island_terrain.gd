extends Node3D
class_name IslandTerrain
## One island/level: builds an IslandGenerator from its exported seed/size,
## turns it into a render mesh (MeshInstance3D, triplanar shader) and a
## matching StaticBody3D/CollisionShape3D (HeightMapShape3D) as children,
## and keeps its material's `naklon_unit` shader parameter in sync with
## Naklon.unit() so the whole island's ground cover shifts with the player
## god's alignment.
##
## Reusable per the brief's "each island is a level": drop this node into
## any scene (see world/terrain/island_demo.tscn for a standalone example),
## set island_seed/size_meters/resolution, and you get a new island. Two
## instances with different seeds never share geometry or noise state.

signal terrain_ready(island_terrain: IslandTerrain)

@export var island_seed: int = 1:
	set(v):
		island_seed = v
		if is_inside_tree():
			regenerate()
@export var size_meters: float = 256.0:
	set(v):
		size_meters = v
		if is_inside_tree():
			regenerate()
@export var resolution: int = 129:
	set(v):
		resolution = v
		if is_inside_tree():
			regenerate()
@export var max_height: float = 42.0
@export var sea_level: float = 0.0
@export var auto_generate_on_ready: bool = true
## Optional override; if unset, a duplicate of island_material.tres is used
## so each IslandTerrain instance can carry its own shader parameters
## (texture_scale, naklon_unit, etc) without stomping other islands.
@export var terrain_material: ShaderMaterial

const DEFAULT_MATERIAL_PATH := "res://world/terrain/island_material.tres"

var generator: IslandGenerator
var mesh_instance: MeshInstance3D
var static_body: StaticBody3D
var collision_shape: CollisionShape3D

func _ready() -> void:
	if terrain_material == null:
		var base: ShaderMaterial = load(DEFAULT_MATERIAL_PATH)
		terrain_material = base.duplicate() if base else null
	if not Naklon.naklon_changed.is_connected(_on_naklon_changed):
		Naklon.naklon_changed.connect(_on_naklon_changed)
	if auto_generate_on_ready:
		regenerate()

## Rebuilds the mesh + collision from the current seed/size/resolution.
## Safe to call at runtime (e.g. a debug "reroll island" action) — geometry
## and collision are fully replaced, nothing is appended.
func regenerate() -> void:
	generator = IslandGenerator.new()
	generator.island_seed = island_seed
	generator.size_meters = size_meters
	generator.resolution = resolution
	generator.max_height = max_height
	generator.sea_level = sea_level

	_ensure_nodes()
	mesh_instance.mesh = generator.build_mesh()
	if terrain_material:
		mesh_instance.material_override = terrain_material
		_apply_naklon(Naklon.unit())
	collision_shape.shape = generator.build_heightmap_shape()
	var step := generator.grid_step()
	collision_shape.transform = Transform3D(Basis().scaled(Vector3(step, 1.0, step)), Vector3.ZERO)
	terrain_ready.emit(self)

func _ensure_nodes() -> void:
	if mesh_instance == null:
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "IslandMesh"
		add_child(mesh_instance)
	if static_body == null:
		static_body = StaticBody3D.new()
		static_body.name = "IslandBody"
		add_child(static_body)
	if collision_shape == null:
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "IslandShape"
		static_body.add_child(collision_shape)

func _on_naklon_changed(_old: float, new_value: float) -> void:
	_apply_naklon((new_value + 1.0) * 0.5)

func _apply_naklon(unit_value: float) -> void:
	if terrain_material:
		terrain_material.set_shader_parameter("naklon_unit", unit_value)

## World-space height query for anything that wants "where's the ground
## here" (village placement, footstep raycasts, camera collision) without
## reaching into the generator directly. Assumes this node is not rotated
## (translation-only islands) — scoped out below for anything that tilts an
## island. Returns sea_level (in this node's local frame) if the generator
## isn't built yet.
func sample_height(world_xz: Vector2) -> float:
	if generator == null:
		return sea_level
	var local := to_local(Vector3(world_xz.x, 0.0, world_xz.y))
	# sample_smoothed_height(), not height_at(): the render mesh and
	# collision are built from the smoothed grid (see island_generator.gd's
	# smoothing_passes), so anything placed via the raw analytic height_at()
	# could sit slightly above or clipped into the ground it's actually
	# standing on. Everything that places something ON the terrain (village
	# anchors, the Avatar/Hand drop height, ReachBorderRing) should agree
	# with what the player can see and collide with.
	return generator.sample_smoothed_height(local.x, local.z) + global_position.y
