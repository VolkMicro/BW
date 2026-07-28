# Rendering: what's real here, and what isn't

## The honest constraint

This project is built inside a sandboxed Linux dev environment with **no
GPU** (`lspci` reports no VGA controller, no `nvidia-smi`, no `vulkaninfo`
against real hardware). Godot 4.3's Forward+ renderer still runs, because
Mesa ships `lavapipe`/`llvmpipe`, a fully spec-compliant *software* Vulkan
implementation. That means:

- Every screenshot in this repo is a **real render** of the real scene
  file, with real materials, real lighting (SDFGI/GI, shadows, glow, fog,
  SSAO/SSIL), captured by actually running the engine
  (`xvfb-run godot --rendering-driver vulkan`) and reading back the
  framebuffer. Nothing here is mocked up in an image editor.
- Frame rate is **not** meaningful evidence of anything on this hardware.
  `llvmpipe` rasterizes on the CPU and is 10-100x slower than any real
  GPU depending on the scene; a scene that renders at a crawl here can be
  buttery on a GTX 1060. Conversely we cannot claim "stable 60 fps" from
  this sandbox and have that claim mean what it would mean on real
  hardware, so this repo never makes that claim from sandbox numbers.
  `docs/systems/performance.md` states the actual measured llvmpipe
  numbers for the record, labeled as such, alongside the frame-budget
  *design* (draw call / triangle / light count targets) that a real GPU
  run would need to hit 60 fps at 1080p on mid-range hardware.
- Ray-traced reflections and traced GI need a real GPU with hardware RT;
  Godot 4.3 does not expose hardware ray tracing at all (its Forward+
  pipeline uses SDFGI/VoxelGI + screen-space + reflection-probe fallback
  for GI and reflections). The brief's "трассировка лучей или качественное
  запечённое GI" requirement is met via SDFGI (real-time, dynamic,
  probeless) plus baked reflection probes at the Sanctum and other
  camera-lingering interiors — this is the actual ceiling Godot 4.3 offers,
  not a placeholder for something better we didn't get to.

## How to reproduce a screenshot yourself

```
xvfb-run -a godot --path . --rendering-driver vulkan <scene-runner-args>
```

See `scripts_ci/screenshot.gd` for the capture harness used by the
integration pass.

## What an independent critic can and can't verify here

A critic subagent in this environment CAN: view a real PNG rendered by the
real engine and judge material response, lighting believability,
composition, and whether a shape/silhouette reads as intended. A critic
CANNOT: benchmark real-hardware frame time, judge how RT reflections would
look (none run here), or treat a llvmpipe screenshot's noise/aliasing
profile as representative of the shipped game's — llvmpipe's software
rasterizer has different antialiasing and filtering behavior than any GPU
driver. Every critic report in `docs/systems/` that references a
screenshot says so explicitly.
