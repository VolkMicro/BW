# Package K — The Avatar's real learning model

## What's here

- `actors/avatar/avatar.gd` — `class_name Avatar`, a `CharacterBody3D`. The
  shared brain + body for all three starting species: three Attachments
  (`attachment_watching`, `attachment_toothy`, `attachment_kind`, each a
  running scalar 0..1), a tag-keyed belief store (`beliefs: Dictionary`,
  `StringName -> float -1..1`), a context-tag stack other systems use to
  tell the Avatar what it's currently doing/considering, and a
  praise/chastise feedback loop wired to the `praise_avatar`/
  `chastise_avatar` input actions already defined in `project.godot`.
- `actors/avatar/species/avatar_species.gd` — `class_name AvatarSpecies`, a
  `Resource`. Pure tuning data (learning-rate baseline, starting
  Attachment seeds, stat/scale baselines, placeholder-mesh palette).
- `actors/avatar/species/otso.tres`, `krukk.tres`, `sarv.tres` — the three
  starting species (Otso the bear, Krukk the raven, Sarv the elk) as
  `AvatarSpecies` instances. One shared `avatar.gd` drives all three; the
  only per-species thing is which `.tres` gets assigned via
  `Avatar.set_species()`.
- `actors/avatar/avatar.tscn` — the shared scene: `CharacterBody3D` +
  `CollisionShape3D` + an empty `Body` `Node3D` (populated at runtime by
  `Avatar._build_placeholder_body()` with primitive meshes appropriate to
  whichever species is assigned) + a billboarded `Label3D` debug readout
  (mirrors `actors/villagers/villager.tscn`'s convention).
- `actors/avatar/avatar_demo.gd` + `avatar_demo.tscn` — a standalone,
  runnable demo: spawns one Avatar (Otso), pushes `Naklon` hard toward
  Cruelty, then runs a scripted sequence of `begin_context` /
  `receive_praise` / `receive_chastise` / `end_context` calls that trains
  the *opposite* way (chastises aggression, praises care), printing every
  belief and Attachment change to the Output panel and an on-screen log.
  Real player input (F/G) still works throughout on top of the script.

## The learning rule, exactly

Every context tag has a belief `beliefs[tag]` in `[-1, 1]`
("how desirable is doing this"), default `0.0` (neutral) for any tag not
yet seen. When `receive_praise()`/`receive_chastise()` fires while one or
more tags are active (`active_tags`, pushed by `begin_context(tag)` /
popped by `end_context(tag)`):

```
reward = +1.0 on praise, -1.0 on chastise
rate   = clamp(species.base_learning_rate * lerp(0.35, 1.85, attachment_watching), 0.02, 0.98)
beliefs[tag] = clamp(lerp(beliefs[tag], reward, rate), -1.0, 1.0)
```

This is the literal brief formula (`lerp(beliefs[tag], reward, learning_rate)`)
with `learning_rate` scaled by the avatar's *current* `attachment_watching`
— a high-Watching avatar's beliefs move fast and hard toward whatever it's
just been rewarded/punished for; a low-Watching one barely budges per
event, which is itself an emergent property since Watching also moves
every feedback event (see below), so an avatar that's *never* praised or
chastised stays a slow learner indefinitely, and one whose god engages with
it often becomes progressively more responsive to further feedback.

Every reinforced event ALSO nudges the Attachments themselves
(`_update_attachment_from_event`):

- Any feedback event at all: `attachment_watching += 0.015` (the avatar is
  learning *that* it's being taught, independent of what about).
- If the tag is registered in `TAG_AXIS` as `&"toothy"` (aggressive/
  self-interested acts: `eat_villager`, `attack_predator`, `hoard_food`,
  `intimidate_stranger`): `attachment_toothy += reward * 0.06`,
  `attachment_kind -= reward * 0.06 * 0.4` (loosely coupled opposite).
- If the tag is registered as `&"kind"` (caretaking acts: `carry_resource`,
  `guard_village`, `share_food`, `comfort_child`): the mirror image.
- If registered as `&"watching"` (curiosity acts: `approach_stranger`,
  `explore_new_place`): a smaller direct pull on `attachment_watching`.
- Any tag NOT in `TAG_AXIS` still gets a real belief update (it's fully
  usable by `get_belief`/`would_do`) but doesn't move any Attachment — a
  deliberate, documented extension point so other packages can invent new
  context tags without editing `avatar.gd`, at the cost of that tag having
  no Attachment coupling until someone adds it to `TAG_AXIS`.

**Feedback with no active context**: if `receive_praise()`/
`receive_chastise()` fires with `active_tags` empty, no belief is touched —
there is nothing to attribute the reward to, and faking an attribution
would make the model dishonest. `attachment_watching` still gets a quarter
of the "any feedback" nudge, since the avatar did notice its god trying to
say something.

## The belief-store schema (for Package L and N to query)

`beliefs: Dictionary` — `StringName` context tag → `float` in `[-1, 1]`.
Documented tags shipped in this pass (all pre-seeded to `0.0` in
`_seed_known_beliefs()` so the Dictionary is visibly complete in the
Inspector from frame one):

| Tag | Axis (`TAG_AXIS`) | Meaning |
|---|---|---|
| `eat_villager` | toothy | eating/killing a mortal |
| `attack_predator` | toothy | attacking a wild threat |
| `hoard_food` | toothy | keeping resources rather than sharing |
| `intimidate_stranger` | toothy | aggressive display at an unknown actor |
| `carry_resource` | kind | ferrying goods/food for a village |
| `guard_village` | kind | standing watch over a settlement |
| `share_food` | kind | giving food away |
| `comfort_child` | kind | gentle behavior toward the young |
| `approach_stranger` | watching | curious approach of something new |
| `explore_new_place` | watching | wandering into unmapped territory |

Any other `StringName` a calling system invents (e.g. a duel-specific tag
from Package L, or a Louhi-proximity tag from Package N) works immediately
through `get_belief`/`would_do`/`begin_context`/`end_context` with no
changes needed here; it simply won't move an Attachment unless it's later
added to `TAG_AXIS`. That list is intentionally the integration surface,
not a closed enum.

## Public API (what other systems call)

```gdscript
avatar.get_belief(tag: StringName) -> float          # -1..1, 0.0 if unseen
avatar.would_do(tag: StringName) -> bool             # samples action_probability(tag)
avatar.action_probability(tag: StringName) -> float  # 0.03..0.97, belief + attachment + noise
avatar.begin_context(tag: StringName) -> void
avatar.end_context(tag: StringName) -> void
avatar.is_context_active(tag: StringName) -> bool
avatar.clear_context() -> void
avatar.receive_praise() -> void                      # also fires on "praise_avatar" input
avatar.receive_chastise() -> void                    # also fires on "chastise_avatar" input
avatar.reinforce_belief(tag: StringName, delta: float) -> void  # environmental/outcome learning, no Attachment coupling
avatar.feed_devotion(amount: float) -> void           # growth input #2
avatar.set_species(s: AvatarSpecies) -> void
avatar.get_species_id() -> StringName
avatar.get_growth_stage() -> int
avatar.get_growth_stage_name() -> String              # "Cub"/"Juvenile"/"Grown"/"Huge"
avatar.get_effective_strength/speed/stamina() -> float # species base * current stage's stat_mult
avatar.get_effective_scale() -> float                  # species base_scale * current stage's scale_mult
avatar.get_growth_scalar(axis: StringName) -> float    # generic per-axis version for duck-typed bridges (e.g. Package L)
avatar.attachment_watching / attachment_toothy / attachment_kind  # @export, inspectable
avatar.beliefs                                          # @export Dictionary, inspectable
avatar.active_tags                                      # Array[StringName], inspectable
avatar.praise_count / chastise_count / devotion_fed      # inspectable growth inputs
```

Signals: `belief_updated(tag, old, new)`, `attachment_changed(axis, old,
new)`, `praised(active_tags)`, `chastised(active_tags)`, `grew(old_stage,
new_stage)`.

`Voices.react` triggers fired from this file (documented for Package M):
`avatar_praised`, `avatar_chastised`, `avatar_grew`, and
`avatar_surprised_expectation` (fired from `would_do` specifically when the
roll goes against a strong lean — see "What real surprise looks like"
below). Context passed: `tags`/`tag`, `species`, plus `stage`/
`probability`/`result` where relevant.

### How another system asks the Avatar something

```gdscript
# A hungry moment near a villager (some other package's script):
avatar.begin_context(&"eat_villager")
if avatar.would_do(&"eat_villager"):
	# ...resolve the bite; the belief is already accounting for whatever
	# this god has praised/punished in the past.
	pass
avatar.end_context(&"eat_villager")
```

`begin_context`/`end_context` bracket the *window* in which player
praise/chastise input should be attributed to that tag — a caller that
wants a decision without exposing a live feedback window can simply call
`would_do(tag)` without ever calling `begin_context` for it (no learning
happens from a bare query, only from an active-context + feedback event).

## Divergence from Naklon (required by the brief, load-bearing)

`attachment_watching`/`attachment_toothy`/`attachment_kind` are **never**
written from `Naklon.value` or `Naklon.unit()` anywhere in `avatar.gd` —
grep confirms zero references to `Naklon` in that file. They move *only*
from `_update_attachment_from_event`, which fires *only* from
`receive_praise()`/`receive_chastise()`. This means:

- A mercy-played god (`Naklon.value` strongly negative) who praises the
  Avatar every time it attacks something can still end up with a
  Toothy-high beast — Naklon says "I generally act with mercy," the beast
  says "my god keeps telling me biting things is good," and both are true
  and independently tracked at once.
- A cruelty-played god (`Naklon.value` strongly positive) who punishes
  every act of aggression ends up with a Toothy-low, Kind-high beast —
  exactly the brief's example, and exactly what `avatar_demo.tscn`
  demonstrates: it pushes `Naklon.shift(0.8, 1.0)` toward Cruelty *before*
  a single feedback event, then trains the Avatar the opposite way, and
  logs the final Attachments next to the final Naklon value so the
  divergence is directly visible in the Output panel / log label rather
  than asserted.

## What real surprise looks like in this model

Two independent sources of surprise, both real (not narrative dressing):

1. **Per-decision noise in `action_probability`.** Even a belief pinned at
   `+1.0` with `attachment_toothy` at `1.0` returns a probability capped at
   `0.97`, not `1.0` — and the noise term
   (`NOISE_BASE * (1.0 - attachment_watching * 0.7)`, `NOISE_BASE = 0.35`)
   is only ever *shrunk*, never eliminated, by high Watching. A
   thoroughly-trained beast can still, occasionally, not do the thing it
   was trained to do — or do the thing it was trained away from. Higher
   Watching makes the avatar more *consistent* (smaller noise band around
   its lean), never perfectly deterministic.
2. **Belief/Attachment disagreement.** Belief and Attachment pull are
   summed (`belief * 0.65 + attachment_pull * 0.6`) rather than one
   overriding the other. A freshly-introduced tag (`belief == 0.0`, never
   reinforced) is still shaded by whatever the Attachment for that axis has
   drifted to from *other* tags on the same axis — e.g. an Otso that's
   never specifically been praised/chastised for `intimidate_stranger` but
   has a high `attachment_toothy` from being praised repeatedly for
   `attack_predator` will still lean toward `intimidate_stranger` more
   often than a 50/50 coin flip, because the Attachment generalizes across
   the axis even where the specific belief hasn't been trained yet. That
   generalization is exactly where a design or narrative surprise ("it did
   the aggressive new thing even though I never taught it that one
   specifically") comes from honestly, not from a scripted exception.

`would_do()` fires `Voices.react(&"avatar_surprised_expectation", {...})`
whenever the sampled probability was below `0.25` (a discouraged action)
but the roll came back `true`, or above `0.75` (an encouraged action) but
the roll came back `false` — so Package M has a real, non-degenerate
trigger to write commentary against rather than needing to guess when
"surprising" happened.

## Growth stages (small → huge)

Gated on **both** accumulated `praise_count` (incremented once per
`receive_praise()` call, regardless of whether a context was active) *and*
cumulative `devotion_fed` (via `feed_devotion(amount)`, callable by any
system — Sanctum overflow, a deliberate feeding rite, etc.). Chastise is
tracked (`chastise_count`) but deliberately does **not** count toward
growth, so a god who only ever punishes cannot back into growth through
punishment volume.

| Stage | min praise | min devotion | scale mult | stat mult |
|---|---|---|---|---|
| Cub | 0 | 0 | 0.55x | 0.65x |
| Juvenile | 6 | 30 | 0.8x | 0.9x |
| Grown | 16 | 120 | 1.0x | 1.0x |
| Huge | 35 | 350 | 1.6x | 1.4x |

`scale_mult` multiplies `species.base_scale` and is applied to the `Body`
node's `Scale3D` (`Avatar.get_effective_scale()` /
`_apply_growth_visuals()`) — a real visual change, not a stat-only one.
`stat_mult` multiplies `species.base_strength/speed/stamina`
(`get_effective_strength/speed/stamina()`), which is what Package L
(combat) and anything else that cares about the Avatar's physical
capability should read instead of the raw species baseline.

## The three species

One shared `avatar.gd`; per-species data lives entirely in
`AvatarSpecies` resources:

- **Otso (bear)** — `base_learning_rate = 0.2` (slow learner), high
  `base_strength` (1.7), low `base_speed` (0.75). Starts with a slightly
  higher `attachment_toothy` seed (0.45) than the others — a bear starts
  more inclined to bite first, but that seed is only a starting point, not
  a ceiling: the demo scene proves an Otso can still be trained
  Kind-dominant.
- **Krukk (raven)** — `base_learning_rate = 0.6` (fast learner), low
  `base_strength` (0.45), high `base_speed` (1.35). Highest starting
  `attachment_watching` seed (0.65) — a raven notices things fastest.
- **Sarv (elk)** — balanced learning rate (0.35), high `base_stamina`
  (1.5), the only species with `feeds_villages = true` /
  `devotion_yield_per_feed_action` set — the data hook for a "the Avatar
  can carry food back to a village" mechanic (see "Scoped out": the hook
  exists on the Resource, the actual feeding-loop gameplay is not wired up
  in this pass).

## Placeholder bodies

`Avatar._build_placeholder_body()` composes a small primitive rig per
species id at runtime (`_build_otso_body`/`_build_krukk_body`/
`_build_sarv_body`/`_build_generic_body` fallback) directly under the
scene's empty `Body` node — `CapsuleMesh`/`SphereMesh`/`BoxMesh`/
`CylinderMesh` only, tinted from `species.color_primary`/`color_accent`.
This is **honestly a placeholder** pending real sculpted/scanned creature
art (see "Scoped out"); the point of building it in code rather than
hand-authoring three meshes is that growth-stage scaling, species
swapping, and demo iteration all work immediately without a modeling pass,
and the primitive composition is recognizably bear/raven/elk-shaped at a
glance (bulky quadruped + ears + snout; small elongated body + beak + flat
wings; tall boxy body + long legs + branching antlers) rather than three
identical grey capsules.

## Integration with the foundation APIs

- **`core/naklon.gd`** — deliberately *not* read anywhere in the learning
  path (see "Divergence from Naklon" above). Not touched by this file at
  all; a later art-direction pass (Package D) is free to read
  `Naklon.unit()` for the Avatar's material/shader the same way
  `actors/hand/hand.gd` already does, without that affecting this file's
  model.
- **`systems/voices/voices.gd`** — `Voices.react(&"avatar_praised", ...)`,
  `&"avatar_chastised"`, `&"avatar_grew"`, `&"avatar_surprised_expectation"`
  fired at the moments documented above.
- **`project.godot` `[input]`** — reads the existing `praise_avatar`
  (physical keycode F) and `chastise_avatar` (physical keycode G) actions
  via `_unhandled_input`; no new input actions were added (K owns no write
  access to `project.godot`).
- **`core/game_state.gd`** — not written to directly by this pass;
  `GameState.avatar_species` (a `StringName`) is the documented hook for
  whichever system runs species selection at game start to call
  `avatar.set_species(GameState.cultures...)`-equivalent
  (`avatar.set_species(load("res://actors/avatar/species/%s.tres" %
  GameState.avatar_species))`) — reading that field and calling
  `set_species` is left to whatever scene wires the Avatar into the real
  world (out of this package's owned directory).
- **`actors/avatar/combat/` (Package L)** — builds against this file's
  public API only (`would_do`, `get_belief`, `begin_context`/
  `end_context`, `get_effective_strength/speed/stamina`); this pass does
  not implement any combat, hunting, or duel logic itself. Cross-checked
  against L's `AvatarCombatant` (which was already written and bridges to
  a "real Avatar" via `has_method()` duck-typing, so it runs standalone
  whether or not this file is wired in): this file implements every method
  `AvatarCombatant` probes for — `get_belief`, `would_do`,
  `get_growth_stage`, plus the two it names explicitly as optional bridge
  points, `reinforce_belief(tag, delta)` and `get_growth_scalar(axis)` —
  so `avatar_path` pointed at a live `Avatar` node activates the real
  bridge rather than silently falling back to `AvatarCombatant`'s local
  demo beliefs. One convention gap worth flagging for whoever does the
  integration pass: `AvatarCombatant`'s own fallback beliefs are scaled
  0..1 ("how strongly it believes in X"), while this file's `beliefs` are
  -1..1 desirability per the design brief; `duel_arena.gd` math like
  `get_belief(&"guard_instinct") * 0.5` degrades gracefully (a
  never-reinforced or negatively-reinforced tag just reads as "rarely/
  never," not a crash) but was not renormalized to 0..1 here, since -1..1
  is what this package was briefed to build and what `get_belief`'s own
  doc comment above promises callers.

## Scoped out

Stated plainly, not silently faked:

- **No locomotion/steering AI.** `avatar.gd` only applies gravity and a
  small idle breathing bob (`_process`) so the demo isn't a static prop.
  Roaming, hunting, fleeing, and duel movement are Package L's territory,
  built against the public API above (`would_do`, `get_belief`,
  `get_effective_speed`, etc.) rather than reimplemented here.
- **No real sculpted/scanned creature meshes.** The three bodies are
  primitive-composed placeholders (see "Placeholder bodies"). No IK
  rig/Skeleton3D either — matches the tradeoff `actors/hand/hand.gd`
  already documents for the Hand.
- **Sarv's "feeds villages" hook is data-only.** `AvatarSpecies.
  feeds_villages`/`devotion_yield_per_feed_action` exist on `sarv.tres` as
  the documented data hook, but this pass does not build the villager-
  facing feeding UI/rite or the `GameState.add_devotion` side effect a full
  "the Avatar carries food home" loop would need — only the belief/growth
  model (`feed_devotion`, which is the god feeding the Avatar, not the
  reverse) is wired up.
- **Growth scale is visual-only, not collision-synced.** `get_effective_scale()`
  scales the `Body` node (the placeholder mesh) but `avatar.tscn`'s root
  `CollisionShape3D` is left at a fixed size — a Huge-stage Avatar will
  visually outgrow its own collision capsule. Scaling a live
  `CollisionShape3D` correctly (recentering so the feet stay planted, not
  just uniformly scaling around the shape's own origin) is a real
  correctness problem for a physics body and was left out rather than
  rushed; Package L (combat), which is the system that actually cares about
  hit volumes, should size its own attack/hurtbox logic off
  `get_effective_scale()` directly instead of trusting the root capsule.
- **No persistence/save format.** `beliefs`/attachment values/growth state
  live only in the running `Avatar` node this pass; wiring them into a
  save file is out of scope here (no save system exists yet in the
  foundation to hook into).
- **No GUT unit tests.** `docs/systems/engineering.md` already flags
  `actors/avatar/` as one of the modules most worth adding automated
  coverage to; this pass ships the runnable `avatar_demo.tscn` instead
  (see `docs/rendering.md`/`docs/systems/engineering.md` for how a
  validation pass would exercise it) since no test framework is wired into
  this project yet.

## Assets used

None. Everything in this package is procedurally-generated primitive
geometry and code; no external CC0/licensed asset files were downloaded
for this pass.
