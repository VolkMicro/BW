# TITHE & TERROR — roadmap and handoff

**This file is the handoff document.** It is written so that a different AI,
or a different person, can pick this project up cold — without the
conversation that produced it — and continue without repeating work or
re-learning the same bugs.

It is committed to git and updated as work proceeds. If you are taking over:
read this file first, then `docs/systems/performance_lowspec.md`, then
`docs/systems/worldbuilding_practices.md`.

---

## 0. The rule about committing

**Commit and push every 5–10 minutes of work, and update this file's
"Current position" section when you do.** Not at the end of a task — during
it. The project owner needs to be able to hand this repository to another AI
at any moment, including mid-task, and have it make sense.

A good commit here explains *why*, not just what, and records what was
measured. Several bugs in this project's history were only findable because
an earlier commit message recorded a measurement. Keep that habit.

Never leave the repository in a state that does not compile. Verify with:

```
godot --headless --path . --check-only --quit-after 3
```

---

## 1. What this game is

A god-sim over the Ninefold Sea. The player is one of two surviving gods.
The other, Louhi of Pohjola, holds the north. Faith is the only food a god
has: villages that pray to you make you stronger, and a god with no
worshippers is nothing.

**The end state is that only one god remains.** That is the shape of the
whole campaign and everything should serve it — see §5.

Original names, lore and art throughout. Mechanics may resemble the genre;
nothing is copied from any existing game. `docs/audit/respect_audit.md` holds
hard rules about the mythological register and has veto power — read it
before inventing any name.

---

## 2. Current position

*Update this section every commit.*

**Status: Phase 1 DONE. Island is 1200 m, cached, chunked, correctly shaped
at that scale, and carries 15 villages planned onto the real terrain.
Next: Phase 2, daily life.**

Done since the roadmap was written:
- **PHASE 2 STARTED: villagers have needs, and the ledger answers them.**
  Food and firewood are consumed every tick; a cold night burns more wood
  than a warm afternoon; a village that runs short loses devotion and a
  little faith, and the Voices say so after six seconds of it (not on a
  one-frame dip). Job choice is no longer a fixed dice table — it reads the
  stores, so an empty larder pulls hands onto food and an empty woodpile
  pulls them into the trees. Rebuilding a damaged Sanctum yields to hunger.
  The economy reads LIVE job counts from `VillagerCrowd.count_job()` instead
  of the authored `Village.jobs` dictionary nothing ever updated (this closes
  the last 1a item), and the crowd spawns each village's OWN population
  rather than a flat 40, so the workforce and the mouths are the same number.
  Verified over ~400 frames: fifteen villages at genuinely different levels,
  three of them running short and losing devotion for it.
  TWO TRAPS FOUND AND FIXED HERE, both worth knowing:
  1. Distance used to gate DECIDING. Once the economy read real job counts,
     every village more than 260 m from the camera reported zero workers and
     quietly starved — twelve of fifteen at food 0.0 with forty idle people.
     `agents_per_tick` is what bounds the cost; distance only decided which
     agents got the frame's slots.
  2. Production was tuned when villagers were a stand-in dictionary. One
     field hand fed eighteen people, so every village sat pinned at its
     storage cap and no shortage could ever happen. Food per worker 0.9 ->
     0.22, wood 0.7 -> 0.16, firewood burn 0.004 -> 0.012 per head.
- **The sun moves.** `environment/day_cycle_driver.gd` drives the scene's
  DirectionalLight3D off `Weather.day_phase()` — a ten-minute day, sunrise
  through noon to a cold dim night. Phase 2 is about villagers having a day,
  and none of that reads if the light never changes. The clock already
  existed (Weather has run a diurnal temperature curve since it was written);
  it was simply never connected to anything visible.
  Night is deliberately not black — this is a game played from the air, and
  half of every cycle spent staring at an unreadable shape is not atmosphere.
  Villages read as points of light at night, which came free from the
  Sanctum altar emission.
  The sky darkens with it too: the daylight factor is layered into
  `environment/weather_environment_driver.gd`, which is the single owner of
  the Environment's ambient/background/fog energies. It went there rather
  than into the day cycle driver precisely so two nodes never write the same
  Environment field. Exposure is deliberately left alone — crushing it on top
  of weak moonlight takes the island from "night" to "cannot see the island".
- `scripts_ci/screenshot.gd` grew `SHOT_DAY_PHASE` (0 = sunrise, 0.25 = noon,
  0.75 = midnight). Without it a shot can only ever show the minute the
  harness happened to boot in.
- **Terrain shape fixed for the new scale.** Noise frequency is in cycles per
  METRE, so growing the island from 256 m to 1200 m without touching it gave
  ~5x as many features at the same size — a field of identical conical hills
  instead of a landmass, with the detail octave aliasing at two samples per
  wavelength. Frequencies now scale by `TUNING_SIZE / size_meters`, i.e.
  cycles per ISLAND. `coast_warp_strength` moved from metres to a fraction of
  half-size for the same reason: 46 m carved bays into a 256 m island and
  merely dimpled a 1200 m one, which is how the big island came out a smooth
  oval — the one shape the design says an island must never be.
  `FORMULA_VERSION` now goes into the cache key, because these are constants
  rather than exported parameters and the cache would otherwise keep serving
  islands built by the old formula.
- **Terrain height queries outside the island footprint now return open sea.**
  They used to clamp to the nearest edge sample, so where the island reached
  the grid boundary every point out to the horizon reported dry land. The
  ocean's shore mask believed it and cut its own triangles away, leaving two
  straight ribbons of missing water running to the horizon.
- **Fifteen villages, planned rather than authored.**
  `world/village/settlement_planner.gd` picks sites off the real heightmap by
  blue-noise rejection, scores them (level, low, above the surf) so the good
  ground fills first, and names each one from the ground it stands on —
  "Sankiln Strand" is on a beach, "Ederhal Dell" is in a basin. The three
  authored villages stay authored because they carry the walkable Sanctum
  interior; the other twelve get their Sanctum, Reach ring and Calling Stone
  built at runtime by `god_view._build_village_anchor()`.
  Scatter now waits for that placement (`auto_scatter_on_ready = false`)
  instead of clearing grass around three authored guesses.
- `scripts_ci/screenshot.gd` grew `SHOT_CAM` (park the camera at an exact
  position/target — it also stops the rig from driving it, or the next frame
  puts it back) and `SHOT_DUMP_VILLAGES`. With the layout generated, these
  are the only way to inspect one particular village out of fifteen.
- **The island is 1200 m across** (was 320 m), `max_height` 120 m,
  ocean plane 5200 m so no world edge is visible. This is the scale the
  15-village target needs.
- **Generation is cached to disk.** `island_generator.gd` hashes the 26
  parameters that affect the heightmap into a key under
  `user://terrain_cache`. Measured at 1200 m / 301 / 60000 droplets:
  first run 2705 ms, cached run 538 ms. Change any generation parameter
  and the key changes, so there is no stale-cache trap — you never need
  to clear it by hand.
- **Scatter is chunked.** Grass, trees and rocks each split into an NxN
  grid of MultiMeshInstance3Ds (8x8 grass, 5x5 trees, 5x5 rocks) so the
  engine can cull whole regions by distance. On a 320 m island one
  MultiMesh per kind was fine; at 1200 m it meant drawing the far side of
  the island every frame. Counts scaled with area: 26000 grass, 5200
  trees, 2600 rocks.
- Island is no longer a dome: lobed elliptical falloff centres plus a
  domain-warped coastline, so each seed is a different landmass with
  headlands and bays (§7 items 1 and 2). Items 3 (inland lakes) and 4
  (cliffs) remain.
- Villages find their own ground. The authored X/Z is now a wish; the
  village settles on the nearest spot above the surf, level across the
  Sanctum footprint, and clear of its neighbours. Warns rather than
  silently teleporting when no site exists.
- **Villages have houses, and the Sanctum reads as a temple.**
  `world/village/` — dwellings placed on real terrain around each village as
  ONE MultiMesh for the whole island, and a tiered temple superstructure
  (roof tiers, corner posts, ridge prows) raised over each Sanctum's existing
  CSG shell so nothing that already worked breaks. This was a legibility fix,
  not a content one: the player could not tell a Sanctum from a shed, and
  villages had no dwellings at all.
- **Villagers are off the scene graph** (1a). `actors/villagers/villager_crowd.gd`
  holds the whole island's population in packed arrays, drawn by ONE
  MultiMesh, standing on the heightmap instead of colliding with it, deciding
  on a round-robin budget (`agents_per_tick`) with a distance-based detail
  cutoff. Verified running at 120 (3 x 40) where the old node-per-villager
  build ran 15. Not yet measured on real hardware.
  Still to do on 1a: `systems/economy/` should read `count_job()` from the
  crowd rather than the authored `Village.jobs` dictionary, and the old
  `villager.gd` node path is still present for the standalone demo.
- Camera zoom is tied to the island instead of magic numbers:
  `god_max_view_fraction` (0.7) derives the zoom-out limit from
  `size_meters` and the vertical FOV, so it keeps meaning "70% of the
  island" when the island grows to 1200 m. Closest zoom is 30 m — one
  villager and their yard legible.

What genuinely works right now:

- Island generation with **hydraulic erosion** (particle model, sea drain,
  flow map exposed via `flow_at()`). Real valleys, ~800 ms at generation.
- Terrain renders correctly: green, lit, textured, with a sand shoreline.
- **Vegetation scatter**: grass, clustered forest, boulders. MultiMesh, three
  draw calls, distance-culled.
- **Rivers** traced from the erosion flow map, reaching the sea. They read
  faintly from god view — unfinished, see §4.
- Ocean with Gerstner waves, cheap shoreline from baked per-vertex depth.
- Wildlife: three species with wander/graze/flee AI (`rimefleece`, `snagbill`,
  `thawjaw` — a predator).
- Villagers: utility-AI job selection, reacting to weather and village state.
  **15 of them, as `CharacterBody3D` nodes.** This is the thing Phase 1 must
  change.
- Two Voices with ~52 authored trigger pools, shown on screen via
  `ui/voice_log.gd`.
- Campaign manager with quests, relics, sigil scrolls.
- LouhiDirector: a real presence AI with escalating signs.
- Graphics presets LOW/MEDIUM/HIGH (`P` cycles at runtime). LOW is default and
  is tuned for integrated Intel graphics.

Scale today: island 320 m, 3 villages, **40 villagers each (120 total)**.

---

## 3. Hard-won lessons — read before debugging anything visual

Every one of these cost hours. They are not hypothetical.

**The rendering target is a laptop with integrated Intel graphics, no
discrete GPU.** SDFGI, volumetric fog, SSAO and SSIL are disabled outright,
the Mobile renderer is in use, resolution scale is 0.5. Anything added must
be cheap, and "cheap" means measured, not assumed.

**Measure rendered pixels; do not reason about the code.** Three consecutive
bugs looked exactly like art problems and were not:

- *The sun pointed at the sky.* All eleven scenes shared a
  `DirectionalLight3D` basis whose `-Z` had a positive Y. SDFGI's bounce
  light hid it until SDFGI was disabled.
- *The terrain rendered its own underside.* An earlier "fix" set
  `cull_disabled` on the terrain shader; front and back faces then land at
  identical depth, and Godot flips the shading normal on a back face, so the
  island was lit as though from below.
- *The terrain's triangle winding was inverted.* Its top faces were
  back-facing, so with `cull_back` the top of the island **was not drawn at
  all** — the pale "plateau" everyone was trying to recolour was the sky and
  the ocean seen through the terrain. Found by comparing the suspect region's
  RGB against the sky's and finding them identical.

**The rule that came out of it:** if a surface ignores every change you make
to it, stop tuning it and ask whether it is being drawn. Force its `ALBEDO`
to a garish colour. If the frame does not change, it is not that surface.

**Traps that invalidate tests:**

- `environment/graphics_preset.gd` sets `env.fog_enabled = true` at runtime.
  Setting it false in the `.tres` does nothing, and any conclusion drawn from
  "I turned fog off" without accounting for this is wrong.
- `environment/weather_environment_driver.gd` used to *overwrite* exposure and
  ambient rather than scale them, making the authored values dead. It now
  scales. `naklon_environment_driver.gd` still overwrites `tonemap_white` by
  design.
- Shaders with `render_mode world_vertex_coords` **ignore the node's
  transform** (`world/ocean/ocean.gdshader`). Moving that node does nothing.
- A fragment `discard` reproducibly crashes Godot 4.3 on Mesa lavapipe here
  (signal 11 during shader compile). Do the same work in the vertex stage or
  on the CPU.
- Declaring `hint_screen_texture` or `hint_depth_texture` forces a
  full-framebuffer copy every frame the material is visible, whether or not
  the sample is branched around. This is the single most expensive thing that
  was removed from this project. Do not reintroduce it.

**Godot quirks here:**

- Plain `--check-only` does not exit. Always pass `--quit-after 3`.
- Ignore exactly two lines in its output: `Parameter "m" is null …
  mesh_get_surface_count`, and `ObjectDB instances leaked at exit`.
- Screenshot with **no** `--rendering-driver` flag — passing `vulkan` silently
  falls back to Forward+ and renders something other than what ships:

```
SHOT_SCENE="res://world/god_view.tscn" SHOT_OUT=/tmp/shot.png SHOT_FRAMES=20 \
  timeout 550 xvfb-run -a godot --path . scripts_ci/screenshot_runner.tscn
```

Takes ~2 minutes on the software rasteriser. There is no GPU in the
development sandbox, so **no performance claim made here has been measured on
real hardware** — say so rather than inventing numbers.

- Common real GDScript bugs in this codebase: type-inference errors (fix with
  an explicit annotation) and setting `global_position` *before* `add_child`
  (must be after).

---

## 4. Known unfinished work

- **Rivers read faintly** from god view — a few pixels wide, showing mostly
  bank foam. Next step: carve the channel into the heightmap at trace time so
  the river sits in a visible cut, rather than widening it further.
- **Paths between villages** were scoped with rivers and are not built.
- **The ocean tiles** visually at distance — the six-wave analytic Gerstner
  sum is exactly periodic, and at a shallow grazing angle that reads as a
  repeating band pattern. Two mitigations were tried and did not close it.
  Real fix is a less regular wave model or a different default camera angle.

---

## 5. The roadmap

Approved by the project owner. Phases are ordered by dependency: **Phase 1 is
mandatory first**, because nothing after it will run on the target hardware
otherwise.

### Phase 1 — Scale and foundation

The enabling work. No new gameplay; without it, everything else is a
slideshow.

**1a. Villagers stop being nodes.** Today a villager is a `CharacterBody3D`
running `move_and_slide()` every physics frame, and there are 15. The target
is **600** (15 villages × 40). That is not "40× more", it is a different
architecture:

- Villager state becomes rows in packed arrays, not scene nodes.
- Rendering: one `MultiMeshInstance3D` per village (or per LOD tier) — one
  draw call for the crowd.
- No physics bodies. Ground contact is a heightmap sample, which this project
  already has (`IslandTerrain.sample_height()`).
- Movement is steering, not pathfinding. **Do not use `NavigationServer` for
  600 agents.** Precompute a flow field per village toward its common
  destinations (forest, shore, fields, home) and have agents follow it.

**1b. AI level-of-detail.** Agents tick on a stagger (roughly once per second,
phase-offset), never all in one frame. Beyond a distance threshold a village
is simulated **in aggregate** — "12 on woodcutting, 8 hunting" — and its
visible figures just walk their routes without deciding anything. The player
cannot tell, and the cost drops by an order of magnitude. If this is skipped,
Phase 1's other work is wasted.

**1c. Island grows to ~1200 m.** At a 4 m cell that is ~90 k vertices, still
one draw call and acceptable. Erosion on that grid will take seconds, so
**cache the generated heightmap to disk keyed by seed and parameters** — the
first run pays, later runs do not. Geometric clipmaps and chunked terrain LOD
remain **rejected** (see `worldbuilding_practices.md` for the reasoning); they
solve a problem this project still does not have.

**1d. Scatter density by distance.** Grass at today's density over 15× the
area would be ~75 k instances. Density must fall off with camera distance, or
the scatter must be chunked with per-chunk visibility ranges.

**1e. Camera.** Zoom range from roughly 25 m (watch one person chop wood) to
whatever altitude shows **70 % of the island** at maximum zoom-out.

> **Note on a conflicting requirement.** The owner asked for "100 m altitude,
> 70 % of the island visible". Those cannot both hold: at 100 m with this FOV
> roughly 20 % of a 1200 m island is in frame; 70 % needs ~450 m. The
> resolution taken here is that **70 % at maximum zoom-out is the goal** — the
> fraction is what matters — and 100 m becomes the "village level" zoom where
> a yard, its people and its smoke are all legible. **If the owner meant
> something else, this is the thing to change first.**

### Phase 2 — Daily life

Needs: hunger, warmth, rest. Firewood burns in a hearth and runs out. Food
spoils. A day cycle drives the routine — out to work in the morning, home in
the evening, asleep at night.

Work stops being a number in a dictionary and becomes a journey: a woodcutter
walks to the forest, fells **a specific tree** (which disappears from the
scatter MultiMesh), and carries the log to the storehouse.

### Phase 3 — The village as a settlement

15 villages, 10+ buildings each: houses (a family lives in each), storehouse,
workyard, drying rack, smokehouse. A house is built when a family has nowhere
to live. The village grows on its own.

`systems/economy/` already has `gathering_house`, `storehouse`, `workyard` and
three wonders — extend rather than replace.

### Phase 4 — Hunting: joining two systems that already exist

Wildlife (three species, with real flee behaviour) currently lives entirely
apart from the villagers. Close the loop: a hunter tracks a herd, the animal
genuinely flees (already implemented), the carcass comes back as food. The
predator `thawjaw` takes livestock, so the village has something to fear.

### Phase 5 — The god layer on top

Only now do the rites land on something living: rain saves a field, lightning
sets fire to a wood someone was working in.

---

## 6. The faith war — how the campaign actually ends

Requested explicitly by the owner and it changes the shape of the game, so it
is written out here rather than left to Phase 5.

**Both gods live on faith, and faith is a finite pool.** Every village belongs
to one god, to the other, or to neither. A god's power — reach, devotion
income, how many rites can be held at once — scales with the villages held.

**Louhi must actively convert, not merely threaten.** Today `LouhiDirector`
escalates signs and can take a village at tier 2. That needs to become a real
contest:

- She works on villages that are *unclaimed or weakly held*, exactly as the
  player does — with gifts, with fear, with displays of power.
- A village being courted shows it: its people argue, its prayers falter.
- **The player can fight back.** There is currently no reclaim mechanic at
  all — a village lost to Louhi is lost permanently. That is the single
  biggest gap in the design and Phase 5 must close it.

**Feedback loop, deliberately:** more villages → more power → easier to take
the next. This makes the midgame tense and the endgame decisive, and it means
losing ground genuinely hurts.

**Victory: every village on the island prays to you. Defeat: none do.** One
god remains. The Two Voices should mark the turn of the tide — Domovoi
counting what is left, Hiisi delighted by the collapse.

---

## 7. Island shape — no more circles

The current island is a radial falloff, so it is a dome, and real islands are
not. Real coastlines are **elongated, lobed, and irregular**, with headlands,
bays, sea cliffs and lakes inland. Compare any real island on a map.

What to build, in order of value:

1. **Multiple overlapping falloff centres** instead of one, so the landmass is
   lobed and elongated rather than circular.
2. **Domain-warped mask** — offset the falloff's sample position by
   low-frequency noise, which turns a smooth coast into headlands and bays for
   almost nothing.
3. **Inland lakes.** Erosion already leaves closed pits (see the tracer's
   `max_climb_steps` note); flood the ones below a size threshold and give
   them a flat water surface. Free scenery from a system that already runs.
4. **Cliffs.** A separate steepness mask so some coast drops sheer into the
   sea instead of shelving. Beware: steep slopes are what caused the terrain
   holes historically — keep the winding correct and do not reach for
   `cull_disabled`.

---

## 8. Ideas proposed and approved, not yet scheduled

- **Paths wear themselves in.** Do not author tracks — count where villagers
  actually walk and replace grass with packed earth there. After half an hour
  of play the map tells you what the village does. Cheap: one wear map, the
  same shape as the erosion flow map.
- **Rumour instead of telepathy.** A village knows only what it has seen. A
  miracle travels to the next village with people, over days. This makes
  missionaries meaningful and lets Louhi work quietly.
- **Famine as story.** A bad winter empties the stores, and the player either
  feeds them or watches. The sacrifice taboo becomes a real temptation rather
  than a button.
- **Craft as knowledge.** A workyard invents a *recipe* the village remembers
  and can lose if the master dies untaught. Neighbours can learn it.
- **Personalities.** Two or three traits per villager (timid, greedy, devout)
  shifting job choice and reaction to the god. Costs almost nothing and stops
  the village reading as one uniform mass.

---

## 9. If you are an AI taking this over

- Read §3 before touching anything visual. It will save you a day.
- Work in small commits and push often (§0).
- Do not trust a comment that says something is fine — several in this
  codebase were confidently wrong and cost days (`"under the island and never
  visible anyway"`, `"winding chosen so … cull_back keeps the topside"`).
  Verify by measurement.
- State plainly what you did not verify. This project's documentation is
  honest about its gaps on purpose, and that is what makes it usable.
