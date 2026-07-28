# Adaptive audio — music & ambience (package R)

## What this is

`audio/music_director.gd` (autoload `MusicDirector`, registered in
`project.godot` at `res://audio/music_director.gd` — this package replaces
the stub's contents only, per `docs/systems/OWNERSHIP.md`; it does not, and
may not, touch the autoload registration itself) is a real, running,
continuously-adaptive audio system with two parts:

1. **A two-layer, continuously-crossfaded music bed.** `layers[&"prayer"]`
   and `layers[&"infernal"]` are real `AudioStreamPlayer`s, always both
   playing, whose relative loudness is recomputed every frame from
   `Naklon.unit()` (0.0 = full prayer/mercy, 1.0 = full infernal/cruelty).
2. **Two continuous ambient beds** — `wind` (non-spatial) and `sea`
   (`AudioStreamPlayer3D`, spatial) — modulated every tick by
   `Weather.current` (`systems/weather/weather.gd`), so a storm forming or
   breaking is audible, not only visible to some future VFX consumer.

Both parts are genuinely wired to their upstream signals and running code,
not stubs. What is **not** real is the audio content itself for three of
the four continuous beds and both ambient beds — see "Honesty: what's real
vs. placeholder" below before assuming otherwise.

## Equal-power crossfade

`_update_crossfade()` reads `Naklon.unit()` once per frame (also re-run
immediately on `Naklon.naklon_changed`, matching the stub's original
`_on_naklon_changed` entry point) and maps it through
`angle = unit * PI/2`, then sets:

```
prayer_gain   = cos(angle)   # 1.0 at unit=0, 0.0 at unit=1
infernal_gain = sin(angle)   # 0.0 at unit=0, 1.0 at unit=1
```

`cos(angle)^2 + sin(angle)^2 == 1` for every `angle`, which is exactly the
equal-power property: the two layers' summed *power* (not their linear
gains) stays constant across the whole crossfade range, so there's no
perceptible loudness dip at `unit() == 0.5` the way a linear `1-t`/`t`
crossfade would produce. Each linear gain is converted to `volume_db` via
`linear_to_db(max(gain, 0.0001))` — the `max()` floor avoids feeding `0.0`
into `linear_to_db` (which returns `-inf`) while still reading as
effectively silent (`linear_to_db(0.0001)` ≈ -80 dB).

Both layers **play continuously** the whole time (per the original stub's
documented contract — "crossfaded continuously by `Naklon.unit()`"); only
`volume_db` moves. This means a player at 0 gain is still burning a tiny
amount of CPU generating silence-adjacent samples nobody hears — acceptable
for a vertical slice, flagged in "Scoped out" as a real, known cost.

A `_duck_current` multiplier (see "Ducking," below) is folded into
`_set_layer_gain()` alongside the crossfade gain, so a Voices remark or
Louhi sign genuinely lowers *both* layers together without disturbing their
balance relative to each other.

## Ambience: wind (non-spatial) + sea (spatial) — and why they differ

The brief left the spatial-vs-non-spatial call to this package, to be
documented rather than defaulted. The two ambient beds made different,
deliberate choices:

- **Wind is `AudioStreamPlayer` (non-spatial).** Weather is a whole-board
  condition — `systems/weather/weather.gd`'s own model is a single blended
  `current` Dictionary for the entire home island, not a per-location
  reading. Making wind spatial would mean it audibly fades out near the
  edges of wherever the camera/listener happens to be, which is the wrong
  behavior for "the whole sea sounds like this right now."
- **Sea/surf is `AudioStreamPlayer3D` (spatial).** Waves breaking on a
  shoreline genuinely *are* directional and distance-attenuated in a way
  wind isn't — louder near the coast, quieter inland — so spatial
  attenuation is the honest choice here, not just the more impressive one.
  It's parented directly under `MusicDirector` (a plain `Node`, not
  `Node3D`) at a placeholder offset, `SEA_PLACEHOLDER_POSITION = Vector3(0,
  2, 120)`, chosen loosely in the same Vector2(x,y) world -> Vector3(x,0,y)
  convention `systems/weather/weather.gd` and `systems/faith/reach.gd`
  already share (`Weather.ISLAND_POS = Vector2.ZERO`, `SEA_RADIUS` ~2600) —
  it is **not** read from any real shoreline geometry, because `audio/`
  doesn't own `world/ocean/`'s geometry and has no dependency on it per
  `docs/systems/OWNERSHIP.md`. `MusicDirector.set_sea_anchor(node: Node3D)`
  / `set_sea_position(pos: Vector3)` are exposed as the integration hook for
  whichever future pass has real shoreline coordinates to hand it.
  Like any `AudioStreamPlayer3D`, this layer is only audible with an active
  `Camera3D`/`AudioListener3D` present in whatever scene is actually
  running — standard Godot behavior, not something this autoload manages
  or can substitute for.

Both beds' target gains are recomputed in `_on_weather_changed(state)` from
`state.wind_speed` / `state.precipitation` / `state.storm_intensity`, then
eased toward smoothly (`move_toward`, `AMBIENCE_LERP_RATE = 0.6`/sec) in
`_update_ambience_gains()` every frame — smoothing matters because
`Weather` only emits `weather_changed` roughly once every 1.5s
(`EMIT_INTERVAL`), and a bare volume snap on that cadence would be audible
as a series of small jumps rather than a continuous gust/lull. Wind's noise
filter also brightens (`_wind_brightness`, less low-pass smoothing) as
`wind_speed` rises, so a storm's wind reads as audibly harsher, not merely
louder. Sea's gain rises with `precipitation` and `storm_intensity`
together, on the reasoning that surf gets louder and the air fills with
rain-on-water texture as a storm builds, not just wind.

## Ducking (optional Voices/Louhi reaction)

`Voices.remark(speaker, line)` (`systems/voices/voices.gd`) is a real, live
signal — every trigger the game fires eventually routes through it. This
package connects to it and briefly dips both music layers to
`DUCK_AMOUNT` (0.45×) for `DUCK_HOLD_SEC` (1.1s), releasing back to full
over `~1.6s` via `move_toward`, giving a Domovoi/Hiisi remark a beat of
breathing room rather than fighting the music bed for attention. A public
`signal ducked(active: bool)` is emitted on state transitions for any
future consumer (subtitles, a VU-style UI) that wants to know the bed just
dipped.

The same dip is reused, at a slightly longer hold
(`DUCK_LOUHI_HOLD_SEC = 1.8s`), for `actors/louhi/louhi_director.gd`'s
`sign_occurred(tier, village_id, description)` signal — **but only if a
node answering to it exists**: `_connect_louhi_if_present()` does
`get_node_or_null("/root/LouhiDirector")` + `has_signal("sign_occurred")`
and connects with the string-based `Object.connect()` (not the
`signal_name.connect()` syntax, since `louhi` is statically typed as plain
`Node` here and doesn't know about package N's script-defined signal at
parse time) — mirroring the exact defensive-connection pattern
`louhi_director.gd` itself already uses for its own undiscovered
`/root/DuelArena` dependency. As of this pass, `LouhiDirector` is **not**
instanced anywhere in the project (confirmed in its own
`docs/systems/louhi.md` "Scoped out": "no autoload registration / no
automatic scene wiring... nothing in the shipped scene tree currently
instances her"), so this connection attempt is a real no-op today — stated
plainly, not silently assumed to be doing something.

## The one real asset: the rite bell

`Naklon.pole_crossed(pole: int)` (`core/naklon.gd`) is a real signal —
fires when Naklon enters mercy dominance, cruelty dominance, or returns to
the neutral band. `_on_pole_crossed()` plays
`res://audio/sfx/bong_001.ogg` (see "Assets used" below — a real,
downloaded, verified CC0 file, not a placeholder) through a dedicated
`AudioStreamPlayer`, with `pitch_scale` set slightly lower (0.85×) for
"returned to neutral" than for "crossed into a dominance" (1.0×) — one
sample, two readings, rather than needing (or fabricating) two separate
files for a single bell cue.

## Honesty: what's real vs. placeholder

This is the repository's core discipline (README, "What this repository
is, honestly") and this package's most consequential decision, so the
actual search performed is recorded here in full rather than summarized:

- **Kenney (https://kenney.nl)** was walked exhaustively for its Audio
  category — not sampled, all of it. Its Audio category, confirmed by
  paging through `kenney.nl/assets?category=Audio` and cross-checking
  against the direct-download zips, consists of exactly nine packs:
  *Digital Audio*, *UI Audio*, *Music Jingles*, *RPG Audio*, *Voiceover
  Pack*, *Voiceover Pack (Fighter)*, *Interface Sounds*, *Impact Sounds*,
  *Casino Audio*, *Sci-fi Sounds*. Two were downloaded and inspected in
  full (`kenney_rpg-audio.zip`, `kenney_music-jingles.zip`): RPG Audio is
  door/cloth/coin/footstep *interaction* foley (56 one-shots, none of them
  music or ambience); Music Jingles is 85 short (~1-2 second) fanfare
  *stings* across five instrument sets (8-bit, hit, pizzicato, sax, steel)
  — not a single sustained, loopable bed among them, and their character
  (upbeat game-show stings) would be a worse mismatch for "dark/ominous
  infernal mood" than an honest placeholder tone. **Kenney has no
  ambient-nature/wind/sea pack at all** — confirmed by walking the full
  category list, not inferred from absence.
- **Freesound (https://freesound.org)** — the sandbox has live internet
  access to the domain, but its search/download API requires
  authentication this sandbox does not have:
  `curl https://freesound.org/apiv2/search/text/?query=wind+loop` returns
  `401 {"detail":"Authentication credentials were not provided."}`. No
  workaround (preview-URL guessing, etc.) was attempted beyond this, since
  it would require already knowing specific sound IDs, which requires the
  same authenticated search this 401 blocks.
- **Musopen (https://musopen.org)** — every request returned `403`,
  including a retry with an explicit browser `User-Agent` header
  (`curl -A "Mozilla/5.0 ..." https://musopen.org/` -> 403). Not pursued
  further per the brief's own "do not burn excessive time/bandwidth on an
  exhaustive search" guidance.

Given that, **all four continuous beds — `prayer`, `infernal`, `wind`,
`sea` — are synthesized at runtime with `AudioStreamGenerator`**, per the
brief's own explicitly-sanctioned escape hatch, not sourced files:

- `prayer`: three sine partials (root/fifth/octave, A3/E4/A4) under a slow
  amplitude "breathing" swell — deliberately consonant, no beating.
- `infernal`: a low root against the tritone ("*diabolus in musica*," the
  traditional "devil's interval") a slow, uneasy LFO apart, plus a thin
  noise grit so it doesn't read as a clean, pure tone.
- `wind`: white noise through a one-pole low-pass filter whose cutoff
  brightens with `Weather.current.wind_speed`.
- `sea`: filtered noise under a slow rectified-sine surge/retreat envelope
  (~one wave cycle per ~8s).

All four are **real, working, audible code** — not silence, not `pass`
stubs — just not sourced/licensed audio content. This is stated as plainly
here as in the code's own header docstring, matching this repo's existing
precedent (`docs/systems/weather.md`'s and `docs/systems/louhi.md`'s own
"Scoped out" sections both name their own gaps the same way) rather than
being presented as a finished, "real" music/ambience pass.

**`audio/sfx/bong_001.ogg` is the one exception — a real, downloaded,
license-verified CC0 asset**, used as-is (see "The one real asset," above,
and "Assets used," below).

## Integration points (exact files)

- **`core/naklon.gd`** — reads `Naklon.unit()` every frame for the
  crossfade; connects `Naklon.naklon_changed` (immediate re-crossfade) and
  `Naklon.pole_crossed` (rite-bell cue). This is the package's one
  documented dependency per `docs/systems/OWNERSHIP.md`.
- **`systems/weather/weather.gd`** — connects `Weather.weather_changed`
  and reads `Weather.current` (`wind_speed`, `precipitation`,
  `storm_intensity`) to set ambience gain/brightness targets. Read-only;
  never writes back into `Weather.current`. As of this pass this is the
  **first** live consumer of `Weather.current` for audio — see
  `docs/systems/weather.md`'s own "Scoped out" ("nothing in world/,
  environment/, or audio/ currently reads Weather.current").
- **`systems/voices/voices.gd`** — connects `Voices.remark` for ducking.
  Read-only (never calls `Voices.react()`).
- **`actors/louhi/louhi_director.gd`** (package N, not a dependency per
  `docs/systems/OWNERSHIP.md`) — optional, defensive connection to
  `sign_occurred` if a node at `/root/LouhiDirector` happens to exist; see
  "Ducking," above, for why this is currently an inert no-op.
- **`project.godot`** — not edited. `MusicDirector`'s autoload path
  (`res://audio/music_director.gd`) was already registered by the
  foundation; this package only replaced that file's contents, per its
  ownership scope.

## Public API surface

```gdscript
var layers: Dictionary               # &"prayer" / &"infernal" -> AudioStreamPlayer (kept from the original stub contract)
signal ducked(active: bool)

func set_sea_anchor(node: Node3D) -> void   # reparents the spatial sea layer onto real geometry
func set_sea_position(pos: Vector3) -> void # or just moves it, without reparenting
```

Nothing else is exposed publicly; all synthesis/gain-smoothing state is
private (`_`-prefixed) since no other package depends on it per
`docs/systems/OWNERSHIP.md`.

## Scoped out

- **No sourced music or ambience audio.** See "Honesty," above, in full —
  not repeated here. The clean follow-up for a future audio pass: obtain
  (or commission) a real short, loopable prayer bed, infernal bed, wind
  loop, and sea/surf loop, then swap each `AudioStreamGenerator` for a real
  `AudioStreamOggVorbis`/`AudioStreamWAV` on the same player — the
  crossfade/ambience-gain/ducking logic around them does not need to
  change at all, since it operates entirely on `volume_db`, never on
  stream content.
- **`SEA_PLACEHOLDER_POSITION` is not real shoreline geometry.** `audio/`
  has no dependency on `world/ocean/` per `docs/systems/OWNERSHIP.md`, so
  this package could not read real coastline coordinates. `set_sea_anchor()`
  / `set_sea_position()` are the integration hook left for whoever next
  touches both packages together.
- **No audio bus routing.** Every player uses the default `Master` bus;
  no reverb/EQ send, no separate Music/Ambience/SFX bus split. Godot's bus
  layout lives in a separate resource this package didn't judge worth
  creating for a vertical slice's worth of players; a future pass wanting
  independent mix control (e.g. a settings-menu music/SFX slider) should
  add a bus layout resource and reassign `.bus` on each player — no
  restructuring of this file needed beyond that.
- **Both music layers always play, even at 0 gain.** Matches the original
  stub's documented "crossfaded continuously" contract, but does mean two
  extra `AudioStreamGenerator`s are being filled with samples nobody's
  currently hearing. Negligible at this scale (a handful of cheap sine/
  noise samples per frame); flagged rather than silently accepted as free.
- **No persistence / save-state for `Naklon`-driven mix position.** Not
  this package's concern — `Naklon.value` itself has no save/load hook
  anywhere in the codebase yet (matching `docs/systems/weather.md`'s same
  observation about `Weather.current`), so there's nothing for audio to
  restore on load until core/ grows one.
- **No Sanctum-specific interior mix.** `world/sanctum_interior/` (package
  T) might eventually want a distinct indoor ambience (muffled wind, no
  sea layer) when the player is inside; nothing here currently detects
  "inside a building." Not attempted since audio/ has no dependency on
  world/sanctum_interior/ and no signal yet exists anywhere in the
  codebase for "player entered an interior."

### Assets used

**Audio (SFX)** — exact row for the consolidation pass to copy into
`CREDITS.md`'s "Audio (SFX)" table:

| Asset | Source | Author | License | Attribution required? |
|---|---|---|---|---|
| `audio/sfx/bong_001.ogg` (from Kenney's "Interface Sounds" pack) | https://kenney.nl/assets/interface-sounds | Kenney (Kenney Vleugels) | CC0 1.0 (http://creativecommons.org/publicdomain/zero/1.0/) | No — CC0; a Kenney credit is requested but not mandatory per the pack's own License.txt |

**Music** — no row to add. No music asset was sourced (see "Honesty,"
above); `layers[&"prayer"]`/`layers[&"infernal"]` are runtime-synthesized
`AudioStreamGenerator` tones, not files, so there is nothing here that
traces to a third-party source or license — CREDITS.md's rule ("every row
above must trace to a real, checkable license") makes a fabricated row
worse than no row, so none was added.
