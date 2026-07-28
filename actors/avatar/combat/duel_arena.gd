extends Node3D
class_name DuelArena
## PACKAGE L — Avatar duels: a 1v1 real-time-tick referee between two
## AvatarCombatant fighters (avatar_combatant.gd, same directory).
##
## Every `tick_interval` seconds both fighters simultaneously choose ONE of
## five moves — BITE, CLAW, CHARGE, GUARD, RETREAT — and the tick is
## resolved: attacks clash against whatever the defender picked (GUARD chips
## bite/claw damage and punishes a CHARGE outright; RETREAT makes an attack
## whiff entirely but can't be done forever). Move SELECTION is delegated to
## AvatarCombatant.would_do()/get_belief() with combat-context tags, which in
## turn bridges to a real Avatar's belief store (package K) when one is
## wired via `avatar_path`, or a local fallback dictionary when it isn't.
## See docs/systems/avatar_combat.md for the full tag table and the
## resolution matrix.
##
## A CHARGE that survives but drops the defender below DOWNED_HEALTH_FRACTION
## knocks them DOWNED (alive, helpless) instead of ending the duel outright.
## The very next tick is a dedicated "finisher window": the attacker's
## would_do(&"finish_downed_foe") decides FINISH (lethal) or MERCY (the
## downed fighter gets back up with a health floor). That decision is
## reinforced into the attacker's belief store immediately — regardless of
## who ultimately wins the duel — because "did the kill/mercy feel right"
## is its own, more immediate signal than the overall win/loss. Win/loss
## reinforcement of press_advantage / retreat_when_hurt / guard_instinct
## happens once, at duel_ended, proportional to how much each tactic was
## actually used relative to its opportunities. See
## docs/systems/avatar_combat.md "What this package writes back" for the
## exact formula.
##
## Public API:
##   duel_arena.start_duel(fighter_a, fighter_b) -> void
## Signals:
##   duel_started(fighter_a, fighter_b)
##   tick_resolved(fighter_a, move_a_name, fighter_b, move_b_name)
##   fighter_downed(fighter, downed_by)
##   fighter_finished(fighter, finisher)
##   fighter_shown_mercy(fighter, mercy_by)
##   duel_ended(winner, loser, finish_type)  -- winner/loser null on a draw;
##     finish_type in &"finished_while_downed", &"defeated_in_exchange",
##     &"double_defeat", &"timeout", &"timeout_draw"

signal duel_started(fighter_a: AvatarCombatant, fighter_b: AvatarCombatant)
signal tick_resolved(fighter_a: AvatarCombatant, move_a_name: StringName, fighter_b: AvatarCombatant, move_b_name: StringName)
signal fighter_downed(fighter: AvatarCombatant, downed_by: AvatarCombatant)
signal fighter_finished(fighter: AvatarCombatant, finisher: AvatarCombatant)
signal fighter_shown_mercy(fighter: AvatarCombatant, mercy_by: AvatarCombatant)
signal duel_ended(winner: AvatarCombatant, loser: AvatarCombatant, finish_type: StringName)

@export var fighter_a_path: NodePath
@export var fighter_b_path: NodePath
@export var tick_interval: float = 0.9
@export var max_ticks: int = 200
@export var autostart: bool = true

# --- Tuning ------------------------------------------------------------------
const RETREAT_HEALTH_THRESHOLD := 0.35
const PRESS_HEALTH_THRESHOLD := 0.45
const DOWNED_HEALTH_FRACTION := 0.2
const RECOVER_HEALTH_FLOOR := 0.22
const MAX_CONSECUTIVE_RETREATS := 2 # a 3rd hurt-retreat in a row is disallowed (cornered -> must act)

const MOVE_DAMAGE := {
	AvatarCombatant.Move.BITE: 12.0,
	AvatarCombatant.Move.CLAW: 7.0,
	AvatarCombatant.Move.CHARGE: 20.0,
}
const MOVE_STAMINA_COST := {
	AvatarCombatant.Move.BITE: 10.0,
	AvatarCombatant.Move.CLAW: 6.0,
	AvatarCombatant.Move.CHARGE: 22.0,
	AvatarCombatant.Move.GUARD: 3.0,
}
const RETREAT_STAMINA_GAIN := 15.0
const GUARD_DAMAGE_REDUCTION := 0.65 # bite/claw chip through a guard at 35% damage
const CHARGE_VS_GUARD_RECOIL := 8.0 # charging into a guard punishes the charger, not the guard
const CHARGE_VS_GUARD_STAMINA_PENALTY := 10.0
const CLAW_STAMINA_DRAIN_ON_HIT := 2.0 # claw also off-balances, on top of its own damage

const REINFORCE_WIN := 0.12
const REINFORCE_LOSS := -0.05
const REINFORCE_FINISH := 0.22
const REINFORCE_MERCY := -0.16
const NAKLON_FINISH_SHIFT := 0.02
const NAKLON_MERCY_SHIFT := -0.02

var fighter_a: AvatarCombatant
var fighter_b: AvatarCombatant

var _running: bool = false
var _tick_count: int = 0
var _tick_timer: float = 0.0
var _consecutive_retreats: Dictionary = {} # AvatarCombatant -> int
var _finisher_pending: Dictionary = {} # {"downed": AvatarCombatant, "attacker": AvatarCombatant}


func _ready() -> void:
	if fighter_a_path != NodePath(""):
		fighter_a = get_node_or_null(fighter_a_path)
	if fighter_b_path != NodePath(""):
		fighter_b = get_node_or_null(fighter_b_path)
	if autostart and fighter_a and fighter_b:
		start_duel(fighter_a, fighter_b)


func start_duel(a: AvatarCombatant, b: AvatarCombatant) -> void:
	fighter_a = a
	fighter_b = b
	fighter_a.reset_for_duel()
	fighter_b.reset_for_duel()
	_running = true
	_tick_count = 0
	_tick_timer = 0.0
	_consecutive_retreats = {a: 0, b: 0}
	_finisher_pending.clear()
	duel_started.emit(a, b)


func is_running() -> bool:
	return _running


func _process(delta: float) -> void:
	if not _running:
		return
	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer = tick_interval
		_run_tick()


func _run_tick() -> void:
	_tick_count += 1
	if not _finisher_pending.is_empty():
		_resolve_finisher_window()
	else:
		_resolve_normal_tick()
	if _running and _tick_count >= max_ticks:
		_end_by_timeout()


# ---------------------------------------------------------------------------
# Normal exchange tick
# ---------------------------------------------------------------------------
func _resolve_normal_tick() -> void:
	var move_a: AvatarCombatant.Move = _choose_move(fighter_a, fighter_b)
	var move_b: AvatarCombatant.Move = _choose_move(fighter_b, fighter_a)

	fighter_a.pending_move = move_a
	fighter_b.pending_move = move_b
	fighter_a.total_moves += 1
	fighter_b.total_moves += 1
	fighter_a.play_move_anim(move_a)
	fighter_b.play_move_anim(move_b)
	_tally_tactic_opportunities(fighter_a, fighter_b, move_a)
	_tally_tactic_opportunities(fighter_b, fighter_a, move_b)

	# Both attacks resolve even if one fighter would already be downed/
	# defeated by the other's blow this same tick — the moves were both
	# already committed before either landed. Ties resolve fighter_a-first;
	# documented, not hidden (docs/systems/avatar_combat.md).
	if move_a in AvatarCombatant.ATTACK_MOVES:
		_land_attack(fighter_a, move_a, fighter_b, move_b)
	if move_b in AvatarCombatant.ATTACK_MOVES:
		_land_attack(fighter_b, move_b, fighter_a, move_a)

	if move_a == AvatarCombatant.Move.GUARD:
		fighter_a.spend_stamina(MOVE_STAMINA_COST[AvatarCombatant.Move.GUARD])
	if move_b == AvatarCombatant.Move.GUARD:
		fighter_b.spend_stamina(MOVE_STAMINA_COST[AvatarCombatant.Move.GUARD])

	_apply_retreat(fighter_a, move_a)
	_apply_retreat(fighter_b, move_b)

	tick_resolved.emit(fighter_a, AvatarCombatant.MOVE_NAMES[move_a], fighter_b, AvatarCombatant.MOVE_NAMES[move_b])
	_check_duel_end()


func _apply_retreat(fighter: AvatarCombatant, move: AvatarCombatant.Move) -> void:
	if move == AvatarCombatant.Move.RETREAT:
		fighter.restore_stamina(RETREAT_STAMINA_GAIN)
		_consecutive_retreats[fighter] = _consecutive_retreats.get(fighter, 0) + 1
	else:
		_consecutive_retreats[fighter] = 0


func _land_attack(attacker: AvatarCombatant, atk_move: AvatarCombatant.Move, defender: AvatarCombatant, def_move: AvatarCombatant.Move) -> void:
	attacker.spend_stamina(MOVE_STAMINA_COST[atk_move])
	var base_damage: float = MOVE_DAMAGE[atk_move] * attacker.damage_scalar

	if def_move == AvatarCombatant.Move.RETREAT:
		return # the attack meets empty air; the defender bought distance

	if def_move == AvatarCombatant.Move.GUARD:
		if atk_move == AvatarCombatant.Move.CHARGE:
			# Charging a braced guard punishes the charger, not the guard.
			attacker.apply_damage(CHARGE_VS_GUARD_RECOIL)
			attacker.spend_stamina(CHARGE_VS_GUARD_STAMINA_PENALTY)
			defender.guard_punish_uses += 1
		else:
			defender.apply_damage(base_damage * (1.0 - GUARD_DAMAGE_REDUCTION))
		return

	# Defender was attacking too, retreating-but-failed-to (handled above),
	# or simply staggered — the attack lands clean.
	defender.apply_damage(base_damage)
	if atk_move == AvatarCombatant.Move.CLAW:
		defender.spend_stamina(CLAW_STAMINA_DRAIN_ON_HIT)

	if atk_move == AvatarCombatant.Move.CHARGE and defender.state == AvatarCombatant.FighterState.READY:
		if defender.health > 0.0 and defender.health_fraction() <= DOWNED_HEALTH_FRACTION and _finisher_pending.is_empty():
			# The is_empty() guard matters when both fighters CHARGE each
			# other in the same tick and both would qualify for a knockdown:
			# only the first one resolved this tick (fighter_a, by the fixed
			# a-then-b order above) actually enters the DOWNED/finisher-window
			# state; the second just takes the raw hit. Without this guard a
			# second qualifying hit would silently overwrite _finisher_pending
			# and strand the first fighter in DOWNED with no window to ever
			# resolve it.
			defender.enter_downed()
			_finisher_pending = {"downed": defender, "attacker": attacker}
			fighter_downed.emit(defender, attacker)


# ---------------------------------------------------------------------------
# Move selection — reads AvatarCombatant.would_do()/get_belief(), which
# bridges to K's Avatar belief store when wired (see avatar_combatant.gd).
# ---------------------------------------------------------------------------
func _choose_move(me: AvatarCombatant, foe: AvatarCombatant) -> AvatarCombatant.Move:
	if me.is_staggered or me.stamina <= 0.0:
		return AvatarCombatant.Move.GUARD # gassed out — can only brace

	var cornered: bool = _consecutive_retreats.get(me, 0) >= MAX_CONSECUTIVE_RETREATS

	if me.health_fraction() <= RETREAT_HEALTH_THRESHOLD and not cornered and me.would_do(&"retreat_when_hurt"):
		return AvatarCombatant.Move.RETREAT

	if foe.health_fraction() <= PRESS_HEALTH_THRESHOLD and me.would_do(&"press_advantage"):
		if me.stamina >= MOVE_STAMINA_COST[AvatarCombatant.Move.CHARGE]:
			return AvatarCombatant.Move.CHARGE
		return AvatarCombatant.Move.BITE

	# Neutral exchange: guard_instinct sets how often this fighter turtles
	# up when neither "press" nor "retreat" conditions fired.
	if randf() < me.get_belief(&"guard_instinct") * 0.5:
		return AvatarCombatant.Move.GUARD

	if me.stamina >= MOVE_STAMINA_COST[AvatarCombatant.Move.CHARGE] and randf() < 0.3:
		return AvatarCombatant.Move.CHARGE
	if me.stamina >= MOVE_STAMINA_COST[AvatarCombatant.Move.BITE] and randf() < 0.5:
		return AvatarCombatant.Move.BITE
	return AvatarCombatant.Move.CLAW


func _tally_tactic_opportunities(me: AvatarCombatant, foe: AvatarCombatant, chosen_move: AvatarCombatant.Move) -> void:
	if foe.health_fraction() <= PRESS_HEALTH_THRESHOLD:
		me.press_advantage_opportunities += 1
		if chosen_move in AvatarCombatant.ATTACK_MOVES:
			me.press_advantage_uses += 1
	if me.health_fraction() <= RETREAT_HEALTH_THRESHOLD:
		me.retreat_opportunities += 1
		if chosen_move == AvatarCombatant.Move.RETREAT:
			me.retreat_hurt_uses += 1


# ---------------------------------------------------------------------------
# Finisher window — dedicated tick right after a knockdown blow.
# ---------------------------------------------------------------------------
func _resolve_finisher_window() -> void:
	var downed_fighter: AvatarCombatant = _finisher_pending["downed"]
	var attacker: AvatarCombatant = _finisher_pending["attacker"]
	_finisher_pending.clear()

	if attacker.would_do(&"finish_downed_foe"):
		attacker.reinforce_belief(&"finish_downed_foe", REINFORCE_FINISH)
		if attacker.is_player_side:
			Naklon.shift(NAKLON_FINISH_SHIFT, 1.0)
		Voices.react(&"duel_foe_finished_while_downed", {
			"finisher": attacker.display_name,
			"downed": downed_fighter.display_name,
		})
		downed_fighter.apply_damage(downed_fighter.health) # lethal
		fighter_finished.emit(downed_fighter, attacker)
		_end_duel(attacker, downed_fighter, &"finished_while_downed")
	else:
		attacker.reinforce_belief(&"finish_downed_foe", REINFORCE_MERCY)
		if attacker.is_player_side:
			Naklon.shift(NAKLON_MERCY_SHIFT, 1.0)
		Voices.react(&"duel_mercy_shown", {
			"spared_by": attacker.display_name,
			"downed": downed_fighter.display_name,
		})
		downed_fighter.recover_from_downed(RECOVER_HEALTH_FLOOR)
		fighter_shown_mercy.emit(downed_fighter, attacker)


# ---------------------------------------------------------------------------
# End conditions
# ---------------------------------------------------------------------------
func _check_duel_end() -> void:
	if not _running:
		return
	var a_dead := fighter_a.state == AvatarCombatant.FighterState.DEFEATED
	var b_dead := fighter_b.state == AvatarCombatant.FighterState.DEFEATED
	if a_dead and b_dead:
		_end_duel(null, null, &"double_defeat")
	elif a_dead:
		_end_duel(fighter_b, fighter_a, &"defeated_in_exchange")
	elif b_dead:
		_end_duel(fighter_a, fighter_b, &"defeated_in_exchange")


func _end_by_timeout() -> void:
	if not _running:
		return
	var a_frac := fighter_a.health_fraction()
	var b_frac := fighter_b.health_fraction()
	if is_equal_approx(a_frac, b_frac):
		_end_duel(null, null, &"timeout_draw")
	elif a_frac > b_frac:
		_end_duel(fighter_a, fighter_b, &"timeout")
	else:
		_end_duel(fighter_b, fighter_a, &"timeout")


func _end_duel(winner: AvatarCombatant, loser: AvatarCombatant, finish_type: StringName) -> void:
	if not _running:
		return
	_running = false
	if winner and loser:
		_apply_belief_feedback(winner, loser)
		Voices.react(&"duel_ended", {
			"winner": winner.display_name,
			"loser": loser.display_name,
			"finish_type": String(finish_type),
		})
	duel_ended.emit(winner, loser, finish_type)


# ---------------------------------------------------------------------------
# Win/loss belief feedback — "winning duels genuinely reinforces whatever
# behavior was used." Proportional to how OFTEN a tactic was actually used
# relative to how often it had an opportunity to be used, so a winner who
# never got low on health doesn't get a false retreat_when_hurt bump, etc.
# ---------------------------------------------------------------------------
func _apply_belief_feedback(winner: AvatarCombatant, loser: AvatarCombatant) -> void:
	_reinforce_tactics(winner, REINFORCE_WIN)
	_reinforce_tactics(loser, REINFORCE_LOSS)


func _reinforce_tactics(fighter: AvatarCombatant, base_amount: float) -> void:
	if fighter.press_advantage_opportunities > 0:
		var ratio: float = float(fighter.press_advantage_uses) / float(fighter.press_advantage_opportunities)
		fighter.reinforce_belief(&"press_advantage", base_amount * ratio)
	if fighter.retreat_opportunities > 0:
		var r_ratio: float = float(fighter.retreat_hurt_uses) / float(fighter.retreat_opportunities)
		fighter.reinforce_belief(&"retreat_when_hurt", base_amount * r_ratio)
	if fighter.guard_punish_uses > 0:
		fighter.reinforce_belief(&"guard_instinct", base_amount * 0.5)
