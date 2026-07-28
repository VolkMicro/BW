# Package H — Buildings, resources, Wonders

Owns `systems/economy/`. Depends only on `core/` (`Village`, `GameState`)
directly; also calls `Voices.react` (`systems/voices/`) on commentable
events and, for one Wonder's Reach bonus, reads (never writes)
`systems/faith/reach.gd`'s public `radius_for_village`/`can_act_at`.

## Files

| File | What it is |
|---|---|
| `systems/economy/stockpile.gd` | `class_name Stockpile` — static helpers implementing the per-village resource-storage convention (see below). No autoload; called directly as `Stockpile.foo(...)`. |
| `systems/economy/building.gd` | `class_name BuildingType extends Resource` — base data+hook definition for one constructable type (cost, build time, `on_complete`). |
| `systems/economy/construction_site.gd` | `class_name ConstructionSite extends RefCounted` — one in-progress build job (village id, `BuildingType`, elapsed time). |
| `systems/economy/building_catalog.gd` | `class_name BuildingCatalog` — static registry, id -> `BuildingType` instance, for all six concrete types below. |
| `systems/economy/village_economy.gd` | `class_name VillageEconomy extends Node` — the manager: production tick, construction queues, the Tithing Stone's devotion hook. **Instantiate this node somewhere in the live scene tree** (see "Integration" below); it is not an autoload. |
| `systems/economy/reach_bridge.gd` | `class_name EconomyReachBridge` — wrapper functions exposing the Far Bell Wonder's Reach bonus without editing `systems/faith/reach.gd`. |
| `systems/economy/buildings/gathering_house.gd` | `class_name GatheringHouseBuilding extends BuildingType` |
| `systems/economy/buildings/storehouse.gd` | `class_name StorehouseBuilding extends BuildingType` |
| `systems/economy/buildings/workyard.gd` | `class_name WorkyardBuilding extends BuildingType` |
| `systems/economy/wonders/wonder.gd` | `class_name Wonder extends BuildingType` — base for the three Wonders (forces `is_wonder = true`, `max_per_village = 1`). |
| `systems/economy/wonders/tithing_stone.gd` | `class_name TithingStoneWonder extends Wonder` — +20% devotion generation. |
| `systems/economy/wonders/swift_yards.gd` | `class_name SwiftYardsWonder extends Wonder` — +35% wood/stone production rate. |
| `systems/economy/wonders/far_bell.gd` | `class_name FarBellWonder extends Wonder` — +6m Reach radius. |
| `systems/economy/economy_demo.gd` + `.tscn` | Standalone validation scene: one test village, three buildings queued, then a Wonder, with a live `Label3D` status readout — proves the whole pipeline runs, not a mock. |

## The one Dictionary-key convention: per-village resource storage

`core/village.gd` (foundation, not this package's to edit) has no
wood/food/stone fields. Rather than invent a second place villages keep
state, this package attaches a runtime Dictionary directly to each
`Village` **Resource instance** via Godot's built-in
`Object.set_meta`/`get_meta`, under exactly one key:

```gdscript
const META_KEY: StringName = &"economy_stockpile"
# stored shape: { &"wood": float, &"food": float, &"stone": float }
```

Any package can read it directly, with no dependency on this one:

```gdscript
var stock: Dictionary = village.get_meta(&"economy_stockpile", {})
var wood: float = stock.get(&"wood", 0.0)
```

...but should prefer `Stockpile`'s static helpers, which also enforce the
storage cap and non-negativity:

```gdscript
Stockpile.get_amount(village, &"wood") -> float
Stockpile.capacity(village, &"wood") -> float       # BASE_CAPACITY (120) + 180 per Storehouse
Stockpile.add(village, &"wood", 12.5) -> Dictionary  # {"new_amount","absorbed","overflowed"}
Stockpile.can_afford(village, {&"wood": 40.0}) -> bool
Stockpile.spend(village, {&"wood": 40.0}) -> bool    # all-or-nothing
Stockpile.snapshot(village) -> Dictionary            # safe copy for UI
```

**Requires-foundation-change note.** The clean, permanent fix — whenever
whoever owns `core/` next is willing to take it — is one line added to
`core/village.gd`'s export block:

```gdscript
@export var resources: Dictionary = {"wood": 0.0, "food": 0.0, "stone": 0.0}
```

which would let `stockpile.gd` collapse to plain field reads/writes and
drop the `set_meta` indirection entirely. This package does not make that
edit itself, per the ownership map; the proposal is recorded here (and
in `stockpile.gd`'s own header comment) for that pass.

## Buildings

`BuildingType` (Resource subclass) fields: `id`, `display_name`,
`description`, `cost: Dictionary` (resource -> amount, keys must match
`Stockpile.RESOURCE_KEYS`), `build_time_seconds`, `is_wonder: bool`,
`max_per_village: int` (`-1` = unlimited). `on_complete(village)` runs
once, the instant construction finishes.

Three concrete types, registered in `BuildingCatalog`:

| id | Cost | Build time | Effect |
|---|---|---|---|
| `&"gathering_house"` | 25 wood | 20s | +0.5 food/sec passively, per Gathering House, stacking |
| `&"storehouse"` | 45 wood, 15 stone | 35s | +180 storage cap per resource, per Storehouse, stacking |
| `&"workyard"` | 40 wood, 25 stone | 45s | +25% wood & stone production rate, per Workyard, additive stacking |

All three deliberately have **no state of their own** beyond the id
sitting in `village.buildings` — their bonus is computed live each
production tick by counting occurrences of that id (`BuildingType.count_in`),
so there's nothing this package owns that could fall out of sync with a
save/load pass it doesn't control.

## Wonders

Three, each `max_per_village = 1`, each with a real, persistent,
already-wired gameplay effect:

| Wonder id | Cost | Build time | Effect | Hooked via |
|---|---|---|---|---|
| `&"wonder_tithing_stone"` | 90 stone, 20 wood | 100s | +20% devotion generation | `GameState.devotion_changed` signal (see below) |
| `&"wonder_swift_yards"` | 110 wood, 60 stone | 120s | +35% wood/stone production rate | this package's own production tick |
| `&"wonder_far_bell"` | 70 stone, 50 wood | 110s | +6m Reach radius | `EconomyReachBridge` wrapper (see below) |

**Tithing Stone — genuinely live, no cooperation needed from other
packages.** `GameState.add_devotion()` is the foundation's one entry point
for crediting a village with devotion, and it always emits
`devotion_changed(village_id, new_amount)` right after updating
`Village.devotion`. `VillageEconomy` connects to that signal, tracks the
last value it saw per village to compute the delta a caller just added,
and — if the Tithing Stone is standing — immediately grants a top-up of
`delta * 0.20` via another `add_devotion` call (a re-entrancy guard stops
that top-up from re-triggering itself). This means the bonus applies to
devotion from *any* current or future source that goes through
`GameState.add_devotion` — currently `actors/villagers/villager.gd`'s
prayer and ambient-work ticks — without this package needing to know who
is calling it, or editing package G's files.

**Swift Yards — fully self-contained.** It multiplies this package's own
`_tick_production` wood/stone output, exactly like a Workyard building but
bigger and Wonder-tier. This is package H's honest reading of the brief's
"+Y villager work speed": it speeds up the *economy system's output*,
which is the whole of what this package can truthfully claim to move.
Actually slowing/quickening the Villager state machine's per-task
duration or animation lives in `actors/villagers/villager.gd` (package G)
and is out of this package's write access — see "Scoped out" below.

**Far Bell — real effect, wrapper-level integration.** `Reach.radius_for_village()`
(`systems/faith/reach.gd`) is owned by package J, and this package does
not edit `systems/faith/`. The bonus is still real and queryable *today*
via:

```gdscript
EconomyReachBridge.radius_bonus(village_id) -> float      # 6.0 or 0.0
EconomyReachBridge.effective_radius(village_id) -> float  # Reach.radius_for_village() + bonus
EconomyReachBridge.can_act_at(world_pos) -> bool          # Reach.can_act_at() equivalent, bonus-aware
```

Any caller happy to use the economy-side wrapper in place of `Reach`'s own
functions gets the boosted number right now. The clean long-term
integration is a one-line, additive (non-breaking) change to
`Reach.radius_for_village()`:

```gdscript
return 8.0 + converts * BASE_REACH_PER_HEAD + EconomyReachBridge.radius_bonus(village_id)
```

left for package J (or whoever next owns `systems/faith/`) to add, since
that file is not this package's directory to write to.

## Production formula (`VillageEconomy._tick_production`, per second)

```
structure_bonus = 1.0 + (workyard_count * 0.25) + (0.35 if Swift Yards else 0.0)
food_gain   = (jobs.fishing + jobs.field) * 0.9 + gathering_house_count * 0.5
wood_gain   = jobs.woodcutting * 0.7 * structure_bonus
stone_gain  = population * 0.04 * structure_bonus   # ambient quarrying/beachcombing — there is
                                                     # no dedicated "quarry" job in village.jobs
                                                     # (fishing/field/woodcutting/building/family/
                                                     # idle only, owned by package G), so stone
                                                     # income is population-scaled rather than
                                                     # job-scaled; see "Scoped out"
food_upkeep = population * 0.05
```

Reads `village.jobs` (a plain `Dictionary`, String-keyed — `"fishing"`,
`"field"`, `"woodcutting"` — already populated by package G's villager
job-assignment code) and `village.population`/`village.buildings`/
`village.wonders` directly; never mutates any of them except appending
finished building/wonder ids.

## Construction (`VillageEconomy`)

```gdscript
economy.start_construction(village_id, building_id) -> bool
# looks up BuildingCatalog, checks max_per_village, spends cost up front
# (all-or-nothing — nothing is deducted on failure), queues a
# ConstructionSite. Returns false on unknown id, limit reached, or
# insufficient resources.

economy.cancel_construction(village_id) -> bool
# drops the front-of-queue site, refunds half its cost.

economy.queue_for(village_id) -> Array   # Array[ConstructionSite], front = active
economy.resource_amount(village_id, resource) -> float
economy.resource_capacity(village_id, resource) -> float
```

Signals: `construction_started(village_id, building_id)`,
`construction_completed(village_id, building_id)`,
`construction_cancelled(village_id, building_id)`,
`resources_changed(village_id)`.

One construction resolves at a time per village, in FIFO order — a second
`start_construction` call while one is active queues behind it rather than
running in parallel, so a village can't out-build its own workforce by
paying twice.

## Voices triggers fired by this package

Documented here for package M (Two Voices content) to write real lines
against — all fire via `Voices.react(trigger, context)`:

| Trigger | Context keys | Fires when |
|---|---|---|
| `&"construction_started"` | `village_id`, `village_name`, `building_id`, `building_name` | `start_construction` succeeds, for a non-Wonder building |
| `&"construction_completed"` | same | a non-Wonder building finishes |
| `&"wonder_completed"` | same | a Wonder finishes |
| `&"stockpile_overflow"` | `village_id`, `village_name`, `resource` | production would push a resource past its cap; fires once per village per resource (not every tick) |

## Integration (no scene under `world/`/`actors/` is this package's to wire in)

`VillageEconomy` is a plain `Node`, not an autoload (per `project.godot`'s
already-fixed autoload list, which this package does not edit) and not
attached to `world/god_view.tscn` (owned by packages B/C, read-only to
this pass). Add exactly one `VillageEconomy` node anywhere in the live
scene tree — it self-registers against every village already in
`GameState.villages` on `_ready()`, and against new ones live via
`GameState.village_registered` — and the whole system runs. Until that
wiring lands in the real campaign scene, `systems/economy/economy_demo.tscn`
demonstrates it standalone: one test village (`&"kettlebrook_economy_demo"`,
a Sankiln village so it doesn't collide with package G's demo villages),
job counts set directly (this package doesn't spawn Villager actors),
three buildings queued back-to-back, then the Swift Yards Wonder once the
Workyard finishes — a `Label3D` shows live stockpile/cap/queue/wonder
state so the whole pipeline is visually checkable in one screenshot.

## Scoped out

- **Actual villager work-speed / animation change from Swift Yards or a
  Workyard.** Both wonders/buildings speed up this package's own
  production-tick numbers, not the Villager state machine's per-task
  timing in `actors/villagers/villager.gd` (package G) — that file is
  outside this package's write access. A future pass wiring this for real
  would have `villager.gd` check `SwiftYardsWonder.is_present(village)` /
  count Workyards the same way this package does, and shorten its own
  per-task durations accordingly.
- **A dedicated stone-gathering job.** `village.jobs` (owned by package
  G's job-assignment code) only has fishing/field/woodcutting/building/
  family/idle — no quarry job — so stone income here is a small
  population-scaled passive trickle rather than assignable labor. Adding
  a `"quarrying"` job key is a reasonable follow-up but requires
  coordination with package G's job-assignment/state-machine code, not
  something this package can do unilaterally to `village.jobs`' meaning.
- **Automatic Reach-bridge wiring into `systems/faith/reach.gd`.** The
  Far Bell's bonus is real and computable today via `EconomyReachBridge`,
  but callers (Hand, sigils, the reach-border shader) have to opt into
  calling the bridge instead of `Reach` directly until package J adds the
  one-line addition documented above. Not silently faked — genuinely
  correct, just not force-fed into a file this package doesn't own.
- **Starvation consequences.** Food upkeep can outpace production and
  drain a village's food stockpile to zero, but nothing currently reduces
  population, morale, or devotion as a result — there's no Voices trigger
  for sustained zero food either. Left for a demography/UI pass that
  wants to make hunger visible and consequential, rather than this
  package guessing at population-death rules that belong to whoever
  designs that mechanic.
- **Cancelling a queued (not-yet-active) build individually.**
  `cancel_construction` only ever cancels the front-of-queue (active)
  site; there's no per-entry cancel for something waiting behind it. A
  real build-menu UI would want that; the queue is a plain `Array` so
  it's a small addition later, just not built here since there's no UI
  yet to expose it through.
- **Persisting `economy_stockpile` through save/load.** Since it lives in
  `Object` metadata rather than an `@export`ed field, whatever save
  system eventually ships needs to explicitly serialize
  `village.get_meta(&"economy_stockpile")` alongside the Village resource
  — flagged here since it's exactly the kind of thing the foundation
  change above (a real `@export var resources` field) would fix for
  free.

### Assets used

None. This package is pure logic/data (Resource subclasses, a manager
Node, a demo scene built from primitive `PlaneMesh`/`StandardMaterial3D`
already used elsewhere in this repo) — no textures, models, or audio were
needed or pulled in.
