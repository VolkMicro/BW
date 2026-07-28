# Weather — the Ninefold Sea's sky (package P)

`systems/weather/weather.gd` (autoload `Weather`) replaces the original
stub with a real, running simulation. It has two mutually-exclusive modes,
switched by `use_real_feed`, both writing into the same public
`current: Dictionary` shape so every consumer (VFX, audio, Louhi's tier-1
sign, a future HUD-less sky read) can stay agnostic to which mode is live.

## Public shape

Kept stable from the original stub — nothing that existed was renamed or
removed, only added to:

```text
wind_dir_deg   float, 0..360, compass bearing the wind blows FROM
wind_speed     float, game units/sec (~m/s scale)
precipitation  float, 0..1
cloud_cover    float, 0..1
temperature_c  float
is_storm       bool
source         "procedural" | "real_feed"
```

Added (additive — safe for any existing reader to ignore):

```text
storm_intensity     float, 0..1 — severity even before is_storm flips true,
                     so VFX/audio can ramp in ahead of the hard cut
updated_unix_time   float — Time.get_unix_time_from_system() at last write
```

`signal weather_changed(state: Dictionary)` fires every time `current` is
recomputed (procedural: throttled to once per `EMIT_INTERVAL`, 1.5s real
time; real_feed: once per successful poll).

**Direction convention:** `wind_dir_deg` is the bearing the wind blows
*from*, matching Open-Meteo's own `winddirection` field exactly, so the two
modes never need re-normalizing against each other and can only be told
apart by `source`. `WeatherFront.bearing_to_vector`/`vector_to_bearing`
(`systems/weather/weather_front.gd`) are the shared conversion, matching
`Village.position_on_island`'s `Vector2(x, y)` → world `Vector3(x, 0, y)`
convention already used by `systems/faith/reach.gd`.

## Procedural mode (default)

A small population (`MAX_FRONTS` = 5) of `WeatherFront` cells drift across
an abstract 2D sea (`ISLAND_POS = Vector2.ZERO`, `SEA_RADIUS` = 2600 units)
around the home island. Each front is a `RefCounted` (`WeatherFront`, not a
node — this is a pure data/simulation object, cheap to spawn and despawn)
carrying its own position, travel bearing, wind speed, cloud cover,
precipitation potential, radius of influence, and storm flag.

- **Spawning:** a new front spawns every 35–85 real seconds
  (`SPAWN_INTERVAL_MIN/MAX`) at the sea's edge, aimed roughly at the island
  (`SPAWN_HEADING_SPREAD_DEG` = 35° of scatter around a direct heading) so
  most fronts actually sweep across it instead of missing entirely.
  `STORM_CHANCE_PER_SPAWN` (14%) decides at spawn time whether a front is a
  storm cell (higher wind/cloud/precipitation ranges) or an ordinary one.
  One front is seeded immediately on `_ready()` so the sea is never dead
  calm at boot.
- **Advancing:** every front moves at its own wind speed along the
  reciprocal of its wind-from bearing, and both its heading and cloud cover
  drift slowly via a per-front sine wander (`WeatherFront.advance`) so nothing
  holds a perfectly straight line or a perfectly flat value — "organic," not
  "on rails."
- **Blending:** `_recompute_current()` distance-weights every front
  currently reaching the island (`WeatherFront.weight_at`, linear falloff
  to 0 at the front's radius) and blends wind (as vectors, so opposing
  fronts partially cancel rather than average nonsensically), cloud cover,
  precipitation, and a `storm_weight` fraction. `is_storm` flips true once
  blended storm-weight crosses `STORM_WEIGHT_THRESHOLD` (0.4) — a single
  storm front at partial influence doesn't instantly call itself a storm.
  If no front currently reaches the island, `current` eases toward a calm
  baseline instead of snapping to it.
- **Despawning:** a front is dropped once it drifts past
  `DESPAWN_RADIUS` (1.6× `SEA_RADIUS`); a despawning storm front fires
  `Voices.react(&"storm_passed", {"age": front.age})` on the way out.
- **Temperature:** `_ambient_temperature()` is a pure sine day/night cycle
  (`DAY_LENGTH_SECONDS` = 600s, ±`DIURNAL_SWING_C` = 4°C around
  `BASE_TEMPERATURE_C` = 14°C), further cooled by current cloud cover and
  precipitation — cloudy, rainy weather reads measurably colder than clear
  skies at the same time of day.

## Real-feed mode (opt-in)

`set_use_real_feed(true)` hands `current` over to a live poll of
Open-Meteo's free, keyless current-weather endpoint
(`https://api.open-meteo.com/v1/forecast`) for a settable lat/lon
(`set_location`, default an arbitrary cold-coast point with no
real-world claim — see the code comment). Polls every 900s
(`REAL_FEED_POLL_INTERVAL`, matching Open-Meteo's own ~15-minute refresh),
via a single `HTTPRequest` child node, non-overlapping (`_fetch_in_flight`
guard). Enabling the feed or calling `set_location` while already enabled
triggers an immediate re-fetch rather than waiting out the interval.

`_map_weathercode()` maps Open-Meteo's WMO weather codes onto this
project's `cloud_cover`/`precipitation`/`storm_intensity`/`is_storm` shape
(full table in the code — clear sky and light cloud codes at the low end,
thunderstorm-with-hail (99) at `{cloud_cover: 1.0, precipitation: 1.0,
storm_intensity: 1.0, is_storm: true}`). An unrecognized code falls back to
a mild, dry overcast rather than silently defaulting to clear skies, since
a wrong-but-plausible guess is worse than an honestly-neutral one here.
`is_storm` is also forced true if reported wind speed alone crosses
`STORM_WIND_SPEED_MIN`, independent of the weathercode. Wind speed arrives
in km/h and is converted to this project's game-units/sec scale (÷3.6) to
stay comparable with the procedural mode's numbers.

Disabling the feed (`set_use_real_feed(false)`) hands control back to the
procedural sim on the very next `_process` tick — the fronts array is
untouched while real-feed is active, so switching back doesn't need to
"re-seed" anything.

## Voices integration

`Weather` calls `Voices.react()` directly on four triggers:
`&"storm_forming"` (a storm front just spawned, or
`debug_spawn_storm_nearby()` was called), `&"storm_broke"` (blended
`is_storm` just flipped true, either mode), `&"storm_calmed"` (blended
`is_storm` just flipped false, procedural only), and `&"storm_passed"` (a
storm front drifted out of range while still storming). All four call
sites are real and firing; **none of the four has an authored line pool
yet** in `systems/voices/voice_lines.gd` (package M) as of this pass —
`Voices.react()` no-ops safely on a trigger with no pool, so this is quiet
rather than broken, exactly the same shape `docs/systems/louhi.md` already
flags for its own two unauthored triggers. Left here for whoever next
touches `voice_lines.gd`.

## Debug / cosmetic read API

- `get_active_fronts() -> Array[Dictionary]` — snapshot of every live
  front's state (`WeatherFront.to_debug_dict()`, copies not live refs).
  Empty while `use_real_feed` is on. Not consumed by anything yet; kept for
  a future cloud-shadow or sea-state cosmetic layer that wants more detail
  than the single blended `current` reading.
- `debug_spawn_storm_nearby() -> void` — force-spawns a storm front near
  the island. Not called by anything in this package; left public so a
  dependent package (e.g. `actors/louhi/louhi_director.gd`, which reads
  `Weather` per `docs/systems/OWNERSHIP.md`) can trigger a storm on demand
  while testing its own reaction to one.

## Integration notes for dependents

- **`actors/louhi/louhi_director.gd`** (package N) writes a cosmetic cold
  front directly into `Weather.current` for its tier-1 sign, built against
  this file's public Dictionary shape (see `docs/systems/louhi.md`'s own
  "Risk flagged for integration" note). That write is **not currently
  protected** from being overwritten: `_recompute_current()` fully
  recomputes every field from the front population every `EMIT_INTERVAL`,
  so an external write to `current` survives at most ~1.5s of real time
  before this file's own simulation stomps it. No `apply_event()` /
  external-override hook exists yet — flagged here rather than silently
  left for whoever hits it, exactly as N's own doc anticipated. The clean
  fix, if a future pass wants Louhi's sign to actually persist, is a small
  queue of temporary external overrides blended in ahead of the front
  population in `_recompute_current()`, not a rewrite of the front sim
  itself.
- Anything that only *reads* `current` (or connects to `weather_changed`)
  is unaffected by mode — the shape is identical whether `source` is
  `"procedural"` or `"real_feed"`.

## Scoped out

- **No visual/audio consumer of `current` yet.** This package makes the
  simulation and its signal real; nothing in `world/`, `environment/`, or
  `audio/` currently reads `Weather.current` to actually darken the sky,
  ripple the ocean surface, or duck the music. That wiring belongs to
  whichever package owns those consumers.
- **No storm voice lines authored** (see Voices integration, above).
- **No persistence.** `current` and the front population reset to their
  `_ready()` state on scene reload; there is no save/load hook here, matching
  the rest of the foundation's current lack of a save system.

### Assets used

None. Pure GDScript simulation; the real-feed mode calls a live, free,
keyless HTTP API (Open-Meteo, already listed in `CREDITS.md` under "Data
feeds") rather than pulling any static asset.
