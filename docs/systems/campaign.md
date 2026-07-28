# Campaign — quests, sigil scrolls, relics, Louhi's approach (package S)

## What this is, and isn't

`campaign/` gives real, structured meaning to two bare fields
`core/game_state.gd` has always had and nothing else touched —
`relics_held: Array[StringName]` (`core/game_state.gd:23`) and
`scrolls_known: Array[StringName]` (`core/game_state.gd:24`) — and adds a
real quest/objective tracker on top, including a set of quests that react to
`actors/louhi/louhi_director.gd`'s three signs ("Louhi's approach," this
package's own brief). Three files carry the three jobs:

- `campaign/relic.gd` / `campaign/relic_catalog.gd` — `Relic` (a
  `class_name Relic extends Resource`) and a static catalog of eight
  invented, respect-audit-checked relics.
- `campaign/scroll_book.gd` — `ScrollBook`, a stateless static utility
  bookkeeping `GameState.scrolls_known` against the nine real
  `SigilTemplates` rite ids.
- `campaign/quest.gd` / `campaign/quest_catalog.gd` / `campaign/campaign_manager.gd`
  — `Quest` (static content), `QuestCatalog` (ten authored quests), and
  `CampaignManager` (`class_name CampaignManager extends Node`), the
  per-playthrough tracker that activates/completes them.

Same shape as `actors/louhi/louhi_director.gd`: `CampaignManager` is a real,
complete, instantiable manager class, **not registered as an autoload**
(package S may not edit `project.godot`) and **not currently instanced
anywhere** in the shipped scene tree. `campaign/campaign_manager.tscn` is a
ready-to-instance one-node wrapper, exactly like
`actors/louhi/louhi_director.tscn`. See "Instancing it" below.

Everything here is pure GDScript data/logic. No new scenes beyond the one
wrapper, no textures, no audio.

## Relics

`RelicCatalog.build()` (`campaign/relic_catalog.gd`) returns a
`StringName -> Relic` dictionary, rebuilt fresh per call (cheap, not a
per-frame path — same rationale `SigilTemplates.get_raw_templates()` already
uses for its own static builder). Every relic is checked against
`docs/audit/respect_audit.md`'s hard rules; each `Relic.origin_notes` field
carries the one-line rationale inline, the same way each `Culture`'s own
`taboo_notes` does.

| id | Display name | Culture | Flavor (short) | Granted by |
|---|---|---|---|---|
| `fenrayt_raft_bell` | Raft-Bell of the Sinking | Fenrayt | A bell fished back out of a raft that should have gone under with the rest of that year's Sinking. | `q_fenrayt_sinking_witness` |
| `sankiln_firereading_bowl` | Firereading Bowl | Sankiln | Ash-grey ceramic, crazed white from a thousand hearth-readings. | `q_sankiln_firereading` |
| `raimborn_wavecall_horn` | Wavecall Horn | Raimborn | Whalebone, worn pale at the mouthpiece from every launch's held note. | `q_raimborn_wavecall` |
| `vainkeeper_grafting_knife` | Grafting Knife of the First Name | Vainkeeper | Carries the first name anyone ever grafted into a living tree. | `q_vainkeeper_grafting` |
| `warning_staves_bundle` | The Four Warning-Staves | *(none)* | Four staves, one per people, all recording the same warning against the Offering-Debt. | `q_four_debts_remembered` |
| `ninefold_tally_cord` | Tally-Cord of the Ninefold Sea | *(none)* | One knot per name a mortal has ever given the player god. | `q_ninefold_tally` |
| `waking_den_stone` | Waking-Den Stone | *(none)* | Worn smooth in a den no living creature dug — whichever Avatar species woke there. Grants epithet "First-Named". | `q_first_rite` |
| `louhi_hidden_sun_sliver` | Sliver of the Hidden Sun | *(none, Louhi's mythos)* | A curl of dull gold that doesn't shine but remembers shining. Grants epithet "Touched the Hidden Sun". | **nothing yet — see Scoped out** |

Sourcing highlights (full rationale in each entry's `origin_notes`):
`warning_staves_bundle` directly embodies respect_audit.md hard rule 7 — it
names each culture's own already-canon taboo (Offering-Debt / Ash-Debt /
Keel-Debt / Root-Debt from `data/cultures/*.tres`'s `taboo_notes`) as a
crime, never a practice. `louhi_hidden_sun_sliver` is drawn from the same
already-vetted Kalevala episode README.md's own phrase "hoarder of the sun"
already references (Louhi hiding the sun and moon in a mountain) — not an
invented cruelty, and a literary epic's own plot device, not a real sacred
object. `waking_den_stone` is deliberately generic across all three Avatar
species (`&"otso"`/`&"krukk"`/`&"sarv"`) rather than naming one, since
`GameState.avatar_species` is a player choice this package can't assume.

`CampaignManager.grant_relic(id)` appends to `GameState.relics_held` (no-op
if already held), emits `relic_gained`, calls `Voices.react(&"relic_found",
{"relic_id": id})`, and — if the relic's `grants_epithet` is non-empty —
calls `GameState.earn_epithet(text, "relic:" + id)`
(`core/game_state.gd:66`). `CampaignManager.get_held_relics() -> Array[Relic]`
resolves `GameState.relics_held`'s bare ids to real `Relic` data for a future
UI pass, skipping any id `RelicCatalog` doesn't recognize rather than
crashing on it (relevant today: `actors/louhi/louhi_director.gd:354`'s tier-3
theft calls `GameState.relics_held.remove_at(idx)` directly on a random held
id — this package's own lookup stays defensive against whatever state that
leaves behind).

## Sigil scrolls

`ScrollBook` (`campaign/scroll_book.gd`) is a stateless static utility (no
autoload, no instance) bookkeeping `GameState.scrolls_known` against the
nine real rite ids in `systems/sigils/sigil_templates.gd`'s
`SigilTemplates.DESCRIPTIONS` (`systems/sigils/sigil_templates.gd:22-32`):

- `ScrollBook.DEFAULT_KNOWN_RITES := [&"ward"]` — the one rite every
  village's first ask of an unproven god would reasonably be (protection),
  known from the start without any scroll.
- `ScrollBook.is_rite_unlocked(rite_id) -> bool` — true for a default rite
  or anything already in `GameState.scrolls_known`.
- `ScrollBook.learn_scroll(rite_id) -> bool` — appends to
  `GameState.scrolls_known` if `rite_id` is a real `SigilTemplates` id not
  already known; returns whether it actually changed anything.
- `ScrollBook.known_rite_ids()` / `locked_rite_ids()` — union/complement
  convenience for a future UI pass.

`CampaignManager.is_rite_unlocked()` / `.learn_scroll()` are thin wrappers
that additionally emit `scroll_learned` and a `Voices.react(&"scroll_learned", ...)`
remark — used by `_grant_rewards()` when a quest's `reward_scrolls` lands.
The other eight rites (`rain_call`, `path_gate`, `harvest`, `lumber`,
`repair`, `fire_arrow`, `lightning`, `storm`) are discovered one at a time
through `QuestCatalog`'s culture quests and the four-culture capstone (see
below).

**THE GATING GAP, stated plainly rather than fixed:** `systems/sigils/sigil_caster.gd`
(package F's territory — this package may not edit it) recognizes and fires
`rite_cast` (`systems/sigils/sigil_caster.gd:28`) for **any** of the nine
rites today regardless of `GameState.scrolls_known` — `_try_recognize()`
(`systems/sigils/sigil_caster.gd:147-166`) has no unlock check anywhere in
it before the `rite_cast.emit(rite_id, score)` call at line 162. Every rite
is fully castable from the very first mouse-drag with zero scrolls learned.
`ScrollBook.is_rite_unlocked()` is real, correct, and ready to be called —
it just isn't. The exact one-line fix, for whoever next touches
`sigil_caster.gd`:

```gdscript
# right before `rite_cast.emit(rite_id, score)` in _try_recognize():
if not ScrollBook.is_rite_unlocked(rite_id):
    stroke_finished.emit(false, rite_id, score)
    Voices.react(&"sigil_rejected", {"best_guess": rite_id, "confidence": score})
    return
```

Flagged here rather than patched, per this package's ownership scope.

## Quests

`QuestCatalog.build()` (`campaign/quest_catalog.gd`) returns ten authored
`Quest` resources. `CampaignManager` tracks each as `LOCKED` / `ACTIVE` /
`COMPLETE` (`CampaignManager.QuestState`) per playthrough — the static
`Quest` data never changes, matching the `Culture`/`Village` and
`Relic`/`relics_held` static-vs-runtime splits already in the codebase.

Activation and completion are event-driven, not polled — see
`CampaignManager._fire_campaign_event()`'s own doc comment for the full
vocabulary. Quick reference:

| Campaign event | Fired by |
|---|---|
| `&"any_village_converted"` | `GameState.village_converted` (`core/game_state.gd:9`), any culture |
| `&"culture_village_converted"` | same signal, filtered to the quest's `culture_id` |
| `&"first_epithet_earned"` | `GameState.epithet_earned` (`core/game_state.gd:11`), only the very first epithet a save ever earns |
| `&"rite_cast_any"` | `CampaignManager.notify_rite_cast()` — **flagged hook, not yet called by anything** (see below) |
| `&"louhi_tier1"` / `&"louhi_tier2"` / `&"louhi_tier3"` | `LouhiDirector.sign_occurred` (`actors/louhi/louhi_director.gd:43`), by tier |
| `&"louhi_tier1_resolved"` | `LouhiDirector.sign_relented` (`actors/louhi/louhi_director.gd:50`, `from_tier == 1`) **or** `sign_occurred(tier=2)` — either way the tier-1 engagement is over |

These are campaign/'s own vocabulary — never the same namespace as
`Voices.react()` triggers or `GameState`/`LouhiDirector` signals, even where
a campaign event is fired *from* one of those.

### The ten quests

| id | Title | Culture | Prereqs | Activates on | Completes on | Rewards |
|---|---|---|---|---|---|---|
| `q_first_rite` | The First Rite | — | none | boot | any rite cast* | relic `waking_den_stone` (grants epithet "First-Named") |
| `q_ninefold_tally` | Keeper of the Tally | — | none | boot | first epithet earned | relic `ninefold_tally_cord`, epithet "Keeper of the Tally" |
| `q_fenrayt_sinking_witness` | What the Bog Remembers | Fenrayt | none | boot | a Fenrayt village converts | relic `fenrayt_raft_bell`, scroll `repair`, epithet "Kept the Bog's Trust" |
| `q_sankiln_firereading` | Reader of Embers | Sankiln | none | boot | a Sankiln village converts | relic `sankiln_firereading_bowl`, scroll `fire_arrow`, epithet "Reader of Embers" |
| `q_raimborn_wavecall` | Named by the Tide | Raimborn | none | boot | a Raimborn village converts | relic `raimborn_wavecall_horn`, scroll `rain_call`, epithet "Named by the Tide" |
| `q_vainkeeper_grafting` | Grafted into the Grove | Vainkeeper | none | boot | a Vainkeeper village converts | relic `vainkeeper_grafting_knife`, scroll `harvest`, epithet "Grafted into the Grove" |
| `q_four_debts_remembered` | The Four Warnings | — | all four culture quests above | prereqs met (auto-completes same tick) | *(auto)* | relic `warning_staves_bundle`, scroll `storm`, epithet "Keeper of the Four Warnings" |
| `q_louhi_cold_wind` | Louhi's Approach: The Cold Wind | — | none | her tier-1 sign | tier-1 engagement resolves (relent or escalation) | epithet "Weathered Her Watching" |
| `q_louhi_silence` | Louhi's Approach: The Silence | — | none | her tier-2 sign | her tier-3 sign | epithet "Remembers the Silence" |
| `q_louhi_reckoning` | Louhi's Approach: The Reckoning | — | none | her tier-3 sign (auto-completes same tick) | *(auto)* | epithet "Marked by Pohjola" |

\* `q_first_rite` completes on `&"rite_cast_any"`, which nothing fires yet —
see the flagged `notify_rite_cast()` hook below. It is real and correctly
wired on `CampaignManager`'s side; it simply has no caller today.

### Louhi's approach, in detail

The three Louhi quests are the direct implementation of this package's
brief ("Louhi's approach" — a quest-log/narrative layer reacting to her
signals with named beats), built entirely off her four public, already-real
signals (`actors/louhi/louhi_director.gd:43,50,57`) and read-only queries
(`get_current_tier()`/`get_current_target()`/`is_engaged()`/`is_dormant()`,
`actors/louhi/louhi_director.gd:437-447`) — no edits to her file, per this
package's dependency scope.

- **Tier 1 (cold front) →** `q_louhi_cold_wind` activates. It resolves one
  of two ways her own state machine already supports: she relents
  (`sign_relented(village_id, from_tier=1)`) or she escalates
  (`sign_occurred(tier=2, ...)`, which also sets `Village.loyal_to_rival = true`
  at `actors/louhi/louhi_director.gd:321` and emits
  `GameState.village_lost` at line 322). Either way,
  `CampaignManager._on_louhi_sign_occurred`/`_on_louhi_sign_relented` fire
  the same `&"louhi_tier1_resolved"` campaign event, completing the quest.
  **Deliberately no differentiated reward for the two outcomes** — see
  Scoped out.
- **Tier 2 (the village goes silent) →** `q_louhi_silence` activates. There
  is genuinely nothing left for the player to defend at this point (her own
  doc: "a one-way door," no reclaim mechanic exists), so this quest's
  completion is tied to the *next* thing that happens — tier 3 — rather
  than any player action.
- **Tier 3 (relic stolen / duel demanded, `actors/louhi/louhi_director.gd:354`) →**
  `q_louhi_reckoning` activates and, since it's a pure narrative log-beat
  with nothing further to resolve (`auto_complete_on_activate = true`),
  completes in the same call. This also completes `q_louhi_silence` in the
  same event dispatch (see `_fire_campaign_event`'s activation-then-
  completion ordering) — the silence's resolution and the reckoning's
  arrival are the same moment.

### Public API surface

Signals:
```gdscript
signal quest_activated(quest_id: StringName)
signal quest_completed(quest_id: StringName)
signal relic_gained(relic_id: StringName)
signal scroll_learned(rite_id: StringName)
```

Queries: `get_quest_def(id)`, `get_quest_state(id) -> QuestState`,
`is_quest_available(id)`, `get_all_quest_ids()`, `get_active_quests()`,
`get_completed_quests()`, `get_locked_quests()`, `get_held_relics()`,
`get_relic_data(id)`, `is_rite_unlocked(id)`.

Mutators: `start_quest(id)` (manual/debug override — activates a LOCKED,
prerequisite-satisfied quest regardless of its `activation_trigger`),
`complete_quest(id)`, `grant_relic(id)`, `learn_scroll(id)`,
`notify_rite_cast(id)` (see flagged hook, below), `attach_to_louhi(node)`
(see below).

`@export var enabled: bool = true` gates the automatic event→quest
reactions only (same as `LouhiDirector`'s own `enabled`) — the mutator
methods above stay callable regardless, e.g. for a debug/QA panel.

## Instancing it (not an autoload)

`CampaignManager` is **not registered in `project.godot`** — package S may
not edit that file, and it isn't in the pre-registered autoload list
(`Naklon`/`GameState`/`Reach`/`Voices`/`Weather`/`MusicDirector`).
`campaign/campaign_manager.tscn` is a one-node wrapper (script on a plain
`Node`), ready to be instanced by whatever integration pass wires the
campaign/world scenes together — either as a child of `world/god_view.tscn`,
or promoted to a `project.godot` autoload in a later, deliberate edit
outside this package's scope. Until then, its code is real and complete but
inert, stated here rather than left to be discovered.

`_ready()` connects to `GameState.village_converted`/`epithet_earned`
directly and unconditionally once confirmed present (guaranteed
foundation autoload, same assumption `systems/faith/reach.gd` and
`systems/voices/voice_lines.gd` already make), then calls
`_try_autodiscover_louhi()` — a defensive, best-effort search
(`get_node_or_null("/root/LouhiDirector")`, then a recursive
`find_child("LouhiDirector", true, false)`) for whenever an integration pass
*does* instance her, exactly the same defensive shape her own
`_attempt_duel_challenge()` uses to find `/root/DuelArena`
(`actors/louhi/louhi_director.gd`'s own documented contract) — just with the
caller/listener roles reversed. `attach_to_louhi(node)` is also public, for
an integration pass that wants to wire the two explicitly instead of relying
on the path/name guess.

## Flagged cross-package hooks

- **For package F (`systems/sigils/`) or whoever next touches
  `sigil_caster.gd`:** the scroll-gating gap above — the exact one-line
  `if not ScrollBook.is_rite_unlocked(rite_id): return` (with the matching
  `stroke_finished`/`Voices.react` calls a rejected cast already makes) right
  before `rite_cast.emit(...)` in `_try_recognize()`
  (`systems/sigils/sigil_caster.gd:147-166`).
- **For package E/F, or whoever wires a `SigilCaster` into a running
  scene:** connect its `rite_cast` signal to
  `CampaignManager.notify_rite_cast(rite_id)` once an instance exists —
  `SigilCaster` is a scene component, not an autoload, so there's no fixed
  path this package can search the way it does for `LouhiDirector`. Until
  that connection exists, `q_first_rite` never auto-completes.
- **For package T (`ui/`):** `CampaignManager`'s quest/relic/scroll queries
  above are the intended data source for a quest-log render. Nothing in
  `ui/` currently reads any of it.
- **For whoever eventually instances both `LouhiDirector` and
  `CampaignManager`:** call `campaign_manager.attach_to_louhi(louhi_director)`
  explicitly if the auto-discovery in `_try_autodiscover_louhi()` doesn't
  find her (e.g. she ends up nested somewhere the name-based search misses).

## Scoped out

- **No autoload registration / no automatic scene wiring**, for the same
  reason `LouhiDirector` isn't wired in either — package S cannot edit
  `project.godot` or the world scenes. `campaign/campaign_manager.tscn`
  exists, ready to be instanced by an integration pass.
- **`sigil_caster.gd` doesn't gate on `scrolls_known` at all** (confirmed by
  reading `_try_recognize()` in full) — every rite is castable from the
  first successful gesture regardless of what's been learned. Flagged above
  with the exact fix rather than patched, since this package may not edit
  `systems/sigils/`.
- **`notify_rite_cast()` has no caller yet** — `q_first_rite` is real and
  will complete correctly the moment something calls it, but nothing does
  today. Flagged above for whoever wires a `SigilCaster` instance in.
- **No differentiated reward for Louhi's tier-1 outcome.** `q_louhi_cold_wind`
  grants the same epithet whether she relented or escalated — building a
  branching reward would need `CampaignManager` to remember *which* event
  resolved the quest, which the current three-state (LOCKED/ACTIVE/COMPLETE)
  model doesn't carry. Not implemented rather than half-built.
- **No repeat-cycle quest generation.** Louhi re-engages a new target after
  her cooldown (`actors/louhi/louhi_director.gd`'s own patience timers), but
  the three Louhi quests here are one-shot (LOCKED→ACTIVE→COMPLETE is
  terminal) — a second cold front later in the same save doesn't spawn a
  second `q_louhi_cold_wind`. A future pass could re-arm them (LOCKED again)
  after `post_resolution_cooldown_sec`, but that wasn't built here.
- **`louhi_hidden_sun_sliver` is real data with no quest granting it.** The
  relic and its lookup are correct and complete; nothing in `QuestCatalog`
  currently awards it, since there's no discovery/dig mechanic anywhere in
  the codebase to place it in the world. Reserved for a future pass rather
  than force-fit into an unrelated quest's rewards.
- **No `world/sanctum/sacrifice.gd` integration.** That file (package I,
  the Offering-Debt taboo's mechanical enforcement) explicitly invites "a
  campaign quest (`campaign/`)" to call `Sacrifice.offer()` directly in its
  own doc comment. This package didn't build that hook: per
  `docs/audit/respect_audit.md` rule 7 the taboo must never be rewarded, and
  a "quest" wired to a taboo act needs a real narrative-consequence design
  (e.g. a *penalty* quest beat that reacts to an offering happening, never a
  reward path) that this pass's brief didn't ask for. Flagged as a natural,
  audit-sensitive follow-up rather than invented under time pressure.
- **No persistence.** Quest/relic/scroll state lives only in
  `CampaignManager`'s in-memory dictionaries and `GameState`'s own arrays;
  there is no save/load hook anywhere in the codebase yet to persist across
  a restart.
- **No UI.** This package produces data and signals only; rendering a quest
  log, relic shelf, or scroll list is package T's (`ui/`) territory.

### Assets used

None. This package is pure GDScript (six scripts — `relic.gd`,
`relic_catalog.gd`, `scroll_book.gd`, `quest.gd`, `quest_catalog.gd`,
`campaign_manager.gd` — plus one trivial wrapper scene) — no textures,
audio, or models were needed or downloaded.
