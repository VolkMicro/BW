extends RefCounted
class_name WildlifeBody
## PACKAGE W (wildlife) — procedural body builder. Godot primitive meshes
## only (CapsuleMesh / SphereMesh / BoxMesh / CylinderMesh), assembled in
## code, matching this project's established "procedural over hand-authored
## art" convention (every docs/systems/*.md records "Assets used: None").
## Nothing here is downloaded, imported, or hand-modelled.
##
## PERFORMANCE — this is the whole reason this file exists as a separate,
## static, cached builder instead of `_add_part()`-ing eight MeshInstance3D
## children onto every creature the way `actors/avatar/avatar.gd` does for
## the single Avatar:
##
##   1. All the primitives for one species are merged, ONCE, into a single
##      `ArrayMesh` with exactly two surfaces (primary + accent) via
##      `SurfaceTool.append_from()`. So a creature is 1 MeshInstance3D and
##      2 surfaces, not 8-14 MeshInstance3D children — the target hardware
##      is integrated Intel graphics at ~5-6 fps and per-node/per-draw
##      overhead is exactly the wrong thing to multiply by a herd.
##   2. The result is cached per species id, so all twelve rimefleeces share
##      ONE Mesh resource and TWO StandardMaterial3D instances. Twelve
##      creatures do not mean twelve mesh uploads, twelve materials, or
##      twelve shader variants — the renderer sorts them into one material
##      batch.
##   3. Every primitive is built at deliberately low tessellation
##      (radial_segments 6-8, rings 1-4) instead of Godot's defaults
##      (SphereMesh defaults to 64x32 = ~4k verts, which would be absurd for
##      a background critter seen from god-view height).
##
## Honest limit: shared Mesh + shared Material reduces state changes and VRAM,
## it does NOT collapse a herd into one draw call. That would need a
## MultiMeshInstance3D, which is explicitly scoped out in
## docs/systems/wildlife.md (it is the documented next lever if a real
## profile on the Latitude ever shows wildlife draw calls mattering).

const _SEG_ROUND := 8
const _SEG_RINGS := 3
const _SEG_CYL := 6

static var _mesh_cache: Dictionary = {}


## Returns the shared, cached ArrayMesh for a species (built on first call).
## Surface 0 = primary color, surface 1 = accent color. May return null only
## if SurfaceTool produced nothing, which wild_creature.gd handles with a
## visible fallback capsule rather than an invisible animal.
static func mesh_for(species: WildlifeSpecies) -> ArrayMesh:
	if species == null:
		return null
	var key: StringName = species.id
	if _mesh_cache.has(key):
		var cached: ArrayMesh = _mesh_cache[key]
		return cached
	var primary: Array = []
	var accent: Array = []
	match key:
		&"rimefleece":
			_build_rimefleece(primary, accent)
		&"snagbill":
			_build_snagbill(primary, accent)
		&"thawjaw":
			_build_thawjaw(primary, accent)
		_:
			_build_generic(primary, accent)
	var mesh := _merge(primary, accent, species.color_primary, species.color_accent)
	_mesh_cache[key] = mesh
	return mesh


## Test/QA hook: drop the cache so a retuned .tres rebuilds its geometry.
## Never called in normal play.
static func clear_cache() -> void:
	_mesh_cache.clear()


# ---------------------------------------------------------------------------
# Primitive helpers — all low-tessellation on purpose (see header).
# ---------------------------------------------------------------------------
static func _capsule(radius: float, height: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = radius
	# CapsuleMesh requires height >= 2*radius; clamp rather than trip an
	# engine error if a .tres is ever retuned to something degenerate.
	m.height = maxf(height, radius * 2.0 + 0.01)
	m.radial_segments = _SEG_ROUND
	m.rings = 2
	return m


static func _sphere(radius: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = _SEG_ROUND
	m.rings = _SEG_RINGS
	return m


static func _box(sx: float, sy: float, sz: float) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = Vector3(sx, sy, sz)
	return m


static func _cyl(top_r: float, bottom_r: float, height: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top_r
	m.bottom_radius = bottom_r
	m.height = height
	m.radial_segments = _SEG_CYL
	m.rings = 0
	return m


## Part record: [Mesh, Transform3D]. `pitch_deg`/`yaw_deg`/`roll_deg` are
## applied in that order about X/Y/Z.
static func _part(mesh: Mesh, pos: Vector3, pitch_deg: float = 0.0, roll_deg: float = 0.0) -> Array:
	var basis := Basis.IDENTITY
	if not is_zero_approx(pitch_deg):
		basis = basis.rotated(Vector3.RIGHT, deg_to_rad(pitch_deg))
	if not is_zero_approx(roll_deg):
		basis = basis.rotated(Vector3.BACK, deg_to_rad(roll_deg))
	return [mesh, Transform3D(basis, pos)]


static func _merge(primary: Array, accent: Array, c_primary: Color, c_accent: Color) -> ArrayMesh:
	var mesh: ArrayMesh = _surface_from(primary, null)
	if mesh == null:
		return null
	mesh = _surface_from(accent, mesh)
	var mat_p := StandardMaterial3D.new()
	mat_p.albedo_color = c_primary
	mat_p.roughness = 0.92
	mat_p.metallic = 0.0
	mesh.surface_set_material(0, mat_p)
	if mesh.get_surface_count() > 1:
		var mat_a := StandardMaterial3D.new()
		mat_a.albedo_color = c_accent
		mat_a.roughness = 0.78
		mat_a.metallic = 0.0
		mesh.surface_set_material(1, mat_a)
	return mesh


static func _surface_from(parts: Array, existing: ArrayMesh) -> ArrayMesh:
	if parts.is_empty():
		return existing
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for entry in parts:
		var part: Array = entry
		var src: Mesh = part[0]
		var xform: Transform3D = part[1]
		st.append_from(src, 0, xform)
	return st.commit(existing)


# ---------------------------------------------------------------------------
# Silhouettes. Forward is +Z (matches actors/avatar/avatar.gd's placeholder
# bodies and the `atan2(dir.x, dir.z)` yaw convention every actor in this
# project already uses). Local y = 0 is the ground the feet stand on.
# ---------------------------------------------------------------------------

## RIMEFLEECE — a low, broad woolly barrel slung between four stubby legs,
## small blunt head carried LOW (grazing posture) with a dark bare face.
## Reads at god-view distance as a wide pale lozenge close to the ground.
static func _build_rimefleece(primary: Array, accent: Array) -> void:
	primary.append(_part(_capsule(0.42, 1.30), Vector3(0.0, 0.70, 0.0), 90.0))
	primary.append(_part(_sphere(0.31), Vector3(0.0, 0.78, -0.58)))          # rump wool
	primary.append(_part(_sphere(0.26), Vector3(0.0, 0.80, 0.42)))           # shoulder wool
	accent.append(_part(_box(0.30, 0.28, 0.40), Vector3(0.0, 0.56, 0.80), -16.0))
	accent.append(_part(_box(0.18, 0.15, 0.20), Vector3(0.0, 0.47, 0.99), -16.0))
	accent.append(_part(_cyl(0.055, 0.05, 0.20), Vector3(0.0, 0.83, -0.82), 42.0))
	var rf_leg_x: Array[float] = [-0.23, 0.23]
	var rf_leg_z: Array[float] = [-0.36, 0.40]
	for sx in rf_leg_x:
		for sz in rf_leg_z:
			accent.append(_part(_cyl(0.07, 0.06, 0.52), Vector3(sx, 0.26, sz)))


## SNAGBILL — tall, nervy, top-heavy: a small slate body on two thin legs,
## long thin neck, hooked pale bill, half-open box wings. Reads as a
## vertical dark tick mark next to whatever it is waiting to finish dying.
static func _build_snagbill(primary: Array, accent: Array) -> void:
	primary.append(_part(_capsule(0.20, 0.54), Vector3(0.0, 0.52, 0.0), 90.0))
	primary.append(_part(_box(0.07, 0.26, 0.42), Vector3(-0.22, 0.56, -0.02), 0.0, 13.0))
	primary.append(_part(_box(0.07, 0.26, 0.42), Vector3(0.22, 0.56, -0.02), 0.0, -13.0))
	primary.append(_part(_box(0.16, 0.05, 0.36), Vector3(0.0, 0.50, -0.38), 14.0))
	primary.append(_part(_sphere(0.13), Vector3(0.0, 0.86, 0.10)))
	accent.append(_part(_cyl(0.06, 0.065, 0.30), Vector3(0.0, 0.70, 0.05), 10.0))
	accent.append(_part(_box(0.06, 0.06, 0.26), Vector3(0.0, 0.85, 0.29), -14.0))
	accent.append(_part(_box(0.05, 0.10, 0.06), Vector3(0.0, 0.80, 0.40)))   # the snag
	accent.append(_part(_box(0.10, 0.06, 0.13), Vector3(0.0, 0.71, -0.02)))  # pale throat
	var sb_leg_x: Array[float] = [-0.09, 0.09]
	for sx in sb_leg_x:
		accent.append(_part(_cyl(0.035, 0.032, 0.44), Vector3(sx, 0.22, 0.01)))


## THAWJAW — long, low and heavy-fronted: deep box chest, wedge head thrust
## forward on a short thick neck, pale jaw, a ridge of plates down the
## spine, and legs long enough that it is obviously faster than anything it
## is standing near. Reads as a dark horizontal bar with a bright jaw.
static func _build_thawjaw(primary: Array, accent: Array) -> void:
	primary.append(_part(_capsule(0.36, 1.55), Vector3(0.0, 0.88, -0.10), 90.0))
	primary.append(_part(_box(0.70, 0.58, 0.52), Vector3(0.0, 0.92, 0.46)))
	primary.append(_part(_cyl(0.19, 0.22, 0.44), Vector3(0.0, 0.96, 0.80), 72.0))
	primary.append(_part(_box(0.32, 0.30, 0.54), Vector3(0.0, 0.94, 1.14), -6.0))
	primary.append(_part(_capsule(0.09, 0.60), Vector3(0.0, 0.76, -1.02), 104.0))
	var tj_leg_x: Array[float] = [-0.26, 0.26]
	var tj_leg_z: Array[float] = [-0.56, 0.44]
	for sx in tj_leg_x:
		for sz in tj_leg_z:
			primary.append(_part(_cyl(0.10, 0.075, 0.82), Vector3(sx, 0.41, sz)))
	accent.append(_part(_box(0.25, 0.13, 0.46), Vector3(0.0, 0.79, 1.19)))
	var ridge_z: Array[float] = [0.28, -0.04, -0.36, -0.68]
	for z in ridge_z:
		accent.append(_part(_box(0.08, 0.17, 0.13), Vector3(0.0, 1.22, z), 8.0))


## Fallback for an unknown species id — deliberately obvious (a plain
## quadruped block) so a typo'd id is visible in-scene rather than silent.
static func _build_generic(primary: Array, accent: Array) -> void:
	primary.append(_part(_capsule(0.30, 0.90), Vector3(0.0, 0.62, 0.0), 90.0))
	accent.append(_part(_sphere(0.20), Vector3(0.0, 0.66, 0.55)))
	var g_leg_x: Array[float] = [-0.18, 0.18]
	var g_leg_z: Array[float] = [-0.28, 0.28]
	for sx in g_leg_x:
		for sz in g_leg_z:
			accent.append(_part(_cyl(0.06, 0.05, 0.44), Vector3(sx, 0.22, sz)))
