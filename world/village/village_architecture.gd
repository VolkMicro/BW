extends RefCounted
class_name VillageArchitecture
## Procedural buildings: the god's temple, and the houses people live in.
##
## ---------------------------------------------------------------------------
## THE REGISTER, AND WHY THIS ONE
## ---------------------------------------------------------------------------
## Northern timber building: steep pitched roofs (snow slides off), tiered
## gables, heavy corner posts, shingled slopes, carved prows at the ridge ends.
## That silhouette is unmistakable at a distance, which is the whole job here —
## a god looking down must be able to tell a temple from a dwelling in one
## glance, without a label.
##
## This is ARCHITECTURE, not iconography. `docs/audit/respect_audit.md` forbids
## using any real sacred symbol, and nothing here is one: no cross, no runic
## inventory, no motif borrowed from a living practice. Steep roofs, posts and
## carved beam-ends are structural answers to snow and timber, used by many
## northern building traditions and owned by none of them. The prows are
## deliberately abstract — a tapered, curled beam-end, not a recognisable
## creature from anyone's mythology.
##
## ---------------------------------------------------------------------------
## WHY THE TEMPLE IS BUILT AROUND THE EXISTING SANCTUM RATHER THAN REPLACING IT
## ---------------------------------------------------------------------------
## `world/sanctum/sanctum.tscn` already carries real gameplay: a hollow CSG
## shell you can walk inside, its collision, the doorway, the altar and its
## offering trigger, and the scorch/glow materials that `sanctum.gd` drives
## from the village's hp and faith. Replacing that geometry would mean
## reimplementing all of it.
##
## So the temple is a SUPERSTRUCTURE: a tall tiered roof, corner posts and
## ridge carvings that sit over and around the existing box. The box becomes
## the hall's lower wall, mostly hidden, still walkable, still collidable,
## still tinted by its own script. The silhouette changes completely; nothing
## that worked stops working.

# Shared palette. Culture colour is multiplied in per instance by the caller,
# so these are relative values — a dark stained timber, a lighter beam, a
# weathered shingle — not final colours.
const TIMBER_DARK := Color(0.20, 0.155, 0.115, 0.0)
const TIMBER_LIGHT := Color(0.33, 0.26, 0.185, 0.0)
const SHINGLE := Color(0.235, 0.215, 0.20, 0.0)
const SHINGLE_LIT := Color(0.35, 0.325, 0.30, 0.0)
const THATCH := Color(0.42, 0.35, 0.20, 0.0)

# ---------------------------------------------------------------------------
# Public builders
# ---------------------------------------------------------------------------

## The god's temple. Tall, tiered, meant to be read from the air.
##
## `width` is the footprint side. The existing Sanctum shell is 7 m, so the
## default deliberately clears it.
static func build_temple(width: float = 9.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half := width * 0.5
	# Three roof tiers of decreasing footprint. Tiering is what separates a
	# temple from a big house: a house has one roof, a temple has a stack of
	# them, and the stack reads as height from any angle.
	var tiers := [
		{"half": half, "base": 3.4, "rise": 2.6, "eave": 1.15},
		{"half": half * 0.72, "base": 5.6, "rise": 2.3, "eave": 1.10},
		{"half": half * 0.46, "base": 7.4, "rise": 2.6, "eave": 1.05},
	]
	for t in tiers:
		_gabled_roof(st, t.half * t.eave, t.base, t.rise, SHINGLE, SHINGLE_LIT)

	# Corner posts, running from the ground up past the first eave. These are
	# what make it read as built rather than moulded.
	var post_r := width * 0.045
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_post(st, Vector3(sx * half * 0.92, 0.0, sz * half * 0.92), post_r, 4.2, TIMBER_DARK, TIMBER_LIGHT)

	# Ridge prows: a tapered beam-end curling up at each end of the top ridge.
	# Abstract on purpose — see the register note at the top of this file.
	var top: Dictionary = tiers[2]
	var ridge_y: float = top.base + top.rise
	_prow(st, Vector3(0.0, ridge_y, top.half * top.eave), 1.0, TIMBER_LIGHT)
	_prow(st, Vector3(0.0, ridge_y, -top.half * top.eave), -1.0, TIMBER_LIGHT)

	st.generate_normals()
	return st.commit()

## A dwelling. One roof, low walls, a stubby chimney — small enough that ten of
## them around a Sanctum read as a village rather than as a second temple.
static func build_house(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var w: float = rng.randf_range(3.0, 4.2)
	var l: float = w * rng.randf_range(1.3, 1.9)   # longhouses, not cubes
	var wall_h: float = rng.randf_range(1.5, 2.0)
	var rise: float = rng.randf_range(1.7, 2.4)

	_box(st, Vector3(-w * 0.5, 0.0, -l * 0.5), Vector3(w * 0.5, wall_h, l * 0.5),
		TIMBER_DARK, TIMBER_LIGHT)
	_gabled_roof_rect(st, w * 0.5 * 1.18, l * 0.5 * 1.10, wall_h, rise, THATCH,
		THATCH.lightened(0.14))

	# Chimney, offset off the ridge so the row of houses does not look stamped.
	var cx: float = rng.randf_range(-w * 0.22, w * 0.22)
	var cz: float = rng.randf_range(-l * 0.25, l * 0.25)
	_box(st, Vector3(cx - 0.16, wall_h, cz - 0.16), Vector3(cx + 0.16, wall_h + rise + 0.5, cz + 0.16),
		Color(0.24, 0.22, 0.21, 0.0), Color(0.30, 0.28, 0.27, 0.0))

	st.generate_normals()
	return st.commit()

# ---------------------------------------------------------------------------
# Primitives
# ---------------------------------------------------------------------------

## A square gabled roof: two sloping faces meeting at a ridge, plus the two
## triangular gable ends that close it.
static func _gabled_roof(st: SurfaceTool, half: float, base_y: float,
		rise: float, low: Color, high: Color) -> void:
	_gabled_roof_rect(st, half, half, base_y, rise, low, high)

## Rectangular version — `hx` across, `hz` along the ridge.
static func _gabled_roof_rect(st: SurfaceTool, hx: float, hz: float, base_y: float,
		rise: float, low: Color, high: Color) -> void:
	var ridge_y := base_y + rise
	var a := Vector3(-hx, base_y, -hz)
	var b := Vector3(hx, base_y, -hz)
	var c := Vector3(hx, base_y, hz)
	var d := Vector3(-hx, base_y, hz)
	var r0 := Vector3(0.0, ridge_y, -hz)
	var r1 := Vector3(0.0, ridge_y, hz)

	# Two slopes.
	_quad(st, a, d, r1, r0, low, low, high, high)
	_quad(st, c, b, r0, r1, low, low, high, high)
	# Two gable ends.
	_tri(st, a, r0, b, low, high, low)
	_tri(st, c, r1, d, low, high, low)
	# Underside, so the roof is solid from below when the camera drops.
	_quad(st, a, b, c, d, low, low, low, low)

static func _post(st: SurfaceTool, at: Vector3, r: float, h: float,
		low: Color, high: Color) -> void:
	var seg := 5
	for i in seg:
		var a0: float = TAU * float(i) / float(seg)
		var a1: float = TAU * float(i + 1) / float(seg)
		var p0 := at + Vector3(cos(a0) * r, 0.0, sin(a0) * r)
		var p1 := at + Vector3(cos(a1) * r, 0.0, sin(a1) * r)
		var q0 := p0 + Vector3.UP * h
		var q1 := p1 + Vector3.UP * h
		_quad(st, p0, p1, q1, q0, low, low, high, high)

## A tapered beam-end curling upward and outward from the ridge.
static func _prow(st: SurfaceTool, at: Vector3, dir: float, tint: Color) -> void:
	var steps := 4
	var prev_a := at + Vector3(-0.14, 0.0, 0.0)
	var prev_b := at + Vector3(0.14, 0.0, 0.0)
	for i in range(1, steps + 1):
		var t := float(i) / float(steps)
		# Out along the ridge and up, curling: the rise accelerates while the
		# beam narrows, which is what gives it the hooked look.
		var p := at + Vector3(0.0, t * t * 1.5, dir * t * 1.5)
		var wdt: float = lerpf(0.14, 0.035, t)
		var a := p + Vector3(-wdt, 0.0, 0.0)
		var b := p + Vector3(wdt, 0.0, 0.0)
		var shade := tint.lightened(t * 0.18)
		_quad(st, prev_a, prev_b, b, a, tint, tint, shade, shade)
		prev_a = a
		prev_b = b

static func _box(st: SurfaceTool, lo: Vector3, hi: Vector3, low: Color, high: Color) -> void:
	var p := [
		Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z),
		Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z),
		Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z),
		Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z),
	]
	_quad(st, p[0], p[1], p[5], p[4], low, low, high, high) # -Z
	_quad(st, p[2], p[3], p[7], p[6], low, low, high, high) # +Z
	_quad(st, p[1], p[2], p[6], p[5], low, low, high, high) # +X
	_quad(st, p[3], p[0], p[4], p[7], low, low, high, high) # -X
	_quad(st, p[4], p[5], p[6], p[7], high, high, high, high) # top

## Counter-clockwise when seen from the front. The winding matters: this
## project spent days on an inverted-winding bug that made an entire island
## invisible (see world/terrain/island_generator.gd). Meshes here are built to
## be viewed with `cull_back`, and `generate_normals()` derives normals from
## this order, so getting it wrong shows up immediately as a black face.
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	_tri(st, a, b, c, ca, cb, cc)
	_tri(st, a, c, d, ca, cc, cd)

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ca: Color, cb: Color, cc: Color) -> void:
	st.set_color(ca); st.add_vertex(a)
	st.set_color(cb); st.add_vertex(b)
	st.set_color(cc); st.add_vertex(c)
