extends Node
class_name LouhiDirector
## Louhi of Pohjola — the other god. Presence-first AI: she is weather and
## silence before she is ever a fight. Per docs/audit/respect_audit.md she
## is drawn straight from her own *Kalevala* role and MUST stay: patient,
## acquisitive, a hoarder and a bargainer. Never a scripted cutscene boss,
## never a mustache-twirler, never announced by UI text — every escalation
## below is a *sign* left in the world (weather, a village's silence, a
## missing relic) surfaced only through signals so other systems can render
## it diegetically. If nothing consumes a signal, nothing happens on
## screen; that silence is itself in character.
##
## THIS NODE IS NOT AN AUTOLOAD. `actors/louhi/` (package N) may not edit
## project.godot, so LouhiDirector has to be instanced somewhere in the
## scene tree by an integration pass (e.g. as a child of world/god_view.tscn,
## or promoted to a project.godot autoload later) — see
## `actors/louhi/louhi_director.tscn` for a ready-to-instance wrapper, and
## docs/systems/louhi.md for exactly how to wire it in.
##
## THE MODEL: a slow utility-AI loop, not a state machine wired to scripted
## beats. Every `evaluation_interval_sec` (minutes, not seconds — patience
## is the entire point) she either:
##   - (tier 0, dormant/scouting) looks at every converted village GameState
##     knows about and scores how exposed each one is, weighting low
##     faith_fraction and low Reach.radius_for_village per the brief; or
##   - (tier 1/2, already engaged with a target) checks whether that
##     village's owner has shored it up enough that she should relent, and
##     otherwise waits out her patience timer before escalating.
## She commits to exactly one target at a time once engaged (tiers 1-2) —
## she does not flit to a shinier target mid-approach; that would read as
## impulsive, which she isn't. She only ever picks a *new* target from
## tier 0 (dormant/scouting).

# --- Signals -----------------------------------------------------------
## Fired every time a sign lands. tier: 1 (cold front), 2 (village goes
## silent), 3 (relic stolen / duel challenge issued). village_id is the
## village the sign is about or was provoked by (tier 3's mechanic is
## global — see _fire_tier3 — but the id is kept for narrative continuity:
## "since that village fell, she's grown bold enough to..."). description
## is a short, human-readable line intended for logging / diegetic display
## (subtitles-off worldbuilding, a debug overlay, etc) — never shown as
## popup UI per the brief.
signal sign_occurred(tier: int, village_id: StringName, description: String)

## Fired when she backs off a target instead of escalating further, because
## the village's owner visibly reinforced it (faith_fraction rose enough
## since she started watching). from_tier is the tier she was at when she
## relented. This is as important to her characterization as sign_occurred:
## a bargainer only presses when the odds are hers.
signal sign_relented(village_id: StringName, from_tier: int)

## Fired the moment she commits to a new target and starts watching it,
## *before* tier 1 actually fires (which happens on the same evaluation
## tick, immediately after). Lets ambient systems (music, lighting) begin
## a slow diegetic mood shift a beat ahead of the visible sign, rather than
## snapping.
signal engagement_began(village_id: StringName)

# --- Tuning: target selection -------------------------------------------
## How often she looks at the board at all. This is deliberately long:
## she is not polling for an opening every few seconds like a combat AI.
@export var evaluation_interval_sec: float = 75.0

## A village with less devotion than this isn't "converted" enough to be
## worth her notice yet — an empty, untouched village isn't a target,
## it's just unclaimed.
@export var min_faith_fraction_to_notice: float = 0.05

## A village at or above this faith_fraction is defended well enough that
## contesting it isn't worth the effort to a patient bargainer; she waits
## for a better opening elsewhere. 0.999 effectively means "only a
## genuinely maxed-out village is safe," matching Village.is_fully_converted().
@export var ignore_above_faith_fraction: float = 0.999

## Utility-score weights for "how exposed is this village" — lower
## faith_fraction and lower Reach both count as exposure; either weight can
## be set to 0.0 to degenerate to a single-metric evaluator if a later pass
## wants that instead of the blended default.
@export var faith_weight: float = 0.6
@export var reach_weight: float = 0.4

## Meters used to normalize Reach.radius_for_village() into a 0..1 exposure
## term comparable to faith_fraction. Tuned loosely against the reach
## curve in systems/faith/reach.gd (BASE_REACH_PER_HEAD); revisit if that
## curve changes substantially.
@export var reach_normalization_m: float = 80.0

# --- Tuning: patience / escalation ---------------------------------------
## How long (seconds) she waits at tier 1 (cold front already sent) before
## escalating to tier 2, absent a relent. Minutes-scale on purpose.
@export var tier1_patience_sec: float = 300.0 # 5 minutes

## How long she waits at tier 2 (village already gone silent) before firing
## tier 3 (the relic theft / duel). There's nothing left for the player to
## defend on this front by this point — see _check_tier2() — so this is a
## pure "how long she savors it before acting" timer, not a contest.
@export var tier2_patience_sec: float = 420.0 # 7 minutes

## If the target's faith_fraction has risen by at least this much since she
## started watching it (tier 1 only — see class doc), she relents instead
## of escalating: the player visibly reinforced the village and a bargainer
## doesn't press a bad trade.
@export var relent_improvement_threshold: float = 0.07

## After relenting on a village, how long before she'll consider it again
## as a candidate target. Keeps her from immediately re-picking the village
## that just rebuffed her, without permanently writing it off.
@export var rebuff_cooldown_sec: float = 900.0 # 15 minutes

## After a tier-3 sign resolves (win or lose), how long she stays fully
## dormant before scouting for a new target at all. She takes her prize
## (or accepts the rebuff) and goes quiet — patience runs in both
## directions.
@export var post_resolution_cooldown_sec: float = 600.0 # 10 minutes

# --- Tuning: tier 1 cold front -------------------------------------------
## Cosmetic-only weather nudge written directly into Weather.current (see
## systems/weather/weather.gd). Documented contract this was built against:
## a plain Dictionary with keys wind_dir_deg/wind_speed/precipitation/
## cloud_cover/temperature_c/is_storm/source. If package P has since
## replaced the stub with a live simulation that overwrites `current` every
## frame, a tier-1 write here may get stomped almost immediately — see
## "Scoped out" in docs/systems/louhi.md for the follow-up this implies.
@export var cold_front_wind_dir_deg: float = 0.0 # "out of the north" — her north, Pohjola
@export var cold_front_wind_speed: float = 9.0
@export var cold_front_cloud_cover: float = 0.75
@export var cold_front_temperature_c: float = 2.0
@export var cold_front_precipitation: float = 0.15 # a sign, not a storm — is_storm stays false
@export var cold_front_duration_sec: float = 240.0 # 4 minutes, then it eases back on its own

@export var enabled: bool = true

# --- State ----------------------------------------------------------------
var _current_target_id: StringName = &""
var _current_tier: int = 0 # 0 = dormant/scouting, 1 or 2 = engaged and waiting
var _tier_started_faith: float = 0.0
var _tier_elapsed: float = 0.0
var _eval_elapsed: float = 0.0

var _in_cooldown: bool = false
var _cooldown_elapsed: float = 0.0

## village_id -> unix-ish time (Time.get_ticks_msec()/1000.0) before which
## she won't reconsider that village as a target after relenting on it.
var _rebuffed_until: Dictionary = {}

var _cold_front_active: bool = false
var _cold_front_elapsed: float = 0.0
var _cached_weather: Dictionary = {}


func _ready() -> void:
	if not has_node("/root/GameState"):
		push_warning("LouhiDirector: /root/GameState not found — she has no board to watch.")
	if not has_node("/root/Weather"):
		push_warning("LouhiDirector: /root/Weather not found — tier 1 cold-front signs will no-op.")
	if not has_node("/root/Voices"):
		push_warning("LouhiDirector: /root/Voices not found — signs will fire silently (signals still emit).")


func _process(delta: float) -> void:
	if not enabled:
		return

	_eval_elapsed += delta
	if _current_tier > 0:
		_tier_elapsed += delta

	if _in_cooldown:
		_cooldown_elapsed += delta
		if _cooldown_elapsed >= post_resolution_cooldown_sec:
			_in_cooldown = false
			_cooldown_elapsed = 0.0

	if _cold_front_active:
		_cold_front_elapsed += delta
		if _cold_front_elapsed >= cold_front_duration_sec:
			_revert_cold_front()

	if _eval_elapsed >= evaluation_interval_sec:
		_eval_elapsed = 0.0
		_evaluate()


func _evaluate() -> void:
	match _current_tier:
		0:
			if not _in_cooldown:
				_scout()
		1:
			_check_tier1()
		2:
			_check_tier2()


# ---------------------------------------------------------------------------
# Target selection (tier 0)
# ---------------------------------------------------------------------------

func _scout() -> void:
	var candidate := _find_weakest_converted_village()
	if candidate == null:
		return
	_begin_engagement(candidate)


## Utility scoring: among villages she'd bother with at all, lower
## faith_fraction and lower Reach both increase exposure. Returns null if
## nothing on the board is worth her attention right now.
func _find_weakest_converted_village() -> Village:
	var best: Village = null
	var best_score := INF
	var now := Time.get_ticks_msec() / 1000.0

	for v in GameState.villages.values():
		var village: Village = v
		if village.loyal_to_rival:
			continue # already hers
		if village.faith_fraction < min_faith_fraction_to_notice:
			continue # nothing devoted enough here yet to be worth taking
		if village.faith_fraction >= ignore_above_faith_fraction:
			continue # too well defended to be a good trade
		var rebuff_expiry: float = _rebuffed_until.get(village.id, 0.0)
		if rebuff_expiry > now:
			continue # rebuffed here recently; let it be for a while

		var reach := Reach.radius_for_village(village.id)
		var normalized_reach := clampf(reach / maxf(reach_normalization_m, 0.001), 0.0, 1.0)
		var score := village.faith_fraction * faith_weight + normalized_reach * reach_weight
		if score < best_score:
			best_score = score
			best = village

	return best


func _begin_engagement(v: Village) -> void:
	_current_target_id = v.id
	_current_tier = 1
	_tier_elapsed = 0.0
	_tier_started_faith = v.faith_fraction
	engagement_began.emit(v.id)
	_fire_tier1(v)


# ---------------------------------------------------------------------------
# Tier 1 — cold front
# ---------------------------------------------------------------------------

func _fire_tier1(v: Village) -> void:
	_apply_cold_front()
	var desc := "A cold front rolls in over %s out of the north, with no storm behind it — just a long, watching stillness." % v.display_name
	sign_occurred.emit(1, v.id, desc)
	if has_node("/root/Voices"):
		Voices.react(&"louhi_sighted", {"village_id": v.id})


func _check_tier1() -> void:
	var v: Village = GameState.get_village(_current_target_id)
	if v == null or v.loyal_to_rival:
		# Target left the board some other way (shouldn't normally happen —
		# GameState never removes villages — but stay defensive).
		_abandon_engagement()
		return

	if v.faith_fraction - _tier_started_faith >= relent_improvement_threshold:
		_relent(v, 1)
		return

	if _tier_elapsed >= tier1_patience_sec:
		_escalate_to_tier2(v)


func _apply_cold_front() -> void:
	if not has_node("/root/Weather"):
		return
	if not _cold_front_active:
		_cached_weather = Weather.current.duplicate(true)
	_cold_front_active = true
	_cold_front_elapsed = 0.0

	var w: Dictionary = Weather.current.duplicate(true)
	w["wind_dir_deg"] = cold_front_wind_dir_deg
	w["wind_speed"] = maxf(float(w.get("wind_speed", 2.0)), cold_front_wind_speed)
	w["cloud_cover"] = clampf(maxf(float(w.get("cloud_cover", 0.2)), cold_front_cloud_cover), 0.0, 1.0)
	w["temperature_c"] = minf(float(w.get("temperature_c", 15.0)), cold_front_temperature_c)
	w["precipitation"] = clampf(maxf(float(w.get("precipitation", 0.0)), cold_front_precipitation), 0.0, 1.0)
	w["is_storm"] = false # she is a sign, not a tantrum — withholding, not raging
	w["source"] = "louhi_sign"
	Weather.current = w
	Weather.weather_changed.emit(Weather.current)


func _revert_cold_front() -> void:
	_cold_front_active = false
	if not has_node("/root/Weather"):
		return
	if String(Weather.current.get("source", "")) == "louhi_sign":
		Weather.current = _cached_weather.duplicate(true)
		Weather.weather_changed.emit(Weather.current)


# ---------------------------------------------------------------------------
# Tier 2 — the village goes silent
# ---------------------------------------------------------------------------

func _escalate_to_tier2(v: Village) -> void:
	_current_tier = 2
	_tier_elapsed = 0.0
	_tier_started_faith = v.faith_fraction

	# The single mechanism Village exposes for "this is Louhi's now" is
	# loyal_to_rival — it works identically whether the village had never
	# been converted at all (faith_fraction == 0, she simply claims an
	# unclaimed village before the player ever reached it) or was partway
	# converted to the player (the case this director's own target
	# selection actually produces, since _find_weakest_converted_village()
	# only considers villages with faith_fraction >= min_faith_fraction_to_notice).
	# There is no separate "pre-conversion" flag in core/village.gd, and none
	# is needed: one boolean covers both, so this director uses it uniformly.
	v.loyal_to_rival = true
	GameState.village_lost.emit(v.id)

	var desc := "%s has gone silent. No word comes back from it, and none will." % v.display_name
	sign_occurred.emit(2, v.id, desc)
	if has_node("/root/Voices"):
		Voices.react(&"village_lost", {"village_id": v.id})


func _check_tier2() -> void:
	# No relent check here: once loyal_to_rival is true, Reach.radius_for_village
	# returns 0 for this village and every conversion method in reach.gd
	# short-circuits on `v.loyal_to_rival` — there is currently no reclaim
	# mechanic anywhere in the codebase for the player to contest this with,
	# so tier 2 is a one-way door and this timer is purely "how long she
	# savors it" before moving on to tier 3, not a contest to be won back.
	if _tier_elapsed >= tier2_patience_sec:
		var v: Village = GameState.get_village(_current_target_id)
		if v == null:
			_resolve_engagement()
			return
		_fire_tier3(v)


# ---------------------------------------------------------------------------
# Tier 3 — stolen relic, or a duel challenge
# ---------------------------------------------------------------------------

## Tier 3's mechanic is deliberately global rather than village-local: by
## this point the named village is already gone (tier 2), so what's left
## for her to take is either a relic from the player's own hoard
## (GameState.relics_held) or, if there's nothing left worth taking, a
## direct challenge. `v` is passed only for the narrative line.
func _fire_tier3(v: Village) -> void:
	var desc: String
	if not GameState.relics_held.is_empty():
		var idx := randi() % GameState.relics_held.size()
		var stolen: StringName = GameState.relics_held[idx]
		GameState.relics_held.remove_at(idx)
		desc = "By morning, %s is simply gone from wherever it was kept, and no one heard a thing — not since %s." % [String(stolen), v.display_name]
		sign_occurred.emit(3, v.id, desc)
		if has_node("/root/Voices"):
			Voices.react(&"louhi_relic_stolen", {"village_id": v.id, "relic": stolen})
	else:
		var challenged := _attempt_duel_challenge(v)
		if challenged:
			desc = "There is nothing left worth stealing, so Louhi asks for a reckoning instead. She names her price and waits."
		else:
			desc = "There is nothing left worth stealing, and no one yet standing who could answer a reckoning. She waits anyway. She is very good at waiting."
		sign_occurred.emit(3, v.id, desc)
		if has_node("/root/Voices"):
			Voices.react(&"louhi_duel_challenge", {"village_id": v.id})

	_resolve_engagement()


## Package L (actors/avatar/combat/) had not landed yet when this was
## written (actors/avatar/combat/ was empty). Documented contract this
## director builds against, defensively: an autoload or /root node named
## "DuelArena" exposing `request_challenge(instigator: StringName,
## defender_village_id: StringName, stakes: Dictionary) -> void`. If L
## lands with a different name/signature, either update this method or
## have L's node also answer to that name — see docs/systems/louhi.md.
## Returns true if a challenge was actually issued.
func _attempt_duel_challenge(v: Village) -> bool:
	var arena := get_node_or_null("/root/DuelArena")
	if arena == null:
		return false
	if not arena.has_method("request_challenge"):
		return false
	arena.call("request_challenge", &"louhi", v.id, {"reason": "tier3_reckoning"})
	return true


# ---------------------------------------------------------------------------
# Relenting / resolving / abandoning
# ---------------------------------------------------------------------------

func _relent(v: Village, from_tier: int) -> void:
	sign_relented.emit(v.id, from_tier)
	if has_node("/root/Voices"):
		Voices.react(&"louhi_sighted", {"village_id": v.id})
	_rebuffed_until[v.id] = (Time.get_ticks_msec() / 1000.0) + rebuff_cooldown_sec
	if _cold_front_active:
		_revert_cold_front()
	_current_target_id = &""
	_current_tier = 0
	_tier_elapsed = 0.0
	_in_cooldown = true
	_cooldown_elapsed = 0.0


func _resolve_engagement() -> void:
	_current_target_id = &""
	_current_tier = 0
	_tier_elapsed = 0.0
	_in_cooldown = true
	_cooldown_elapsed = 0.0


func _abandon_engagement() -> void:
	if _cold_front_active:
		_revert_cold_front()
	_current_target_id = &""
	_current_tier = 0
	_tier_elapsed = 0.0
	_in_cooldown = true
	_cooldown_elapsed = 0.0


# ---------------------------------------------------------------------------
# Public read-only queries (for diegetic consumers — HUD-less by design, so
# these exist for e.g. ambient audio/lighting systems that want to know
# "is something wrong right now" without caring about her internals)
# ---------------------------------------------------------------------------

func get_current_target() -> StringName:
	return _current_target_id

func get_current_tier() -> int:
	return _current_tier

func is_engaged() -> bool:
	return _current_tier > 0

func is_dormant() -> bool:
	return _current_tier == 0 and not _in_cooldown


## Debug/QA hook only: forces the next evaluation to happen on the very
## next frame instead of waiting out evaluation_interval_sec. Not called
## anywhere in this package; exists so a future test harness or campaign
## scripting beat doesn't have to wait out real minutes to see her act.
func debug_force_evaluate() -> void:
	_eval_elapsed = evaluation_interval_sec
