# Package A — Engine, pipeline, CI, frame budget

## Engine & version
Godot 4.3.stable (official binary), Forward+ (Vulkan) renderer. Rationale
in top-level README.md; hard constraints in docs/rendering.md.

## Build / "CI" in this environment
There is no hosted CI runner available to this project (no GitHub Actions
minutes provisioned here), so validation is local and must be run by hand
or via `scripts_ci/`:

- **Static/syntax validation**: `godot --headless --path . --check-only`
  parses every script and scene and reports GDScript errors without
  opening a window. This is the fast, cheap check to run after any script
  change, and it is the check every builder package is expected to pass
  before handing work to its critic.
- **Visual validation**: `scripts_ci/screenshot.gd` (see docs/rendering.md)
  renders a real frame of a given scene under Xvfb + software Vulkan and
  saves a PNG. Slow (llvmpipe), so used for spot-checks and the
  integration pass, not on every save.
- No automated unit-test framework is wired in yet (e.g. GUT). Given the
  project's actual risk surface (a learning-agent creature, a gesture
  recognizer, fatigue/decay curves) is logic-heavy, `core/`, `systems/faith/`,
  `systems/sigils/`, and `actors/avatar/` are the modules most worth adding
  GUT coverage to next; flagged here rather than silently skipped.

## Frame budget (design target, not yet measured on real hardware)

No GPU exists in the environment this repo was built in (docs/rendering.md).
The numbers below are the *design* target for a real mid-range GPU
(GTX 1660 / RX 5600 class) at 1080p, 60 fps => 16.6ms/frame budget:

| Line item | Budget |
|---|---|
| Opaque geometry (terrain + villages + Avatar) | ~6.0 ms |
| Ocean (full island shoreline in view) | ~1.5 ms |
| Shadows (cascaded directional, contact hardening) | ~2.5 ms |
| SDFGI + reflections | ~2.5 ms |
| Volumetric fog + post (glow/DOF/tonemap/TAA) | ~2.0 ms |
| Crowd (villagers, MultiMesh-instanced, LOD'd past ~30m) | ~1.0 ms |
| Misc (UI-less HUD, audio, gameplay logic) | ~1.1 ms |

Practical levers if a real profiling pass comes in over budget, in the
order they should be pulled: drop `scaling_3d/scale` below the 0.9 set in
`project.godot` (FSR upscale covers the rest), reduce
`sdfgi_min_cell_size`/cascades, drop volumetric fog to non-filtered, then
shadow resolution, before ever cutting draw distance or crowd counts —
those two are load-bearing for the "colossal scale" feel the brief asks
for.
