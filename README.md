# TITHE & TERROR

*(«Десятина и ужас»)* — a god-sim / life-sim hybrid. You are one of two gods
left awake over the Ninefold Sea. Everything else went quiet. The other one,
Louhi of Pohjola, is not in a hurry.

## Stack decision

**Engine: Godot 4.3 (Forward+ / Vulkan renderer), GDScript + a handful of
custom `.gdshader` files, no proprietary middleware.** This project needs a
huge, walkable, physically-simulated ocean-and-island world, a hand-driven
IK creature the player never directly controls, a gesture recognizer, and a
learning-agent creature — all of that is systems work, not asset-pipeline
work, and Godot's scene/resource format is plain text, which means the work
can be built, diffed, and reviewed the same way as the code that drives it.
Godot 4.3's Forward+ renderer already gives SDFGI global illumination,
screen-space and (where hardware supports it) voxel-traced reflections,
volumetric fog, soft contact-hardening shadows, a full glow/DOF/tonemap
post stack, and a real ocean-grade shading model — the actual visual
ceiling this brief asks for — without a licensing cost or an engine seat to
manage, and without fighting a rendering engine that wasn't built to expose
its internals to gameplay code (the Hand, the Avatar's learning state, and
the Naklon-reactive art direction all need to reach deep into rendering
state at runtime). Unreal would give a marginally higher ray-tracing
ceiling on real GPU hardware; it was not chosen because this project is
built and iterated in a sandboxed dev environment with **no GPU** (see
`docs/rendering.md`) — Unreal's editor and lighting bakes assume one and
Godot's does not, and the whole point of the stack choice is to keep art
direction, gameplay, and verification in the same loop everywhere the game
is actually built. Every render claim in this repo's docs is qualified by
that constraint rather than asserted and left for someone else to discover.

## What this repository is, honestly

This is a **deep, playable vertical slice** implementing every mechanic in
the design brief with real, working code and real (CC0/open-licensed)
assets — not a finished, shipped AAA title. A shipped AAA game in this
genre is a multi-year, many-discipline production (dedicated environment
artists, a mocap or hand-keyed animation pass on the Avatar, an audio
department, months of tuning). What an agentic coding session *can*
responsibly deliver, and what this repo contains, is:

- every system in the brief implemented as real, inspectable, running code
  (not stubs pretending to be features) — terrain, ocean, the Hand, sigil
  casting, villager AI, the Avatar's learning model, the Two Voices, Louhi's
  presence AI, Reach/Faith/fatigue, the Sanctum, weather, adaptive music;
- real screenshots taken from the actual engine (see `docs/rendering.md`
  for exactly how, and its limits — the sandbox this was built in has
  **no GPU**, so screenshots here are captured on Mesa's `llvmpipe`
  software Vulkan rasterizer; they prove the scene, materials, and lighting
  are real and correctly wired, they are *not* evidence of the frame rate
  the same scene would hit on real hardware, and this repo never claims
  otherwise);
- a full CREDITS.md trail for every third-party asset, checked by an
  independent audit pass (`docs/audit/`) with veto power over the release.

Where a system is deliberately scoped down for this pass (e.g. one culture
fully art-directed in depth, the other three defined in complete data/lore
form but lighter on bespoke geometry), it's stated plainly in
`docs/systems/` next to that system, not left for you to discover.

## Mythology & respect — read before touching names

The naming register is drawn from Norse, Slavic/East-Slavic folk,
Kalevala-Finnic, and circumpolar Northern folkloric material that is public
domain literature and living oral tradition. **Every people, deity,
settlement, and rite in this game is fictional.** No in-game culture is
named after, or stands in for, a real living or historical people; no
real venerated creator-deity or living sacred practice is depicted as
villainous, mocked, or used as loot. The one antagonist explicitly modeled
on a named source, Louhi of Pohjola, is drawn from the *Kalevala* — a
19th-century literary epic in the public domain, not a living cult — where
she is already the story's antagonist: patient, acquisitive, and a hoarder
of the sun. Full sourcing notes, and the reasoning behind every
borderline call, are in `docs/audit/respect_audit.md`, which the
independent audit package can veto the release over.

## Repository layout

```
core/               Naklon (alignment), GameState, Village/Culture data
data/cultures/       Fenrayt, Sankiln, Raimborn, Vainkeeper — invented peoples
world/               terrain, ocean, sanctum, sanctum_interior
actors/              hand, villagers, avatar (+ combat), louhi
systems/             sigils, economy, faith (reach/fatigue), weather, voices
modes/               skirmish maps, Nine Thrones networking
environment/         WorldEnvironment, post-process, Naklon-driven grading
audio/               adaptive music director, spatial ambience
ui/                  Sanctum-as-menu, HUD-less diegetic UI, camera rig
campaign/            quests, sigil scrolls, relics, Louhi's approach
docs/systems/        one doc per system: what's implemented, what's scoped out
docs/audit/          license, originality, and respect audit reports
CREDITS.md           every third-party asset, source, author, license
```

## Running it

```
godot --path . 
```

Requires Godot 4.3 (Forward+/Vulkan). A software-Vulkan fallback
(`lavapipe`/`llvmpipe`, bundled with Mesa) works for development on
machines without a GPU, at development-only frame rates — see
`docs/rendering.md`.
