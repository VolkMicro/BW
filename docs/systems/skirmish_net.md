# Skirmish mode & Nine Thrones networking — Package O

Owns: `modes/skirmish/`, `net/`, and this doc. Depends on `core/` per
`docs/systems/OWNERSHIP.md`. Reads (never edits) `actors/louhi/`,
`systems/faith/reach.gd`, `systems/voices/`, `systems/weather/`.

## What this is, and isn't

Two independent, real, working systems that share an owner but not a hard
dependency on each other:

- **`modes/skirmish/skirmish_scenario.gd`** (`class_name SkirmishScenario`,
  extends `Node`) — a bounded, self-contained skirmish session: a small
  subset of villages (not the full open-ended campaign island), a real
  timer, a real win condition, and an optional opponent — either
  `actors/louhi/louhi_director.gd` (package N's real presence AI, retuned
  to a much faster pace) or a Nine Thrones networked match. It runs fine
  with no networking at all.
- **`net/network_manager.gd`** (`class_name NetworkManager`, extends
  `Node`) — "Nine Thrones" networking: real multiplayer over Godot 4.3's
  high-level API (`ENetMultiplayerPeer` + `@rpc`), not a description of
  one. It runs fine with no `SkirmishScenario` present at all.

Both follow the exact shape `actors/louhi/louhi_director.gd` established as
this repo's pattern for "a real, complete system that isn't wired into any
scene yet": a real script, a `class_name`, a one-node wrapper `.tscn` ready
to be instanced by a future integration pass, and this doc stating plainly
what's wired vs. not. **Neither is registered in `project.godot`** —
package O may not edit that file per `docs/systems/OWNERSHIP.md`.

## Honesty norm — what is and isn't verified

Per this repo's engineering discipline (see `README.md` "What this
repository is, honestly" and `docs/systems/louhi.md`'s own "Scoped out"):

- **Verified by careful reading/reasoning, not by execution:** every file
  in this package. This session could not run
  `godot --headless --path . --check-only` (a coordinating process runs
  one consolidated check after all parallel packages land, to avoid
  concurrent Godot processes corrupting the shared `.godot/` import
  cache), so nothing here was verified by actually parsing or running it
  in Godot. Every script was proofread by hand for `class_name`
  collisions (checked against every existing `class_name` in the repo —
  none), matching parentheses/brackets (checked programmatically, not
  just by eye), consistent tab indentation, and RPC/signal signatures
  matching their call sites.
- **What real multi-client testing would require, and could NOT be
  performed here:** `net/network_manager.gd`'s actual networked behavior —
  a real ENet handshake, RPCs actually crossing a socket, two independent
  `Naklon`/`GameState` instances converging — needs at least two separate
  Godot client processes talking to each other. This sandbox has **no
  GPU** and this session could not launch a second Godot process to test
  against the first. `net/network_manager_test.gd` /
  `network_manager_test.tscn` is a real, usable manual test harness (Host
  / Join buttons, a live status readout, a signal-driven event feed) built
  for exactly this purpose, but it has **not been run**. The honest
  claim is: this code is correct *per the documented Godot 4.3 high-level
  multiplayer API* as best as careful reading can establish, not
  "tested and confirmed working across real separate clients."
- **What IS effectively exercised by reasoning alone:** `perform_conversion()`
  and `_apply_local()` on `NetworkManager` fall through to the exact same
  `Reach.convert_via_help/terror/missionary` calls single-player code
  already uses whenever `is_networked()` is false — that path has no new
  logic of its own, it's a direct pass-through, so its correctness rests
  entirely on `systems/faith/reach.gd` (package J), already a landed,
  presumably-checked file.
- **`modes/skirmish/skirmish_scenario_demo.tscn`** is the one piece of
  this package that — if actually opened in the editor/engine — would be a
  real, self-contained, watchable proof: it spawns real `Village`
  resources into the real `GameState`, a real (retuned) `LouhiDirector`,
  and simulates player input via the same public `Reach.convert_via_help()`
  any real conversion uses. This was not executed here either (no GPU),
  but unlike the networking side, nothing about it depends on a second
  process or real sockets — it's exactly the kind of thing the
  coordinator's consolidated check can exercise along with every other
  package's demo scenes.

## `modes/skirmish/skirmish_scenario.gd`

### Reuses, doesn't reinvent

Villages in a skirmish are real `Village` resources
(`core/village.gd`) registered into the real `GameState.villages`
Dictionary via `GameState.register_village()`
(`core/game_state.gd:40-42`) — the exact same call every other package
uses. Conversion mechanics run through the real
`systems/faith/reach.gd` (package J) `convert_via_help/terror/missionary`
methods. Alignment is the real `Naklon` autoload. The only genuinely new
bookkeeping this file owns is (a) which small set of village ids belongs
to *this* bounded session (`village_ids`) and (b) the session's own
timer/win-condition — nothing else in the codebase has a concept of a
scored, time-boxed session; `GameState`'s campaign is intentionally
open-ended.

If `village_ids` is left empty (the default), `_spawn_default_villages()`
creates one small village per culture already loaded into
`GameState.cultures` (populated unconditionally by
`core/game_state.gd:26-38` at boot) — a compact ~30m-radius cluster,
~12 population each, modest starting `faith_fraction` — and registers them
under deterministic ids (`skirmish_<culture_id>`). This makes the node
runnable completely standalone, the same guarantee
`actors/avatar/combat/duel_arena_demo.gd` makes for package L. A future
integration pass (`world/sanctum`, `campaign/`, or a menu in `ui/`) can
instead populate `village_ids` with real, already-registered campaign
village ids before `start_scenario()` runs, so "a skirmish" can just as
well be a scored subset of the real campaign island rather than a
generated one.

### Opponent modes

```gdscript
enum Opponent { NONE, LOUHI_PRESENCE, SECOND_GOD_NETWORKED }
```

- **`NONE`** — a bare sandbox: villages exist, the session timer runs, no
  opponent contests anything. Useful as a tutorial-weight space or a pure
  timer-based challenge.
- **`LOUHI_PRESENCE`** — `_spawn_louhi_opponent()` loads
  `actors/louhi/louhi_director.gd` **by script path, not by `class_name`**
  (`load("res://actors/louhi/louhi_director.gd").new()`), the same
  defensive pattern `louhi_director.gd` itself uses for its own
  `/root/DuelArena` hook (`get_node_or_null` + `has_method`/`has_signal` +
  `.call()`/`.connect(name, Callable)`), so a rename or removal on
  package N's side degrades to "no opponent" rather than a parse error in
  this file. `LouhiDirector`'s pacing (`evaluation_interval_sec` 75s
  default, 5-7 minute patience timers — see `docs/systems/louhi.md`) is
  built for an open campaign that can run for hours; before `add_child()`,
  this file sets her `evaluation_interval_sec` / `tier1_patience_sec` /
  `tier2_patience_sec` / `post_resolution_cooldown_sec` via
  `Object.set()` to skirmish-scaled defaults (10s / 35s / 45s / 20s) —
  exactly the same `@export` fields `docs/systems/louhi.md` documents as
  designer-tunable "without touching code," turned from a script instead
  of the Inspector. Her `sign_occurred`/`sign_relented` signals are
  forwarded through this scenario's own `louhi_sign`/`louhi_relented`
  signals, so a consumer of `SkirmishScenario` never needs to know
  `LouhiDirector` exists at all.
- **`SECOND_GOD_NETWORKED`** — no Louhi opponent is spawned. Instead, if
  `network_manager_path` resolves to a `net/network_manager.gd` node that
  `is_hosting()`, `start_scenario()` calls its
  `assign_home_villages(village_ids)` to hand starting villages to
  whichever seats have already joined. Village ownership for the tally
  (below) is read from `NetworkManager.get_village_owner()` rather than
  `Village.loyal_to_rival`, since that boolean means specifically
  "belongs to Louhi" everywhere else in the codebase (see
  `actors/louhi/louhi_director.gd`'s own comment on why it's the one flag
  `Village` exposes for that) and does not extend to "one of up to nine
  living players." **Combining `LOUHI_PRESENCE` and
  `SECOND_GOD_NETWORKED` in the same match is not attempted in this
  pass** — see "Scoped out."

### Win condition / tally

`_tally()` (called every `_process` tick) reads `GameState`/`Village`
directly — no duplicate scoreboard — and returns
`{player_count, rival_count, contested_count, average_faith_fraction}`.
Single-player: a village counts as `rival` if `loyal_to_rival`, `player`
if `faith_fraction >= 0.999` (exactly `Village.is_fully_converted()`'s own
threshold, `core/village.gd:37-38`, so "win the skirmish" and "fully
convert a village" never disagree), else `contested`. Networked: a
village counts toward `player_count` if any seat owns it (per
`NetworkManager.get_village_owner()`), else `contested_count`. The
scenario ends (`scenario_ended(reason, tally)`) when either side sweeps
every village in play (`&"rival_swept_board"` / `&"player_swept_board"`
— the latter only checked in non-networked modes, since a networked sweep
by one seat among nine isn't "the player" winning in any single-sided
sense) or when `session_duration_sec` elapses (`&"timeout"`), or when
`abort_scenario()` is called early (`&"aborted"`). `_tally()` also emits
`village_claimed(village_id, state)` on every real state transition
(change-detected against `_last_state`, not fired every frame).

### Public API

```gdscript
signal scenario_started(village_ids: Array[StringName])
signal scenario_ended(reason: StringName, tally: Dictionary)
signal village_claimed(village_id: StringName, state: StringName)
signal louhi_sign(tier: int, village_id: StringName, description: String)
signal louhi_relented(village_id: StringName, from_tier: int)

func start_scenario() -> void
func abort_scenario() -> void
func is_running() -> bool
func get_elapsed() -> float
func time_remaining() -> float
```

`@export`ed tuning: `village_ids`, `session_duration_sec`, `opponent_mode`,
`autostart`, the four `louhi_*` retuning fields, `network_manager_path`.

## `net/network_manager.gd`

### The sync model

Real Godot 4.3 high-level multiplayer: `ENetMultiplayerPeer`,
`multiplayer.multiplayer_peer`, `@rpc`-annotated methods called via
`method_name.rpc(...)` / `method_name.rpc_id(id, ...)` (the current Godot
4.x calling convention — the same pattern `systems/voices/voices.gd`'s own
`load(...).new()` idiom mirrors for defensive instancing, though that file
predates any networking need). **What must agree across every peer, and
why:**

1. **The seat roster** — `int peer_id -> int seat_index` (1..9,
   `MAX_SEATS`), assigned host-side in `_assign_seat()` on
   `peer_connected`, taking the lowest free index so a seat vacated by a
   disconnect can be re-taken by the next joiner.
2. **Village ownership** — `StringName village_id -> int peer_id`
   (`village_owner`, `0` = unclaimed) — "whose god controls which
   village," exactly what the brief asks for. Authoritative on the host,
   mirrored to every peer via `_rpc_apply_village_state`.

**Naklon is deliberately NOT synchronized as shared/authoritative state.**
`core/naklon.gd` is a plain autoload; every peer's OS process has its own
independent `Naklon` instance representing only that peer's own god.
`perform_conversion()` always runs `Reach.convert_via_*` **locally first**
on the acting peer's own machine — identical to single-player — which is
what correctly moves *that* peer's own `Naklon` and fires *that* peer's
own `Voices.react()` remark, with no per-player special-casing needed
anywhere. What IS mirrored, read-only, is `player_naklon: Dictionary` (`int
peer_id -> float`), purely so other gods could someday be shown each
other's alignment (a future diegetic "their throne looks colder now" cue);
it is never applied to drive any other peer's own gameplay.

**Why the host never calls `Reach.convert_via_*` on a remote peer's
behalf:** doing so would shift the *host's own* local `Naklon` for a
different player's action — clearly wrong attribution.
`_server_recompute_gain()` instead mirrors `reach.gd`'s private
`_grow_faith()` (`systems/faith/reach.gd:126-141`) using **only** Reach's
public constants (`HELP_GAIN_PER_AMOUNT`/`HELP_CEILING` at
`reach.gd:25-26`, `TERROR_GAIN_PER_AMOUNT`/`TERROR_CEILING` at
`reach.gd:30-31`, `MISSIONARY_CEILING` at `reach.gd:35`) and public
methods (`Reach.effectiveness()` at `reach.gd:51`, `Reach.register_use()`
at `reach.gd:60`) plus `GameState.set_faith_fraction()`
(`core/game_state.gd:57-64`) — never `convert_via_help/terror/missionary`
themselves, and never `Naklon`/`Voices`. This is the one place in this
package that duplicates a formula instead of calling through to it,
because Reach's only public entry points for this math are inseparable
from their Naklon/Voices side effects; a comment at the top of
`_server_recompute_gain()` flags that it needs a matching update if
`reach.gd`'s private formula ever changes.

**Full flow for a remote peer's action** (`perform_conversion()` on a
non-host peer): apply locally first (own Naklon/Voices, immediate
feedback) → `_rpc_request_action.rpc_id(1, ...)` to the host → host
validates ownership, recomputes via `_server_recompute_gain()` against its
own authoritative `GameState` copy (a *separate* process's memory from the
acting peer's — this is not a double-count, it's two independent updates
to two independent copies) → host broadcasts
`_rpc_apply_village_state.rpc(...)` to everyone, which snaps every peer's
local copy (including the acting peer's own optimistic guess) to the
authoritative number. This is standard client-side prediction / server
reconciliation: the two numbers agree in the common case (nothing else
touched that village meanwhile) and only visibly correct on an actual race
between two peers acting on the same village in the same instant.

**For the host acting as a player itself**, `perform_conversion()` takes a
simpler path: `_apply_local()` alone is *both* the optimistic and the
authoritative update, since the host's `GameState` copy is the one true
copy — no RPC round-trip to itself, no second gain application.

### Real Godot networking gotcha, flagged plainly

Godot's high-level RPC dispatches by matching **NodePath** across peers —
a `.rpc()` call only reaches the "same" node on a remote peer if that node
sits at an identical path from the scene root on every peer. Whoever
instances `NetworkManager` into a real scene must place it at the same
path on the host and every joining client (e.g. a fixed child of a
lobby/menu scene loaded identically everywhere), or RPCs silently fail to
route. This package cannot enforce that from inside its own script, so
it's flagged here — and in a comment at the top of `network_manager.gd` —
rather than left to be discovered.

### Public API

```gdscript
signal server_started(port: int)
signal join_requested(address: String, port: int)
signal joined_server()
signal connection_failed()
signal server_disconnected()
signal seat_assigned(peer_id: int, seat_index: int)
signal seat_freed(peer_id: int, seat_index: int)
signal village_ownership_changed(village_id: StringName, owner_peer_id: int)
signal player_naklon_changed(peer_id: int, value: float)
signal action_rejected(village_id: StringName, reason: String)

func host_game(port: int = DEFAULT_PORT, max_players: int = MAX_SEATS) -> Error
func join_game(address: String, port: int = DEFAULT_PORT) -> Error
func close_connection() -> void
func is_hosting() -> bool
func is_networked() -> bool
func get_local_peer_id() -> int
func get_seat_for_peer(peer_id: int) -> int
func get_village_owner(village_id: StringName) -> int
func assign_home_villages(candidate_village_ids: Array[StringName]) -> void  # host-only
func perform_conversion(village_id: StringName, method_id: StringName, amount: float) -> void
```

`MAX_SEATS = 9` ("Nine Thrones"), `DEFAULT_PORT = 9091` (arbitrary, no
real-world service registered on it), `UNCLAIMED = 0`.

### `net/network_manager_test.gd` / `.tscn`

A manual, human-in-the-loop test harness — Host/Join buttons, an address
field, a live status line (`is_networked()`/`is_hosting()`/seat roster),
and an event feed wired to every `NetworkManager` signal. **Not an
automated test and not executed in this session** (see "Honesty norm"
above). To really verify this package: run two separate instances of this
project, open this scene in both, Host in one, Join `127.0.0.1` (same
port) in the other.

## Integration points (exact file:line references)

- `core/game_state.gd:40-42` (`register_village`), `:44-45`
  (`get_village`), `:57-64` (`set_faith_fraction`) — read/written by both
  `SkirmishScenario._spawn_default_villages()` and
  `NetworkManager._server_recompute_gain()`/`_rpc_apply_village_state()`.
- `core/village.gd:15-16` (`faith_fraction`, `loyal_to_rival`), `:37-38`
  (`is_fully_converted()`) — `SkirmishScenario`'s
  `VICTORY_FAITH_FRACTION` constant matches this threshold exactly.
- `core/naklon.gd:7` (`naklon_changed` signal), `:39-40` (`shift()`) —
  `NetworkManager._on_local_naklon_changed()` listens to the signal;
  `shift()` itself is only ever called indirectly, via
  `Reach.convert_via_*`, never directly by this package.
- `systems/faith/reach.gd:25-35` (public gain/ceiling constants), `:51`
  (`effectiveness()`), `:60` (`register_use()`), `:126-141`
  (`_grow_faith()`, mirrored not called), `:143-190`
  (`convert_via_help/terror/missionary`) — see "The sync model" above.
- `actors/louhi/louhi_director.gd` (whole file, package N) — instanced
  defensively by `SkirmishScenario._spawn_louhi_opponent()`; its
  `evaluation_interval_sec`/`tier1_patience_sec`/`tier2_patience_sec`/
  `post_resolution_cooldown_sec` `@export` fields are retuned via
  `Object.set()`; its `sign_occurred`/`sign_relented` signals are
  forwarded.
- `docs/systems/avatar_combat.md` ("No networking" in its "Scoped out"
  section) explicitly defers multiplayer duels to this package.
  `actors/avatar/combat/duel_arena.gd` (`class_name DuelArena`) is a
  complete, real, local 1v1 duel referee this package could hook a
  networked duel challenge into later — **not attempted in this pass**;
  see "Scoped out" below.

## Scoped out

- **No PvP contest for an already-claimed village.** Ownership in a Nine
  Thrones match only transfers unclaimed → claimed, first-valid-request-
  wins, arbitrated by the host. Taking a village away from another living
  player (e.g. terror-converting a rival-owned village toward a flip) is
  not implemented — the sync primitive (`village_owner`, authoritative on
  host, broadcast to everyone) is real and ready for a future pass to add
  real contest rules on top of.
- **No reclaim/abdication rule for a disconnected peer's villages.** A
  disconnected peer's seat is freed (`seat_freed`), but their villages
  stay marked as theirs rather than reverting to unclaimed — an absent
  ruler's throne sits empty but still claimed, not silently redistributed.
- **No combination of `LOUHI_PRESENCE` and `SECOND_GOD_NETWORKED` in one
  match.** A skirmish is either single-player-vs-Louhi or a Nine Thrones
  match among living players in this pass, never both at once — a
  reasonable, evocative future combination ("nine gods and Louhi") that
  wasn't attempted here given the scope of a first pass.
- **No networked duel.** `actors/avatar/combat/duel_arena.gd` (package L)
  is a complete, real, local 1v1 referee; hooking a Nine Thrones "duel
  challenge between two seated gods" into it (synchronizing move choices,
  or running the duel authoritatively on the host and broadcasting
  results) is the natural next step this package's sync model was built
  to support, but is not implemented here.
- **No lobby/menu UI.** `host_game()`/`join_game()` are real, callable
  methods; `net/network_manager_test.gd` is a functional but bare manual
  test harness, not a real menu. `ui/` (package T) is the natural owner of
  an actual Nine Thrones lobby screen.
- **`Voices.react()` commentary in a networked match only plays on
  whichever peer's own `_apply_local()` call triggered it** — `Voices` is
  a per-process autoload with no network hook of its own, so a remote
  peer's action never makes *your* Domovoi/Hiisi comment. A future pass
  could RPC-forward specific `Voices` triggers alongside
  `_rpc_apply_village_state`, but that's not attempted here.
- **No real multi-client testing.** See "Honesty norm" above — this is
  the single most important thing scoped out of this pass, stated as
  plainly as possible rather than left to be discovered.
- **Balance numbers (skirmish session length, Louhi retuning constants,
  default village population/faith_fraction) are a first, playable pass**,
  not a tuned one — every constant lives at the top of
  `skirmish_scenario.gd` in one place specifically so a future tuning pass
  doesn't have to hunt for them.

## Assets used

None. Every file in this package is pure GDScript (plus trivial wrapper
`.tscn` files whose only visual content is `CanvasLayer`/`Label`/`Button`
UI nodes) — no textures, audio, or models were downloaded or referenced
for this package.
