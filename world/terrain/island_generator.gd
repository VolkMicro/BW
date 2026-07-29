extends Resource
class_name IslandGenerator
## Procedural island shape: a heightmap built from three layered
## FastNoiseLite passes (continent silhouette + ridged erosion-look detail +
## small-scale roughness), shaped by a radial falloff so the noise reads as
## an island rather than infinite terrain. Deterministic per `island_seed` +
## `size_meters` + `resolution`, so the same three numbers always reproduce
## the same island — no mesh data needs to be saved to disk.
##
## This is the reusable "island shape" API the brief asks for ("each island
## is a level"): construct one of these per island with a different seed,
## call build_mesh() / build_heightmap_shape(), and you have a new island of
## whatever size you want, without touching any other island's data.

@export var island_seed: int = 1
@export var size_meters: float = 256.0 ## island footprint, one side, meters
@export var resolution: int = 129 ## vertices per side (grid is resolution x resolution)
@export var max_height: float = 42.0
@export var sea_level: float = 0.0
@export var continent_noise_scale: float = 1.0
@export var ridge_noise_scale: float = 1.0
@export var detail_noise_scale: float = 1.0
@export var coastal_falloff_power: float = 2.2 ## higher = sharper coastline, lower = gentler shelf

var _continent_noise: FastNoiseLite
var _ridge_noise: FastNoiseLite
var _detail_noise: FastNoiseLite
var _noise_built: bool = false

var _cached_heights: PackedFloat32Array
var _cached_resolution: int = -1

## Noise is built lazily on first use rather than in _init(), because the
## normal usage pattern is `IslandGenerator.new()` followed by setting
## island_seed/size_meters/etc — building eagerly in _init() would bake in
## whatever the export defaults were at construction time and silently
## ignore every property set afterward.
func _ensure_noise() -> void:
	if _noise_built:
		return
	_build_noise()
	_noise_built = true

func _build_noise() -> void:
	_continent_noise = FastNoiseLite.new()
	_continent_noise.seed = island_seed
	_continent_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_continent_noise.frequency = 0.006 / maxf(continent_noise_scale, 0.001)
	_continent_noise.fractal_octaves = 4
	_continent_noise.fractal_gain = 0.5
	_continent_noise.fractal_lacunarity = 2.0

	# Ridge/detail octave counts below are capped so their finest octave's
	# wavelength stays well above 2x the default grid step (size_meters /
	# (resolution-1) = 256/128 = 2m). FRACTAL_RIDGED in particular turns
	# undersampled high-frequency content into sharp, chaotic, disconnected-
	# looking peaks rather than a gentle aliasing blur (verified: the
	# previous 5-octave/2.1-lacunarity ridge setting put its finest octave
	# at ~0.49 cycles/m, a ~2m wavelength sampled at a 2m grid step, which
	# rendered as shredded/spiky terrain instead of a smooth ridged mound).
	# If `resolution` or `size_meters` changes enough to move the grid step,
	# re-check these against the same >=4-samples-per-wavelength target
	# (i.e. keep each noise's finest-octave frequency below roughly
	# 1 / (4 * grid_step)).
	_ridge_noise = FastNoiseLite.new()
	_ridge_noise.seed = island_seed + 1013
	_ridge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_ridge_noise.frequency = 0.025 / maxf(ridge_noise_scale, 0.001)
	_ridge_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge_noise.fractal_octaves = 3
	_ridge_noise.fractal_gain = 0.55
	_ridge_noise.fractal_lacunarity = 2.1

	_detail_noise = FastNoiseLite.new()
	_detail_noise.seed = island_seed + 7331
	_detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_detail_noise.frequency = 0.06 / maxf(detail_noise_scale, 0.001)
	_detail_noise.fractal_octaves = 2
	_detail_noise.fractal_gain = 0.45

## Height (meters, relative to sea_level; negative = sea floor) at a point in
## this island's *local* XZ space (origin at island center). Pure function of
## seed + the three noise layers + radial mask — safe to call from other
## systems (village placement, the Hand, footstep raycasts) as long as they
## convert world position to this generator's local space first.
func height_at(local_x: float, local_z: float) -> float:
	_ensure_noise()
	var half := size_meters * 0.5
	var nx := local_x / half
	var nz := local_z / half
	var r := sqrt(nx * nx + nz * nz)
	var mask := clampf(1.0 - pow(r, coastal_falloff_power), 0.0, 1.0)
	mask = smoothstep(0.0, 1.0, mask)

	var continent := _continent_noise.get_noise_2d(local_x, local_z) * 0.5 + 0.5 # 0..1
	var ridge := _ridge_noise.get_noise_2d(local_x, local_z) # ridged fractal, biased positive
	var detail := _detail_noise.get_noise_2d(local_x, local_z) # small-scale roughness

	# Ridge weight kept low relative to continent: FRACTAL_RIDGED has sharp
	# creases (a derivative discontinuity right at each ridge line) that a
	# heightfield mesh can only approximate with a real, short, steep V at
	# the sample resolution, regardless of noise frequency. At the original
	# 0.35 weight against a 42m max_height those local slopes went steep
	# enough to backface-cull from a normal outdoor camera angle (see
	# terrain_triplanar.gdshader's cull_disabled note) and read as
	# shredded holes rather than mountain relief. Lowered further to 0.1
	# (from an intermediate 0.2) per a "smoother, rolling-hills island"
	# request — combined with the post-sample smoothing pass in
	# _sample_grid(), this reads as gentle terrain with only soft
	# undulation, not a mountain range, while the continent layer alone
	# still keeps every island shape distinct per-seed.
	var shaped := continent * 0.86 + ridge * 0.1 + detail * 0.04
	var h := shaped * max_height * mask
	# Outside the island mask, sink toward a plausible sea floor instead of a
	# hard cliff at the heightmap's border.
	h -= (1.0 - mask) * max_height * 0.35
	return h + sea_level

## A light box blur run BEFORE erosion, only to take the sharpest per-cell
## creases off the raw ridged noise so droplets do not spend their whole life
## trapped in one-cell pits. Erosion does the real shaping now, so this is 1
## pass rather than the 2 it used to be. 0 disables it.
##
## Note it applies to the sampled grid, not to height_at() — that function
## stays the raw analytic value. Anything that needs to agree with the
## surface a player actually sees and collides with must call
## sample_smoothed_height() instead, which reads this same eroded grid.
@export var smoothing_passes: int = 1

# ---------------------------------------------------------------------------
# HYDRAULIC EROSION
#
# Blurring is not erosion. A blur removes detail evenly everywhere, which is
# precisely why this island used to read as a smooth mesa: it had no valleys,
# because nothing had ever run down it. Real terrain looks the way it does
# because water carved it, and the cheapest honest way to get that is to
# simulate the water.
#
# Standard particle model. Each droplet spawns somewhere on the island, then
# repeatedly: reads the height gradient under itself, steers downhill (with
# some inertia so it does not snap to the steepest neighbour and produce
# staircase artefacts), moves one cell, and compares how much sediment it is
# carrying against how much it *could* carry at its current speed and slope.
# Under capacity, it scoops terrain up; over capacity — or moving uphill — it
# drops sediment, which is what fills basins and builds the gentle deltas
# where a valley meets flat ground.
#
# Two details make the difference between this working and not:
#
#  * THE SEA DRAIN. A droplet that reaches sea level is done — it has run
#    into the ocean. Without that, droplets pool at the coast and the
#    shoreline gets a ring of deposited silt instead of river mouths. This is
#    the failure mode Nick McDonald's hydrology write-up calls out (pools
#    treating the map boundary as a wall); an island makes the fix trivial,
#    since the boundary genuinely is a drain.
#
#  * ERODING THROUGH A BRUSH, not a single cell. Removing height from one
#    cell per step carves single-pixel spikes that look like noise and break
#    the normals. Each erosion event is spread over a small radius, weighted
#    by distance, so what appears is a channel rather than a needle.
#
# Cost is paid ONCE, at generation, on a 161x161 grid — it cannot touch frame
# rate at all, which matters because this project's target hardware is a
# laptop with integrated graphics (docs/systems/performance_lowspec.md).
# ---------------------------------------------------------------------------

## 0 disables erosion entirely and falls back to blur-only terrain.
@export var erosion_droplets: int = 22000
## Max steps a single droplet may take before it is abandoned.
@export var erosion_droplet_lifetime: int = 26
## How strongly a droplet keeps its heading vs. following the gradient.
## 0 = always straight down the steepest slope (staircase artefacts),
## 1 = never turns. Low values look like water, high values look like noise.
@export_range(0.0, 1.0) var erosion_inertia: float = 0.06
## Multiplier on how much sediment a droplet can carry for a given
## speed/slope/volume. Higher = deeper valleys.
@export var erosion_capacity: float = 5.5
## Floor on capacity so a droplet on dead-flat ground still does something
## rather than dumping its whole load in one cell.
@export var erosion_min_capacity: float = 0.02
@export_range(0.0, 1.0) var erosion_erode_rate: float = 0.35
@export_range(0.0, 1.0) var erosion_deposit_rate: float = 0.28
@export_range(0.0, 1.0) var erosion_evaporation: float = 0.025
@export var erosion_gravity: float = 10.0
## Radius, in cells, that a single erosion event is spread over.
@export var erosion_brush_radius: int = 2

## Per-cell record of how much water crossed it, normalised 0..1 after the
## run. This is the flow map, and it is the genuinely valuable by-product:
## it is the correct input for placing rivers (high flow), for deciding where
## vegetation should be lush (damp valleys) vs. where bare rock shows
## (scoured ridges), rather than guessing from slope and height alone.
## Empty until a grid has been built. See flow_at().
var _flow: PackedFloat32Array = PackedFloat32Array()

func _sample_grid(res: int) -> PackedFloat32Array:
	if _cached_resolution == res and _cached_heights.size() == res * res:
		return _cached_heights
	var half := size_meters * 0.5
	var step := size_meters / float(res - 1)
	var heights := PackedFloat32Array()
	heights.resize(res * res)
	for zi in res:
		var wz := -half + zi * step
		for xi in res:
			var wx := -half + xi * step
			heights[zi * res + xi] = height_at(wx, wz)
	for i in smoothing_passes:
		heights = _box_blur(heights, res)
	if erosion_droplets > 0:
		_erode(heights, res)
	_cached_heights = heights
	_cached_resolution = res
	return heights

## Normalised 0..1 water flow through the cell nearest this local XZ point.
## 0 until a grid has been built. Bilinear would be overkill — consumers of
## this (river placement, vegetation moisture) want a broad signal, not a
## precise one.
func flow_at(local_x: float, local_z: float) -> float:
	if _flow.is_empty() or _cached_resolution <= 0:
		return 0.0
	var res := _cached_resolution
	var half := size_meters * 0.5
	var step := size_meters / float(res - 1)
	var xi := clampi(int(round((local_x + half) / step)), 0, res - 1)
	var zi := clampi(int(round((local_z + half) / step)), 0, res - 1)
	return _flow[zi * res + xi]

func _erode(heights: PackedFloat32Array, res: int) -> void:
	var rng := RandomNumberGenerator.new()
	# Seeded off the island's own seed, so the same island always erodes into
	# the same valleys — the whole generator is meant to be reproducible from
	# island_seed alone.
	rng.seed = hash(island_seed) ^ 0x5EED
	var step := size_meters / float(res - 1)
	var half := size_meters * 0.5

	_flow = PackedFloat32Array()
	_flow.resize(res * res)

	# Precompute the erosion brush: offsets within the radius and their
	# distance weights, normalised to sum to 1 so an erosion event removes
	# exactly the amount asked for regardless of radius.
	var brush_dx := PackedInt32Array()
	var brush_dz := PackedInt32Array()
	var brush_w := PackedFloat32Array()
	var wsum := 0.0
	for bz in range(-erosion_brush_radius, erosion_brush_radius + 1):
		for bx in range(-erosion_brush_radius, erosion_brush_radius + 1):
			var d := sqrt(float(bx * bx + bz * bz))
			if d > float(erosion_brush_radius):
				continue
			var w := 1.0 - d / float(erosion_brush_radius + 1)
			brush_dx.append(bx)
			brush_dz.append(bz)
			brush_w.append(w)
			wsum += w
	for i in brush_w.size():
		brush_w[i] = brush_w[i] / wsum

	var max_index := res - 1
	var flow_peak := 0.0

	for _d in erosion_droplets:
		# Spawn anywhere on the grid. Droplets starting below sea level die
		# immediately in the loop's first check, which is correct and cheap.
		var px := rng.randf() * float(max_index)
		var pz := rng.randf() * float(max_index)
		var dx := 0.0
		var dz := 0.0
		var speed := 1.0
		var water := 1.0
		var sediment := 0.0

		for _life in erosion_droplet_lifetime:
			var cx := int(px)
			var cz := int(pz)
			if cx < 0 or cz < 0 or cx >= max_index or cz >= max_index:
				break
			var fx := px - float(cx)
			var fz := pz - float(cz)
			var i00 := cz * res + cx
			var i10 := i00 + 1
			var i01 := i00 + res
			var i11 := i01 + 1
			var h00 := heights[i00]
			var h10 := heights[i10]
			var h01 := heights[i01]
			var h11 := heights[i11]

			# Height and gradient under the droplet, bilinear.
			var height_here := h00 * (1.0 - fx) * (1.0 - fz) + h10 * fx * (1.0 - fz) \
				+ h01 * (1.0 - fx) * fz + h11 * fx * fz

			# THE SEA DRAIN: the droplet has reached the ocean, it is done.
			if height_here <= sea_level:
				break

			_flow[i00] += water
			if _flow[i00] > flow_peak:
				flow_peak = _flow[i00]

			var grad_x := (h10 - h00) * (1.0 - fz) + (h11 - h01) * fz
			var grad_z := (h01 - h00) * (1.0 - fx) + (h11 - h10) * fx

			dx = dx * erosion_inertia - grad_x * (1.0 - erosion_inertia)
			dz = dz * erosion_inertia - grad_z * (1.0 - erosion_inertia)
			var dlen := sqrt(dx * dx + dz * dz)
			if dlen < 0.0001:
				break # sitting in a pit with nowhere to go
			dx /= dlen
			dz /= dlen

			px += dx
			pz += dz
			var ncx := int(px)
			var ncz := int(pz)
			if ncx < 0 or ncz < 0 or ncx >= max_index or ncz >= max_index:
				break

			var nfx := px - float(ncx)
			var nfz := pz - float(ncz)
			var n00 := ncz * res + ncx
			var new_height := heights[n00] * (1.0 - nfx) * (1.0 - nfz) \
				+ heights[n00 + 1] * nfx * (1.0 - nfz) \
				+ heights[n00 + res] * (1.0 - nfx) * nfz \
				+ heights[n00 + res + 1] * nfx * nfz
			var delta := new_height - height_here

			var capacity := maxf(-delta * speed * water * erosion_capacity, erosion_min_capacity)

			if sediment > capacity or delta > 0.0:
				# Over capacity, or running uphill: drop material. When
				# running uphill, never drop more than fills the step — that
				# is what turns a pit into flat ground rather than a bump.
				var drop := (sediment - capacity) * erosion_deposit_rate if delta <= 0.0 \
					else minf(delta, sediment)
				sediment -= drop
				# Deposit bilinearly on the four cells we just left, so the
				# fill follows the surface instead of stacking on one vertex.
				heights[i00] += drop * (1.0 - fx) * (1.0 - fz)
				heights[i10] += drop * fx * (1.0 - fz)
				heights[i01] += drop * (1.0 - fx) * fz
				heights[i11] += drop * fx * fz
			else:
				# Under capacity on a downhill step: cut. Never cut deeper
				# than the step itself, or the droplet digs a shaft.
				var cut := minf((capacity - sediment) * erosion_erode_rate, -delta)
				sediment += cut
				for bi in brush_w.size():
					var bx := cx + brush_dx[bi]
					var bz := cz + brush_dz[bi]
					if bx < 0 or bz < 0 or bx > max_index or bz > max_index:
						continue
					heights[bz * res + bx] -= cut * brush_w[bi]

			speed = sqrt(maxf(speed * speed + delta * erosion_gravity, 0.0))
			water *= (1.0 - erosion_evaporation)
			if water < 0.01:
				break

	# Normalise the flow map so consumers get a stable 0..1 regardless of
	# droplet count.
	if flow_peak > 0.0:
		for i in _flow.size():
			_flow[i] = _flow[i] / flow_peak

## One pass of a 3x3 box blur (self + 4-neighbor average, edge samples
## clamped rather than wrapped) — cheap (single pass over the grid, no
## noise re-evaluation) and run once per (re)generation, not per frame.
func _box_blur(heights: PackedFloat32Array, res: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(res * res)
	for zi in res:
		var z0 := maxi(zi - 1, 0)
		var z1 := mini(zi + 1, res - 1)
		for xi in res:
			var x0 := maxi(xi - 1, 0)
			var x1 := mini(xi + 1, res - 1)
			var sum := heights[zi * res + xi] * 4.0 \
				+ heights[zi * res + x0] + heights[zi * res + x1] \
				+ heights[z0 * res + xi] + heights[z1 * res + xi]
			out[zi * res + xi] = sum / 8.0
	return out

func _normal_from_heights(heights: PackedFloat32Array, xi: int, zi: int, res: int, step: float) -> Vector3:
	var hl := heights[zi * res + maxi(xi - 1, 0)]
	var hr := heights[zi * res + mini(xi + 1, res - 1)]
	var hd := heights[maxi(zi - 1, 0) * res + xi]
	var hu := heights[mini(zi + 1, res - 1) * res + xi]
	var dx := (hr - hl) / (2.0 * step)
	var dz := (hu - hd) / (2.0 * step)
	return Vector3(-dx, 1.0, -dz).normalized()

## Builds the render mesh: a resolution x resolution grid, positions/normals
## from the heightmap, one UV set spanning 0..1 across the island (used by
## the shader only as a fallback — the triplanar material samples by world
## position, not UV), and baked tangents (needed for the triplanar shader's
## normal mapping).
func build_mesh() -> ArrayMesh:
	var res := maxi(resolution, 2)
	var half := size_meters * 0.5
	var step := size_meters / float(res - 1)
	var heights := _sample_grid(res)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	vertices.resize(res * res)
	normals.resize(res * res)
	uvs.resize(res * res)

	for zi in res:
		var wz := -half + zi * step
		for xi in res:
			var wx := -half + xi * step
			var idx := zi * res + xi
			vertices[idx] = Vector3(wx, heights[idx], wz)
			uvs[idx] = Vector2(float(xi) / float(res - 1), float(zi) / float(res - 1))
			normals[idx] = _normal_from_heights(heights, xi, zi, res, step)

	var indices := PackedInt32Array()
	indices.resize((res - 1) * (res - 1) * 6)
	var t := 0
	for zi in res - 1:
		for xi in res - 1:
			var i0 := zi * res + xi
			var i1 := i0 + 1
			var i2 := i0 + res
			var i3 := i2 + 1
			# Winding chosen so cross(v1-v0, v2-v0) points +Y, matching the
			# computed up-facing normals, so cull_back keeps the topside.
			indices[t] = i0; t += 1
			indices[t] = i2; t += 1
			indices[t] = i1; t += 1
			indices[t] = i1; t += 1
			indices[t] = i2; t += 1
			indices[t] = i3; t += 1

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var raw_mesh := ArrayMesh.new()
	raw_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	# Re-emit through SurfaceTool purely to bake tangents (raw arrays above
	# don't include them and the triplanar shader's NORMAL_MAP needs a TBN).
	var st := SurfaceTool.new()
	st.create_from(raw_mesh, 0)
	st.generate_tangents()
	return st.commit()

## Builds a HeightMapShape3D matching build_mesh()'s geometry exactly (same
## seed/size/resolution => same samples, read from the same cache). The
## returned shape assumes 1-unit sample spacing in local space, same as
## Godot's HeightMapShape3D convention — the caller (IslandTerrain) is
## responsible for scaling its CollisionShape3D by size_meters/(resolution-1)
## on X/Z so the collision grid lines up with the render mesh.
func build_heightmap_shape() -> HeightMapShape3D:
	var res := maxi(resolution, 2)
	var heights := _sample_grid(res)
	var shape := HeightMapShape3D.new()
	shape.map_width = res
	shape.map_depth = res
	shape.map_data = heights
	return shape

## Meters-per-sample step for the current resolution/size — the scale factor
## IslandTerrain applies to the collision shape's transform.
func grid_step() -> float:
	return size_meters / float(maxi(resolution, 2) - 1)

## Bilinearly-interpolated height from the smoothed render/collision grid
## (see _sample_grid()/_box_blur()) at an arbitrary point in local XZ space.
## This is what village placement, the Avatar/Hand drop height, and
## ReachBorderRing should call instead of height_at() — height_at() is the
## raw analytic value *before* smoothing, so it can disagree with the mesh
## a player actually walks on by up to a couple of smoothing passes' worth
## of local relief. Falls back to height_at() if the grid hasn't been
## sampled yet (e.g. called before the first build_mesh()/
## build_heightmap_shape()).
func sample_smoothed_height(local_x: float, local_z: float) -> float:
	if _cached_heights.is_empty():
		return height_at(local_x, local_z)
	var res := _cached_resolution
	var half := size_meters * 0.5
	var step := size_meters / float(res - 1)
	var fx := clampf((local_x + half) / step, 0.0, float(res - 1))
	var fz := clampf((local_z + half) / step, 0.0, float(res - 1))
	var x0 := int(floor(fx))
	var z0 := int(floor(fz))
	var x1 := mini(x0 + 1, res - 1)
	var z1 := mini(z0 + 1, res - 1)
	var tx := fx - float(x0)
	var tz := fz - float(z0)
	var h00 := _cached_heights[z0 * res + x0]
	var h10 := _cached_heights[z0 * res + x1]
	var h01 := _cached_heights[z1 * res + x0]
	var h11 := _cached_heights[z1 * res + x1]
	return lerp(lerp(h00, h10, tx), lerp(h01, h11, tx), tz)
