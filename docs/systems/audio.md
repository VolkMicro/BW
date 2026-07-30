# Audio

> ## Assets added 2026-07-30 (second pass)
>
> | File | Source | Author | Licence |
> |---|---|---|---|
> | `audio/sfx/village/chop.ogg`, `creak2.ogg`, `metalPot1.ogg`, `handleCoins.ogg`, `doorOpen_1.ogg`, `footstep03.ogg` | [kenney.nl/assets/rpg-audio](https://kenney.nl/assets/rpg-audio) | Kenney Vleugels | **CC0** (licence text shipped beside the files) |
> | `audio/music/oga_exploration.mp3` | [opengameart.org/content/medieval-exploration](https://opengameart.org/content/medieval-exploration) | see the OGA page | **CC0** |
>
> These are RECORDINGS of real objects, which is why they are sourced rather
> than synthesised: an axe in wood and a pot on a hearth are exactly what a
> delay line and some noise does badly, where a sea and a drone are exactly
> what it does well.
>
> The Exploration track is offered as an ALTERNATIVE to the synthesised mercy
> bed, selectable in Settings, not as a replacement. Only that layer: the
> infernal bed is built on the same D as the synthesised mercy one so the
> Naklon crossfade does not grind, and swapping one half of a matched pair
> would undo exactly what the pairing was for. Choosing the sourced track
> accepts a looser match — the player's call, since nobody working on this
> can hear either of them.
>
> **2026-07-30: the four continuous beds are now SYNTHESISED, not sourced.**
> `tools/synth_audio.py` writes them, and is committed beside them so any of
> it can be retuned and regenerated. The CC0 files they replaced were
> licence-clean and wrong for this island — see "Why they were replaced"
> below. The one-shot SFX for grabbing, throwing, the rite flash, thunder and
> the bell are still the sourced CC0 assets listed further down, and their
> paper trail is unchanged.
>
> ## Why they were replaced
>
> The project owner's verdict on the shipped mix was that the sea "just makes
> a monotone white-noise sound" and the whole thing "feels plastic". Both are
> accurate and both were structural:
>
> * **The sea was a short surf recording on a loop.** The ear resolves that
>   into flat noise within a few seconds, because a loop cuts the drain off
>   every wave that straddles its ends — what is left is texture where there
>   should be events. The synthesised sea is built from events instead: three
>   incommensurate swell periods with discrete breakers over them, each with
>   its own attack, hiss and drain. Measured at 5.5x between its quietest and
>   loudest half-second, where a noise bed is by definition 1.0x.
> * **Both beds were far too bright.** Measured spectral centroids on the
>   first synthesis attempt: sea 4181 Hz, wind 5123 Hz. That is hiss, not
>   weather. Surf and wind heard from three hundred metres up have had their
>   sparkle absorbed by the air long before they arrive. Now 1357 Hz and
>   1763 Hz.
> * **There was no music, only ambience.** The two "music" layers were
>   generic ambient loops with no relationship to each other or to the game.
>   They are now built on the same D so the Naklon crossfade does not grind:
>   D Dorian above (the mode most northern and eastern European folk music
>   sits in — minor-coloured but with a raised sixth, melancholy without
>   being funereal), the same D an octave down with a semitone rub below.
>   Plucked voices are Karplus-Strong, which is the closest thing to a gut
>   string you can get out of a delay line and some noise.
>
> Four outcome cues were added at the same time, for the playability audit's
> finding that a rite landing, a rite out of reach and a rite on a village
> that has heard enough all felt identical.
>
> **Still unverified by ear.** This sandbox has no audio device; everything
> above is measured, not listened to. Retune after a real listen.

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
3. **A one-shot SFX layer** (added in the second audio pass) for the things
   a player actually *does*: the Hand grabbing, the Hand throwing/setting
   down, a rite being cast, and thunder during a storm. Spatial
   (`AudioStreamPlayer3D`, small fixed voice pool) for the Hand/rite cues,
   non-spatial for thunder. See "One-shot SFX" below.

All three parts are genuinely wired to their upstream signals and running
code, not stubs.

**Update — second sourcing pass:** the audio *content* is now real too.
All four continuous beds and all four one-shot SFX are real, downloaded,
CC0-licensed `.ogg` files from OpenGameArt.org; the runtime-synthesized
tones are retained as a per-layer fallback for a build with a missing file.
The full record of both sourcing passes — including the first pass's dead
ends, which are still accurate — is in "Honesty: what's real vs.
placeholder" below. Read it before assuming *how good* any of it sounds:
nothing here has been auditioned, because this build sandbox has no audio
device.

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

> **Superseded by the second audio pass.** `_connect_louhi_if_present()`
> is gone; the hardcoded `/root/LouhiDirector` path was wrong once the
> integration pass instanced her at `/root/GodView/LouhiDirector`, so the
> connection would have stayed a silent no-op forever. Louhi is now found
> by capability along with the Hand and the sigil caster — see "Emitter
> discovery — and a latent bug it fixed," below. The ducking behaviour
> described above (amount, holds, `ducked` signal) is unchanged; only the
> way her node is located changed, and it now genuinely fires.

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

## One-shot SFX (second audio pass)

Before this pass, **nothing in the entire repository played a sound for
anything a player did.** Verified, not assumed: `grep -rn
"AudioStreamPlayer" --include=*.gd --include=*.tscn .` returned matches in
`audio/music_director.gd` and nowhere else — the Hand, the sigil caster,
the villagers, the Avatar, the combat system and the weather system all
emitted their signals into silence. That was the single largest audio gap,
larger than the music placeholder question, so it was closed here.

Four cues, chosen as the smallest set that covers what a player is
actually doing most of the time:

| Cue | Trigger | Player | Variation |
|---|---|---|---|
| grab | `Hand.grabbed(node)` | 3D, at the Hand's `global_position` | pitch ±7% random, so repeats don't sound machine-stamped |
| throw / set-down | `Hand.released(node, velocity)` | 3D, at the Hand | `velocity.length()` decides: under `THROW_MIN_SPEED` (2.5 m/s) it re-uses the softer *grab* sample quieter and lower ("put down"); above it, the air-whoosh, with volume and pitch both scaling to `speed / THROW_REF_SPEED` |
| rite cast | `SigilCaster.rite_cast(rite_id, confidence)` | 3D, at the caster | the recognizer's own `confidence` drives volume and pitch — a sloppy match that barely registered sounds thinner than a clean one |
| thunder | `Weather.current.storm_intensity` (see below) | non-spatial | volume scales with storm severity; pitch ±9% random |

**Thunder is generated by this package, not triggered by a strike event,
because no strike event exists.** `systems/weather/weather.gd` models
weather as a continuously-blended `current` Dictionary and has no
lightning/strike signal of any kind — nothing to subscribe to. So
`_update_thunder()` runs its own self-scheduling timer: below
`THUNDER_MIN_INTENSITY` (0.25) it re-arms and stays silent; above it, the
gap between cracks interpolates from `THUNDER_GAP_MAX` (26s) down to
`THUNDER_GAP_MIN` (7s) as severity rises, times a `randf_range(0.6, 1.4)`
jitter so the rhythm never becomes a metronome. The honest consequence:
**thunder does not line up with any visual lightning** — there is no
lightning VFX in the build either, so nothing is currently out of sync,
but a future VFX pass must drive its flash from the new
`thunder_cracked(intensity)` signal rather than rolling its own timer, or
the two will drift apart.

Thunder is deliberately **non-spatial**, for the same reason wind is: a
storm is a whole-board condition, and thunder that pans and attenuates
with camera position would read as "a small noise over there" instead of
weather.

### Voice pool, not per-event nodes

`SFX_VOICES = 4` `AudioStreamPlayer3D`s are created once at `_ready()` and
reused round-robin; a fifth overlapping one-shot steals the oldest voice.
No node is allocated or freed per event. Four is not arbitrary: the Hand
is the game's only cursor and can physically grab or throw exactly one
thing at a time, so four covers a throw whoosh still ringing while the
next grab and a rite fire, with headroom. Bounding it matters more than
the audio does on a machine this GPU-starved — an unbounded
`AudioStreamPlayer3D.new()`-per-event pattern is the standard way this
gets expensive later.

## Emitter discovery — and a latent bug it fixed

`audio/` owns none of the packages that emit these signals and may not
edit `world/god_view.tscn` (`docs/systems/OWNERSHIP.md`), so nothing here
uses a hardcoded `NodePath`. Instead `_on_node_added()` — connected to
`get_tree().node_added` — binds by **capability**: the first node to enter
the tree with both a `grabbed` and a `released` signal is the Hand; the
first with `rite_cast` is the sigil caster; the first with `sign_occurred`
is Louhi. Each binding also connects that node's `tree_exiting` so the
reference is cleared and re-bound on a scene reload or skirmish-map swap.
A one-shot deferred `_scan_tree_for_emitters()` sweep covers the reverse
ordering (an already-running tree when the autoload comes up).

This replaced the previous pass's
`get_node_or_null("/root/LouhiDirector")`, which **had never once fired**:
`world/god_view.tscn` instances her at `/root/GodView/LouhiDirector`, one
level deeper than that path. The old code was documented as "a real no-op
today" on the grounds that Louhi wasn't instanced anywhere — true when it
was written, no longer true after the integration pass, and the hardcoded
path would have silently kept it a no-op forever. Louhi's sign-ducking now
genuinely connects (verified — see "How this was verified").

Cost: `_on_node_added` runs for every node entering the tree. Once all
three are bound it early-returns on three null compares; before that it
does up to four `has_signal()` hash lookups. Both are far below the cost
of instancing the node that triggered the callback.

## Honesty: what's real vs. placeholder

This is the repository's core discipline (README, "What this repository
is, honestly") and this package's most consequential decision, so the
actual search performed is recorded here in full rather than summarized.

### First pass (dead ends — still accurate, kept for the record)

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

Those three findings are still true. What they were not is *the whole
internet* — see the second pass, next.

### Second pass — OpenGameArt.org, and what it turned up

The first pass never tried OpenGameArt.org, which unlike Kenney is a
game-asset site with a real, filterable licence facet and genuine CC0
ambient loops and mood music. Its advanced search
(`opengameart.org/art-search-advanced`) exposes art-type and licence as
query facets — `field_art_type_tid[]=12` (Music) / `13` (Sound Effect) and
`field_art_licenses_tid[]=4` (CC0) — so it can be queried directly for
"CC0 only," which is exactly the filter this repo's rules need. Every
candidate's licence was then re-confirmed on its own item page (the
`license-name` block) rather than trusted from the search facet, and for
derivative works the parent asset's licence was checked too.

**Eight files were found, downloaded and shipped. All are CC0.** Exact
rows are in "Assets used" below. Two provenance notes worth stating
explicitly:

- `wind_woosh_loop.ogg` (SketchMan3) is a **derivative** — the author's own
  description says it is a looped, EQ'd section of OpenGameArt's *Loopable
  Dungeon Ambience*. That parent was checked and is itself CC0 (author
  JaggedStone), so the chain is clean end to end. A CC0 derivative of an
  unverified parent would not have shipped.
- `jasinski_beach_waves.ogg` is a **mirror**: OpenGameArt user *qubodup*
  re-hosted Freesound sound #18363 by *jasinski*, which is CC0 at source.
  This is the one place the first pass's Freesound wall was routed around
  — not by evading Freesound's API auth, but because a CC0 sound had
  already been legitimately mirrored somewhere that doesn't need a key.

**Sources checked in this pass and rejected:**

- **archive.org** — its `advancedsearch.php` JSON endpoint works fine from
  this sandbox (no auth needed) and a `mediatype:(audio) AND
  licenseurl:(*publicdomain*)` query returns tens of thousands of hits.
  It was still rejected as a source for this package, on provenance
  grounds rather than availability: the top ocean/ambience matches are
  things like *"2 Tropical Beach Ambience 3 Hours Of Peaceful Ocean Waves
  (4K Video) (128 Kbps)"* tagged with the **Public Domain Mark** by an
  uploader who is plainly not the recording's author. The PD Mark is a
  third-party *assertion* about someone else's work, not a licence grant,
  and re-uploaded video rips are the textbook case where that assertion is
  wrong. CREDITS.md's rule ("if an asset's origin can't be established, it
  does not go in the build — full stop") disqualifies these. archive.org
  is genuinely useful for *known* public-domain-era recordings; it was not
  needed once OpenGameArt supplied everything, so no further time went
  into it.
- **IMSLP** — not pursued, deliberately. The brief's own caution is the
  whole reason: IMSLP's strength is public-domain *scores*, and a
  public-domain score says nothing about the rights in a particular
  *recording* of it. Establishing per-recording rights there is slow, and
  OpenGameArt had already produced clean, explicitly-CC0, loop-ready
  files. Recorded as "not attempted," not as "checked and empty."
- **Freesound / Musopen / Kenney** — unchanged from the first pass; not
  re-attempted.

### What is real now, and what is still not

Real: **every bed and every SFX in the build is a sourced, CC0-licensed
file.** `_layer_is_sourced` records this per layer at startup, and the
self-test below confirms all four beds and all four SFX loaded.

Still not verified: **how any of it sounds.** This sandbox has no audio
device, so every file was chosen from its title, its author's own
description, its duration, and its channel/sample-rate header — *not by
listening to it*. Concretely, these are guesses, flagged as guesses:

- the loudness trims (`SOURCED_MUSIC_TRIM_DB = -8`,
  `SOURCED_WIND_TRIM_DB = -7`, `SOURCED_SEA_TRIM_DB = -6`, and the
  `SFX_*_DB` constants) are conservative first estimates, not a mix;
- the sea bed is a 12.3s field recording of beach surf looped by
  `AudioStreamOggVorbis.loop = true`. Surf is broadband, so a seam is more
  likely to read as a small level step than a click — but **the seam has
  not been heard**, and if it is audible the honest fix is a longer
  recording, not a code change;
- whether the "dark cavern" bed reads as *infernal* rather than merely
  *cave-y*, and whether the "heavenly" bed reads as *prayer*, is a
  judgement made from the authors' descriptions.

Anyone with speakers should re-audition all eight files and retune those
constants; that is a real remaining task, not a formality.

### The synthesized tones are kept, as a fallback

The runtime `AudioStreamGenerator` synthesis was **not deleted**. Each bed
independently calls `_stream_for_layer()`, which checks
`ResourceLoader.exists()` and falls back to that layer's original
synthesis (with a `push_warning`) if the `.ogg` is missing from the build.
A missing asset degrades one layer to a tone; it never crashes and never
goes silent. The four synthesis routines are unchanged and still
documented here:

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
stubs. In a normal build none of them run (see "Performance," below); they
exist so that a build missing an asset still makes a sound.

One behavioural difference between sourced and synthesized wind, stated
because it is a small honest regression: the synthesized wind *brightens*
its low-pass filter as `Weather.current.wind_speed` rises, so a gale reads
as harsher, not just louder. A fixed recording can't do that. The
substitute is a ±6% `pitch_scale` nudge on the sourced wind bed driven by
the same `_wind_brightness` value — cheaper and audible, but not the same
thing as an opening filter. A future pass wanting the real behaviour back
should route the wind player through an audio bus with an
`AudioEffectLowPassFilter` and automate its cutoff; that needs a bus
layout resource this package still doesn't create (see "Scoped out").

## Performance

The relevant number here is a **saving**, not a cost.

The previous all-synthesized version called a GDScript `Callable` **once
per audio sample per layer** — 44,100 × 4 = **~176,400 GDScript function
calls per second**, on the main thread, every second the game was running,
whether or not anyone could hear the result.

That loop was benchmarked directly in this sandbox (the sandbox has no
GPU, but it does have a CPU, so this is a real measurement, not an
estimate): **17.06 ms of CPU to synthesize one second of one layer**, on
an Intel Xeon E5-2695 v3 @ 2.30 GHz. Four layers ≈ **68 ms of main-thread
CPU per second of wall-clock time**, independent of framerate. At the
target machine's current ~5–6 fps (~170 ms/frame) that is roughly **11 ms
of every frame**, ~7% of the frame budget, spent on placeholder tones.

Now that all four beds are file-backed, `_fill_all_generators()`
early-returns on four null compares and that entire cost is gone. Decoding
four Vorbis streams instead happens on Godot's own audio thread in C++,
which is what that thread is for.

Caveats, stated rather than glossed: the benchmark measures the synthesis
loop in isolation on a *different* CPU from the target Dell Latitude 5411
(whose i5-10310U has better single-thread IPC, so the real figure there is
probably somewhat lower). **No frame rate was measured, before or after —
this sandbox has no GPU and cannot measure one.** The claim is "this much
main-thread CPU work per second was removed," which is measurable, not
"the game got N fps faster," which is not.

What this pass *added* per frame:

- `_update_thunder(delta)`: one float compare when there's no storm; one
  compare, one subtract and (every 7–26 s) one `randf_range` during one.
  Unmeasurably cheap.
- one `clampf` + one `pitch_scale` write per frame on the wind player
  while the wind bed is file-backed, inside the existing
  `_update_ambience_gains()` — no new traversal.
- `_on_node_added`: **not** per-frame; per node entering the tree, and
  three null compares once the three emitters are bound.
- Voices: 4 pooled `AudioStreamPlayer3D` + 1 `AudioStreamPlayer`, created
  once. Idle players cost nothing; they are not filled or mixed while
  stopped.

Memory added: ~3.4 MB of `.ogg` on disk (3.3 MB of it the two music beds),
decoded on demand by Godot's Vorbis decoder rather than held as PCM.

**`audio/sfx/bong_001.ogg`** remains the first pass's one real asset (see
"The one real asset," above, and "Assets used," below).

## How this was verified

`godot --headless --path . --check-only --quit-after 3` parses clean for
this package (the parse errors present in that run belong to
`actors/villagers/villager.gd` and `actors/wildlife/wild_creature.gd`,
other packages' in-flight work at the time of writing, not to `audio/`).

Parsing is not running, so behaviour was also checked with a **temporary**
self-test scene under `audio/` (instanced the real
`actors/hand/hand.tscn`, `systems/sigils/sigil_caster.tscn` and
`actors/louhi/louhi_director.tscn`, emitted their real signals, then
deleted — it is not in the repo). It confirmed, at runtime:

- `_layer_is_sourced == {prayer: true, infernal: true, wind: true, sea:
  true}` — all four beds file-backed, no fallback taken;
- all four SFX streams loaded (`grab`, `throw`, `rite`, `thunder`);
- both music players `playing == true` with a sane `volume_db`;
- emitter discovery bound the real `Hand`, `SigilCaster` **and
  `LouhiDirector`** (the last of which the old hardcoded path never
  found);
- emitting the real `grabbed` / `released` / `rite_cast` signals started
  voices in the pool; forcing `storm_intensity = 0.9` fired thunder and
  re-armed the timer.

Not verified: anything audible. Headless Godot uses a dummy audio driver.
"`playing == true`" means the engine accepted the stream and started
playback; it is not evidence that the result sounds good, or even that it
sounds like wind.

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
  `docs/systems/OWNERSHIP.md`) — optional connection to `sign_occurred`,
  now found by capability rather than by hardcoded path, so it fires
  against the real `/root/GodView/LouhiDirector`. See "Emitter discovery."
- **`actors/hand/hand.gd`** (package E, not a dependency) — optional
  connections to `grabbed(node)` and `released(node, velocity)` for the
  grab/throw SFX. Read-only: this package never calls into the Hand, never
  moves it, and never gates its actions.
- **`systems/sigils/sigil_caster.gd`** (package F, not a dependency) —
  optional connection to `rite_cast(rite_id, confidence)` for the rite SFX.
  Read-only.
- **`project.godot`** — not edited. `MusicDirector`'s autoload path
  (`res://audio/music_director.gd`) was already registered by the
  foundation; this package only replaced that file's contents, per its
  ownership scope. **No audio bus layout was added either** — see "Scoped
  out."

## Public API surface

```gdscript
var layers: Dictionary               # &"prayer" / &"infernal" -> AudioStreamPlayer (kept from the original stub contract)
signal ducked(active: bool)
signal thunder_cracked(intensity: float)  # fired when a thunder one-shot starts; drive a lightning flash from THIS, not a second timer

func set_sea_anchor(node: Node3D) -> void   # reparents the spatial sea layer onto real geometry
func set_sea_position(pos: Vector3) -> void # or just moves it, without reparenting
```

Nothing else is exposed publicly; all synthesis/gain-smoothing/SFX-pool
state is private (`_`-prefixed) since no other package depends on it per
`docs/systems/OWNERSHIP.md`. In particular, other packages should **not**
call into `MusicDirector` to play their own sounds — this package finds
their signals, not the other way round, so `audio/` stays the only
directory that has to know about audio.

## Scoped out

- **~~No sourced music or ambience audio.~~ Closed by the second pass** —
  all four beds and all four SFX are now real CC0 files (see "Honesty" and
  "Assets used"). What remains open is the *mix*: nothing has been
  auditioned, so the trim constants are unverified guesses. That is a
  listening task, not a coding task.
- **No SFX for anything beyond the four cues.** Villagers praying, the
  Avatar's moves/growth, combat hits, construction completing, quest and
  relic events, sanctum damage — all of these emit real signals this
  package could bind to with three more lines each, and none of them make
  a sound. Villager prayer specifically was checked and *cannot* be done
  cleanly yet: `actors/villagers/villager.gd` exposes no "started praying"
  signal at all (the only villager-adjacent signals in the codebase are
  `GameState`'s conversion/devotion ones), so there is nothing to connect
  to without editing package G. Deliberately left: four well-documented
  cues beat twenty guessed ones on a machine at 5–6 fps, and every extra
  cue is another unauditioned file.
- **No footsteps, no UI sounds, no voice-over.** Same reasoning; also
  `systems/voices/` produces *text* remarks, not spoken lines, so
  "the Two Voices" are subtitles with a music duck, not audio.
- **No dynamic music beyond the Naklon crossfade.** No stems, no tempo or
  key matching between the prayer and infernal beds (they are two
  unrelated recordings by two different authors, played simultaneously at
  complementary gains). Equal-power crossfading two unrelated ambient beds
  is musically safe *because* neither has a strong tonal centre — but it
  is not the same thing as a scored, layered adaptive soundtrack, and it
  has not been heard.
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
  stub's documented "crossfaded continuously" contract. This is now much
  cheaper than it was: at 0 gain the layer is a Vorbis stream being
  decoded on the audio thread, not 44,100 GDScript calls per second on the
  main thread (see "Performance"). Still not free — flagged rather than
  silently accepted.
- **The wind bed can no longer open a filter with wind speed.** The
  synthesized version could; a fixed recording can't. Substituted with a
  ±6% pitch nudge. The real fix needs an audio bus with a low-pass effect
  — see the bus-routing item above. Documented as a small, deliberate
  regression rather than quietly dropped.
- **Thunder is invented here, not driven by a lightning event.**
  `systems/weather/weather.gd` has no strike signal, so thunder is
  scheduled from `storm_intensity` by this package. It will not line up
  with any future lightning VFX unless that VFX listens to
  `thunder_cracked`. See "One-shot SFX."
- **`AudioStreamOggVorbis.loop = true` is set in code, not baked into the
  `.import` files.** Deliberate (the intent is visible in review, and the
  same file could be reused as a one-shot elsewhere), but it does mean the
  loop flags live in `music_director.gd` — a future pass regenerating the
  imports won't accidentally change behaviour, but also won't see the
  loops in the import settings.
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
| `audio/sfx/sfx100v2_items_01.ogg` (grab / set-down; from the "100 CC0 SFX #2" pack, original filename kept) | https://opengameart.org/content/100-cc0-sfx-2 | rubberduck | CC0 1.0 (http://creativecommons.org/publicdomain/zero/1.0/) | No — CC0 |
| `audio/sfx/sfx100v2_air_01.ogg` (throw whoosh; same pack, original filename kept) | https://opengameart.org/content/100-cc0-sfx-2 | rubberduck | CC0 1.0 (http://creativecommons.org/publicdomain/zero/1.0/) | No — CC0 |
| `audio/sfx/sfx100v2_thunder_01.ogg` (storm thunder; same pack, original filename kept) | https://opengameart.org/content/100-cc0-sfx-2 | rubberduck | CC0 1.0 (http://creativecommons.org/publicdomain/zero/1.0/) | No — CC0 |
| `audio/sfx/magical_4.ogg` (rite-cast cue; from the "Magic Spell SFX" set, original filename kept) | https://opengameart.org/content/magic-spell-sfx | JaggedStone | CC0 1.0 (http://creativecommons.org/publicdomain/zero/1.0/) | No — CC0 |

**Audio (music & ambience)** — new table for the consolidation pass;
`CREDITS.md`'s "Music" section currently says "None," and should be
replaced with these four rows plus a pointer back to this doc:

| Asset | Source | Author | License | Attribution required? |
|---|---|---|---|---|
| `audio/music/heavenly_loop.ogg` (the `prayer` bed; OGA title "Heavenly Loop", original file `Heavenly Loop_0.ogg`) | https://opengameart.org/content/heavenly-loop | isaiah658 | CC0 1.0 (http://creativecommons.org/publicdomain/zero/1.0/) | No — CC0 |
| `audio/music/dark_cavern_ambient_002.ogg` (the `infernal` bed; OGA title "Dark Cavern Ambient", file `002` = the continuous-loop variant) | https://opengameart.org/content/dark-cavern-ambient | Paul Wortmann | CC0 1.0 (http://creativecommons.org/publicdomain/zero/1.0/) | No — CC0 |
| `audio/music/wind_woosh_loop.ogg` (the `wind` ambience bed; OGA title "wind whoosh loop", original file `wind woosh loop.ogg`) | https://opengameart.org/content/wind-whoosh-loop | SketchMan3 — a CC0 derivative of "Loopable Dungeon Ambience" by JaggedStone (https://opengameart.org/content/loopable-dungeon-ambience), which is itself CC0; both checked | CC0 1.0 (http://creativecommons.org/publicdomain/zero/1.0/) | No — CC0 |
| `audio/music/jasinski_beach_waves.ogg` (the `sea` ambience bed; OGA title "Beach Ocean Waves", original file `jasinski-wave-prev.ogg`) | https://opengameart.org/content/beach-ocean-waves | jasinski (recording), mirrored to OpenGameArt by qubodup from Freesound #18363 (https://freesound.org/people/jasinski/sounds/18363/), CC0 at source | CC0 1.0 (http://creativecommons.org/publicdomain/zero/1.0/) | No — CC0 |

Notes for the audit pass, stated rather than left to be discovered:

- **Every one of these is CC0**, so none carries a mandatory attribution
  obligation. They are listed anyway because this repo credits by policy,
  not only where legally compelled.
- **Original filenames were kept** (`sfx100v2_items_01.ogg`,
  `magical_4.ogg`, …) rather than renamed to gameplay names, specifically
  so an auditor can match a file in the build to a file in the source pack
  without trusting this table.
- Licences were confirmed on each asset's own OpenGameArt item page (the
  `license-name` block), not merely from the search filter, and for the
  one derivative the parent's licence was confirmed too.
- These files were **not auditioned** — see "What is real now, and what is
  still not." Their licensing is verified; their suitability is a
  judgement from the authors' own descriptions.
- Nothing was taken from archive.org. Its Public-Domain-Mark uploads of
  third-party recordings do not establish origin to this repo's standard;
  see "Second pass" for the full reasoning.
