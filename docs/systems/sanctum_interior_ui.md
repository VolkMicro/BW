# Package T — Sanctum interior dressing, camera rig, diegetic interaction

## What this is

Three real, working pieces that sit on top of package I's finished Sanctum
(`world/sanctum/`, read but never edited here):

1. **`world/sanctum_interior/interior_dressing.gd`/`.tscn`** — a small stone
   idol on a pedestal (procedural CSG, no downloaded assets), instanced
   under a Sanctum's `InteriorAnchor` exactly where `docs/systems/sanctum.md`
   invites it ("parent altar/idol/interior-dressing scenes here"). It
   re-tints per the owning village's culture using package I's own
   mechanism, and its glow reacts live to both `Naklon` and the Sanctum's
   hp.
2. **`ui/camera_rig.gd`/`.tscn`** — one real `Camera3D` plus a `Tween`-driven
   transition helper that cuts or eases between a god-view framing, a
   Sanctum-interior framing (with real, clamped WASD/arrow-key walking),
   and a duel-arena framing, all inside one running scene — no
   `change_scene_to_file()` anywhere, matching `core/game_state.gd`'s own
   stated constraint that god-view/Sanctum-interior/duel-arena never need a
   loading screen because everything already agrees on `GameState`.
3. **`ui/sanctum_interaction.gd`/`.tscn`** — the diegetic interaction layer:
   proximity to the *existing* altar trigger and this package's own new
   interior repair point drives two `Label3D` prompts (no Control-node HUD
   panel) and one keypress. Approaching the altar shows live
   devotion/faith_fraction/relics; approaching the idol's repair point and
   pressing Enter attempts a real repair, genuinely refused/greyed while
   offering-debt is active.

`world/sanctum_interior/sanctum_interior_demo.tscn` +
`sanctum_interior_demo.gd` wire all of the above around one real, freshly
registered `Village` (Sankiln — deliberately not the same culture as
package I's own Fenrayt demo, to prove the re-skin isn't hard-coded) and a
real instanced `Sanctum`, following the same standalone-demo shape as
`world/sanctum/sanctum_demo.tscn` / `systems/economy/economy_demo.tscn` /
`world/ocean/ocean_demo.tscn`. Run:

```
godot --path . world/sanctum_interior/sanctum_interior_demo.tscn
```

Nothing here is a stub: every interaction calls the real Sanctum public API
(`world/sanctum/sanctum.gd`), never re-derives hp/mercy/culture state, and
the camera transitions are real running `Tween`s.

## Files

| File | What it is |
|---|---|
| `world/sanctum_interior/interior_dressing.gd` | `class_name InteriorDressing extends Node3D`. Culture-skinned, Naklon/hp-reactive idol + a `RepairPoint` Area3D + `attempt_repair()`/`can_repair()` forwarding to the real `Sanctum`. |
| `world/sanctum_interior/interior_dressing.tscn` | Pedestal (`CSGCylinder3D`) + idol column (`CSGCylinder3D`) + idol head (`CSGSphere3D`), all procedural, plus the `RepairPoint` `Area3D`. |
| `world/sanctum_interior/sanctum_interior_demo.gd` | Standalone demo bootstrap: registers one real Sankiln `Village`, seeds `GameState.relics_held`, and wires number-key camera cuts + test hooks for damage/repair-lock. |
| `world/sanctum_interior/sanctum_interior_demo.tscn` | `WorldEnvironment` + `Sun` + `Ground` + one instanced `Sanctum` (with `InteriorDressing` parented under its `InteriorAnchor`) + `CameraRig` + `SanctumInteraction` + a `Marker3D` god-view shot + a `Marker3D` duel-focus stand-in. |
| `ui/camera_rig.gd` | `class_name CameraRig extends Node3D`. One `Camera3D`, `cut_to()`/`transition_to()`, three `frame_*` convenience wrappers, and the interior walk/clamp logic. |
| `ui/camera_rig.tscn` | `CameraRig` + child `Camera3D` + child `PlayerProxy` (`AnimatableBody3D`) — see "The proxy-body trick" below. |
| `ui/sanctum_interaction.gd` | `class_name SanctumInteraction extends Node3D`. Proximity → prompt-label wiring for the altar readout and the repair point. |
| `ui/sanctum_interaction.tscn` | `SanctumInteraction` + two `Label3D` prompt children. |

## Interior dressing

### Attachment point

`InteriorDressing` is instanced as a child of `Sanctum/InteriorAnchor`
(`world/sanctum/sanctum.gd:38`, `Marker3D` at Sanctum-local `(0, 0.6,
-1.5)`) — see `sanctum_interior_demo.tscn:49`,
`[node name="InteriorDressing" parent="Sanctum/InteriorAnchor"
instance=ExtResource("4")]`, exactly the hookup `docs/systems/sanctum.md`
("For package T") describes. Its own `@export var sanctum_path: NodePath =
NodePath("../..")` default walks back up to the `Sanctum` root from that
attachment point without needing to be told where it is.

### Culture skin — same mechanism as package I, not a second one

`Sanctum._duplicate_materials()` / `_apply_culture_skin()`
(`world/sanctum/sanctum.gd:85-131`) duplicate template materials once per
instance and re-tint from `GameState.cultures[village.culture_id]
.color_primary`/`.color_accent`, falling back to the template's shipped
color if the village/culture isn't registered yet, re-applied on
`GameState.village_registered`. `InteriorDressing._duplicate_materials()` /
`_apply_culture_skin()` (`interior_dressing.gd:99-125`) do exactly the same
three things in the same order, reading through the owning `Sanctum`'s own
`village_id` (`_get_village()`/`_get_culture()`, `interior_dressing.gd:106-
115`) rather than taking a second `village_id` export — one source of
truth for "which village is this."

### Naklon + hp reactive glow

`_refresh_glow()` (`interior_dressing.gd:148-153`) does two independent
things every time it's called:

- lerps the idol's emission color between `MERCY_COLOR` and
  `CRUELTY_COLOR` by `Naklon.unit()` (`core/naklon.gd:52-53`), called from
  `_on_naklon_changed()` which is wired to `Naklon.naklon_changed` directly
  — live, no polling.
- scales the emission *energy* by `lerpf(MIN_GLOW_FRACTION, 1.0,
  hp_fraction)`, where `hp_fraction` is only ever updated from
  `Sanctum.sanctum_damaged`/`sanctum_repaired`/`sanctum_destroyed`
  (`interior_dressing.gd:136-146`) — never re-read from
  `GameState.villages` directly. This mirrors
  `Sanctum._refresh_visual_from_hp()`'s scorch-mix idea
  (`world/sanctum/sanctum.gd:273-277`, `MAX_SCORCH_MIX = 0.75`, never fully
  black): the idol dims toward `MIN_GLOW_FRACTION` (0.15) as the building
  takes damage, but never goes fully dark — "an idol nobody's tending," not
  a blackout.

**Why a plain `StandardMaterial3D` + direct signal listening, not
`shaders/naklon_shader_driver.gd`'s global-shader-uniform:** that driver
exists so *shader*-side consumers can react to `Naklon.unit()` without
per-material wiring, but a `.gdshader`/material resource is package D's
territory (`shaders/`, `materials/` per `docs/systems/OWNERSHIP.md`), which
this package doesn't touch. A per-instance script-side material lerp is
simpler here and is exactly the pattern `sanctum.gd` already uses for its
own altar glow (`_refresh_altar_glow()`, `sanctum.gd:279-287`) — mirroring
the sibling package's own choice rather than introducing a second
mechanism.

### Simplification

The idol's head (`CSGSphere3D`) has no collision (`use_collision` left at
its default `false`) — decorative only, the same simplification package I
made for the standing stones (`docs/systems/sanctum.md` "Scoped out").

## Camera rig (`ui/camera_rig.gd`)

`CameraRig` owns exactly one `Camera3D` and exposes:

- `cut_to(xform, mode)` — instant snap, no tween.
- `transition_to(xform, mode, duration)` — a real, running
  `create_tween().tween_property(camera, "global_transform", xform,
  duration)`, cubic ease-in-out. Godot 4 interpolates `Transform3D`
  properties directly (origin + basis), so this is a genuine interpolated
  move+look, not a hand-rolled approximation.
- `frame_god_view(xform, ...)` — plays whatever transform the caller
  supplies (e.g. copied from `world/god_view.tscn`'s own `GodCamera`); this
  rig never instances or depends on `world/god_view.tscn` itself.
- `frame_sanctum_interior(sanctum: Node3D, ...)` — reads the real
  `InteriorAnchor`/`EntranceMarker` child nodes off whatever is passed
  (`world/sanctum/sanctum.tscn:134-138`) to compute a just-inside-the-
  doorway eye position looking at the anchor, and sets the walk-clamp
  reference to that same node.
- `frame_duel_arena_focus(focus: Node3D, distance, height, ...)` —
  deliberately generic: backs the camera off any `Node3D`'s
  `global_position` and looks back at it. See "Scoped out" for why this
  doesn't call into `actors/avatar/combat/` directly.

`mode_changed`/`transition_started`/`transition_finished` signals let any
future consumer (audio, environment grading) react to which framing is
live without polling.

### Deliberately generic

`CameraRig` never types against `Sanctum` or any duel-arena class — the
three `frame_*` wrappers duck-type by child-node **name**
(`InteriorAnchor`/`EntranceMarker`) or just read `global_position` off a
plain `Node3D`. This is what makes `frame_duel_arena_focus` safe to call
whether or not `actors/avatar/combat/` (package L) happens to be instanced
in the current scene.

### God-view free camera (pan/zoom/orbit)

`frame_god_view(xform, ...)` no longer just plays a one-off transform and
leaves the camera parked there — it seeds a real orbit-camera state
(`_derive_orbit_from_xform()`: intersects the given transform's forward ray
with the sea-level plane to find a ground focus point, then reads off
distance/yaw/pitch from that) and, once any transition finishes, hands
control to `_process_god_view_free_camera()` every physics frame:

- **Pan** — the same `ui_up`/`ui_down`/`ui_left`/`ui_right` arrow actions
  the interior-walk mode already uses (mode-gated, so no conflict), moving
  the orbit's focus point across the ground plane, relative to current yaw
  so "up" always means "further into the screen."
- **Zoom** — mouse wheel, clamped between `god_min_distance`/
  `god_max_distance`.
- **Orbit** — hold the **middle** mouse button and drag; yaw/pitch update
  from mouse motion, pitch clamped (`god_min_pitch_deg`/`god_max_pitch_deg`)
  so it can't flip to looking level or straight down. Deliberately the
  middle button, not left/right — `actors/hand/hand.gd` (grab) and
  `systems/sigils/sigil_caster.gd` (draw a sigil) already own those, and
  middle-drag was free, so no cross-file input-priority change was needed
  anywhere else to add this.

This only runs in `MODE_GOD_VIEW`, and is suspended while an eased
`transition_to()` tween is still in flight (checked via `_tween.is_valid()`)
so the two don't fight over `camera.global_transform` on the same frame —
free control picks up the instant the transition finishes, from wherever it
landed. `frame_sanctum_interior()`/`frame_duel_arena_focus()` are
unaffected; they still play a fixed framing exactly as before.

### Interior walking + the clamp

While `mode == MODE_SANCTUM_INTERIOR`, `_physics_process()` reads
`ui_up`/`ui_down`/`ui_left`/`ui_right` — Godot's **built-in default** UI
actions (arrow keys), deliberately **not** a new custom `InputMap` action,
since `project.godot` is foundation-owned per `docs/systems/OWNERSHIP.md`
and package T may not edit it — and moves the camera along its own basis,
clamped in the Sanctum's own local space
(`_clamp_to_interior()`, `camera_rig.gd:93-99`) to the ~6.2m×6.2m interior
square and the floor/ceiling band `docs/systems/sanctum.md` documents
("floor height y≈0.6 local-y, ceiling ≈1.9m above that").

### The proxy-body trick

Sanctum's `OfferingTrigger` and this package's own `RepairPoint` are both
`Area3D`s that fire `body_entered`/`body_exited` for a real
`PhysicsBody3D` — not for an arbitrary `Node3D` like a bare `Camera3D`.
`CameraRig` has no player-character body of its own, so it carries a small
`PlayerProxy` (`AnimatableBody3D` — the node type Godot intends for a
collider moved by script rather than by the physics engine), glued to
`camera.global_position` every `_physics_process()` tick
(`camera_rig.gd:70-73`). It has no gameplay meaning beyond making the two
real trigger areas fire correctly; `sync_to_physics = true` is set
explicitly on it in `camera_rig.tscn`.

## Diegetic interaction (`ui/sanctum_interaction.gd`)

No Control-node HUD panel anywhere. Two interactables:

- **The altar** — proximity comes from `Sanctum.offering_area_entered`/
  `offering_area_exited` (`world/sanctum/sanctum.gd:144-148`), the
  *existing* `WorshipYard/Altar/OfferingTrigger` `Area3D` other systems
  already use to detect "something is standing at the altar." This
  package adds no collision shape of its own here. While in range, the
  `AltarPromptLabel` (`Label3D`) shows `village.display_name`,
  `Village.devotion`, `Village.faith_fraction`, and
  `GameState.relics_held.size()` — read straight from `core/game_state.gd`,
  never a second copy of that state (`sanctum_interaction.gd:101-110`).
- **The repair point** — `InteriorDressing.repair_area_entered`/
  `repair_area_exited`, this package's own interior-only `Area3D`, since
  Sanctum's hollow interior box ships with no fixtures at all
  (`docs/systems/sanctum.md` "For package T"). While in range, the
  `RepairPromptLabel` reads `Sanctum.can_repair()` every frame
  (`sanctum_interaction.gd:112-123`) to decide whether to show "Press
  Enter: repair the Sanctum (hp N%)" in white, or grey out
  (`Color(0.55, 0.55, 0.55, 1.0)`) and show "Repair refused — {debt_name}
  (Ns remaining)" using `Sacrifice.taboo_name_for()` /
  `Sacrifice.offering_debt_seconds_remaining()`
  (`world/sanctum/sacrifice.gd`) — exactly the culturally-correct debt name,
  never a generic label. This is the literal ask in `docs/systems/sanctum.md`:
  *"package T's UI [should] grey out a repair action instead of letting
  the click silently no-op."*

Pressing `ui_accept` (Enter/Space/Kp Enter — again a **built-in** default
action, not a new one) while at the repair point calls
`InteriorDressing.attempt_repair()`, which **always** calls the real
`Sanctum.repair()` — so Sanctum's own `mercy_blocked`/`sanctum_repaired`
signals and its `Voices.react()` call fire for real regardless of outcome.
This script never reimplements the offering-debt lock; it only reads
`can_repair()` to decide what to show *before* the player commits.

`SanctumInteraction` also listens directly to
`sanctum_damaged`/`sanctum_repaired`/`sanctum_destroyed`/`mercy_blocked`
so both labels refresh immediately on a real state change even if it
happened for a reason unrelated to the player currently standing there
(e.g. the demo's `R`/`T` test hooks, or eventually Louhi/combat damage).

## The demo, end to end

`sanctum_interior_demo.gd` registers a Sankiln village (population 30,
faith_fraction 0.6, sanctum_hp 80/100), seeds one relic into
`GameState.relics_held`, and starts in a god-view framing. Keys:

| Key | Effect |
|---|---|
| `1` | `frame_god_view()` — back to the overview shot |
| `2` | `frame_sanctum_interior(sanctum)` — transitions inside; arrow keys walk, clamped |
| `3` | `frame_duel_arena_focus(duel_focus)` — a bare `Marker3D` stand-in, see "Scoped out" |
| Enter | interact at whichever prompt is currently showing |
| `R` | `sanctum.apply_damage(20.0)` — test hook so hp-reactive dimming is reachable without a live combat/Louhi package wired in |
| `T` | `sanctum.try_offer(null)` — test hook: a real `Sacrifice.offer()` call (generic/object target) that locks the mercy path for 180s exactly like the real mechanic, so the greyed-out repair prompt is provably real |

## Voices / GameState integration

This package fires no new `Voices.react()` triggers of its own — every
Voices reaction along this whole path (`sanctum_damaged`,
`sanctum_destroyed`, `mercy_blocked_by_debt`, `offering_taboo`,
`offering_out_of_reach`) already comes from `Sanctum`/`Sacrifice`
themselves, which this package calls into rather than duplicates.
`GameState.villages`/`.relics_held`/`.cultures` are read, never written,
except for the demo's own `register_village()`/`relics_held.append()` calls
(exactly as package I's and H's own demos seed their test state).

## Public API surface

**`InteriorDressing` (`world/sanctum_interior/interior_dressing.gd`)**
- `can_repair() -> bool`, `attempt_repair() -> bool`
- Signals: `repair_area_entered(body)`, `repair_area_exited(body)`,
  `repair_attempted(village_id, success, reason)`

**`CameraRig` (`ui/camera_rig.gd`)**
- `cut_to(xform, mode)`, `transition_to(xform, mode, duration)`
- `frame_god_view(xform, instant, duration)`
- `frame_sanctum_interior(sanctum: Node3D, instant, duration)`
- `frame_duel_arena_focus(focus: Node3D, distance, height, instant, duration)`
- Signals: `mode_changed(old_mode, new_mode)`, `transition_started(mode)`,
  `transition_finished(mode)`

**`SanctumInteraction` (`ui/sanctum_interaction.gd`)** — no public methods
beyond `@export`ed `sanctum_path`/`interior_dressing_path`; it's a wiring
node, not a library.

## Scoped out

- **No mouse-look.** Interior walking is arrow-key strafe/forward-back
  only, at a fixed orientation set by the last camera cut. A full FPS-style
  look controller (captured mouse, pitch/yaw) was judged out of scope for
  what this package needs to prove ("walking around the Sanctum interior
  IS the menu system") versus the risk of getting mouse-capture/UI-focus
  interactions wrong with no other package's input scheme to coordinate
  against yet.
- **No physical walk-through-the-door auto-transition.** Crossing from
  god-view to Sanctum-interior is a `CameraRig` API call (bound to a
  number key in the demo), not an automatic trigger fired by walking a
  player-character body through `EntranceMarker`'s vicinity. There is no
  player-character body anywhere in the codebase yet for that to attach
  to (`PlayerProxy` is a physics-detection shim, not a game-playable
  avatar) — whichever package eventually owns "the god's own physical
  presence," if any, is the natural caller of
  `CameraRig.frame_sanctum_interior()` on proximity, not something this
  package should guess the shape of.
- **No real dependency on `actors/avatar/combat/` (package L).** That
  directory turned out to already be built (`duel_arena.gd`,
  `avatar_combatant.gd`) by the time this package landed, and its
  `DuelArena` is a **per-scene `Node3D`** (`fighter_a_path`/`fighter_b_path`
  exported `NodePath`s, `autostart`), **not** an autoload or a
  `/root/DuelArena` singleton the way `actors/louhi/louhi_director.gd`'s own
  docs speculatively assumed when it was written before L existed. Flagged
  here since it's a fact this package discovered, useful for whichever
  integration pass wires Louhi's duel-challenge sign to a camera cut:
  `CameraRig.frame_duel_arena_focus()` takes any `Node3D`, so passing it
  the real `DuelArena` node (or one of its fighters) directly, once one is
  instanced in the same scene, needs no change on this package's side.
  This package's own demo instances a bare stand-in `Marker3D`
  (`DemoDuelFocus`) rather than depending on L's scenes, since L is not a
  declared dependency of package T (only `core/` and `world/sanctum/` are,
  per `docs/systems/OWNERSHIP.md`).
- **No scroll shelf / relic rack geometry.** The brief's "a relic rack, a
  scroll shelf" example furniture isn't built — the altar readout shows
  `GameState.relics_held.size()` as a number rather than a walkable rack
  of individual relic props, and there's no scroll-shelf interactable at
  all. This was cut to keep the vertical slice honest about what's real:
  one dressed idol + one repair point is a complete, working diegetic loop
  end to end; a rack/shelf would have been more geometry in the same style
  without adding a new *mechanic*. If `campaign/` (package S) lands a real
  quest log or relic/scroll list, the natural next step here is a second
  small interactable (a shelf `Area3D` + `Label3D`) reading
  `GameState.scrolls_known`/`.relics_held` by name rather than count —
  flagged as the likely next ask, not invented preemptively.
- **No sound.** No footstep audio, no ambient interior tone, no repair/
  offering stingers — `audio/` (package R) territory.
- **Repair amount is a flat, untuned constant.** `REPAIR_AMOUNT_PER_ATTEMPT
  = 15.0` per keypress, with no cooldown of its own beyond
  `ui_accept`'s natural one-press-per-edge behavior — not balanced against
  whatever real repair economy (cost in devotion/resources, if any) a
  later pass might want; currently a free, repeatable action whenever
  `can_repair()` is true. Flagged rather than silently guessed at, same
  spirit as `docs/systems/sanctum.md`'s own note on unbalanced devotion
  constants.
- **Camera transform interpolation quality is whatever Godot's built-in
  `Transform3D` `Tween` interpolation does** (origin lerp, basis
  slerp-equivalent) — not hand-tuned for a specific "cinematic" feel
  (overshoot, ease curves beyond `TRANS_CUBIC`/`EASE_IN_OUT`). Real and
  running, not bespoke.

## Assets used

None. `world/sanctum_interior/` is pure `CSGCylinder3D`/`CSGSphere3D`
primitives and `StandardMaterial3D` colors sourced from
`data/cultures/*.tres`, same as package I's own Sanctum building — no
textures, models, or audio were downloaded for this package. `ui/` is
pure code + `Label3D` (font is Godot's built-in default project font).
