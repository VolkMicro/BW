extends CharacterBody3D
class_name Avatar
## PACKAGE K — the Avatar's real learning model. This is the heart of the
## game: a genuine, inspectable reinforcement-style learner, not a scripted
## imitation of one. Every number below actually drives behavior; nothing
## here is a stub that returns a fixed answer.
##
## THE MODEL, IN ONE PARAGRAPH: the Avatar carries three Attachments
## (Watching/Toothy/Kind, each 0..1) and a tag-keyed belief store
## (`beliefs`, StringName -> float -1..1 desirability). Other systems mark
## "this is what I'm doing/considering right now" with begin_context(tag);
## while a tag is active, the player's praise_avatar/chastise_avatar input
## (already bound in project.godot) — or any other system calling
## receive_praise()/receive_chastise() directly — nudges beliefs[tag] via a
## real lerp toward +1/-1, at a rate scaled by the CURRENT Watching
## attachment. Toothy/Kind then drift a little from the SAME events,
## coupled to whichever axis the tag is registered under in TAG_AXIS. Other
## systems ask "what would this thing do" via would_do(tag) /
## action_probability(tag), which read belief + attachment + a noise term —
## never a hardcoded switch. Full write-up: docs/systems/avatar.md.
##
## DIVERGENCE FROM NAKLON (required by the design brief, load-bearing):
## attachment_watching/toothy/kind are NEVER written from Naklon.value or
## Naklon.unit() anywhere in this file. A mercy-played god (Naklon strongly
## negative) who nonetheless praised every act of aggression will grow a
## Toothy-high beast; a cruelty-played god who punished aggression every
## time will grow a Toothy-low, Kind-high beast. See avatar_demo.tscn, which
## deliberately pushes Naklon toward Cruelty and then trains the opposite
## way, to prove this isn't just an unused variable.
##
## Public API relied on by other packages (L = combat, N = Louhi, G =
## villagers, campaign):
##   avatar.get_belief(tag: StringName) -> float
##   avatar.would_do(tag: StringName) -> bool
##   avatar.action_probability(tag: StringName) -> float   (0..1, the number would_do samples against)
##   avatar.begin_context(tag) / end_context(tag) / is_context_active(tag)
##   avatar.receive_praise() / avatar.receive_chastise()   (also fire on the bound input actions)
##   avatar.feed_devotion(amount: float)                    (growth input #2, alongside praise_count)
##   avatar.set_species(s: AvatarSpecies)
##   avatar.get_growth_stage() -> int / get_growth_stage_name() -> String
##   avatar.get_effective_strength/speed/stamina/scale() -> float
##   avatar.attachment_watching / attachment_toothy / attachment_kind (exported, inspectable)
##   avatar.beliefs (exported Dictionary, inspectable)
## Signals: belief_updated, attachment_changed, praised, chastised, grew.
## Group membership: every live Avatar is in group &"avatar".

signal belief_updated(tag: StringName, old_value: float, new_value: float)
signal attachment_changed(axis: StringName, old_value: float, new_value: float)
signal praised(active_tags: Array)
signal chastised(active_tags: Array)
signal grew(old_stage: int, new_stage: int)

# ---------------------------------------------------------------------------
# Context-tag -> Attachment-axis map. Only tags listed here pull an
# Attachment when reinforced (see _update_attachment_from_event); any other
# StringName tag still gets a real belief (get_belief/would_do work on it
# fine) but with no attachment coupling — this is a deliberate, documented
# extension point so package L/N/campaign can invent new context tags
# without editing this file, at the cost of that new tag not moving
# Watching/Toothy/Kind on its own.
# ---------------------------------------------------------------------------
const TAG_AXIS: Dictionary = {
	# Toothy-coded: self-interested / aggressive acts.
	&"eat_villager": &"toothy",
	&"attack_predator": &"toothy",
	&"hoard_food": &"toothy",
	&"intimidate_stranger": &"toothy",
	# Kind-coded: caretaking / compassionate acts.
	&"carry_resource": &"kind",
	&"guard_village": &"kind",
	&"share_food": &"kind",
	&"comfort_child": &"kind",
	# Watching-coded: curiosity/attentiveness, not a morality axis.
	&"approach_stranger": &"watching",
	&"explore_new_place": &"watching",
}

# Growth stages: small -> huge. Gated on BOTH accumulated praise_count AND
# cumulative devotion_fed (see _check_growth) — either alone is not enough,
# so a god who only clicks praise without ever routing devotion to the
# Avatar (or vice versa) does not get a shortcut to Huge.
const GROWTH_STAGES: Array[Dictionary] = [
	{"name": "Cub", "min_praise": 0, "min_devotion": 0.0, "scale_mult": 0.55, "stat_mult": 0.65},
	{"name": "Juvenile", "min_praise": 6, "min_devotion": 30.0, "scale_mult": 0.8, "stat_mult": 0.9},
	{"name": "Grown", "min_praise": 16, "min_devotion": 120.0, "scale_mult": 1.0, "stat_mult": 1.0},
	{"name": "Huge", "min_praise": 35, "min_devotion": 350.0, "scale_mult": 1.6, "stat_mult": 1.4},
]

const DEFAULT_LEARNING_RATE := 0.35
const ATTACHMENT_SHIFT_STEP := 0.06   # per reinforced event, direct axis pull
const ATTACHMENT_NOTICE_STEP := 0.015 # per ANY feedback event, Watching ticks up a little
const COUPLING_FACTOR := 0.4          # Toothy/Kind loosely pull against each other
const BELIEF_WEIGHT := 0.65
const ATTACHMENT_WEIGHT := 0.6
const NOISE_BASE := 0.35              # max +/- noise injected into action_probability at Watching=0
const SURPRISE_THRESHOLD_LOW := 0.25
const SURPRISE_THRESHOLD_HIGH := 0.75
const GRAVITY := 9.8

# --- Config ------------------------------------------------------------------
@export var species: AvatarSpecies = null
@export var show_debug_label: bool = true
## Off: the label is the creature's name and growth stage, which is how a
## player finds it. On: the learning model's internals, for tuning.
@export var show_developer_readout: bool = false

## The three Attachments. Independently-tracked running scalars, 0..1 —
## see the class doc comment above: NEVER slaved to Naklon.value.
@export var attachment_watching: float = 0.5:
	set(v):
		var old := attachment_watching
		attachment_watching = clampf(v, 0.0, 1.0)
		if not is_equal_approx(old, attachment_watching):
			attachment_changed.emit(&"watching", old, attachment_watching)
@export var attachment_toothy: float = 0.3:
	set(v):
		var old := attachment_toothy
		attachment_toothy = clampf(v, 0.0, 1.0)
		if not is_equal_approx(old, attachment_toothy):
			attachment_changed.emit(&"toothy", old, attachment_toothy)
@export var attachment_kind: float = 0.3:
	set(v):
		var old := attachment_kind
		attachment_kind = clampf(v, 0.0, 1.0)
		if not is_equal_approx(old, attachment_kind):
			attachment_changed.emit(&"kind", old, attachment_kind)

## The belief store. StringName context tag -> learned scalar, -1..1
## desirability. Exported so it is genuinely inspectable in the editor / the
## remote scene tree debugger while the game runs, per the design brief.
@export var beliefs: Dictionary = {}

# --- Runtime state -----------------------------------------------------------
var active_tags: Array[StringName] = []
var praise_count: int = 0
var chastise_count: int = 0
var devotion_fed: float = 0.0
var growth_stage: int = 0

var _body: Node3D
var _label: Label3D
var _base_body_y: float = 0.0
var _t: float = 0.0


func _ready() -> void:
	add_to_group(&"avatar")
	_body = get_node_or_null(^"Body")
	_label = get_node_or_null(^"DebugLabel")
	if species:
		_initialize_from_species()
	_seed_known_beliefs()
	_build_placeholder_body()
	_apply_growth_visuals()
	_update_debug_label()


func _seed_known_beliefs() -> void:
	# Pre-populate every documented tag at neutral (0.0) so the Dictionary is
	# visibly complete in the Inspector from frame one, rather than only
	# growing keys lazily as events happen.
	for tag in TAG_AXIS.keys():
		if not beliefs.has(tag):
			beliefs[tag] = 0.0


# ---------------------------------------------------------------------------
# Species
# ---------------------------------------------------------------------------
## Assign (or change) species at runtime. Resets the three Attachments to
## that species' starting seed and rebuilds the placeholder body. Safe to
## call before or after _ready().
func set_species(s: AvatarSpecies) -> void:
	species = s
	if species:
		_initialize_from_species()
	if is_inside_tree():
		_build_placeholder_body()
		_apply_growth_visuals()
		_update_debug_label()


func _initialize_from_species() -> void:
	attachment_watching = species.start_attachment_watching
	attachment_toothy = species.start_attachment_toothy
	attachment_kind = species.start_attachment_kind


func get_species_id() -> StringName:
	return species.id if species else &"unknown"


# ---------------------------------------------------------------------------
# Context tags — other systems declare "this is what I'm doing right now"
# ---------------------------------------------------------------------------
func begin_context(tag: StringName) -> void:
	if not active_tags.has(tag):
		active_tags.append(tag)


func end_context(tag: StringName) -> void:
	active_tags.erase(tag)


func clear_context() -> void:
	active_tags.clear()


func is_context_active(tag: StringName) -> bool:
	return active_tags.has(tag)


# ---------------------------------------------------------------------------
# Praise / chastise — the actual learning event
# ---------------------------------------------------------------------------
## Bound to the "praise_avatar" input action (project.godot [input]). Also
## callable directly by any system (villager AI, campaign scripting,
## avatar_demo.gd) that wants to reward the Avatar programmatically.
func receive_praise() -> void:
	praise_count += 1
	_apply_feedback(1.0)
	praised.emit(active_tags.duplicate())
	Voices.react(&"avatar_praised", {"tags": active_tags.duplicate(), "species": get_species_id()})
	_check_growth()


## Bound to the "chastise_avatar" input action. Chastise moves beliefs and
## Attachments exactly like praise (reward = -1.0 instead of +1.0) but does
## NOT count toward growth thresholds — growth is gated on praise_count
## specifically (see GROWTH_STAGES doc comment), so a god who only ever
## punishes never accidentally grows the Avatar through punishment volume.
func receive_chastise() -> void:
	chastise_count += 1
	_apply_feedback(-1.0)
	chastised.emit(active_tags.duplicate())
	Voices.react(&"avatar_chastised", {"tags": active_tags.duplicate(), "species": get_species_id()})


func _apply_feedback(reward: float) -> void:
	if active_tags.is_empty():
		# Honest no-op for beliefs: there is nothing to attribute the
		# feedback to. We still nudge Watching up a hair — the Avatar
		# notices it's being addressed even without knowing about what —
		# see docs/systems/avatar.md "Feedback with no active context".
		_shift_attachment(&"watching", ATTACHMENT_NOTICE_STEP)
		return
	for tag in active_tags:
		_apply_reward_to_tag(tag, reward)


## THE learning rule. `beliefs[tag] = lerp(beliefs[tag], reward, rate)`,
## rate scaled by the CURRENT attachment_watching (see
## _effective_learning_rate). This is the one place beliefs are written from
## player feedback.
func _apply_reward_to_tag(tag: StringName, reward: float) -> void:
	var old_belief: float = get_belief(tag)
	var rate := _effective_learning_rate()
	var new_belief: float = clampf(lerp(old_belief, reward, rate), -1.0, 1.0)
	beliefs[tag] = new_belief
	if not is_equal_approx(old_belief, new_belief):
		belief_updated.emit(tag, old_belief, new_belief)
	_update_attachment_from_event(tag, reward)


func _effective_learning_rate() -> float:
	var base_rate: float = species.base_learning_rate if species else DEFAULT_LEARNING_RATE
	# Watching scales how far a single event can move a belief: a
	# low-Watching beast barely updates per event (it wasn't paying
	# attention); a high-Watching one nearly snaps toward the reward.
	return clampf(base_rate * lerp(0.35, 1.85, attachment_watching), 0.02, 0.98)


func _update_attachment_from_event(tag: StringName, reward: float) -> void:
	# ANY feedback event sharpens attentiveness a little — the Avatar is
	# learning THAT it is being taught, independent of what about.
	_shift_attachment(&"watching", ATTACHMENT_NOTICE_STEP)
	var axis: StringName = TAG_AXIS.get(tag, &"")
	match axis:
		&"toothy":
			_shift_attachment(&"toothy", reward * ATTACHMENT_SHIFT_STEP)
			_shift_attachment(&"kind", -reward * ATTACHMENT_SHIFT_STEP * COUPLING_FACTOR)
		&"kind":
			_shift_attachment(&"kind", reward * ATTACHMENT_SHIFT_STEP)
			_shift_attachment(&"toothy", -reward * ATTACHMENT_SHIFT_STEP * COUPLING_FACTOR)
		&"watching":
			_shift_attachment(&"watching", reward * ATTACHMENT_SHIFT_STEP * 0.5)
		_:
			pass # tag has no attachment coupling registered — belief-only learning


func _shift_attachment(axis_name: StringName, delta: float) -> void:
	match axis_name:
		&"watching":
			attachment_watching += delta
		&"toothy":
			attachment_toothy += delta
		&"kind":
			attachment_kind += delta


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"praise_avatar"):
		receive_praise()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"chastise_avatar"):
		receive_chastise()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Public inspection API — what other systems (a duel opponent, a hungry
# moment near a villager, Louhi sizing up the beast) ask the Avatar.
# ---------------------------------------------------------------------------
func get_belief(tag: StringName) -> float:
	return beliefs.get(tag, 0.0)


## 0..1 probability that the Avatar would do `tag` right now. Genuinely
## depends on accumulated belief AND the current Attachments — never a
## hardcoded table. This is also where "real surprise" lives: even a
## strongly-formed belief still has a noise term (shrunk, not erased, by
## high Watching), so a well-trained Avatar can still occasionally do the
## unexpected thing.
func action_probability(tag: StringName) -> float:
	var belief := get_belief(tag)
	var axis: StringName = TAG_AXIS.get(tag, &"")
	var pull := 0.0
	match axis:
		&"toothy":
			pull = (attachment_toothy - 0.5) * 2.0
		&"kind":
			pull = (attachment_kind - 0.5) * 2.0
		&"watching":
			pull = (attachment_watching - 0.5) * 2.0
		_:
			pull = 0.0
	var combined := belief * BELIEF_WEIGHT + pull * ATTACHMENT_WEIGHT
	# A more attentive (higher Watching) Avatar is more consistent/deliberate;
	# a distracted one is more erratic. Noise never fully vanishes.
	var noise_amplitude := NOISE_BASE * (1.0 - attachment_watching * 0.7)
	combined += randf_range(-noise_amplitude, noise_amplitude)
	return clampf(0.5 + combined * 0.5, 0.03, 0.97)


## Environmental/outcome-driven belief reinforcement — distinct from
## receive_praise()/receive_chastise(). Lets another system that observed a
## CONSEQUENCE in the world (Package L's duel_arena.gd crediting "pressing
## the advantage worked out" or "retreating while hurt saved it") nudge a
## belief directly, without that being mistaken for the player's own
## praise/chastise input. Deliberately does NOT move any Attachment: per
## this file's design, Watching/Toothy/Kind only move from the player's own
## signal (see class doc comment, "Divergence from Naklon"), not from a
## generic reward channel — otherwise "trained by the god" and "trained by
## the world" would be indistinguishable in the Attachments, which defeats
## the point of tracking them independently. Also doubles as the duck-typed
## bridge method Package L's AvatarCombatant looks for via has_method().
func reinforce_belief(tag: StringName, delta: float) -> void:
	var old_belief := get_belief(tag)
	var new_belief := clampf(old_belief + delta, -1.0, 1.0)
	beliefs[tag] = new_belief
	if not is_equal_approx(old_belief, new_belief):
		belief_updated.emit(tag, old_belief, new_belief)


## Samples action_probability(tag) against a fresh random roll. Callers
## should treat every call as a real coin flip weighted by the model, not an
## idempotent query — call it once per decision point, not every frame.
func would_do(tag: StringName) -> bool:
	var p := action_probability(tag)
	var result := randf() < p
	# Flag the genuinely surprising outcomes (rolled against a strong lean)
	# so package M can write real commentary for them.
	if (p < SURPRISE_THRESHOLD_LOW and result) or (p > SURPRISE_THRESHOLD_HIGH and not result):
		Voices.react(&"avatar_surprised_expectation", {"tag": tag, "probability": p, "result": result, "species": get_species_id()})
	return result


# ---------------------------------------------------------------------------
# Growth — small to huge, gated on praise_count AND devotion_fed
# ---------------------------------------------------------------------------
## Feed accumulated devotion into the Avatar (growth input #2). Any system
## can call this (Sanctum overflow, a deliberate "feed the beast" rite).
## The Sarv-only village-feeding loop — the Avatar giving resources BACK to
## a village — is the reverse direction and is a separate, scoped-out
## mechanic; see docs/systems/avatar.md "Scoped out".
func feed_devotion(amount: float) -> void:
	if amount <= 0.0:
		return
	devotion_fed += amount
	_check_growth()


func _check_growth() -> void:
	var new_stage := growth_stage
	for i in range(GROWTH_STAGES.size() - 1, -1, -1):
		var stage: Dictionary = GROWTH_STAGES[i]
		if praise_count >= int(stage.min_praise) and devotion_fed >= float(stage.min_devotion):
			new_stage = i
			break
	if new_stage != growth_stage:
		var old := growth_stage
		growth_stage = new_stage
		_apply_growth_visuals()
		grew.emit(old, growth_stage)
		Voices.react(&"avatar_grew", {"stage": get_growth_stage_name(), "species": get_species_id()})


func get_growth_stage() -> int:
	return growth_stage


func get_growth_stage_name() -> String:
	return String(GROWTH_STAGES[growth_stage].name)


func _current_stat_mult() -> float:
	return float(GROWTH_STAGES[growth_stage].stat_mult)


func get_effective_strength() -> float:
	return (species.base_strength if species else 1.0) * _current_stat_mult()


func get_effective_speed() -> float:
	return (species.base_speed if species else 1.0) * _current_stat_mult()


func get_effective_stamina() -> float:
	return (species.base_stamina if species else 1.0) * _current_stat_mult()


func get_effective_scale() -> float:
	var base_scale: float = species.base_scale if species else 1.0
	return base_scale * float(GROWTH_STAGES[growth_stage].scale_mult)


## Generic per-axis growth multiplier for external bridges that don't know
## about get_effective_strength/speed/stamina() individually — currently
## Package L's AvatarCombatant, which asks for &"health"/&"damage" via
## has_method() duck-typing. All axes share the current stage's stat_mult
## in this pass (see GROWTH_STAGES); kept as a match rather than returning
## _current_stat_mult() directly so a later pass can differentiate
## per-axis curves (e.g. health scaling faster than damage) without
## breaking either this method's signature or its callers.
func get_growth_scalar(axis: StringName) -> float:
	match axis:
		&"health", &"damage", &"strength", &"speed", &"stamina":
			return _current_stat_mult()
		_:
			return _current_stat_mult()


func _apply_growth_visuals() -> void:
	if _body:
		_body.scale = Vector3.ONE * get_effective_scale()
	_update_debug_label()


# ---------------------------------------------------------------------------
# Placeholder body — primitive-composed low-poly creature geometry.
# Honestly a placeholder pending real sculpted/scanned art (see
# docs/systems/avatar.md "Scoped out"). One shared script builds a
# different primitive rig per species id so a single avatar.tscn can be
# reused for all three starting species.
# ---------------------------------------------------------------------------
func _build_placeholder_body() -> void:
	if _body == null:
		return
	for child in _body.get_children():
		child.queue_free()
	var sid: StringName = species.id if species else &""
	match sid:
		&"otso":
			_build_otso_body()
		&"krukk":
			_build_krukk_body()
		&"sarv":
			_build_sarv_body()
		_:
			_build_generic_body()
	_base_body_y = _body.position.y


func _add_part(mesh: Mesh, xform: Transform3D, color: Color, name_hint: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name_hint
	mi.mesh = mesh
	mi.transform = xform
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	mi.material_override = mat
	_body.add_child(mi)
	return mi


func _primary_color() -> Color:
	return species.color_primary if species else Color(0.5, 0.5, 0.5, 1.0)


func _accent_color() -> Color:
	return species.color_accent if species else Color(0.8, 0.8, 0.8, 1.0)


func _build_otso_body() -> void:
	var primary := _primary_color()
	var accent := _accent_color()
	var torso := CapsuleMesh.new()
	torso.radius = 0.55
	torso.height = 1.3
	_add_part(torso, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(90.0)), Vector3(0.0, 0.85, 0.0)), primary, "Torso")
	var head := SphereMesh.new()
	head.radius = 0.4
	head.height = 0.8
	_add_part(head, Transform3D(Basis.IDENTITY, Vector3(0.0, 1.05, 0.75)), primary, "Head")
	var snout := CapsuleMesh.new()
	snout.radius = 0.16
	snout.height = 0.34
	_add_part(snout, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(90.0)), Vector3(0.0, 0.95, 1.08)), accent, "Snout")
	var ear := SphereMesh.new()
	ear.radius = 0.12
	ear.height = 0.24
	_add_part(ear, Transform3D(Basis.IDENTITY, Vector3(0.28, 1.38, 0.62)), primary, "EarL")
	_add_part(ear, Transform3D(Basis.IDENTITY, Vector3(-0.28, 1.38, 0.62)), primary, "EarR")
	var leg := CylinderMesh.new()
	leg.top_radius = 0.17
	leg.bottom_radius = 0.15
	leg.height = 0.6
	for x in [0.36, -0.36]:
		for z in [0.55, -0.55]:
			_add_part(leg, Transform3D(Basis.IDENTITY, Vector3(x, 0.3, z)), primary, "Leg")


func _build_krukk_body() -> void:
	var primary := _primary_color()
	var accent := _accent_color()
	var body_mesh := SphereMesh.new()
	body_mesh.radius = 0.26
	body_mesh.height = 0.52
	var body_inst := _add_part(body_mesh, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, 0.0)), primary, "Body")
	body_inst.scale = Vector3(1.0, 1.0, 1.5)
	var head := SphereMesh.new()
	head.radius = 0.15
	head.height = 0.3
	_add_part(head, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.66, 0.32)), primary, "Head")
	var beak := CylinderMesh.new()
	beak.top_radius = 0.0
	beak.bottom_radius = 0.06
	beak.height = 0.22
	_add_part(beak, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(90.0)), Vector3(0.0, 0.64, 0.5)), accent, "Beak")
	var wing := BoxMesh.new()
	wing.size = Vector3(0.5, 0.05, 0.32)
	_add_part(wing, Transform3D(Basis(Vector3.FORWARD, deg_to_rad(8.0)), Vector3(0.32, 0.5, 0.0)), primary, "WingL")
	_add_part(wing, Transform3D(Basis(Vector3.FORWARD, deg_to_rad(-8.0)), Vector3(-0.32, 0.5, 0.0)), primary, "WingR")
	var tail := BoxMesh.new()
	tail.size = Vector3(0.08, 0.05, 0.36)
	_add_part(tail, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, -0.4)), primary, "Tail")
	var leg := CylinderMesh.new()
	leg.top_radius = 0.03
	leg.bottom_radius = 0.03
	leg.height = 0.34
	_add_part(leg, Transform3D(Basis.IDENTITY, Vector3(0.08, 0.17, 0.05)), accent, "LegL")
	_add_part(leg, Transform3D(Basis.IDENTITY, Vector3(-0.08, 0.17, 0.05)), accent, "LegR")


func _build_sarv_body() -> void:
	var primary := _primary_color()
	var accent := _accent_color()
	var torso := BoxMesh.new()
	torso.size = Vector3(0.55, 0.55, 1.15)
	_add_part(torso, Transform3D(Basis.IDENTITY, Vector3(0.0, 1.05, 0.0)), primary, "Torso")
	var neck := CapsuleMesh.new()
	neck.radius = 0.16
	neck.height = 0.55
	_add_part(neck, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(35.0)), Vector3(0.0, 1.45, 0.55)), primary, "Neck")
	var head := BoxMesh.new()
	head.size = Vector3(0.24, 0.24, 0.42)
	_add_part(head, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(15.0)), Vector3(0.0, 1.8, 0.88)), primary, "Head")
	var leg := CylinderMesh.new()
	leg.top_radius = 0.09
	leg.bottom_radius = 0.07
	leg.height = 1.0
	for x in [0.22, -0.22]:
		for z in [0.42, -0.42]:
			_add_part(leg, Transform3D(Basis.IDENTITY, Vector3(x, 0.5, z)), primary, "Leg")
	var antler := CylinderMesh.new()
	antler.top_radius = 0.02
	antler.bottom_radius = 0.035
	antler.height = 0.5
	_add_part(antler, Transform3D(Basis(Vector3.FORWARD, deg_to_rad(30.0)), Vector3(0.12, 2.05, 0.82)), accent, "AntlerL")
	_add_part(antler, Transform3D(Basis(Vector3.FORWARD, deg_to_rad(-30.0)), Vector3(-0.12, 2.05, 0.82)), accent, "AntlerR")
	var tine := CylinderMesh.new()
	tine.top_radius = 0.015
	tine.bottom_radius = 0.025
	tine.height = 0.24
	_add_part(tine, Transform3D(Basis(Vector3.FORWARD, deg_to_rad(60.0)), Vector3(0.24, 2.28, 0.9)), accent, "TineL")
	_add_part(tine, Transform3D(Basis(Vector3.FORWARD, deg_to_rad(-60.0)), Vector3(-0.24, 2.28, 0.9)), accent, "TineR")


func _build_generic_body() -> void:
	# Fallback for an Avatar spawned with no species assigned (should not
	# happen in normal play — GameState.avatar_species is chosen at game
	# start — but keeps the scene from rendering nothing if it does).
	var torso := CapsuleMesh.new()
	torso.radius = 0.35
	torso.height = 1.5
	_add_part(torso, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.9, 0.0)), Color(0.55, 0.55, 0.55, 1.0), "Torso")
	var head := SphereMesh.new()
	head.radius = 0.24
	head.height = 0.48
	_add_part(head, Transform3D(Basis.IDENTITY, Vector3(0.0, 1.55, 0.0)), Color(0.7, 0.7, 0.7, 1.0), "Head")


# ---------------------------------------------------------------------------
# Debug label (mirrors actors/villagers/villager.gd's DebugLabel convention)
# ---------------------------------------------------------------------------
func _update_debug_label() -> void:
	if _label == null:
		return
	_label.visible = show_debug_label
	if not show_debug_label:
		return
	# Float the label clear of the creature's own head. The Avatar is scaled
	# by species and growth stage — at the bear's 4.5 the authored 2.6 m put
	# the caption inside its shoulders, hiding the thing it was meant to help
	# you find.
	_label.position.y = 2.6 * get_effective_scale() + 2.0
	var name_str := species.display_name if species else "Avatar"
	if not show_developer_readout:
		# What a PLAYER needs: which creature this is and how grown it is.
		# The three attachment scalars and the praise/chastise counters are
		# the learning model's internals — useful when tuning it, noise when
		# playing. This label is now the only thing marking the creature on a
		# 1200 m island, so it has to be a name, not a debug dump.
		_label.text = "%s\n%s" % [
			TranslationServer.translate(name_str),
			TranslationServer.translate(get_growth_stage_name())]
		return
	_label.text = "%s (%s)\nW:%.2f  T:%.2f  K:%.2f\npraise:%d  chastise:%d  devotion:%.0f" % [
		name_str, get_growth_stage_name(), attachment_watching, attachment_toothy, attachment_kind,
		praise_count, chastise_count, devotion_fed,
	]


# ---------------------------------------------------------------------------
# WALKING.
#
# This used to be gravity and nothing else, with a comment explaining that
# locomotion belonged to a combat package that was never built. The result, on
# the shipped island, was a creature that stood on one spot for the entire
# game — the project owner's question was literally "where is my creature?",
# and the honest answer was "two metres tall, in a field, unable to move, four
# hundred metres from the nearest village".
#
# A learning model with no body cannot be taught anything by a player who
# cannot see it. This is the smallest locomotion that makes the Avatar a
# presence: it walks to where it is sent, and otherwise drifts around the
# ground it thinks of as home. No pathfinding — the same reasoning as the
# villager crowd, which shares this island and this frame budget: refuse the
# steps that would go into the sea or up a cliff and that is enough.
# ---------------------------------------------------------------------------

## Metres per second at base_speed 1.0. The bear's 0.75 makes it deliberately
## slower than a villager (2.1): a god's creature that outruns everything is
## hard to watch, and watching it is the whole relationship.
const WALK_SPEED := 3.4
## How close counts as arrived.
const ARRIVE_RADIUS := 2.5
## A step that would drop it below this is refused — it will not walk into
## the sea.
const MIN_WALK_HEIGHT := 0.6
## A step that climbs more than this in one stride is refused.
const MAX_STEP_CLIMB := 2.2
## How far it drifts from home when it has nowhere to be.
const ROAM_RADIUS := 34.0
const ROAM_PAUSE_MIN := 4.0
const ROAM_PAUSE_MAX := 12.0

## Where it goes when it has nothing else to do. Set by whoever placed it.
var home_position: Vector2 = Vector2.ZERO
## Terrain to walk on. Anything with sample_height(Vector2) -> float.
var terrain: Node = null

var _walk_target: Vector3 = Vector3.ZERO
var _has_target: bool = false
var _roam_timer: float = 0.0
var _roam_rng := RandomNumberGenerator.new()


## Send the creature somewhere. This is the god pointing.
func walk_to(world_xz: Vector2) -> void:
	_walk_target = Vector3(world_xz.x, _ground(world_xz), world_xz.y)
	_has_target = true


## Where it lives when nobody is telling it anything.
func set_home(world_xz: Vector2) -> void:
	home_position = world_xz


func is_walking() -> bool:
	return _has_target


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	if _has_target:
		_step_toward(_walk_target, delta)
	else:
		_roam(delta)

	move_and_slide()
	_stand_on_ground()


func _step_toward(target: Vector3, delta: float) -> void:
	var here := global_position
	var to := Vector2(target.x - here.x, target.z - here.z)
	if to.length() <= ARRIVE_RADIUS:
		_has_target = false
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var speed := WALK_SPEED * (species.base_speed if species != null else 1.0)
	var dir := to.normalized()
	var next := Vector2(here.x, here.z) + dir * speed * delta
	var h := _ground(next)
	# Refuse the sea and the cliff, and give up on a target it cannot reach
	# rather than grinding against the obstacle forever.
	if h < MIN_WALK_HEIGHT or h - here.y > MAX_STEP_CLIMB:
		_has_target = false
		velocity.x = 0.0
		velocity.z = 0.0
		return
	velocity.x = dir.x * speed
	velocity.z = dir.y * speed
	# Face where it is going. Body only — rotating the CharacterBody3D would
	# rotate its capsule and its collision with it.
	if _body != null:
		_body.rotation.y = lerp_angle(_body.rotation.y, atan2(-dir.x, -dir.y), delta * 4.0)


func _roam(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_roam_timer -= delta
	if _roam_timer > 0.0:
		return
	_roam_timer = _roam_rng.randf_range(ROAM_PAUSE_MIN, ROAM_PAUSE_MAX)
	if home_position == Vector2.ZERO:
		return
	var a := _roam_rng.randf() * TAU
	var r := sqrt(_roam_rng.randf()) * ROAM_RADIUS
	var spot := home_position + Vector2(cos(a), sin(a)) * r
	if _ground(spot) >= MIN_WALK_HEIGHT:
		walk_to(spot)


## Keeps its feet on the heightmap. The island has collision, but the Avatar
## is the only physics body that walks on it and a single sample is far
## cheaper than resolving a capsule against a 301x301 collision mesh every
## frame — the same trade the villager crowd makes for six hundred agents.
func _stand_on_ground() -> void:
	if terrain == null:
		return
	var h := _ground(Vector2(global_position.x, global_position.z))
	if global_position.y < h:
		global_position.y = h
		velocity.y = 0.0


func _ground(world_xz: Vector2) -> float:
	if terrain != null and terrain.has_method("sample_height"):
		return terrain.call("sample_height", world_xz)
	return global_position.y


func _process(delta: float) -> void:
	_t += delta
	if _body:
		_body.position.y = _base_body_y + sin(_t * 1.3) * 0.03 * get_effective_scale()
