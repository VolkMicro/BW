# Environment & performance notes (package Q)

## What this package built

Two small, non-autoload `Node` scripts in `environment/`, styled directly
after package D's `shaders/naklon_shader_driver.gd` (tiny, no exported
scene dependency beyond the shared resource, idempotent `_ready()`, safe to
instantiate more than once):

- **`environment/naklon_environment_driver.gd`** (`class_name
  NaklonEnvironmentDriver`) — drives the shared
  `environment/world_environment.tres` Environment resource's sky colors,
  fog light color, `volumetric_fog_albedo`, `tonemap_white`, the
  `adjustment_*` grade sliders, and glow from `Naklon.unit()`, using
  package D's exact mercy/cruelty target numbers
  (`docs/systems/art_direction.md` §4).
- **`environment/weather_environment_driver.gd`** (`class_name
  WeatherEnvironmentDriver`) — the **first real visual consumer** of
  `Weather.current` (`systems/weather/weather.gd`, package P), which that
  package's own doc flags as unconsumed. Drives `fog_density`,
  `volumetric_fog_density`, `tonemap_exposure`, `ambient_light_energy`,
  `background_energy_multiplier`, and `fog_light_energy` from
  `cloud_cover` / `precipitation` / `storm_intensity`.

Both scripts `load()` `environment/world_environment.tres` directly rather
than requiring a `NodePath` to a `WorldEnvironment` node — Godot's
`ResourceLoader` caches by path, so this returns the same live `Environment`
instance already assigned to whatever `WorldEnvironment` node references
that path elsewhere in the project, and mutating it in place is visible
immediately, no scene-tree wiring required. `world_environment.tres` itself
is untouched (still exactly the foundation-authored file) — everything
here is a runtime extension, per `docs/systems/OWNERSHIP.md`. Two
one-node wrapper scenes (`environment/naklon_environment_driver.tscn`,
`environment/weather_environment_driver.tscn`, same shape as
`actors/louhi/louhi_director.tscn`) are provided for convenience; the
scripts work equally well added to any existing scene by hand.

## How the two divide the Environment (so they don't fight)

| Concern | Owner | Properties |
|---|---|---|
| Mood/grade ("what pole is the world at") | `NaklonEnvironmentDriver` | sky/ground colors (on the `ProceduralSkyMaterial` sub-resource), `fog_light_color`, `volumetric_fog_albedo`, `tonemap_white`, `adjustment_brightness/contrast/saturation`, `glow_intensity`, `glow_hdr_threshold`, `adjustment_color_correction` (optional) |
| Weather atmosphere ("what's the sky doing") | `WeatherEnvironmentDriver` | `fog_density`, `volumetric_fog_density`, `tonemap_exposure`, `ambient_light_energy`, `background_energy_multiplier`, `fog_light_energy` |

Fog density is the one property both conceptually care about. Rather than
both writing it, `NaklonEnvironmentDriver` computes (but never writes) a
Naklon-scaled *base* fog/volumetric-fog density, exposed via
`get_base_fog_density()` / `get_base_volumetric_fog_density()`.
`WeatherEnvironmentDriver` looks that instance up by group
(`NaklonEnvironmentDriver.GROUP_NAME`, via
`get_tree().get_first_node_in_group()` — no hard `NodePath`) and multiplies
that base by its own weather factor before writing the final value. If no
`NaklonEnvironmentDriver` is present in a given scene, it falls back to the
plain values already in the checked-in `.tres`, so it still works standing
alone. `sdfgi_*`, `ssao_*`, `ssil_enabled`, and `tonemap_mode` are left
untouched by both scripts, matching `art_direction.md` §4's explicit
instruction that GI/AO quality shouldn't visibly shift with mood or
weather — only color and atmosphere do.

**Known boot-order nuance:** if `WeatherEnvironmentDriver`'s `_ready()`
happens to run before `NaklonEnvironmentDriver`'s in a given scene's child
order, its very first application (at `_ready()`, before either signal has
fired again) uses the fallback base density rather than Naklon's, for
exactly one application — self-corrects the moment either driver next
reacts to its own signal. Not a bug, just a startup-ordering detail worth
stating rather than leaving implicit.

## Deviation from `art_direction.md` §4's literal formula (documented)

§4 states the Naklon blend as a straight two-point
`lerp(mercy_value, cruelty_value, Naklon.unit())`. Applied literally, this
would discard whatever is actually sitting in the checked-in `.tres` at
Naklon's neutral resting value (`Naklon.value` defaults to `0.0`, i.e.
`unit() == 0.5`), because the table's own "Baseline (current .tres,
Naklon=0)" column is *not* the midpoint of its Mercy/Cruelty columns —
e.g. `sky_top_color`'s baseline `(0.259, 0.443, 0.702)` is nowhere near the
mercy/cruelty midpoint `(0.225, 0.325, 0.405)` the literal formula would
produce at `unit == 0.5`. A player who has never acted (Naklon exactly
neutral) would otherwise see the sky change the instant this driver's
`_ready()` runs, with no action of theirs behind it. `NaklonEnvironmentDriver`
instead captures whatever is already in the `.tres` at `_ready()` as a live
baseline anchor and does a **piecewise** lerp — mercy → baseline over unit
`[0, 0.5]`, baseline → cruelty over unit `[0.5, 1]` — which still reaches
exactly D's documented Mercy/Cruelty targets at the poles and still reads
as one continuous blend, but keeps the neutral resting look exactly as
already authored. Flagged here rather than silently diverging from D's doc
without explanation; not a criticism of D's handoff, just a case where the
literal formula and the stated intent ("the sky/fog/tonemap breathe in
sync with Naklon") pulled in different directions at exactly one point
(neutral), and this pass picked the reading that matches the intent.

## Frame budget: honest, design-time-only assessment

**No GPU exists in this sandbox** (`docs/rendering.md`), so nothing below
is a measured frame time — it is a design-time judgment about what kind of
work this package's additions actually are, cross-referenced against
`docs/systems/engineering.md`'s frame-budget table. This repo does not
claim a frame rate it hasn't measured, here or anywhere else.

`engineering.md`'s table budgets **Volumetric fog + post (glow/DOF/tonemap/
TAA)** at ~2.0 ms and leaves the rest (SDFGI/reflections ~2.5 ms, shadows
~2.5 ms, opaque geometry ~6.0 ms, etc.) alone. This package's writes land
entirely inside that one line item's *inputs* — they change **uniform
values already consumed by pipeline stages that run regardless** (the
volumetric fog compute pass, the tonemap/adjustment post shader), not new
passes, new geometry, new lights, or new shadow casters. Concretely:

- **Cheap, by construction — the normal case:**
  - `NaklonEnvironmentDriver` does nothing at all except while `Naklon`
    is actually mid-tween: `Naklon.naklon_changed` only fires on a
    deliberate player action (`core/naklon.gd`'s own comment: "Naklon does
    not passively drift; only actions move it"), so outside of that this
    script is fully inert — no `_process()`, no polling.
  - `WeatherEnvironmentDriver` reacts to `Weather.weather_changed`, which
    `systems/weather/weather.gd` itself throttles to at most once per 1.5s
    (`EMIT_INTERVAL`) in procedural mode or once per 900s poll in
    real-feed mode. Each reaction is a handful of `float`/`Color` lerps and
    up to ~16 `Object.set()`-equivalent property writes total across both
    scripts — trivially cheap on any CPU, this sandbox's llvmpipe included,
    since none of it touches the GPU/shader-compile path.
  - The optional LUT cross-fade (`NaklonLutBlend.blended()`, off by
    default — see below) is a 256×4 = 1024-pixel CPU image blend, called
    at most once per Naklon change, matching `naklon_lut_blend.gd`'s own
    documented cost/usage guidance verbatim.

- **The one real, bounded per-frame cost — worth naming plainly:** both
  scripts ease their target values over `ease_seconds` (default 1.5s for
  Naklon, 1.2s for Weather) via a `Tween` rather than snapping instantly,
  for visual polish. While a tween is in flight, Godot's tween processing
  writes a handful of interpolated properties to one `Environment`
  resource once per frame — not a shader recompile, not a draw call, not
  new geometry, just `Object` property setters. This is several orders of
  magnitude below anything in `engineering.md`'s budget table, but it is
  not literally free, and — because `Weather.weather_changed` can fire
  every 1.5s during a long storm system, close to `WeatherEnvironmentDriver`'s
  own 1.2s ease window — its tween could in practice be almost
  continuously active during sustained bad weather, rather than the rare,
  short-lived case Naklon's tween is (player actions are not that
  frequent). Still cheap in absolute terms; flagged as the one place this
  package's design could compound if a real profiling pass ever showed
  otherwise.
- **Fog/tonemap density value changes do not change pipeline cost.** The
  volumetric fog compute shader and the tonemap/adjustment post shader run
  every frame regardless of what `fog_density`/`tonemap_exposure`/etc. are
  set to — this package changes their *inputs*, not whether or how many
  times those passes execute. A design-time read cannot rule out that an
  extreme density value increases perceived overdraw/complexity in ways
  that would only show up in a real GPU profile, so that residual
  uncertainty is stated rather than waved away.

### A genuinely new lever (added to this doc, not to `engineering.md`)

`engineering.md`'s existing "practical levers" list (scale_3d, SDFGI
cell/cascade count, fog filtering, shadow resolution, before ever cutting
draw distance/crowd counts) is about the rendering pipeline itself and
this package doesn't add to it there — `engineering.md` is
foundation-owned and out of scope for this package to edit regardless. One
lever specific to *this* package's own code, worth recording here for
whoever eventually runs a real profiling pass: if Environment-property
tweening ever shows up as measurable, both `ease_seconds` exports (default
1.5s / 1.2s) can be set to `0.0` to make either driver snap instantly
instead of easing, at zero further code change — this removes the one
per-frame cost this package introduces, in exchange for a harder visual
cut on mood/weather changes.

### Where this leaves the existing SDFGI/volumetric fog/glow stack

Unchanged and unexamined further here beyond the above — this package
does not touch `sdfgi_enabled`, `sdfgi_cascades`, `sdfgi_min_cell_size`,
`ssao_*`, or `ssil_enabled` at all, matching `art_direction.md` §4's
explicit instruction. Package A's (`engineering.md`) budget and levers for
that part of the stack stand exactly as written; this doc doesn't
duplicate them.

## Real-hardware incident: ~1 fps on first actual playtest, and the fixes

Everything above was written honestly as a **design-time-only** assessment
because no GPU existed anywhere this project had been built or run. The
first time a real person actually cloned the repo and pressed Play on a
real GPU (Windows, `world/god_view.tscn`), it ran at approximately **1
fps** — effectively unplayable. This section records what was actually
changed in response, by a later pass than the one that wrote the rest of
this doc, since the honest thing to do with a "not yet measured" caveat
that turns out badly is to say so plainly once it is measured, not quietly
leave the design-time text standing uncorrected.

**Diagnosis (reasoned from the exact settings in place, not a real GPU
profiler trace — still not available in the sandbox this fix was written
in):** the checked-in stack combined, all simultaneously, at fairly
aggressive quality: `sdfgi_cascades = 6` at `sdfgi_min_cell_size = 0.2`
(fine voxel GI over a wide world footprint), `ssil_enabled = true`
alongside SDFGI (redundant indirect-lighting cost — SDFGI already supplies
indirect light; SSIL is one of the more expensive screen-space passes and
was adding cost on top of it, not instead of it), 4x MSAA *and* the
project's own `scaling_3d/mode = 2` (FSR2) active together (FSR2 already
does its own temporal reconstruction; combining it with explicit MSAA is
close to paying for two different anti-aliasing strategies at once),
`directional_shadow/size = 4096` with `soft_shadow_filter_quality = 3`
(high-quality PCSS-style soft shadows, expensive), and
`scaling_3d/scale = 0.9` (rendering at 90% resolution, a small win at
best). Layered on top of three runtime-built CSG Sanctums, three
InteriorDressings, and the ocean shader's own per-fragment procedural
noise (see the ocean-tiling note in `docs/systems/integration.md`), this
is a legitimately heavy "everything near-max" Forward+ configuration that
had never been checked against real hardware cost — exactly the risk this
doc's own "Frame budget" section above could only ever flag, not verify.

**Fixes applied, in the order `docs/systems/engineering.md`'s own
"practical levers" list already specified** (resolution scale → GI →
fog → shadows, before ever touching draw distance/crowd counts):

- `project.godot`: `scaling_3d/scale` 0.9 → 0.65; `anti_aliasing/quality/msaa_3d`
  2 → 0 (drop explicit MSAA — FSR2 upscaling already active);
  `global_illumination/gi/use_half_resolution` false → true;
  `environment/ssao/quality` and `environment/ssil/quality` 2 → 1;
  `environment/volumetric_fog/use_filter` 1 → 0;
  `lights_and_shadows/*/soft_shadow_filter_quality` 3 → 1;
  `directional_shadow/size` 4096 → 2048.
- `environment/world_environment.tres`: `ssil_enabled` true → **false**
  (redundant with SDFGI, one of the pricier screen-space passes);
  `sdfgi_cascades` 6 → 4; `sdfgi_min_cell_size` 0.2 → 0.4 (halves voxel
  density). **This directly contradicts this doc's own earlier claim**
  ("this package does not touch `sdfgi_enabled`, `sdfgi_cascades`,
  `sdfgi_min_cell_size`, `ssao_*`, or `ssil_enabled` at all") — that claim
  was true for the original package Q pass and is left standing above
  rather than silently edited, but a later pass, responding to a real
  measured problem rather than `art_direction.md` §4's mood-only-changes
  instruction, did touch them. If mood/weather visibly stops tracking
  GI/AO quality as a result, that instruction is the thing to revisit.
- `world/ocean/ocean.gdshader`: the per-fragment procedural detail
  (micro-normal + foam breakup, 4 `fbm()` calls of 4 octaves each) was
  previously computed on *every* fragment regardless of camera distance,
  with only its *contribution* faded out at range — meaning the compute
  cost was paid everywhere even where the result was discarded. Changed to
  an `if (detail_fade > 0.001)` branch so most of a wide god-view's
  visible ocean surface (past the 150m fade distance) skips the noise
  evaluation entirely rather than just hiding its output.

**Honestly still true after these fixes:** none of this was re-measured on
real hardware either — the sandbox this fix was written in still has no
GPU. These are the standard, well-reasoned levers for exactly this
symptom (SDFGI+SSIL+high shadows+redundant AA all at once on a
never-profiled scene), applied in the order this project's own engineering
doc pre-committed to, not a guess — but if it's still slow after this,
the next lever per that same doc is draw distance/crowd counts (fewer/
further-culled villagers, a smaller ocean plane or coarser subdivision),
and the one after that is asking what GPU it's actually running on.

### Round two: confirmed integrated-only GPU (no discrete card) — quality tuning wasn't enough, disabled outright

The report that came back after round one: no measurable change, still
~5-6 fps. Two things turned out to be true at once: (a) the round-one
commit had never actually reached the tester's checkout — `git pull`
failed with a merge conflict on `project.godot`/`environment/
world_environment.tres` (Godot's own editor rewrites small parts of these
on open, e.g. UID cache entries, which collided with the checked-in
changes) — so round one was never actually running; and (b) once that was
untangled, the hardware was confirmed to be **integrated Intel graphics
only, no discrete GPU at all** (a Dell Latitude 5411 in its base
configuration). That second fact means round one's approach — reduce
SDFGI cascades/cell density, lower SSAO/SSIL quality tiers — was always
going to be insufficient on its own: integrated GPUs share system memory
bandwidth and have far fewer compute units than any discrete card, and are
specifically, disproportionately bad at exactly the two techniques this
project leaned on hardest (SDFGI's real-time 3D voxel cone tracing, and
volumetric fog's raymarched froxel grid) — reducing their quality knobs
doesn't change that they're fundamentally the wrong tool for this class of
hardware, only outright disabling them does.

Round two, in `environment/world_environment.tres`: `sdfgi_enabled`,
`volumetric_fog_enabled`, and `ssao_enabled` all set to **false** (`ssil_enabled`
was already false from round one). `ambient_light_source = 2` (sky-driven
ambient) is untouched and still lights every surface without SDFGI's
dynamic bounce contribution; `fog_enabled` (a flat, depth-based color
blend — not raymarched, nowhere near the same cost class as volumetric
fog) stays on for cheap atmosphere. In `project.godot`: shadow quality
filter `1 → 0`, shadow map size `2048 → 1024`, SSAO/SSIL quality knobs now
irrelevant (disabled) but zeroed anyway, resolution scale `0.65 → 0.5`.

**Deliberately not attempted, and why:** switching `renderer/
rendering_method` from `"forward_plus"` to `"mobile"` — Godot's own
built-in low-spec renderer target, which would likely help more than any
individual toggle — was considered and set aside for this round. Custom
shaders in this repo (`world/ocean/ocean.gdshader`'s `hint_screen_texture`/
`hint_depth_texture` reads, in particular) have compatibility surface
between Forward+ and Mobile that this sandbox has no way to verify without
real hardware to actually render on; flipping the renderer method blind
and shipping a possibly-broken shader compile to someone already dealing
with a bad first impression was judged the wrong trade. Flagged here as
the next real lever if disabling SDFGI/volumetric fog still isn't enough,
not silently skipped.

**Still honestly unverified from this end** — there is still no GPU, of
any kind, integrated or discrete, in the sandbox these changes were made
in. Every number above is reasoned from what SDFGI/volumetric fog/shadow
mapping/SSAO are known to cost on integrated graphics in general, not
measured on this specific machine. If this round still isn't enough, the
concrete next steps, in order: confirm this round actually reached the
checkout this time (see the git note above — that failure mode can repeat
on any future pull if local edits to these same two files exist again);
try `renderer/rendering_method="mobile"` despite the shader-compatibility
risk above; reduce villager count / ocean subdivision / island resolution
(the "draw distance and crowd counts" lever round one deferred).

## Property names: verified, not assumed

Godot 4.3's `Environment`/`ProceduralSkyMaterial` classes were not taken on
faith. This pass could not run the editor (no GPU; running
`godot --headless --path . --check-only` is reserved for the coordinating
process's consolidated pass per this package's brief) but *could* run
`strings` against the installed `~/toolchain/godot/godot` 4.3.1 binary —
static inspection, not execution — to confirm exact property/setter names
before using them in code, the same verification method package D used for
`adjustment_color_correction` (see `art_direction.md` §5). Confirmed
present as real bound setters/getters: `ambient_light_energy`,
`background_energy_multiplier` (`set_bg_energy_multiplier`),
`fog_density`, `fog_light_color`, `fog_light_energy`, `tonemap_exposure`,
`tonemap_white`, `volumetric_fog_density`, `volumetric_fog_albedo`,
`adjustment_enabled`, `adjustment_brightness`, `adjustment_contrast`,
`adjustment_saturation`, `adjustment_color_correction`, `glow_intensity`,
`glow_hdr_threshold`, and (on `ProceduralSkyMaterial`) `sky_top_color`,
`sky_horizon_color`, `ground_bottom_color`, `ground_horizon_color`. All of
these are used directly (dot-access) in both scripts.

**Could not confirm:** `adjustment_use_1d_color_correction`. `strings`
against the binary surfaces `use_1d_color_correction` and the
RenderingServer-internal `environment_get_use_1d_color_correction`, but no
`set_use_1d_color_correction`/`is_using_1d_color_correction`/
`adjustment_use_1d_color_correction` string appears anywhere in the binary
— which is inconclusive (this is a stripped release binary with no
embedded doc XML to cross-check against, not proof the property doesn't
exist under that name), but not a confirmation either. Per this package's
brief ("verify the exact property names... before using them"), the
honest response to an inconclusive check is to not assert the name with
confidence: `_apply_lut()` in `naklon_environment_driver.gd` writes it
through the dynamic, string-keyed `Object.set()` rather than direct
dot-access, so a wrong name fails gracefully (an engine warning at worst)
rather than a script parse error, and the whole LUT-grading path is gated
behind `@export var use_lut_grading: bool = false` — implemented, real,
and off by default until someone with actual editor access confirms the
name and flips it on.

## Integration points (exact files)

- `core/naklon.gd` — `Naklon.unit()`, `Naklon.naklon_changed`.
- `systems/weather/weather.gd` — `Weather.current`, `Weather.weather_changed`.
- `environment/world_environment.tres` — read for its baseline values,
  mutated in place at runtime, never rewritten as a file.
- `docs/systems/art_direction.md` §4 — source of the mercy/cruelty target
  numbers (see the "Deviation" section above for the one place this pass
  diverged from its literal formula, and why).
- `shaders/naklon_lut_blend.gd`, `materials/luts/naklon_lut_{mercy,cruelty}_1d.png`
  (package D) — used, optionally, by `NaklonEnvironmentDriver._apply_lut()`.
- `docs/systems/engineering.md` — frame-budget table and practical-levers
  list this doc cross-references above; not edited.
- `docs/systems/weather.md` — states the "no visual consumer yet" gap this
  package's `WeatherEnvironmentDriver` fills for `environment/`. Also
  documents that a Louhi (package N) tier-1 cold-front write into
  `Weather.current` currently survives at most ~1.5s before Weather's own
  simulation stomps it (no override queue exists yet in `weather.gd`).
  `WeatherEnvironmentDriver` renders whatever `Weather.current` says at
  each emit faithfully, Louhi-authored or not — so for that ~1.5s window,
  this package's driver is what would make a Louhi cold-front sign
  actually visible (a real fog/gloom bump), which is a nice side effect of
  this being the first real consumer, not something built specifically for
  N. Worth knowing if N's own follow-up work ever wants to verify its sign
  is visually landing.

## Risk flagged for other packages

- **Package R (`audio/`, MusicDirector) and any future ambience layer:**
  if R's music ducking or an ambience system also wants to react to
  `Weather.current`'s gloom/storm severity, `WeatherEnvironmentDriver`
  already exposes read-only `get_gloom_factor()` / `get_fog_multiplier()`
  hooks (not consumed by anything in this package) so a future consumer
  doesn't have to re-derive the same blend from `Weather.current` fields
  independently and risk the two systems disagreeing about "how bad is it
  right now." Not a hard dependency — R can equally read
  `Weather.current` directly — just flagged as an available shortcut.
- **Whoever assembles `world/god_view.tscn`:** neither driver is wired
  into any scene yet (this package cannot edit `world/god_view.tscn` or
  `project.godot`), exactly the same situation `docs/systems/louhi.md`
  documents for `LouhiDirector`. Both `.tscn` wrappers in `environment/`
  are ready to instance as a child of whatever scene actually renders the
  world; until then this code is real and correct but inert.

## Scoped out

- **True 3D LUT / full cross-channel grading.** Not attempted here either
  — same reasoning as `art_direction.md` §6 (package D): a hand-built
  `Texture3D` can't be verified without editor access in this pass.
- **LUT-driven grading left off by default** pending confirmation of
  `adjustment_use_1d_color_correction` — see "Property names" above.
- **No `DirectionalLight3D` (sun disc) modulation.** This package only
  touches `Environment`-level properties (ambient/background/fog energy),
  not an actual sun light's color/energy/shadow softness, because no
  `DirectionalLight3D` node is owned by this package — `world/god_view.tscn`
  (foundation) and its extending scenes own any Light3D nodes. If a future
  pass wants literal sun-dimming under storms (not just ambient/fog), that
  needs a defensively-optional `NodePath`/group lookup into whichever
  scene owns that light, the same pattern `WeatherEnvironmentDriver` already
  uses to find `NaklonEnvironmentDriver`.
- **No wind-driven cloud animation.** `wind_dir_deg`/`wind_speed` are real,
  live fields in `Weather.current` that nothing here reads — animating a
  moving cloud layer would mean writing a custom sky shader (Godot's
  `ProceduralSkyMaterial` has no built-in cloud layer), which is a
  `shaders/`-territory change (package D), not an `environment/` one.
- **No persistence.** Both drivers re-derive their state from `Naklon`/
  `Weather` on `_ready()`; there is no save/load hook, matching the rest of
  the project's current lack of a save system (see `docs/systems/weather.md`'s
  identical note).
- **No real profiling data.** Cannot exist in this sandbox; see "Frame
  budget" above for the full honest accounting instead.

## Assets used

None new. The optional (currently disabled by default) LUT-grading path in
`NaklonEnvironmentDriver._apply_lut()` reuses two PNGs package D already
created and documented — `materials/luts/naklon_lut_mercy_1d.png` and
`naklon_lut_cruelty_1d.png` (see `docs/systems/art_direction.md` for their
own provenance) — this package did not source, generate, or modify any
texture, audio, or model of its own, so there is nothing new to add to
`CREDITS.md` from this package.
