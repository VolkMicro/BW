# Avatar combat, growth application, duels — Package L

Owns: `actors/avatar/combat/`. Depends on `actors/avatar/` (package K) per
`docs/systems/OWNERSHIP.md`.

## What's here

- `avatar_combatant.gd` (`class_name AvatarCombatant`, extends `Node3D`) —
  one fighter: health, stamina, growth-scaled stats, a belief bridge to a
  real Avatar (package K) with a working standalone fallback, and purely
  procedural combat "juice" (lunge/guard-crouch/retreat-pull-back/hit-flash/
  collapse), no skeletal animation.
- `duel_arena.gd` (`class_name DuelArena`, extends `Node3D`) — the referee:
  a real-time tick loop that has both fighters simultaneously choose a
  move, resolves the exchange, tracks a downed/finisher-window special
  case, ends the duel, and applies belief-store feedback for both the
  finisher/mercy decision and the overall win/loss.
- `avatar_combatant.tscn` — reusable fighter scene (capsule body + box
  head + `Label3D` status readout), instanced twice by the demo.
- `duel_arena_demo.gd` + `duel_arena_demo.tscn` — a self-contained arena:
  two AI fighters with deliberately contrasting growth stage and belief
  presets duel automatically, on a loop, with an on-screen feed of every
  move, downed/finish/mercy event, `Voices.react()` remark, and the final
  result. No player input; this proves the state machine and the
  belief/growth wiring, it isn't campaign content.

At the time this package was built, `actors/avatar/avatar.gd` (package K)
did not yet exist in the tree — only the empty `actors/avatar/combat/`
directory was present. **Everything here was built against the documented
API contract in the brief, not a live file.** `AvatarCombatant` never
assumes that contract is honored: every call into a wired Avatar node goes
through `has_method()` first (see "Integration contract" below), and when
no Avatar node is wired (or it doesn't implement a given method yet) each
call falls back to a local, fully-functional belief dictionary and a
growth-stage stat curve, so this package runs and is screenshot-able
standalone either way. The integration pass should point
`AvatarCombatant.avatar_path` at a real Avatar node once K's file lands and
confirm `has_method()` finds the real methods instead of falling back.

## Integration contract (what this package expects from K's avatar.gd)

```gdscript
avatar.get_belief(tag: StringName) -> float        # 0..1, current strength of a learned disposition
avatar.would_do(tag: StringName) -> bool           # stochastic/threshold decision derived from the belief
avatar.reinforce_belief(tag: StringName, delta: float) -> void  # nudge belief by delta, clamped 0..1
avatar.get_growth_stage() -> int                   # 0=hatchling .. N=elder, whatever K's enum is
avatar.get_growth_scalar(stat: StringName) -> float # multiplier for &"health" / &"damage" at current stage
```

`AvatarCombatant` wires to one via `@export var avatar_path: NodePath` and
resolves it with `get_node_or_null()` in `_ready()`. If left empty (as both
demo fighters do), or if the resolved node lacks a given method, that one
call transparently falls back — there is no hard failure mode, which was a
deliberate choice given K's file wasn't guaranteed to exist first.

## Move set

Five moves, chosen simultaneously by both fighters every `tick_interval`
(0.9s default):

| Move | Damage | Stamina cost | Notes |
|---|---|---|---|
| BITE | 12 × `damage_scalar` | 10 | reliable mid attack |
| CLAW | 7 × `damage_scalar` | 6 | cheap, also drains 2 stamina from a hit target (off-balancing) |
| CHARGE | 20 × `damage_scalar` | 22 | high risk/reward — see below |
| GUARD | 0 | 3 (held cost) | reduces BITE/CLAW damage taken by 65%; **punishes** an incoming CHARGE instead of absorbing it |
| RETREAT | 0 | — (regains 15 stamina) | makes the foe's attack whiff entirely this tick; capped at `MAX_CONSECUTIVE_RETREATS` (2) in a row before the fighter is "cornered" and must act |

Resolution (`DuelArena._land_attack`): a RETREAT always causes an incoming
attack to whiff. A GUARD absorbs BITE/CLAW at 35% damage, but a CHARGE into
a GUARD backfires on the *charger* (8 recoil damage + a stamina penalty) —
GUARD beats CHARGE, CHARGE beats a flat-footed opponent, RETREAT beats
everything but is rationed. Running out of stamina (`stamina <= 0`) forces
GUARD and applies a 1.5× damage-taken multiplier (`is_staggered`) until
stamina recovers.

### Downed / finisher window

A CHARGE that lands clean and drops the defender to ≤20% max health (but
doesn't kill them outright) knocks them **DOWNED** instead of ending the
duel. The very next tick is a dedicated finisher window: no normal moves
are chosen that tick — only the attacker's `would_do(&"finish_downed_foe")`
resolves to either:

- **FINISH**: lethal damage, duel ends `&"finished_while_downed"`, and
  `reinforce_belief(&"finish_downed_foe", +0.22)` fires on the finisher
  immediately (not deferred to duel end — see below).
- **MERCY**: the downed fighter recovers to a 22%-health floor and gets
  back up, duel continues, and `reinforce_belief(&"finish_downed_foe",
  -0.16)` fires on the would-be finisher immediately.

If the fighter on the finishing end has `is_player_side = true`, that same
moment also nudges the shared `Naklon` scalar (`+0.02` cruelty on FINISH,
`-0.02` mercy on MERCY) — a duel fought by the player's own Avatar reflects
on the god, not just the beast. Both demo fighters have `is_player_side =
false`, so no Naklon movement is visible in the demo; this is exercised
only when a future caller (e.g. `campaign/` or `world/sanctum/`) marks one
combatant as the player's.

Only one downed/finisher-window can be pending at a time; if both fighters
somehow land a qualifying CHARGE in the same tick, the second is treated as
a plain hit rather than overwriting the first's pending window (see the
comment at the `_finisher_pending.is_empty()` guard in `duel_arena.gd`) —
a real, if rare, edge case, handled rather than silently dropped.

## What this package reads from beliefs

| Tag | Read where | Effect |
|---|---|---|
| `&"retreat_when_hurt"` | `_choose_move`, when own health ≤ 35% and not "cornered" | if `would_do` is true, RETREAT is chosen over anything else |
| `&"press_advantage"` | `_choose_move`, when foe's health ≤ 45% | if `would_do` is true, CHARGE (or BITE if under-stamina) is chosen |
| `&"guard_instinct"` (invented — not in the brief's example list, documented here for package M) | `_choose_move`, neutral exchanges only | `get_belief() * 0.5` is the probability of turtling up with GUARD that tick |
| `&"finish_downed_foe"` | `_resolve_finisher_window` | `would_do` decides FINISH vs MERCY |

## What this package writes back into beliefs

Two separate feedback moments, both real, both documented rather than
asserted:

1. **Immediate, at the finisher window** (see above): `finish_downed_foe`
   is reinforced the instant the choice is made, regardless of who
   eventually wins the duel — "did the kill/mercy feel right" is treated as
   its own, faster signal than the overall outcome.
2. **At `duel_ended`**: the winner gets `reinforce_belief(tag, +0.12 *
   usage_ratio)` and the loser gets `reinforce_belief(tag, -0.05 *
   usage_ratio)` for `press_advantage` and `retreat_when_hurt`, where
   `usage_ratio` = how often that tactic was actually used relative to how
   often it had an *opportunity* to be used this duel (tracked live via
   `press_advantage_uses/_opportunities` and `retreat_hurt_uses/
   retreat_opportunities` on `AvatarCombatant`) — a fighter who was never
   badly hurt doesn't get a false `retreat_when_hurt` bump just for
   winning. `guard_instinct` gets a flat `±half-magnitude` bump if that
   fighter ever punished an incoming CHARGE with GUARD this duel.

This is exactly "winning duels reinforce whatever behavior was used,"
implemented as a real proportional-credit pass, not a stub.

## Growth stage → combat stats

`AvatarCombatant.get_growth_stage()`/the growth scalars decide
`max_health` and `damage_scalar` (`max_stamina` is deliberately **not**
growth-scaled — endurance is written up as a fatigue/skill trait, not a
size trait). When no live Avatar is wired, a local fallback curve
(`GROWTH_STAT_CURVE = [0.55, 0.8, 1.0, 1.3]` for stages 0..3) stands in for
K's real per-stage table. The demo scene deliberately pits a small,
aggressive stage-1 fighter against a bigger, cautious stage-3 fighter so
the "growth visibly affects combat" claim is something you can actually
watch happen, not just read as true in a comment — the elder is visibly
larger (body mesh scales by the cube root of its health multiplier, so it
reads as size, not a paint-can wobble) and hits harder per landed blow.

## Voices triggers introduced (for package M)

| Trigger | Context dict | When |
|---|---|---|
| `&"duel_foe_finished_while_downed"` | `{finisher: String, downed: String}` | a downed fighter is killed by the finisher choice |
| `&"duel_mercy_shown"` | `{spared_by: String, downed: String}` | a downed fighter is spared instead |
| `&"duel_ended"` | `{winner: String, loser: String, finish_type: String}` | any duel concludes with a winner/loser (not fired on a draw) |

These are new trigger names invented for this package; no line pools exist
for them yet (`systems/voices/voice_lines.gd` is package M's file — not
touched here). `Voices.react()` on an unknown trigger is a documented no-op
in `voices.gd`, so calling these before M writes lines for them is safe.

## Scoped out

- **No physical hitboxes/animation rig.** Combat is entirely stat-driven
  (health/stamina/move-type), matching the "prefer procedural over
  hand-authored art" guidance — the visual layer is primitive-mesh lunges,
  crouches, and collapses, not real bite/claw animation or collision
  detection between two creature bodies. A real creature model (package
  K's Avatar mesh) can be swapped in place of `avatar_combatant.tscn`'s
  placeholder capsule/box without touching `duel_arena.gd` at all, since
  the arena only ever talks to the `AvatarCombatant` script API.
- **No player-controlled duel.** Both fighters in the demo are AI; nothing
  here reads input. A future player-vs-Avatar duel would need an input
  layer that produces the same `Move` enum choices this package already
  consumes — not built here, since the brief scoped this package around
  the belief-driven AI loop and the growth/belief feedback wiring, not
  player controls.
- **No networking.** `modes/skirmish/` + `net/` (package O) own multiplayer;
  a duel here is entirely local/deterministic-per-client and would need
  explicit synchronization work to be fair over a network, which is out of
  this package's scope.
- **No persistence into campaign/quest state.** A duel's outcome only
  mutates the two `AvatarCombatant` nodes and (optionally) `Naklon`; nothing
  here writes to `GameState` or a quest log. `campaign/` (package S) is the
  natural owner of "a duel result unlocks/changes X."
- **Balance numbers are a first, playable pass**, not a tuned one — every
  damage/stamina/threshold constant lives at the top of `duel_arena.gd` in
  one place specifically so a future tuning pass doesn't have to hunt for
  them.

## Assets used

None. Every mesh in this package (`CapsuleMesh`, `BoxMesh`, `CylinderMesh`
for the demo arena floor) is a Godot primitive built and materialed in code
or in the `.tscn`, per the "prefer procedural" guidance — no external
texture/model/audio files were downloaded for this package.
