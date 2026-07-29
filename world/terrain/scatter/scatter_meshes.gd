extends RefCounted
class_name ScatterMeshes
## Procedural, code-only meshes for the terrain scatter layer: one grass
## clump, one tree, one boulder. No imported art — every vertex here is
## generated from Godot primitives / SurfaceTool, matching this project's
## established "Assets used: None" convention.
##
## Three deliberate design rules, because these meshes are drawn thousands of
## times through a MultiMesh on integrated graphics:
##
## 1. **One surface per mesh.** A MultiMesh issues one draw call *per surface*
##    of its mesh, so a tree whose trunk and canopy were separate surfaces
##    would cost two draw calls for the whole forest instead of one. Trunk and
##    canopy are therefore the same surface, told apart by VERTEX COLOR
##    (`world/terrain/scatter/scatter_foliage.gdshader` reads `COLOR.rgb` as
##    albedo), not by material.
##
## 2. **`COLOR.a` is a wind/sway mask, not opacity.** The shader is opaque and
##    never writes ALPHA; it uses the alpha channel as "how much does this
##    vertex move in the wind" — 0 at a trunk base or on a rock, 1 at a grass
##    tip. It rides in the vertex colour stream that already exists, so it is
##    free.
##
## 3. **Grass normals point straight up, on both faces of every blade.** A
##    grass blade is drawn as two coincident triangles with opposite winding
##    (so `cull_back` keeps exactly one of them from any viewpoint) and both
##    carry NORMAL = +Y. Blades therefore catch the sun the same way the
##    ground under them does, instead of half the tuft going black because its
##    true normal is horizontal and facing away from the sun. This is also why
##    the grass material does NOT use `cull_disabled`: Godot flips the shading
##    normal on a back face, which is the exact failure mode round four of the
##    low-spec work documented on the terrain shader.

# --------------------------------------------------------------------------
# Grass
# --------------------------------------------------------------------------

## A tuft of `blades` tapered blades on a small disc. Two triangles per blade
## (front + back winding) => `blades * 2` triangles. Deterministic in `rng`.
static func build_grass_clump(rng: RandomNumberGenerator, blades: int = 6,
		spread: float = 0.42, min_height: float = 0.55, max_height: float = 1.05) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in maxi(blades, 1):
		var ang: float = rng.randf() * TAU
		var rad: float = sqrt(rng.randf()) * spread
		var base := Vector3(cos(ang) * rad, 0.0, sin(ang) * rad)
		var half_w: float = rng.randf_range(0.05, 0.085)
		var height: float = rng.randf_range(min_height, max_height)
		var lean: float = rng.randf_range(0.10, 0.36)
		var side := Vector3(-sin(ang), 0.0, cos(ang)) * half_w
		var tip := base + Vector3(cos(ang) * lean, height, sin(ang) * lean)
		var shade: float = rng.randf_range(0.82, 1.16)
		var c_base := Color(0.13 * shade, 0.26 * shade, 0.09 * shade, 0.0)
		var c_tip := Color(0.30 * shade, 0.52 * shade, 0.16 * shade, 1.0)
		var v0 := base - side
		var v1 := base + side
		# Front face and back face, both with an up-facing shading normal.
		_tri(st, v0, v1, tip, c_base, c_base, c_tip, Vector3.UP)
		_tri(st, v1, v0, tip, c_base, c_base, c_tip, Vector3.UP)
	st.index()
	return st.commit()

# --------------------------------------------------------------------------
# Tree
# --------------------------------------------------------------------------

## Trunk cylinder + three stacked capped cones, one surface, vertex-coloured.
## `segments` 7 gives a readable stylised silhouette at god-view scale:
## 7*2 (trunk sides) + 3*(7 + 5) (cone sides + fan caps) = 50 triangles.
static func build_tree(segments: int = 7, trunk_height: float = 2.0,
		trunk_radius: float = 0.20) -> ArrayMesh:
	var seg := maxi(segments, 3)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var total_height: float = 6.0
	var bark_dark := Color(0.20, 0.145, 0.095)
	var bark_light := Color(0.30, 0.22, 0.145)

	# --- trunk (open cylinder; its cap is never visible, it is buried) ---
	for i in seg:
		var a0: float = TAU * float(i) / float(seg)
		var a1: float = TAU * float(i + 1) / float(seg)
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		var b0 := d0 * trunk_radius
		var b1 := d1 * trunk_radius
		var t0 := d0 * (trunk_radius * 0.66) + Vector3.UP * trunk_height
		var t1 := d1 * (trunk_radius * 0.66) + Vector3.UP * trunk_height
		var ca := _with_sway(bark_dark, 0.0, total_height)
		var cb := _with_sway(bark_light, trunk_height, total_height)
		_tri(st, b0, t0, b1, ca, cb, ca, d0)
		_tri(st, b1, t0, t1, ca, cb, cb, d1)

	# --- canopy: three cones, darker at the bottom ---
	_cone(st, seg, 1.35, 1.55, 2.3, Color(0.115, 0.235, 0.105), total_height)
	_cone(st, seg, 2.75, 1.18, 2.05, Color(0.145, 0.295, 0.125), total_height)
	_cone(st, seg, 3.95, 0.78, 2.05, Color(0.185, 0.355, 0.145), total_height)

	st.index()
	return st.commit()

## One capped cone: ring of `seg` verts at `base_y` with radius `radius`,
## apex at `base_y + height`, plus a downward-facing triangle-fan cap so the
## underside is not see-through under `cull_back`.
static func _cone(st: SurfaceTool, seg: int, base_y: float, radius: float,
		height: float, tint: Color, total_height: float) -> void:
	var apex := Vector3(0.0, base_y + height, 0.0)
	var c_apex := _with_sway(tint.lightened(0.10), apex.y, total_height)
	var c_ring := _with_sway(tint, base_y, total_height)
	var ring: Array[Vector3] = []
	for i in seg:
		var a: float = TAU * float(i) / float(seg)
		ring.append(Vector3(cos(a) * radius, base_y, sin(a) * radius))
	for i in seg:
		var v0: Vector3 = ring[i]
		var v1: Vector3 = ring[(i + 1) % seg]
		# Outward-ish normal for the sloped side.
		var n := (v0 + v1).normalized().lerp(Vector3.UP, 0.45).normalized()
		_tri(st, v0, apex, v1, c_ring, c_apex, c_ring, n)
	for i in range(1, seg - 1):
		_tri(st, ring[0], ring[i], ring[i + 1], c_ring, c_ring, c_ring, Vector3.DOWN)

# --------------------------------------------------------------------------
# Boulder
# --------------------------------------------------------------------------

## A squashed, dented low-poly sphere. Built from `SphereMesh`'s own arrays
## (so the topology is Godot's, not hand-rolled), then displaced by a hash of
## each vertex's position — position-based rather than index-based so the two
## duplicate vertices on the UV seam and at the poles move identically and no
## crack opens up. Normals are regenerated after displacement.
static func build_boulder(radial_segments: int = 7, rings: int = 4,
		dent: float = 0.26, squash: float = 0.62) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = maxi(radial_segments, 3)
	sphere.rings = maxi(rings, 2)
	var arrays: Array = sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]

	var moved := PackedVector3Array()
	moved.resize(verts.size())
	for i in verts.size():
		var p: Vector3 = verts[i]
		var dir: Vector3 = p.normalized() if p.length_squared() > 1e-8 else Vector3.UP
		var h: float = _hash_pos(p)
		var q: Vector3 = p + dir * (h - 0.5) * dent
		q.y *= squash
		moved[i] = q

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in indices.size():
		var v: Vector3 = moved[indices[i]]
		var shade: float = 0.86 + _hash_pos(v * 3.1) * 0.28
		st.set_color(Color(0.315 * shade, 0.305 * shade, 0.285 * shade, 0.0))
		st.set_normal(Vector3.UP)
		st.add_vertex(v)
	st.generate_normals()
	st.index()
	return st.commit()

# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ca: Color, cb: Color, cc: Color, n: Vector3) -> void:
	st.set_normal(n)
	st.set_color(ca)
	st.add_vertex(a)
	st.set_normal(n)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_normal(n)
	st.set_color(cc)
	st.add_vertex(c)

## Packs the sway mask into the alpha channel: nothing at the ground, full at
## the top of the silhouette, biased so the lower trunk stays nearly still.
static func _with_sway(c: Color, y: float, total_height: float) -> Color:
	var t: float = clampf(y / maxf(total_height, 0.001), 0.0, 1.0)
	return Color(c.r, c.g, c.b, pow(t, 1.6))

static func _hash_pos(p: Vector3) -> float:
	var v: float = sin(p.x * 127.1 + p.y * 311.7 + p.z * 74.7) * 43758.5453
	return v - floor(v)

## Triangle count of a built mesh, for the honest cost figures the scatter
## node reports (see TerrainScatter.get_stats()).
static func triangle_count(mesh: Mesh) -> int:
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	var total: int = 0
	for s in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if idx.size() > 0:
			total += idx.size() / 3
		else:
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			total += verts.size() / 3
	return total

# --------------------------------------------------------------------------
# Villager
# --------------------------------------------------------------------------

## One person, for `VillagerCrowd`'s MultiMesh. Deliberately tiny: a tapered
## body and a head, ~40 triangles.
##
## The temptation is to make this better-looking. Resist it — this mesh is
## instanced up to ~600 times in a single draw call on integrated graphics, so
## every triangle here is paid six hundred times over, and at the distance a
## god actually watches from what carries is the SILHOUETTE and the fact that
## it moves. A tapered upright blob with a head reads unmistakably as a person
## at fifty metres; the detail budget belongs to the things the camera stops
## on, not to the crowd.
##
## COLOR.a is 0 everywhere so that if these are ever drawn with the foliage
## shader (which uses alpha as a wind-sway mask) they stand still rather than
## swaying like grass.
static func build_villager(height: float = 1.7) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var seg := 6
	var hip := height * 0.42
	var shoulder := height * 0.80
	var head_y := height * 0.90
	var r_hip := height * 0.115
	var r_shoulder := height * 0.095

	var cloth := Color(0.30, 0.26, 0.21, 0.0)
	var cloth_lit := Color(0.40, 0.35, 0.29, 0.0)
	var skin := Color(0.52, 0.40, 0.31, 0.0)

	# Body: a closed tapered prism from hip to shoulder, plus a skirt down to
	# the ground so there are no legs to animate and nothing to intersect the
	# terrain awkwardly on a slope.
	for i in seg:
		var a0: float = TAU * float(i) / float(seg)
		var a1: float = TAU * float(i + 1) / float(seg)
		var b0 := Vector3(cos(a0) * r_hip, 0.0, sin(a0) * r_hip)
		var b1 := Vector3(cos(a1) * r_hip, 0.0, sin(a1) * r_hip)
		var h0 := Vector3(cos(a0) * r_hip, hip, sin(a0) * r_hip)
		var h1 := Vector3(cos(a1) * r_hip, hip, sin(a1) * r_hip)
		var s0 := Vector3(cos(a0) * r_shoulder, shoulder, sin(a0) * r_shoulder)
		var s1 := Vector3(cos(a1) * r_shoulder, shoulder, sin(a1) * r_shoulder)
		var n := (b0 + b1).normalized()
		_tri(st, b0, h1, b1, cloth, cloth, cloth, n)
		_tri(st, b0, h0, h1, cloth, cloth, cloth, n)
		_tri(st, h0, s1, h1, cloth, cloth_lit, cloth, n)
		_tri(st, h0, s0, s1, cloth, cloth_lit, cloth_lit, n)

	# Head: a small octahedron. Cheaper than a sphere and, at this size, reads
	# the same.
	var top := Vector3(0.0, head_y + height * 0.10, 0.0)
	var bot := Vector3(0.0, head_y - height * 0.03, 0.0)
	var hr := height * 0.062
	for i in 4:
		var a0: float = TAU * float(i) / 4.0
		var a1: float = TAU * float(i + 1) / 4.0
		var e0 := Vector3(cos(a0) * hr, head_y + height * 0.035, sin(a0) * hr)
		var e1 := Vector3(cos(a1) * hr, head_y + height * 0.035, sin(a1) * hr)
		_tri(st, e0, top, e1, skin, skin, skin, (e0 + e1).normalized().lerp(Vector3.UP, 0.5).normalized())
		_tri(st, e1, bot, e0, skin, skin, skin, (e0 + e1).normalized().lerp(Vector3.DOWN, 0.5).normalized())

	return st.commit()
