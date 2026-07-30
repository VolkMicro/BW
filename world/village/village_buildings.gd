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
## Dwellings per village at the reference population below. The real count
## scales with `Village.population`, so a village that grows visibly gains
## houses and a village Louhi has hollowed out visibly loses them — see
## `_house_count_for()`.
@export var houses_per_village: int = 12
## The population `houses_per_village` describes. SettlementPlanner sizes
## villages between about 14 and 34 people, so this sits in the middle.
@export var reference_population: int = 24
@export var min_houses_per_village: int = 4
@export var max_houses_per_village: int = 26
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
## Debounced rebuild. Population moves once every couple of minutes per
## village, but fifteen villages growing independently would otherwise rebuild
## every MultiMesh on the island several times a minute for one extra hut.
## Coalescing into one rebuild a few seconds later costs nothing anybody can
## see and turns a burst of births into a single pass.
const REBUILD_DEBOUNCE := 4.0
var _rebuild_pending: float = -1.0

func queue_rebuild() -> void:
	_rebuild_pending = REBUILD_DEBOUNCE
	set_process(true)


func _process(delta: float) -> void:
	if _rebuild_pending < 0.0:
		set_process(false)
		return
	_rebuild_pending -= delta
	if _rebuild_pending <= 0.0:
		_rebuild_pending = -1.0
		set_process(false)
		build()


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

## The dwelling models. Real CC0 art (Quaternius, Medieval Village Pack) rather
## than the procedural box this used to build: at village-level zoom the
## procedural houses read as brown wedges, and a player looking at them said
## so. Credits in docs/systems/village_buildings.md; licence text ships beside
## the models in assets/models/village/License.txt.
##
## One MultiMesh PER MODEL, not per building: four types means four draw calls
## for every dwelling on the island, however many villages there are. The
## models carry their own materials (untextured, flat-coloured — which is
## exactly right for this hardware), so nothing here sets material_override:
## doing so would collapse every surface of the model onto one material and
## throw the roof/plaster/stone colours away.
const HOUSE_MODELS := [
	"res://assets/models/village/House_1.obj",
	"res://assets/models/village/House_2.obj",
	"res://assets/models/village/House_3.obj",
	"res://assets/models/village/House_4.obj",
]

## One of these is placed per village as a landmark, so villages are not just
## a ring of identical huts. Deliberately few — these are the heavier meshes.
## Mill, Stable and Sawmill are NOT here. All three reproducibly crashed
## Godot 4.3's OBJ importer (SIGABRT during --import, three runs), while the
## six kept below import cleanly. Rather than ship an asset that aborts the
## importer, they were removed from the repository entirely — a broken import
## is the kind of thing that wastes an hour for whoever next clones this.
const LANDMARK_MODELS := [
	"res://assets/models/village/Blacksmith.obj",
	"res://assets/models/village/Inn.obj",
	# The three that follow are the SAME artist's pack in glTF. Mill, Sawmill
	# and Stable in OBJ reproducibly crashed Godot 4.3's OBJ importer and were
	# deleted from the repo; glTF goes through a different importer entirely
	# and loads them without trouble. See assets/models/village_gltf/LICENSE.md.
	"res://assets/models/village_gltf/Mill.glb",
	"res://assets/models/village_gltf/Barracks.glb",
	"res://assets/models/village_gltf/BellTower.glb",
]

## MEASURED, NOT GUESSED — and necessary, because the poly.pizza mirror
## normalises every model to a different size. Measured heights as imported,
## against the houses already in the village at 3.3 m:
##
##   Mill 4.80   BellTower 4.76   Barracks 1.85   Sawmill 0.59
##   Well 1.25   MarketStalls 0.55   VillageMarket 0.55   Cart 0.80
##   Fence 1.10 (5.89 wide)
##
## A barracks the size of a wheelbarrow and a mill shorter than the cottages
## it grinds for are not stylistic choices, they are an artefact of how the
## mirror exports. These factors put each one at a height that makes sense
## beside a 3.3 m house.
const MODEL_SCALE := {
	"Mill": 1.5,          # ~7 m — taller than the houses, as a mill should be
	"BellTower": 1.9,     # ~9 m — the thing you see first from the air
	"Barracks": 2.2,      # ~4 m, long and low
	"Sawmill": 2.0,       # a saw platform, not a building
	"Well": 1.8,
	"MarketStalls": 2.0,
	"VillageMarket": 2.0,
	"Cart": 1.6,
	"Fence": 1.3,         # ~1.4 m tall, 7.6 m wide per section
}

## Small things that make a settlement look lived in rather than deployed: a
## well people draw from, a market, a cart somebody left out. One of each per
## village at most, and only where there is room.
##
## Deliberately NOT a church. Every "church"/"chapel" model in these packs
## carries a cross, and `docs/audit/respect_audit.md` forbids real sacred
## symbols — which is also why the game builds its own temples procedurally
## (world/village/village_architecture.gd) instead of downloading one.
const PROP_MODELS := [
	"res://assets/models/village_gltf/Well.glb",
	"res://assets/models/village_gltf/MarketStalls.glb",
	"res://assets/models/village_gltf/Cart.glb",
	"res://assets/models/village_gltf/VillageMarket.glb",
	"res://assets/models/village_gltf/Sawmill.glb",
]
## How many fence sections ring a village. Cheap, and the single strongest
## signal that the ground inside belongs to somebody.
## Fence RUNS, not sections. A single 7.6 m section on a 195 m perimeter is a
## stick in a field; three or four in a row read as somebody's boundary. This
## was visible immediately in the first render and is the difference between
## a fenced village and a village with litter around it.
@export var fence_runs: int = 4
@export var fence_run_length_min: int = 3
@export var fence_run_length_max: int = 6
const FENCE_MODEL := "res://assets/models/village_gltf/Fence.glb"

## How many dwellings this village should have standing.
##
## Roughly one house per two adults, scaled off the reference population, so
## the settlement is a picture of its own census rather than a fixed dozen
## huts. This is what makes Phase 3 growth visible at all: without it a
## village that doubles its population looks exactly like one that starved.
func _house_count_for(v: Village) -> int:
	var ratio: float = float(v.population) / float(maxi(reference_population, 1))
	return clampi(int(round(float(houses_per_village) * ratio)),
		min_houses_per_village, max_houses_per_village)


func _build_houses() -> void:
	# Bucket the placements by model so each model gets exactly one MultiMesh.
	var buckets: Array = []
	for _i in HOUSE_MODELS.size():
		buckets.append([] as Array[Transform3D])
	var placed: Array[Vector3] = []
	var landmark_i := 0

	for v in GameState.villages.values():
		var centre: Vector2 = v.position_on_island
		var wanted := _house_count_for(v)
		var made := 0
		var attempts := 0
		while made < wanted and attempts < wanted * 25:
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
			# Face roughly toward the Sanctum, with slack — a village whose
			# doors all point at its temple reads as a settlement around
			# something, which is what it is. Fully random yaw reads as debris.
			var toward := (centre - xz).angle() + _rng.randf_range(-0.9, 0.9)
			var b := Basis(Vector3.UP, toward).scaled(Vector3.ONE * _rng.randf_range(0.95, 1.25))
			buckets[_rng.randi() % HOUSE_MODELS.size()].append(Transform3D(b, pos))

		_place_landmark(centre, placed, landmark_i)
		landmark_i += 1

	for i in HOUSE_MODELS.size():
		var xforms: Array = buckets[i]
		if xforms.is_empty():
			continue
		var mesh: Mesh = _load_building(HOUSE_MODELS[i])
		if mesh == null:
			push_warning("VillageBuildings: could not load %s" % HOUSE_MODELS[i])
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = xforms.size()
		for k in xforms.size():
			mm.set_instance_transform(k, xforms[k])
		var node := MultiMeshInstance3D.new()
		node.name = "Dwellings%d" % (i + 1)
		node.multimesh = mm
		node.visibility_range_end = house_visibility_range_end
		add_child(node)

## A single larger building per village, placed just outside the house ring.
func _place_landmark(centre: Vector2, placed: Array[Vector3], index: int) -> void:
	# One landmark per village, cycling through the list, so fifteen
	# settlements do not all read as the same silhouette from the air. With
	# six kinds and fifteen villages no two neighbours share one.
	_place_model(LANDMARK_MODELS[index % LANDMARK_MODELS.size()], centre, placed,
		house_ring_outer * 0.75, house_ring_outer * 1.25, house_min_gap * 1.6)
	# Then the small stuff. A different prop per village for the same reason,
	# plus a well for everyone — a settlement with no water source reads wrong
	# even to somebody who could not say why.
	_place_model(PROP_MODELS[0], centre, placed,
		house_ring_inner * 0.35, house_ring_inner * 0.8, house_min_gap * 0.8)
	_place_model(PROP_MODELS[1 + index % (PROP_MODELS.size() - 1)], centre, placed,
		house_ring_inner * 0.9, house_ring_outer * 0.8, house_min_gap)
	_place_fence(centre, placed)


## Puts one model down somewhere in a ring around the village, on ground that
## can take it and clear of everything already placed.
func _place_model(path: String, centre: Vector2, placed: Array[Vector3],
		ring_min: float, ring_max: float, gap: float) -> Node3D:
	for _try in 40:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(ring_min, ring_max)
		var xz := centre + Vector2(cos(a), sin(a)) * r
		if not _buildable(xz):
			continue
		var pos := Vector3(xz.x, _height(xz), xz.y)
		var clear := true
		for p in placed:
			if p.distance_to(pos) < gap:
				clear = false
				break
		if not clear:
			continue
		var node := _spawn_model(path, pos, (centre - xz).angle() + _rng.randf_range(-0.5, 0.5))
		if node == null:
			return null
		placed.append(pos)
		return node
	return null


## A broken ring of fence around the settlement. Broken on purpose: gaps are
## where the paths are, and a perfect ring reads as a stockade rather than as
## somebody's boundary.
func _place_fence(centre: Vector2, placed: Array[Vector3]) -> void:
	if fence_runs <= 0:
		return
	var radius := house_ring_outer * 1.05
	# One section is 5.89 m as imported, scaled by MODEL_SCALE. Stepping by
	# exactly that arc keeps the posts of adjacent sections meeting.
	var section_width: float = 5.89 * float(MODEL_SCALE.get("Fence", 1.0))
	var step: float = section_width / radius
	for run in fence_runs:
		# Runs are spread around the ring with jitter, so the gaps between
		# them (where the paths are) fall in different places per village.
		var start: float = TAU * (float(run) + _rng.randf_range(-0.18, 0.18)) / float(fence_runs)
		var count: int = _rng.randi_range(fence_run_length_min, fence_run_length_max)
		for i in count:
			var a: float = start + float(i) * step
			var xz: Vector2 = centre + Vector2(cos(a), sin(a)) * radius
			if not _buildable(xz):
				continue
			var pos := Vector3(xz.x, _height(xz), xz.y)
			# The section runs ALONG the ring, so it is turned to face out.
			_spawn_model(FENCE_MODEL, pos, a)


## OBJ and glTF are loaded by completely different importers and need
## completely different handling.
##
## An .obj arrives as a Mesh whose .mtl carries LINEAR colour values, which is
## why they need the ^(1/2.2) correction below — this project spent three
## separate debugging sessions on models importing near-black before that was
## understood. A .glb arrives as a PackedScene whose materials are already
## correct, and applying the same correction to it would wash every one of
## them out. So: instantiate the scene, touch nothing.
func _spawn_model(path: String, pos: Vector3, yaw: float) -> Node3D:
	var node: Node3D = null
	if path.ends_with(".glb") or path.ends_with(".gltf"):
		var packed: PackedScene = load(path)
		if packed == null:
			push_warning("VillageBuildings: could not load %s" % path)
			return null
		node = packed.instantiate()
		_set_visibility_range(node, house_visibility_range_end)
		var factor: float = float(MODEL_SCALE.get(path.get_file().get_basename(), 1.0))
		if not is_equal_approx(factor, 1.0):
			node.scale = Vector3.ONE * factor
	else:
		var mesh: Mesh = _load_building(path)
		if mesh == null:
			return null
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.visibility_range_end = house_visibility_range_end
		node = mi
	node.name = "Prop_%s" % path.get_file().get_basename()
	add_child(node)
	node.global_position = pos
	node.rotation.y = yaw
	return node


## visibility_range_end lives on each GeometryInstance3D, and an imported glTF
## scene is a tree of them. Without this a village's props are submitted from
## the far side of the island.
func _set_visibility_range(n: Node, range_end: float) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).visibility_range_end = range_end
	for c in n.get_children():
		_set_visibility_range(c, range_end)

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

## Loads a building model and lifts its materials into the visible range.
##
## The .mtl files carry LINEAR diffuse values straight out of Blender —
## House_1's nine surfaces measure 0.343, 0.122, 0.308, 0.028, 0.213, 0.124,
## 0.078, 0.015, 0.177. Godot imports those as albedo unchanged, which is
## technically faithful and visually useless: under this project's deliberately
## low exposure (tonemap_exposure 0.52, chosen so the ocean does not blow out)
## every house rendered as a black silhouette. Verified by reading the imported
## materials, not by guessing.
##
## Raising each channel by ^(1/2.2) recovers roughly the value the artist saw
## in Blender's own viewport — 0.028 becomes 0.19, 0.343 becomes 0.61 — which
## is what "looks like the model" means in practice.
##
## Materials are duplicated before editing: the imported Mesh is a shared
## resource, so mutating it in place would write through Godot's resource cache
## and silently affect anything else that loads the same model.
var _model_cache: Dictionary = {}

func _load_building(path: String) -> Mesh:
	if _model_cache.has(path):
		return _model_cache[path]
	var mesh: Mesh = load(path)
	if mesh == null:
		push_warning("VillageBuildings: could not load %s" % path)
		return null
	for i in mesh.get_surface_count():
		var mat = mesh.surface_get_material(i)
		if mat is StandardMaterial3D:
			var m: StandardMaterial3D = mat.duplicate()
			var c: Color = m.albedo_color
			m.albedo_color = Color(pow(c.r, 1.0 / 2.2), pow(c.g, 1.0 / 2.2), pow(c.b, 1.0 / 2.2), c.a)
			m.roughness = 0.9
			m.metallic = 0.0
			mesh.surface_set_material(i, m)
	_model_cache[path] = mesh
	return mesh

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
