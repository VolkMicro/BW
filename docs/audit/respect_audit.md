# Respect audit — living tradition & sourcing (package U, pass 1/3)

Status: **initial pass, foundation phase**. This document is owned by the
independent audit package and gets appended to (never silently edited) as
each content package lands. It has veto power over release.

## Sourcing map

| In-game element | Drawn from | Public-domain / living? | Treatment |
|---|---|---|---|
| Louhi of Pohjola (rival god) | *Kalevala* (Elias Lönnrot, compiled 1835/1849) | Literary compilation, public domain. Not the object of a living cult — no attested modern religious veneration of "Louhi" as a deity. | Kept as the epic's own antagonist: a hoarder, a bargainer, patient and clever, never a monster-for-shock. No invented cruelty added beyond what the source epic already gives her. |
| Domovoi (advisor) | East Slavic folk belief — household spirit | Folk-belief figure still referenced in folklore/heritage contexts, not a worshipped deity in any organized living religion | A minor hearth-spirit archetype, not a god; comedy targets his own fussiness and the player's bureaucracy, never the belief itself |
| Hiisi (advisor) | Finnic folklore — a Hiisi is a class of spirit/sacred-grove-turned-sinister-place in folk belief, also used in *Kalevala* for monstrous creatures | Folk-belief class, not a named living cult figure | Played as a trickster archetype (raven/fox hybrid); comedy targets his gluttony/impulsiveness, never a real practice |
| Otso, Krukk, Sarv (Avatar species) | Otso = a *Kalevala* poetic name for "bear"; Krukk/Sarv are invented sound-alike coinages, not attested words | Otso: public-domain literary epithet. Krukk/Sarv: invented. | Used as creature *names*, not deity names — none of the three is a worshipped figure in any tradition |
| Fenrayt, Sankiln, Raimborn, Vainkeeper (the four peoples) | Invented compound names (bog+wright, kiln, rime-born, vine-keeper) | Fictional — checked against Sámi, Yakut/Sakha, Nenets, Evenki, Komi, Norse, and East Slavic ethnonyms; none match | No real people is depicted committing the game's "cruel path" atrocities |
| Sigils (rite gestures) | Original geometric designs authored for this project | N/A — must never resemble attested runic/sacred inventories | Design constraint tracked in `systems/sigils/`; audit checks each shape at art-lock, not just at first sketch |

## Hard rules checked at every future pass

1. No real venerated creator/supreme deity appears as villain, monster, or joke.
2. No playable culture is named for a real people, living or historical.
3. No real sacred symbol (runic or otherwise) is used as a villain marker; no swastika-family motif in any orientation, regardless of historical attestation.
4. No currently-practiced rite (Ysyach-type midsummer festivals, blót, seida offerings, shamanic drumming under any real name) is depicted mockingly, as gore-comedy, or fictionalized under its real name — rites in this game belong to the game's invented cultures only.
5. No real shrine or sacred object becomes loot or a puzzle prop.
6. Advisor comedy targets the player's own hypocrisy/bureaucracy, not real belief or its holders.
7. The Offering-Debt (living-sacrifice-for-instant-devotion) mechanic is written, in every culture's own voice, as a named taboo the fiction itself condemns — never presented as an authentic real-world practice.

## Open items for later passes

- Verify final sigil shapes at art-lock against a broader runic/sacred-symbol reference sweep (not just the initial geometric brief).
- Verify final voice-line pool (systems/voices/) for the advisors once written in full.
- Re-check culture names once architecture/costume concept art lands, in case visual specifics drift toward a real people's material culture rather than the intended generic Northern materials.

**Verdict so far: no blocking issues.** This is not a final release verdict — see the follow-up passes appended below as content lands.

## Follow-up pass — campaign, skirmish/net, weather content (post-vertical-slice)

**Date: 2026-07-28. Reviewer: independent audit pass, no authorship overlap
with the content below.** Scope: everything named/invented since the
initial pass in `campaign/` (8 relics, 10 quests), `modes/skirmish/` +
`net/` ("Nine Thrones"), `systems/weather/` (storm Voices triggers),
`environment/` (color grading — checked for stray naming only), and
`world/sanctum_interior/` (the idol dressing). Method: read every named
file in full, then cross-checked each relic/quest's own `origin_notes`
claims against the actual `data/cultures/*.tres` `taboo_notes`/`ritual_notes`
text they cite, rather than taking the in-repo rationale comments on faith.

### Relics (`campaign/relic_catalog.gd`, `campaign/relic.gd`)

| Relic | Culture/mythos tie | Checked against | Finding |
|---|---|---|---|
| Raft-Bell of the Sinking | Fenrayt | `fenrayt.tres` `ritual_notes` (the Sinking — willing, inanimate) | Clean. Flavor text ("should have gone under... somebody fished it back out") is a mystery hook, not the Offering-Debt itself — the relic's whole point is the Sinking, the taboo's *opposite*. |
| Firereading Bowl | Sankiln | `sankiln.tres` `ritual_notes` ("advice, not worship") | Clean. Invented hearth-divination, not a real-world rite depicted under its own name. |
| Wavecall Horn | Raimborn | `raimborn.tres` `ritual_notes` ("costs nothing, nobody thrown to it") | Clean. Explicitly a free, harmless custom. |
| Grafting Knife of the First Name | Vainkeeper | `vainkeeper.tres` `ritual_notes` (naming-graft custom) | Clean. |
| The Four Warning-Staves | Cross-culture | All four `taboo_notes` (Offering-Debt/Ash-Debt/Keel-Debt/Root-Debt) | Verified word-for-word against the .tres files — every one of the four culture files independently names its own variant as a crime/bad-luck taboo, never a practice. This relic is the strongest hard-rule-7 artifact in the game: an object whose entire diegetic purpose is condemning the taboo, sourced from four independent already-vetted taboo texts, not invented fresh for this relic. **Clean, and a good example of the rule working as intended.** |
| Tally-Cord of the Ninefold Sea | Frame-myth only | README's own "Ninefold Sea" | Clean — ties to the game's own invented cosmology, not a real sea/naming tradition. |
| Waking-Den Stone | Avatar (species-neutral) | Otso/Krukk/Sarv sourcing (already cleared row 4 of the sourcing map) | Clean. Deliberately doesn't commit to one Avatar species, so it can't be read as favoring one real-world animal-cult reading over another. |
| Sliver of the Hidden Sun | Louhi/Kalevala | Louhi hiding the sun and moon inside a mountain (an actual *Kalevala* episode) | Clean. This is the one relic that leans directly on the source epic's own plot rather than an invented custom — matches the existing sourcing-map treatment of Louhi exactly ("a literary epic's own plot device," "no invented cruelty added beyond what the source epic already gives her"). The relic doesn't invent a new cruelty or turn the episode into a shock beat — it's a quiet, melancholy object ("does not shine. It remembers shining"), consistent with her established patient/acquisitive characterization. |

### Quests (`campaign/quest_catalog.gd`)

All ten titles/descriptions read clean against the seven hard rules. Two
groups get specific note:

- **The four culture quests + `q_four_debts_remembered`** — each culture
  quest's flavor text (e.g. "A god who wants their trust doesn't ask what's
  down there") stays inside that culture's own already-vetted ritual, and
  the capstone quest's text ("Every one of the four peoples keeps its own
  name for the same old crime... None of them needed a god to tell them it
  was wrong") is, if anything, a *stronger* condemnation of the Offering-Debt
  than the baseline hard rule requires — it explicitly denies the player-god
  any credit for the taboo being wrong. No note of concern.
- **The three Louhi quests** (`q_louhi_cold_wind`, `q_louhi_silence`,
  `q_louhi_reckoning`) — checked word-for-word against
  `docs/systems/louhi.md`'s "patient, acquisitive, a hoarder and a bargainer...
  no invented cruelty added beyond what the source epic already gives her."
  The quest text matches that register throughout: "She hasn't taken
  anything yet. She's deciding whether it's worth taking" (patient, not
  aggressive); "something is simply gone... or she's named her price"
  (hoarder/bargainer, not a monster); nothing depicts her harming a person
  on-screen, and tier 2's loss of a village is narrated obliquely ("nothing
  left there to defend") rather than as gore or spectacle. This is the same
  restraint the existing implementation (`actors/louhi/louhi_director.gd`)
  already holds itself to, carried through faithfully into the new
  narrative layer rather than loosened for a "quest reward" beat. Clean.

No quest rewards the Offering-Debt path in any way — confirmed by reading
`docs/systems/campaign.md`'s own "Scoped out" section, which states plainly
that this package deliberately did **not** build a `Sacrifice.offer()`
quest hook, precisely because a taboo-triggered "quest" would need a
penalty design, never a reward, and that wasn't in scope this pass. Correct
call, flagged rather than guessed at — no action needed from this audit.

### `docs/systems/campaign.md`

No additional invented names beyond what's already in the two `.gd` files
above (`campaign_manager.gd`/`quest.gd`/`scroll_book.gd` are pure
plumbing — no new proper nouns). Clean.

### Skirmish / net — "Nine Thrones" (`modes/skirmish/skirmish_scenario.gd`, `net/network_manager.gd`, `docs/systems/skirmish_net.md`)

"Nine Thrones" names a nine-seat multiplayer lobby, explicitly tied back to
the already-established "Ninefold Sea" frame-myth ("up to nine god-seats
can contest the Ninefold Sea's villages"), not to any real people, deity,
or rite. It is a mechanics label (max player count), not a claimed people
or practice — none of the seven hard rules actually apply to it, since it
names neither a culture, a deity, nor a rite. Worth stating plainly rather
than waving past: "Nine Thrones" has a loose surface echo of the Christian
angelic-hierarchy order called "Thrones" (Pseudo-Dionysius), but the game
never invokes angelology, never uses "Thrones" as a religious title, and
the number nine here derives transparently from this project's own
already-vetted "Ninefold Sea," not from any real liturgical or
cosmological nine (e.g. it is not "Nine Worlds," which would have been a
much closer and more loaded Norse echo — that specific phrase was
avoided). **Judgment: clean, no rename needed**, but flagging the
reasoning explicitly so a future pass doesn't have to re-derive it. Village
ownership, seat mechanics, and the retuned-Louhi opponent mode add no new
names or rites of their own — everything else in these two files is
mechanical (ENet peer ids, ownership dictionaries) with no fictional
content to check.

### Weather (`systems/weather/weather.gd`, `docs/systems/weather.md`)

The four storm triggers (`storm_forming`, `storm_broke`, `storm_calmed`,
`storm_passed`) are plain physical-simulation event names — no god, spirit,
or rite is named as the storm's cause or target anywhere in the code or
doc (Louhi's own tier-1 cold-front write is a separate, already-vetted
mechanic that merely *borrows* the weather system's Dictionary shape, per
`docs/systems/louhi.md`; nothing in `weather.gd` itself frames a storm as
her doing, or as any real weather deity's/spirit's doing). No storm voice
lines are authored yet (`docs/systems/weather.md` "Scoped out" states this
plainly), so there is nothing yet in `systems/voices/voice_lines.gd` to
check for these four triggers specifically — flagged as a forward-looking
item, not a finding, since it doesn't exist to review yet. Clean.

### Environment/performance (`environment/naklon_environment_driver.gd`, `docs/systems/performance_notes.md`)

As expected, this package's job was color grading and frame-budget
accounting, not lore — confirmed no invented names, cultures, deities, or
rites appear anywhere in either file. Clean, nothing further to check.

### Sanctum interior idol (`world/sanctum_interior/interior_dressing.gd`, `docs/systems/sanctum_interior_ui.md`)

The idol is procedural geometry only (`CSGCylinder3D` pedestal + column,
`CSGSphere3D` head) with no modeled face, iconography, or attributes beyond
a culture-tinted color (`color_primary`/`color_accent`, the same generic
per-culture palette already used for Sanctum's own walls) and a
Naklon-reactive emission glow. It depicts no specific figure — not Louhi,
not a named creator-deity, not any real-world venerated image — and
"idol" here reads as a generic devotional prop, the same register as the
existing altar. Nothing about its shape, dressing, or reactive glow draws
on any one real people's specific religious iconography; the culture skin
is exactly the same abstract color-swap mechanism already audited for
Sanctum's exterior. Clean.

### Verdict of this pass

**No blocking issues found.** Every newly-invented name, relic, quest, and
system-level label checked in this pass either (a) stays inside an
already-vetted sourcing lane (Louhi/Kalevala, the four invented cultures'
own already-cleared taboo/ritual text, the Ninefold Sea frame-myth), or (b)
is a plain mechanical label with no fictional content to violate a hard
rule in the first place. The one thing worth a second look at a later pass,
noted above rather than treated as a defect now: **"Nine Thrones"** is
judged clean today on the reasoning given, but since naming is exactly the
kind of thing that can drift as marketing copy, box art, or a splash screen
gets built around it later, a future pass should re-check that no
downstream material (trailer copy, store page, loading screens) pushes
"Nine Thrones" toward an explicit angelic-hierarchy reference the game
script itself carefully avoids. This is not a final release verdict — see
further follow-up passes appended below as more content lands.
