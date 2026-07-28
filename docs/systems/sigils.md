# Package F — Sigil recognition + rite VFX

Owns `systems/sigils/`. Depends only on `core/` (Naklon/GameState are not
touched directly by this pass, but `Voices.react` — `systems/voices/` — is
called on both a successful and a rejected cast) and the input action
`hand_sigil_draw` already registered in `project.godot`.

## Files

| File | What it is |
|---|---|
| `systems/sigils/unistroke_recognizer.gd` | `class_name UnistrokeRecognizer` — a from-scratch reimplementation of the **$1 Unistroke Recognizer** (Wobbrock, Wilson & Li, UIST 2007), a published academic algorithm description, not any game's proprietary code. |
| `systems/sigils/sigil_templates.gd` | `class_name SigilTemplates` — the nine original rite gesture shapes, generated parametrically (arcs/spirals/waves as point-lists, straight edges as corner vertices). |
| `systems/sigils/sigil_caster.gd` | `class_name SigilCaster extends Node3D` — the component that records a stroke, runs it through the recognizer, and emits `rite_cast`. |
| `systems/sigils/sigil_caster.tscn` | A one-node convenience wrapper (`Node3D` + the script above) so another package can `instance()` it without writing the wiring by hand. |
| `systems/sigils/rite_vfx.gd` | `class_name RiteVFX` — per-rite `GPUParticles3D` presets, built procedurally at runtime (no texture/model assets). |

## The recognizer (`unistroke_recognizer.gd`)

Implements the $1 algorithm's published pipeline exactly, as five static,
independently callable steps plus the golden-section-search comparator:

1. **Resample** the raw stroke to 64 equidistant points along its path
   length (`RESAMPLE_POINTS`).
2. **Indicative angle**: find the angle from the centroid to the first
   point, then rotate the whole stroke so that angle is zero.
3. **Scale to a reference square** (`SQUARE_SIZE = 250`), non-uniformly
   (the paper's own accepted "distortion" — this is what makes the
   recognizer indifferent to whether a gesture was drawn tall, wide, or
   tiny).
4. **Translate to origin** (center the centroid at `(0,0)`).
5. **Compare**: for each loaded template (normalized through the same four
   steps once, at load time), run a **golden-section search** over
   rotation in `[-45°, +45°]` (2° precision) to find the alignment that
   minimizes mean point-to-point distance (`distance_at_best_angle` /
   `path_distance`), and keep the template with the lowest distance.
6. **Score**: `1.0 - best_distance / (0.5 * diagonal_of_reference_square)`,
   clamped to `>= 0`. `1.0` is a perfect match; this is the same
   normalized-score formula the paper uses.

`UnistrokeRecognizer` is a plain `RefCounted` — no autoload, no scene
dependency — so it can be unit-tested in isolation (flagged in
`docs/systems/engineering.md`'s GUT-coverage list as one of the modules
most worth covering next). Its public surface:

```gdscript
var r := UnistrokeRecognizer.new(SigilTemplates.get_raw_templates())
var result := r.recognize(stroke_points) # Array[Vector2] (any density, any scale)
# result == {"rite_id": StringName, "score": float 0..1}
```

Individual pipeline steps (`resample`, `indicative_angle`, `rotate_by`,
`bounding_box`, `scale_to_square`, `translate_to_origin`, `path_distance`,
`distance_at_best_angle`, ...) are all `static func`s on the class, callable
directly for testing or reuse.

## The nine rite sigils (`sigil_templates.gd`)

Every shape is an original invention for this project — none are a real
runic alphabet (no Elder Futhark, no other real script), no real sacred
symbol, and none resemble a swastika-family motif in any rotation (checked
by eye against all four rotational quadrants for each shape below; none of
them are a 4-armed bent cross of any kind — they're waves, arches,
crescents, zigzags, spirals, chevrons, and a plain circle).

| Rite id | Shape description |
|---|---|
| `&"rain_call"` (Water/Rain-call) | A rippling sine wave (~1.75 gentle cycles) with a short tail dropping straight down at the end, like a raindrop falling off the last ripple. |
| `&"path_gate"` (Path-Gate) | A doorway arch drawn in one stroke: straight post up, a rounded lintel arcing over the top, straight post back down. |
| `&"harvest"` (Harvest) | A sickle: a wide, open crescent arc with a short straight handle flaring off one tip. |
| `&"lumber"` (Lumber) | A tight, even ripsaw zigzag — four sharp, evenly-spaced peaks. |
| `&"repair"` (Repair) | An inward spiral: starts wide (radius ~82) and winds down to a tight center (radius ~6) over 2.25 turns, like binding a wound closed. |
| `&"ward"` (Ward) | A plain closed protective circle with a short straight tail stub where the stroke enters it. |
| `&"fire_arrow"` (Fire-Arrow) | A diagonal shaft rising left-to-right with a small chevron notch doubled back at the tip, like a nocked arrow's fletching. |
| `&"lightning"` (Lightning) | A jagged, asymmetric bolt: three sharp long-short-long angles — deliberately fewer, larger, more irregular segments than Lumber's saw teeth so the two don't get confused. |
| `&"storm"` (Storm) | A wide, outward-growing gyre — opposite winding direction and more turns (3) than Repair's inward spiral, so the two read as opposites, not near-duplicates. |

`SigilTemplates.get_raw_templates() -> Dictionary` returns `StringName ->
Array[Vector2]` in an arbitrary local coordinate space (roughly
`[-100, 100]`, y-down to match screen space); `get_descriptions() ->
Dictionary` returns the same table as human-readable strings, the single
source of truth also used to write the table above (so if a future pass
tunes a shape, the doc and the data can't drift apart silently).

## The caster component (`sigil_caster.gd`)

`class_name SigilCaster extends Node3D`. Meant to be attached as a child of
(or otherwise kept near) the Hand once package E's `actors/hand/` lands;
today it works completely standalone (no dependency on `actors/hand/`
existing) via its mouse fallback, so it's testable end-to-end in this pass.

**Signals**

```gdscript
signal rite_cast(rite_id: StringName, confidence: float)
signal stroke_started()
signal stroke_finished(matched: bool, rite_id: StringName, confidence: float)
```

`rite_cast` only fires on a confident match. `stroke_finished` fires on
*every* completed stroke attempt (matched or not) so a debug HUD or the Two
Voices can react to a miss too — this file already calls
`Voices.react(&"sigil_recognized", {"rite_id": ..., "confidence": ...})`
and `Voices.react(&"sigil_rejected", {"best_guess": ..., "confidence": ...})`
so package M has both trigger names ready to write lines against.

**Two input sources, explicitly documented (per the brief's requirement to
document which is used):**

1. **Mouse-drag (primary, working today).** Holding the existing
   `hand_sigil_draw` input action — already mapped in `project.godot` to
   the right mouse button — and dragging records raw *viewport-space mouse
   positions* directly as the stroke's points via `_unhandled_input`.
2. **Hand-tip-driven (for package E to wire in later).** Call
   `begin_stroke()`, then once per frame while the Hand's own draw-input is
   held, `add_point_3d(hand_tip_world_position, camera)`; call
   `end_stroke()` when released. `add_point_3d` unprojects the 3D point
   through the given (or current) `Camera3D` into the same viewport-space
   the mouse path uses, so **both sources feed one identical 2D stroke
   buffer** — the recognizer never sees anything but flat 2D points,
   regardless of where they came from.

**Forgiving-by-design ("распознавание снисходительное и волшебное"):**
`score_threshold` defaults to `0.75` on the $1 recognizer's 0..1 normalized
score — well below a strict match — and is `@export`ed so a designer can
tune it per-difficulty without touching code. `min_points_required` (6) and
`min_stroke_span_px` (40px) filter out accidental taps/jitter without
otherwise penalizing sloppy-but-clear gestures.

**Bonus polish (in-scope, small, still just this package):** an optional
`Line2D`-under-`CanvasLayer` ink trail (`show_trail`, on by default) draws
the stroke as it's made and fades it out over `trail_fade_time` seconds
after release, so casting a sigil reads as "drawing light in the air"
rather than invisible input capture.

**Public API summary**

```gdscript
caster.begin_stroke()
caster.add_point(viewport_point: Vector2)          # mouse/UI path
caster.add_point_3d(world_pos: Vector3, camera: Camera3D = null) # Hand path
caster.end_stroke()                                 # recognizes + emits signals
```

## Rite VFX (`rite_vfx.gd`)

`class_name RiteVFX`, static-only (no instance state). One call gets any
other package a real, working one-shot particle burst:

```gdscript
sigil_caster.rite_cast.connect(func(rite_id, confidence):
    RiteVFX.spawn(rite_id, cast_world_position, some_parent_node)
)
```

`spawn(rite_id, world_position, parent) -> GPUParticles3D` builds a real
`GPUParticles3D` with a `ParticleProcessMaterial` configured in code
(direction, spread, velocity range, gravity, scale range, color, spherical
emission volume) and one of three built-in primitive meshes
(`SphereMesh`/`BoxMesh`/`TorusMesh`) carrying an unshaded, emissive
`StandardMaterial3D` — no textures or imported models, matching the "prefer
procedural over hand-authored art" guidance. It's added under `parent`,
positioned, set to `one_shot = true`, and a `SceneTreeTimer` frees it once
its burst has finished. `RiteVFX.color_for(rite_id) -> Color` exposes the
same per-rite color so a UI cursor glow or subtitle color can match a rite
without spawning particles.

Presets (color / motion feel, one line each): `rain_call` — blue droplets
falling with added downward gravity; `path_gate` — teal-green shimmering
torus, gentle rise; `harvest` — warm gold drift upward; `lumber` — brown
chips kicked out fast with strong gravity; `repair` — soft gold sparkle,
slow and tight; `ward` — pale cyan torus, barely moving (a held ring);
`fire_arrow` — orange-red burst, high velocity, upward kick; `lightning`
— bright white-blue shards, very fast, very short-lived; `storm` — grey-blue
spread, wide angle, long-lived swirl.

## Scoped out

- **No integration with `actors/hand/`** — that package (E) doesn't exist
  yet in this pass. `SigilCaster` is written so it works standalone via
  its mouse fallback today, and exposes `add_point_3d` specifically so
  package E can wire the Hand's fingertip into it later without any change
  to this file. This is a real, working end-to-end path today (mouse), not
  a stub waiting on another package.
- **No $N multi-stroke recognition** — the brief asked for unistroke
  gestures; every rite here is drawable without lifting the input. (Note
  `fire_arrow`'s chevron and `ward`'s tail-then-loop are deliberately built
  as a single continuous path for exactly this reason.)
- **No Protractor/$P speed optimization** — the paper's own follow-up
  algorithms trade some flexibility for raw speed; at 9 templates and one
  recognition per stroke-release (not per-frame), golden-section search
  against the plain $1 templates is already well under a frame's budget,
  so there was no reason to add that complexity in this pass.
- **No hand-authored `.tscn` VFX file per rite.** `RiteVFX.spawn()` builds
  the same real `GPUParticles3D` + `ParticleProcessMaterial` graph a
  hand-authored scene would contain, but does it in code — this was a
  deliberate choice over nine separate `.tscn` files, since this sandbox
  has no way to open the editor and visually confirm a hand-typed
  `ParticleProcessMaterial` resource block parses and looks right; a typo
  in a raw `.tres`/`.tscn` resource block fails silently until someone
  loads it. The code path is exercised the same way either way and is
  easier to verify by re-reading.
- **No gameplay effect wiring** (devotion cost, cooldown, what a `rain_call`
  rite actually *does* to weather/villages) — this package's job is
  "recognize the gesture and say which rite it was," not simulate rite
  outcomes; that belongs to whichever system owns weather/economy/faith
  effects and should listen for `rite_cast`.
- **No on-screen sigil reference/tutorial UI** (e.g. a scroll showing the
  player what each shape looks like) — that's `campaign/` (scrolls) or
  `ui/` territory per `docs/systems/OWNERSHIP.md`, not `systems/sigils/`.

### Assets used

None. Every visual in this pass (`rite_vfx.gd`'s particle presets) is
built procedurally at runtime from Godot's built-in primitive meshes
(`SphereMesh`, `BoxMesh`, `TorusMesh`) and code-configured materials — no
textures, models, or audio were downloaded, so there is nothing to add to
`CREDITS.md` from this package.
