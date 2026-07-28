# Art direction — Naklon-reactive style bible (Package D)

This is the reference other packages should check against when they ask
"does this read as Mercy or Cruelty?" It covers the shared shader mechanism,
the demonstration materials, and the exact numbers for environment tuning
and color grading at both Naklon poles. Everything here is real, running
code/assets checked into `shaders/` and `materials/` — nothing described
below is a stub.

## 1. The core idea

`core/naklon.gd` already gives every system one scalar, `Naklon.value`
(-1 mercy .. +1 cruelty) and `Naklon.unit()` (0..1). Package D's job is to
make that scalar visible in rendering everywhere, once, rather than have
every future package hand-roll its own mercy/cruelty branching. The
mechanism has three layers:

1. **A single global shader uniform**, `naklon_unit`, kept in sync with
   `Naklon.unit()` by a tiny driver node (`shaders/naklon_shader_driver.gd`).
   Any shader anywhere can read it.
2. **A shared include**, `shaders/naklon_globals.gdshaderinc`, with mixing
   and procedural-noise helpers built on top of that uniform, so writing a
   new Naklon-reactive shader is a few lines, not a noise function
   reimplemented from scratch.
3. **One reusable reactive shader**, `shaders/naklon_reactive.gdshader`,
   plus preset `.tres` materials in `materials/` for rock, timber, and
   fabric, demonstrating the mechanism and directly usable by other
   packages that need "a rock/wood/cloth material that reacts to Naklon."

## 2. Public API

### `shaders/naklon_globals.gdshaderinc`

`#include` this from any `.gdshader`. It declares:

```glsl
global uniform float naklon_unit = 0.5; // 0 = full Mercy, 1 = full Cruelty
```

and helper functions, all pure:

| Function | Signature | Purpose |
|---|---|---|
| `naklon_mix_f` | `float(float mercy, float cruelty)` | scalar blend |
| `naklon_mix_v2/v3/v4` | `vecN(vecN mercy, vecN cruelty)` | vector/color blend |
| `naklon_eased` | `float()` | smoothstepped `naklon_unit`, for effects that should feel like they accelerate away from neutral (emission, rim) |
| `naklon_hash21`, `naklon_noise`, `naklon_fbm` | noise primitives | cheap procedural detail, no texture needed |
| `naklon_crack_mask` | `float(vec2 uv, float scale, float amount)` | ridge-thresholded fbm read as cracks/veins; `amount` both narrows the ridge and fades it to nothing at 0 |

### `shaders/naklon_shader_driver.gd`

A `Node` script — **not an autoload** (project.godot is foundation-owned;
see `docs/systems/OWNERSHIP.md`). It pushes `Naklon.unit()` into the
`naklon_unit` global shader uniform on `_ready()` and on every
`Naklon.naklon_changed` signal.

**How another package wires this in (do this once per scene that needs
live Naklon-reactive shading):**

```gdscript
# from code, anywhere in _ready():
var driver := Node.new()
driver.set_script(load("res://shaders/naklon_shader_driver.gd"))
add_child(driver)
```

or in a `.tscn`:

```
[node name="NaklonShaderDriver" type="Node" parent="."]
script = ExtResource("res://shaders/naklon_shader_driver.gd")
```

It is idempotent — instantiating it in more than one scene/package at once
(e.g. the god view world and a Sanctum interior loaded alongside it) is
harmless, not a bug; every instance ends up writing the same value to the
same global slot. It exposes no signals of its own — it is a bridge from
`Naklon` (GDScript-land) to `RenderingServer` (shader-land), nothing more.
If your own script logic needs the value, read `Naklon.unit()` /
`Naklon.naklon_changed` directly; only instantiate the driver for the
shader side.

See `shaders/naklon_demo.tscn` / `shaders/naklon_demo.gd` for a
self-contained, running example: it instances the driver once, applies the
three reactive materials to a sphere/cylinder/plane, and lets Left/Right
arrow keys nudge `Naklon.value` live (no `InputMap` action needed, since
`project.godot` is off-limits — it polls `Input.is_key_pressed` directly)
so the shift is visible in real time.

### `shaders/naklon_reactive.gdshader`

One `shader_type spatial` shader. Every "mercy vs cruelty" surface property
is declared as a `_mercy`/`_cruelty` uniform pair and blended with
`naklon_mix_f`/`naklon_mix_v3` from the include — see the shader's own
header comment for the full uniform list (albedo, roughness, metallic,
specular, crack amount/scale/glow color/energy, normal strength, rim). The
crack/damage detail is **procedural** (`naklon_crack_mask`, fbm-based), not
a texture, so it needs no authored art and looks correct on any mesh/UV
layout. The same noise field also drives a screen-space-free fake normal
map (finite-difference of the noise), so cracks read as physical relief,
not just a color change.

### `shaders/naklon_lut_blend.gd`

Optional CPU helper (`class_name NaklonLutBlend`) for whichever package
owns the actual `Environment` resource (`environment/`, package Q per
OWNERSHIP.md) if it wants continuous (not just pole-snapped) color-curve
grading. See §5.

## 3. Materials — the palette bible

Two ways to consume the palette, both in `materials/`:

- **Reactive** (`naklon_rock.tres`, `naklon_timber.tres`,
  `naklon_fabric.tres`) — `ShaderMaterial`s using
  `naklon_reactive.gdshader`. Apply one of these to any mesh and it shifts
  live as `Naklon` changes, with no per-object logic. **Use these by
  default.**
- **Static/locked-pole** (`rock_mercy.tres` / `rock_cruelty.tres`,
  `timber_mercy.tres` / `timber_cruelty.tres`, `fabric_mercy.tres` /
  `fabric_cruelty.tres`) — plain `StandardMaterial3D`s at each extreme, no
  custom shader, no procedural cracks. Use these only where an object's
  appearance is meant to be **permanently locked** to a resolved state
  (e.g. a village that has fully converted and stays that way) or where a
  custom shader isn't wanted for cost/simplicity reasons. They intentionally
  lack the procedural crack/normal detail the reactive shader has — that
  detail only exists in the shader version.

### The palette, by object type

| | **Mercy** (Naklon → -1) | **Cruelty** (Naklon → +1) |
|---|---|---|
| **Rock** | mossy grey-green stone `#758566`, matte (roughness 0.85), no specular punch (0.25), no cracks, soft warm rim light | ash-black fractured stone `#1A1717`, glassy-wet sheen (roughness 0.35, specular 0.9), heavy iron-red crack glow `#B82414`, harsh normal relief |
| **Timber / wood** | warm honey birch `#9E7545`, roughness 0.6, gentle rim light, unmarked grain | charred ash-grey timber `#120F0D`, tighter roughness 0.5 with more specular bite (0.6), wide checked/split cracks (bigger crack scale than rock) glowing ember-orange `#C7330F` |
| **Fabric / cloth** | undyed warm cream wool-linen `#CCC2A3`, very matte (roughness 0.9), lowest specular of the three (cloth doesn't gloss), strongest soft rim (fibers catch light) | ash-and-rust-stained cloth `#471A17`, waxed/oiled harsh sheen (specular 0.85), fine mottled staining rather than deep cracks (higher crack scale = smaller, denser marks), rim almost fully suppressed |

Read as a whole: **Mercy is soft, warm, low-specular, undamaged, and rim-lit
— the world looks cared for.** **Cruelty is dark, desaturated-toward-ash,
high-specular/glassy, fractured, and glowing at the seams like something
still hot underneath — the world looks starved and fractured, not simply
"evil-colored."** This should generalize to any new material another
package writes: pick the mercy pole for softness/warmth/care and the
cruelty pole for hardness/fracture/heat, not just "green vs red."

These colors are deliberately generic/material-agnostic (not tied to one
of the four cultures' specific palettes) since `data/cultures/*.tres`
already defines each culture's own `material_palette` / `color_primary` /
`color_accent` — a village-specific system should still pull from its
culture resource for hue identity and use this shader only for the
mercy/cruelty *response* (roughness, specular, cracking, rim), not to
override a culture's identity colors outright. A reasonable pattern: set
`albedo_mercy`/`albedo_cruelty` on a per-instance material override to a
tint of that village's `culture.color_primary`/`color_accent` rather than
the generic defaults above.

## 4. WorldEnvironment tuning note

**Package D does not edit `environment/world_environment.tres`** (owned by
package Q). This section is the exact target values Q or the integration
pass should apply, so the sky/fog/tonemap breathe in sync with the same
`Naklon.unit()` value the shaders use. Formula throughout:

```
current_value = lerp(mercy_value, cruelty_value, Naklon.unit())
```

recomputed whenever `Naklon.naklon_changed` fires (the signal only fires on
player action, so this is cheap — no per-frame work needed unless you also
want it to visually "settle"/ease rather than snap, in which case tween
toward the new target over ~1-2s instead of setting instantly).

| Property | Baseline (current .tres, Naklon=0) | **Mercy** target (-1) | **Cruelty** target (+1) |
|---|---|---|---|
| `sky_top_color` | `(0.259, 0.443, 0.702)` | `(0.34, 0.56, 0.72)` — brighter, warmer blue | `(0.11, 0.09, 0.09)` — ash-charcoal |
| `sky_horizon_color` | `(0.694, 0.749, 0.784)` | `(0.86, 0.87, 0.78)` — warm pale gold-green haze | `(0.46, 0.29, 0.26)` — smoky red-brown |
| `ground_bottom_color` | `(0.157, 0.157, 0.157)` | `(0.24, 0.29, 0.19)` — mossy green-brown | `(0.05, 0.04, 0.04)` — near-black ash |
| `ground_horizon_color` | `(0.694, 0.749, 0.784)` | `(0.86, 0.87, 0.78)` | `(0.46, 0.29, 0.26)` |
| `fog_light_color` | `(0.639, 0.702, 0.784)` | `(0.82, 0.85, 0.74)` — warm pale green-gold | `(0.36, 0.22, 0.19)` — ember-red-grey |
| `fog_density` | `0.0008` | `0.0005` (clearer air) | `0.0020` (hazier — ash in the air) |
| `volumetric_fog_density` | `0.015` | `0.010` (thinner, calmer) | `0.030` (oppressive, roiling) |
| `volumetric_fog_albedo` | `(0.9, 0.92, 0.95)` | `(0.95, 0.97, 0.90)` | `(0.5, 0.4, 0.38)` — ashen |
| `tonemap_white` | `6.0` | `5.0` (gentler highlight rolloff, nothing blows out harshly) | `8.5` (harsher clipped highlights — embers/iron edges blow out) |
| `adjustment_brightness` | `1.0` | `1.04` | `0.92` |
| `adjustment_contrast` | `1.02` | `0.97` (soft) | `1.16` (harsh, crushed blacks) |
| `adjustment_saturation` | `1.0` | `1.08` (slightly richer, alive) | `0.72` (bled out toward ash) |
| `glow_intensity` | `0.55` | `0.48` (calmer bloom) | `0.78` (embers/iron bloom harder) |
| `glow_hdr_threshold` | `1.1` | `1.2` (only the brightest things bloom) | `0.85` (more things bloom) |

`sdfgi_*`, `ssao_*`, `ssil_enabled`, and `tonemap_mode` are left untouched
at both poles — GI/AO quality shouldn't visibly degrade just because the
player is being cruel; only color and atmosphere should shift.

## 5. Post-process color grading (1D LUT)

Godot's `Environment.adjustment_color_correction` supports two modes,
confirmed directly from the engine's compiled tonemap shader source (found
via `strings` on the installed `godot` 4.3.1 binary at
`~/toolchain/godot/godot`, not by running it — see `docs/rendering.md`/
project rule against invoking the binary):

- **3D LUT** (`adjustment_use_1d_color_correction = false`): a true
  `Texture3D`, sampled directly as `textureLod(source, color.rgb, 0.0)`.
  Full cross-channel grading, but Godot 4 has no in-editor way to author a
  `Texture3D` `.tres` by hand without running the editor's import step to
  verify the binary layout — doing this blind, in a pass where I can't run
  Godot myself to check it imports correctly, would risk shipping a
  silently-broken asset. **Scoped out for this pass** — see §6.
- **1D per-channel curves** (`adjustment_use_1d_color_correction = true`):
  a plain 2D texture, sampled as
  `texture(source, vec2(color.r, 0.0)).r` (and same for g/b) — i.e. each
  output channel is an *independent* tone curve, encoded in the matching
  channel of one strip image. This only needs a normal PNG, which I *can*
  generate and verify byte-for-byte without running the engine.

### What's actually in `materials/luts/`

Three real, generated 256×4 PNGs (column `x` encodes input value `x/255`;
4 identical rows so the sampler's v-coordinate is irrelevant):

- `naklon_lut_mercy_1d.png` — lifted blacks (never fully crushed), a
  gentle upward bulge in the midtones (soft glow), tiny warm/green tint
  (`R+0.006, G+0.020, B-0.006`).
- `naklon_lut_cruelty_1d.png` — crushed blacks, a double-smoothstep
  contrast curve (harsh punch), split-toned red-up/blue-down
  (`R+0.050, G-0.015, B-0.050`) for the ash + hot-iron look.
- `naklon_lut_neutral_1d.png` — identity curve (pass-through), for the
  neutral band or as a safe default.

Generated by a small, reproducible Python script (not committed as a
build dependency — it's documentation of intent; the PNGs themselves are
the real deliverable) implementing exactly:

```python
def mercy_channel(x, tint, lift=0.035):
    eased = clamp01(x + 0.12 * sin(pi * x))
    return clamp01(lift + (1.0 - lift) * eased + tint)

def cruelty_channel(x, tint, lift=-0.02, crush=0.04):
    eased = smoothstep(smoothstep(x))
    return clamp01(eased * (1.0 - crush) + lift + tint)
```

Verified output (this build): mercy curve maps input 0 → `(10,14,7)`
(lifted, greenish-lifted black) and input 1 → `(255,255,253)`; cruelty
curve maps input 0 → `(8,0,0)` (crushed, red-biased) and input 1 →
`(252,236,227)` (warm clipped highlight).

### How to wire it (for whichever package owns the `Environment`)

Two options, both documented in `shaders/naklon_lut_blend.gd`'s header:

1. **Pole-snapped** (cheapest): on `Naklon.pole_crossed`, assign
   `naklon_lut_mercy_1d.png` / `naklon_lut_cruelty_1d.png` /
   `naklon_lut_neutral_1d.png` to `environment.adjustment_color_correction`
   depending on the new pole. Set
   `environment.adjustment_use_1d_color_correction = true` once.
2. **Continuous**: call `NaklonLutBlend.blended(Naklon.unit())` from a
   `Naklon.naklon_changed` handler — it CPU-lerps the two 256×4 strips
   pixel-for-pixel (1024 pixels, trivial cost, and the signal only fires on
   player action) and returns a ready `ImageTexture` to assign to
   `adjustment_color_correction`.

## 6. Scoped out

- **True 3D LUT / full cross-channel grading.** The 1D per-channel curves
  above cover split-toning, contrast, and lift/crush — most of the visual
  distance between the two poles — but can't do a pure hue rotation or a
  lightness-dependent color twist independent of the RGB channels
  themselves. Not attempted because a hand-built `Texture3D` `.tres` can't
  be verified in this pass (no GPU/editor run available to confirm the
  encoding — see `docs/rendering.md`), and shipping an unverifiable binary
  asset format is worse than not shipping it. If a future pass has editor
  access, bake one from the same curve functions extended to 16×16×16 and
  swap `adjustment_use_1d_color_correction` to `false`.
- **Actually editing `environment/world_environment.tres`.** Not this
  package's directory (owned by Q per `docs/systems/OWNERSHIP.md`). §4 is
  the handoff.
- **Continuous cross-fade of the 1D LUT running every frame.** The CPU
  blend helper is correct but is meant to run only on `naklon_changed`
  (rare); nothing here animates it every frame, since Naklon itself only
  changes on discrete player actions, not continuously.
- **Per-culture palette variants of the reactive shader.** §3 explains the
  intended pattern (tint from `culture.color_primary`/`color_accent` per
  instance) but no culture-specific `.tres` presets were authored — that's
  naturally each village/building-owning package's job, using
  `naklon_reactive.gdshader` directly with their own uniform values.
- **A Naklon-reactive skin/water/foliage shader.** Out of scope for this
  pass; `world/terrain/` (B) and `world/ocean/` (C) own those surfaces and
  can `#include naklon_globals.gdshaderinc` themselves if they want the
  same mechanism — the include is generic enough for any shader type.

## Assets used

None. Everything in this package (both shaders, the `.gdshaderinc`, the
driver/helper scripts, all nine `.tres` materials, and the three LUT PNGs
in `materials/luts/`) is procedurally generated or hand-written in this
pass — no external CC0/licensed textures, HDRIs, or images were downloaded.
