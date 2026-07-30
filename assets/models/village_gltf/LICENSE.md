# Village models (glTF)

All nine models below are by **Quaternius**, released under **CC0 1.0
Universal (public domain dedication)**, obtained through the poly.pizza
mirror. CC0 imposes no attribution requirement; they are credited here
anyway, because `docs/audit/respect_audit.md` requires every third-party
asset in this repository to trace to a real, checkable licence and a named
author.

| File | poly.pizza | Author | Licence |
|---|---|---|---|
| Mill.glb | https://poly.pizza/m/89dsFYAoX1 | Quaternius | CC0 |
| Sawmill.glb | https://poly.pizza/m/UTJHANd25O | Quaternius | CC0 |
| Well.glb | https://poly.pizza/m/QlqncKYxXb | Quaternius | CC0 |
| Fence.glb | https://poly.pizza/m/e02PFKKhbr | Quaternius | CC0 |
| MarketStalls.glb | https://poly.pizza/m/PUZZ5F91OE | Quaternius | CC0 |
| BellTower.glb | https://poly.pizza/m/ux44tbeQvj | Quaternius | CC0 |
| Barracks.glb | https://poly.pizza/m/UXCOwRBSxx | Quaternius | CC0 |
| VillageMarket.glb | https://poly.pizza/m/0TsHLxX6CB | Quaternius | CC0 |
| Cart.glb | https://poly.pizza/m/94b32c91 (m/l7bDe7ak6j) | Quaternius | CC0 |

## Why glTF and not OBJ

The four houses and two landmarks already in `assets/models/village/` are
the same author's pack in OBJ. Three models from that pack — Mill, Stable and
Sawmill — **reproducibly crashed Godot 4.3's OBJ importer** (SIGABRT during
`--import`, three separate runs), and were removed from the repository rather
than ship an asset that aborts the importer for whoever next clones this.

glTF goes through a completely different importer, so the same buildings load
without trouble. That is the whole reason this directory exists beside the
other one.

## No sacred imagery

Deliberately absent: every "church"/"chapel"/"cathedral" model in these
packs. `docs/audit/respect_audit.md` forbids real sacred symbols, and those
models carry crosses. The bell tower is a bell tower — a civic structure with
no religious marking on it — and the game's own temples are built
procedurally by `world/village/village_architecture.gd` precisely so that
their iconography is invented rather than borrowed.
