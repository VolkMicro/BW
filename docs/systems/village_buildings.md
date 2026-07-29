# Village buildings — the temple and the dwellings

`world/village/` puts a settlement on the ground: dwellings around each
village, a landmark building, and the temple superstructure over each Sanctum.

## Why this exists

Two things a player said on first looking at the island: *"I don't understand
what these Sanctums are"* and *"I didn't see any houses."* Both fair. The
systems underneath — village hp, faith, offering, prayer — were already real;
they simply could not be read. This is a legibility pass, not a content one.

## Dwellings: real models, not procedural boxes

The first version built houses procedurally. At village-level zoom they read
as brown wedges, and the verdict was "грустно" — which was correct. They are
now real CC0 models (see Assets used).

**One MultiMesh per model, not per building.** Four house types means four
draw calls for every dwelling on the island, however many villages there are.
Placement is bucketed by model so this stays true as villages are added.

**No `material_override`.** The models carry their own materials — nine
surfaces on House_1, one per material — and overriding would collapse them all
onto a single colour and throw the roof/plaster/stone split away.

**Houses face the Sanctum**, with about ±50° of slack. A village whose doors
all point at its temple reads as a settlement gathered around something, which
is exactly what it is; fully random yaw reads as debris.

## Two traps this hit, both worth knowing

**The models imported black.** The `.mtl` files carry *linear* diffuse values
straight out of Blender — House_1's nine surfaces measure 0.343, 0.122, 0.308,
0.028, 0.213, 0.124, 0.078, 0.015, 0.177. Godot imports those as albedo
unchanged, which is faithful and useless: under this project's deliberately low
exposure (`tonemap_exposure` 0.52, set so the ocean does not blow out) every
house was a black silhouette. Diagnosed by *reading the imported materials*,
not by guessing at lighting — the same discipline that found the terrain
winding bug.

Fixed by raising each channel by `^(1/2.2)` at load, which recovers roughly the
value the artist saw in Blender's viewport (0.028 → 0.19, 0.343 → 0.61).
Materials are duplicated first: the imported Mesh is a shared resource and
mutating it in place writes through Godot's resource cache.

This is the *third* time in this project that authored-dark colour values have
caused a "why is it black" hunt — the culture primaries did it twice (Fenrayt's
is 0.106, 0.114, 0.098). If something renders black here, suspect the palette
before the lighting.

**Three models crash Godot's OBJ importer.** `Mill.obj`, `Stable.obj` and
`Sawmill.obj` reproducibly abort `--import` with SIGABRT (three separate runs);
the six kept import cleanly. They were removed from the repository rather than
left to abort the importer for whoever next clones this.

## The temple

`world/village/village_architecture.gd` builds it procedurally — there is no
CC0 model of a *pagan northern temple*, and buying the silhouette this design
needs was not on offer. Three tiers of steep gabled roof, corner posts, and
abstract curled beam-ends at the ridge. Tiering is what separates a temple from
a big house: a house has one roof, a temple has a stack, and a stack reads as
height from any angle.

It is a **superstructure over** the existing Sanctum, not a replacement.
`sanctum.tscn` already carries the walkable hollow shell, its collision, the
doorway, the altar and its offering trigger, and the scorch/glow materials
`sanctum.gd` drives from village hp and faith. Rebuilding all that to change a
silhouette would be daft. Because the roof is parented to `Exterior`, it
inherits the collapse tween when a village dies — the temple falls with the
building, for free.

**Audit note:** this is architecture, not iconography. No cross, no runic
inventory, nothing drawn from a living practice. Steep roofs and heavy posts
are structural answers to snow and timber, used by many northern building
traditions and owned by none of them; the ridge prows are deliberately abstract
rather than any recognisable creature. See `docs/audit/respect_audit.md`.

## Assets used

Rows ready for the `CREDITS.md` consolidation pass, under **Models / props**:

| Asset | Source | Author | License | Used for |
|---|---|---|---|---|
| Medieval Village Pack — `House_1`, `House_2`, `House_3`, `House_4` (OBJ) | https://opengameart.org/content/lowpoly-medieval-village-pack | Quaternius | CC0 1.0 | village dwellings |
| Medieval Village Pack — `Blacksmith`, `Inn` (OBJ) | https://opengameart.org/content/lowpoly-medieval-village-pack | Quaternius | CC0 1.0 | per-village landmark building |

Licence verified from the pack's own `License.txt`, which ships alongside the
models in `assets/models/village/` and reads: *"CC0 1.0 Universal (CC0 1.0)
Public Domain Dedication"*. Untextured, flat-material, ~1500–3800 triangles
each — which is exactly right for the target hardware.
