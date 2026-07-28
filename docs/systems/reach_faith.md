# Reach & Faith growth (package J)

Extends `systems/faith/reach.gd` (the `Reach` autoload). Every function
that existed before this pass — `radius_for_village`, `can_act_at`,
`effectiveness`, `register_use` — keeps its exact signature and behavior.
Everything below is additive, either new functions on `Reach` itself or a
new sibling file, `systems/faith/missionary.gd`.

## Files

- `systems/faith/reach.gd` — extended in place (see "What was added").
- `systems/faith/missionary.gd` — new. `class_name Missionary`, a
  `CharacterBody3D` that walks between villages and preaches.
- `systems/faith/missionary.tscn` — new. One-scene puppet built from
  primitives (robe capsule + staff cylinder), same construction style as
  `actors/villagers/villager.tscn` so it renders under the same software
  Vulkan (llvmpipe) constraints described in `docs/rendering.md` without
  needing any imported mesh.

## The method_id table (read this before wiring a new conversion source)

Every conversion-relevant action in the game should go through
`Reach.effectiveness(village_id, method_id)` before it "counts" and
`Reach.register_use(village_id, method_id)` after it resolves, so miracle
fatigue is tracked correctly per village *and* per method (repeating one
trick stops working; switching it up keeps working). `method_id` is just a
`StringName` key into `Village.method_fatigue` — any new string works with
zero changes to `Reach`, but please reuse one of these where it fits so
fatigue pools don't fragment pointlessly:

| method_id | Owner / caller | Meaning |
|---|---|---|
| `&"calling_stone_prayer"` | `actors/villagers/villager.gd` (G) | Ambient prayer at a Calling Stone. Feeds `Village.devotion`, not `faith_fraction`, directly. |
| `&"help"` | `Reach.convert_via_help()` — feed/heal/gift rites (H economy, F sigils) | Helpful acts. Feeds `faith_fraction`, ceiling 1.0. |
| `&"terror"` | `Reach.convert_via_terror()` — lightning/fire-rain/plague rites (F sigils, N Louhi reprisals) | Terror acts. Feeds `faith_fraction`, ceiling **0.85** — see "Why terror is capped" below. |
| `&"missionary"` | `Reach.convert_via_missionary()`, called internally by `Missionary._hold_station()` | Sermons from a stationed missionary. Feeds `faith_fraction`, ceiling 1.0, but per-tick amount is small (slow by design). |

Raw miracles (Hand grabs, sigil rites that don't fit help/terror, "the
Avatar was simply seen") can use their own descriptive method_id
(`&"miracle_lightning"`, `&"avatar_sighting"`, whatever the calling
package prefers) — `effectiveness()`/`register_use()` already handle any
string with no changes needed here.

## What was added to `reach.gd`

### 1. `convert_via_help(village_id, amount) -> float`

`amount` is caller-defined ("units of food delivered", "HP healed" —
whatever the calling rite means by it), **not** a `faith_fraction` delta.
Internally: `requested_gain = amount * HELP_GAIN_PER_AMOUNT`, then that
gain is scaled by `Reach.effectiveness(village_id, &"help")` (miracle
fatigue) and by remaining headroom to the ceiling
(`(ceiling - faith_fraction) / ceiling`, so the curve naturally flattens
as a village gets closer to full devotion — diminishing returns, not a
flat per-amount add). The actual gain applied is written via
`GameState.set_faith_fraction()` (so `village_converted` still fires
correctly at the 0.999 threshold) and `register_use(village_id, &"help")`
is always called. Also shifts `Naklon` toward mercy
(`HELP_NAKLON_SHIFT_PER_AMOUNT * amount`, weight `HELP_NAKLON_WEIGHT`) —
feeding/healing a village is a real, if small, act of mercy each time it
happens, consistent with how `actors/hand/hand_demo.gd` and
`actors/villagers/villager.gd` already shift Naklon on their own
grab/release and forced-prayer-death events. Ceiling: **1.0** — genuine
kindness can win a village all the way over.

Returns the actual `faith_fraction` gain applied (float, may be 0 if the
village is fatigued flat, already at ceiling, `null`, or
`loyal_to_rival`). Fires `Voices.react(&"village_helped", {village_id,
amount, gain})`.

### 2. `convert_via_terror(village_id, amount) -> float`

Same shape as `convert_via_help`, different constants and — the actual
point of a second method existing — a different ceiling:
`TERROR_CEILING := 0.85`. However much a village is terrorized, terror
alone tops out at 85% faith_fraction; closing the last 15% requires
something else (help, missionary presence, raw miracles). This is the
"faith growth curve" difference the brief asked for between methods: help
approaches 1.0 with the usual diminishing-returns shape, terror approaches
a hard ceiling below 1.0 with the same shape below that ceiling. It's also
the mechanical expression of the game's own thesis (see README) that fear
buys compliance, not devotion. Shifts `Naklon` toward cruelty
(`TERROR_NAKLON_SHIFT_PER_AMOUNT`, weight `TERROR_NAKLON_WEIGHT` — set
higher than help's, since a terror act reasonably should move the needle
more per unit than a kindness of the same nominal "size"). Fires
`Voices.react(&"village_terrorized", {village_id, amount, gain})`.
Intended callers: package F's lightning/fire-rain rites, package N's
Louhi reprisals, or any other "the god was cruel here" event.

### 3. `convert_via_missionary(village_id, amount) -> float`

Same shared curve helper, ceiling 1.0, no Naklon shift (missionary
presence is deliberately neutral — persuasion by patient presence, not
coded as either a mercy or a cruelty act on its own; individual sermons a
missionary gives could of course be helpful or threatening in a later
pass, but that's out of scope here). Called internally by
`Missionary._hold_station()` roughly every 3 seconds while stationed; not
usually meant to be called directly by other packages, but left public in
case a future package wants a "one-off sermon" effect without spawning a
physical unit.

### 4. `smoothed_radius_for_village(village_id) -> float`

Verified the brief's point 3 first: Reach radius already grows with
population, with zero extra code needed — `radius_for_village()` reads
`population * faith_fraction` live on every call
(`8.0 + converts * BASE_REACH_PER_HEAD`), so as villagers are born
(`actors/villagers/villager.gd::_mature_child`) or converts accumulate,
the next call to `radius_for_village()` already reflects it. That part of
the brief needed documentation, not new code.

The one real gap: that number is **instant** — a villager dying, or ten
converts landing in a single prayer tick, makes it jump/shrink visibly the
very next frame. For gameplay gating (`can_act_at`, and
`radius_for_village` itself) that's correct and was left untouched:
"can I act here" must never lag true state. But anything cosmetic reading
the radius (a border-glow shader, a UI meter) benefits from continuity
instead of a pop. `smoothed_radius_for_village()` exponentially eases
toward the same target (`~3s to close 90% of a sudden gap`,
`RADIUS_SMOOTH_RATE := 0.35`), updated once per `_process()` alongside the
existing fatigue decay loop. `world/terrain/reach_border.gd` (package B)
currently calls `radius_for_village()` directly and is free to keep doing
so or switch to the smoothed variant — not changed here since that file
belongs to package B.

## `systems/faith/missionary.gd`

`class_name Missionary`, `extends CharacterBody3D`. A minimal mover, not a
`Villager` subclass — see the file's header comment for why (short
version: `Village.jobs` has no missionary bucket and editing
`core/village.gd` isn't allowed; building a tiny independent mover avoided
depending on package G's in-progress file).

Public API:

```gdscript
Missionary.spawn(home_village_id: StringName, target_village_id: StringName, parent: Node) -> Missionary
missionary.home_village_id: StringName
missionary.target_village_id: StringName
missionary.current_state: Missionary.State  # WALKING / STATIONED / RETURNING / DONE
missionary.send_to(new_target_village_id: StringName) -> void
missionary.recall() -> void
```

Signals: `arrived(missionary, village_id)`, `recalled(missionary,
village_id)`. Group: every live missionary is added to group
`&"missionary"`.

Lifecycle: spawned at `home_village_id`'s position, walks in a straight
line (flat-ground steering, gravity applied the same way
`actors/villagers/villager.gd` does — no `NavigationAgent3D`, see "Scoped
out") toward `target_village_id`'s position, arrives when within 4m,
switches to `STATIONED`, and every `STATION_TICK_INTERVAL` (3s) calls
`Reach.convert_via_missionary(target_village_id, STATION_GAIN_PER_TICK)`.
If the target is lost to Louhi (`loyal_to_rival` becomes true) or
disappears, the missionary auto-recalls. If the target reaches full
conversion, the missionary just stands there awaiting `recall()` or
`send_to()` from its owner — it does not free itself, since a caller may
still hold a reference and want to redeploy it. `recall()` walks it home
and frees it on arrival (see "Scoped out" — no persistent roster).

Fires `Voices.react()` on four triggers, documented here for package M
(Two Voices content):

| trigger | context keys | moment |
|---|---|---|
| `&"missionary_sent"` | `village_id` (home), `target_village_id` | on spawn |
| `&"missionary_arrived"` | `village_id` (target) | reaches destination |
| `&"missionary_recalled"` | `village_id` (target they were pulled from), `home_village_id` | `recall()` called, or auto-recalled because target fell to Louhi |
| `&"village_helped"` | `village_id`, `amount`, `gain` | any `convert_via_help()` call |
| `&"village_terrorized"` | `village_id`, `amount`, `gain` | any `convert_via_terror()` call |

## Scoped out

- **No `NavigationAgent3D` / pathfinding.** No baked navmesh exists yet
  anywhere in the project (same limitation `actors/villagers/villager.gd`
  already lives with, per its own "Movement" comment). Missionaries walk
  a straight flat-ground line toward the target village's
  `position_on_island`; on non-trivial island geometry they can walk
  through terrain features. Fixing this project-wide is out of scope for
  a faith/reach pass and belongs with whoever owns terrain collision
  (package B) plus a navmesh bake step.
- **No missionary roster/reassignment UI.** `Missionary.spawn()` and
  `.recall()`/`.send_to()` are the whole surface; whatever package wants
  to let the player manage a pool of missionaries (send N of them, see
  which are idle, etc.) needs to keep its own `Array[Missionary]` and call
  these. `recall()` frees the node on arrival rather than parking it
  "idle at home" for reuse, to keep this pass's lifecycle simple and
  leak-free; a persistent pool is a UI/economy-layer concern (H/T).
- **No missionary attrition/death.** Unlike villagers forced to pray
  (which can die, per `villager.gd::force_praying_while_collapsed`),
  missionaries in this pass can't be killed, starved, or eaten by Louhi's
  forces. A future pass tying them into a hazard/combat system could add
  that; nothing here blocks it (any package can just `queue_free()` a
  Missionary node directly, or extend this file — it's not sealed).
- **No distinct "miracle" method_id defined here.** Raw miracle
  conversion (Hand-grab effects, sigil rites that aren't help/terror
  shaped) is out of this package's scope — those callers should just pick
  their own descriptive `method_id` string; `effectiveness()`/
  `register_use()` already support any `StringName` with no changes
  needed.
- **No new autoload.** `Missionary` is a plain scene/script, not a
  singleton — `project.godot`'s `[autoload]` block is foundation-owned
  and this package doesn't touch it. Anything that wants a "how many
  missionaries are currently out" count should query
  `get_tree().get_nodes_in_group(&"missionary")`.

## Assets used

None. Everything here is procedural (primitive meshes built in the
`.tscn`, same style as `actors/villagers/villager.tscn`) — no textures,
models, audio, or HDRIs were needed for this package.
