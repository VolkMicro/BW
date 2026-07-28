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
	# the sample resolution, regardless of noise frequency. At the previous
	# 0.35 weight against a 42m max_height those local slopes went steep
	# enough to backface-cull from a normal outdoor camera angle (see
	# terrain_triplanar.gdshader's cull_disabled note) and read as
	# shredded holes rather than mountain relief. 0.2 keeps visible ridged
	# character without the slope crossing that line.
	var shaped := continent * 0.8 + ridge * 0.2 + detail * 0.04
	var h := shaped * max_height * mask
	# Outside the island mask, sink toward a plausible sea floor instead of a
	# hard cliff at the heightmap's border.
	h -= (1.0 - mask) * max_height * 0.35
	return h + sea_level

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
	_cached_heights = heights
	_cached_resolution = res
	return heights

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
