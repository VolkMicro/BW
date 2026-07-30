# Startup time, and the grey screen

## The report

> "Godot burns on a grey screen when the project is new, hung for about five
> minutes and showed nothing. Maybe the hardware is weak."

Two different things are hiding in that sentence, and they have different
answers.

## 1. The grey window is not a hang

Godot keeps presenting the LAST frame it drew. While a scene's `_ready()`
runs, nothing new is drawn — so if nothing was ever drawn, the window is an
empty rectangle for the whole build. The engine is working the entire time;
it just has nothing to show, and an empty window is indistinguishable from a
crash from the outside.

Measured on the development machine (Godot 4.7.1, warm caches):

| Phase | Time |
|---|---|
| Load every script and scene | 35 ms |
| Island: noise, erosion, mesh, collision | 598 ms (1825 ms cold) |
| Vegetation scatter | **1348 ms** |
| Village buildings and props | 436 ms |
| Villager crowd (600 agents) | 6 ms |
| First frame (shader/pipeline compilation) | ~1000 ms |

That is ~2.6 s of nothing on a fast desktop. On a laptop with integrated
graphics, multiply.

**Two fixes went in:**

* **The scatter is built AFTER the first frame.** It was more than the
  island, villages and crowd put together, and nothing depends on it
  existing. World build before the first frame: 2637 ms → **1409 ms**. The
  player watches their island appear and then furnish itself instead of
  watching a grey rectangle for the sum of both.
* **The main menu draws a loading veil and waits two frames before changing
  scene.** Two, not one: the first only queues the redraw. Because Godot
  keeps presenting the last drawn frame, that veil is what stays on screen
  for the whole blocking build. There is no grey window left anywhere in the
  normal path.

## 2. Five minutes is not this

Nothing measured here comes close to five minutes, so that number is almost
certainly one of:

* **First-time asset import.** A fresh clone has no `.godot/` (it is
  gitignored, correctly). Godot imports every model, texture and sound before
  it can open the project. Measured headless here: 9 s. On a slow disk with a
  cold file cache, minutes is plausible. **It happens once.** If it happens
  every launch, the project folder is not writable, and that is a real bug
  worth reporting.
* **Shader compilation on an Intel driver.** The first run compiles every
  pipeline the scene needs. `rendering/shader_compiler/shader_cache/enabled`
  and `rendering/rendering_device/pipeline_cache/enable` are both on by
  default, so this is also a once-per-machine cost — but on Mesa/Intel it can
  be a long once.

To tell them apart, run with the profile switch and read the log:

```
GODOT_PROFILE_STARTUP=1 godot --path .
```

If the `STARTUP` lines print quickly and the window is still blank, it is
shader compilation or import, not our world build.

## Godot 4.7.1

The project was migrated from 4.3 to 4.7.1 in one step. Every test passed
unchanged, no script errors, and the render is identical. `project.godot`
declares `4.7` now. The old binary is kept as `godot43` on this machine so a
regression can be bisected against it.

Nothing in 4.7 changes the numbers above by itself. What is worth knowing:

* **AreaLight3D** — a real rectangular area light. Not useful here: it is a
  cost we cannot afford on integrated graphics, and this island is lit by one
  directional sun on purpose.
* **Nearest-neighbour 3D viewport scaling** — potentially useful. The LOW
  preset already renders at 0.5 resolution scale with bilinear; nearest is
  the same cost and crisper, at the price of aliasing. Worth A/B-ing on the
  target laptop.
* **Inline shader previews, the Asset Store, standalone Android export,
  virtual joystick, Control offset transforms** — editor and platform work,
  none of it relevant to this project.

The honest summary: 4.7.1 is a clean upgrade with no immediate wins for us.
It was worth doing for the three years of fixes underneath the headlines, not
for anything in them.
