# Package B — Islands, terrain, erosion-look, biomes

## What this is

A real, procedural island terrain system: a layered-noise heightmap, baked
into an `ArrayMesh` for rendering and a matching `HeightMapShape3D` for
collision, textured with a triplanar-blended PBR shader (grass / rock /
sand by slope + height), whose look shifts with `Naklon.unit()`. Nothing
here is a stub — `island_demo.tscn` is a real, standalone scene you can
open and run today (`godot --path . world/terrain/island_demo.tscn`) that
shows an actual generated island next to a sea plane, lit by the shared
`environment/world_environment.tres`.

## Files

| File | What it is |
|---|---|
| `world/terrain/island_generator.gd` | `class_name IslandGenerator extends Resource`. The reusable "island shape" — noise layers, heightmap sampling, mesh + collision-shape builders. |
| `world/terrain/island_terrain.gd` | `class_name IslandTerrain extends Node3D`. Drop-in scene node: owns an `IslandGenerator`, builds/attaches the `MeshInstance3D` + `StaticBody3D`/`CollisionShape3D`, keeps the material's `naklon_unit` uniform in sync with `Naklon`. |
| `world/terrain/terrain_triplanar.gdshader` | The triplanar grass/rock/sand shader, Naklon-reactive. |
| `world/terrain/island_material.tres` | Default `ShaderMaterial` wiring the shader to the downloaded PBR texture sets, with tuned default uniform values. |
| `world/terrain/island_demo.tscn` | Standalone demo scene: `WorldEnvironment` + `Sun` + `DemoCamera` + a sea `PlaneMesh` + one `IslandTerrain` node. Does **not** touch `world/god_view.tscn` — the integration pass splices this in. |
| `world/terrain/reach_border.gdshader`, `world/terrain/reach_border.gd` | Ground-flush glowing ring visualizing `Reach.radius_for_village()` — see "Reach border" below for why this lives here. |
| `assets/textures/terrain/{grass,rock,sand}/*.jpg` | Downloaded CC0 PBR texture sets (see Assets used). |

## How island generation works (`island_generator.gd`)

`height_at(local_x, local_z)` combines three `FastNoiseLite` layers, all
seeded from one `island_seed` (offset per-layer so they don't correlate):

1. **Continent shape** — `TYPE_SIMPLEX_SMOOTH`, very low frequency
   (`0.006 / continent_noise_scale`), 4 fractal octaves. This is the big,
   slow silhouette — where the landmass broadly is.
2. **Ridged erosion-look detail** — `TYPE_SIMPLEX` with
   `fractal_type = FRACTAL_RIDGED`, mid frequency (`0.025 / ridge_noise_scale`),
   5 octaves. Ridged fractal noise produces the folded, valley/ridge look
   erosion leaves behind — this is what keeps the island from reading as a
   smooth blob.
3. **Small-scale roughness** — `TYPE_SIMPLEX`, high frequency
   (`0.12 / detail_noise_scale`), 3 octaves, low weight (0.06). Breaks up
   flat stretches so the mesh doesn't look mathematically smooth up close.

These three are weighted-summed (`0.75 / 0.35 / 0.06`) and multiplied by a
**radial falloff mask** (`smoothstep` of `1 - r^coastal_falloff_power`,
`r` = distance from center normalized by half the island size) so the
result reads as an island with a coastline, not infinite terrain — outside
the mask the height is pulled down toward a plausible sea floor instead of
ending in a hard cliff at the heightmap's border.

`build_mesh()` samples this on a `resolution × resolution` grid, computes
per-vertex normals from finite differences of the heightmap (the standard
`normalize(-dh/dx, 1, -dh/dz)` formula), builds the triangle grid with
winding verified by hand to match the up-facing normals (so `cull_back`
keeps the topside), and then re-emits the mesh through a `SurfaceTool` pass
purely to call `generate_tangents()` — needed for the triplanar shader's
`NORMAL_MAP` output, which requires a TBN basis.

`build_heightmap_shape()` samples the *same* cached heightmap (see
`_sample_grid`'s cache — it keys off resolution so mesh and collision are
guaranteed to agree) into a `HeightMapShape3D`. `HeightMapShape3D` assumes
1-unit sample spacing in local space, so `IslandTerrain` scales the
`CollisionShape3D`'s transform by `grid_step()` (`size_meters / (resolution-1)`)
on X/Z to line the collision grid up with the render mesh exactly.

**Bug caught and fixed during this pass**: noise was originally built
eagerly in `_init()`, which runs at `IslandGenerator.new()` time — before
the caller (`IslandTerrain.regenerate()`) gets a chance to set
`island_seed`/`size_meters`/etc on the new instance, which would have
silently baked in whatever the export defaults were and ignored every
custom seed. Fixed by building noise lazily on first call into `height_at()`
(`_ensure_noise()`, guarded by a built-once flag), so the generator only
needs its properties set correctly *before* the first `height_at`/
`build_mesh`/`build_heightmap_shape` call — which is exactly how
`IslandTerrain.regenerate()` uses it (set all properties, then build).

### Reusability ("each island is a level")

`IslandGenerator` takes only `island_seed` + `size_meters` (+ `resolution`,
`max_height`, `sea_level`, and three noise-scale knobs) and is otherwise
stateless/deterministic — two generators with the same seed+size produce
the identical heightmap, nothing is cached to disk. `IslandTerrain` wraps
one generator per node instance; drop multiple `IslandTerrain` nodes into
a scene with different `island_seed` values to get multiple distinct
islands, each with its own mesh, collision, and material instance (the
default material is `.duplicate()`d per instance in `_ready()` so per-island
shader tuning — e.g. a rockier `texture_scale` — never leaks across
islands).

`IslandTerrain` only exposes `island_seed` / `size_meters` / `resolution` /
`max_height` / `sea_level` as top-level export vars (the ones a level
designer actually wants to vary per island). The noise-shape sub-parameters
(`continent_noise_scale`, `ridge_noise_scale`, `detail_noise_scale`,
`coastal_falloff_power`) are still real, working `@export` vars on
`IslandGenerator` itself — construct/configure an `IslandGenerator` directly
if a specific island needs a different erosion character (e.g. a flatter,
less-ridged island for an early tutorial).

## Triplanar shader + Naklon integration (`terrain_triplanar.gdshader`)

Standard triplanar blending: sample each texture set on all three axis
planes (`xz`, `xy`, `zy`) and blend by `pow(abs(world_normal), blend_sharpness)`
normalized to sum to 1 — this avoids UV stretching on steep/vertical faces,
which a heightmap's single planar UV set would suffer badly on cliffs.

Per-fragment placement (grass vs. rock vs. sand) is by **slope + height**,
not by painted vertex colors or a splatmap texture (none was authored for
this pass — see Scoped out):

- `slope = smoothstep(rock_slope_end, rock_slope_start, world_normal.y)` —
  1 on flat ground, 0 on cliff faces, with a soft transition band between
  `rock_slope_end` (0.35) and `rock_slope_start` (0.55).
- `beach = (1 - (world_y - sea_level) / sand_height) * slope` — low and flat
  ground near `sea_level` reads as sand; steep faces never count as beach
  even at low elevation.
- Normal maps are decoded to tangent space, blended as vectors, renormalized,
  then re-encoded to the 0..1 range Godot's `NORMAL_MAP` built-in expects.

### `naklon_unit` — the coordinated uniform name for package D

**Uniform name: `naklon_unit`, `hint_range(0.0, 1.0)`, 0 = full Mercy, 1 =
full Cruelty** — identical convention to `Naklon.unit()` in
`core/naklon.gd`; do not re-invert it downstream. `IslandTerrain` keeps this
uniform live automatically (connects to `Naklon.naklon_changed` and pushes
`(new_value + 1.0) * 0.5` on every change, plus once on `_ready()`), so
nothing else has to poll `Naklon` for terrain to react.

Effect of `naklon_unit` on the *same* underlying mesh (silhouette is
governed only by seed/size — Naklon changes ground cover and grade, not
geometry, per this package's scope — see Scoped out):

- `cruelty_rock_bias = naklon_unit * 0.6` subtracts from the slope mask
  before grass is allowed, so near Cruelty, grass recedes off shallow
  slopes and more bare, cracked rock shows through even where the terrain
  hasn't changed shape at all.
- A multiplicative color grade lerps from a green `mercy_tint` (0.85, 1.05,
  0.85) to a dry/ash `cruelty_tint` (0.95, 0.72, 0.62) across the blended
  albedo — multiplicative so the real PBR scan textures stay legible
  instead of being replaced by a flat overlay.

Package D (art direction) can drive `naklon_unit` from anywhere with
`material.set_shader_parameter("naklon_unit", value)` — `IslandTerrain`
already exposes `terrain_material` as a public field if D's code wants to
reach in and add more parameters (glow, dust particles, etc.) keyed off the
same value.

## Reach border (`reach_border.gd` / `.gdshader`)

`systems/faith/reach.gd` (foundation code, not owned by this package) has
a doc comment stating territory is rendered via
`world/terrain/reach_border.gdshader` rather than a UI overlay, per the
design brief's "no HUD for territory" rule. Since that path falls under
this package's ownership, it's implemented here as a small, real, working
extra alongside the main terrain deliverable:

- `reach_border.gdshader`: an additive, unshaded, depth-non-writing ring
  shader, colored by `naklon_unit` the same way the terrain material is
  (green near Mercy, red near Cruelty), with a slow emissive pulse.
- `reach_border.gd` (`class_name ReachBorderView extends MeshInstance3D`):
  attach to a node, set `village_id`; it builds a `TorusMesh`, polls
  `Reach.radius_for_village(village_id)` in `_process()` (cheap — only
  rebuilds the torus when the radius actually changes), and positions
  itself at the village's `position_on_island`, optionally sampling ground
  height from an assigned `IslandTerrain` via `sample_height()` so the ring
  sits flush with the terrain instead of floating at `y = 0`.

This is **not** wired into any scene automatically — no package's brief
asked for one ring per village to be spawned, and doing so would mean
guessing at spawn/despawn lifecycle that belongs to whichever package
actually creates village visuals (I / G). It's a real, working, drop-in
component for those packages to attach, documented here since the file
lives in this directory.

## Assets used

All three sets are CC0 1.0 (public domain) from ambientCG, downloaded at
1K-JPG resolution (kept small deliberately — see Scoped out) via:

```
curl -sL -o Grass004_1K-JPG.zip  "https://ambientcg.com/get?file=Grass004_1K-JPG.zip"
curl -sL -o Rock023_1K-JPG.zip   "https://ambientcg.com/get?file=Rock023_1K-JPG.zip"
curl -sL -o Ground054_1K-JPG.zip "https://ambientcg.com/get?file=Ground054_1K-JPG.zip"
```

| Asset | Source | Author | License | Used for |
|---|---|---|---|---|
| Grass 004 | https://ambientcg.com/a/Grass004 | ambientCG (Lennart Demes) | CC0 1.0 | `grass_albedo`/`grass_normal`/`grass_rough` — flat/rolling ground cover |
| Rock 023 | https://ambientcg.com/a/Rock023 | ambientCG (Lennart Demes) | CC0 1.0 | `rock_albedo`/`rock_normal`/`rock_rough` — cliff faces, steep slopes |
| Ground 054 | https://ambientcg.com/a/Ground054 | ambientCG (Lennart Demes) | CC0 1.0 | `sand_albedo`/`sand_normal`/`sand_rough` — beach/low-elevation flat ground |

Only Color, NormalGL (OpenGL-convention normal map, matching Godot's
`hint_normal` expectation), and Roughness maps were kept from each
downloaded zip; the `.blend`/`.mtlx`/`.usdc`/`.tres`/preview-PNG/`NormalDX`
files ambientCG bundles were deleted to keep the repo lean — none of them
are used by this package. Files live at
`assets/textures/terrain/{grass,rock,sand}/`.

## Scoped out

Stated plainly, not silently faked:

- **No hand-authored splatmap / vertex-painted biome control.** Biome
  placement is entirely procedural (slope + height), which is honest for
  a single generated island but means a level designer can't hand-place
  "put sand here, rock there" independent of the actual terrain shape.
  A splatmap-texture input would be the natural next step if hand
  authoring is wanted later — the shader would need one more sampler and
  a lerp; not implemented here to keep this pass's forward mesh + collision
  + shader pipeline the actual focus.
- **Naklon does not reshape the mesh silhouette, only ground cover +
  color.** The brief's example ("rolling green hills near mercy,
  cracked/burnt rock near cruelty") is delivered as a material-space
  effect (what's rendered on top of the terrain), not a geometry
  deformation (e.g. displacing vertices to look literally more jagged at
  Cruelty). Re-baking geometry per Naklon shift would mean rebuilding the
  ArrayMesh and HeightMapShape3D live every time Naklon crosses a
  threshold — collision would need to update too, which risks physics pops
  under anything standing on the terrain. Scoped to the safer, still real,
  shader-driven approach; a geometry-displacement pass is a reasonable
  follow-up if a critic wants a stronger silhouette read at either pole.
- **Only one texture resolution tier (1K).** Chosen deliberately — this
  sandbox renders on `llvmpipe` (software Vulkan, see `docs/rendering.md`),
  where 2K/4K texture sets cost real wall-clock decode/upload time on every
  render with no visual benefit on a screenshot-sized viewport; 1K is
  already sharp enough at any camera distance this god-sim's top-down/
  angled view actually uses. Swapping in 2K/4K later is a one-line texture
  swap in `island_material.tres`, not a pipeline change.
- **No island-to-island streaming/LOD.** Each `IslandTerrain` builds one
  full-resolution mesh; a multi-island campaign map would want
  distance-based mesh LOD or unloading off-screen islands. Out of scope
  for a single vertical-slice island (this package's own demo instantiates
  exactly one).
- **`sample_height()` assumes a translation-only `IslandTerrain` node**
  (no rotation). Documented in the function's own doc comment; fine for
  every island being a flat-on-the-sea placement, which is the only case
  this pass needed.
- **No beach foam / shoreline blending with the ocean.** That seam belongs
  to package C (`world/ocean/`), which owns water rendering; this package
  only guarantees the terrain mesh extends below `sea_level` at the coast
  so there's real geometry for the ocean plane to intersect against,
  rather than a bare drop-off.
