extends Node3D
class_name AvatarCombatant
## PACKAGE L — one fighter in a duel_arena.gd match.
##
## This node is a thin combat body: it owns health/stamina/state and a
## *bridge* to a real Avatar's belief store and growth stage (package K,
## actors/avatar/avatar.gd) without hard-depending on that class existing.
## Every belief/growth call goes through has_method() duck-typing against
## `avatar_node`, so this file compiles and runs standalone (see
## avatar_combatant.tscn / duel_arena_demo.tscn) whether or not K's
## avatar.gd has landed yet. See docs/systems/avatar_combat.md
## "Integration contract" for the exact method signatures this expects
## K's avatar.gd to expose, and which of them existed at write time.
##
## Public API:
##   combatant.health / combatant.stamina / combatant.state (FighterState)
##   combatant.health_fraction() / combatant.stamina_fraction()
##   combatant.get_belief(tag) -> float        (reads K's avatar if wired)
##   combatant.would_do(tag) -> bool           (reads K's avatar if wired)
##   combatant.reinforce_belief(tag, delta)    (writes K's avatar if wired)
##   combatant.get_growth_stage() -> int
##   combatant.apply_damage(amount) / spend_stamina(amount) / restore_stamina(amount)
##   combatant.enter_downed() / recover_from_downed(floor_fraction)
## Signals: health_changed, stamina_changed, move_performed, downed,
##          recovered_from_downed, defeated.

signal health_changed(new_health: float, max_health: float)
signal stamina_changed(new_stamina: float, max_stamina: float)
signal move_performed(move_name: StringName)
signal downed()
signal recovered_from_downed()
signal defeated()

enum Move { BITE, CLAW, CHARGE, GUARD, RETREAT }
enum FighterState { READY, DOWNED, DEFEATED }

const ATTACK_MOVES: Array[Move] = [Move.BITE, Move.CLAW, Move.CHARGE]

const MOVE_NAMES := {
	Move.BITE: &"bite",
	Move.CLAW: &"claw",
	Move.CHARGE: &"charge",
	Move.GUARD: &"guard",
	Move.RETREAT: &"retreat",
}

# --- Config ------------------------------------------------------------------
@export var display_name: String = "Avatar"
@export var base_health: float = 100.0
@export var base_stamina: float = 100.0
@export var tint: Color = Color(0.7, 0.7, 0.7)

## Optional: path to a real K Avatar node (actors/avatar/avatar.gd) to read
## beliefs and growth scalars from. Leave empty to run in standalone/demo
## mode against the local `_fallback_beliefs` dictionary below — this is
## also what happens automatically if the node at this path lacks the
## expected methods (has_method() checked every call, never assumed).
@export var avatar_path: NodePath = ^""

## Used ONLY in standalone/demo mode (no avatar_node, or avatar_node lacks
## get_growth_stage()/get_growth_scalar()). 0=hatchling .. 3=elder. Stands in
## for K's real per-stage table so the demo scene can still show growth
## visibly affecting stats before K's file exists.
@export_range(0, 3, 1) var demo_growth_stage: int = 1

## If true, this fighter's finish/mercy choice in a duel also nudges the
## shared Naklon scalar (a duel fought by the player's own Avatar reflects
## on the god, not just the beast). Left false for NPC-vs-NPC demo duels.
@export var is_player_side: bool = false

# --- Runtime state -----------------------------------------------------------
var avatar_node: Node = null
var max_health: float = 100.0
var max_stamina: float = 100.0
var damage_scalar: float = 1.0
var health: float = 100.0
var stamina: float = 100.0
var state: FighterState = FighterState.READY
var pending_move: Move = Move.GUARD
var is_staggered: bool = false

# Tallies consumed by duel_arena.gd's end-of-duel belief feedback pass.
# Reset in reset_for_duel(). Public because DuelArena reads/increments them
# directly (this class has no reason to hide its own scoreboard).
var total_moves: int = 0
var press_advantage_uses: int = 0
var press_advantage_opportunities: int = 0
var retreat_hurt_uses: int = 0
var retreat_opportunities: int = 0
var guard_punish_uses: int = 0

## Standalone belief store, used only when avatar_node is absent or doesn't
## implement the belief API yet. Values are 0..1: "how strongly this fighter
## believes in doing X." Tag list matches the contract this package was
## briefed to read/write; see docs/systems/avatar_combat.md.
var _fallback_beliefs: Dictionary = {
	&"press_advantage": 0.5,
	&"retreat_when_hurt": 0.4,
	&"finish_downed_foe": 0.5,
	&"guard_instinct": 0.35,
}

const GROWTH_STAT_CURVE := [0.55, 0.8, 1.0, 1.3] # fallback health/damage multiplier per demo_growth_stage

@onready var _body_mesh: MeshInstance3D = get_node_or_null("Body")
@onready var _head_mesh: MeshInstance3D = get_node_or_null("Body/Head")
@onready var _label: Label3D = get_node_or_null("StatusLabel")

var _base_body_scale: Vector3 = Vector3.ONE
var _lunge_t: float = 0.0
var _guard_t: float = 0.0
var _retreat_t: float = 0.0
var _hit_flash_t: float = 0.0


func _ready() -> void:
	if avatar_path != NodePath(""):
		avatar_node = get_node_or_null(avatar_path)
	_apply_growth_scalars()
	health = max_health
	stamina = max_stamina
	if _body_mesh:
		_base_body_scale = _body_mesh.scale
		_apply_tint()
	_refresh_label()


## Re-arms this fighter for a fresh duel without re-instancing the node
## (handy for the demo's "fight again" loop). Growth/belief state is left
## alone — only the per-duel scoreboard and vitals reset.
func reset_for_duel() -> void:
	_apply_growth_scalars()
	health = max_health
	stamina = max_stamina
	state = FighterState.READY
	pending_move = Move.GUARD
	is_staggered = false
	total_moves = 0
	press_advantage_uses = 0
	press_advantage_opportunities = 0
	retreat_hurt_uses = 0
	retreat_opportunities = 0
	guard_punish_uses = 0
	_refresh_label()


func _apply_growth_scalars() -> void:
	var health_mult := 1.0
	var damage_mult := 1.0
	if avatar_node and avatar_node.has_method("get_growth_scalar"):
		health_mult = avatar_node.get_growth_scalar(&"health")
		damage_mult = avatar_node.get_growth_scalar(&"damage")
	else:
		var stage := clampi(demo_growth_stage, 0, GROWTH_STAT_CURVE.size() - 1)
		health_mult = GROWTH_STAT_CURVE[stage]
		damage_mult = GROWTH_STAT_CURVE[stage]
	max_health = base_health * health_mult
	max_stamina = base_stamina # endurance is fatigue/skill, not size — not growth-scaled
	damage_scalar = damage_mult
	# Visual body scale is NOT set here — it's recomputed every frame in
	# _process() from _base_body_scale (captured once in _ready(), before
	# any growth scaling ever touches the mesh) so calling this repeatedly
	# from reset_for_duel() can never compound the scale.


## Public setter for the standalone/demo belief dictionary (used by
## duel_arena_demo.gd to give its two fighters contrasting personalities
## without reaching into the "private" _fallback_beliefs field directly).
## Has no effect once a live avatar_node with get_belief() is wired — that
## Avatar's own belief store is the real source of truth at that point.
func configure_demo_beliefs(beliefs: Dictionary) -> void:
	for tag in beliefs:
		_fallback_beliefs[tag] = beliefs[tag]


## Public setter for `tint` that also re-applies it to the mesh materials.
## Needed because `tint` is only baked into a StandardMaterial3D once, in
## _ready() -> _apply_tint(); a plain `combatant.tint = Color(...)` after
## _ready() has already run (e.g. from a demo/setup script) would silently
## have no visual effect otherwise.
func set_tint(color: Color) -> void:
	tint = color
	_apply_tint()


func get_growth_stage() -> int:
	if avatar_node and avatar_node.has_method("get_growth_stage"):
		return avatar_node.get_growth_stage()
	return demo_growth_stage


# ---------------------------------------------------------------------------
# Belief bridge (reads/writes K's avatar.gd when wired, else local fallback)
# ---------------------------------------------------------------------------
func get_belief(tag: StringName) -> float:
	if avatar_node and avatar_node.has_method("get_belief"):
		return avatar_node.get_belief(tag)
	return _fallback_beliefs.get(tag, 0.5)


func would_do(tag: StringName) -> bool:
	if avatar_node and avatar_node.has_method("would_do"):
		return avatar_node.would_do(tag)
	return randf() < get_belief(tag)


func reinforce_belief(tag: StringName, delta: float) -> void:
	if avatar_node and avatar_node.has_method("reinforce_belief"):
		avatar_node.reinforce_belief(tag, delta)
	else:
		_fallback_beliefs[tag] = clampf(_fallback_beliefs.get(tag, 0.5) + delta, 0.0, 1.0)


# ---------------------------------------------------------------------------
# Vitals
# ---------------------------------------------------------------------------
func health_fraction() -> float:
	return health / max_health if max_health > 0.0 else 0.0


func stamina_fraction() -> float:
	return stamina / max_stamina if max_stamina > 0.0 else 0.0


func apply_damage(amount: float) -> void:
	if state == FighterState.DEFEATED or amount <= 0.0:
		return
	var mult := 1.5 if is_staggered else 1.0
	health = maxf(0.0, health - amount * mult)
	_hit_flash_t = 1.0
	health_changed.emit(health, max_health)
	_refresh_label()
	if health <= 0.0:
		_defeat()


func spend_stamina(amount: float) -> void:
	stamina = clampf(stamina - amount, 0.0, max_stamina)
	is_staggered = stamina <= 0.0
	stamina_changed.emit(stamina, max_stamina)
	_refresh_label()


func restore_stamina(amount: float) -> void:
	stamina = clampf(stamina + amount, 0.0, max_stamina)
	if stamina > 0.0:
		is_staggered = false
	stamina_changed.emit(stamina, max_stamina)
	_refresh_label()


func enter_downed() -> void:
	state = FighterState.DOWNED
	downed.emit()
	_refresh_label()


func recover_from_downed(health_floor_fraction: float) -> void:
	state = FighterState.READY
	health = maxf(health, max_health * health_floor_fraction)
	health_changed.emit(health, max_health)
	recovered_from_downed.emit()
	_refresh_label()


func _defeat() -> void:
	state = FighterState.DEFEATED
	defeated.emit()
	_refresh_label()


# ---------------------------------------------------------------------------
# Visuals — procedural, no skeletal animation (see docs "Scoped out"): a
# lunge/recoil/crouch/collapse readback driven purely by move + state.
# ---------------------------------------------------------------------------
func play_move_anim(move: Move) -> void:
	move_performed.emit(MOVE_NAMES[move])
	match move:
		Move.BITE, Move.CLAW, Move.CHARGE:
			_lunge_t = 1.0
		Move.GUARD:
			_guard_t = 1.0
		Move.RETREAT:
			_retreat_t = 1.0


func _apply_tint() -> void:
	if _body_mesh == null:
		return
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = tint
	body_mat.roughness = 0.75
	_body_mesh.material_override = body_mat
	if _head_mesh:
		var head_mat := StandardMaterial3D.new()
		head_mat.albedo_color = tint.lightened(0.25)
		head_mat.roughness = 0.5
		_head_mesh.material_override = head_mat


func _process(delta: float) -> void:
	_lunge_t = maxf(0.0, _lunge_t - delta * 3.0)
	_guard_t = maxf(0.0, _guard_t - delta * 2.5)
	_retreat_t = maxf(0.0, _retreat_t - delta * 2.5)
	_hit_flash_t = maxf(0.0, _hit_flash_t - delta * 4.0)
	if _body_mesh == null:
		return

	var base_scale := _base_body_scale * pow(max_health / maxf(base_health, 0.001), 1.0 / 3.0)
	match state:
		FighterState.DEFEATED:
			_body_mesh.rotation.z = lerp_angle(_body_mesh.rotation.z, deg_to_rad(85.0), delta * 5.0)
			_body_mesh.position.y = lerp(_body_mesh.position.y, 0.25, delta * 5.0)
			return
		FighterState.DOWNED:
			_body_mesh.rotation.z = lerp_angle(_body_mesh.rotation.z, deg_to_rad(70.0), delta * 6.0)
			_body_mesh.position.y = lerp(_body_mesh.position.y, 0.3, delta * 6.0)
			return
		_:
			_body_mesh.rotation.z = lerp_angle(_body_mesh.rotation.z, 0.0, delta * 6.0)

	var lunge_offset := 0.4 * _lunge_t
	var crouch_scale := 1.0 - 0.15 * _guard_t
	var pull_back := -0.3 * _retreat_t
	_body_mesh.position.z = lunge_offset + pull_back
	_body_mesh.position.y = lerp(_body_mesh.position.y, base_scale.y * 0.75, delta * 8.0)
	_body_mesh.scale = base_scale * crouch_scale

	if _body_mesh.material_override is StandardMaterial3D:
		var mat: StandardMaterial3D = _body_mesh.material_override
		mat.emission_enabled = _hit_flash_t > 0.0
		if _hit_flash_t > 0.0:
			mat.emission = Color(1.0, 0.25, 0.2)
			mat.emission_energy_multiplier = _hit_flash_t * 2.0

	_refresh_label()


func _refresh_label() -> void:
	if _label == null:
		return
	var state_text: String = ["ready", "DOWNED", "defeated"][state]
	_label.text = "%s\nHP %d/%d  ST %d/%d\n%s" % [
		display_name, int(ceil(health)), int(max_health),
		int(ceil(stamina)), int(max_stamina), state_text,
	]
