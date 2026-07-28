extends Node
## Package O demo/proving-ground for skirmish_scenario.gd. Self-contained:
## no player input, no GPU-dependent visuals needed to prove the point (a
## CanvasLayer text feed, same pattern as
## actors/avatar/combat/duel_arena_demo.gd for package L). Spawns a
## SkirmishScenario in LOUHI_PRESENCE mode with skirmish-paced (fast) Louhi
## tuning, then simulates "a player periodically tending a village" by
## calling the SAME public Reach.convert_via_help() any real single-player
## village conversion in the game already uses — standing in for real
## player input, which this package deliberately does not read (ui/ and
## campaign/ own real input, exactly as avatar_combat.md scopes input out
## of package L's duel demo).
##
## This proves SkirmishScenario really registers real Village resources
## into the real GameState, really spawns a real (if retuned) LouhiDirector
## that reacts to them via the real Reach/Weather/Voices autoloads, and
## really ends the session on a real win condition — not a scripted fake.
## What this demo does NOT prove: anything about net/network_manager.gd,
## since opponent_mode here is LOUHI_PRESENCE, not SECOND_GOD_NETWORKED —
## see docs/systems/skirmish_net.md for why a networked demo can't be built
## the same way in this sandbox.

@onready var _scenario: SkirmishScenario = $SkirmishScenario
@onready var _feed_label: Label = $UI/FeedLabel
@onready var _status_label: Label = $UI/StatusLabel

var _feed_lines: Array[String] = []
const MAX_FEED_LINES := 18

var _tend_timer: float = 0.0
const TEND_INTERVAL := 6.0

var _restart_timer: float = 0.0
const RESTART_DELAY := 5.0


func _ready() -> void:
	_scenario.scenario_started.connect(_on_scenario_started)
	_scenario.scenario_ended.connect(_on_scenario_ended)
	_scenario.village_claimed.connect(_on_village_claimed)
	_scenario.louhi_sign.connect(_on_louhi_sign)
	_scenario.louhi_relented.connect(_on_louhi_relented)
	Voices.remark.connect(_on_voices_remark)
	Naklon.naklon_changed.connect(_on_naklon_changed)

	# autostart is left false on the SkirmishScenario node (see
	# skirmish_scenario_demo.tscn) specifically so every signal above is
	# connected BEFORE the first scenario_started fires — starting it any
	# earlier would race that first signal, same reasoning
	# duel_arena_demo.gd documents for its own DuelArena.
	_scenario.start_scenario()


func _process(delta: float) -> void:
	if _scenario.is_running():
		_tend_timer -= delta
		if _tend_timer <= 0.0:
			_tend_timer = TEND_INTERVAL
			_tend_random_village()
		_status_label.text = "Skirmish running — %ds elapsed / %ds remaining\n%s" % [
			int(_scenario.get_elapsed()), int(_scenario.time_remaining()), _village_status_line()
		]
	elif _restart_timer > 0.0:
		_restart_timer -= delta
		_status_label.text = "Skirmish ended. Rematch in %ds..." % int(ceil(_restart_timer))
		if _restart_timer <= 0.0:
			_push_feed("--- new skirmish ---")
			_scenario.start_scenario()


## Debug readout only — reads GameState directly (every package is free to
## do that), it does not reach into SkirmishScenario's internals.
func _village_status_line() -> String:
	var parts: Array[String] = []
	for village_id in _scenario.village_ids:
		var v: Village = GameState.get_village(village_id)
		if v == null:
			continue
		var state := "rival" if v.loyal_to_rival else ("%d%%" % int(v.faith_fraction * 100.0))
		parts.append("%s:%s" % [v.display_name, state])
	return " | ".join(parts)


func _tend_random_village() -> void:
	if _scenario.village_ids.is_empty():
		return
	var village_id: StringName = _scenario.village_ids[randi() % _scenario.village_ids.size()]
	var v: Village = GameState.get_village(village_id)
	if v == null or v.loyal_to_rival:
		return
	Reach.convert_via_help(village_id, randf_range(2.0, 5.0))
	_push_feed("(you tend %s)" % v.display_name)


func _on_scenario_started(village_ids: Array[StringName]) -> void:
	_push_feed("Skirmish begins: %d villages in play" % village_ids.size())


func _on_scenario_ended(reason: StringName, tally: Dictionary) -> void:
	_push_feed("Skirmish ends (%s): %s" % [String(reason), str(tally)])
	_restart_timer = RESTART_DELAY


func _on_village_claimed(village_id: StringName, state: StringName) -> void:
	_push_feed(">> %s is now %s <<" % [String(village_id), String(state)])


func _on_louhi_sign(tier: int, _village_id: StringName, description: String) -> void:
	_push_feed("[Louhi tier %d] %s" % [tier, description])


func _on_louhi_relented(village_id: StringName, from_tier: int) -> void:
	_push_feed("[Louhi relents on %s, was tier %d]" % [String(village_id), from_tier])


func _on_voices_remark(speaker: StringName, line: String) -> void:
	_push_feed("[%s] %s" % [String(speaker), line])


func _on_naklon_changed(old_value: float, new_value: float) -> void:
	_push_feed("(Naklon %.2f -> %.2f)" % [old_value, new_value])


func _push_feed(text: String) -> void:
	_feed_lines.append(text)
	if _feed_lines.size() > MAX_FEED_LINES:
		_feed_lines.pop_front()
	_feed_label.text = "\n".join(_feed_lines)
