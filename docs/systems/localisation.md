# Localisation

## The shape of it

Godot's translation server, with a CSV in `localization/strings.csv` and
**the English source text as the key**.

That choice is the whole design. The alternative — symbolic keys like
`HUD_VILLAGES_OWNED` — means an untranslated string renders as
`HUD_VILLAGES_OWNED` on screen, so the game is broken until the table is
complete. Keyed by the source text, a missing row renders as the original
English sentence: still readable, still in voice, still shippable. This
project has 253 pairs of authored dialogue and they are being translated in
batches, so degrading one line at a time is not a nicety, it is the only way
the work can be done incrementally.

## Where translation happens

| What | Where it is translated |
|---|---|
| Menus, pause, settings | `tr()` at build/retranslate time |
| HUD, end card, help line | `tr()` on the format template, THEN `%` |
| Village captions | `tr()` on the template, then `%` |
| Rite names and descriptions | `tr()` in `ui/rite_grimoire.gd` |
| Voice lines | `TranslationServer.translate()` in `voice_lines.gd`'s `pick_pair`, **before** placeholder substitution |
| Speaker names | `tr()` in `ui/voice_log.gd`'s `_rebuild` |
| Village names | `TranslationServer.translate()` in `settlement_planner.gd` |

Two rules that are easy to get wrong:

1. **Translate the template, not the result.** `tr("%d hungry")` then `%`,
   never `tr("3 hungry")`. Otherwise the table needs a row per number.
2. **`TranslationServer.translate()`, not `tr()`, outside Nodes.** `tr()` is
   an `Object` method. `SettlementPlanner` is a static helper and
   `VoiceLinePool` is a `RefCounted`; both would fail to parse.

## Village names

`SettlementPlanner._name_for()` returns BOTH an English name and a display
name. The village's ID is built from the English one and must stay stable:
an ID that changed with the locale would make a save written in Russian
unloadable in English. The display name goes through the table twice, once
for the culture stem and once for the landform word, plus once more for the
join — Russian settlement names of this shape take a hyphen
(Фенрайт-Лощина), English a space.

Invented creature names are transliterated rather than translated. They are
proper nouns of this world; but they still have to go THROUGH the table, or a
Russian sentence ends up with an English word wedged into the middle of it.

## Continuing the translation

Dump every authored voice line:

```
python3 - <<'PY'
import re
s=open('systems/voices/voice_lines.gd').read()
pat = re.compile(r'_p\(\s*"([^"]+)"\s*,\s*\n?\s*"((?:[^"\\]|\\.)*)"\s*,\s*\n?\s*"((?:[^"\\]|\\.)*)"\s*\)', re.S)
for m in pat.findall(s):
    print(m[1]); print(m[2])
PY
```

Cross-reference against column 1 of `localization/strings.csv`, translate
what is missing, append rows. Keep every `{placeholder}` intact — they are
substituted after translation.

## Known gaps

* Roughly half the Voice pairs are still English (campaign quests, Louhi's
  signs, the Avatar, missionaries, construction, offerings).
* Quest titles in `campaign/quest_catalog.gd` are not routed through `tr()`
  yet, so the objective line's "Spoken of: ..." stays English.
* Changing the language mid-game does not rename villages that have already
  been generated; their `display_name` was resolved at plan time. Restarting
  the island fixes it. Worth doing properly if language switching turns out
  to be something people do more than once.
