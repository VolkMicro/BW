extends Node3D
## Package L demo harness. Spawns two AvatarCombatant fighters with
## deliberately contrasting growth stages and belief presets (so the "bigger
## Avatar hits harder and survives longer" and "beliefs steer move choice"
## claims are actually visible in one run, not just true in the abstract),
## wires them into a DuelArena, and prints a running feed of tick-by-tick
## moves plus every Voices.react() remark fired by the duel. Not meant as
## real campaign content — world/sanctum (I) and campaign/ (S) own where a
## real duel would be triggered from; this is a self-contained proving
## ground for the combat state machine and its belief read/write wiring,
## run directly or embedded.
##
## No live actors/avatar/avatar.gd (package K) is assumed to exist: both
## demo fighters run in AvatarCombatant's standalone/fallback-belief mode
## (avatar_path left empty). If K's avatar.gd is present in the project at
## integration time, this demo can be pointed at real Avatar nodes by
## setting `fighter_a.avatar_path` / `fighter_b.avatar_path` in the editor
## or from a follow-up script — no code change required here, since
## AvatarCombatant already duck-types against get_belief/would_do/
## reinforce_belief/get_growth_stage/get_growth_scalar.

@onready var _fighter_a: AvatarCombatant = $FighterA
@onready var _fighter_b: AvatarCombatant = $FighterB
@onready var _arena: DuelArena = $DuelArena
@onready var _feed_label: Label = $UI/FeedLabel
@onready var _status_label: Label = $UI/StatusLabel

var _feed_lines: Array[String] = []
const MAX_FEED_LINES := 16
var _restart_timer: float = 0.0
const RESTART_DELAY := 4.0


func _ready() -> void:
	# Fighter A: young, aggressive — high press_advantage/finish beliefs,
	# low retreat/guard instinct, smaller growth stage (juvenile).
	_fighter_a.display_name = "Otso-cub, the Overeager"
	_fighter_a.set_tint(Color(0.62, 0.24, 0.16))
	_fighter_a.demo_growth_stage = 1
	_fighter_a.configure_demo_beliefs({
		&"press_advantage": 0.85,
		&"retreat_when_hurt": 0.15,
		&"finish_downed_foe": 0.8,
		&"guard_instinct": 0.15,
	})

	# Fighter B: old, cautious — favors guard/retreat, shows mercy more
	# often, but is a full growth stage bigger (elder), so it hits harder
	# and has more health despite being the more passive fighter.
	_fighter_b.display_name = "Krukk-elder, the Patient"
	_fighter_b.set_tint(Color(0.22, 0.3, 0.34))
	_fighter_b.demo_growth_stage = 3
	_fighter_b.configure_demo_beliefs({
		&"press_advantage": 0.35,
		&"retreat_when_hurt": 0.7,
		&"finish_downed_foe": 0.25,
		&"guard_instinct": 0.6,
	})

	_arena.duel_started.connect(_on_duel_started)
	_arena.tick_resolved.connect(_on_tick_resolved)
	_arena.fighter_downed.connect(_on_fighter_downed)
	_arena.fighter_finished.connect(_on_fighter_finished)
	_arena.fighter_shown_mercy.connect(_on_fighter_shown_mercy)
	_arena.duel_ended.connect(_on_duel_ended)
	Voices.remark.connect(_on_voices_remark)

	# autostart is left false on the DuelArena node (see duel_arena_demo.tscn)
	# specifically so this _ready() can finish naming/tinting/configuring
	# both fighters and hooking every signal BEFORE the first duel_started
	# fires — starting it any earlier would race the very first signal.
	_arena.start_duel(_fighter_a, _fighter_b)


func _process(delta: float) -> void:
	if _restart_timer > 0.0:
		_restart_timer -= delta
		if _restart_timer <= 0.0:
			_push_feed("--- rematch ---")
			_arena.start_duel(_fighter_a, _fighter_b)
	_status_label.text = (
		"%s  HP %d/%d  ST %d/%d  [growth %d]\n%s  HP %d/%d  ST %d/%d  [growth %d]"
		% [
			_fighter_a.display_name, int(ceil(_fighter_a.health)), int(_fighter_a.max_health),
			int(ceil(_fighter_a.stamina)), int(_fighter_a.max_stamina), _fighter_a.get_growth_stage(),
			_fighter_b.display_name, int(ceil(_fighter_b.health)), int(_fighter_b.max_health),
			int(ceil(_fighter_b.stamina)), int(_fighter_b.max_stamina), _fighter_b.get_growth_stage(),
		]
	)


func _on_duel_started(a: AvatarCombatant, b: AvatarCombatant) -> void:
	_push_feed("Duel begins: %s vs %s" % [a.display_name, b.display_name])


func _on_tick_resolved(a: AvatarCombatant, move_a: StringName, b: AvatarCombatant, move_b: StringName) -> void:
	_push_feed("%s: %s   |   %s: %s" % [a.display_name, String(move_a), b.display_name, String(move_b)])


func _on_fighter_downed(fighter: AvatarCombatant, downed_by: AvatarCombatant) -> void:
	_push_feed(">> %s is DOWNED by %s <<" % [fighter.display_name, downed_by.display_name])


func _on_fighter_finished(fighter: AvatarCombatant, finisher: AvatarCombatant) -> void:
	_push_feed(">> %s finishes off %s <<" % [finisher.display_name, fighter.display_name])


func _on_fighter_shown_mercy(fighter: AvatarCombatant, mercy_by: AvatarCombatant) -> void:
	_push_feed(">> %s spares %s <<" % [mercy_by.display_name, fighter.display_name])


func _on_duel_ended(winner: AvatarCombatant, loser: AvatarCombatant, finish_type: StringName) -> void:
	if winner:
		_push_feed("Duel ends (%s): %s defeats %s" % [String(finish_type), winner.display_name, loser.display_name])
	else:
		_push_feed("Duel ends (%s): draw" % String(finish_type))
	_restart_timer = RESTART_DELAY


func _on_voices_remark(speaker: StringName, line: String) -> void:
	_push_feed("[%s] %s" % [String(speaker), line])


func _push_feed(text: String) -> void:
	_feed_lines.append(text)
	if _feed_lines.size() > MAX_FEED_LINES:
		_feed_lines.pop_front()
	_feed_label.text = "\n".join(_feed_lines)
