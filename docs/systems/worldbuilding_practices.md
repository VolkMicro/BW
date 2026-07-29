# World-building practices worth adopting, and what they mean for this project

Research pass requested after the island still failed to read as a living
place on screen. This is not a general essay — every item below is judged
against what this project actually is: a **single 320 m island**, seen from
**god view**, on a **laptop with integrated Intel graphics**, in Godot 4.3.
Several widely-recommended techniques are correctly **rejected** here for
that reason, and the reasoning is written down so nobody re-litigates it.

Sources are listed at the bottom.

---

## 1. Terrain LOD: clipmaps and chunking — NOT for us, and that is fine

The standard answer for large terrain in Godot 4 is a geometric clipmap
(what Terrain3D uses, ~10 LOD levels) or chunked LOD with stitched edges.
Both exist to render *kilometres* of terrain.

**Rejected, deliberately.** Our island is one 161×161 grid — 25,921
vertices, ~51k triangles, one draw call, entirely inside the view frustum
at all times. A clipmap would add real complexity (edge stitching, LOD pops,
per-chunk collision) to solve a problem we do not have. Vertex count has
never once appeared in this project's measured bottlenecks; every real
performance win so far has been **fill-rate and bandwidth** (SDFGI,
volumetric fog, the ocean's screen-buffer copies, 27 texture fetches per
terrain fragment — see `performance_lowspec.md`).

**What to take instead:** the *reason* clipmaps exist — spend detail where
the camera is. We already do the fill-rate equivalent (weight-culled
triplanar sampling, distance-faded ocean detail, `visibility_range_end` on
scatter). That is the right axis for this hardware.

**Revisit if:** the brief's "ocean of islands" ever becomes real. Multiple
islands streaming in and out *is* the case chunking was built for.

---

## 2. Hydraulic erosion — the highest-value idea available to us

This is the one that would change how the island reads, and we currently do
none of it. Our terrain is three layers of noise times a radial falloff,
then blurred. Blurring is not erosion: it removes detail everywhere equally,
which is exactly why the island reads as a smooth mesa rather than land.

Real terrain looks the way it does because **water ran down it**. The
particle-based algorithm is well documented and cheap enough to run once at
generation time:

Per droplet, spawned at a random point:
1. **Descend** — step downhill along the gradient, carrying `volume`,
   `sediment` and `speed`.
2. **Erode / deposit** — compare sediment carried against a capacity
   proportional to speed and slope; scoop terrain where under capacity, drop
   it where over. This is what carves valleys and fills basins.
3. **Evaporate** — reduce volume each step; the droplet dies when it is
   spent, leaves the map, or pools.
4. **Pool and drain** (the refinement most implementations skip) — when a
   droplet stops in a depression, flood-fill to find the pool's outlet and
   continue from there. Without this, water piles up in local minima and
   rivers never reach the coast.

Key parameters: inertia, sediment capacity, erosion rate, deposition rate,
evaporation rate. Typical runs are tens to hundreds of thousands of
droplets; the flood-fill step dominates cost.

**Two things matter specifically for us:**
- **Sea-level drain.** Nick McDonald's write-up calls out that pools
  otherwise treat the map boundary as a wall and water never leaves. Our
  island is surrounded by sea — every droplet reaching `sea_level` should
  simply terminate. This is a one-line guard that makes rivers actually run
  to the coast.
- **It is a generation-time cost, not a frame cost.** It runs once inside
  `IslandGenerator`, on a 161×161 grid. That is small. It cannot hurt frame
  rate at all, which makes it unusually safe for this hardware.

**Bonus:** erosion produces the *flow map* for free — how much water crossed
each cell. That is exactly the data needed to place rivers (high flow),
choose where grass grows lushest (damp valleys), and where bare rock shows
(scoured ridges). It replaces guesswork with something derived from the
terrain itself.

**This is the top recommendation for the next iteration.**

---

## 3. Readability beats realism at god-view distance

The art-direction sources converge on one point for top-down and isometric
views: **strong value separation and clear silhouettes**, because at that
distance detail becomes noise. Stylisation is described not as a budget
compromise but as a *cognitive clarity* choice — the player must parse the
whole island at a glance.

There is also a direct warning against our current framing: cartographic
top-down clarity and oblique cinematic mood **weaken each other when
combined**. Our god view is trying to be both.

**Concrete implications:**
- The island currently has almost no value separation from the sea — both
  sit in the same mid-grey band. Land should be clearly *lighter and
  warmer* than water, or clearly darker; either reads, the current
  near-match does not.
- Fog is actively working against us. It compresses the island's value
  range toward the sky's, which is the opposite of separation. Fog belongs
  at the horizon, not over the play space 250 m from the camera.
- Saturation should be pushed further than looks correct up close. A muted
  real-world scan (Grass004 is a genuine muted olive) reads as grey at
  distance through atmosphere.

---

## 4. Vegetation: clustering, not sprinkling

Already applied this pass, and the sources agree it is the right instinct:
woods and clearings driven by a low-frequency mask read as a landscape;
uniform density reads as a lawn. Worth extending once erosion lands —
vegetation should follow **moisture** (the flow map), not just slope and
height. Trees in the valleys, bare on the ridges. That single change does
more for "this is a real place" than any amount of extra instances.

---

## 5. Honest note on process

Two full days of this project's rendering work were spent on bugs that
*looked* like art problems and were not: a sun pointing at the sky, a
terrain shader rendering its own underside, an environment driver silently
discarding the authored exposure. In each case the fix was found by
**measuring rendered pixels** and bisecting, not by adjusting values that
seemed wrong.

The current unsolved issue — most of the island not being drawn by the
terrain shader at all — was narrowed the same way and is documented at the
end of the previous commit. **Establish that the surface on screen is the
surface you think it is before tuning its colour.** Every hour lost this
week was lost to skipping that step.

---

## Priority for the next iteration

1. **Particle-based hydraulic erosion in `IslandGenerator`**, with a
   sea-level drain, replacing the box-blur smoothing passes. Highest impact,
   zero frame cost, and it unlocks 2 and 4 below.
2. **Rivers from the flow map** — the river shader already exists and is
   still unused.
3. **Value and saturation separation** between land, water and sky; pull
   fog back to the horizon.
4. **Moisture-driven vegetation** using the same flow map.
5. Only then revisit terrain LOD, and only if the world grows past one
   island.

---

## Sources

- [Clipmap algorithm — Godot Forum](https://forum.godotengine.org/t/clipmap-algorithm/141864)
- [Best way to handle LODs for a chunked terrain — Godot Forum](https://forum.godotengine.org/t/best-way-to-handle-lods-for-a-chunked-terrain/95102)
- [Terrain3D (Godot 4 geometric clipmap terrain)](https://github.com/outobugi/Terrain3D/wiki)
- [Procedural Hydrology: Dynamic Lake and River Simulation — Nick McDonald](https://nickmcd.me/2020/04/15/procedural-hydrology/)
- [Hydraulic Erosion — Awesome GameDev Resources](https://courses.tolstenko.net/artificialintelligence/01-pcg/HydraulicErosion/)
- [Improved terrain generation using hydraulic erosion — Ivo van der Veen](https://medium.com/@ivo.thom.vanderveen/improved-terrain-generation-using-hydraulic-erosion-2adda8e3d99b)
- [Erosion Simulation in Terrain Generation — Daniel Gray](https://www.danbgray.com/blog/Coding/The_3D_Background/Erosion_Simulation)
- [Realism vs Stylization in Game Art — Sunstrike Studios](https://sunstrikestudios.com/en/blog/game_art_visual_direction/)
- [Stylized art style — Pixune](https://pixune.com/blog/stylized-art-style/)
- [Understanding game art styles — Argentics](https://www.argentics.io/understanding-game-art-styles)

---

# Applied: hydraulic erosion (this pass)

Item 1 of the priority list is implemented in `world/terrain/island_generator.gd`.

**Measured:** `build_mesh()` with 22,000 droplets takes **818 ms** on this
machine — a one-time generation cost, zero frame cost, exactly as predicted.
Height range is preserved (max 32.7 m, min -20.3 m) and only **17 vertices
out of 25,921** end up steeper than `n.y < 0.55`, so erosion does *not*
reintroduce the near-vertical slopes that caused the old hole problem. The
flow map normalises correctly (peak 1.0 after normalisation, 244 of the
sampled cells carrying meaningful flow).

**Visible result:** branching valleys now run down the island and the
clustered forest follows them, because the scatter rules key off slope and
the valleys are the steep parts. That is the "it looks like water ran here"
effect the blur could never produce.

The sea drain works as the sources warned it must: droplets terminate on
reaching `sea_level` instead of pooling at the coast.

`flow_at(local_x, local_z) -> float` exposes the normalised flow map. It is
not consumed by anything yet — it is the intended input for river placement
(item 2) and moisture-driven vegetation (item 4).

## Also applied: fog moved to the horizon (item 3, partially)

Fog was exponential, which begins at the camera, so at god-view range it lay
a blue-grey sheet over the play space itself. Measured: it pulled the island
from green-dominant (G−B = +1) to blue-dominant (G−B = −3). Now DEPTH-mode
fog beginning at 420 m — past the island, before the ocean's 1200 m edge —
so the horizon is still hidden and the island is not washed.

**Trap worth knowing:** `environment/graphics_preset.gd` sets
`env.fog_enabled = true` at runtime, so setting `fog_enabled = false` in the
`.tres` does nothing. Two separate debugging sessions were lost to that. The
knobs that actually work are the depth bounds and
`naklon_environment_driver.gd`'s `MERCY/CRUELTY_FOG_DENSITY` constants.

## Still unsolved: the terrain surface renders pale, not green

Recorded properly so the next attempt starts from facts. What is now
established by measurement, each by its own render:

- The blend masks are correct — grass = 1.00, rock = 0.00, beach = 0.00,
  computed against the real mesh at four inland points.
- The textures load and are green (grass average 0.36 / 0.40 / 0.18).
- The material's `naklon_unit` is 0, so the mercy tint is in effect.
- **Forcing `ALBEDO = vec3(0, 1, 0)` in the terrain shader changes the
  rendered result by ~1/255.** This is the strongest clue and it means the
  surface on screen is not this shader's output.
- It is not the grass scatter (`grass_count = 0` changes nothing), not the
  ocean, not fog, not specular or roughness, not sky reflections, not
  shadows, not the tonemapper.
- With the terrain mesh hidden the pale surface remains; with the ocean
  hidden a pale *dome* remains. The dome shape is correct, so the geometry
  was never the problem — only its colour.

**Method note for whoever picks this up:** `world/ocean/ocean.gdshader` uses
`render_mode world_vertex_coords`, which means the node's transform is
ignored — moving the `OceanSurface` node does nothing at all. A test that
moves it and concludes "the ocean is not involved" is invalid. Verify a
surface responds to a change before drawing conclusions from it not
responding.

The next thing to try is the simplest one not yet done: put a garish flat
material on the terrain via `island_material.tres` (not via the shader) and
confirm whether *that* reaches the screen. If it does not, the material
override in `IslandTerrain.regenerate()` is the suspect, not the shader.
