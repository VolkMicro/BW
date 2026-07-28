extends MeshInstance3D
class_name ReachBorderView
## Ground-flush glowing ring showing Reach.radius_for_village(village_id) —
## the design brief's "no HUD overlay for territory" rule, satisfied by
## drawing the border as a real world-space mesh instead of 2D UI. Not
## wired into any scene automatically; attach one per visible village from
## whichever package owns village spawning (I — world/sanctum, or G —
## actors/villagers) by setting `village_id` (and optionally `terrain` so
## the ring follows ground height).
##
## This exists because systems/faith/reach.gd's own doc comment names this
## exact path as the territory-rendering answer; it is a light, optional
## extra alongside this package's main deliverable (the island mesh itself),
## not a required part of every island.

@export var village_id: StringName = &""
@export var terrain: IslandTerrain ## optional — if set, ring height follows the ground

var _last_radius: float = -1.0

func _ready() -> void:
	if mesh == null:
		mesh = TorusMesh.new()
	if material_override == null:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://world/terrain/reach_border.gdshader")
		material_override = mat
	if not Naklon.naklon_changed.is_connected(_on_naklon_changed):
		Naklon.naklon_changed.connect(_on_naklon_changed)
	_on_naklon_changed(0.0, Naklon.value)

func _process(_delta: float) -> void:
	if village_id == &"":
		return
	var radius := Reach.radius_for_village(village_id)
	if not is_equal_approx(radius, _last_radius):
		_last_radius = radius
		_update_ring(radius)

func _update_ring(radius: float) -> void:
	var torus := mesh as TorusMesh
	if torus == null:
		return
	torus.inner_radius = maxf(radius - 1.2, 0.05)
	torus.outer_radius = maxf(radius, torus.inner_radius + 0.05)
	var v: Village = GameState.get_village(village_id)
	if v == null:
		return
	var wx := v.position_on_island.x
	var wz := v.position_on_island.y
	var wy := terrain.sample_height(Vector2(wx, wz)) if terrain else 0.0
	global_position = Vector3(wx, wy + 0.05, wz)

func _on_naklon_changed(_old: float, new_value: float) -> void:
	var mat := material_override as ShaderMaterial
	if mat:
		mat.set_shader_parameter("naklon_unit", (new_value + 1.0) * 0.5)
