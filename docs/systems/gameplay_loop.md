# The gameplay loop — press Play, and then what?

The verdict on the previous build was blunt and correct: **«нет геймплея»** —
there is no gameplay. Every system in this repository ran. None of them added
up to anything a player could win, lose, or even understand. You pressed Play
and got an island, a camera, and silence.

This document is the trace that was asked for: **player presses Play → sees
X → does Y → gets feedback Z → is pointed at the next thing**, step by step,
with file:line for every link in the chain, and an explicit list of the
places where the chain is still thin. Nothing in here is claimed unless it
was either read in the code or observed in a headless run of the real
`world/god_view.tscn` — and where a number is quoted, how it was obtained is
stated next to it.

Owner: the integration pass (`world/god_view.tscn`, `world/god_view.gd`,
`ui/voice_log.gd`). No other package's files were edited.

---

## 0. What was actually broken

Four load-bearing edges did not exist. Not "were rough" — did not exist.

| Break | Evidence | Consequence |
|---|---|---|
| **Rites did nothing.** `Reach.convert_via_help()` / `convert_via_terror()` (`systems/faith/reach.gd:143,159`) had no caller anywhere in the shipping scene. `grep` over the whole repo found exactly two callers: `modes/skirmish/skirmish_scenario_demo.gd:91` and `net/network_manager.gd:333` — a standalone demo and the netcode's host path. | grep | **A village could not be converted by any player action.** The central verb of the game resolved to nothing. |
| **The Two Voices talked to nobody.** `Voices.remark` (`systems/voices/voices.gd:11`) had exactly four listeners in the repo: three `*_demo.gd` files and `audio/music_director.gd:259`, which listens only to duck the music and never displays the text. | grep | 48 authored trigger pools / 474 lines (`docs/systems/voices_content.md`) were generated and thrown away on the way to the screen. |
| **The Avatar could not grow.** `Avatar.feed_devotion()` (`actors/avatar/avatar.gd:383`) had no caller outside `avatar_demo.gd`, and no context tag was ever opened, so `praise_avatar`/`chastise_avatar` reinforced nothing. | grep + `docs/systems/integration.md`'s own "Standalone / inert" note | Pressing F did nothing observable, forever. |
| **The conversion curve could not reach conversion.** `Village.is_fully_converted()` needs `faith_fraction >= 0.999` (`core/village.gd:36`), but `Reach._grow_faith()` scales every gain by remaining headroom (`systems/faith/reach.gd:131-137`), making the curve asymptotic. | **Observed, not deduced**: a headless probe fired 400 consecutive `harvest` rites at one village. It went 0.55 → 0.783 and was still climbing by thousandths. | Even after the first break was fixed, the loop still could not close. |

Two smaller ones: the on-screen help promised `[` / `]` for Naklon and
nothing in `god_view.gd` implemented them (only `actors/hand/hand_demo.gd`
did), and a gesture game shipped without ever telling the player what shapes
exist.

---

## 1. The trace

### Step 1 — Play → you are told what you are

`world/god_view.gd:_ready()` finishes bootstrapping and calls
`_voice_log.unmute()`. Four authored beats then fire from `_process()` on a
schedule (`OPENING_EXCHANGE`, at t = 1.5 / 6 / 11 / 16.5 s), rendered by
`ui/voice_log.gd` bottom-left in the same register as the existing
`UI/HelpLabel`:

> **Domovoi** — You're awake. Three villages on this rock, and not one of them has settled on what you are.
> **Hiisi** — Two of them have barely heard of you at all. I say we introduce ourselves. Loudly.
> **Domovoi** — Quietly. Hold the right mouse button and drag a shape over a village — that is a rite. They will feel it. Then they will argue about it for a week.
> **Hiisi** — And when all three say your name without being asked, the island is yours and I am going to sleep for a year.

That is the whole tutorial: what you are, what the verb is, and what winning
means, said by the two characters who were going to be talking anyway. **No
popup, no modal, no "press E to continue"** — the brief forbids all three.

**Why the lines live in `world/god_view.gd` and not in the pool:**
`systems/voices/voice_lines.gd` belongs to package M and has no `game_start`
trigger; authoring one would mean editing another package's file. They are
pushed through `VoiceLog.push_line()`, which renders them identically to a
real `Voices.react()` pair. If a future pass moves them into the pool as a
`game_start` trigger, delete `OPENING_EXCHANGE` and call
`Voices.react(&"game_start")` instead — nothing else changes.

**Verified:** headless run, transcript read off the live node at t = 12.5 s —
beats 2 and 3 on screen, beat 1 correctly aged out.

**A boot-time flood was deliberately suppressed.** `CampaignManager._ready()`
activates six quests, each firing `Voices.react(&"quest_activated")` — twelve
lines of dialogue at frame 0, before the player has touched anything.
`VoiceLog.start_muted` defaults true and `god_view.gd` unmutes at the end of
its own `_ready()` (a parent's `_ready()` runs after every child's), so
exactly those twelve are dropped and nothing else is. This is explicit rather
than relying on node ordering in the `.tscn`.

### Step 2 — you see the objective

`UI/ObjectiveLabel`, top-left, rebuilt by `_build_objective_text()` at 1 Hz
and on every relevant signal. At boot it reads:

```
Yours: 0 of 3 villages.
Now — Fenrayt Hollow (55% theirs): hold right mouse and drag a rite over it.
Spoken of: "What the Bog Remembers"
```

- Line 1 is real state: a count over `GameState.villages`.
- Line 2 targets the **nearest-to-done** unconverted village, so the pointer
  does not flap between villages every second, and it prints that village's
  real `faith_fraction`.
- Line 3 is the live quest from `CampaignManager.get_active_quests()` →
  `get_quest_def(id).title`, preferring a Louhi quest (she is the clock),
  then a quest whose `culture_id` matches the village you are being pointed
  at, then anything.
- A fourth line appears when Louhi acts, carrying her own
  `sign_occurred(tier, village_id, description)` text verbatim.

**Verified:** all four line forms observed in headless runs, including
Louhi's ("*Louhi, at Sankiln Terrace (sign 1): A cold front rolls in over
Sankiln Terrace out of the north…*").

### Step 3 — you act, and the act lands somewhere specific

Hold right mouse, drag a shape. `systems/sigils/sigil_caster.gd` recognizes
it against the nine `SigilTemplates` and emits `rite_cast(rite_id, confidence)`.
`god_view.gd:_on_rite_cast()` is now connected to it (alongside the
pre-existing `CampaignManager.notify_rite_cast` hook) and does four things:

1. **Resolves a target**: `_village_in_reach_of(_hand.get_target_position())`
   — the village whose Reach circle the Hand is over. That circle is the same
   one `world/terrain/reach_border.gd` already draws on the ground every
   frame, so "where can I cast" is something the player can *see* rather than
   a rule they have to be told.
2. **If there is none, refuses**: `Hand.request_refusal_flash()`
   (`actors/hand/hand.gd:194`) plus `Voices.react(&"offering_out_of_reach")`.
   This is the single most important teaching moment in the game — it is how
   a player learns Reach exists, by trying to cast at the sea and being told
   *"That village is beyond us. Faith goes out first and the taking comes
   after, and you've tried it backwards."* **Verified in a headless run.**
3. **Spawns the burst**: `RiteVFX.spawn(rite_id, world_pos, self)`
   (`systems/sigils/rite_vfx.gd:103`) — a one-shot procedural particle
   effect that frees itself. This is the only confirmation that the rite
   landed *here* and not somewhere else.
4. **Converts**: `Reach.convert_via_help()` or `convert_via_terror()` with an
   amount from `HELP_RITE_AMOUNT` / `TERROR_RITE_AMOUNT`, scaled 0.875–1.0 by
   the recognizer's confidence.

Rites are split **by meaning, not by convenience**: everything that gives a
village something (`harvest`, `rain_call`, `repair`, `ward`, `lumber`,
`path_gate`) is help; everything that happens *to* one (`fire_arrow`,
`lightning`, `storm`) is terror.

### Step 4 — feedback, four channels at once

| Channel | Mechanism | Where it comes from |
|---|---|---|
| **The Voices** | `Reach.convert_via_help()` already called `Voices.react(&"village_helped", {gain})` at `reach.gd:153` — it just had no caller and no display. Now: *"We've done Fenrayt Hollow an actual kindness. Faith's up 9%, and it will stay up, which is more than terror ever manages."* | `systems/faith/reach.gd` + `ui/voice_log.gd` |
| **The ground** | `Reach.radius_for_village()` grows with `population × faith_fraction`, and `reach_border.gd` reads it every frame. The territory ring visibly widens. Measured across one conversion: **10.2 m → 18.8 m**. | `world/terrain/reach_border.gd` |
| **The sky and the sea** | Help shifts Naklon toward Mercy, terror toward Cruelty (`reach.gd:154,169`), and `NaklonEnvironmentDriver` regrades the whole scene off it. A player who converts by kindness ends the island at roughly full Mercy. | `environment/naklon_environment_driver.gd` |
| **The objective** | The percentage in line 2 moves. | `_build_objective_text()` |

### Step 5 — the village tips, and pays out

Once `faith_fraction >= CONVERSION_TIPPING_POINT` (0.90),
`_maybe_tip_over()` calls `GameState.set_faith_fraction(id, 1.0)`, which
emits `village_converted` through the normal path. Everything downstream is
pre-existing code that had simply never fired in a real game:

- `Voices.react(&"village_converted")` — a six-pair pool that existed since
  package M's second pass and that **nothing in the repo had ever called**.
- `CampaignManager._on_village_converted()` → the matching culture quest
  completes → grants a **relic**, a **scroll**, and an **epithet**.
- The epithet lands in `GameState.epithets`, which `core/game_state.gd` calls
  "the player's real scorecard" — and which nothing had ever displayed.
- The scroll unlocks a new rite, which appears in the rites list (key `3`).

**Observed, end to end, in one headless run:**

```
>> village_converted isle_raimborn_shore
>> relic_gained raimborn_wavecall_horn
>> scroll_learned rain_call
>> epithet 'Named by the Tide'
>> quest_completed q_raimborn_wavecall
>> relic_gained ninefold_tally_cord   (q_ninefold_tally: "first epithet earned")
>> epithet 'Keeper of the Tally'
RITES KNOWN: [ward, rain_call]
```

Note the second-order effect: earning the *first* epithet completes a
different quest, which grants another relic and another epithet. The campaign
layer chains correctly the moment anything at all feeds it.

### Step 6 — you are pointed at the next thing

The objective recomputes: `Yours: 1 of 3 villages. / Now — Fenrayt Hollow
(55% theirs): …`. The new rite appears under key `3`. The loop closes.

### Step 7 — the island ends

Three terminal states, checked at 1 Hz and on every conversion/loss
(`_check_end_state()`), all three **observed working in headless runs**:

| Ending | Condition | Card |
|---|---|---|
| **VICTORY** | every village fully converted | "THE ISLAND IS YOURS" |
| **DIVIDED** | everything still standing is converted, but ≥1 village was lost | "THE ISLAND IS DIVIDED — 2 of 3 villages are yours. 1 answer to Pohjola, and there is no way back through that door." |
| **DEFEAT** | every village lost | "THE ISLAND IS HERS" |

Every card lists the epithets mortals actually coined for you, which is the
game's own stated scorecard, or admits that nobody bothered.

**Why DIVIDED exists.** A village Louhi takes sets `loyal_to_rival = true`
(`actors/louhi/louhi_director.gd:321`) and there is **no reclaim mechanic
anywhere in this codebase** — her own doc calls tier 2 "a one-way door". So
after one loss, VICTORY is permanently unreachable. Without a third ending
the player would be left grinding toward something the code cannot give
them. Saying "this is as far as this island goes" is more honest than an
infinite sandbox.

A village also counts as lost at `population <= 0`
(`actors/villagers/villager.gd:1040`), which is reachable by praying
villagers to death at a Calling Stone.

---

## 2. The one place this pass overrides another package's numbers

`CONVERSION_TIPPING_POINT = 0.90`, in `world/god_view.gd`, declared loudly in
a comment at the constant.

The reason is in §0: reach.gd's growth curve is asymptotic and 0.999 is
mathematically out of reach. The two honest fixes were (a) change reach.gd's
curve — package J's file, and mirrored by `net/network_manager.gd:388-398`
for deterministic multiplayer, so a change there is a two-file change with a
netcode desync risk — or (b) decide at the integration layer when "convinced
enough" becomes "converted". This is (b).

It is set **above** `Reach.TERROR_CEILING` (0.85) on purpose, so terror alone
still cannot take a village. That design rule — "fear buys compliance, never
the last sliver of genuine devotion" — survives completely intact, and the
objective line says so out loud when a player hits the wall:

> Now — Sankiln Terrace (85%): fear has carried them as far as fear goes. The rest has to be given: harvest, rain, mending, a ward.

---

## 3. Pacing — measured, at a realistic cast rate

Fatigue is what makes this a game rather than a click-counter:
`Reach.register_use()` raises per-village-per-method fatigue by 0.28 of the
remaining gap on every use and it decays at 0.015/s (~65 s to forget a
method entirely). Spamming one rite visibly stops working; walking away
restores it.

**Measured** by a headless probe that drove the real scene, casting one rite
every **5 seconds** (about the pace of actually drawing one), rotating
`harvest` / `rain_call` / `repair` / `ward`:

> **Raimborn Shore, the hardest village (starts at 0.20 faith): converted in
> 19 casts / 90 seconds of game time.**

Fenrayt Hollow starts at 0.55 and Sankiln Terrace at 0.35, so the whole
island is roughly 45 casts, call it five to eight minutes of active casting —
before Louhi, weather, the Sanctum, the Avatar, or wildlife are counted.

**This is a CPU/logic measurement of game time, taken headlessly. It is not a
frame-rate measurement and this sandbox has no GPU.**

For contrast, the same probe at an unrealistic ~30 casts/second (fatigue
pinned near 1.0) needed 400 casts to move a village 0.55 → 0.783. Both
numbers are real; the 5-second one is the one that describes play.

---

## 4. Everything else this pass wired up

### The Avatar can now grow

`_on_devotion_changed()` forwards `AVATAR_DEVOTION_SHARE` (0.35) of every
point of village devotion into `Avatar.feed_devotion()`. Villagers already
generated that devotion for real (`villager.gd:860` prayer, `:984` ambient
labour) and `GameState.devotion_changed` was always emitted — it just went
nowhere.

Measured across two headless runs (30 s and 90 s, boot population): the
island produces ~0.9–1.4 devotion/s, so the Avatar is fed ~0.3–0.5/s →
"Juvenile" (30) in 1–2 minutes, "Grown" (120) in 4–7 minutes. Both stages
*also* gate on praise count (6 and 16 presses of F), which the player must
supply.

`_update_avatar_context()` keeps exactly one context tag open —
`guard_village` when the Avatar stands inside a village's Reach,
`explore_new_place` otherwise — so that F/G finally reinforce *something*.
The Avatar was moved from the empty middle of the island to just outside
Fenrayt Hollow (`guard_village` active at boot, verified). See §6 for the
honest limitation.

### The Naklon keys the help text had been lying about

`[` / `]` now call `Naklon.shift()` in `god_view.gd:_unhandled_input()`. They
were advertised in the old `HelpLabel` and implemented only in
`actors/hand/hand_demo.gd`.

### Rite discovery (key `3`)

A gesture game that never tells you what to draw is not a game.
`ScrollBook.known_rite_ids()` and `SigilTemplates.DESCRIPTIONS` both already
existed and had never been shown to anybody. Key `3` toggles a list of the
rites you know, each with its English shape description ("*A plain closed
circle with a short straight tail stub at the top…*") and whether it is a
gift or a terror. Hidden by default, because a permanently-open list is a HUD
and this game does not have one. It grows as scrolls are earned — verified
(`ward` at boot, `ward + rain_call` after the first conversion).

### Wildlife

`actors/wildlife/wildlife_manager.tscn` instanced at the count its own
package recommended: **10 rimefleece / 5 snagbill / 1 thawjaw = 16**, with
`terrain_path`/`avatar_path`/`hand_path` wired and a 105 m spawn radius. It
does its own rejection-sampled terrain placement via `IslandTerrain.sample_height()`.
Verified alive at 16 in a headless run of the real scene, and its
`wildlife_scattered` Voices trigger observed firing in response to the Hand.

### Perf, exactly as the low-spec pass specified

Applied from `docs/systems/performance_lowspec.md` §0.2, verbatim:

| Node | Change |
|---|---|
| `OceanSurface` | `subdivisions` 160 → **64** |
| `Sun` | `directional_shadow_mode = 0` (`SHADOW_ORTHOGONAL`) — was defaulting to 4 parallel splits, i.e. the whole shadow scene rendered 4× per frame |
| new | `environment/graphics_preset.tscn` instanced |
| new | **`P` cycles LOW → MEDIUM → HIGH → LOW** via `GraphicsPreset.cycle()`, and the help line shows the current preset |

**Deliberately not changed, because that same document explicitly recommends
against it:** `Island.resolution` (161) and `VILLAGERS_PER_VILLAGE` (5). Its
words: *"neither is close to being the bottleneck on a fragment-bound,
bandwidth-bound integrated GPU, and cutting them would cost real content for
a saving that is probably not measurable."* Following the recommendation
literally means leaving those two alone, and this pass did.

**Not applied, out of scope:** the terrain-texture `.import` fix
(`compress/mode=2`, `mipmaps/generate=true` across
`assets/textures/terrain/*/*.import`), which that document calls *"the single
highest-value item on this page"*. `assets/` is not this pass's to write.
It remains the highest-value outstanding perf item in the project.

---

## 5. Per-frame cost this pass adds

Stated precisely, because the target is a Dell Latitude 5411 on integrated
Intel graphics at ~5–6 fps and a pretty feature that costs frames is a
failure.

**Steady state, every frame, in `god_view.gd:_process()`:** one float add,
one compare against the opening-exchange list size (a compare against a
constant once the four beats are done), one float subtract, one compare.
**Four float operations.** Everything real is behind the 1 Hz tick.

**Once per second (`_slow_update()`):** one camera distance check; three
distance checks for the Avatar context; two boolean nudge checks; an
end-state pass over three villages; and an objective string rebuild that is
**only assigned to the Label when the string actually changed** — so the
common case is a string comparison and no re-layout. Call it a few hundred
float ops and one small string build per second. This is not measurable
against a 170 ms frame.

**`ui/voice_log.gd`:** `_process` is **disabled** whenever the transcript is
empty and re-enabled by a remark, so a silent minute costs exactly zero
callbacks. While lines are up: one float subtract + compare per entry (≤ 6)
and one alpha write. The BBCode string is rebuilt only when an entry arrives
or expires — a few times a minute, never per frame.

**Event-driven, not per-frame:** `_on_devotion_changed` fires ~5–8 times a
second (a Dictionary read, a subtract, a compare, and a 4-element loop inside
`feed_devotion`). `_on_rite_cast` fires at human speed.

**The one real GPU cost added: `RiteVFX.spawn()`** — a `GPUParticles3D` burst
of 32–48 particles with a primitive mesh draw pass, `one_shot`, self-freeing
after ~1.9 s. It exists **only** while a rite is resolving, which is a
player-initiated event a few times a minute, and it is the only thing in the
game that confirms a rite landed at a particular place. Judgement: a
transient two-second burst of a few dozen tiny meshes is an acceptable price
for the game's only spatial feedback. If it proves not to be on the real
laptop, the one-line removal is deleting the `RiteVFX.spawn()` call in
`_on_rite_cast()` — everything else in the loop still works.

**Rendering added by the scene changes:** 16 wildlife creatures at ~2 draw
calls each (~32 draw calls, ~8–9k verts — the wildlife package's own
measured figures) and four `Control` nodes, three of which are usually
hidden or empty. Against that, the ocean lost 21,696 vertices and the sun
lost three full shadow passes per frame.

**No frame rate is claimed anywhere in this document, before or after. This
sandbox has no GPU and cannot measure one.**

---

## 6. Where the loop is still thin — stated, not hidden

1. **The Avatar cannot walk.** `actors/avatar/avatar.gd` implements a full
   learning model (beliefs, three attachment axes, four growth stages) and
   **no locomotion at all** — its only `_physics_process` applies gravity.
   So it stands where it is placed forever. `_update_avatar_context()`
   correctly flips between `guard_village` and `explore_new_place`, but in
   practice the tag never changes on its own because nothing ever moves the
   creature. The wiring is real and forward-looking; the behaviour it is
   waiting for belongs to package K. Right now, praise/chastise trains a
   statue that is standing in a good place.
2. **Reach does not actually gate reaching the next village.** Every village
   has a minimum radius of 8 m regardless of faith (`reach.gd:75`), and the
   villages are ~130 m apart, so all three are castable from the first
   second. Growing Reach is real, visible, and feeds Louhi's target
   selection — but "grow Reach to reach the next village" is not literally
   how the island opens up. Closing that would mean changing reach.gd's base
   radius, which is package J's.
3. **Scroll gating is still not enforced.** `campaign/scroll_book.gd`
   correctly tracks which rites are known, and the rites panel shows only
   those — but `systems/sigils/sigil_caster.gd:162` emits `rite_cast` for any
   recognized shape regardless of `GameState.scrolls_known`. A player who
   guesses the lightning zigzag on turn one can cast it. `docs/systems/campaign.md`
   already documents the exact one-line fix and whose file it belongs in;
   this pass did not reach into `systems/sigils/` to apply it.
4. **The Voices have no queue.** Two triggers in one frame means four lines
   at once. The first rite is the worst case: `sigil_recognized` +
   `first_rite_cast` + `village_helped` can arrive together, six lines, and
   the transcript is six lines deep. `docs/systems/voices_content.md` says
   plainly that sequencing belongs to `voices.gd`, which is package M's file.
5. **No restart, no persistence.** The end card is terminal. There is no
   save/load anywhere in the codebase, and `reload_current_scene()` would be
   worse than nothing here — the autoloads (`GameState.epithets`,
   `relics_held`, `Naklon.value`) survive a scene reload, so a "restart"
   would begin with the last run's epithets and alignment still attached.
   Not built rather than half-built.
6. **The economy is not in the loop.** `systems/economy/village_economy.gd`
   runs, produces, and builds for real, and the player has no verb that
   touches it: there is no way to order a building, and `lumber`/`harvest`
   convert faith rather than adding to a stockpile. It is a simulation
   running beside the loop, not inside it.
7. **The Sanctum interior (key `2`) is a room, not a menu.** You can walk in
   and interact, and `docs/systems/sanctum_interior_ui.md` describes what is
   there — but the campaign's relics, quest log and scroll shelf are not
   rendered anywhere in it. `CampaignManager`'s query API is still, as its
   own doc says, waiting for a reader.
8. **One conversion path is unreachable in practice.**
   `systems/faith/missionary.gd` is complete and correct, and nothing spawns
   a Missionary — there is no player verb for it. `convert_via_missionary`
   therefore never runs in a single-player game.
9. **Casting a help rite on an already-converted village** is allowed and
   yields no faith (headroom is zero) but still nudges Naklon. Harmless —
   Naklon clamps at ±1 — but it is a small free-floating lever, noted rather
   than papered over.
10. **The island renders very dark.** Flagged by the low-spec pass as
    pre-existing and reproduced with the original unmodified shader; the
    leading suspect is terrain vertex normals. It belongs to `world/terrain/`
    and is not touched here, but it is the first thing a player will notice.

---

## 7. Files this pass changed

| File | Change |
|---|---|
| `world/god_view.gd` | Extended (not rewritten): rite→conversion resolution, tipping point, objective builder, three end states, opening exchange + two teaching nudges, Avatar devotion feed + context tag, Naklon keys, rites panel, graphics-preset key |
| `world/god_view.tscn` | Ocean subdivisions 64; sun shadow mode orthogonal; `GraphicsPreset` and `WildlifeManager` instanced; UI gains `ObjectiveLabel`, `VoiceLog`, `RitesLabel`, `EndCard`; `HelpLabel` re-anchored and rewritten |
| `ui/voice_log.gd` | **New.** The presenter for `Voices.remark` — the thing whose absence made 474 authored lines invisible |
| `docs/systems/gameplay_loop.md` | **New.** This file |

Nothing outside those four paths was written.

### Validation

`godot --headless --path . --check-only --quit-after 3` — **clean**. Output
is the version banner plus only the two documented-harmless families
(`Parameter "m" is null … mesh_get_surface_count`, and the
`ObjectDB instances leaked` / `N resources still in use at exit` shutdown
group, which `--verbose` attributes to the `MusicDirector` autoload's four
held `.ogg` streams and which is present on the pre-change baseline).

Beyond parse-checking: the real scene was run headlessly for 4,000 frames
with no `SCRIPT ERROR` of any kind, and driven through the entire loop —
refusal, conversion, quest payout, scroll unlock, and all three endings — by
temporary probe scenes that were deleted afterwards and are not in the repo.
