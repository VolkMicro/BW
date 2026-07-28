# Package C — Ocean, rivers, coastline

## What's here

`world/ocean/` (owned by this package):

| File | What it is |
|---|---|
| `gerstner_common.gdshaderinc` | Shared pure-function shader math: hash/value-noise/fbm, and `linearize_depth()` (DEPTH_TEXTURE → linear view-space depth). No uniforms declared here — see "Why the wave sum isn't in the shared include" below. |
| `ocean.gdshader` | Open-ocean surface material: 6-wave Gerstner sum in `vertex()`, depth-fade shoreline/object foam + wave-crest whitecaps, depth-tinted color with a cheap screen-space refraction blend, fresnel-weighted reflection response. |
| `river.gdshader` | Narrow-water variant of the same shader: shorter/steeper/faster waves, a flow-direction UV scroll, bank-edge foam (in addition to the same depth-fade foam). |
| `gerstner_wave_set.gd` (`class_name GerstnerWaveSet`) | A `Resource` holding up to 6 wave definitions (direction/wavelength/steepness/amplitude/speed). Packs itself into the two flat arrays the shaders expect, **and** exposes a CPU-side `sample()` that reproduces the exact same math for gameplay height/normal queries. Ships `default_ocean()` and `default_river(flow_direction)` factory presets. |
| `ocean_surface.gd` (`class_name OceanSurface`, extends `MeshInstance3D`) | Builds a subdivided `PlaneMesh` sized for an island scene, attaches the ocean shader, and exposes `get_height(world_pos)` / `sample_surface(world_pos)` for buoyancy-style queries. |
| `river_surface.gd` (`class_name RiverSurface`, extends `MeshInstance3D`) | Takes an `Array`/`PackedVector3Array` of control points, Catmull-Rom-smooths them, and builds a tapering ribbon mesh (via `SurfaceTool`) with the river shader applied. Exposes `rebuild(new_points)` and `get_height(world_pos)`. |
| `ocean_demo.tscn` | Standalone demo scene (WorldEnvironment + Sun + Camera + a placeholder island/reef prop built directly in this scene + one `OceanSurface` + one `RiverSurface` carved as an inlet). Does **not** touch `world/god_view.tscn` or package B's `world/terrain/`. |

## How the wave math works

Both shaders sum up to 6 Gerstner waves directly on the vertex, following
the standard Gerstner-wave formulation (Fernando, *GPU Gems* ch.1):

```
for each wave i:
  k_i      = 2π / wavelength_i
  f_i      = k_i · dot(direction_i, position.xz) + time · speed_i
  Q_i      = steepness_i / (k_i · amplitude_i · active_wave_count)   // auto-normalized so waves don't self-intersect
  displacement.x += Q_i · amplitude_i · direction_i.x · cos(f_i)
  displacement.z += Q_i · amplitude_i · direction_i.y · cos(f_i)
  displacement.y += amplitude_i · sin(f_i)
  normal          -= (direction_i.x, Q_i, direction_i.y)-weighted analytic partials  // see code
```

`GerstnerWaveSet.sample()` (GDScript) implements the *identical* formula so
that gameplay code — the Hand dropping something in the sea, a boat, a
corpse washing ashore — can query wave height/normal at a world XZ without
a GPU readback. **Caveat inherited from the standard technique**: both the
shader and the CPU sampler evaluate the wave field at the *undisplaced* XZ
position rather than inverting the horizontal Gerstner displacement to
find which vertex ends up above a given target — the universal
simplification for buoyancy-style queries. It's visually and functionally
correct at the steepness values shipped here; it would start to look wrong
if someone cranks `steepness` toward 1.0 with large amplitude (crests
would begin to fold over, and CPU queries would sample slightly the wrong
column). Documented rather than silently wrong.

### Why the wave-sum loop isn't in the shared `.gdshaderinc`

`gerstner_common.gdshaderinc` intentionally contains **only** parameterless
helper functions (noise, depth linearization) — no uniform declarations,
no functions taking whole arrays as parameters. `ocean.gdshader` and
`river.gdshader` each declare their own `wave_dir_len_steep[6]` /
`wave_amp_speed[6]` uniforms and their own local
`calculate_gerstner_ocean()` / `calculate_gerstner_river()` function that
reads those uniforms directly (globals-in-scope, not function parameters).
This duplicates ~35 lines of wave-summation code between the two files,
traded deliberately for **not** relying on GLSL array-typed function
parameters inside a Godot `#include`, which is the one part of this
setup with the least precedent to verify by hand-reading in a no-GPU
sandbox. The genuinely shared, harder-to-get-right math (hash/noise/fbm,
depth reconstruction) — which only ever takes scalars/vec2/sampler2D/mat4
as parameters, all unambiguous — stays in the include.

## Exact shader uniforms (for package Q — rendering, and D — art direction)

### `ocean.gdshader`

| Group | Uniform | Type | Default | Meaning |
|---|---|---|---|---|
| Waves | `wave_dir_len_steep[6]` | `vec4[6]` | *(set by script)* | `.xy` = wave direction, `.z` = wavelength (m), `.w` = steepness (0..1). Amplitude 0 in the paired entry = inert/unused slot. |
| Waves | `wave_amp_speed[6]` | `vec2[6]` | *(set by script)* | `.x` = amplitude (m), `.y` = phase speed. |
| Waves | `crest_reference_height` | `float` | `1.6` | Normalizes the whitecap crest mask only — not physical. |
| Surface_Color | `color_shallow` | `vec4` (color) | `(0.263, 0.616, 0.576)` | Shallow/near-shore tint. |
| Surface_Color | `color_deep` | `vec4` (color) | `(0.016, 0.078, 0.153)` | Open-water tint. |
| Surface_Color | `depth_fade_distance` | `float` | `6.0` | Meters of scene-depth-below-surface over which shallow→deep fully blends. |
| Surface_Color | `refraction_strength` | `float` | `0.04` | How much the fragment normal bends the SCREEN_TEXTURE sample. |
| Foam | `foam_color` | `vec4` (color) | near-white | Foam tint. |
| Foam | `foam_distance` | `float` | `0.65` | Meters of depth-diff within which shoreline/object foam appears. |
| Foam | `foam_noise_scale` | `float` | `0.4` | World-space frequency of the foam breakup noise. |
| Foam | `foam_crest_threshold` / `foam_crest_softness` | `float` | `0.6` / `0.35` | Where whitecaps start appearing on tall crests, and the softness of that edge. |
| Micro_Detail | `micro_normal_strength` / `micro_normal_scale` | `float` | `0.18` / `1.6` | Procedural fbm ripple-normal detail layered over the analytic Gerstner normal (no texture). |
| Reflection | `roughness_base` | `float` (0..1) | `0.06` | Base roughness away from foam. |
| Reflection | `fresnel_power` | `float` | `5.0` | Grazing-angle falloff exponent. |
| Reflection | `fresnel_tint` | `vec3` (color) | pale blue-grey | Color blended in at grazing angles (cheap stand-in for a real reflected-sky sample). |
| — | `depth_texture` | `sampler2D` (`hint_depth_texture`) | engine-provided | Scene depth for the foam/color-fade pass. |
| — | `screen_texture` | `sampler2D` (`hint_screen_texture`) | engine-provided | Opaque-pass color for the refraction blend. |

### `river.gdshader`

Same `Surface_Color` / `Foam` / `Micro_Detail` / `Reflection` groups as
above (different tuned defaults — narrower `depth_fade_distance` (2.0),
tighter `foam_distance` (0.35)), plus:

| Group | Uniform | Type | Default | Meaning |
|---|---|---|---|---|
| Flow | `flow_direction` | `vec2` | `(0, 1)` | Set from the spline's start→end direction by `RiverSurface`. |
| Flow | `flow_time` | `float` | `0.0` | Driven every frame by `RiverSurface._process()`; feeds the UV scroll. |
| Flow | `flow_uv_scale` | `float` | `0.6` | Tiling of the flow-scrolled noise against the ribbon's length-wise UV. |
| Foam | `bank_foam_width` | `float` | `0.12` | Fraction of channel width (each bank) that always foams, independent of depth-fade — river/inlet edges are shallow by construction. |

Both shaders' `TIME`-driven animation and all of the above are safe to
tune live in the inspector on the generated `ShaderMaterial` — nothing
requires a script edit to reskin for art direction (package D) or to pull
a performance lever (package Q): dropping `micro_normal_scale`'s fbm
octave count (currently a hardcoded `4` at each `fbm(...)` call site) is
the next lever if the per-pixel cost needs to come down further.

## Integration with the foundation

- **`core/` / `GameState` / `Naklon`**: not touched. Ocean/river surfaces
  are pure presentation + a CPU height-query API; they don't currently
  react to `Naklon` (e.g., a stormier sea under Cruelty) or register
  anything in `GameState`. That hook is a natural, cheap follow-up
  (`OceanSurface` could scale `crest_reference_height`/amplitude off
  `Naklon.unit()`) — flagged here as scoped out, not silently skipped.
- **`environment/world_environment.tres`**: read-only reference, used by
  `ocean_demo.tscn` via `ExtResource`, never modified.
- **Package B (`world/terrain/`)**: no direct coupling. A terrain script
  can build a `RiverSurface` (`RiverSurface.new()`, set `control_points`,
  add as a child) anywhere in *its own* scene and get a working spline
  river without editing anything in `world/ocean/`; this package only
  demonstrates that pattern in its own `ocean_demo.tscn`.
- **Buoyancy consumers** (package E — Hand, package K — Avatar, a future
  boat/relic-in-the-sea mechanic): call
  `OceanSurface.get_height(world_pos)` / `.sample_surface(world_pos)` or
  the equivalent on `RiverSurface`. No signals are emitted (polling is
  cheap and these are per-frame physics-adjacent queries, not events).

## Scoped out

- **No LOD/chunking for the open-ocean plane.** A single `PlaneMesh`
  covers the whole visible sea (default 700×700 m, 140 subdivisions ≈
  19.9k tris). Fine for a demo/vertical-slice camera distance; a
  colossal-scale open world would want a distance-based quadtree or
  clipmap so far-field ocean uses far fewer vertices. Flagged in
  `docs/systems/engineering.md`'s frame-budget terms as the next lever if
  the ~1.5 ms ocean line item is measured over budget on real hardware.
- **No real-time reflections beyond the engine's own SDFGI/reflection
  probes + the manual fresnel tint.** Screen-space or ray-traced water
  reflections aren't available on this renderer/hardware combination (see
  `docs/rendering.md`); the fresnel-tint mix is a deliberate cheap
  stand-in, not a placeholder for something accidentally left unwired.
- **No buoyancy/physics body** — `get_height()`/`sample_surface()` are
  read-only queries; wiring an actual `RigidBody3D` boat or floating prop
  to them is left to whichever package owns that object.
- **No `Naklon`-reactive sea state** (storms under Cruelty, glassy calm
  under Mercy) — see "Integration" above. The `GerstnerWaveSet` API is
  shaped to make this a small follow-up (swap/interpolate two wave sets
  based on `Naklon.unit()`), not a redesign.
- **River mesh has no physical collision** — it's a visual surface only;
  a river that needs to stop the Avatar or float debris needs a
  `CollisionShape3D` added by whichever package needs that (out of this
  package's scope, but `RiverSurface`'s generated mesh is a normal
  `ArrayMesh`, so `create_trimesh_shape()` on it works if needed).

## Assets used

**None — fully procedural.** Foam breakup, micro-ripple normal detail, and
all wave motion are generated in-shader (value noise / fbm) or on the GPU
via the Gerstner vertex displacement; no textures, HDRIs, or models were
downloaded for this package. This was a deliberate choice, not an
oversight: a real foam/normal texture would look better at extreme
close-range, but procedural noise (a) needs no import pipeline or license
tracking, (b) tiles infinitely at any camera distance without a visible
seam, and (c) matches this pass's stated preference for "procedural/
code-driven content over hand-authored art you don't have time to make
well." If a future pass wants a genuine foam texture, ambientcg.com has
several CC0 water-foam/normal sets that would drop into the `foam_color`/
`micro_normal_*` sampling points with minimal shader changes.
