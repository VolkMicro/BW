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
   back to `IDLE` and immediately re-score every job (**changed in the
   second pass** — this used to be "whichever bucket has the fewest
   workers"; it is now the full utility evaluation below, run with
   `force = true` so an idle villager never sits out its hysteresis
   margin).
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

---

# Second pass: villagers that actually decide things

Everything above describes the first build of this package and is still
accurate except where explicitly marked. This section documents what the
second pass added, in response to a plain complaint from the person playing
it: *"AI must not only be for enemies — villagers and animals need it too."*
Before this pass, only `actors/louhi/louhi_director.gd` had a real decision
loop; a villager picked a job at random on spawn and only ever reconsidered
while idle, by counting heads. Nothing a villager did was caused by anything
that happened in the world.

Nothing was rewritten. The state machine, the prayer/fatigue/collapse/death
loop, the family loop, the job-bucket invariant and the movement model are
all exactly as documented above; this pass layers three staggered timers and
an event-reaction system on top of them.

## 1. Utility job choice (`Villager._score_jobs` / `_evaluate_jobs`)

Each villager owns a **personal** re-evaluation timer, `randf_range(4.5,
7.0)` seconds, **started at a random phase** (`randf_range(0.4, 7.0)` in
`_ready`). Fifteen villagers therefore spread fifteen job re-scores over
several seconds instead of stacking them on one frame, and — because each
one rolls a fresh interval every time plus a small per-evaluation jitter —
they never re-decide in lockstep or stampede into the same job together.

The score for each of the five real job buckets, all inputs read from
systems that already existed:

| Input | Where it comes from | Effect |
|---|---|---|
| food / wood / stone stored | `systems/economy/stockpile.gd`'s documented `village.get_meta(&"economy_stockpile")` convention + `Stockpile.capacity()` — **read-only, no economy file is written or edited** | empty stores push `fishing`/`field` (food) and `woodcutting` (wood) hard; having both wood and stone in hand makes `building` sensible |
| job crowding | `Village.jobs` occupancy ÷ the **sum of the job buckets** | a bucket already holding most of the workforce scores up to `-1.6` |
| children ÷ population | `Village.children`, `Village.population` | below ~0.35 children per head, `family` gains up to `+1.1` |
| weather | `Weather.current` (`storm_intensity`, `precipitation`, `is_storm`) via `weather_changed`, sampled once at spawn too | `fishing -2.2 × harshness` (worst place to be), `field -1.5`, `woodcutting -0.9`, `building -0.6`, **`family +1.3`** — the one job that gets better in foul weather |
| Sanctum damage | `Village.sanctum_hp / sanctum_hp_max` | `building` gains up to `+2.4` — the strongest single pull in the table |
| faith | `Village.faith_fraction` | small `building` bonus (they tend their own temple) |
| Naklon | `Naklon.value` | cruelty pushes people off the water and into `building`/`family`; mercy favours `family` |

A villager only switches if the winner beats their current job by
`UTILITY_SWITCH_MARGIN` (0.35) — hysteresis, so two near-equal options don't
make a village oscillate. `&"idle"` is deliberately not scored, so an idle
villager always takes work on their next evaluation.

**Observed in a real headless run** of `world/god_view.tscn` (not asserted
from reading the code): villagers spread themselves across
fishing/field/woodcutting by need, and when a storm was forced with
`Weather.debug_spawn_storm_nearby()` every villager not pinned to the
Calling Stone left the water and fields for `family` within one evaluation
cycle, with the crowding term visibly lowering each successive switcher's
score. The temporary probe prints used to observe this were removed before
this doc was written; what remains in the code is the behaviour, not the
instrumentation.

## 2. Real reactions to real events (`Villager.Alert`)

Reactions are a transient `Alert` layered *over* `State`, deliberately not
new `State` values: that keeps `calling_stone.gd`'s priority buckets and the
`sum(jobs) == heads` invariant working untouched. Every reaction moves the
villager and/or changes what they are doing — none of them only sets a flag.

| Signal (all pre-existing) | Reaction |
|---|---|
| `Weather.weather_changed` → storm | `SHELTER` (14s): run to the village centre at ×1.3 speed and immediately re-score jobs, where fishing/field are now terrible |
| `Sanctum.sanctum_damaged(village_id, new_hp, max_hp)` | `RALLY` (12s): take the `building` job, run to the Sanctum at ×1.35 speed, and stay on the repair (non-forced re-scores are skipped for the duration) |
| `Sanctum.sanctum_destroyed(village_id)` | `FLEE` (7s): drop the job, scatter 16 m away from the ruin at ×1.6 speed. **Breaks prayer** — see "hard events" below |
| `GameState.village_lost(village_id)` — own village | `MOURN` (12s): stop dead where they stand (speed ×0) in the kneeling posture. Breaks prayer |
| `GameState.village_lost(village_id)` — another village | `GATHER` (9s): crowd toward their own Sanctum in a ring |
| `Naklon.pole_crossed(+1)` | `DREAD` (6s): back away 7 m from wherever the Hand/Avatar last was, cowering posture, and re-score jobs |
| `Naklon.pole_crossed(-1)` | `GATHER` toward the Sanctum |

**Hard events.** A `COLLAPSED` villager reacts to nothing (they are
face-down). A `PRAYING` villager is owned by the Calling Stone, so ordinary
events do *not* pull them off their knees — but two events do, via
`_can_react(hard = true)`: their Sanctum actually falling, and their own
village being lost. A worshipper whose temple just came down does not keep
kneeling politely.

Each villager finds its own Sanctum by **duck-typing** (a node carrying both
`sanctum_damaged` and `sanctum_destroyed` signals plus a `village_id`), so
this package keeps no parse-time dependency on package I. The lookup is one
shared tree walk for the whole population, at most once per 8 s, and only
while some villager still has no Sanctum bound. In `village_demo.tscn`
there is no Sanctum at all and everything above simply stays quiet.

## 3. Naklon-reactive demeanour

`_demeanour` mirrors `Naklon`'s pole (`-1` merciful / `0` / `+1` cruel), set
at spawn and updated on `pole_crossed`. It is expressed entirely through
movement targets, speed and the existing posture squash — no new animation
system, no new node:

- **Cruel.** Fear radius around the Hand/Avatar widens to 10 m (5.5 m
  neutral, 2 m merciful). Inside it they steer away, flinch (a 1.1 s
  crouch), and actually back off 7 m. Wander anchors are pushed away from
  wherever the Hand was last seen; wander radius widens 25%; walk speed
  ×1.15 (skittish). Prayer willingness rises sharply — fear drives people to
  the stone harder than devotion does.
- **Merciful.** Wander anchors are pulled 35% of the way toward the Sanctum,
  walk speed ×0.92 (unhurried), the Hand is barely minded at all, and
  crossing into mercy makes the village visibly gather at the Sanctum.

## 4. Calling Stone changes (`calling_stone.gd`)

- **Ordered by willingness.** Within each existing priority tier the stone
  now pulls in order of `Villager.prayer_willingness()` — a cached 0..2
  value combining `faith_fraction`, `prayer_fatigue`, `Naklon`, and
  `Reach.effectiveness(village_id, &"calling_stone_prayer")` (so a village
  whose prayer method is fatigued reads as less willing). It is recomputed
  on each villager's own staggered utility tick, so the stone's sort is
  three ~5-element comparisons per village per 0.5 s and re-derives nothing.
  Releasing (when the dial drops) now lets go of the *least* willing first.
- **Panic is respected.** A villager currently `FLEE`ing a fallen Sanctum or
  `MOURN`ing a lost village cannot be summoned, and the stone's effective
  target drops by that many heads instead of reaching deeper into the
  collapsed pool. Without this the village would be dragged back to the
  cairn half a second after the temple fell on it, and the shortfall would
  silently route into the force-the-collapsed death path.
- **Dial target vs. spawned bodies (a real bug found while testing this
  pass).** The stone used to resolve its target as
  `clampi(village.calling_stone_target, 0, village.population)`.
  `world/god_view.tscn` registers each village with `population = 12` but
  spawns **5** real `Villager` nodes, so a dial at 0.3 asked for
  `round(0.3 × 12) = 4` worshippers out of 5 living bodies: nearly the whole
  visible village was pinned to the cairn permanently, and every collapse
  routed the shortfall into `force_praying_while_collapsed()` — a slow death
  spiral nobody asked for, and the reason none of this pass's reactions were
  visible the first time it was run in the integrated scene. The stone now
  resolves the dial ratio against the villagers who **actually exist as
  bodies** for that village. `Village.calling_stone_target` is still written
  by `set_target_ratio()` exactly as `core/village.gd` documents it (nothing
  else in the project reads that field). The deliberate risk path is
  unchanged: crank the dial to 1.0 and the collapsed still get forced back
  up, and still die at 18%.

## 5. Per-frame cost (the honest accounting)

Target hardware is a Dell Latitude 5411 with **integrated Intel graphics
only**, currently ~5-6 fps (`docs/systems/performance_notes.md`). **There is
no GPU in the sandbox this was written in, so nothing below is a measured
frame time** — it is a statement of what work was added, which is countable
without a profiler.

Added per villager per frame, in `_process`:

- three float subtractions and three comparisons (the alert, sense and
  utility timers). That is the entire unconditional cost.

Added per villager per frame, in `_physics_process`:

- one comparison (`_avoid_vector != Vector3.ZERO`), and **only while
  something frightening is actually inside the fear radius**, one `Vector3`
  add + normalize;
- one float multiply (`WALK_SPEED * _speed_scale`).

Everything else is behind a timer:

- **every 0.4 s per villager** (phase-offset): up to two
  `distance_squared_to`-equivalents against cached Hand/Avatar references —
  ~75 distance checks per second across 15 villagers, no allocation;
- **every 4.5-7.0 s per villager** (phase-offset): one job re-score — six
  dictionary reads, ~40 float operations, one 5-entry dictionary allocated;
- **at most once per 5 s / 8 s for the whole population**: the shared
  Hand/Avatar group lookup and the shared Sanctum tree walk. Not per
  villager, not per frame;
- **event-driven only**: alert reactions. `Weather.weather_changed` fires at
  most every 1.5 s and each villager early-outs unless the coarse severity
  bucket (calm/rough/storm) actually changed; `Naklon.pole_crossed` fires
  only on a deliberate player action.

**Nothing was added that costs GPU time at all** — no new node, no new mesh,
no new material, no new light, no particle. There is still no
`NavigationAgent3D`, no navmesh, no per-frame raycast, no physics query, and
no pathfinding of any kind: the movement model is exactly the direct
steering documented under "Movement" above, with one optional avoidance
vector blended in. Fifteen villagers' worth of the above is a few thousand
float operations per second on the CPU, which is why it was judged
acceptable on this machine — but that judgement is reasoning, not a
measurement, and this doc does not claim otherwise.

## 6. Voices triggers — checked, not duplicated

The brief for this pass asked for villager-event Voices triggers to be
fired "if the villager code is the natural place for them and they are not
already fired elsewhere." They were all grepped first. Result: **no new
`Voices.react` call sites were added, because every one of them already
exists and firing them again would double-fire.**

| Trigger | Already fired at | This pass |
|---|---|---|
| `&"villager_collapsed"` | `villager.gd` `_collapse()` | unchanged |
| `&"villager_died_praying"` | `villager.gd` `_die()` | unchanged |
| `&"village_child_born"` | `villager.gd` `_birth_child()` | unchanged |
| `&"village_child_matured"` | `villager.gd` `_mature_child()` | unchanged |
| `&"village_helped"` | `systems/faith/reach.gd:149` (`convert_via_help`) | **not** fired from here — that is Reach's event, not a villager's |
| `&"village_terrorized"` | `systems/faith/reach.gd:165` (`convert_via_terror`) | **not** fired from here, same reason |

No new trigger names were invented either: package M is authoring lines for
the existing set in parallel, and adding names it doesn't know about would
produce silent no-ops that look like content.

## Scoped out (second pass)

- **Animals.** The complaint that prompted this pass said "villagers *and
  animals*". This pass did **only villagers** — `actors/villagers/` is the
  only directory it owns. The Avatar (`actors/avatar/`) is a different
  package with its own learning model, and there is no ambient-wildlife
  system anywhere in the project to extend. Stated plainly rather than
  quietly answering half the request.
- **Pathfinding, still.** Villagers walk in straight lines and will walk
  into a Sanctum wall rather than around it. The avoidance vector steers
  around the *Hand and the Avatar*, not around geometry. A navmesh pass is
  still the honest follow-up, exactly as the first pass said.
- **No per-villager awareness of other villagers.** No flocking, no
  personal-space separation, no queueing. Crowds overlap. The only
  villager-to-villager query in the whole package is still the family
  pairing search, unchanged.
- **No memory or personality.** Every villager scores the world with the
  same weights; the only per-villager variation is timer phase, a stable
  wander angle, and a small per-evaluation jitter. Nobody remembers that the
  Hand crushed their neighbour last minute.
- **No hunger/health model on the individual.** Food is a village-level
  stockpile number that biases job choice; a villager cannot personally
  starve. `VillageEconomy`'s food upkeep is the only consumer of that.
- **Jobs still have no real work sites.** Job anchors remain fixed offsets
  from `village.position_on_island` (see the first pass's "Scoped out"). A
  `building`-job villager runs to the Sanctum on a `RALLY` but does not
  interact with `systems/economy/construction_site.gd`, and repairing is
  still only `ui/sanctum_interaction.gd`'s player-driven `attempt_repair()`.
- **`villager.tscn` unchanged.** Every new behaviour reuses the existing
  capsule/sphere/label nodes and the existing scale-and-rotate posture
  trick. No new node was added to the scene, deliberately: on this hardware
  a new node per villager is a real cost and none was needed.
- **Not measured on the target machine.** See §5.

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
