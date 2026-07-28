# The Hand (package E)

The player has no cursor. The Hand *is* the cursor — a stylized god's hand
that follows the mouse through the world with real lag and weight, and is
the only way the player ever touches anything directly (grabbing, and by
extension carrying and throwing; sigil casting and rites are other
packages' concern but gate on the same Reach API and can reuse the Hand's
visible-refusal language — see "Integration" below).

## Files

- `actors/hand/hand.gd` — the Hand actor script (`class_name Hand`,
  extends `Node3D`). Everything: targeting, spring motion, grip/grab/
  carry/throw, Reach gating, Naklon-reactive material, procedural model
  construction.
- `actors/hand/hand.tscn` — a one-node scene (`Node3D` + the script). The
  entire visual hierarchy (palm, wrist, 5 fingers, grab zone, held socket,
  particle trail) is built in code in `_ready()` rather than hand-authored
  in the `.tscn`, deliberately — see "Why procedural, not hand-authored"
  below.
- `actors/hand/hand_material.gdshader` — the Naklon/grip/refusal-reactive
  spatial shader shared by every mesh piece of the hand.
- `actors/hand/hand_demo.tscn` + `hand_demo.gd` — standalone testable
  scene: ground, two `RigidBody3D` props (a box and a ball), a camera, an
  instanced Hand, and an on-screen status/feed readout. Registers one demo
  `Village` so `Reach.can_act_at()` has something to say yes to (see
  "Reach gating" below for why that registration is necessary at all).

## Why procedural, not hand-authored

No licensed hand mesh/rig was available, and the brief explicitly allows
either a `Skeleton3D` + skinned mesh or "a clean CSG/primitive composition
if a full skeleton is overkill for this pass." I chose the latter:

- **Chosen**: palm + wrist as single primitives, each of the 5 fingers as
  a 2-joint chain of independent `Node3D` pivots each holding a
  `CapsuleMesh` `MeshInstance3D` (an "articulated puppet" — like stop-motion
  armature pieces, not a skinned surface). Curl is applied by rotating
  each joint's `Node3D.rotation.x` directly, no bone/skin weights at all.
  - *Pro*: zero skinning math to get right without being able to render
    and eyeball it (this sandbox has no GPU — see `docs/rendering.md` —
    and I was not permitted to invoke `godot` myself per the task rules,
    so I could not iteratively screenshot-check a skin weight gradient).
    Trivially cheap (11 mesh instances total). Trivially correct to reason
    about by hand: I derived the curl rotation's sign from the standard
    right-hand rotation-around-X matrix rather than guessing (see the
    comment above `_build_hand_model()` in `hand.gd`), so the mechanical
    behavior (0 = open flat, 1 = closed fist, monotonic in between) is a
    property I can actually verify without rendering, even though the
    *exact* silhouette/proportions were not screenshot-verified by me.
  - *Con*: visible hard seams at every joint (no smooth skin blend), and
    the thumb's resting orientation (rotated base transform) means its
    curl axis, while still mechanically correct relative to its own local
    frame, composes with Godot's YXZ Euler order in a way I could not
    visually confirm looks like a natural thumb curl rather than merely
    "correct in principle." **This is the one place in this package where
    I'm flagging an unverified visual claim explicitly rather than
    asserting it** — a follow-up pass with an actual render (the
    orchestrator's post-integration screenshot pass, per
    `docs/rendering.md`) should sanity-check the thumb silhouette and
    retune `hand.gd`'s `finger_defs`/thumb `rot` value if it reads wrong.
- **Not chosen**: `Skeleton3D` + one skinned `MeshInstance3D`. Would look
  smoother (no joint seams) but requires either hand-writing bone
  transforms *and* per-vertex skin weights on a mesh I'd also have to
  build by hand with no visual feedback loop, or spending the pass's
  budget on tooling to generate that instead of on the actual behavior
  (spring motion, grab/throw, Reach gating) the brief cares about most.

## Motion: damped spring, not a teleport

`_integrate_spring()` in `hand.gd` runs a literal spring-damper each
`_physics_process`:

```
accel = (target - position) * spring_stiffness - velocity * spring_damping
velocity += accel * delta
position += velocity * delta
```

`spring_stiffness = 90`, `spring_damping = 14`. Critical damping for that
stiffness is `2*sqrt(90) ≈ 18.97`; running under that on purpose means the
hand slightly overshoots and settles rather than creeping in dead-flat —
it reads as something with real inertia arriving, not a cursor snapping to
a point. Both are `@export`ed for retuning without touching the script.

Finger curl (`_grip`) is smoothed separately and much faster
(`grip_response = 9`, simple exponential approach, not a spring — a fist
closing doesn't need to overshoot) so grabbing feels responsive even while
the palm is still catching up to the mouse.

## Targeting

By default (`use_own_mouse_raycast = true`) the Hand raycasts from
whatever `Camera3D` is current in the viewport (auto-detected via
`get_viewport().get_camera_3d()`, or explicitly via the `camera_path`
export) through the mouse position, against physics bodies; if nothing is
hit (looking at open sky) it falls back to intersecting a horizontal plane
at `hover_height`. This means dropping `hand.tscn` into any scene with a
current camera and *something* with collision (ground, props, terrain)
makes it work with zero wiring.

For integration into `world/god_view.tscn`'s `GodCamera` (or a future
camera rig), a controller can instead set `use_own_mouse_raycast = false`
and drive the Hand every frame via the public `set_target_position(pos:
Vector3)` — e.g. if a future camera-relative aiming scheme needs to differ
from a raw screen-to-world raycast.

## Grabbing, carrying, throwing

- **Grab** (`_try_grab` → `_do_grab`, triggered on `hand_grip` just-pressed,
  reusing the input action already defined in `project.godot` — no new
  input action invented): finds the nearest body overlapping a small
  `Area3D` ("GrabZone", a sphere, radius `grab_radius = 0.4m`, positioned
  just under/in front of the palm) that is either a `RigidBody3D` or in
  the `&"grabbable"` group (so non-rigid `Node3D` actors, e.g. a future
  villager controller, can opt in without being a physics body). Chosen
  carry mechanism: **freeze + reparent**, not a `Generic6DOFJoint3D`.
  The body's `freeze = true` (`freeze_mode = FREEZE_MODE_KINEMATIC`), then
  it's reparented under the Hand's `HeldSocket` node and **snapped** to
  that socket's local origin (`Transform3D.IDENTITY`) — it does not
  preserve the exact point/offset it was grabbed at. A frozen `RigidBody3D`
  still has its global transform driven by the scene tree each frame (Godot
  syncs kinematic/frozen bodies' transforms *to* the physics server, not
  the reverse), so it reliably follows the hand's spring motion with zero
  jitter. A `Generic6DOFJoint3D` would keep the body live in the physics
  simulation (nicer collision response while held, could react to bumping
  other objects) but is much more prone to fighting/jittering against a
  moving, damped-spring-driven parent body, and was judged not worth the
  tuning budget for this pass — documented here as a deliberate choice,
  not an oversight.
- **Carry**: automatic — once a body is a child of `HeldSocket` with an
  identity local transform, it inherits the Hand's `global_transform` for
  free every frame; no per-frame carry code needed.
- **Throw** (`_release_held`, triggered on `hand_grip` just-released): the
  body is reparented back to whatever parent it came from (falling back to
  `get_tree().current_scene` if that parent no longer exists), its world
  transform is preserved across the reparent (captured before, reapplied
  after), `freeze` is cleared, and `linear_velocity` is set to the Hand's
  own current spring velocity (`get_hand_velocity()`) × `throw_impulse_multiplier`
  — literally "the hand's recent velocity imparted as impulse," per the
  brief. A small amount of `angular_velocity` (`velocity.cross(Vector3.UP)
  * throw_spin_factor`) is added purely for throw-arc visual flair.

## Reach gating — visible refusal, not silent failure

`can_act_here()` wraps `Reach.can_act_at(global_position)` (the Hand's own
current world position — i.e. where the "touch" actually happens, not the
raw unclamped mouse-raycast target). This is checked:

1. **Continuously**, every physics frame: `_out_of_reach_amount` smoothly
   ramps to 1 whenever the Hand is outside all villages' Reach radii, and
   feeds the shader's `out_of_reach` uniform, which desaturates the hand's
   skin toward grey, dims it, and boosts roughness — a constant, ambient
   "this doesn't work here" cue, not just a reaction to clicking.
2. **On grab attempts**: outside Reach, fingers are capped at 18% closure
   (`effective_grip_target = min(grip_target, 0.18)` in
   `_physics_process`) even while the grip button is held — the hand
   visibly *can't* close into a fist — and no grab is attempted at all
   (`_try_grab` returns early). A sharp decaying red `refusal` flash
   (`request_refusal_flash`) fires alongside an `action_refused(reason,
   world_pos)` signal.

Important operational note: `Reach.can_act_at()` iterates
`GameState.villages` and returns `false` for every position if that
dictionary is empty (see `systems/faith/reach.gd`) — with **zero**
villages registered, the Hand can never grab anything, anywhere. This
isn't a bug in the Hand; it's `Reach`'s actual contract (no converts yet =
no reach anywhere). `hand_demo.tscn`/`hand_demo.gd` registers one small
`Village` (`&"demo_hearth"`, population 10, faith_fraction 0.4 → reach
radius ≈ 10.4m) purely so the demo scene has *some* in-reach area to
demonstrate grabbing in, plus enough out-of-reach ground (a 30×30m plane)
to also demonstrate the refusal behavior in the same scene.

### Integration point for other packages (documented per the brief)

`can_act_here() -> bool` and `request_refusal_flash(reason: StringName =
&"generic_out_of_reach") -> void` are public specifically so package F
(sigil casting) or any other Reach-gated action can reuse the *same*
visible refusal language (desaturation + flash + `action_refused` signal)
the Hand uses for grabbing, instead of inventing a second "no" cue. F is
not required to use this — it can call `Reach.can_act_at()` itself and
handle refusal its own way — but if it wants visual consistency with the
Hand, calling `hand_instance.request_refusal_flash(&"sigil_out_of_reach")`
when its own `Reach.can_act_at()` check fails gets it for free.

## Naklon reactivity

`hand.gd` reads `Naklon.unit()` directly every physics frame (in
`_update_material()` and `_update_trail()`) and feeds it to:

- `hand_material.gdshader`'s `naklon_unit` uniform, which lerps the skin's
  albedo between `mercy_color` (pale cool white/blue) and `cruelty_color`
  (dark red) and does the same for an emission tint, on top of (and
  independent from) the `out_of_reach`/`refusal` cues described above.
- A `GPUParticles3D` trail's `ParticleProcessMaterial.color`, lerped the
  same way — small glowing motes (world-space, so they leave a genuine
  trail behind hand motion, `local_coords = false`) that shift from pale
  to blood-red as the player leans toward Cruelty.

**Why direct `Naklon.unit()` and not package D's global shader uniform**:
at the time this package was built, `shaders/` and `materials/` (package
D's directories) were both still empty — no global uniform existed yet to
read. Reading `Naklon.unit()` directly is also how `Naklon`'s own docstring
suggests it be consumed ("Convenience for shader/material lerps"). If
package D's global uniform lands later, `hand_material.gdshader` can be
switched from its own `naklon_unit` uniform parameter to
`global_uniform_naklon_unit` (or whatever D names it) in one line — this
is a documented, not-yet-done follow-up, not a silent gap.

## Public API summary

```gdscript
signal grabbed(node: Node3D)
signal released(node: Node3D, velocity: Vector3)
signal action_refused(reason: StringName, world_pos: Vector3)

func is_holding() -> bool
func get_held() -> Node3D
func get_target_position() -> Vector3
func get_hand_velocity() -> Vector3
func set_target_position(pos: Vector3) -> void   # for external target control
func can_act_here() -> bool                       # wraps Reach.can_act_at(global_position)
func request_refusal_flash(reason: StringName = &"generic_out_of_reach") -> void
```

## Voices triggers fired here (for package M)

Documented per the brief's requirement that trigger names be spelled out
for whoever writes the actual line pools:

- `&"hand_grabbed_object"` — context: `{"node_name": StringName}`. Fired
  the instant a grab succeeds.
- `&"hand_threw_object"` — context: `{"node_name": StringName, "speed":
  float}` (throw speed in m/s). Fired on release.

`action_refused` is a **signal**, not a `Voices.react()` call — I left the
decision of whether/how "you can't act here" should get a spoken line to
whichever package owns the Sanctum/Reach commentary layer, since firing a
voice line on every single failed grab attempt near a border risked being
extremely noisy without tuning I didn't have the scope to do here. This is
a deliberate scope line, not an oversight: wiring `action_refused` to
`Voices.react(&"hand_reach_refused", {"reason": reason})` (with some
debounce) is a one-line follow-up for whichever package wants it.

## Scoped out

- **Exact grab-point offset**: grabbed objects snap to a fixed
  hand-relative socket rather than preserving the precise position/
  orientation they were grabbed at. A real "pinch where you clicked"
  feel would need per-contact-point tracking; not implemented this pass.
- **Held-object collision while carried**: frozen bodies don't push other
  physics objects out of the way while being carried (a `Generic6DOFJoint3D`
  approach would allow this at the cost of stability — see above).
- **Losing grip on an object mid-carry if the Hand itself leaves Reach**:
  only the *initial* grab is Reach-gated. Once held, an object stays held
  regardless of where the Hand travels. This was a deliberate design
  read (a god's hand doesn't drop what it's already holding just because
  it wandered past a village border) rather than an oversight, but it's
  worth flagging as a rule a future balance pass might want to revisit.
- **Two-handed / multi-object holding**: the Hand holds at most one thing
  at a time (`_held` is a single reference, not a list).
  `Skeleton3D`-based skinning / smooth joint blending: see "Why
  procedural, not hand-authored" above.
- **Visual/aesthetic screenshot verification of the model's proportions
  and thumb curl silhouette**: not possible for me to do — this task
  explicitly forbids invoking the `godot` binary directly (concurrent
  packages were writing files at the same time), and this sandbox has no
  GPU regardless (`docs/rendering.md`). The mechanical correctness of the
  curl (monotonic, correctly signed per the rotation math) was verified
  by hand; the aesthetic result was not. Flagged explicitly rather than
  asserted as verified.
- **Collision layer/mask scheme**: `GrabZone` and the demo props use
  Godot's default collision layer/mask (1/1). Whichever package
  eventually defines the game's real collision layer scheme (villagers,
  terrain, props, water) may need to update `grab_radius`'s `Area3D` mask
  in `hand.gd`'s `_build_hand_model()` accordingly — flagged here so
  that's a one-line change, not a rediscovery.

### Assets used

None. Every visual element (hand meshes, material, particle trail) is
generated procedurally from Godot primitives (`BoxMesh`, `CapsuleMesh`,
`SphereMesh`) and a hand-written `.gdshader` — no external texture, HDRI,
model, or audio asset was needed or downloaded for this package.
