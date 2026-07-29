extends Node3D
class_name VillageBuildings
## Puts dwellings around every village, and raises the temple superstructure
## over every Sanctum.
##
## ---------------------------------------------------------------------------
## WHY THIS EXISTS
## ---------------------------------------------------------------------------
## Two things were wrong when a player first looked at the island:
##
##   1. **There were no houses.** A village was a Sanctum, a calling stone and
##      some people standing in a field. Nothing said "people live here", so
##      the villages did not read as settlements at all.
##   2. **The Sanctum did not read as a temple.** It is a 7 m box with a low
##      pyramid cap, and from god view that is a shed. A player could not tell
##      what it was or that it was theirs.
##
## Both are legibility problems, not content problems: the systems underneath
## (village hp, faith, offering, prayer) were already real. This node fixes
## what the player can see.
##
## ---------------------------------------------------------------------------
## COST
## ---------------------------------------------------------------------------
## Houses are one `MultiMeshInstance3D` for the whole island — one draw call
## for every dwelling in every village, however many villages there are. Built
## once at startup and never touched again; nothing here has a `_process`.
##
## The temple is per-Sanctum geometry (a handful of them), added as a child of
## the Sanctum's existing `Exterior` node so it inherits the collapse tween
## `sanctum.gd` plays when a village is destroyed — the temple falls with the
## building it belongs to, for free.

const VillageArch := preload("res://world/village/village_architecture.gd")

@export var terrain_path: NodePath
@export var auto_build_on_ready: bool = false

@export_group("Dwellings")
@export var houses_per_village: int = 10
## Ring the houses occupy around the village centre. The inner radius clears
## the Sanctum's own worship yard (a 9 m platform) so nobody builds on it.
@export var house_ring_inner: float = 13.0
@export var house_ring_outer: float = 30.0
## Minimum gap between two houses, so a village looks settled rather than
## stacked.
@export var house_min_gap: float = 5.5
## Houses will not be placed below this height or on ground steeper than this.
@export var house_min_height: float = 2.0
@export var house_max_slope_drop: float = 2.6
@export var house_visibility_range_end: float = 700.0

var _terrain: Node = null
var _rng := RandomNumberGenerator.new()
var _houses: MultiMeshInstance3D = null

func _ready() -> void:
	if auto_build_on_ready:
		build()

## Called by the scene owner once villages are registered — see the _ready()
## ordering note in world/god_view.gd (children run before parents, so
## GameState is empty at this node's own _ready()).
func build() -> void:
	_terrain = _resolve_terrain()
	if _terrain == null:
		push_warning("VillageBuildings: no terrain with sample_height(); nothing built.")
		return
	_rng.seed = hash("village_buildings") ^ 0xB01D
	_build_houses()
	_raise_temples()

# ---------------------------------------------------------------------------
# Dwellings
# ---------------------------------------------------------------------------

func _build_houses() -> void:
	# Every house shares one mesh, so per-house variety comes from the
	# transform (yaw, slight scale) and the instance colour rather than from
	# separate meshes — that is what keeps this to a single draw call.
	var mesh := VillageArch.build_house(_rng)
	var placed: Array[Vector3] = []

	for v in GameState.villages.values():
		var centre: Vector2 = v.position_on_island
		var culture: Culture = GameState.cultures.get(v.culture_id)
		var tint := Color(1, 1, 1)
		if culture:
			# Lift the culture colour well toward white: it is multiplied into
			# already-dark timber vertex colours, and the authored primaries
			# are near-black (Fenrayt's is 0.106, 0.114, 0.098). Used raw, every
			# house came out a black smudge.
			tint = culture.color_primary.lerp(Color(1, 1, 1), 0.72)

		var made := 0
		var attempts := 0
		while made < houses_per_village and attempts < houses_per_village * 25:
			attempts += 1
			var a := _rng.randf() * TAU
			var r := _rng.randf_range(house_ring_inner, house_ring_outer)
			var xz := centre + Vector2(cos(a), sin(a)) * r
			if not _buildable(xz):
				continue
			var pos := Vector3(xz.x, _height(xz), xz.y)
			var clear := true
			for p in placed:
				if p.distance_to(pos) < house_min_gap:
					clear = false
					break
			if not clear:
				continue
			placed.append(pos)
			made += 1
			_house_transforms.append(Transform3D(
				Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.92, 1.12)),
				pos))
			_house_colors.append(tint)

	if _house_transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = _house_transforms.size()
	for i in _house_transforms.size():
		mm.set_instance_transform(i, _house_transforms[i])
		mm.set_instance_color(i, _house_colors[i])
	_houses = MultiMeshInstance3D.new()
	_houses.name = "Dwellings"
	_houses.multimesh = mm
	_houses.visibility_range_end = house_visibility_range_end
	_houses.material_override = _building_material()
	add_child(_houses)

var _house_transforms: Array[Transform3D] = []
var _house_colors: Array[Color] = []

## A house needs ground above the surf and roughly level under its footprint —
## the same test the villages themselves use to pick a site, at building scale.
func _buildable(xz: Vector2) -> bool:
	var h := _height(xz)
	if h < house_min_height:
		return false
	var lo := h
	var hi := h
	for i in 4:
		var a := TAU * float(i) / 4.0
		var s := _height(xz + Vector2(cos(a), sin(a)) * 3.0)
		lo = minf(lo, s)
		hi = maxf(hi, s)
	return (hi - lo) <= house_max_slope_drop

# ---------------------------------------------------------------------------
# Temples
# ---------------------------------------------------------------------------

## Adds the tiered roof, posts and ridge prows over each Sanctum's existing
## shell. The CSG box underneath is left completely alone — it is still the
## walkable interior, still collides, still gets scorched by sanctum.gd. Only
## the silhouette changes.
func _raise_temples() -> void:
	for sanctum in get_tree().get_nodes_in_group(&"sanctum"):
		_raise_one(sanctum)
	# The Sanctum scene does not put itself in a group, so also sweep the tree
	# for anything that looks like one. Duck-typed on the public API rather
	# than typed against the class, matching how the rest of this project
	# crosses package lines.
	for n in _find_sanctums(get_tree().current_scene):
		_raise_one(n)

func _raise_one(sanctum: Node) -> void:
	if sanctum == null or not is_instance_valid(sanctum):
		return
	var exterior := sanctum.get_node_or_null(^"Exterior")
	if exterior == null or exterior.has_node(^"TempleRoof"):
		return   # already raised
	var mi := MeshInstance3D.new()
	mi.name = "TempleRoof"
	mi.mesh = VillageArch.build_temple(9.0)
	mi.material_override = _building_material()
	# Sits on the Sanctum's own floor level; the tiers rise from there and
	# swallow the CSG cap.
	mi.position = Vector3(0.0, 0.2, 0.0)
	exterior.add_child(mi)

func _find_sanctums(node: Node, out: Array[Node] = []) -> Array[Node]:
	if node.has_method("hp_fraction") and node.has_node(^"Exterior"):
		out.append(node)
	for c in node.get_children():
		_find_sanctums(c, out)
	return out

# ---------------------------------------------------------------------------

## Vertex colours carry the timber/shingle shading, and the MultiMesh instance
## colour carries the culture tint, so one material serves every building.
func _building_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.92
	m.metallic = 0.0
	return m

func _height(xz: Vector2) -> float:
	return float(_terrain.call("sample_height", xz))

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
