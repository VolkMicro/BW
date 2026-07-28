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
| `&"offering_taboo"` | 6 | "That is an {debt}, and every {culture} elder could describe it in loving, horrified detail. We just did it." / "Finally! A rule with teeth! I love rules with teeth, they're the only kind worth breaking." |
| `&"avatar_praised"` | 5 | "They're praising the Avatar again. I'd like it on record that I did the actual paperwork." / "Paperwork doesn't have teeth. Teeth get praised. That's just how praising works." |
| `&"avatar_chastised"` | 5 | "The Avatar's being scolded. Good. Someone other than me finally said it." / "Scolded, chastised, corrected — such fussy words for 'somebody's cranky.'" |
| `&"avatar_grew"` | 5 | "The Avatar's grown again. Wonderful. Now I need to refit every door in the Sanctum." / "Bigger Avatar means bigger portions. Best news I've had all week." |
| `&"louhi_sighted"` | 5 | "Louhi's been sighted again. Lock up anything that isn't nailed down, and half of what is." / "Louhi! Finally, someone interesting. Do you think she'd let me follow along? Just to watch. Mostly to watch." |
| `&"missionary_sent"` | 5 | "A missionary's off to spread the word. Do try to remember the word this time." / "I remember the important part: knock politely, then, if that fails, don't." |
| `&"first_duel_won"` | 5 | "First duel won. I'll allow one moment of pride before the paperwork ruins it." / "One moment? I intend to savor this all week. Possibly with the loser's boots as a souvenir." |
| `&"drought"` | 5 | "Drought again. The wells are down, the fields are cracking, and somehow it's still my job to say so calmly." / "Cracking fields! Wonderful sightlines. Everything's easier to catch when it can't hide in tall grass." |

That's 58 pairs / 116 lines total across 11 triggers.

## Triggers already fired elsewhere that this pass does NOT cover

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
