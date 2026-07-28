extends Node
class_name CampaignManager
## The quest log, relic ledger, and scroll bookkeeping for the campaign —
## package S's territory (`campaign/`). Same shape as
## `actors/louhi/louhi_director.gd`: a real, complete, instantiable manager
## class that is **not registered as an autoload** (package S may not edit
## `project.godot`) and is **not currently instanced anywhere** in the
## shipped scene tree. `campaign/campaign_manager.tscn` is a ready-to-instance
## one-node wrapper, exactly like `actors/louhi/louhi_director.tscn`. See
## docs/systems/campaign.md for exactly how to wire this in, and its own
## "Scoped out" section for what that implies until someone does.
##
## THREE JOBS, ONE MANAGER:
##  1. Quests — `QuestCatalog`-authored `Quest` resources, tracked here as
##     LOCKED / ACTIVE / COMPLETE per playthrough (`QuestState`).
##  2. Relics — resolves `GameState.relics_held` ids against `RelicCatalog`
##     and grants new ones (quest rewards, or a future discovery mechanic).
##  3. Scrolls — thin wrapper around the stateless `ScrollBook` utility for
##     `GameState.scrolls_known` / the nine `SigilTemplates` rite ids.
##
## EVENT MODEL: quests activate/complete off small, campaign-local event
## names (never the same vocabulary as `Voices.react()` triggers or
## `GameState`/`LouhiDirector` signals, even where a campaign event is fired
## *from* one of those) rather than being polled every frame. The full
## vocabulary, and what fires each one:
##   &"any_village_converted"        — GameState.village_converted, any culture
##   &"culture_village_converted"    — GameState.village_converted, filtered
##                                      to the quest's own culture_id
##   &"first_epithet_earned"         — GameState.epithet_earned, only the
##                                      very first epithet a save ever earns
##   &"rite_cast_any"                — notify_rite_cast() — see the flagged
##                                      hook on that method below
##   &"louhi_tier1"                  — LouhiDirector.sign_occurred(tier=1)
##   &"louhi_tier1_resolved"         — LouhiDirector.sign_relented(from_tier=1)
##                                      OR sign_occurred(tier=2) (either way
##                                      the tier-1 engagement is over)
##   &"louhi_tier2"                  — LouhiDirector.sign_occurred(tier=2)
##   &"louhi_tier3"                  — LouhiDirector.sign_occurred(tier=3)
## `Quest.activation_trigger`/`Quest.completion_trigger` reference these by
## name; `""` means "not event-gated" (see quest.gd's own doc for the two
## different meanings that takes for activation vs completion).

signal quest_activated(quest_id: StringName)
signal quest_completed(quest_id: StringName)
signal relic_gained(relic_id: StringName)
signal scroll_learned(rite_id: StringName)

enum QuestState { LOCKED, ACTIVE, COMPLETE }

## Master switch for the automatic event->quest reactions below (village
## conversions, epithets, Louhi's signs). Public API — complete_quest(),
## grant_relic(), learn_scroll(), start_quest() — stays callable regardless,
## exactly like LouhiDirector's own `enabled` only gates her `_process` loop,
## not her public methods.
@export var enabled: bool = true

var _quest_defs: Dictionary = {} # StringName -> Quest
var _quest_states: Dictionary = {} # StringName -> QuestState
var _louhi: Node = null


func _ready() -> void:
	_quest_defs = QuestCatalog.build()
	for quest_id in _quest_defs.keys():
		_quest_states[quest_id] = QuestState.LOCKED

	if not has_node("/root/GameState"):
		push_warning("CampaignManager: /root/GameState not found — quests reacting to conversions/epithets will no-op.")
	else:
		# GameState is a foundation-registered autoload (docs/systems/
		# OWNERSHIP.md), so this connection is made unconditionally once
		# confirmed present, the same way systems/faith/reach.gd and
		# systems/voices/voice_lines.gd already assume it's live rather than
		# re-checking on every call.
		GameState.village_converted.connect(_on_village_converted)
		GameState.epithet_earned.connect(_on_epithet_earned)

	_try_autodiscover_louhi()
	_try_activate_available_quests()


# ---------------------------------------------------------------------------
# Quest queries
# ---------------------------------------------------------------------------

func get_quest_def(quest_id: StringName) -> Quest:
	return _quest_defs.get(quest_id, null)

func get_quest_state(quest_id: StringName) -> QuestState:
	return _quest_states.get(quest_id, QuestState.LOCKED)

## LOCKED, but every prerequisite is already COMPLETE — i.e. it would
## activate on its own the moment its activation_trigger (if any) fires, or
## can be force-started right now via start_quest().
func is_quest_available(quest_id: StringName) -> bool:
	if get_quest_state(quest_id) != QuestState.LOCKED:
		return false
	var q: Quest = _quest_defs.get(quest_id, null)
	return q != null and _prerequisites_met(q)

func get_all_quest_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for k in _quest_defs.keys():
		out.append(k)
	return out

func get_active_quests() -> Array[StringName]:
	return _quests_in_state(QuestState.ACTIVE)

func get_completed_quests() -> Array[StringName]:
	return _quests_in_state(QuestState.COMPLETE)

func get_locked_quests() -> Array[StringName]:
	return _quests_in_state(QuestState.LOCKED)

func _quests_in_state(state: QuestState) -> Array[StringName]:
	var out: Array[StringName] = []
	for quest_id in _quest_defs.keys():
		if _quest_states.get(quest_id, QuestState.LOCKED) == state:
			out.append(quest_id)
	return out


# ---------------------------------------------------------------------------
# Quest activation / completion
# ---------------------------------------------------------------------------

## Manual/debug override: activates quest_id right now if it's LOCKED and its
## prerequisites are met, regardless of its activation_trigger. Most quests
## in QuestCatalog activate on their own (empty trigger + prereqs met, or a
## matching campaign event); this exists for a future dialogue/debug hook
## that wants to force a start without waiting for the natural trigger.
func start_quest(quest_id: StringName) -> bool:
	if not is_quest_available(quest_id):
		return false
	_activate_quest(quest_id)
	return true

## Completes an ACTIVE quest, grants its rewards, and re-checks every LOCKED
## quest's prerequisites (so a capstone quest gated on this one can activate
## in the same call). Public: quests with no completion_trigger are only
## ever finished by some other system calling this directly (e.g. a future
## "hand the elder the bell" interaction).
func complete_quest(quest_id: StringName) -> bool:
	if not _quest_defs.has(quest_id):
		push_warning("CampaignManager.complete_quest: unknown quest id %s" % quest_id)
		return false
	if _quest_states.get(quest_id, QuestState.LOCKED) != QuestState.ACTIVE:
		return false

	var q: Quest = _quest_defs[quest_id]
	_quest_states[quest_id] = QuestState.COMPLETE
	_grant_rewards(q)
	quest_completed.emit(quest_id)
	Voices.react(&"quest_completed", {"quest_id": quest_id, "quest_title": q.title})
	_try_activate_available_quests()
	return true

func _activate_quest(quest_id: StringName) -> void:
	if _quest_states.get(quest_id, QuestState.LOCKED) != QuestState.LOCKED:
		return
	var q: Quest = _quest_defs[quest_id]
	_quest_states[quest_id] = QuestState.ACTIVE
	quest_activated.emit(quest_id)
	Voices.react(&"quest_activated", {"quest_id": quest_id, "quest_title": q.title})
	if q.auto_complete_on_activate:
		complete_quest(quest_id)

func _prerequisites_met(q: Quest) -> bool:
	for prereq_id in q.prerequisites:
		if _quest_states.get(prereq_id, QuestState.LOCKED) != QuestState.COMPLETE:
			return false
	return true

## Activates every LOCKED quest with an empty activation_trigger whose
## prerequisites are now all COMPLETE. Called once at _ready() (the boot
## pass — picks up the always-on opener quests and anything already
## satisfied) and again after every complete_quest() (so a capstone quest
## chained onto other quests activates the instant its last prerequisite
## lands, without polling).
func _try_activate_available_quests() -> void:
	for quest_id in _quest_defs.keys():
		if _quest_states.get(quest_id, QuestState.LOCKED) != QuestState.LOCKED:
			continue
		var q: Quest = _quest_defs[quest_id]
		if q.activation_trigger != &"":
			continue
		if _prerequisites_met(q):
			_activate_quest(quest_id)

func _grant_rewards(q: Quest) -> void:
	for relic_id in q.reward_relics:
		grant_relic(relic_id)
	for rite_id in q.reward_scrolls:
		learn_scroll(rite_id)
	if q.reward_epithet != "":
		GameState.earn_epithet(q.reward_epithet, "quest:" + String(q.id))


# ---------------------------------------------------------------------------
# Campaign event dispatch — the activation_trigger/completion_trigger engine
# ---------------------------------------------------------------------------

## Fires one campaign event by name: activates every eligible LOCKED quest
## whose activation_trigger matches (prerequisites permitting), then
## completes every ACTIVE quest whose completion_trigger matches — in that
## order, so a quest that both activates AND resolves on the same event
## (auto_complete_on_activate, or a capstone chained the same tick) settles
## within one call rather than needing a second event to catch up.
## culture_filter is only consulted for &"culture_village_converted" (see
## _on_village_converted below); every other event ignores it.
func _fire_campaign_event(event_name: StringName, culture_filter: StringName = &"") -> void:
	if not enabled:
		return

	for quest_id in _quest_defs.keys():
		if _quest_states.get(quest_id, QuestState.LOCKED) != QuestState.LOCKED:
			continue
		var q: Quest = _quest_defs[quest_id]
		if q.activation_trigger != event_name:
			continue
		if event_name == &"culture_village_converted" and culture_filter != &"" and q.culture_id != culture_filter:
			continue
		if _prerequisites_met(q):
			_activate_quest(quest_id)

	for quest_id in _quest_defs.keys():
		if _quest_states.get(quest_id, QuestState.LOCKED) != QuestState.ACTIVE:
			continue
		var q: Quest = _quest_defs[quest_id]
		if q.completion_trigger != event_name:
			continue
		if event_name == &"culture_village_converted" and culture_filter != &"" and q.culture_id != culture_filter:
			continue
		complete_quest(quest_id)


func _on_village_converted(village_id: StringName) -> void:
	_fire_campaign_event(&"any_village_converted")
	var v: Village = GameState.get_village(village_id)
	if v:
		_fire_campaign_event(&"culture_village_converted", v.culture_id)

func _on_epithet_earned(_epithet_text: String, _reason: String) -> void:
	# Only the very first epithet a save ever earns fires q_ninefold_tally —
	# GameState.earn_epithet() appends to `epithets` before emitting, so
	# size() == 1 here means this is that first one.
	if GameState.epithets.size() == 1:
		_fire_campaign_event(&"first_epithet_earned")

## FLAGGED CROSS-PACKAGE HOOK for whoever wires SigilCaster into a scene
## (package E/F's territory): `systems/sigils/sigil_caster.gd` fires
## `rite_cast(rite_id, confidence)` on every successful cast, but this
## package may not edit systems/sigils/ to connect to it, and SigilCaster is
## a scene component (not an autoload, not instanced at any fixed path) so
## there's no reliable path to auto-discover it the way `_try_autodiscover_louhi()`
## does for a `/root`-adjacent autoload candidate. Whatever integration pass
## instances a SigilCaster should also call, once:
##   sigil_caster.rite_cast.connect(func(rite_id, _confidence): campaign_manager.notify_rite_cast(rite_id))
## Until that connection exists, q_first_rite (the only quest keyed to this
## event) simply never auto-completes — see docs/systems/campaign.md's
## "Scoped out" section.
func notify_rite_cast(rite_id: StringName) -> void:
	_fire_campaign_event(&"rite_cast_any")


# ---------------------------------------------------------------------------
# LouhiDirector integration — defensive, exactly like her own DuelArena call
# ---------------------------------------------------------------------------

## Best-effort discovery for whenever an integration pass instances
## LouhiDirector (actors/louhi/louhi_director.gd, package N) — she is NOT an
## autoload and is NOT currently instanced anywhere in the shipped scene
## tree (docs/systems/louhi.md's "Instancing her"), so this may find nothing,
## which is fine: the three Louhi-reactive quests then simply never
## activate, same honest silence her own signals already default to when
## nothing is listening.
func _try_autodiscover_louhi() -> void:
	var candidate := get_node_or_null("/root/LouhiDirector")
	if candidate == null and get_tree() != null:
		candidate = get_tree().get_root().find_child("LouhiDirector", true, false)
	if candidate:
		attach_to_louhi(candidate)

## Public, explicit alternative to the auto-discovery above: whatever
## integration pass instances both this node and LouhiDirector can call this
## directly instead of relying on the path/name guess (e.g. if she ends up
## nested somewhere auto-discovery won't find). Connects defensively
## (has_signal check per signal) exactly like _attempt_duel_challenge() in
## louhi_director.gd checks has_method() before calling out — the direction
## is just reversed here (campaign/ is the listener, not the caller).
func attach_to_louhi(louhi: Node) -> void:
	if louhi == null or louhi == _louhi:
		return
	_louhi = louhi
	if louhi.has_signal("sign_occurred"):
		louhi.connect("sign_occurred", Callable(self, "_on_louhi_sign_occurred"))
	if louhi.has_signal("sign_relented"):
		louhi.connect("sign_relented", Callable(self, "_on_louhi_sign_relented"))

func _on_louhi_sign_occurred(tier: int, _village_id: StringName, _description: String) -> void:
	match tier:
		1:
			_fire_campaign_event(&"louhi_tier1")
		2:
			_fire_campaign_event(&"louhi_tier1_resolved") # the tier-1 engagement is over, one way or the other
			_fire_campaign_event(&"louhi_tier2")
		3:
			_fire_campaign_event(&"louhi_tier3")

func _on_louhi_sign_relented(_village_id: StringName, from_tier: int) -> void:
	if from_tier == 1:
		_fire_campaign_event(&"louhi_tier1_resolved")


# ---------------------------------------------------------------------------
# Relics
# ---------------------------------------------------------------------------

## Appends relic_id to GameState.relics_held if not already held, grants its
## `Relic.grants_epithet` epithet if it has one, and emits relic_gained.
## Returns false (no-op) if already held. Safe to call with an id
## RelicCatalog doesn't recognize (grants the bare id, warns) rather than
## silently dropping it — GameState.relics_held has no schema of its own to
## enforce, this is just this package's own sanity check on itself.
func grant_relic(relic_id: StringName) -> bool:
	if relic_id in GameState.relics_held:
		return false
	if not RelicCatalog.exists(relic_id):
		push_warning("CampaignManager.grant_relic: %s is not in RelicCatalog — granting the bare id anyway." % relic_id)
	GameState.relics_held.append(relic_id)
	relic_gained.emit(relic_id)
	Voices.react(&"relic_found", {"relic_id": relic_id})
	var data := RelicCatalog.get_relic(relic_id)
	if data and data.grants_epithet != "":
		GameState.earn_epithet(data.grants_epithet, "relic:" + String(relic_id))
	return true

func get_relic_data(relic_id: StringName) -> Relic:
	return RelicCatalog.get_relic(relic_id)

## GameState.relics_held resolved to real Relic data, skipping any id
## RelicCatalog doesn't recognize (defensive — e.g. a save file from a
## future pass with more relics than this catalog knows about).
func get_held_relics() -> Array[Relic]:
	var out: Array[Relic] = []
	for relic_id in GameState.relics_held:
		var data := RelicCatalog.get_relic(relic_id)
		if data:
			out.append(data)
	return out


# ---------------------------------------------------------------------------
# Scrolls — thin wrappers around the stateless ScrollBook utility, kept here
# too so a caller that already holds a CampaignManager reference gets the
# scroll_learned signal/Voices remark for free instead of calling
# ScrollBook directly (which stays available for anyone who doesn't need
# those and just wants the plain query — see scroll_book.gd's own doc).
# ---------------------------------------------------------------------------

func is_rite_unlocked(rite_id: StringName) -> bool:
	return ScrollBook.is_rite_unlocked(rite_id)

func learn_scroll(rite_id: StringName) -> bool:
	if not ScrollBook.learn_scroll(rite_id):
		return false
	scroll_learned.emit(rite_id)
	Voices.react(&"scroll_learned", {"rite_id": rite_id})
	return true
