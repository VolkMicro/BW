extends RefCounted
class_name WeatherFront
## One drifting weather cell on the Ninefold Sea. systems/weather/weather.gd
## owns a small population of these, moves them each frame, spawns new ones
## at the edge of the sea, and despawns ones that have drifted well past the
## home island. The island's `Weather.current` is a distance-weighted blend
## of whichever fronts currently reach it (see Weather._recompute_current).
##
## Direction convention: `wind_dir_deg` is the compass bearing the wind is
## blowing FROM (0 = the bearing-zero axis, increasing clockwise toward 90),
## exactly matching Open-Meteo's `winddirection` field so the procedural sim
## and the real-weather feed share one convention and can be told apart only
## by `source`, never by having to renormalize angles. A front's *travel*
## direction is therefore the reciprocal bearing (wind_dir_deg + 180).

var position: Vector2
var wind_dir_deg: float
var wind_speed: float # game units/sec, roughly analogous to m/s
var cloud_cover: float # 0..1
var precipitation_potential: float # 0..1, this front's base severity
var radius: float # influence radius, world units
var is_storm: bool = false
var age: float = 0.0

var _wander_seed: float

func _init(p_position: Vector2, p_wind_dir_deg: float, p_wind_speed: float,
		p_cloud_cover: float, p_precipitation: float, p_radius: float) -> void:
	position = p_position
	wind_dir_deg = fposmod(p_wind_dir_deg, 360.0)
	wind_speed = p_wind_speed
	cloud_cover = clampf(p_cloud_cover, 0.0, 1.0)
	precipitation_potential = clampf(p_precipitation, 0.0, 1.0)
	radius = p_radius
	_wander_seed = randf() * 1000.0

## Compass bearing -> unit vector, bearing 0 along +Y, 90 along +X (this
## project's Vector2 map-space matches Village.position_on_island, which
## reach.gd projects into world space as Vector3(x, 0, y)).
static func bearing_to_vector(deg: float) -> Vector2:
	var rad := deg_to_rad(deg)
	return Vector2(sin(rad), cos(rad))

## Inverse of bearing_to_vector: unit/non-unit vector -> compass bearing.
static func vector_to_bearing(v: Vector2) -> float:
	if v.length_squared() < 0.0000001:
		return 0.0
	return fposmod(rad_to_deg(atan2(v.x, v.y)), 360.0)

## This front's direction of travel (reciprocal of the "from" bearing).
func velocity() -> Vector2:
	return -bearing_to_vector(wind_dir_deg) * wind_speed

func advance(delta: float, elapsed_time: float) -> void:
	position += velocity() * delta
	age += delta
	# Slow organic wander so fronts don't feel like they're on rails: the
	# heading and intensity drift a little rather than holding dead steady.
	wind_dir_deg = fposmod(
		wind_dir_deg + sin(elapsed_time * 0.05 + _wander_seed) * 5.0 * delta, 360.0)
	cloud_cover = clampf(
		cloud_cover + sin(elapsed_time * 0.037 + _wander_seed * 2.0) * 0.015 * delta,
		0.0, 1.0)

## 0 outside radius, up to 1 at the front's center. Used to blend multiple
## overlapping fronts' influence on any one point (usually the island).
func weight_at(point: Vector2) -> float:
	var d := position.distance_to(point)
	if d >= radius:
		return 0.0
	return 1.0 - (d / radius)

func to_debug_dict() -> Dictionary:
	return {
		"position": position,
		"wind_dir_deg": wind_dir_deg,
		"wind_speed": wind_speed,
		"cloud_cover": cloud_cover,
		"precipitation_potential": precipitation_potential,
		"radius": radius,
		"is_storm": is_storm,
		"age": age,
	}
