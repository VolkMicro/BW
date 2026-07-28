# Credits

Every third-party asset used in this project is listed here with its source,
author, license, and (where the license requires it) the exact attribution
line used in-game or in this repo. Nothing ships without an entry here.
Nothing extracted, ripped, or converted from another game is used anywhere
in this project.

## Textures / PBR materials

| Asset | Source | Author | License | Used for |
|---|---|---|---|---|
| Grass 004 (1K-JPG: Color, NormalGL, Roughness) | https://ambientcg.com/a/Grass004 | ambientCG (Lennart Demes) | CC0 1.0 | `world/terrain/` — flat/rolling ground cover, `assets/textures/terrain/grass/` |
| Rock 023 (1K-JPG: Color, NormalGL, Roughness) | https://ambientcg.com/a/Rock023 | ambientCG (Lennart Demes) | CC0 1.0 | `world/terrain/` — cliff faces, steep slopes, `assets/textures/terrain/rock/` |
| Ground 054 (1K-JPG: Color, NormalGL, Roughness) | https://ambientcg.com/a/Ground054 | ambientCG (Lennart Demes) | CC0 1.0 | `world/terrain/` — beach/low-elevation flat ground, `assets/textures/terrain/sand/` |

No other package pulled a texture — `docs/systems/art_direction.md`, `ocean.md`, and `sanctum.md` all confirm their materials are procedural/code-generated or plain `StandardMaterial3D` colors, not downloaded scans.

## HDRIs

None pulled this pass. `environment/world_environment.tres` uses a procedural `ProceduralSkyMaterial`, not an HDRI; no package's own doc lists one.

## Models / props

None pulled this pass. Every actor/prop in the repo (Hand, villagers, Avatar, Sanctum, standing stones, etc.) is built from Godot primitive meshes (`CapsuleMesh`/`BoxMesh`/`SphereMesh`/CSG) per each package's own "Assets used" section — see `docs/systems/`.

## Audio (SFX)

| Asset | Source | Author | License | Attribution required? |
|---|---|---|---|---|
| `audio/sfx/bong_001.ogg` (from Kenney's "Interface Sounds" pack) | https://kenney.nl/assets/interface-sounds | Kenney (Kenney Vleugels) | CC0 1.0 | No — CC0; a Kenney credit is requested but not mandatory per the pack's own License.txt |

## Music

None. `docs/systems/audio.md` documents an exhaustive, recorded search (Kenney's full Audio category, Freesound, Musopen) that turned up no usable, rights-clear prayer/infernal music bed; `audio/music_director.gd`'s four continuous layers (prayer, infernal, wind, sea) are runtime-synthesized via `AudioStreamGenerator`, not sourced files, so there is nothing here that traces to a third-party license. See that doc's "Honesty: what's real vs. placeholder" section for the full record and the follow-up this leaves for a future audio pass.

## Engine & tools

| Tool | Source | License |
|---|---|---|
| Godot Engine 4.3 | https://godotengine.org | MIT |

## Data feeds (not assets, no license obligation, listed for transparency)

- Open-Meteo (https://open-meteo.com) — free weather API, no key required, CC-BY-4.0 attribution requested by the provider: "Weather data by Open-Meteo.com". Used by the optional real-weather feed (systems/weather/).

## Rule enforced by the audit package (docs/audit/)

Every row above must trace to a real, checkable license. "Found on a
wallpaper site" is not a license. If an asset's origin can't be established,
it does not go in the build — full stop.
