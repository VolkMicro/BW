# Rivers — traced from the island's own drainage

`world/terrain/waterways/river_network.gd` (`class_name RiverNetwork`) puts
watercourses on the island, and `world/ocean/river_surface.gd` (which existed
but was never instanced by anything) builds the ribbon for each.

## Why the courses are found, not drawn

The obvious way to put a river on an island is to author a spline and drop
water on it. That reads wrong immediately, because a river is not a shape
laid over terrain — it is the terrain's own drainage. Water that crosses a
ridge, or runs along a contour instead of down it, looks painted on even to
someone who cannot say why.

So the courses are derived:

1. **Seed from the flow map.** `IslandGenerator`'s hydraulic erosion already
   records how much water crossed each cell (`flow_at()`). The strongest
   inland, high-enough cells are the catchments the simulation itself found.
2. **Walk downhill** by steepest descent with inertia, sampling the same
   smoothed heightmap the visible mesh is built from.
3. **Stop at sea level.**

A river therefore runs in a valley here not because it was placed in one, but
because the valley is where the water ran — both come from the same
simulation, so they cannot disagree.

## Two things that had to be fixed to make it work

**Crossing sediment lips.** The first tracer broke at the first uphill step.
Measured: all three courses died after 60-90 m on a 320 m island. Erosion
*deposits* as well as cuts, so it leaves shallow lips and closed pits all
over an otherwise well-drained surface. `max_climb_steps` now tolerates a
short climb and only a sustained one ends the river — the cheap equivalent of
what a real hydrology solver does by flooding a pit and continuing from its
outlet.

**The ribbon buried itself.** `RiverSurface` smooths its control points with
a Catmull-Rom, and a spline cuts corners, so through a tight valley bend the
ribbon passes *inside* the turn — below the ground it is meant to lie on. At
the original 0.35 m lift the rivers were invisible because they were
underground. Fixed with a denser control-point stride plus `surface_lift`
at 1.1 m.

## Shader: the cheap path

`world/ocean/river.gdshader` shipped reading `hint_screen_texture` and
`hint_depth_texture`. Declaring either makes Godot copy the whole framebuffer
every frame the material is visible, whether or not the sample is branched
around — the single most expensive thing this project removed from the ocean.
A handful of river ribbons must not quietly reintroduce it, so both are gone:

- **Cross-channel depth from the ribbon's own UV.** `UV.x` is 0 at one bank
  and 1 at the other, so "how deep am I" is free. Arguably more correct than
  the depth buffer for a river anyway — a watercourse *is* deepest in its
  middle, whereas the depth buffer only knew how far the bed happened to be.
- **Bank foam from the same UV**, replacing the depth-derived shore foam.
- `ALPHA` no longer written and `blend_mix` dropped, so the surface is opaque
  and gets a depth prepass and early-Z. The river was never see-through.
- `cull_disabled` → `cull_back`. A ribbon is a single layer, so with culling
  off its front and back faces land at identical depth and which survives is
  arbitrary — and Godot flips the shading normal on a back face. That is
  exactly the bug that made the terrain render as if lit from below for days
  (see `island_generator.gd`'s winding comment).

## Cost

All at startup: a few hundred height samples per river, then one static
ribbon mesh each. No `_process()` anywhere in `RiverNetwork`. Three rivers by
default — on this hardware, and at this scale, three real rivers read as
"this island has rivers" better than a dozen threads would.

## Honest state

The rivers are real: three are traced, they follow the eroded valleys, and
they reach the sea (verified from the tracer's own logs — 3 sources found,
courses of 15-22 steps each terminating at the waterline).

**But they read faintly from god view.** At that distance a 4-15 m channel is
a few pixels wide, and what shows is mostly its bank foam — a light streak
rather than a clear blue watercourse. The water colour has been pushed away
from the terrain's green toward blue, which helped, but not enough to call
this finished. Next things to try, in order: widen further and let the width
curve open earlier; carve the channel into the heightmap itself at trace time
so the river sits in a visible cut rather than on the surface; only then
touch colour again.

Paths between villages are **not** built. They were scoped alongside rivers
and are not done.

### Assets used

None. Procedural geometry and hand-written shaders throughout.
