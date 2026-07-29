# Wildlife — animals with actual AI (`actors/wildlife/`)

Before this pass there was **no animal or wildlife system anywhere in this
project** — nothing in the repo mentioned animals, wildlife, or predators.
The only non-human creature was the Avatar (package K), which is the player's
one learning creature, not a population. This package adds the island's
resident fauna: three invented species, a real state machine per animal, real
predation, and a shared manager that keeps the whole thing affordable on the
target hardware.

## What's here

| File | What it is |
|---|---|
| `actors/wildlife/wildlife_species.gd` | `class_name WildlifeSpecies extends Resource`. Data-only tuning per species. Same pattern package K used for `AvatarSpecies`: one shared brain, one small Resource per species. |
| `actors/wildlife/species/rimefleece.tres` | The grazing herd animal. |
| `actors/wildlife/species/snagbill.tres` | The skittish scavenger bird. |
| `actors/wildlife/species/thawjaw.tres` | The lone predator. |
| `actors/wildlife/wildlife_body.gd` | `class_name WildlifeBody`. Static, cached procedural body builder — Godot primitives merged into one `ArrayMesh` per species. |
| `actors/wildlife/wild_creature.gd` | `class_name WildCreature extends CharacterBody3D`. The AI. |
| `actors/wildlife/wild_creature.tscn` | The one shared creature scene (all three species use it; geometry and collider come from the `.tres`). |
| `actors/wildlife/wildlife_manager.gd` | `class_name WildlifeManager extends Node3D`. Spawns, places, and drives the population; owns the shared threat cache. |
| `actors/wildlife/wildlife_manager.tscn` | One-node wrapper, same convention as `actors/louhi/louhi_director.tscn`. |
| `actors/wildlife/wildlife_demo.gd` / `.tscn` | Standalone runnable demo over a real `IslandTerrain`, same convention as `village_demo.tscn` / `avatar_demo.tscn`. |

---

## The three species

All three names are **invented compounds**, checked against
`docs/audit/respect_audit.md`'s seven hard rules and against the already-used
Avatar species names (Otso / Krukk / Sarv — no collision; these are not
Finnic-register single words at all, so they can't be mistaken for a fourth
Avatar option). None names a real people, a deity, a venerated figure, a real
sacred animal, or a real endangered species. None is a wolf, bear, raven, or
any other animal that carries a specific veneration in the northern
traditions this project's register draws on — that avoidance is deliberate,
not accidental. The snagbill in particular is **not** a corvid and is
explicitly not a raven: Hiisi is already characterised as a raven/fox hybrid
archetype (`systems/voices/voice_lines.gd`), and the snagbill carries no
spiritual role in the fiction at all — it is a shore carrion bird of no real
family. Etymologies are transparently English-compound (rime + fleece, snag +
bill, thaw + jaw), the same construction the four cultures already use
(bog+wright, kiln, rime-born, vine-keeper).

### Rimefleece — the grazing herd animal

> Named for a coat that looks frosted even in high summer. They are the
> reason anyone on this island ever bothered inventing a fence. A rimefleece
> has exactly two ideas — grass, and the herd — and will abandon the first
> for the second without hesitating.

**Silhouette:** a low, broad woolly barrel slung between four stubby legs,
with a small blunt head carried *low* in a grazing posture and a bare dark
face. At god-view height it reads as a wide pale lozenge close to the ground.
Pale frost-grey body, peat-dark face and legs.

Herds. Flees at 11 m. Slow (1.5 m/s) but panics fast (4.6 m/s). The only
thing on the island a thawjaw hunts.

### Snagbill — the skittish scavenger

> Follows anything with teeth, at a respectful distance. Children are told a
> snagbill can count to nine, which is a lie — but it can certainly count to
> one, and it leaves the moment the answer stops being zero.

**Silhouette:** tall, nervy and top-heavy — a small slate body on two thin
legs, a long thin neck, a hooked pale bill, box wings held half-out. A
vertical dark tick-mark standing next to whatever it is waiting to finish
dying. Dark slate with a bone-pale throat, bill and legs.

Does not herd. The most skittish thing on the island (flees at 18 m, faster
than anything else at 6.4 m/s) and the widest-ranging (42 m home range).
Not hunted by anything — it is absent from the thawjaw's `hunts` list, which
is how it survives next to a predator without needing a fudged "escape
chance". **Scavenges:** when anything dies within 60 m, every snagbill walks
to the carcass and feeds for ~9 s. Because its fear response outranks its
scavenging, the classic behaviour falls out for free — the birds get shooed
off the kill by the feeding predator and hop back in once it wanders away.

### Thawjaw — the lone predator

> One to an island, usually. Nobody has seen two thawjaws together and been
> in a position to report it. It hunts the rimefleece herds and ignores the
> villages — for now — and it is the reason the herds have any opinions at
> all.

**Silhouette:** long, low and heavy-fronted — a deep box chest, a wedge head
thrust forward on a short thick neck, a pale jaw, a ridge of plates down the
spine, and legs long enough that it is obviously faster than anything
standing near it. A dark horizontal bar with one bright jaw. Dark peat-brown
with bone accents.

Gets hungry every ~85 s, picks the nearest rimefleece within 34 m, pursues at
5.6 m/s, kills at 1.8 m, feeds for 13 s. Does not flee from other predators
(it is not `is_prey`), but *does* flee a god — at only 8 m, because a
thawjaw is warier of a god than a sheep is but not by much. It never hunts
villagers or the Avatar; see "Scoped out".

---

## The AI: a real state machine, not an animation loop

`WildCreature.State`: `GRAZE`, `WANDER`, `FLEE`, `HUNT`, `FEED`,
`SCAVENGE`, `DEAD`. The decision pass (`_think()`) evaluates in this order,
and the order is the design:

1. **Fear beats everything.** Nearest threat (gods first, then predators for
   anything `is_prey`) against the species' `flee_radius`. Entering `FLEE`
   fires `alarmed` / `WildlifeManager.creature_alarmed`.
2. **Calming down is separate from fleeing**, with real hysteresis:
   `calm_radius` is larger than `flee_radius` (11 → 17 m for a rimefleece)
   and the threat has to stay outside it for `calm_seconds` before the animal
   goes back to wandering. Without the gap animals strobe in and out of panic
   at the boundary; with it, an animal that has just escaped keeps moving
   nervously for a few seconds before settling.
3. **Fleeing is steered, not blind.** `_aim_away_from()` runs the escape
   vector away from the threat, biases it back toward the home range once the
   animal has been pushed twice the range's radius out, and — if the escape
   route would put it in the sea — veers along the shore instead. That is one
   height lookup on a think tick, not a raycast.
4. **Predator business.** Hunger accumulates in real time; a hungry predator
   asks the manager for the nearest prey it actually hunts, pursues it,
   re-aims at the live target every think tick, gives up if the prey gets
   2.25× its hunt radius away, and kills on contact.
5. **The prey really dies.** `WildCreature.kill_by()` sets `DEAD`, drops the
   creature out of its groups so nothing can re-target it, lies the body over
   (the same capsule-tilt convention `villager.gd` uses for `COLLAPSED`),
   fires `killed` **and** `WildlifeManager.prey_killed(prey_species,
   predator_species, world_position)` **before** despawning so listeners can
   read the position while the node is still valid, disables its collider so
   the feeding predator doesn't shove its own dinner around, and queue_frees
   after 6 s.
6. **Scavenging**, then **ordinary life** (alternating `GRAZE` and `WANDER`
   legs inside the home range).

### Flocking, honestly

The brief suggested nearest-neighbour cohesion. This implements **per-herd
centroid cohesion** instead, which is strictly cheaper and behaves the same
at this scale: `WildlifeManager` computes each herd's centroid *once* in the
single O(N) pass it already runs twice a second, and a rimefleece choosing
its next wander target lerps that target toward the centroid **only if it is
already further out than `cohesion_radius` (9 m)**. Nearest-neighbour would
be O(N) work *per creature* (O(N²) overall) for a visually identical loose
blob. Cost of this version: one `Dictionary` lookup and one `Vector3.lerp`
per creature per wander-target pick — i.e. roughly once every 5 seconds.

Measured in a headless run: a herd of 12 spawned with a mean spread of ~23 m
from its own centroid converged to **9-14 m** after ~40 s undisturbed, and
scattered on cue when a threat was parked on top of one of them. It is a
loose blob that reforms, not a rigid formation — which is the intent.

### Naklon reaction — implemented, not scoped out

Two effects, both essentially free because neither is polled:

- **Skittishness.** `WildlifeManager` connects to `Naklon.naklon_changed`
  (which `core/naklon.gd` only fires on a deliberate player action — "Naklon
  does not passively drift") and pushes a fear scale to every creature, which
  re-derives six cached squared radii. Under full mercy ×0.75 (animals let
  you get close), neutral ×1.0, full cruelty ×1.40 (they spook from much
  further away and take longer to settle). **Measured:** 0.75 / 1.00 / 1.40
  at Naklon −1 / 0 / +1.
- **Scarcity, at spawn time only.** A cruel god's island has fewer animals.
  **Measured** against a base count of 12: Naklon −1.0 → 14, −0.5 → 13,
  0.0 → 12, +0.5 → 10, +1.0 → 8.

Both use a **piecewise** mercy→neutral→cruelty blend rather than a straight
two-point lerp, so a player who has never acted (`Naklon.value == 0.0`,
`unit() == 0.5`) gets exactly the authored numbers instead of the midpoint of
the two poles. That is the same reasoning
`environment/naklon_environment_driver.gd` already documents in
`docs/systems/performance_notes.md` ("Deviation from `art_direction.md` §4"),
reused deliberately rather than re-litigated.

### Ground placement and gravity

Nothing floats, and there is not a single raycast in this package.

- **Spawn**: `WildlifeManager._find_spawn_point()` rejection-samples up to 24
  points on a disc (uniformly, via `sqrt(randf())`), calling
  `IslandTerrain.sample_height()` on each and rejecting anything below the
  species' `min_ground_height`. The accepted point is used at
  `terrain_height + 0.8 m` and gravity settles the body — exactly the
  convention `world/god_view.gd` already uses for villagers.
  `sample_height()` samples the **smoothed** heightmap
  (`island_terrain.gd:104-115`), which is what the visible mesh and the
  `HeightMapShape3D` collision are both built from, so a creature agrees with
  the ground the player can see.
- **Standing on it**: `CharacterBody3D` + `move_and_slide()` + a 9.8 gravity
  integration, identical in shape to `actors/villagers/villager.gd:468-495`.
- **Not walking into the sea**: every wander target is height-checked before
  being accepted (up to 4 tries; if all fail the animal simply stays put and
  retries at its next state change). Same check on the flee vector.
- **Verified**, headless, over several minutes of simulated time: with 19
  creatures on a real 200 m `IslandTerrain`, the count of creatures more than
  1.0 m above or 0.6 m below the sampled ground was **0 at every census**,
  including immediately after spawn, mid-panic, and mid-hunt. A creature
  instanced by hand with no manager at all was checked separately: it landed
  with its origin exactly on the sampled ground height and did not crash.

---

## PERFORMANCE

Target hardware, per the standing brief and
`docs/systems/performance_notes.md`: a Dell Latitude 5411, **integrated Intel
graphics only, no discrete GPU, currently ~5-6 fps**. SDFGI, volumetric fog
and SSAO are already disabled outright. Everything below was designed against
that, and the CPU-side claims were *measured* headlessly. **The GPU-side
claims were not and cannot be** — this sandbox has no GPU of any kind, so
this document does not state a frame rate, here or anywhere.

### Per-creature, per-frame cost

**One script callback.** There is no `_process()` on `WildCreature` at all —
the decision timer and the movement both live in a single
`_physics_process()`. `villager.gd` uses both callbacks; this is deliberately
half that.

Inside that one callback, per creature per physics tick:

| Case | Work |
|---|---|
| **Resting** (`GRAZE`/`FEED`/arrived-`SCAVENGE`, already on the floor, already stopped) | 3 float subtractions and a compare, then `return`. **No gravity integration, no `move_and_slide()`, no steering math, no draw-call-side change.** |
| **Moving** (`WANDER`/`FLEE`/`HUNT`) | the above, plus gravity, one vector subtract, one `length_squared()`, one `sqrt`, one `lerp_angle`, and one `move_and_slide()`. |

**Measured resting fraction: 56-61%** of creature-frames across 60 samples of
a settled 18-19 animal population. So a bit more than half the herd is paying
almost nothing on any given frame, and `move_and_slide()` — by far the
dominant cost here — is being called roughly 8 times per frame for a
19-animal population, not 19.

**Decisions run ~3×/second per creature**, not 60: `think_interval` is
0.30-0.40 s per species, and each creature's phase is randomized at spawn
(`randf_range(0, think_interval)`) and re-jittered ±15% on every tick, so a
herd spawned in a single frame never converges onto one think frame. A
decision pass is a handful of squared-distance compares against at most ~6
cached `Vector3`s.

**Zero `.distance_to()` / `.length()` in any hot path.** Every proximity test
is `length_squared()` against a radius pre-squared once into `_flee_r2`,
`_calm_r2`, `_kill_r2`, `_cohesion_r2`, `_hunt_r2`, `_home_r2` — recomputed
only when the species or the Naklon fear scale changes.

**Zero raycasts, ever.** Ground contact is `CharacterBody3D`'s own floor
detection. "Is this spot dry land" is `IslandTerrain.sample_height()`, which
is a bilinear read out of an already-built `PackedFloat32Array`
(`island_generator.gd:265-283`) — not a physics query — and it is only called
when picking a new wander target (every 3-8 s) or a flee vector, never per
frame.

**No creature ever searches the scene tree.** No `get_nodes_in_group`, no
`find_child`, no `get_first_node_in_group` anywhere in `wild_creature.gd`.

### Per-manager, per-frame cost

`WildlifeManager` has one `_process()` doing **three float subtractions per
frame**. Twice a second it runs one O(N) pass over the population that does
*all* the shared work at once: rebuild the threat cache, prune dead entries,
collect predator positions, and compute every herd centroid. Node references
(Avatar, Hand, terrain) are resolved **once** and only re-resolved if they go
invalid.

This is the whole reason a manager exists. The naive version — every creature
looking up the Avatar and the Hand every frame — is N tree walks + N group
queries + N `distance_to()` calls *per frame*. This is one pass, twice a
second, shared.

The predator's prey scan runs in the manager, on demand, **only while a
predator is hungry and targetless**, over the per-species bucket it already
maintains, with a 5 s cooldown after a failed or abandoned hunt so an empty
island doesn't get rescanned three times a second forever.

### Rendering cost

- **3 `ArrayMesh` resources and 6 `StandardMaterial3D` instances for the
  entire population**, not one per creature. `WildlifeBody` merges every
  primitive for a species into one mesh with exactly two surfaces
  (`SurfaceTool.append_from`) and caches it statically. Twelve rimefleeces
  share one mesh and two materials, so the renderer sorts them into one
  material batch.
- **1 `MeshInstance3D` per creature, 2 surfaces** — so ~2 draw calls each,
  not the 8-14 that eight-to-fourteen child `MeshInstance3D`s would cost
  (which is what `actors/avatar/avatar.gd` does, correctly, for the *one*
  Avatar; it is the wrong shape for a herd).
- **Measured vertex counts** (surface 0 / surface 1): rimefleece 198/198,
  snagbill 225/162, thawjaw 414/120. So **~400-530 verts per animal**, or
  roughly **8-9k verts for a 19-animal population.** Every primitive is built
  at 6-8 radial segments and 2-3 rings rather than Godot's defaults — a
  default `SphereMesh` alone is 64×32 ≈ 4k verts, which would have been
  absurd for something seen from god-view height.
- **Honest limit:** shared meshes and materials cut state changes and VRAM;
  they do **not** collapse a herd into one draw call. Sixteen creatures still
  cost roughly 32 draw calls. That is small next to three CSG Sanctums and an
  800 m ocean plane, but it is not zero, and it is the first thing to attack
  if a real profile on the Latitude ever implicates wildlife — see the lever
  below.

### The one lever this package leaves on the table

If a real profile ever shows wildlife draw calls mattering, replace the
per-creature `MeshInstance3D` with a **`MultiMeshInstance3D` per species**,
written by the manager in its existing 0.5 s pass (interpolated for the
frames between, or accepted at 2 Hz for distant animals). That would take a
whole species to one draw call. It was **not** done here because it means
giving up `CharacterBody3D`'s gravity and floor collision — which is the
thing keeping the animals honestly on the terrain, and which the brief
specifically asked to match `villager.gd` on — and trading it for hand-rolled
ground snapping. Flagged as the next lever, not silently skipped.

### Recommended instance count

**16 total: 10 rimefleece, 5 snagbill, 1 thawjaw.** That is a real herd, a
scatter of birds, and one predator — enough for the island to feel inhabited
and dangerous.

19 (12/6/1) is what was actually simulated for the numbers above and behaved
fine CPU-side. **Do not go past ~24 total** without a real profile on the
Latitude: the honest reason is that this project has 15 villagers +
3 Sanctums + an 800 m Gerstner ocean already competing for the same ~5-6 fps,
and the next lever `docs/systems/performance_notes.md` itself pre-commits to
after the render toggles is *"draw distance and crowd counts."* Adding a
crowd right before that lever gets pulled would be working against the
project's own plan. If frame time needs to come back, the counts below are
the knob — halve them, or set `thawjaw_count = 0` and keep the herd.

---

## INTEGRATION — exact instructions

**This package deliberately did not touch `world/god_view.tscn` or
`world/god_view.gd`.** Here is everything the integration agent needs.

### Scene to instance

```
res://actors/wildlife/wildlife_manager.tscn
```

One instance, as a **direct child of `GodView`** (a sibling of `Island`,
`Avatar`, `Hand`, `Villages`). Name it `Wildlife`. It is a `Node3D`; leave its
transform at the origin.

Order does not matter — it resolves `Island`, `Avatar` and `Hand` itself and
re-resolves them lazily if they aren't up yet — but placing it **after
`Island` and `Avatar`** in the tree means it finds everything on the very
first cache rebuild.

### Exported properties to set on that node

| Property | Value for `god_view.tscn` | Why |
|---|---|---|
| `terrain_path` | `NodePath("../Island")` | The real `IslandTerrain` (seed 1, 320 m, res 161, `max_height` 42). Without it the manager falls back to a flat plane at y=0 and everything spawns in the sea. **This is the one property you must not omit.** |
| `avatar_path` | *(leave empty)* | Auto-found via the `&"avatar"` group that `actors/avatar/avatar.gd:144` already joins. |
| `hand_path` | `NodePath("../Hand")` | Recommended. `hand.gd` registers no group (and this package may not edit package E's file, per `OWNERSHIP.md`), so the fallback is a one-time `find_child("Hand")` type check. Setting the path explicitly skips that search entirely. |
| `spawn_center_xz` | `Vector2(0, 0)` | Island centre. |
| `spawn_radius` | `120.0` | The island is 320 m across, so ±160 m is the full extent; 120 keeps spawns comfortably inland of the coastline at this seed/falloff, the same hand-tuned-for-this-seed caveat `integration.md` already records for the village anchors. |
| `rimefleece_count` | `10` | See "Recommended instance count". |
| `snagbill_count` | `5` | |
| `thawjaw_count` | `1` | |
| `show_debug_labels` | `false` (the default) | Deliberate: `integration.md` records that fixed-size `Label3D`s from 15 villagers collapsed into one unreadable block at god-view height. Wildlife defaults to labels **off** so that bug cannot recur. Flip on in the standalone demo, never here. |
| `naklon_affects_wildlife` | `true` (the default) | |
| `respawn_prey` | `true` (the default) | One grazer wanders back in from the coast every 90 s, up to the original count, so a long session doesn't end on an empty island. Predators never respawn. |

Everything else can stay at its default.

### Where on the island they should spawn

Do **not** hand-place them. The manager rejection-samples the spawn disc
against real terrain height and only accepts spots at or above each species'
`min_ground_height` (rimefleece 1.4 m, thawjaw 1.0 m, snagbill 0.6 m — the
bird is allowed nearer the waterline, which is the point of a shore
scavenger). Rimefleece additionally spawn **clumped**: the first one placed
anchors the herd and ~80% of the rest land within 12 m of it, so a herd
starts as a herd instead of spending two minutes finding itself.

With `spawn_center_xz = (0,0)` and `spawn_radius = 120`, animals land across
the whole inland body of the island, which puts them in and around the three
village anchors without being placed *at* them. That is intentional: a herd
grazing near Fenrayt Hollow, a thawjaw prowling the ridge.

### Optional hooks worth one line each

None of these are required — the system is fully live without them.

```gdscript
# In world/god_view.gd, after $Wildlife exists:
$Wildlife.prey_killed.connect(_on_wildlife_killed)
```

- `prey_killed(prey_species: StringName, predator_species: StringName, world_position: Vector3)`
- `creature_alarmed(creature: WildCreature, threat_position: Vector3)`
- `creature_spawned(creature: WildCreature)` — emitted deferred, so a parent
  connecting in its own `_ready()` genuinely receives all of them.

Two of these close gaps other packages' docs already flagged, if the
integration agent wants them:

- **`docs/systems/integration.md` "No context tag is ever opened for the
  Avatar in this scene"** names *"a predator appearing"* as exactly the kind
  of real world event that should drive `Avatar.begin_context()`.
  `creature_alarmed` is that event, now real and firing. One line in
  `god_view.gd` would make F/G (praise/chastise) actually teach the Avatar
  something. **This package did not write that line** — `god_view.gd` is out
  of scope and the tag vocabulary belongs to package K.
- `prey_killed` is a natural input for a future `Avatar.begin_context()` or
  for `systems/economy/` (a hunted island feeding a village). Not wired.

### Debug / QA

`WildlifeManager.debug_force_hunt()` makes every predator hungry immediately
instead of waiting out the 85 s hunger timer — the same convention
`LouhiDirector.debug_force_evaluate()` established, and the same reason
(`world/god_view.gd` binds `KEY_L` to Louhi's). Bind a spare key to it if you
want to see a kill without waiting.

---

## Verification actually performed

Everything claimed above about behaviour was run, headless, against a real
`IslandTerrain`, and read off the output — not inferred from the code.

- `godot --headless --path . --check-only --quit-after 3` — **exit 0, zero
  parse/compile/script errors**, zero `is_inside_tree` errors. (The only
  remaining output is the known-harmless `ObjectDB instances leaked at exit`
  plus the RID-leak lines, both of which were confirmed present in a baseline
  run of this project with `actors/wildlife/` moved out of the tree entirely —
  they are not this package's.)
- `godot --headless --path . actors/wildlife/wildlife_demo.tscn --quit-after 200`
  — completely silent, no errors.
- A temporary self-test scene (written, run, and then deleted) drove several
  minutes of simulated time and confirmed: meshes merge with 2 surfaces and 2
  materials and are genuinely shared between instances; 19 creatures spawn on
  real terrain with 0 floating at every census; parking a threat on one
  rimefleece put it in `FLEE` and moved it 13.7-14.3 m, leaving it outside its
  11 m flee radius but still inside its 17 m calm radius and therefore still
  fleeing (hysteresis working as designed); the thawjaw hunted, caught, and
  killed rimefleece, dropping the population 12 → 11 → 10, with `prey_killed`
  firing on each; snagbills entered `SCAVENGE` in response; the herd converged
  from ~23 m to 9-14 m spread; a hand-dropped creature with no manager landed
  exactly on the ground and did not crash.

### A real bug found and fixed during this pass

The first version of `wild_creature.gd` typed its `manager` field as
`WildlifeManager`. Because `wildlife_manager.gd` statically references
`WildCreature` throughout (typed arrays, typed signal arguments, typed
returns), that closed a **`class_name` cycle**, which Godot 4.3 rejects at
parse time with `Could not resolve external class member "manager"`.

Worth recording because of *how* it surfaced: **`--check-only --quit-after 3`
did not catch it.** That command validates the main scene
(`world/god_view.tscn`), which does not reference this package, so these
scripts were never loaded. It only appeared when the demo scene was actually
run. Fixed by making the dependency one-directional — the manager statically
knows about creatures, creatures reach back dynamically (untyped) on the
think tick, where dynamic dispatch costs nothing measurable at ~3 calls per
second per creature.

A second, smaller one, also only visible in a real run: the manager originally
populated inline in `_ready()`, so `creature_spawned` was emitted 19 times to
nobody — a parent's `_ready()` runs *after* its children's. Now deferred.

---

## Scoped out (deliberately not done)

- **No flight.** The snagbill walks and hops; it never leaves the ground.
  Real flight means 3D pathing, a separate airborne movement mode, and takeoff
  /landing transitions — more per-frame work on the exact hardware that cannot
  afford it, for a creature usually seen from 300 m up.
- **No skeletal animation and no procedural gait.** The bodies are rigid.
  Legs do not move; a fleeing rimefleece slides. This matches every other
  actor in this project (`villager.gd`'s own doc says "purely visual — capsule
  tilt/scale, no skeletal animation in this pass") and is stated plainly
  rather than implied. The one pose change that exists is a dead animal
  tipping over, which reuses `villager.gd`'s `COLLAPSED` capsule-tilt trick.
- **No MultiMesh batching.** See "The one lever this package leaves on the
  table" — real, understood, deliberately deferred with its cost stated.
- **Wildlife does not interact with villagers, the economy, or Faith.**
  A thawjaw will not eat a villager; a rimefleece is not a food resource;
  killing one does not move Naklon. Predation here is nature, not the player's
  cruelty, and coding it as a Naklon shift would have been a design claim this
  package has no standing to make. All three would be one-liners against
  existing APIs (`Villager`, `VillageEconomy`, `Naklon.shift`) once somebody
  owns that design decision — but they are *other packages'* files, and
  `docs/systems/OWNERSHIP.md` is explicit about not editing across lanes.
- **The Hand cannot pick an animal up.** `hand.gd` grabs `RigidBody3D`s;
  these are `CharacterBody3D`s, like villagers, which the Hand also cannot
  pick up. Consistent with the existing system, not a new limitation.
- **No Voices lines.** `report_alarm()` and `report_kill()` fire
  `Voices.react(&"wildlife_scattered")` and `Voices.react(&"wildlife_kill")`
  with real context dictionaries, and the alarm one is throttled to once per
  12 s so a scattering herd cannot make the advisors gabble. **No lines exist
  for either trigger yet** — `systems/voices/voice_lines.gd` is package M's
  file and this package may not edit it. `Voices.react()` no-ops cleanly on an
  unknown trigger (`pick_pair` returns `[]` for a missing key, verified by
  reading it), so these are live hooks waiting for content, not a feature
  being claimed. Package M can add `&"wildlife_scattered"` and
  `&"wildlife_kill"` whenever it likes and they will speak immediately.
- **No population dynamics.** Animals do not breed. `respawn_prey` is a flat
  timer that walks one grazer back in from the coast every 90 s up to the
  original count — it is repopulation, not a predator/prey equilibrium model.
  Predators never respawn: an island that loses its thawjaw has lost it.
- **No persistence.** Nothing saves, matching the rest of the project's
  current lack of a save system (`docs/systems/weather.md` records the same).
- **No day/night behaviour, no weather reaction.** `Weather.current` is real
  and live and nothing here reads it. A storm does not make animals huddle.
  That would be a genuinely nice, genuinely cheap follow-up (one signal
  connection, one multiplier on `graze_seconds`) and is left as a named
  opportunity rather than half-built.
- **No real frame-rate measurement.** There is no GPU in this sandbox, of any
  kind. Every CPU-side number in this document was measured headlessly and is
  labelled as such; no frame rate is claimed anywhere, because none could be
  taken.

## Assets used

**None.** Every mesh is a Godot primitive (`CapsuleMesh`, `SphereMesh`,
`BoxMesh`, `CylinderMesh`) built in code and merged at runtime; every material
is a `StandardMaterial3D` built in code from two `Color`s in a `.tres`.
Nothing was downloaded, imported, or derived from any third-party source, so
there is nothing for this package to add to `CREDITS.md`.
