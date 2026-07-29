extends Node
## Autoload. Weather = the Ninefold Sea's weather.
##
## Two modes, switched by `use_real_feed`:
##  - procedural (default): a handful of WeatherFront cells drift across an
##    abstract sea around the home island, evolving over real time. Whichever
##    fronts currently reach the island are distance-weighted-blended into
##    `current`. Fronts occasionally spawn as storms; storms also fade out
##    naturally as their front drifts past and away.
##  - real_feed (opt-in): polls Open-Meteo's free, keyless current-weather
##    endpoint for a real lat/lon and maps its fields onto the same `current`
##    shape, with `source` flipped to "real_feed" so consumers (and this
##    file) can tell which regime produced the numbers.
##
## Public shape kept stable for existing/future consumers (do not remove
## these keys; new keys were added, see below):
##   wind_dir_deg   float, 0..360, compass bearing wind blows FROM
##   wind_speed     float, game units/sec (~m/s scale)
##   precipitation  float, 0..1
##   cloud_cover    float, 0..1
##   temperature_c  float
##   is_storm       bool
##   source         "procedural" | "real_feed"
## Added fields (additive, safe to ignore):
##   storm_intensity     float, 0..1 — severity even when is_storm is still
##                        false (lets VFX/audio ramp in before the hard cut)
##   updated_unix_time   float — Time.get_unix_time_from_system() at last write

signal weather_changed(state: Dictionary)

const WeatherFront = preload("res://systems/weather/weather_front.gd")

var current: Dictionary = {
	"wind_dir_deg": 0.0,
	"wind_speed": 2.0,
	"precipitation": 0.0,
	"cloud_cover": 0.2,
	"temperature_c": 15.0,
	"is_storm": false,
	# Where we are in the island's day. 0.0 = sunrise, 0.25 = noon,
	# 0.5 = sunset, 0.75 = midnight. Published here rather than in a separate
	# clock because the diurnal temperature curve below was already keeping
	# this number privately, and two clocks that can disagree is a bug waiting
	# to be filed.
	"day_phase": 0.0,
	"is_night": false,
	"source": "procedural",
	"storm_intensity": 0.0,
	"updated_unix_time": 0.0,
}

# --- Procedural simulation tuning ------------------------------------------

## Abstract map-space center of the home island. Village.position_on_island
## and Reach both treat Vector2(x, y) as world (x, z); fronts live in that
## same 2D space so a future cosmetic consumer (cloud shadows, sea-state)
## could plot them directly without a coordinate translation.
const ISLAND_POS := Vector2.ZERO
const SEA_RADIUS := 2600.0 # fronts spawn on a ring this far out
const DESPAWN_RADIUS := SEA_RADIUS * 1.6 # and are culled once they drift this far past it

const MAX_FRONTS := 5
const SPAWN_INTERVAL_MIN := 35.0 # real seconds between new fronts
const SPAWN_INTERVAL_MAX := 85.0
const SPAWN_HEADING_SPREAD_DEG := 35.0 # how far off "straight at the island" a new front's travel can be

const FRONT_RADIUS_MIN := 800.0
const FRONT_RADIUS_MAX := 1700.0
const WIND_SPEED_MIN := 1.5
const WIND_SPEED_MAX := 6.5
const STORM_WIND_SPEED_MIN := 7.5
const STORM_WIND_SPEED_MAX := 13.0
const STORM_CHANCE_PER_SPAWN := 0.14

const STORM_WEIGHT_THRESHOLD := 0.4 # blended storm-weight fraction that flips is_storm true

const EMIT_INTERVAL := 1.5 # throttle: recompute/emit `current` this often, not every frame
const DAY_LENGTH_SECONDS := 600.0 # one full ambient-temperature cycle (~10 real minutes)
const BASE_TEMPERATURE_C := 14.0
const DIURNAL_SWING_C := 4.0

var _fronts: Array[WeatherFront] = []
var _elapsed: float = 0.0
var _next_spawn_in: float = 0.0
var _emit_accum: float = 0.0

# --- Real-feed (Open-Meteo) -------------------------------------------------

## Opt-in: false = procedural sim drives `current` (default). true = the
## real-weather feed drives it instead. Toggle via set_use_real_feed() so
## the fetch timer/HTTPRequest state stays consistent; the bare var is left
## public (per the brief) but prefer the setter from other packages.
var use_real_feed: bool = false

const REAL_FEED_POLL_INTERVAL := 900.0 # seconds; matches Open-Meteo's own ~15min refresh
const REAL_FEED_ENDPOINT := "https://api.open-meteo.com/v1/forecast"

var _lat: float = 60.39 # default: an arbitrary Ninefold-Sea-ish coastal point
var _lon: float = 5.32  # (no real-world claim; just a plausible cold-coast default)
var _real_feed_accum: float = REAL_FEED_POLL_INTERVAL # fetch immediately on first enable
var _fetch_in_flight: bool = false
var _http: HTTPRequest

func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	_next_spawn_in = randf_range(SPAWN_INTERVAL_MIN, SPAWN_INTERVAL_MAX)
	# Seed a front immediately so the sea isn't dead calm at boot.
	_spawn_front()
	weather_changed.emit(current)

func _process(delta: float) -> void:
	_elapsed += delta
	if use_real_feed:
		_real_feed_accum += delta
		if _real_feed_accum >= REAL_FEED_POLL_INTERVAL and not _fetch_in_flight:
			_real_feed_accum = 0.0
			_fetch_real_weather()
		return
	_update_fronts(delta)
	_emit_accum += delta
	if _emit_accum >= EMIT_INTERVAL:
		_emit_accum = 0.0
		_recompute_current()

# --- Procedural front simulation -------------------------------------------

func _update_fronts(delta: float) -> void:
	_next_spawn_in -= delta
	if _next_spawn_in <= 0.0 and _fronts.size() < MAX_FRONTS:
		_spawn_front()
		_next_spawn_in = randf_range(SPAWN_INTERVAL_MIN, SPAWN_INTERVAL_MAX)

	for front in _fronts:
		front.advance(delta, _elapsed)

	var kept: Array[WeatherFront] = []
	for front in _fronts:
		if front.position.distance_to(ISLAND_POS) < DESPAWN_RADIUS:
			kept.append(front)
		elif front.is_storm:
			Voices.react(&"storm_passed", {"age": front.age})
	_fronts = kept

func _spawn_front() -> void:
	var spawn_angle := randf() * TAU
	var spawn_pos := ISLAND_POS + Vector2(cos(spawn_angle), sin(spawn_angle)) * SEA_RADIUS

	# Aim the front's travel roughly at the island, with spread, so most
	# fronts actually sweep across it rather than skirting the whole sea.
	var to_island := ISLAND_POS - spawn_pos
	var travel_bearing := WeatherFront.vector_to_bearing(to_island) \
		+ randf_range(-SPAWN_HEADING_SPREAD_DEG, SPAWN_HEADING_SPREAD_DEG)
	var wind_dir_deg := fposmod(travel_bearing + 180.0, 360.0)

	var storming := randf() < STORM_CHANCE_PER_SPAWN
	var wind_speed: float
	var cloud_cover: float
	var precipitation: float
	if storming:
		wind_speed = randf_range(STORM_WIND_SPEED_MIN, STORM_WIND_SPEED_MAX)
		cloud_cover = randf_range(0.8, 1.0)
		precipitation = randf_range(0.6, 1.0)
	else:
		wind_speed = randf_range(WIND_SPEED_MIN, WIND_SPEED_MAX)
		cloud_cover = randf_range(0.1, 0.85)
		precipitation = randf_range(0.0, 0.5) if cloud_cover > 0.4 else 0.0

	var radius := randf_range(FRONT_RADIUS_MIN, FRONT_RADIUS_MAX)
	var front := WeatherFront.new(spawn_pos, wind_dir_deg, wind_speed, cloud_cover, precipitation, radius)
	front.is_storm = storming
	_fronts.append(front)

	if storming:
		Voices.react(&"storm_forming", {"wind_speed": wind_speed})

func _recompute_current() -> void:
	var total_weight := 0.0
	var wind_vec := Vector2.ZERO
	var cloud_acc := 0.0
	var precip_acc := 0.0
	var wind_speed_acc := 0.0
	var storm_weight := 0.0

	for front in _fronts:
		var w := front.weight_at(ISLAND_POS)
		if w <= 0.0:
			continue
		total_weight += w
		wind_vec += WeatherFront.bearing_to_vector(front.wind_dir_deg) * w
		cloud_acc += front.cloud_cover * w
		precip_acc += front.precipitation_potential * w
		wind_speed_acc += front.wind_speed * w
		if front.is_storm:
			storm_weight += w

	var was_storm: bool = current.is_storm
	if total_weight <= 0.0:
		# No front currently reaches the island: calm baseline, slowly clearing.
		current.cloud_cover = lerpf(current.cloud_cover, 0.15, 0.2)
		current.precipitation = lerpf(current.precipitation, 0.0, 0.25)
		current.wind_speed = lerpf(current.wind_speed, 1.5, 0.1)
		current.storm_intensity = lerpf(current.storm_intensity, 0.0, 0.2)
		current.is_storm = false
	else:
		current.wind_dir_deg = WeatherFront.vector_to_bearing(wind_vec)
		current.wind_speed = wind_speed_acc / total_weight
		current.cloud_cover = clampf(cloud_acc / total_weight, 0.0, 1.0)
		current.precipitation = clampf(precip_acc / total_weight, 0.0, 1.0)
		current.storm_intensity = clampf(storm_weight / total_weight, 0.0, 1.0)
		current.is_storm = current.storm_intensity > STORM_WEIGHT_THRESHOLD

	current.temperature_c = _ambient_temperature() \
		- current.cloud_cover * 3.0 - current.precipitation * 2.0
	current.day_phase = day_phase()
	current.is_night = is_night()
	current.source = "procedural"
	current.updated_unix_time = Time.get_unix_time_from_system()

	if current.is_storm and not was_storm:
		Voices.react(&"storm_broke", {"wind_speed": current.wind_speed})
	elif was_storm and not current.is_storm:
		Voices.react(&"storm_calmed", {})

	weather_changed.emit(current)

func _ambient_temperature() -> float:
	return BASE_TEMPERATURE_C + sin(day_phase() * TAU) * DIURNAL_SWING_C

## 0.0 = sunrise, 0.25 = noon, 0.5 = sunset, 0.75 = midnight.
##
## Read this rather than `current.day_phase` when you need it smooth: `current`
## is only recomputed every EMIT_INTERVAL (1.5 s), which is fine for deciding
## whether people are asleep and visibly wrong for moving the sun.
func day_phase() -> float:
	return fposmod(_elapsed / DAY_LENGTH_SECONDS, 1.0)

## True between sunset and sunrise. The one place the day/night boundary is
## defined — everything else asks.
func is_night() -> bool:
	return day_phase() > 0.5

# --- Real-weather feed (Open-Meteo) ----------------------------------------

## Enable/disable the real-weather feed. Disabling hands control back to
## the procedural sim on the next _process tick; enabling triggers an
## immediate fetch rather than waiting for the poll interval.
func set_use_real_feed(enabled: bool) -> void:
	use_real_feed = enabled
	if enabled:
		_real_feed_accum = REAL_FEED_POLL_INTERVAL
		_fetch_real_weather()

## Set the real-world coordinates the feed reads from. Safe to call whether
## or not the feed is currently enabled; if it is, this triggers an
## immediate re-fetch at the new location.
func set_location(lat: float, lon: float) -> void:
	_lat = lat
	_lon = lon
	if use_real_feed:
		_fetch_real_weather()

func _fetch_real_weather() -> void:
	if _fetch_in_flight:
		return
	var url := "%s?latitude=%f&longitude=%f&current_weather=true" % [REAL_FEED_ENDPOINT, _lat, _lon]
	var err := _http.request(url)
	if err != OK:
		push_warning("Weather: real-feed request failed to start (err %d)" % err)
		return
	_fetch_in_flight = true

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_fetch_in_flight = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		push_warning("Weather: real-feed request did not succeed (result %d, http %d)" % [result, response_code])
		return

	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary) or not parsed.has("current_weather"):
		push_warning("Weather: real-feed response missing current_weather")
		return

	var cw: Dictionary = parsed["current_weather"]
	var code := int(cw.get("weathercode", 0))
	var mapped := _map_weathercode(code)

	current.wind_dir_deg = fposmod(float(cw.get("winddirection", current.wind_dir_deg)), 360.0)
	# Open-Meteo reports windspeed in km/h; convert to this project's
	# game-units-per-second scale (same order of magnitude as m/s) so
	# procedural and real_feed values are comparable to downstream consumers.
	current.wind_speed = float(cw.get("windspeed", current.wind_speed * 3.6)) / 3.6
	current.temperature_c = float(cw.get("temperature", current.temperature_c))
	current.cloud_cover = mapped.cloud_cover
	current.precipitation = mapped.precipitation
	current.storm_intensity = mapped.storm_intensity
	current.is_storm = mapped.is_storm or current.wind_speed > STORM_WIND_SPEED_MIN
	# The real feed carries no clock for OUR island — it reports the sky over a
	# real latitude/longitude, not the hour on the Ninefold Sea. Day phase
	# therefore stays on the local simulated cycle whichever source is driving
	# the weather, so the sun never jumps when the feed is switched on.
	current.day_phase = day_phase()
	current.is_night = is_night()
	current.source = "real_feed"
	current.updated_unix_time = Time.get_unix_time_from_system()

	if current.is_storm:
		Voices.react(&"storm_broke", {"wind_speed": current.wind_speed, "source": "real_feed"})

	weather_changed.emit(current)

## Maps an Open-Meteo WMO weather code to this project's cloud_cover /
## precipitation / storm fields. See docs/systems/weather.md for the full
## table and rationale. Unknown codes fall back to a mild, dry overcast
## rather than silently defaulting to clear skies.
func _map_weathercode(code: int) -> Dictionary:
	match code:
		0: return {"cloud_cover": 0.0, "precipitation": 0.0, "storm_intensity": 0.0, "is_storm": false}
		1: return {"cloud_cover": 0.2, "precipitation": 0.0, "storm_intensity": 0.0, "is_storm": false}
		2: return {"cloud_cover": 0.5, "precipitation": 0.0, "storm_intensity": 0.0, "is_storm": false}
		3: return {"cloud_cover": 0.9, "precipitation": 0.0, "storm_intensity": 0.05, "is_storm": false}
		45, 48: return {"cloud_cover": 0.85, "precipitation": 0.05, "storm_intensity": 0.0, "is_storm": false}
		51: return {"cloud_cover": 0.7, "precipitation": 0.2, "storm_intensity": 0.0, "is_storm": false}
		53: return {"cloud_cover": 0.75, "precipitation": 0.4, "storm_intensity": 0.05, "is_storm": false}
		55: return {"cloud_cover": 0.8, "precipitation": 0.6, "storm_intensity": 0.1, "is_storm": false}
		56: return {"cloud_cover": 0.75, "precipitation": 0.3, "storm_intensity": 0.05, "is_storm": false}
		57: return {"cloud_cover": 0.8, "precipitation": 0.5, "storm_intensity": 0.1, "is_storm": false}
		61: return {"cloud_cover": 0.7, "precipitation": 0.3, "storm_intensity": 0.05, "is_storm": false}
		63: return {"cloud_cover": 0.85, "precipitation": 0.6, "storm_intensity": 0.15, "is_storm": false}
		65: return {"cloud_cover": 0.95, "precipitation": 0.9, "storm_intensity": 0.35, "is_storm": false}
		66: return {"cloud_cover": 0.8, "precipitation": 0.4, "storm_intensity": 0.1, "is_storm": false}
		67: return {"cloud_cover": 0.9, "precipitation": 0.7, "storm_intensity": 0.25, "is_storm": false}
		71: return {"cloud_cover": 0.75, "precipitation": 0.3, "storm_intensity": 0.05, "is_storm": false}
		73: return {"cloud_cover": 0.85, "precipitation": 0.6, "storm_intensity": 0.15, "is_storm": false}
		75: return {"cloud_cover": 0.95, "precipitation": 0.9, "storm_intensity": 0.3, "is_storm": false}
		77: return {"cloud_cover": 0.75, "precipitation": 0.3, "storm_intensity": 0.05, "is_storm": false}
		80: return {"cloud_cover": 0.7, "precipitation": 0.4, "storm_intensity": 0.1, "is_storm": false}
		81: return {"cloud_cover": 0.85, "precipitation": 0.7, "storm_intensity": 0.3, "is_storm": false}
		82: return {"cloud_cover": 1.0, "precipitation": 1.0, "storm_intensity": 0.8, "is_storm": true}
		85: return {"cloud_cover": 0.8, "precipitation": 0.4, "storm_intensity": 0.1, "is_storm": false}
		86: return {"cloud_cover": 0.95, "precipitation": 0.8, "storm_intensity": 0.5, "is_storm": true}
		95: return {"cloud_cover": 1.0, "precipitation": 0.8, "storm_intensity": 0.7, "is_storm": true}
		96: return {"cloud_cover": 1.0, "precipitation": 0.9, "storm_intensity": 0.9, "is_storm": true}
		99: return {"cloud_cover": 1.0, "precipitation": 1.0, "storm_intensity": 1.0, "is_storm": true}
		_: return {"cloud_cover": 0.4, "precipitation": 0.0, "storm_intensity": 0.0, "is_storm": false}

# --- Optional read-only debug/cosmetic API ---------------------------------

## Snapshot of active procedural fronts (empty while use_real_feed is on).
## Not required by any current consumer; provided for a future cloud-shadow
## or sea-state cosmetic layer that wants more than the single blended
## `current` reading. Returns copies (Dictionary), never the live objects.
func get_active_fronts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for front in _fronts:
		out.append(front.to_debug_dict())
	return out

## Debug/test helper: force-spawns a storm front near the island. Not called
## by anything in this package; left public so other packages (e.g. N —
## actors/louhi, which depends on Weather per OWNERSHIP.md) can trigger a
## storm on demand while testing their own reactions to one.
## Brings a storm in over the island. Real gameplay, not a debug hook: the
## `storm` rite calls this, because a rite that summons weather should summon
## the weather system's weather rather than describe one in a Voices line.
func summon_storm() -> void:
	var spawn_angle := randf() * TAU
	var spawn_pos := ISLAND_POS + Vector2(cos(spawn_angle), sin(spawn_angle)) * (SEA_RADIUS * 0.35)
	var travel_bearing := WeatherFront.vector_to_bearing(ISLAND_POS - spawn_pos)
	var wind_dir_deg := fposmod(travel_bearing + 180.0, 360.0)
	var front := WeatherFront.new(
		spawn_pos, wind_dir_deg,
		randf_range(STORM_WIND_SPEED_MIN, STORM_WIND_SPEED_MAX),
		randf_range(0.85, 1.0), randf_range(0.7, 1.0),
		randf_range(FRONT_RADIUS_MIN, FRONT_RADIUS_MAX))
	front.is_storm = true
	_fronts.append(front)
	Voices.react(&"storm_forming", {"wind_speed": front.wind_speed, "forced": true})


## Kept as the old name for any QA panel or scripted beat that already calls
## it. Same behaviour; the rite path uses summon_storm().
func debug_spawn_storm_nearby() -> void:
	summon_storm()
