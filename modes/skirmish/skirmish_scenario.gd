extends Node
class_name SkirmishScenario
## Package O — a bounded, self-contained skirmish session: a small subset
## of villages (not the full open-ended campaign island) where a player
## god plays against either Louhi's presence AI (actors/louhi/louhi_director.gd,
## package N, retuned to a skirmish's much shorter pace — see "Louhi
## retuning" below) or another living god over the network
## (net/network_manager.gd, this same package, per docs/systems/OWNERSHIP.md).
##
## This is deliberately NOT a parallel game-state system: villages here are
## real Village resources (core/village.gd) registered into the same
## GameState autoload every other package reads, Naklon is the same Naklon
## autoload every other package reads, and every conversion mechanic a
## caller runs against a scenario village goes through the same
## systems/faith/reach.gd (package J) methods any single-player village
## conversion already uses. The only genuinely new bookkeeping this file
## owns is (a) which small set of villages belongs to THIS bounded session
## and (b) the session's own timer/win-condition — nothing else in the
## codebase has a concept of a scored, time-boxed session; GameState's
## campaign is intentionally open-ended.
##
## THIS NODE IS NOT AN AUTOLOAD. Package O may not edit project.godot per
## docs/systems/OWNERSHIP.md. See skirmish_scenario.tscn for a
## ready-to-instance wrapper (same shape as
## actors/louhi/louhi_director.tscn) and docs/systems/skirmish_net.md for
## exactly what's wired vs. not, plus this repo's honesty norm on what
## could and couldn't be verified without a GPU or a second real client.
##
## modes/skirmish/ and net/ are independent, duck-typed-coupled systems —
## this scenario runs fine with no NetworkManager present at all (single
## player vs. Louhi, or a bare sandbox with no opponent), and a
## NetworkManager runs fine with no SkirmishScenario present (a future
## full-campaign multiplayer mode could drive it directly). See
## `network_manager_path` below for the one, optional, fully-defensive
## integration point between the two.

signal scenario_started(village_ids: Array[StringName])
signal scenario_ended(reason: StringName, tally: Dictionary)
signal village_claimed(village_id: StringName, state: StringName)
## Forwarded straight from an instanced LouhiDirector's own signals (see
## _spawn_louhi_opponent below) so a consumer of THIS scenario never needs
## to know LouhiDirector exists, let alone reach into it directly.
signal louhi_sign(tier: int, village_id: StringName, description: String)
signal louhi_relented(village_id: StringName, from_tier: int)

enum Opponent {
	NONE,                 ## sandbox — no AI, no second god; just a bounded timer
	LOUHI_PRESENCE,       ## actors/louhi/louhi_director.gd, retuned fast (package N)
	SECOND_GOD_NETWORKED, ## net/network_manager.gd owns per-seat village ownership (this package)
}

# --- Scenario setup ---------------------------------------------------------

## Which existing GameState villages belong to this bounded session. Left
## empty by default so this node is runnable completely standalone (see
## _spawn_default_villages) — exactly the same "runs and is inspectable on
## its own" guarantee actors/avatar/combat/duel_arena_demo.gd makes for
## package L. A future integration pass (world/sanctum, campaign/, or a
## menu in ui/) can instead populate this with real, already-registered
## village ids before start_scenario() runs, so a "skirmish" can just as
## well be a scored subset of the real campaign island.
@export var village_ids: Array[StringName] = []

## A skirmish is bounded — "a compact...session," per the brief — not the
## open campaign. Default: three minutes. Ends the session even if no
## side has swept the board.
@export var session_duration_sec: float = 240.0

@export var opponent_mode: Opponent = Opponent.LOUHI_PRESENCE

@export var autostart: bool = true

## faith_fraction at/above this counts a village as fully the player's for
## the single-player tally — matches core/village.gd's own
## Village.is_fully_converted() threshold exactly, so "win the skirmish"
## and "fully convert a village" never disagree.
const VICTORY_FAITH_FRACTION := 0.999

# --- Louhi retuning (skirmish pace, not campaign pace) ----------------------
# LouhiDirector's defaults (75s scouting tick, 5-7 minute patience timers —
# see actors/louhi/louhi_director.gd / docs/systems/louhi.md) are built for
# an open campaign that can run for hours of real playtime. A skirmish is
# minutes long, so every one of her timers is scaled down by roughly an
# order of magnitude below. These are the exact same @export fields
# docs/systems/louhi.md documents as designer-tunable "without touching
# code, from the Inspector" — this is that same knob, turned from a script
# instead, once, right after instancing her (see _spawn_louhi_opponent).
@export_group("Louhi retuning (only used when opponent_mode == LOUHI_PRESENCE)")
@export var louhi_evaluation_interval_sec: float = 10.0
@export var louhi_tier1_patience_sec: float = 35.0
@export var louhi_tier2_patience_sec: float = 45.0
@export var louhi_post_resolution_cooldown_sec: float = 20.0

# --- Optional net/ integration (duck-typed; see class doc) ------------------

## Path to a net/network_manager.gd node, only consulted when
## opponent_mode == SECOND_GOD_NETWORKED. Left as a NodePath (not a static
## NetworkManager type) and always accessed through get_node_or_null() +
## has_method() so this file never hard-depends on net/'s node actually
## being present in the scene tree — the same defensive shape
## actors/louhi/louhi_director.gd uses for its own optional DuelArena hook.
@export var network_manager_path: NodePath

const LOUHI_DIRECTOR_SCRIPT_PATH := "res://actors/louhi/louhi_director.gd"

var _elapsed: float = 0.0
var _running: bool = false
var _louhi_node: Node = null
var _network_manager: Node = null
var _last_state: Dictionary = {} # StringName village_id -> StringName state, change-detection only


func _ready() -> void:
	if network_manager_path != NodePath(""):
		_network_manager = get_node_or_null(network_manager_path)
	if autostart:
		start_scenario()


## Public entry point. Safe to call again after scenario_ended fires (e.g.
## to run a rematch) — re-registers the same village ids (idempotent; see
## _spawn_default_villages) and spawns a fresh opponent instance.
func start_scenario() -> void:
	if village_ids.is_empty():
		village_ids = _spawn_default_villages()
	_elapsed = 0.0
	_running = true
	_last_state.clear()
	if opponent_mode == Opponent.LOUHI_PRESENCE:
		_spawn_louhi_opponent()
	elif opponent_mode == Opponent.SECOND_GOD_NETWORKED:
		_start_networked_match()
	scenario_started.emit(village_ids)


## Stops the session early without a win/loss condition having fired (e.g.
## the player backs out of a menu mid-skirmish). Distinct from
## _end_scenario's normal reasons (&"timeout" / &"player_swept_board" /
## &"rival_swept_board") so a listener can tell "the session concluded" from
## "the session was cancelled."
func abort_scenario() -> void:
	if not _running:
		return
	_end_scenario(&"aborted", _tally())


func is_running() -> bool:
	return _running


func get_elapsed() -> float:
	return _elapsed


func time_remaining() -> float:
	return maxf(0.0, session_duration_sec - _elapsed)


# ---------------------------------------------------------------------------
# Default village generation — makes this node runnable standalone, with no
# other package's scene wired in yet. Reuses GameState.cultures (already
# loaded by the foundation autoload's own _ready(), see core/game_state.gd:26-38)
# rather than inventing new culture data.
# ---------------------------------------------------------------------------

const DEFAULT_START_POPULATION := 12
const DEFAULT_START_FAITH_FRACTION := 0.08
const DEFAULT_SPREAD_RADIUS_M := 30.0 # a compact cluster, not campaign-island scale

func _spawn_default_villages() -> Array[StringName]:
	var culture_ids := GameState.cultures.keys()
	if culture_ids.is_empty():
		# Shouldn't normally happen — GameState._ready() always loads the
		# four data/cultures/*.tres resources unconditionally — but stay
		# defensive rather than producing a zero-village, unwinnable
		# scenario if load order or a future refactor ever changes that.
		culture_ids = [&"fenrayt", &"sankiln", &"raimborn", &"vainkeeper"]

	var ids: Array[StringName] = []
	var angle_step := TAU / maxf(float(culture_ids.size()), 1.0)
	for i in culture_ids.size():
		var culture_id: StringName = culture_ids[i]
		var culture: Culture = GameState.cultures.get(culture_id, null)
		var v := Village.new()
		v.id = StringName("skirmish_%s" % String(culture_id))
		v.display_name = "%s Outpost" % (culture.display_name if culture else String(culture_id).capitalize())
		v.culture_id = culture_id
		var angle := angle_step * i
		v.position_on_island = Vector2(cos(angle), sin(angle)) * DEFAULT_SPREAD_RADIUS_M
		v.population = DEFAULT_START_POPULATION
		v.faith_fraction = DEFAULT_START_FAITH_FRACTION
		GameState.register_village(v)
		ids.append(v.id)
	return ids


# ---------------------------------------------------------------------------
# Louhi opponent (LOUHI_PRESENCE)
# ---------------------------------------------------------------------------

## actors/louhi/louhi_director.gd (package N) is a real, complete script but
## is deliberately not registered as an autoload and not wired into any
## scene (see docs/systems/louhi.md "Instancing her") — exactly the shape
## this package's own two nodes take. Loaded and instanced defensively via
## its script path rather than its class_name: package O must not assume
## LouhiDirector's exact class shape stays stable, and every cross-package
## reference elsewhere in this codebase (e.g. louhi_director.gd's own
## `/root/DuelArena` hook) uses this same load()+has_method() pattern
## rather than a compile-time class_name reference, so a rename or removal
## on N's side degrades to "no opponent" instead of a parse error here.
func _spawn_louhi_opponent() -> void:
	if _louhi_node != null and is_instance_valid(_louhi_node):
		_louhi_node.queue_free()
		_louhi_node = null

	if not ResourceLoader.exists(LOUHI_DIRECTOR_SCRIPT_PATH):
		push_warning("SkirmishScenario: LOUHI_PRESENCE requested but %s is missing; running with no opponent." % LOUHI_DIRECTOR_SCRIPT_PATH)
		return
	var script: Script = load(LOUHI_DIRECTOR_SCRIPT_PATH)
	var node: Object = script.new()
	if not (node is Node):
		push_warning("SkirmishScenario: actors/louhi/louhi_director.gd did not produce a Node; running with no opponent.")
		return

	_louhi_node = node
	_louhi_node.name = &"SkirmishLouhi"
	_louhi_node.set("evaluation_interval_sec", louhi_evaluation_interval_sec)
	_louhi_node.set("tier1_patience_sec", louhi_tier1_patience_sec)
	_louhi_node.set("tier2_patience_sec", louhi_tier2_patience_sec)
	_louhi_node.set("post_resolution_cooldown_sec", louhi_post_resolution_cooldown_sec)
	add_child(_louhi_node)

	if _louhi_node.has_signal("sign_occurred"):
		_louhi_node.connect("sign_occurred", Callable(self, "_on_louhi_sign"))
	if _louhi_node.has_signal("sign_relented"):
		_louhi_node.connect("sign_relented", Callable(self, "_on_louhi_relent"))


func _on_louhi_sign(tier: int, village_id: StringName, description: String) -> void:
	louhi_sign.emit(tier, village_id, description)


func _on_louhi_relent(village_id: StringName, from_tier: int) -> void:
	louhi_relented.emit(village_id, from_tier)


# ---------------------------------------------------------------------------
# Networked match (SECOND_GOD_NETWORKED)
# ---------------------------------------------------------------------------

## Host-only, and entirely optional: if a net/network_manager.gd node is
## wired at network_manager_path and is currently hosting, hand it this
## scenario's village list so it can round-robin starting "home" villages
## to whichever seats have already joined. If no NetworkManager is wired,
## or it isn't hosting (e.g. this instance is a joining client), this is a
## silent no-op — ownership sync is entirely NetworkManager's job, not
## this file's; see net/network_manager.gd's own class doc for the full
## sync model.
func _start_networked_match() -> void:
	if _network_manager == null:
		return
	if not (_network_manager.has_method("is_hosting") and _network_manager.call("is_hosting")):
		return
	if _network_manager.has_method("assign_home_villages"):
		_network_manager.call("assign_home_villages", village_ids)


# ---------------------------------------------------------------------------
# Session tick / win condition
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not _running:
		return
	_elapsed += delta
	var tally := _tally()

	if not village_ids.is_empty():
		if int(tally.get("rival_count", 0)) >= village_ids.size():
			_end_scenario(&"rival_swept_board", tally)
			return
		if opponent_mode != Opponent.SECOND_GOD_NETWORKED and int(tally.get("player_count", 0)) >= village_ids.size():
			_end_scenario(&"player_swept_board", tally)
			return

	if _elapsed >= session_duration_sec:
		_end_scenario(&"timeout", tally)


## Reads only public, already-shared state (GameState/Village, and — for
## SECOND_GOD_NETWORKED — NetworkManager.get_village_owner()) rather than
## keeping its own duplicate scoreboard. Also the single place that detects
## a per-village ownership change and emits village_claimed, so a listener
## never needs to poll this itself.
func _tally() -> Dictionary:
	var player_count := 0
	var rival_count := 0
	var contested_count := 0
	var faith_sum := 0.0

	for village_id in village_ids:
		var v: Village = GameState.get_village(village_id)
		if v == null:
			continue

		var state: StringName
		if opponent_mode == Opponent.SECOND_GOD_NETWORKED and _network_manager != null and _network_manager.has_method("get_village_owner"):
			var owner_peer: int = _network_manager.call("get_village_owner", village_id)
			if owner_peer == 0:
				state = &"unclaimed"
				contested_count += 1
			else:
				# Networked ownership is per-seat (up to nine), not a
				# two-sided player/rival split — "player_count" here means
				# "owned by *some* seat," used only for the all-claimed
				# sweep check above, not for crediting a single winner.
				state = StringName("peer_%d" % owner_peer)
				player_count += 1
		elif v.loyal_to_rival:
			state = &"rival"
			rival_count += 1
		elif v.faith_fraction >= VICTORY_FAITH_FRACTION:
			state = &"player"
			player_count += 1
		else:
			state = &"contested"
			contested_count += 1

		faith_sum += v.faith_fraction
		if _last_state.get(village_id, &"") != state:
			_last_state[village_id] = state
			village_claimed.emit(village_id, state)

	return {
		"player_count": player_count,
		"rival_count": rival_count,
		"contested_count": contested_count,
		"average_faith_fraction": faith_sum / maxf(float(village_ids.size()), 1.0),
	}


func _end_scenario(reason: StringName, tally: Dictionary) -> void:
	if not _running:
		return
	_running = false
	if _louhi_node != null and is_instance_valid(_louhi_node):
		_louhi_node.queue_free()
		_louhi_node = null
	scenario_ended.emit(reason, tally)
