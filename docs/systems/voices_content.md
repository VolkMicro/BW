# The Two Voices — content (Package M)

Replaces the stub `systems/voices/voice_lines.gd` with a real line-pool.
`systems/voices/voices.gd` (owned by the foundation, not touched by this
package) is unmodified: its public contract —

```gdscript
signal remark(speaker: StringName, line: String)
func react(trigger: StringName, context: Dictionary = {}) -> void
```

— still works exactly as before, because `VoiceLinePool.pick_pair(trigger,
context, recent)` still returns an `Array` of objects with `.id`, `.speaker`,
`.text` (the same `VoiceLine` inner class the stub defined).

## Who they are

- **Domovoi** — hearth spirit, fussy, practical, keeps a ledger nobody asked
  him to keep, endlessly disappointed but never actually leaves.
- **Hiisi** — forest trickster, half-raven half-fox, theatrical, genuinely
  believes almost every problem (political, spiritual, structural, romantic)
  is solved by eating someone or something.

They always speak in a **back-to-back pair**: Domovoi reacts first, Hiisi
answers and needles him. `react()` emits both lines from a single call.

## Comedic-target rule (audited)

Every joke lands on **the player's own bureaucracy/hypocrisy running this
god-operation**, or on **the advisors' own absurdity** (Domovoi's fussiness
about paperwork and structural load-bearing; Hiisi's appetite and
theatricality). No line mocks real belief, a real rite, or a real person.

`&"offering_taboo"` is the one trigger where the two are meant to visibly
disagree: Domovoi is genuinely appalled, Hiisi is weirdly delighted. That
split is what should read to the player as "the mercy path just got locked
in a little further" — Domovoi's horror is the game's own moral voice,
Hiisi's glee is a joke on Hiisi, not endorsement.

The "Debt" names used in `offering_taboo` lines (Offering-Debt, Ash-Debt,
Keel-Debt, Root-Debt) are **not invented for this package** — they're pulled
directly from the taboo_notes already written into
`data/cultures/{fenrayt,sankiln,raimborn,vainkeeper}.tres`, so the joke stays
inside the game's own invented mythology rather than gesturing at anything
real.

## Implementation

`systems/voices/voice_lines.gd`:

- `class_name VoiceLinePool`, inner `class VoiceLine` (`id: String`,
  `speaker: StringName`, `text: String`) — identical shape to the old stub.
- `_pairs: Dictionary` — `StringName trigger -> Array[Array[VoiceLine]]`,
  each inner array a `[domovoi_line, hiisi_line]` pair. Built once in
  `_init()` via `_build_pairs()`.
- `pick_pair(trigger, context, recent) -> Array`:
  1. Look up the trigger's pair list; empty list -> empty return (matches
     old "unknown trigger does nothing" behavior, so callers that fire a
     trigger this package hasn't authored yet just get silence, not a
     crash).
  2. Filter to pairs where **neither** line's id appears in `recent` — a
     real anti-repeat filter, not decorative. If every variant has recently
     been said (small pool + very active session), fall back to the full
     list rather than the advisors going mute.
  3. Pick uniformly at random from the surviving candidates.
  4. Format `{placeholder}` tokens (see below) against `context` and return
     fresh `VoiceLine` copies so the pool itself stays immutable.
- `_placeholders(context)` resolves `{village}`, `{culture}`, `{debt}`,
  `{epithet}`, `{reason}`, `{method}`, `{amount}` — looking up
  `GameState.get_village(context.village_id)` and
  `GameState.cultures[culture_id]` when available, and falling back to
  generic text (`"that village"`, `"somebody's"`, `"Old Debt"`) so a call
  with a sparse context never ships a literal unfilled `{token}`.
- `known_triggers()` — a small convenience (not part of the required
  contract) that lists every trigger this pool has content for; useful for
  a future debug/QA panel, not required by `voices.gd`.

`voices.gd` itself needed **zero changes** — it already calls
`_pool.pick_pair(trigger, context, _recent_line_ids)` and emits each
returned line, with its own 12-entry `_recent_line_ids` memory feeding the
anti-repeat filter above.

## Triggers implemented (4–6 non-repeating pairs each)

Every trigger below has its own set of pairs; one sample pair (Domovoi line
/ Hiisi line) is shown per trigger. `{village}` etc. resolve live from
whatever `context` the caller passes (village_id, culture_id, epithet,
reason, method_id/method, amount) — see `_placeholders()` above for exact
keys and fallbacks.

| Trigger | Pairs | Sample (Domovoi / Hiisi) |
|---|---|---|
| `&"first_rite_cast"` | 6 | "First rite's cast. I've already found two things wrong with it." / "I found one thing right with it: it's over. Can we eat now?" |
| `&"village_converted"` | 6 | "{village} converted. Someone go check they still have enough grain to be grateful with." / "Grateful villages taste better anyway. More seasoning in it." |
| `&"village_lost"` | 5 | "{village} is gone. Add it to the list of things I warned you about and you cast anyway." / "Gone doesn't mean gone-gone. Something's still down there. I could go check. With my mouth." |
| `&"offering_taboo"` | 6 | "That is the {debt}, and every {culture} elder could describe it in loving, horrified detail. We just did it." / "Finally! A rule with teeth! I love rules with teeth, they're the only kind worth breaking." |
| `&"avatar_praised"` | 5 | "They're praising the Avatar again. I'd like it on record that I did the actual paperwork." / "Paperwork doesn't have teeth. Teeth get praised. That's just how praising works." |
| `&"avatar_chastised"` | 5 | "The Avatar's being scolded. Good. Someone other than me finally said it." / "Scolded, chastised, corrected — such fussy words for 'somebody's cranky.'" |
| `&"avatar_grew"` | 5 | "The Avatar's grown again. Wonderful. Now I need to refit every door in the Sanctum." / "Bigger Avatar means bigger portions. Best news I've had all week." |
| `&"louhi_sighted"` | 5 | "Louhi's been sighted again. Lock up anything that isn't nailed down, and half of what is." / "Louhi! Finally, someone interesting. Do you think she'd let me follow along? Just to watch. Mostly to watch." |
| `&"missionary_sent"` | 5 | "A missionary's off to spread the word. Do try to remember the word this time." / "I remember the important part: knock politely, then, if that fails, don't." |
| `&"first_duel_won"` | 5 | "First duel won. I'll allow one moment of pride before the paperwork ruins it." / "One moment? I intend to savor this all week. Possibly with the loser's boots as a souvenir." |
| `&"drought"` | 5 | "Drought again. The wells are down, the fields are cracking, and somehow it's still my job to say so calmly." / "Cracking fields! Wonderful sightlines. Everything's easier to catch when it can't hide in tall grass." |

That's 58 pairs / 116 lines total across 11 triggers.

## Triggers already fired elsewhere that this pass does NOT cover

> **Superseded by the second content pass** (see the section below, which
> authors all of them plus twenty-odd more). The original text of this
> section is kept verbatim rather than rewritten, because it is the honest
> record of what the first pass chose not to do and why.

A `grep` across the codebase turned up several triggers other packages
already call (`&"village_helped"`, `&"village_terrorized"` in
`systems/faith/reach.gd`; `&"villager_forced_to_kneel"`,
`&"village_child_born"`, `&"village_child_matured"`, `&"villager_collapsed"`,
`&"villager_died_praying"` in `actors/villagers/villager.gd`;
`&"sigil_recognized"`, `&"sigil_rejected"` in
`systems/sigils/sigil_caster.gd`; `&"hand_grabbed_object"`,
`&"hand_threw_object"` in `actors/hand/hand.gd`). The brief scoped this pass
to the 11 triggers listed above, so those calls currently resolve to an
empty pair (silent — `voices.gd` already no-ops gracefully on an empty
result) rather than crashing. **Scoped out deliberately**: adding pools for
every trigger already in the codebase would have meant thinner, more
repetitive content for the 11 the brief actually asked for. Extending
`_pairs` with more trigger keys later is a pure content addition — no
change to `pick_pair`'s logic, `voices.gd`, or the public API is needed.

## Scoped out

- **Non-English/localization** — lines are plain English strings, no
  translation keys. Out of scope for a single content pass; would need a
  project-wide localization strategy other packages aren't using yet.
- **Voice-over/audio** — this package is text-only; `remark(speaker, line)`
  already gives Package R (audio) a hook to play stingers per speaker if it
  wants to, but no audio assets are added here.
- **Per-culture variant flavor beyond `offering_taboo`** — only the taboo
  lines pull culture-specific data (`{debt}`, `{culture}`); the other
  triggers stay culture-agnostic since the brief's list (first rite, avatar
  growth, duels, drought, Louhi, missionaries) is about the player's
  operation in general, not any one culture.
- **Pools for the pre-existing triggers** listed in the section above — see
  that section for why and how to extend later.

### Assets used

None. This package is pure GDScript content (dialogue text) — no textures,
audio, or models were needed or downloaded.

---

# Second content pass — the 34 silent triggers

## Why

A grep of every `Voices.react(` call in the repo turned up **41 distinct
triggers being fired by live code**, against **11 authored pools**. The
other 30-odd resolved to an empty pair, i.e. the two advisors said nothing
at all for storms, construction, duels, sigil failures, quests, relics,
Louhi's thefts, births, collapses, prayer-deaths, and the mercy lockout —
which is most of the game, and the Voices are the game's teaching layer.
This pass authors all of them.

Nothing was rewritten: the eleven original pools are untouched apart from
one grammar fix (`offering_taboo` ot1 said "an {debt}", which reads wrong
for two of the four culture debt names — now "the {debt}"). The pair
shape, `pick_pair()` contract, and `voices.gd` are all unchanged, and
`voices.gd` was **not edited by this pass at all**.

## Triggers authored, and the context keys each one actually provides

Every placeholder used in a line was checked against that trigger's real
call site — no line references a key its caller does not pass. Fallback
text (e.g. `"that village"`) covers a sparse context, and a placeholder
landing at the head of a sentence is sentence-cased after substitution so
a fallback never produces "wood spilling out of…" mid-paragraph.

| Trigger | Call site | Keys the call site passes | Placeholders used | Pairs |
|---|---|---|---|---|
| `avatar_surprised_expectation` | `actors/avatar/avatar.gd` | tag, probability, result, species | `{tag}` `{chance}` | 5 |
| `construction_started` | `systems/economy/village_economy.gd` | village_id, village_name, building_id, building_name | `{village}` `{building}` | 5 |
| `construction_completed` | same | same | `{village}` `{building}` | 5 |
| `wonder_completed` | same (the `is_wonder` branch) | same | `{village}` `{building}` | 4 |
| `duel_ended` | `actors/avatar/combat/duel_arena.gd` | winner, loser, finish_type | `{winner}` `{loser}` `{finish}` | 5 |
| `duel_foe_finished_while_downed` | same | finisher, downed | `{finisher}` `{downed}` | 5 |
| `duel_mercy_shown` | same | spared_by, downed | `{sparer}` `{downed}` | 5 |
| `hand_grabbed_object` | `actors/hand/hand.gd` | node_name | `{thing}` | 5 |
| `hand_threw_object` | same | node_name, speed | `{thing}` `{speed}` | 5 |
| `louhi_duel_challenge` | `actors/louhi/louhi_director.gd` | village_id | `{village}` | 5 |
| `louhi_relic_stolen` | same | village_id, relic | `{village}` `{relic}` | 5 |
| `mercy_blocked_by_debt` | `world/sanctum/sanctum.gd` | village_id, debt_name, seconds_remaining | `{village}` `{debt}` `{seconds}` | 5 |
| `missionary_arrived` | `systems/faith/missionary.gd` | village_id | `{village}` | 4 |
| `missionary_recalled` | same | village_id (abandoned target), home_village_id | `{village}` `{home_village}` | 4 |
| `offering_out_of_reach` | `world/sanctum/sanctum.gd` | village_id | `{village}` | 5 |
| `quest_activated` | `campaign/campaign_manager.gd` | quest_id, quest_title | `{quest}` | 5 |
| `quest_completed` | same | quest_id, quest_title | `{quest}` | 5 |
| `relic_found` | same | relic_id | `{relic}` | 5 |
| `scroll_learned` | same | rite_id | `{rite}` | 5 |
| `sanctum_damaged` | `world/sanctum/sanctum.gd` | village_id, amount, hp_fraction, source | `{village}` `{amount}` | 5 |
| `sanctum_destroyed` | same | village_id, culture_id | `{village}` `{culture}` | 5 |
| `sigil_recognized` | `systems/sigils/sigil_caster.gd` | rite_id, confidence | `{rite}` `{confidence}` | 5 |
| `sigil_rejected` | same | best_guess, confidence | `{rite}` `{confidence}` | 6 |
| `stockpile_overflow` | `systems/economy/village_economy.gd` | village_id, village_name, resource | `{village}` `{resource}` | 5 |
| `storm_forming` | `systems/weather/weather.gd` | wind_speed (+ forced) | `{wind}` | 5 |
| `storm_broke` | same | wind_speed (+ source) | `{wind}` | 5 |
| `storm_calmed` | same | *(nothing — empty dict)* | none | 4 |
| `storm_passed` | same | age | none | 4 |
| `village_child_born` | `actors/villagers/villager.gd` | village_id, culture_id | `{village}` `{culture}` | 5 |
| `village_child_matured` | same | village_id, culture_id | `{village}` | 4 |
| `village_helped` | `systems/faith/reach.gd` | village_id, amount, gain | `{village}` `{gain}` | 5 |
| `village_terrorized` | same | village_id, amount, gain | `{village}` `{gain}` | 5 |
| `villager_collapsed` | `actors/villagers/villager.gd` | village_id, culture_id | `{village}` | 5 |
| `villager_died_praying` | same | village_id, culture_id | `{village}` | 6 |
| `villager_forced_to_kneel` | same | village_id, culture_id | `{village}` | 5 |

Two more pools were added on top of that table, for triggers that landed in
the repo from a parallel package while this pass was being written and that
the same package's own comment says it cannot author (it may not edit this
file): `wildlife_kill` (`{species}`, `{predator}`) and `wildlife_scattered`
(`{species}`), 4 pairs each, from
`actors/wildlife/wildlife_manager.gd`.

**37 triggers, 179 pairs, 358 lines** added this pass. Combined with the
first pass the pool now covers **48 triggers / 237 pairs / 474 lines**, and
**every `Voices.react()` call anywhere in the repo now has authored
content** (verified by diffing the set of `react(&"…")` literals in the
repo against the pool's own keys). (`wonder_completed` wasn't on this
pass's brief but is fired by the same line of `village_economy.gd` as
`construction_completed`, so leaving it silent would have been an odd
hole.)

## Hard-rule-7 triggers (audited): the taboo is condemned, never rewarded

`docs/audit/respect_audit.md` rule 7 binds four of the new pools, and they
were written to it deliberately:

- **`villager_died_praying`** — the call site already shifts Naklon toward
  cruelty and earns the player the epithet "The One Who Prayed Them to
  Death". Domovoi names it as a death that belongs to the player ("Not for
  us. At us."). **Hiisi refuses his own running joke** — "I make a joke
  about eating everything. I am not making one about this." Both voices
  condemn; no line frames the devotion as worth it, because the fiction is
  clear that it isn't.
- **`villager_forced_to_kneel`** — fires only when a collapsed villager
  survived being dragged back to prayer. Domovoi: "That isn't devotion.
  That's a hand on the back of a neck." Hiisi supplies the sentence the
  player is meant to finish: "There's a word for that and the word isn't
  'faith.'"
- **`mercy_blocked_by_debt`** — the Sanctum's repair lockout during an
  active offering-debt. This is the fiction agreeing with the mechanic:
  "You do not get to take a life at that stone and then mend the roof with
  the same hand." Hiisi, who is normally the permissive one, sides with
  Domovoi here ("Even I won't touch this one. And I touch everything."),
  and the joke lands on the player's shopping-for-godhood hypocrisy, per
  rule 6.
- **`offering_out_of_reach`** — the taboo act refused on a *jurisdictional*
  technicality. The comedy is entirely divine bureaucracy ("Bureaucracy has
  saved more lives than mercy ever has. Nobody carves that on a temple"),
  and Domovoi is quietly relieved rather than disappointed, so the beat can
  never read as "shame, that would have been useful".

Related, though not rule 7: **`village_child_born`** is the one place
Hiisi's eat-everything bit could have gone badly wrong. He explicitly
declines it ("I'm not making my usual joke. I've decided. Don't ask me
again"), which is both funnier and keeps the appetite gag pointed where the
audit requires — at Hiisi himself.

`village_terrorized` is written as teaching content rather than a punchline:
terror is capped at `TERROR_CEILING` 0.85 in `reach.gd` and can never buy
genuine devotion, so Domovoi says exactly that ("Fear buys compliance. It
has never once bought the last of anyone's devotion"), and Hiisi's
"somebody else always pays — I'd know, I've been somebody else" lands the
cost rather than celebrating it.

## Three mechanism changes inside `voice_lines.gd` (no API change)

`voices.gd` and the `pick_pair(trigger, context, recent) -> Array` contract
are untouched. All three of these live inside the pool file:

1. **Optional per-pair weights.** A pair may now carry a third element, a
   float weight (`_pw(0.6, id, d, h)`); plain `_p(...)` pairs weigh 1.0.
   `_weighted_pick()` does a normal weighted draw over whatever survived
   the anti-repeat filter, so a big swing (Hiisi refusing a joke, "a god
   that prays its people to death has run out of things to call itself")
   stays in the pool but stays rare. `pick_pair` now reads exactly the
   first two elements of the chosen pair rather than iterating it, so the
   weight is never mistaken for a line.
2. **Per-trigger pacing.** `_PACING_COOLDOWN_MSEC` gives high-frequency,
   low-stakes triggers a minimum gap (Hand grab/throw 11 s, sigil reads
   9–14 s, births 25 s, overflow 30 s, …). Without it the advisors talk
   over literally every object the Hand picks up. A suppressed trigger
   returns an empty array, which `voices.gd` already treats as "say
   nothing" — no crash path, no API change. **Every morally load-bearing
   trigger is deliberately absent from that table and always speaks**:
   `offering_taboo`, `villager_died_praying`, `villager_forced_to_kneel`,
   `mercy_blocked_by_debt`, `offering_out_of_reach`, `sanctum_destroyed`,
   `village_lost`, `duel_*`, `louhi_*`, quests, relics, wonders.
   `respect_pacing = false` on the pool disables it for QA.
3. **Sentence-casing after substitution**, so a lowercase fallback
   (`"that village"`, `"wood"`) at the head of a line doesn't produce
   "wood spilling out of…". One character comparison, only on lines that
   actually contain a `{`.

`_placeholders()` gained the keys the new triggers need — `{building}`
`{resource}` `{quest}` `{relic}` `{rite}` `{thing}` `{winner}` `{loser}`
`{downed}` `{finisher}` `{sparer}` `{finish}` `{target_village}`
`{home_village}` `{wind}` `{speed}` `{seconds}` `{gain}` `{chance}`
`{confidence}` `{tag}` `{kind}` `{stage}` — with number formatting (`_num`,
`_pct`) so a line says "5%" and "12.5", never "0.050000". `{relic}` resolves
through `RelicCatalog.get_relic()` to the relic's real display name
("Raft-Bell of the Sinking") and falls back to a prettified id. `{finish}`
maps `duel_arena.gd`'s `finish_type` ids to English phrases
("defeated_in_exchange" -> "in a straight exchange") so no snake_case id is
ever spoken. `{debt}` now prefers an explicit `debt_name` in the context
(both `sacrifice.gd` and `sanctum.gd` pass one) over the culture-id lookup,
so the two can never disagree.

## Performance

**Zero per-frame cost.** This file has no `_process`/`_physics_process` and
is not a Node; it does work only inside a `Voices.react()` call, which is
event-driven. Per call that work is: one Dictionary lookup for the pool,
one lookup + one `Time.get_ticks_msec()` for pacing, a linear scan of ≤6
pairs for the anti-repeat filter, a weighted draw over the same ≤6, one
Dictionary build of ~30 short strings, and up to two `String.format()`
calls — microseconds, on the CPU, at human-speech frequency. The pacing
table strictly *reduces* the number of react() calls that do the formatting
half of that work.

The relic lookup is the only allocating path (`RelicCatalog.build()`
constructs its 8 `Relic` resources per call) and it runs on exactly two
triggers, `relic_found` and `louhi_relic_stolen`, which fire a handful of
times per campaign. Not worth caching; flagged here rather than left for
someone to find.

Nothing here touches the renderer, so nothing here is affected by the
integrated-Intel frame budget in `docs/systems/performance_notes.md`.

## Verification

- `godot --headless --path . --check-only --quit-after 3` — clean (the two
  known-harmless headless lines aside).
- A throwaway runtime smoke scene (written, run, deleted — not committed)
  instantiated the pool and called `pick_pair()` **40 times for each of the
  39 trigger/context cases**, using the exact context dictionaries the real
  call sites pass, plus two deliberately malformed ones (an unknown relic
  id, and a village_id that resolves to nothing). Result: **3200 lines
  generated, 0 triggers with no pool, 0 lines containing an unfilled
  `{token}`**, and the pacing check confirmed a chatty trigger is
  suppressed on its second immediate call while `villager_died_praying`
  speaks every time.
- **Not measured:** anything frame-rate related. This sandbox has no GPU,
  and a text pool wouldn't be the thing to measure anyway.

## Scoped out (second pass)

- **`voices.gd` untouched.** No cooldown, priority, queueing, or
  interrupt logic was added to the autoload. Two advisors currently emit
  both lines of a pair in the same frame via `remark`; if two triggers fire
  in the same frame the UI receives four lines back-to-back. Sequencing
  that (a spoken-line queue with a display delay) belongs to whoever owns
  the UI/audio presentation of `remark`, not to the content pool, and is
  deliberately left alone.
- **No audio.** Still text-only; `remark(speaker, line)` remains the hook.
- **No localization.** Plain English strings, no translation keys —
  unchanged from the first pass and for the same reason.
- **No per-culture variants** for the new triggers beyond `{culture}` /
  `{debt}` substitution. Writing four culture-specific variants of 35
  triggers would have meant thinner writing everywhere; the Fenrayt and the
  Raimborn hear the same Domovoi.
- **No reactions to `context` values beyond substitution.** Nothing branches
  on, say, `hp_fraction` to pick a graver line when a Sanctum is nearly
  down, or on `result` for the Avatar's surprise. That would need a
  selector predicate per pair; the weight field added here is the cheap
  half of that idea, and the conditional half is a clean follow-up that
  needs no API change either.
- **No `first_*` gating.** `first_rite_cast` and `first_duel_won` are fired
  once by their own systems; this pass didn't add "first time you ever X"
  variants for the new triggers, which would need state the pool doesn't
  keep.

### Assets used

None. Pure GDScript dialogue content, as before.
