# Louhi of Pohjola — the rival god AI (package N)

## What she is, and isn't

Louhi is a **presence-first AI**, not a scripted boss sequence. She is
implemented as a slow utility-AI loop (`actors/louhi/louhi_director.gd`,
`class_name LouhiDirector`) that periodically looks at the board, scores
how exposed the player's weakest converted village is, and — only after
waiting out a long patience timer with no improvement — escalates one of
three "signs." She never puts up UI text. Every sign is a real change to
world state (weather, a village's `loyal_to_rival` flag, a missing relic)
paired with a signal other systems can render diegetically. If nothing is
listening, nothing visibly happens — that silence is itself in character.

This keeps faith with `docs/audit/respect_audit.md`'s existing commitment,
which this package does not touch or reinterpret: Louhi is drawn straight
from her own *Kalevala* role — patient, acquisitive, a hoarder and a
bargainer, "no invented cruelty added beyond what the source epic already
gives her." Nothing in this implementation adds cruelty beyond that: tier 1
is weather, not violence; tier 2 is silence, not a raid; tier 3 takes a
*thing* (a relic) or asks for a *reckoning* (a duel), never depicts her
harming a person on-screen. She is never announced as a monster, never
mustache-twirls, and the escalation timers are measured in real minutes so
she reads as patient, not aggressive.

## The loop

`LouhiDirector` runs `_process(delta)` accumulating a few plain timers
(no `Timer` nodes needed — this keeps the whole state machine legible in
one file) and calls `_evaluate()` every `evaluation_interval_sec` (default
**75s**). What `_evaluate()` does depends on her current tier:

- **Tier 0 (dormant/scouting):** if not in post-resolution cooldown, she
  scores every village in `GameState.villages` and picks the single most
  "exposed" one to engage. Villages are skipped if they're already
  `loyal_to_rival` (already hers), below `min_faith_fraction_to_notice`
  (untouched — not a target, just unclaimed), at/above
  `ignore_above_faith_fraction` (too devoted to be worth contesting — this
  is a bargainer, not a completionist), or currently rebuff-cooled-down
  (see relenting, below). The exposure score blends normalized
  `faith_fraction` and `Reach.radius_for_village()` via exported weights
  (`faith_weight`/`reach_weight`, default 0.6/0.4) so either the brief's
  "lowest faith_fraction" or "lowest Reach" criterion — or a blend of
  both — drives targeting; either weight can be set to 0 to get a pure
  single-metric evaluator.
- **Tier 1 (cold front already sent):** each evaluation tick she checks
  whether the target's `faith_fraction` has risen by
  `relent_improvement_threshold` (default 0.07) since she started
  watching. If so, she **relents** (see below) instead of escalating — a
  bargainer doesn't press a bad trade. Otherwise, once `tier1_patience_sec`
  (default 300s / 5 min) has elapsed with no improvement, she escalates to
  tier 2.
- **Tier 2 (village gone silent):** no relent check happens here — see
  "Why tier 2 is a one-way door" below. After `tier2_patience_sec` (default
  420s / 7 min), she fires tier 3.
- **Tier 3 fires once, then resolves:** it is not a held state; the moment
  it fires she either steals a relic or issues a duel challenge (see
  below), then returns to tier 0 and starts a `post_resolution_cooldown_sec`
  (default 600s / 10 min) dormant period before scouting again.

She commits to exactly one target at a time once engaged (tier 1 or 2) —
target re-evaluation only happens from tier 0. She does not abandon an
in-progress approach because a shinier village appeared; that would read
as impulsive, which is the one thing she is explicitly not.

## The three signs

### Tier 1 — cold front
A cosmetic weather nudge written directly into `Weather.current` (the
`systems/weather/weather.gd` autoload). **Built against the documented
stub contract** (`wind_dir_deg`/`wind_speed`/`precipitation`/
`cloud_cover`/`temperature_c`/`is_storm`/`source` — package P's territory
per `docs/systems/OWNERSHIP.md`, not yet landed as of this pass; the stub
in the repo when this was written was exactly the Dictionary shape
described in the brief). `LouhiDirector` caches the pre-existing weather,
merges in a light cold snap (raised wind/cloud/precipitation, lowered
temperature, `is_storm` stays **false** — "she is a sign, not a tantrum"),
sets `source = "louhi_sign"`, and emits `Weather.weather_changed`. The
front eases back to the cached weather on its own after
`cold_front_duration_sec` (default 240s), or immediately if she relents
early. Wind direction defaults to "out of the north" as a small, harmless
nod to Pohjola without any mechanical weight riding on it.

**Risk flagged for integration:** if package P's real weather simulation
has, by the time this runs, replaced the stub with a live per-frame sim
that overwrites `Weather.current` itself, a tier-1 write here could get
stomped almost immediately after being set. This wasn't fixable from this
package without depending on P's not-yet-landed API, so it's flagged here
rather than silently assumed away — see "Scoped out."

### Tier 2 — the village goes silent
`LouhiDirector` sets `village.loyal_to_rival = true` directly on the
`Village` resource (obtained via `GameState.get_village()`) and emits
`GameState.village_lost.emit(village_id)` — the same signal-emission
pattern already used elsewhere in the codebase for village loss (see
`actors/villagers/villager.gd`'s population-extinction path), so this
plugs into whatever already listens for "a village is gone" (confirmed:
`systems/voices/voice_lines.gd` already has a `village_lost` trigger pool
authored by package M, reused here — see Voices integration below).

**Which flag, and why:** `core/village.gd` exposes exactly one boolean for
"this belongs to Louhi now" — `loyal_to_rival`. There is no separate
"claimed pre-conversion" flag, and none was needed: `loyal_to_rival` reads
correctly whether `faith_fraction` was 0 (an untouched village she claimed
before the player ever reached it) or partway converted to the player (the
case this director's own target selection actually exercises, since
scouting only considers villages at/above `min_faith_fraction_to_notice`).
This package uses the single flag uniformly rather than inventing a second
one Village doesn't have.

**Why tier 2 has no relent check, and is a one-way door for now:** once
`loyal_to_rival` is true, `Reach.radius_for_village()` returns 0 for that
village and every conversion method in `systems/faith/reach.gd`
(`convert_via_help`/`convert_via_terror`/`convert_via_missionary`)
short-circuits on `v.loyal_to_rival`. There is currently no reclaim
mechanic anywhere in the codebase for the player to contest this with, so
the tier-2→tier-3 patience timer is purely "how long she savors it" before
acting further, not a contest the player can still win. If a later package
adds a reclaim rite, this is the natural place to add a symmetrical relent
check.

### Tier 3 — stolen relic, or a duel challenge
Tier 3's mechanic is deliberately **global**, not village-local — by this
point the named village is already gone, so there's nothing left there to
threaten further. If `GameState.relics_held` is non-empty, she steals one
at random (`remove_at`) and the sign names it. If the player is holding no
relics, she instead attempts a duel challenge.

**Duel hook — documented contract, defensive call:**
`actors/avatar/combat/` (package L) was an **empty directory** when this
was written, so there was no existing API to read. `LouhiDirector` builds
against a documented, invented contract rather than guessing at internals:
an autoload or `/root` node named `DuelArena` exposing

```gdscript
func request_challenge(instigator: StringName, defender_village_id: StringName, stakes: Dictionary) -> void
```

The call site (`_attempt_duel_challenge`) is fully defensive:
`get_node_or_null("/root/DuelArena")` + `has_method("request_challenge")`,
so it silently no-ops (and the sign's description says so, in-fiction —
"no one yet standing who could answer a reckoning") rather than erroring
if L lands with a different shape, or hasn't landed at all. **If package L
lands with a different method name/signature, either update
`_attempt_duel_challenge` or have L's node also answer to
`request_challenge` on a node reachable at `/root/DuelArena`.**

## Relenting, resolving, abandoning

- `_relent(v, from_tier)`: fires `sign_relented`, reverts an active cold
  front immediately, blacklists that village from re-targeting for
  `rebuff_cooldown_sec` (default 900s / 15 min), and returns her to tier 0
  plus a `post_resolution_cooldown_sec` dormant period. This is the
  mechanical expression of "a bargainer only presses when the odds are
  hers" — reinforcing a threatened village is a genuine, working
  counterplay against tier 1.
- `_resolve_engagement()`: the normal path after tier 3 fires.
- `_abandon_engagement()`: a defensive fallback if a targeted village
  somehow leaves the board outside her own state machine (not expected in
  the current codebase, since `GameState` never removes villages, but kept
  since `get_village()` can return `null`).

## Integration with the foundation APIs

- **`core/game_state.gd`** — reads `GameState.villages` for scouting;
  reads/writes `Village.loyal_to_rival` and `GameState.relics_held`; emits
  the existing `GameState.village_lost` signal on tier 2, matching the
  emission pattern already used elsewhere in the codebase rather than
  inventing a new one.
- **`systems/faith/reach.gd`** — reads `Reach.radius_for_village()` as one
  input to exposure scoring. Never calls `Reach.register_use()` or any
  `convert_via_*` method — she isn't a conversion method herself, she's an
  opposing force, so she doesn't participate in miracle-fatigue
  bookkeeping.
- **`systems/weather/weather.gd`** — reads and writes `Weather.current`
  directly (see tier 1, above) and emits the existing
  `Weather.weather_changed` signal. Built against the stub's documented
  Dictionary shape per the brief; the "Scoped out" section below states
  the follow-up this implies once package P's real sim lands.
- **`systems/voices/voices.gd`** — calls `Voices.react(trigger, context)`
  on every sign and every relent. Reuses two trigger names package M
  (`systems/voices/voice_lines.gd`) had **already authored** before this
  package landed, rather than duplicating them:
  - `&"louhi_sighted"` (tier 1 cold front, and also fired on relent — both
    are "Louhi was here, then wasn't" beats) — M's existing pool ("Lock up
    anything that isn't nailed down...") fits both without changes.
  - `&"village_lost"` (tier 2) — M's existing pool already reads generically
    enough ("We lost {village}... won't be collecting devotion from. Ever.")
    to cover "defected to Louhi" as well as the population-extinction case
    it was originally written for.
  Two **new** trigger names are introduced for tier 3, since no existing
  pool covers "a relic went missing" or "a duel was demanded":
  - `&"louhi_relic_stolen"` — context: `{"village_id": StringName, "relic": StringName}`
  - `&"louhi_duel_challenge"` — context: `{"village_id": StringName}`
  `Voices.react()` no-ops safely (returns without emitting `remark`) if a
  trigger has no authored pool yet, so this package's use of two
  currently-empty triggers is safe by construction; a future pass on
  `systems/voices/voice_lines.gd` (package M's territory) can add pools for
  them without needing anything else to change.
- **`actors/avatar/combat/`** (package L) — documented defensive contract
  only; see Tier 3 above. Not a hard dependency.

## Instancing her (not an autoload)

`LouhiDirector` is **not registered in `project.godot`** — package N may
not edit that file per `docs/systems/OWNERSHIP.md`, and Louhi isn't in the
pre-registered autoload list (`Naklon`/`GameState`/`Reach`/`Voices`/
`Weather`/`MusicDirector`). `actors/louhi/louhi_director.tscn` is a
one-node wrapper scene (script attached to a plain `Node`) ready to be
instanced by whatever integration pass wires the campaign/world scenes
together — either as a child of `world/god_view.tscn`, or promoted to a
project.godot autoload in a later, deliberate edit outside this package's
scope. Until then, her code is real and complete but inert (no node in the
tree calling `_process`), which is stated here rather than left to be
discovered.

## Public API surface

Signals:
```gdscript
signal sign_occurred(tier: int, village_id: StringName, description: String)
signal sign_relented(village_id: StringName, from_tier: int)
signal engagement_began(village_id: StringName)
```

Read-only queries (for diegetic consumers — ambient audio/lighting/camera
systems that want to know "is something wrong right now" without reaching
into her internals):
```gdscript
func get_current_target() -> StringName
func get_current_tier() -> int      # 0 dormant, 1 or 2 engaged
func is_engaged() -> bool
func is_dormant() -> bool
```

`debug_force_evaluate()` exists as a QA/test hook only (forces the next
evaluation tick immediately instead of waiting out
`evaluation_interval_sec`); nothing in this package calls it.

All tuning constants (`evaluation_interval_sec`, both patience timers,
`relent_improvement_threshold`, `rebuff_cooldown_sec`,
`post_resolution_cooldown_sec`, the cold-front parameters, the scoring
weights, `enabled`) are `@export`ed on the node so a designer can retune
her pacing per-scene from the Inspector without touching code.

## Scoped out

- **No autoload registration / no automatic scene wiring.** She is a
  complete, working script and a ready `.tscn`, but package N cannot edit
  `project.godot` or `world/god_view.tscn` (foundation-owned), so nothing
  in the shipped scene tree currently instances her. Stated plainly rather
  than faked with a silent no-op node reference.
- **No resilience against package P's weather sim overwriting `Weather.current`
  every frame.** The tier-1 write is correct against the stub that existed
  when this was built (see the brief's own escape hatch: "if package P
  hasn't replaced the stub yet, write against the documented Dictionary
  shape... and note you built against the contract"). If P's landed
  simulation runs its own `_process` that recomputes `current` from scratch
  every frame, a tier-1 sign could be visually stomped within one frame of
  being set. The clean fix is a small addition on P's side (an `apply_event()`
  / external-override hook weather cells can blend in) rather than this
  package guessing at P's undisclosed internals; flagged here for whoever
  does the next weather pass.
- **No real duel resolution.** `actors/avatar/combat/` (package L) was
  empty when this was written. Tier 3's duel path is a documented,
  defensively-called contract (see above), not a fabricated fight — if L
  hasn't landed by the time a player reaches tier 3 with no relics held,
  the sign fires with an honest in-fiction line ("no one yet standing who
  could answer a reckoning") rather than silently pretending a duel
  happened.
- **No reclaim mechanic for tier-2-lost villages.** Nothing in the
  codebase currently lets the player win a `loyal_to_rival` village back,
  so tier 2 is presently permanent once it fires. This isn't something
  package N's brief asked for, so it wasn't invented here — but it's the
  natural next lever the tier 2→3 timer implies now, if a future
  package wants to add a genuine contest for lost villages instead of a
  pure timer.
- **No bespoke tier-3 voice lines yet.** `&"louhi_relic_stolen"` and
  `&"louhi_duel_challenge"` are new trigger names introduced by this
  package with no authored line pools (package M's `voice_lines.gd` had
  already landed before this package did). `Voices.react()` is safe to
  call on a trigger with no pool (no-op), so this doesn't crash or fake
  anything — it's simply quiet until a future voices pass adds real lines,
  exactly like any other un-authored trigger in the codebase.
- **No music/lighting reaction wired to her signals.** `engagement_began`,
  `sign_occurred`, and `sign_relented` are real, emitting signals — no
  consumer in `audio/` or `environment/` currently subscribes to them.
  Wiring an ambient mood shift to her presence is explicitly the kind of
  diegetic rendering the brief asks *other* systems to do; package N's
  job was to make the signals real and meaningful, not to also author
  every downstream reaction.

### Assets used

None. This package is pure GDScript (one script, one trivial wrapper
scene) — no textures, audio, or models were needed or pulled.
