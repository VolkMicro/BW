# Package I — Sanctum, worship, devotion, and the sacrifice taboo

## What this is

A real, walkable Sanctum building — exterior, worship-yard, and a simple
hollow interior shell, all procedural CSG geometry (no downloaded assets,
see "Assets used" below) — plus the two pieces of gameplay logic the brief
calls out by name:

1. **Sanctum hp is the Village's hp.** `sanctum.gd` never keeps its own
   copy of "building health"; every read and write goes straight through
   `GameState.get_village(village_id).sanctum_hp` /`.sanctum_hp_max`. Damage
   to the building and damage to the village are, per the brief, "physically
   one and the same number."
2. **The Offering (`world/sanctum/sacrifice.gd`, `class_name Sacrifice`).**
   A systems-level `offer(village_id, target: Node) -> void` that grants an
   instant, steep devotion bump — much more for a living person than an
   object, most of all for a child — but always shifts `Naklon` hard toward
   cruelty, always tells the Two Voices to react with disapproval, and
   always locks the Sanctum's gentle repair path for a real cooldown
   window. This is not a value-neutral currency tap; it is the one act
   every culture in this game explicitly condemns as a crime.

Nothing here is a stub. `world/sanctum/sanctum_demo.tscn` is a real,
standalone scene — `godot --path . world/sanctum/sanctum_demo.tscn` —
that registers a real (damaged, partly-converted) `Village` in `GameState`
and shows an actual instanced `Sanctum` reacting to it: culture-tinted
walls, a scorch tint proportional to its 62/100 hp, and an altar glow
proportional to its 0.45 faith_fraction.

## Files

| File | What it is |
|---|---|
| `world/sanctum/sanctum.tscn` | The Sanctum scene: worship-yard (round platform, six standing stones, altar + offering-trigger area) and exterior building (CSG box shell with a subtracted hollow interior, doorway, and two windows, plus a CSG pyramid roof). One scene, reused per village — see "Culture skin" below. |
| `world/sanctum/sanctum.gd` | `class_name Sanctum extends Node3D`. Owns hp sync, culture re-skinning, damage/repair, the collapse/restore visual, and forwards `try_offer()` to `Sacrifice.offer()`. |
| `world/sanctum/sacrifice.gd` | `class_name Sacrifice extends RefCounted`. The Offering mechanic: static `offer()`, target classification, Naklon/devotion/Voices wiring, and the offering-debt cooldown that locks `Sanctum.repair()`. |
| `world/sanctum/sanctum_demo.gd` | Standalone demo bootstrap: registers one test `Village` (Fenrayt, damaged, partly converted) before the sibling Sanctum's own visuals settle — see "A note on _ready() order" below. |
| `world/sanctum/sanctum_demo.tscn` | `WorldEnvironment` + `Sun` + `DemoCamera` + a flat ground plane + one instanced `Sanctum`, following the same standalone-demo pattern as `world/terrain/island_demo.tscn` / `world/ocean/ocean_demo.tscn`. |

## The Sanctum building

`sanctum.tscn` is built entirely from Godot's built-in CSG nodes
(`CSGCombiner3D` / `CSGBox3D` / `CSGCylinder3D`) rather than hand-authored
meshes or downloaded kit pieces — real, working, boolean-carved geometry
(a genuine doorway and windows cut through a solid shell), chosen over a
half-finished custom mesh per the brief's "prefer procedural... over
needing hand-authored art you don't have time to make well."

Layout (all local to the `Sanctum` root):

- **`WorshipYard/Platform`** — a round dais (`CSGCylinder3D`, r=9m,
  24 sides), `use_collision = true`. Top surface at y≈0.2.
- **`WorshipYard/StandingStones`** — six monoliths in a ring at r=7m,
  60° apart, decorative (no individual collision — a deliberate
  simplification, see "Scoped out").
- **`WorshipYard/Altar`** (`CSGBox3D`, solid, collides) at
  `(0, 0.7, 2.0)`, with a child `Area3D "OfferingTrigger"`
  (`SphereShape3D`, r=2.2) other systems can use to detect "something is
  standing at the altar" without adding their own collision shape — its
  `body_entered`/`body_exited` are re-emitted as `Sanctum.offering_area_entered`
  / `offering_area_exited`.
- **`Exterior/Walls`** (`CSGCombiner3D`, `use_collision = true`) — a
  7×4×7m `Shell` box with a 6.2×3.4×6.2m `Hollow` subtracted out (leaving
  ~0.4m walls, a real walkable interior floor and low ceiling), a `DoorCut`
  breached flush with the platform (no threshold lip) on the +Z face, and
  two `WindowCut` openings on the side walls.
- **`Exterior/Roof`** — a `CSGCylinder3D` with `sides=4, cone=true`: a
  procedural 4-sided pyramid cap, no custom mesh needed.
- **`InteriorAnchor`** (`Marker3D`, local `(0, 0.6, -1.5)`) — the usable
  interior floor is roughly `x∈[-3.1, 3.1]`, `z∈[-3.1, 3.1]` at floor
  height `y≈0.6` (Sanctum-local). **This is the hook for package T**: parent
  altar/idol/interior-dressing scenes here rather than re-deriving the
  interior box from the wall geometry.
- **`EntranceMarker`** (`Marker3D`, local `(0, 0.2, 4.8)`) — just outside
  the doorway, at platform height, for spawn-in/camera-cut placement.

### Culture skin

`Sanctum` doesn't hard-code one culture's colors. On `_ready()` (and again
whenever `GameState.village_registered` fires for a matching `village_id`),
it duplicates its template materials once per instance and re-tints walls/
roof/altar/stones from `GameState.cultures[village.culture_id].color_primary`
/`.color_accent` (falling back to the template's default Fenrayt-ish
bog-dark palette if the village or culture isn't registered yet). One
scene file, instanced once per village, serves all four cultures.

### A note on `_ready()` order

Godot calls a node's `_ready()` after all its children's `_ready()` have
already run. In `sanctum_demo.tscn`, the Village-registering bootstrap
script sits on the *scene root* (a parent of the `Sanctum` instance), so
it actually runs **after** `Sanctum`'s own first-frame skin/hp/glow pass —
at that point `GameState.get_village(village_id)` is still null and the
Sanctum briefly computes fallback/default values. This is not a bug:
`sanctum.gd` subscribes to `GameState.village_registered` *before* doing
that first pass, so the moment the bootstrap script calls
`GameState.register_village()`, the signal fires synchronously and the
Sanctum recomputes its real skin/hp/glow — all still within the same
frame, before anything is drawn. Any integration that registers a
village on a **later** frame (e.g. after a network round-trip) would show
one frame of default coloring first; noted here rather than silently
relied upon.

## Sanctum hp — one number, two readers

```gdscript
# sanctum.gd
func apply_damage(amount: float, source: Node = null) -> void:
    var v := GameState.get_village(village_id)
    v.sanctum_hp = maxf(0.0, v.sanctum_hp - amount)   # writes the Village directly
    ...
    if v.sanctum_hp <= 0.0:
        GameState.set_faith_fraction(village_id, 0.0)  # village loses all faith
        ...
```

`apply_damage(amount, source)` is the public entry point for anything
that hurts a Sanctum (Louhi's presence AI, a combat hit from
`actors/avatar/combat/`, weather, a rival raid) — it takes an optional
`source: Node` purely so `Voices.react()` and the eventual UI can say who
did it. Whoever calls it does not need to know or care that "Sanctum hp"
and "Village hp" are the same field; that's exactly the point.

`repair(amount)` is the symmetric gentle-restore path, **except** it
refuses to run while the village is under active offering-debt (see
below) — emitting `mercy_blocked` and a `&"mercy_blocked_by_debt"` Voices
reaction instead of touching hp. `can_repair() -> bool` is exposed for
package T's UI to grey out a repair action instead of letting the click
silently no-op.

At 0 hp: `sanctum_built` is cleared, `sanctum_destroyed` fires, the
`Exterior` node visibly sinks and tilts (a `Tween` on `position:y` /
`rotation:z` — a real, running animation, not a described one) and its
CSG collision layers are zeroed so the fallen shell stops blocking
movement. `repair()` crossing back above 0 hp reverses all of that.

## The Offering / the taboo, in fiction

**This is the crime the fiction condemns, not a rite any of the four
cultures practices willingly.** Read `data/cultures/*.tres` and every one
of them names this exact act, unprompted, as the line their real,
willingly-kept rite refuses to cross:

| Culture | Real rite (never touches the taboo) | Their name for the taboo |
|---|---|---|
| Fenrayt | The Sinking — a woven raft of *work*, never anything living | **Offering-Debt** |
| Sankiln | The Firereading — a fistful of *grain* in the hearth | **Ash-Debt** |
| Raimborn | The Wavecall — costs nothing, "nobody is thrown to it" | **Keel-Debt** |
| Vainkeeper | The Grafting — a cutting, "nothing is asked of it but growth" | **Root-Debt** |

`Sacrifice.taboo_name_for(village_id)` looks this up from the village's
`culture_id` (`TABOO_NAME_BY_CULTURE` in `sacrifice.gd`) so every context
dict handed to `Voices.react()` carries the *culturally correct* name of
the crime, not a generic label — a Fenrayt village's altar always calls it
Offering-Debt, never Ash-Debt.

`Sacrifice.offer(village_id, target)`:

1. Classifies `target` as `OBJECT` / `LIVING_ADULT` / `LIVING_CHILD` (see
   the contract documented at the top of `sacrifice.gd` — a
   `get_offering_kind()` method, a `&"villager"`/`&"villager_child"` group,
   or duck-typed `is_living`/`is_child` properties; `target == null` is
   treated as a generic goods offering).
2. Grants devotion via `GameState.add_devotion()` — `8.0` / `40.0` / `90.0`
   respectively (tunable constants; not yet balanced against
   `systems/economy/`'s passive devotion income, see "Scoped out").
3. **Always** shifts `Naklon` toward cruelty via `Naklon.shift(amount, 3.0)`
   — weight `3.0`, a "big, deliberate act" per `naklon.gd`'s own doc
   comment, so one offering moves the scalar far more than routine small
   mercies or cruelties do. There is no code path where `offer()` leaves
   Naklon untouched.
4. **Always** calls `Voices.react(&"offering_taboo", {village_id,
   culture_id, kind, devotion_gained, debt_name})` — so the Two Voices
   package (M) can write real, specific disapproval lines keyed on both
   `kind` and the culturally correct `debt_name`.
5. If the target was a living villager, the village actually loses that
   person: `village.population -= 1`, and for a child, `village.children
   -= 1` as well (floored at 0) — "read Village.children" is honored by
   this being a real population cost, not flavor text.
6. Sets a **real** cooldown (`COOLDOWN_SECONDS = 180.0`) via a static
   `village_id -> Time.get_ticks_msec()` map. While active,
   `Sacrifice.is_offering_debt_active(village_id)` is true and
   `Sanctum.repair()` refuses to run at that village's Sanctum — enforced
   in `sanctum.gd`, not just described here.

Repeated offerings are **not** blocked by the cooldown — only the mercy/
repair path is. The design intent: a player can keep choosing cruelty, but
can't immediately buy back gentleness at the same altar.

## Public API

**`Sanctum` (Node3D, `world/sanctum/sanctum.tscn`)**
- `@export var village_id: StringName`
- `current_hp() / max_hp() / hp_fraction() -> float`
- `apply_damage(amount: float, source: Node = null) -> void`
- `repair(amount: float) -> void`
- `can_repair() -> bool`
- `try_offer(target: Node) -> void` — gated on `Reach.can_act_at(global_position)`
  (a Sanctum whose village has fully fallen to the rival and isn't covered
  by any neighbor's reach refuses the offering outright), then forwards to
  `Sacrifice.offer(village_id, target)`
- `debt_name() -> String` — this village's culturally correct taboo name
- Signals: `sanctum_damaged(village_id, new_hp, max_hp)`,
  `sanctum_destroyed(village_id)`,
  `sanctum_repaired(village_id, new_hp, max_hp)`,
  `mercy_blocked(village_id, reason)`,
  `offering_area_entered(body)` / `offering_area_exited(body)`

**`Sacrifice` (static, `world/sanctum/sacrifice.gd`)**
- `static func offer(village_id: StringName, target: Node) -> void`
- `static func is_offering_debt_active(village_id: StringName) -> bool`
- `static func offering_debt_seconds_remaining(village_id: StringName) -> float`
- `static func taboo_name_for(village_id: StringName) -> String`
- `static func bus() -> SacrificeBus` — a lazily-created shared instance
  exposing `signal offering_made(village_id, kind, devotion_gained)` for
  anything that wants to react to an offering specifically (not just the
  generic `GameState.devotion_changed` / `Naklon.naklon_changed` it also
  triggers).

## Voices triggers this package fires (for package M)

| Trigger | Context dict | When |
|---|---|---|
| `&"offering_taboo"` | `village_id, culture_id, kind, devotion_gained, debt_name` | Every `Sacrifice.offer()` call, unconditionally. |
| `&"sanctum_damaged"` | `village_id, amount, hp_fraction, source` | Every `apply_damage()` call. |
| `&"sanctum_destroyed"` | `village_id, culture_id` | hp reaches 0. |
| `&"mercy_blocked_by_debt"` | `village_id, debt_name, seconds_remaining` | `repair()` refused during offering-debt cooldown. |
| `&"offering_out_of_reach"` | `village_id` | `try_offer()` refused because `Reach.can_act_at()` says the god has no purchase at this Sanctum's position. |

`Voices.react()` is currently a safe no-op against these (the stub
`voice_lines.gd`'s `pick_pair()` always returns `[]`), so calling it now
doesn't require package M to exist yet — package M just needs to key real
line pools off these four trigger names and their fields.

## For package T (interior)

You own `world/sanctum_interior/` and `ui/`. What I've built inside the
Sanctum shell is deliberately minimal: a hollow box with a floor, a
doorway, and two windows — no altar-facing idol, no interior lighting
fixtures, no floor dressing. Use `Sanctum/InteriorAnchor`
(`Marker3D`, local `(0, 0.6, -1.5)`) as your parent/reference point; the
usable interior floor is roughly a 6.2m×6.2m square centered on the
Sanctum's local X/Z axis, floor height ≈0.6 local-y, ceiling ≈1.9m above
that. `Sanctum.hp_fraction()`, `.can_repair()`, and the
`sanctum_damaged`/`sanctum_destroyed`/`sanctum_repaired` signals are the
hooks your UI should read from rather than re-deriving hp state.

## Scoped out

- **No passive/ambient devotion production.** `Village.devotion` as
  "spendable currency, produced by active prayer" is described in
  `core/village.gd`'s own doc comment as someone else's system
  (`systems/economy/`, package H, or villager AI, package G) — this
  package only implements the *instant, taboo* devotion spike
  (`Sacrifice.offer()`). The devotion constants (`8.0`/`40.0`/`90.0`) are
  not yet balanced against whatever passive income rate H ships; flagged
  here rather than silently guessed at.
- **No individual collision on the standing stones.** They're `MeshInstance3D`
  + `BoxMesh`, visual only — a deliberate simplification given six extra
  `StaticBody3D`s around a small worship-yard cost more than they add for
  a vertical slice. Trivial to add (`use_collision`-style CSG conversion)
  if a later pass wants the Hand to be able to knock one over.
  Standing on a stone won't visually register.
- **No hand-verified roof/wall seam.** The pyramid roof
  (`CSGCylinder3D(sides=4, cone=true)`) sits on the square wall shell by
  radius/height math worked out by hand, not by looking at a rendered
  frame — this sandbox has no GPU for an interactive editor session (see
  `docs/rendering.md`). The geometry is internally consistent (no
  contradictory CSG operations, no out-of-bounds cuts) but the exact
  visual seam between the 4-sided cone and the box corners hasn't been
  screenshotted and eyeballed. A one-line `rotation_degrees.y` tweak on
  `Exterior/Roof` is the likely fix if a later screenshot pass shows a
  visible mismatch.
- **No UI/HUD for offering or repair.** `try_offer()` / `repair()` /
  `can_repair()` are plain methods; wiring them to an actual interaction
  (Hand gesture, button, dialog) is `actors/hand/` (E) and `ui/` (T)'s
  job. This package guarantees the mechanic is real and callable, not
  that there's a diegetic way to trigger it yet.
- **No physical "offered object" prop/animation.** `offer()` resolves
  instantly and abstractly (devotion added, Naklon shifted, Voices told) —
  there's no thrown-object arc, no altar-consuming VFX. Left for whichever
  package owns the Hand's throw animation and/or a particle pass, since
  building a half-convincing custom VFX here risked exactly the "stub
  pretending to be a feature" the brief warns against.

## Assets used

None. The Sanctum is built entirely from Godot's built-in CSG primitives
and `StandardMaterial3D` colors sourced from `data/cultures/*.tres`
(`color_primary`/`color_accent`) — no textures, models, or audio were
downloaded for this package. This is a deliberate choice, not an
oversight: the brief's hard rule 6 explicitly prefers procedural/
code-driven content over external assets a single pass doesn't have time
to integrate well, and a small walkable building reads clearly as
flat-shaded culture-tinted geometry without needing PBR texture sets
(which `world/terrain/` and `world/ocean/` already source their own of,
for the surfaces that actually need them).
