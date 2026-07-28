extends Resource
class_name GerstnerWaveSet
## A tunable set of up to MAX_WAVES Gerstner waves shared by the ocean and
## river shaders (world/ocean/ocean.gdshader, world/ocean/river.gdshader)
## AND by CPU-side height/normal queries (see OceanSurface.get_height,
## RiverSurface.get_height below) so gameplay code — a floating object the
## Hand drops, a boat, a corpse washing up — can sample the *same* wave
## field the shader is drawing, without a GPU readback.
##
## Each entry in `waves` is a Dictionary:
##   direction: Vector2  (need not be pre-normalized)
##   wavelength: float   (meters, > 0)
##   steepness: float    (0..1 — fraction of the theoretical max sharpness;
##                        summed steepness across active waves is
##                        automatically normalized, see sample()/the
##                        shaders' `qi` term, so values don't need to sum
##                        to <= 1 by hand)
##   amplitude: float    (meters, half wave height)
##   speed: float        (phase speed; larger = the crest races past faster)

const MAX_WAVES := 6

@export var waves: Array[Dictionary] = []

## Open-sea default: long, fairly steep swell down to short wind-chop,
## spread across a range of directions so the surface doesn't look like a
## single repeating corduroy pattern from any angle.
static func default_ocean() -> GerstnerWaveSet:
	var s := GerstnerWaveSet.new()
	s.waves = [
		{"direction": Vector2(1.0, 0.15), "wavelength": 42.0, "steepness": 0.55, "amplitude": 1.1, "speed": 2.6},
		{"direction": Vector2(0.62, -0.79), "wavelength": 27.0, "steepness": 0.45, "amplitude": 0.7, "speed": 3.1},
		{"direction": Vector2(-0.35, 0.94), "wavelength": 15.0, "steepness": 0.4, "amplitude": 0.4, "speed": 3.9},
		{"direction": Vector2(0.87, 0.49), "wavelength": 9.0, "steepness": 0.35, "amplitude": 0.22, "speed": 4.6},
		{"direction": Vector2(-0.68, -0.73), "wavelength": 5.0, "steepness": 0.3, "amplitude": 0.12, "speed": 5.4},
		{"direction": Vector2(0.2, -0.98), "wavelength": 2.4, "steepness": 0.25, "amplitude": 0.06, "speed": 6.5},
	]
	return s

## River/inlet default: short, steep, fast ripples roughly aligned with
## `flow_direction` plus a little cross-chop — no fetch for open-sea swell
## in a narrow channel.
static func default_river(flow_direction: Vector2 = Vector2(0.0, 1.0)) -> GerstnerWaveSet:
	var dir := flow_direction.normalized()
	if dir.length_squared() < 0.0001:
		dir = Vector2(0.0, 1.0)
	var s := GerstnerWaveSet.new()
	s.waves = [
		{"direction": dir, "wavelength": 4.0, "steepness": 0.5, "amplitude": 0.08, "speed": 5.5},
		{"direction": dir.rotated(0.35), "wavelength": 2.2, "steepness": 0.4, "amplitude": 0.05, "speed": 6.8},
		{"direction": dir.rotated(-0.4), "wavelength": 1.4, "steepness": 0.35, "amplitude": 0.03, "speed": 7.6},
		{"direction": dir.rotated(1.4), "wavelength": 0.8, "steepness": 0.25, "amplitude": 0.015, "speed": 8.5},
	]
	return s

## Packs into the flat array the shaders expect:
## wave_dir_len_steep[i] = vec4(dir.x, dir.y, wavelength, steepness).
## Always exactly MAX_WAVES entries (padded with inert, zero-amplitude
## entries) so set_shader_parameter always sends a fixed-size array
## matching the shader's declared uniform size.
func to_shader_dir_len_steep() -> Array:
	var out: Array = []
	for i in range(MAX_WAVES):
		if i < waves.size():
			var w: Dictionary = waves[i]
			var dir: Vector2 = w.get("direction", Vector2.RIGHT)
			out.append(Vector4(dir.x, dir.y, maxf(w.get("wavelength", 1.0), 0.01), clampf(w.get("steepness", 0.0), 0.0, 1.0)))
		else:
			out.append(Vector4(1.0, 0.0, 1.0, 0.0))
	return out

## wave_amp_speed[i] = vec2(amplitude, speed). Same fixed-size padding.
func to_shader_amp_speed() -> Array:
	var out: Array = []
	for i in range(MAX_WAVES):
		if i < waves.size():
			var w: Dictionary = waves[i]
			out.append(Vector2(w.get("amplitude", 0.0), w.get("speed", 0.0)))
		else:
			out.append(Vector2(0.0, 0.0))
	return out

## CPU-side sample at world XZ `pos` and time `t` (seconds), matching the
## shaders' calculate_gerstner_ocean()/calculate_gerstner_river() formula
## exactly. Returns {"displacement": Vector3, "normal": Vector3}.
##
## Caveat: like the shader, this samples at the *undisplaced* XZ position
## rather than inverting the horizontal Gerstner displacement to find
## which original vertex ends up above a given target point — the
## standard simplification for buoyancy-style queries, fine at the
## steepness values used here, wrong at extreme steepness/close inspection.
func sample(pos: Vector2, t: float) -> Dictionary:
	var displacement := Vector3.ZERO
	var normal := Vector3(0.0, 1.0, 0.0)

	var active_waves := 0
	for w in waves:
		if float(w.get("amplitude", 0.0)) > 0.0001:
			active_waves += 1
	active_waves = maxi(active_waves, 1)

	for w in waves:
		var amplitude: float = w.get("amplitude", 0.0)
		if amplitude <= 0.0001:
			continue
		var speed: float = w.get("speed", 0.0)
		var dir: Vector2 = (w.get("direction", Vector2.RIGHT) as Vector2).normalized()
		var wavelength: float = maxf(w.get("wavelength", 1.0), 0.01)
		var steepness: float = clampf(w.get("steepness", 0.0), 0.0, 1.0)

		var k := TAU / wavelength
		var f := k * dir.dot(pos) + t * speed
		var qi := steepness / (k * amplitude * float(active_waves))

		displacement.x += qi * amplitude * dir.x * cos(f)
		displacement.z += qi * amplitude * dir.y * cos(f)
		displacement.y += amplitude * sin(f)

		var wa := k * amplitude
		normal.x -= dir.x * wa * cos(f)
		normal.z -= dir.y * wa * cos(f)
		normal.y -= qi * wa * sin(f)

	return {"displacement": displacement, "normal": normal.normalized()}
