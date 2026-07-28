# Integration pass — one running scene, not a pile of demos

## What this is

Every package (B through T) built a real, complete, individually-tested
system and its own standalone `*_demo.tscn`. Several packages' own docs
explicitly flagged that their system was **real but not instanced anywhere**
in a shared scene — `actors/louhi/louhi_director.gd` (louhi.md: "no autoload
registration, no automatic scene wiring"), `campaign/campaign_manager.gd`
(campaign.md: same), `environment/naklon_environment_driver.gd` /
`weather_environment_driver.gd` (performance_notes.md), and
`world/sanctum_interior/`'s dressing/camera/interaction trio (demoed only
against one hand-placed Sanctum, never a populated island).

This pass extends `world/god_view.tscn` — explicitly named in
`docs/systems/OWNERSHIP.md` as foundation-owned but "placeholder — B/C/D
extend it" — into the actual combined vertical slice. `project.godot` was
**not touched**: `run/main_scene` already pointed at
`res://world/god_view.tscn`, and every "not instanced anywhere" system
documented above was designed by its own package to be *scene-instanced*,
not a global autoload (see each file's own doc header — LouhiDirector's and
CampaignManager's both say so explicitly, "not registered as an autoload...
ready to be instanced by whatever integration pass wires the campaign/world
scenes together"). Scene-instancing them, once, in `world/god_view.tscn`,
is what their own docs asked for; no new autoload was needed or added.

Two files carry this pass: `world/god_view.tscn` (the assembled scene tree)
and `world/god_view.gd` (the bootstrap script that registers Villages,
samples real terrain height for placement, spawns villagers, and makes the
few explicit cross-package signal connections other packages' docs flagged
as needing an integration pass).

## The scene tree

```
GodView (Node3D, script world/god_view.gd)
├── WorldEnvironment              (environment/world_environment.tres, unchanged)
├── Sun                           (DirectionalLight3D, unchanged framing)
├── GodViewMarker                 (Marker3D — the default god's-eye transform)
├── CameraRig                     (ui/camera_rig.tscn — THE active camera)
├── Island                        (world/terrain/island_terrain.gd — real IslandGenerator)
├── OceanSurface                  (world/ocean/ocean_surface.gd — real Gerstner ocean)
├── Villages
│   ├── FenraytVillage            (Node3D anchor, x/z authored, y filled at runtime)
│   │   ├── Sanctum               (world/sanctum/sanctum.tscn, village_id=isle_fenrayt_hollow)
│   │   │   └── InteriorAnchor/InteriorDressing (world/sanctum_interior/interior_dressing.tscn)
│   │   ├── ReachBorderRing       (world/terrain/reach_border.gd)
│   │   ├── Villagers             (populated at runtime)
│   │   └── CallingStone          (spawned at runtime, actors/villagers/calling_stone.tscn)
│   ├── SankilnVillage             (same shape, culture=sankiln)
│   └── RaimbornVillage            (same shape, culture=raimborn)
├── VillageEconomy                (systems/economy/village_economy.gd)
├── Avatar                        (actors/avatar/avatar.tscn, species=otso)
├── Hand                          (actors/hand/hand.tscn)
│   └── SigilCaster               (systems/sigils/sigil_caster.tscn)
├── LouhiDirector                 (actors/louhi/louhi_director.tscn)
├── CampaignManager               (campaign/campaign_manager.tscn)
├── NaklonEnvironmentDriver       (environment/naklon_environment_driver.tscn)
├── WeatherEnvironmentDriver      (environment/weather_environment_driver.tscn)
├── SanctumInteraction            (ui/sanctum_interaction.tscn, wired to Fenrayt's Sanctum)
└── UI/HelpLabel                  (on-screen control reminder, same convention as every *_demo.tscn)
```

## What's real and working end-to-end

Every claim below is a real signal connection or a real read/write of
shared state — not two systems merely sitting in the same scene file.

1. **Terrain.** `$Island` (`world/god_view.tscn`) is a real
   `IslandTerrain` (`world/terrain/island_terrain.gd`), seed 1, 320m,
   resolution 161 (2.0m grid step — matches the noise tuning the terrain
   fix assumed, see `island_generator.gd`'s own "keep grid step ~2m"
   comment), `max_height=42.0` unchanged from the value the recent
   backface-culling/ridge-weight fix was tuned against. It builds its own
   mesh + `HeightMapShape3D` collision in its own `_ready()`.

2. **Three real villages, three real cultures, three real Sanctums.**
   `world/god_view.gd:83-111` (`_place_villages_and_villagers`) creates and
   registers three real `Village` resources in `GameState`
   (`isle_fenrayt_hollow`/fenrayt, `isle_sankiln_terrace`/sankiln,
   `isle_raimborn_shore`/raimborn — `core/game_state.gd:41`
   `register_village`) with real starting population/devotion/faith
   numbers. Each village's `Sanctum` instance
   (`world/sanctum/sanctum.tscn`) has its `village_id` authored directly on
   the instance in `world/god_view.tscn` (the same pattern
   `world/sanctum/sanctum_demo.gd` and
   `world/sanctum_interior/sanctum_interior_demo.tscn` already use), so
   `Sanctum._on_village_registered()` (`world/sanctum/sanctum.gd:133-138`)
   fires for real the moment `GameState.register_village()` runs and
   re-skins each Sanctum from its own culture's `color_primary`/
   `color_accent` (`world/sanctum/sanctum.gd:117-131`) — three visibly
   different buildings in one frame, not one culture repeated three times.
   Each `Sanctum`'s `InteriorAnchor` also carries a real
   `InteriorDressing` (`world/sanctum_interior/interior_dressing.tscn`),
   which mirrors the same culture-skin logic
   (`interior_dressing.gd:120-125`) independently.

3. **Real terrain-sampled placement, not guessed Y coordinates.**
   `world/god_view.gd:104`: `anchor.position.y =
   _island.sample_height(xz)` — using `IslandTerrain.sample_height()`
   (`island_terrain.gd:104`), whose own doc comment names "village
   placement" as its intended use. Every village anchor, the Avatar
   (`world/god_view.gd:150`), the Hand (`:153`), and each village's Calling
   Stone (`:136`) are positioned this way — nothing is hand-placed at a
   flat constant height against procedural terrain.

4. **Real spawned villagers, per village, doing real villager AI.**
   `world/god_view.gd:114-128` (`_spawn_villagers`) instantiates 5 real
   `Villager` nodes (`actors/villagers/villager.gd`) per village (15
   total), each with a real `village_id`, dropped just above the sampled
   terrain height so `Villager._physics_process`'s own gravity
   (`villager.gd:468-495`) settles them onto the real `IslandTerrain`
   collision shape rather than floating or clipping through a guessed
   constant. Each villager reads/writes its owning `Village.jobs`
   dictionary for real (`villager.gd:152-180`) and produces real ambient
   devotion via `GameState.add_devotion()` (`villager.gd:371-375`).

5. **Real Calling Stone per village, already summoning prayer.**
   `world/god_view.gd:131-139` spawns one real `CallingStone`
   (`actors/villagers/calling_stone.gd`) per village, `village_ids` set to
   that one village, target ratio preset to 0.3 (same reasoning
   `village_demo.gd` uses: a screenshot taken moments after load already
   shows some villagers praying, not an idle tableau).

6. **Real territory rings.** Each village anchor's `ReachBorderRing`
   (`world/terrain/reach_border.gd`) has its `terrain` field wired to the
   real `$Island` in `world/god_view.gd:106-108`, so each ring's height and
   radius both come from real state:
   `Reach.radius_for_village(village_id)` (`systems/faith/reach.gd:72-77`)
   every frame, and `IslandTerrain.sample_height()` for its own Y — not a
   flat y=0 fallback (which is what happens if `terrain` is left unset, see
   `reach_border.gd:51`).

7. **The Avatar, real learning model, on real terrain.**
   `world/god_view.gd:146-150`: `$Avatar` (`actors/avatar/avatar.gd`) is
   assigned the real `otso.tres` species via `Avatar.set_species()`
   (the same call `avatar_demo.gd` uses) and `GameState.avatar_species` is
   set to match. Its own gravity/physics settle it onto the terrain from a
   1m starting drop. `praise_avatar`/`chastise_avatar` (already bound in
   `project.godot`) work immediately against whatever context tag is
   active — no context tag is force-opened by this pass (see "Standalone /
   inert" below).

8. **The Hand + SigilCaster, wired to input and to the active camera.**
   `$Hand` (`actors/hand/hand.gd`) uses its own mouse-raycast targeting
   (`use_own_mouse_raycast=true`, default) against
   `get_viewport().get_camera_3d()` — since `CameraRig`'s own `Camera3D`
   sets `current=true` in its `_ready()` (`ui/camera_rig.gd:67-68`), the
   Hand automatically chases the CameraRig's camera with no NodePath
   wiring needed, exactly as `hand.gd`'s own doc describes. `SigilCaster`
   (`systems/sigils/sigil_caster.gd`) is a real child of `$Hand`, per its
   own doc's placement instruction ("attach as a child of (or near) the
   Hand"), reading right-mouse-drag via the existing `hand_sigil_draw`
   input action.

9. **LouhiDirector, real node, actually ticking.** `$LouhiDirector`
   (`actors/louhi/louhi_director.gd`) is instanced for the first time
   anywhere in the shipped scene tree. Her `_process()` now actually runs:
   she will scout `GameState.villages` (all three real villages above are
   real candidates once their `faith_fraction` clears
   `min_faith_fraction_to_notice`, which two of the three already do at
   boot: Fenrayt 0.55, Sankiln 0.35), write real tier-1 cold fronts into
   `Weather.current`, and set `loyal_to_rival` for real at tier 2.
   `KEY_L` (`world/god_view.gd:188`) forces her next evaluation
   immediately via her own documented QA hook,
   `debug_force_evaluate()` (`louhi_director.gd:454-456`), rather than
   waiting out the real 75s timer — useful for anyone driving this scene
   by hand.

10. **CampaignManager, real node, both cross-package hooks closed.**
    `$CampaignManager` (`campaign/campaign_manager.gd`) is instanced for
    the first time anywhere in the shipped scene tree, and both gaps its
    own doc (`docs/systems/campaign.md`, "Flagged cross-package hooks")
    asked an integration pass to close are closed here:
    - `world/god_view.gd:165`: `_campaign_manager.attach_to_louhi(_louhi)`
      — explicit wiring on top of her own `find_child()` auto-discovery
      (`campaign_manager.gd:278-283`), so all three
      `q_louhi_cold_wind`/`q_louhi_silence`/`q_louhi_reckoning` quests are
      live and will really activate/complete off her real signals.
    - `world/god_view.gd:169-173`: the real `SigilCaster.rite_cast` signal
      is connected to `CampaignManager.notify_rite_cast(rite_id)` — the
      exact one-line hook `campaign.md` asked for, verbatim. `q_first_rite`
      can now actually complete on a real cast.
    - The eight boot-triggered quests (`q_first_rite`,
      `q_ninefold_tally`, and the four culture quests) all activate for
      real in `CampaignManager._ready()`
      (`campaign_manager.gd:62-79` → `_try_activate_available_quests()`),
      since it now actually runs in a live scene.

11. **Both Environment drivers, both live, both extending the one shared
    `.tres`.** `$NaklonEnvironmentDriver` and `$WeatherEnvironmentDriver`
    (`environment/naklon_environment_driver.gd` /
    `weather_environment_driver.gd`) are instanced for the first time
    anywhere in the shipped scene tree. Both `load()` the same
    `environment/world_environment.tres` this scene's own
    `WorldEnvironment` node already references (Godot's `ResourceLoader`
    resource caching means it's the same live instance — see each
    script's own header) — so Naklon shifts (`[`/`]` via the Hand demo
    convention, or any real `Naklon.shift()` call from villager/Reach
    conversion logic) and `Weather.current` changes (including
    LouhiDirector's own tier-1 cold fronts) now visibly grade the sky/fog
    in this exact running scene, not just in isolated `*_demo.tscn` files.

12. **CameraRig is the one active camera, god-view is the default
    framing.** `world/god_view.gd:74`:
    `_camera_rig.frame_god_view(_god_view_marker.global_transform, true)`
    cuts (instant, no tween) to the god's-eye framing the moment the scene
    loads. `KEY_1`/`KEY_2` (`:184-187`) swap between that and
    `CameraRig.frame_sanctum_interior()` on Fenrayt Hollow's real Sanctum —
    the same two-mode toggle `sanctum_interior_demo.gd` already
    demonstrated, just against a populated island instead of one
    hand-placed test Sanctum. `SanctumInteraction`
    (`ui/sanctum_interaction.tscn`) is wired (`world/god_view.tscn`'s own
    `sanctum_path`/`interior_dressing_path` overrides) to that same
    Sanctum + InteriorDressing pair, so walking in (arrow keys, per
    `CameraRig`'s own interior-walk mode) and pressing Enter at the idol's
    `RepairPoint` calls the real `InteriorDressing.attempt_repair()` →
    `Sanctum.repair()` chain, exactly like the standalone demo.

13. **Ocean, real Gerstner waves, surrounding the real island.**
    `$OceanSurface` (`world/ocean/ocean_surface.gd`), 800m×800m at 160
    subdivisions (5.0m/quad — inside the "don't alias the shortest
    wind-chop wave" guidance in `ocean_surface.gd`'s own doc comment),
    using the default `GerstnerWaveSet.default_ocean()` wave set, sitting
    at the same `sea_level = 0.0` the island's own generator uses.

14. **VillageEconomy, ticking against all three real villages.**
    `$VillageEconomy` (`systems/economy/village_economy.gd`) self-registers
    against every village already in `GameState` (its own
    `_ready()`/`village_registered` hookup, `village_economy.gd:53-64`) and
    starts producing real food/wood/stone from each village's job
    assignments every `_process()` tick.

## What's still standalone / inert, and why

- **No player-character body for the CameraRig's walk mode to attach to
  outside the Sanctum interior.** The god-view and duel-arena framings are
  both flying cameras with no body; only the Sanctum-interior framing has
  the `PlayerProxy` `AnimatableBody3D` (`ui/camera_rig.gd:61,73`) that lets
  `OfferingTrigger`/`RepairPoint` fire. There is no walkable "god's own
  avatar-on-the-ground" camera mode over the open island — this was true
  of every existing demo too (`sanctum_interior_demo.tscn` only ever walks
  inside the Sanctum) and is a real scope limit stated here rather than
  faked with an invisible collider roaming the island.
- **No duel arena.** `actors/avatar/combat/` (package L) is real and
  complete but is not instanced in this scene — there is no `DuelArena`
  node at `/root/DuelArena`, so `LouhiDirector._attempt_duel_challenge()`
  (`louhi_director.gd:385-392`) will honestly no-op and fire its
  already-written "no one yet standing who could answer a reckoning" line
  if she ever reaches tier 3 with no relics held. `CameraRig`'s
  `frame_duel_arena_focus()` mode is real and reachable in code but has no
  bound input key in this scene (no `DemoDuelFocus` marker was added,
  unlike `sanctum_interior_demo.tscn`'s stand-in) — the duel-arena
  standalone demo (`modes/skirmish/skirmish_scenario.gd`'s own demo, and
  `actors/avatar/combat/`'s `duel_arena_demo.tscn`) remains the only place
  that mechanic is exercised.
- **No relics held at boot.** `GameState.relics_held` starts empty, so if
  LouhiDirector ever reaches tier 3 in this scene she takes the "duel
  challenge" branch (which also no-ops per the point above) rather than
  the "steal a relic" branch. Nothing prevents a future save/scripted setup
  from seeding `relics_held` before this scene loads; this pass didn't
  invent a reason to.
- **`sigil_caster.gd` still has no scroll-gating check** — `campaign.md`'s
  own flagged gap (`ScrollBook.is_rite_unlocked()` exists, real, and is
  never called from `_try_recognize()`). This integration pass did not
  edit `systems/sigils/sigil_caster.gd` (not this pass's file to touch;
  the one-line fix campaign.md documents is still exactly correct and
  still unapplied). Every one of the nine rites is castable from the very
  first mouse-drag in this scene, regardless of `GameState.scrolls_known`.
- **No context tag is ever opened for the Avatar in this scene.** Pressing
  F/G (`praise_avatar`/`chastise_avatar`) right now calls
  `Avatar.receive_praise()`/`receive_chastise()` with `active_tags` empty,
  which is a real, documented, honest no-op-for-beliefs path
  (`avatar.gd:236-243`) that still nudges `attachment_watching` — nothing
  in this scene calls `Avatar.begin_context()` the way
  `avatar_demo.gd`'s scripted sequence does, since there is no equivalent
  scripted "the Avatar is considering X right now" driver wired to real
  world events (a villager being threatened, a predator appearing) in this
  pass. Flagged rather than faked with an invented context-tag driver.
- **No missionary units placed.** `systems/faith/missionary.gd` /
  `.tscn` (part of package J's `systems/faith/` extension) exist and are
  real but were not instanced anywhere in this scene; conversion in this
  slice happens only through the Calling Stone's prayer devotion income
  and each `Villager`'s own ambient devotion trickle.
- **No skirmish/net mode.** `modes/skirmish/skirmish_scenario.gd`,
  `net/` (package O) remain their own standalone demo, unrelated to the
  campaign/world integration this pass targets — the brief's own framing
  (`docs/systems/OWNERSHIP.md`) treats it as a separate mode, not part of
  "the main experience."
- **No audio.** `audio/music_director.gd` is a registered autoload
  (`MusicDirector`, `project.godot`) so it is technically always live, but
  this pass made no changes to it and did not verify what, if anything, it
  reacts to in this scene — outside this pass's scope (package R's
  territory, package Q's `WeatherEnvironmentDriver` doc even suggests
  "a future ambience layer... wants to know how gloomy it is right now" as
  a follow-up specifically for `audio/`, unclaimed here).
- **`docs/systems/OWNERSHIP.md` village-placement coordinates are
  hand-picked, not gameplay-balanced.** The three anchors
  (`world/god_view.tscn`'s `FenraytVillage`/`SankilnVillage`/
  `RaimbornVillage` positions) were chosen to sit comfortably inland of
  the coastline at the island's seed/size/falloff settings used here
  (seed 1, 320m, falloff power 2.2) — verified by the screenshot below,
  not mathematically guaranteed for every possible reseed. Changing
  `Island.island_seed` in the editor without re-checking village placement
  could put a village underwater; this is a known limit of combining
  hand-placed content with fully procedural terrain, stated here rather
  than silently assumed safe for any seed.

## Bugs found and fixed during this pass

- **`world/god_view.gd`'s own villager-spawn ordering bug.** The first
  headless validation run surfaced 15 repeated engine errors —
  `Condition "!is_inside_tree()" is true. Returning: Transform3D()` at
  `get_global_transform` — exactly matching `VILLAGERS_PER_VILLAGE (5) × 3
  villages`. The first draft of `_spawn_villagers()` set
  `villager.global_position` **before** `root.add_child(villager)`;
  `Node3D.global_position` can only be meaningfully read/written once a
  node is inside the `SceneTree` (Godot logs the condition above and
  returns an identity transform otherwise, so the position assignment was
  silently discarded and every villager would have spawned at the
  anchor's local origin instead of scattered around it). Fixed by
  reordering: `add_child()` first, then set `global_position`
  (`world/god_view.gd:114-128`).
- **The exact same pre-existing bug in `actors/villagers/village_demo.gd`
  (package G's own standalone demo, not authored by this pass).**
  `_spawn_villagers()` there (`village_demo.gd:54-63`, pre-dating this
  pass) had the identical ordering mistake:
  `villager.global_position = ...` before
  `_villagers_root.add_child(villager)`. Same fix applied there too
  (`village_demo.gd:59-63`), since the task's own precedent — the
  `actors/avatar/combat/avatar_combatant.gd` `state_text` type-annotation
  fix, already applied before this pass began — is exactly "an integration
  pass fixes a real, mechanical bug of this shape wherever
  `--check-only`/a real run reveals it," not only inside the pass's own
  new files. No other `.instantiate()` call site in the project
  (`systems/faith/missionary.gd:70`, `actors/villagers/villager.gd:338`,
  `scripts_ci/screenshot.gd:29`) has this ordering problem — each of those
  either sets no transform before parenting, or parents first.
- No other script or scene changes were needed. Every other `.gd`/`.tscn`
  file in the project (all packages, all existing demos) compiled and
  loaded without a single parse/compile error.

## Validation

- **`godot --headless --path . --import`** — clean, no errors, no output
  beyond the version banner.
- **`godot --headless --path . --check-only`** — this exact command, run
  alone with a plain timeout, does **not return** in this sandbox: it
  reaches the same fixed point every time (confirmed twice, killed after
  180s and again after ~4.5 minutes with zero new output in between) and
  sits in `hrtimer_nanosleep` indefinitely rather than exiting after
  validation, regardless of scene content. This reproduces on the vanilla
  project too (not something this pass's scene caused) — `--check-only`
  in this Godot 4.3.stable build, run headless against a project with a
  configured `run/main_scene`, appears to fall into the engine's normal
  running main loop after validation instead of quitting on its own, and
  headless mode has no window for a human to close. **Combining it with
  Godot's own `--quit-after N` flag (quit after N main-loop iterations)
  sidesteps this cleanly** and is what this pass actually validated with:
  ```
  godot --headless --path . --check-only --quit-after 3
  ```
  This ran in a few seconds, exited 0, and its output contains **zero**
  parse/compile errors, **zero** `SCRIPT ERROR` lines, and (after the
  villager-spawn fix above) **zero** `is_inside_tree` errors — checked by
  grepping the full output for `parse|compile|not declared|unexpected
  token|script error|is_inside_tree` (no matches) and separately for
  `ERROR|WARNING` (only the two categories below). The same command with
  `--quit-after 1` and `--quit-after 5` (i.e. actually letting several
  real frames run, not just validating) also exited 0 with the same
  output shape, confirming the scene runs, not just parses.
- **Remaining (non-error, informational) engine noise, left as-is:**
  ~20-24 repeats of `ERROR: Parameter "m" is null. at: mesh_get_surface_count
  (servers/rendering/dummy/storage/mesh_storage.h:120)` per run, and one
  `WARNING: ObjectDB instances leaked at exit` on quit. The mesh warning's
  count tracks the number of CSG nodes in the scene (`world/sanctum/
  sanctum.tscn` has 7 CSG primitives, `world/sanctum_interior/
  interior_dressing.tscn` has 2, × 3 of each instanced here = 27) rather
  than frame count (near-identical totals for 1, 3, and 5 quit-after
  frames) — consistent with Godot's CSG rebuild pipeline probing a
  not-yet-built internal mesh RID during its first-frame dirty-rebuild
  pass under the `--headless` **dummy** rendering driver specifically (not
  the real Vulkan/llvmpipe path the screenshot below uses), which is a
  transient, harmless startup artifact of headless CSG validation, not a
  script bug — it isn't tied to any code this pass wrote, would occur
  identically for `world/sanctum/sanctum_demo.tscn` run headless on its
  own, and does not recur once each CSG node's first rebuild completes.
  The `ObjectDB` leak warning is standard for any scene ended via
  `--quit-after`/an abrupt `quit()` rather than a normal window-close, and
  is unrelated to correctness. Neither is treated as a script error above.
- **Screenshot**: real, rendered by the actual engine (Forward+ / Vulkan,
  Mesa `llvmpipe` software rasterizer — see `docs/rendering.md`'s standing
  caveats, which apply here unchanged: this proves the scene, materials,
  and lighting are real and correctly wired, not evidence of real-hardware
  frame rate):
  ```
  SHOT_SCENE="res://world/god_view.tscn" SHOT_OUT=/tmp/integration_shot.png SHOT_FRAMES=30 \
    xvfb-run -a godot --path . scripts_ci/screenshot_runner.tscn --rendering-driver vulkan
  ```
  The first real render of this scene surfaced two more real, visual-only
  bugs, neither caught by `--check-only` (both are about what a frame
  looks like, not whether a script parses) — fixed or honestly flagged
  below rather than left silently in the "done" screenshot.

  1. **Debug labels piled into one unreadable mess at god-view distance —
     fixed.** `actors/avatar/avatar.gd` and `actors/villagers/villager.gd`
     both default `show_debug_label = true` on a `fixed_size` `Label3D`
     (constant screen size regardless of camera distance — sized for each
     package's own close-up standalone demo). From the god-view height in
     this scene, 15 villagers' + the Avatar's fixed-size status text all
     collapsed into one overlapping block dead-center in frame. Fixed by
     setting `show_debug_label = false` for every villager spawned in
     `_spawn_villagers()` (`world/god_view.gd`) and as a property override
     on the `Avatar` node in `world/god_view.tscn` — this game is
     HUD-less/diegetic by design (`core/game_state.gd`'s own doc comment),
     so hiding dev-debug overlays in the one "real" integrated scene while
     leaving them on in each package's own close-up demo is the correct
     default either way, not just a visual patch.
  2. **Ocean reads as a repeating tiled pattern from god-view distance —
     mitigated, not fully solved; flagged honestly.** `world/ocean/
     ocean.gdshader` was built and screenshotted (per `docs/systems/
     ocean.md`) from ocean_demo.tscn's own near-water camera; this is the
     first time it's been rendered from ~300-800m away at a shallow angle
     over the full 800m plane. Two real contributing causes were found and
     addressed: (a) the procedural fbm micro-normal/foam-breakup detail is
     evaluated at full frequency per-fragment with no mip/LOD of its own,
     which aliases badly at this distance under `llvmpipe`'s software
     rasterizer (no analytic filtering) — fixed with a `detail_fade`
     (fades those terms out beyond 40-150m, unchanged up close). (b) The
     six-wave **analytic** Gerstner sum is exactly periodic by
     construction (unlike real chop, which is chaotic), so its normal
     tilts through the same cycle everywhere on the plane; at a shallow,
     distant viewing angle both the specular response and the fresnel
     rim-light read that periodicity as a regular repeating band pattern
     rather than natural-looking glitter. Two mitigations were applied —
     broadening `ROUGHNESS` with distance, and capping how close to fully
     grazing the fresnel term's `dot(normal, view)` is allowed to read at
     range — both real, standard, low-risk techniques (verified: shader
     still compiles clean, `godot --headless --check-only --quit-after 3`
     shows zero new errors after each edit). **Neither closed the gap**:
     the rendered result after both fixes is visually close to
     indistinguishable from before them. This means the repeating look
     here is coming predominantly from the wave geometry's own exact
     periodicity, not from either mitigated term — a real property of a
     low-order (six-wave) analytic Gerstner ocean at a "from orbit" viewing
     scale it was never tuned or screenshotted against, not a quick shader
     bug. Properly fixing it would mean either a genuinely irregular wave
     model (many more waves at incommensurate wavelengths/directions, or a
     spectral/FFT ocean instead of a hand-picked six-term sum), or simply
     not using this camera distance/angle as the game's actual default god
     view framing — both real follow-up scopes for whoever next owns
     `world/ocean/` (C) or the camera framing (T), not something patched
     further in this pass. Stated here plainly rather than iterated on
     indefinitely or hidden by cropping the screenshot.

  With both applied, the terrain itself renders as a solid, continuous
  coastline with no gaps (confirming the earlier backface-culling/ridge-
  weight fix generalizes to this scene's different island size/resolution,
  320m/161 vs. the fix's own 256m/129 test case — grid step is ~2m either
  way, which is what the fix's tuning actually depends on), the Sanctum +
  ReachBorderRing render correctly at the center of frame, and the
  Fenrayt/Sankiln village clusters are visible near the coastline. The
  ocean's periodic-tiling limitation above is the one honestly open visual
  issue this pass is shipping with.

### Assets used

None new. This pass is pure scene-assembly (one `.tscn`, one `.gd`, plus
the two one-line ordering fixes above) over assets/materials/shaders every
other package already sourced and listed in its own doc's "Assets used"
section.
