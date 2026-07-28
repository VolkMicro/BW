# Directory ownership map (avoids parallel-build collisions)

Foundation (already built, do not restructure without reason):
`project.godot`, `core/`, `data/cultures/*.tres`, `environment/world_environment.tres`,
`world/god_view.tscn` (placeholder — B/C/D extend it), `scripts_ci/`,
`README.md`, `CREDITS.md`, `LICENSE`, `.gitignore`, `docs/rendering.md`,
`docs/audit/respect_audit.md`, `docs/systems/engineering.md`.

| Pkg | Owns (write here only) | Depends on |
|---|---|---|
| B | `world/terrain/` | core/, environment/ |
| C | `world/ocean/` | core/, environment/ |
| D | `shaders/`, `materials/`, `docs/systems/art_direction.md` | core/naklon.gd |
| E | `actors/hand/` | core/, systems/faith/reach.gd |
| F | `systems/sigils/` | core/ |
| G | `actors/villagers/` | core/, systems/faith/ |
| H | `systems/economy/` | core/ |
| I | `world/sanctum/` | core/, systems/faith/reach.gd, systems/voices/voices.gd |
| J | extends `systems/faith/` (do not break reach.gd's existing public API) | core/ |
| K | `actors/avatar/` (not `actors/avatar/combat/`) | core/ |
| L | `actors/avatar/combat/` | actors/avatar/ (K) — build against K's public API, documented in K's own docs/systems note |
| M | `systems/voices/` (replaces stub voice_lines.gd) | core/ |
| N | `actors/louhi/` | core/, systems/weather/weather.gd |
| O | `modes/skirmish/`, `net/` | core/ |
| P | `systems/weather/` (replaces stub weather.gd) | none |
| Q | `environment/` (extend, don't replace world_environment.tres wholesale), `docs/systems/performance_notes.md` | docs/systems/engineering.md |
| R | `audio/` (replaces stub music_director.gd) | core/naklon.gd |
| S | `campaign/` | core/ |
| T | `world/sanctum_interior/`, `ui/` | core/, world/sanctum/ (I) |

Every package writes its own `docs/systems/<package_name>.md` — never edits
another package's doc. Every package that downloads a CC0/licensed asset
lists it in its own doc's "Assets used" section (source URL, author,
license) instead of touching CREDITS.md directly; a single consolidation
pass merges all of these into CREDITS.md afterward to avoid concurrent
merge conflicts on one file.

None of B–T may edit `project.godot` — required autoloads are already
registered (Naklon, GameState, Reach, Voices, Weather, MusicDirector).
