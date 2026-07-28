# Package G — Villager AI: work, family, prayer

## What's here

- `actors/villagers/villager.gd` — `class_name Villager`, a `CharacterBody3D`.
  A utility-AI-lite state machine (`enum State`: `IDLE, FISHING, FIELD,
  WOODCUTTING, BUILDING, FAMILY, PRAYING, COLLAPSED, DEAD`) that owns a
  villager's job assignment, wandering, pair-bonding/reproduction, and
  prayer/fatigue/collapse/death loop.
- `actors/villagers/villager.tscn` — the mortal itself: a tinted capsule
  ("Body") with a small sphere ("Head") for a second tint slot, a
  `CollisionShape3D`, and a billboarded `Label3D` state debug tag. Honestly
  low-poly and admittedly placeholder — see "Scoped out" below.
- `actors/villagers/calling_stone.gd` — `class_name CallingStone`, a
  `StaticBody3D`. A fixed cairn with a liftable "dial" whose height (0..1
  ratio) sets how many villagers, across every linked village, get pulled
  into prayer. Ticks a priority-ordered assignment pass every 0.5s.
- `actors/villagers/calling_stone.tscn` — the stone's geometry (base +
  guide rod + dial knob).
- `actors/villagers/village_demo.gd` + `village_demo.tscn` — a runnable demo
  scene: registers three small test `Village` resources (one per culture —
  Fenrayt, Sankiln, Raimborn — 4 villagers each, 12 total), spawns them
  around one shared `CallingStone`, and presets the dial to 0.4 so the
  mechanic is visibly active immediately on load. Includes its own
  placeholder ground plane, sun, and camera so it can be opened and
  screenshotted standalone without depending on `world/terrain` (package B)
  or `world/god_view.tscn`.

## How it integrates with the foundation APIs

- **`core/village.gd` (`Village.jobs`)** — the *only* place any of these
  scripts writes to a village's `jobs` Dictionary is `Villager._assign_job`
  and `Villager._release_job_bucket_to_idle`, both of which always
  decrement the old bucket and increment the new one in the same call, so
  `sum(village.jobs.values()) == village.population` is an invariant that
  never drifts, including across births, deaths, and calling-stone pulls.
- **`core/game_state.gd`** — `GameState.get_village`/`register_village` for
  lookup/creation (demo only registers, never fabricates duplicate
  villages); `GameState.add_devotion` is called from every praying and
  every working/idling villager (see "Devotion accrual" below);
  `GameState.earn_epithet` is called (idempotently — `GameState`'s own
  implementation already no-ops on a repeat string) the first time a
  villager dies from forced prayer; `GameState.village_lost.emit(id)` is
  emitted directly (Godot 4 lets any holder of a `Signal` call `.emit()` on
  it) if a village's population is driven to zero by prayer deaths — a
  deliberate reuse of that signal for "this settlement has been wiped out,"
  not only "converted to Louhi," since nothing else currently emits it for
  that case and downstream listeners (Sanctum, HUD-less UI, campaign) need
  *some* signal to know a village is gone.
- **`core/naklon.gd`** — `Naklon.shift(0.03, 1.0)` fires once per villager
  death caused by forced prayer. Small and deliberate: letting people
  collapse and recover is free; forcing an already-collapsed worshipper
  back to the stone until they die is the one action in this package coded
  as cruelty. Ordinary prayer, fatigue, and recovery never touch Naklon.
- **`systems/faith/reach.gd`** — every praying villager calls
  `Reach.effectiveness(village_id, &"calling_stone_prayer")` to scale their
  devotion contribution and `Reach.register_use(village_id,
  &"calling_stone_prayer")` on the same tick (every `PRAYER_TICK_INTERVAL`
  = 2.5s per villager, not every frame), so hammering the calling stone
  nonstop on one village genuinely suffers the same miracle-fatigue curve
  Reach already implements for every other conversion method — the
  Calling Stone is "just another method" from Reach's point of view, method
  id `&"calling_stone_prayer"`.
- **`systems/voices/voices.gd`** — see trigger table below. All calls are
  safe no-ops right now since `systems/voices/voice_lines.gd` is still
  package M's stub (`pick_pair` always returns `[]`); wiring is real and
  ready for M to fill in.

## Job-bucket mapping (documented deliberately, since it's a compromise)

`core/village.gd`'s `jobs` Dictionary has exactly six keys: `fishing,
field, woodcutting, building, family, idle`. There is no `praying` key, and
this package cannot add one without editing a foundation file it doesn't
own. So: **a villager who is `PRAYING` or `COLLAPSED` is counted in the
`idle` bucket** for as long as they're off their regular job — the bucket
change happens once, at the moment they're first pulled off a job, and
reverses once, at the moment they either return to a job or die. This
keeps the population-bucket invariant intact and is honestly documented
here rather than silently implied by reading the code.

## The prayer / fatigue / collapse / death loop

1. `CallingStone._update_assignment` runs every 0.5s per linked village. It
   computes `target = clamp(village.calling_stone_target, 0, population)`
   (that field is written by `CallingStone.set_target_ratio`, driven by the
   dial) and fills it in priority order: **keep already-praying villagers →
   idle → family-pairing → working (fishing/field/woodcutting/building)**.
   Only if the target still isn't met (i.e. the player has set it above the
   entire healthy population) does it reach into the **collapsed** pool and
   force them back up early — the deliberate risk path.
2. While `PRAYING`, `prayer_fatigue` (0..1 float on the villager) rises at
   `0.045`/s (~22s to max). Every 2.5s it ticks a `Reach`-scaled devotion
   contribution into `GameState.add_devotion` and calls
   `Reach.register_use`. Once fatigue crosses `0.7`, each second rolls an
   increasing chance (up to `0.35`/s at fatigue = 1.0) of collapsing.
3. `COLLAPSED` villagers lie down (visually — see posture below), stop
   contributing devotion, and recover over `14s`, at which point they go
   back to `IDLE` and get auto-assigned to whichever job bucket currently
   has the fewest workers.
4. If the calling stone forces a **still-collapsed** villager back to
   prayer (only happens when supply of healthy villagers is exhausted),
   there's an `18%` chance per forced attempt that they die instead of
   resuming prayer. Death: population -1, `Naklon.shift(0.03)`,
   `Voices.react(&"villager_died_praying", …)`, `GameState.earn_epithet`,
   and (if population hits 0) `GameState.village_lost.emit(id)`.

## Devotion accrual

- **Actively praying**: `DEVOTION_RATE_PRAYING = 0.6`/s, scaled by
  `Reach.effectiveness`, ticked every 2.5s.
- **Working or idling**: a much smaller ambient trickle,
  `DEVOTION_RATE_WORKING = 0.08`/s, ticked every 4s — representing
  background faith from a people who still believe even while their hands
  are busy, per the brief's "scaled down while they're also working."
  `FAMILY` state counts as "working" for this purpose.
- Collapsed/dead villagers contribute nothing.

## Family / reproduction

Villagers assigned the `family` job bucket look for an unpaired `FAMILY`
villager of the same village within 6m and pair up (`Villager.partner`,
bidirectional). The lower-`instance_id` partner in a pair ticks a 20s
gestation timer; on completion `village.children += 1` and
`Voices.react(&"village_child_born", …)` fires, then a 40s maturation timer
starts. On maturation, `village.children -= 1`, `village.population += 1`,
a brand-new `Villager` node is instantiated (`village_demo.gd`'s own
`Villager.tscn`/`VILLAGER_SCENE` constant, reused by the villager script
itself) at the parent's position with `initial_job = &"idle"`, and
`Voices.react(&"village_child_matured", …)` fires. A pair can conceive
again after a 30s cooldown. This means population genuinely grows over a
long enough play session, with new visible bodies, not just a number
ticking up.

## Voices trigger names (for package M)

All calls pass a `context: Dictionary` with at least `village_id` and
`culture_id` (both `StringName`):

| Trigger | Fires when |
|---|---|
| `&"villager_collapsed"` | A praying villager's fatigue roll causes a collapse. |
| `&"villager_forced_to_kneel"` | The calling stone drags an already-collapsed villager back to prayer and they survive the death roll. |
| `&"villager_died_praying"` | A forced-while-collapsed death roll kills the villager. |
| `&"village_child_born"` | A family pair completes gestation. |
| `&"village_child_matured"` | A child finishes maturation and becomes a new population-counted `Villager` node. |

## Culture-tinted placeholder mortals

`Villager._apply_culture_tint` reads `GameState.cultures[culture_id]`
(`color_primary`/`color_accent`) and builds two runtime
`StandardMaterial3D`s — one for the capsule "Body" (primary) and one for
the sphere "Head" (accent) — per villager instance. This is an honest,
deliberately simple placeholder: **capsule-and-sphere low-poly mortals, no
sculpted geometry, no clothing silhouette, no animation beyond a
scale/rotation "posture" swap** (kneeling = squashed capsule lowered
slightly; collapsed = capsule rotated ~85° to lie down). It reads at a
glance and is honest about being a placeholder rather than pretending to
be finished art.

## Movement

No `NavigationAgent3D` / baked `NavigationRegion3D` is used. At the time
this package was built, `world/terrain` (package B) had not yet landed and
no navmesh exists anywhere in the project, so a `NavigationAgent3D` would
either silently fail to path or require this package to bake its own
navmesh over ground geometry it doesn't own. Instead, `Villager` steers
directly toward `target_position` on a `CharacterBody3D` with simple
gravity, assuming flat, walkable ground (true for `village_demo.tscn`'s own
placeholder ground plane). This is stated as a real limitation, not hidden:
**if package B's terrain has real slopes/obstacles by the time villagers
are placed on it, this package's direct-line steering will need a
navmesh-based follow-up pass** — flagged here rather than silently
claimed as finished.

## The Calling Stone as a "draggable-by-Hand" object

`actors/hand/` (package E) had not landed yet either. `CallingStone`
exposes the integration point package E needs — `hand_drag(delta_ratio:
float)`, to be called once per frame while the Hand is gripping the dial —
without needing to know anything about the Hand's own grip/gesture
implementation. Until the Hand exists, `CallingStone` also implements its
own minimal standalone left-click-drag-vertically mouse fallback
(`_input_event`/`_input`) purely so this package's own demo scene is
interactive and screenshot-testable without package E.

## Scoped out

- **Real navmesh-based pathing.** See "Movement" above — direct steering
  only, documented limitation, not a silent stub.
- **Skeletal animation / IK.** Posture is communicated by scale + rotation
  of a placeholder capsule, not bone-driven animation. A real rigged mortal
  model is out of scope for a single build pass with no art pipeline.
- **Spawning actual new job sites/buildings.** `Village.buildings` is read
  nowhere in this package; job "anchors" are fixed offsets from
  `village.position_on_island`, not derived from actual placed building
  meshes (there are none yet — `world/sanctum`, economy buildings, etc.
  belong to other packages).
- **Per-child individuality.** Matured children spawn as an ordinary
  `Villager` with a random job, not a distinguishable "grew up here" trait.
- **Multiple calling stones / per-village stones.** `CallingStone` supports
  an array of `village_ids` so one stone can serve several villages (used
  by the demo to gather three cultures around one stone); a full campaign
  will likely want one stone per village instead, which is a config change
  (`village_ids = [single_id]`), not a code change.
- **Sound.** No audio (footsteps, chanting, collapse groan) is wired up;
  `audio/` is package R's.

## Assets used

None. Every mesh in this package (capsule/sphere mortals, cairn dial
stone, placeholder ground plane, village markers) is procedurally
generated `PlaneMesh`/`CapsuleMesh`/`SphereMesh`/`CylinderMesh` primitives
with `StandardMaterial3D` colors, built directly in the `.tscn` files or at
runtime from `Culture` data — no external CC0/licensed asset downloads
were needed for this pass.
