class_name QuestCatalog
extends RefCounted
## Static table of every authored quest. Same shape/rationale as
## `RelicCatalog`: a plain static builder returning fresh `Quest` resources
## rather than a cached singleton (lookups are rare — quest-log rendering,
## `CampaignManager`'s own boot pass — never a per-frame hot path).
##
## Ten quests: two culture-agnostic openers, one per culture (four), one
## cross-culture capstone gated on all four, and three that react to
## `actors/louhi/louhi_director.gd`'s three signs ("Louhi's approach," per
## this package's own brief). See docs/systems/campaign.md for the full
## table with exact trigger wiring and reward rationale.

static func _make(id: StringName, title: String, culture_id: StringName,
		description: String, prerequisites: Array[StringName],
		activation_trigger: StringName, completion_trigger: StringName,
		auto_complete_on_activate: bool, reward_relics: Array[StringName],
		reward_scrolls: Array[StringName], reward_epithet: String) -> Quest:
	var q := Quest.new()
	q.id = id
	q.title = title
	q.culture_id = culture_id
	q.description = description
	# .duplicate() on every incoming array: several calls below intentionally
	# pass the same empty `no_ids`/`no_rites` locals to multiple quests, and
	# Array is a reference type in GDScript — without duplicating here, every
	# quest that got the same "empty" convenience local would share one
	# Array object, so an in-place mutation on one quest's list (append,
	# erase) would silently leak into every other quest built from the same
	# call. Cheap (all lists here are tiny) and correct regardless of how
	# many call sites eventually build quests this way.
	q.prerequisites = prerequisites.duplicate()
	q.activation_trigger = activation_trigger
	q.completion_trigger = completion_trigger
	q.auto_complete_on_activate = auto_complete_on_activate
	q.reward_relics = reward_relics.duplicate()
	q.reward_scrolls = reward_scrolls.duplicate()
	q.reward_epithet = reward_epithet
	return q

## id -> Quest. Rebuilt fresh on every call (see class doc).
static func build() -> Dictionary:
	var no_ids: Array[StringName] = []
	var no_rites: Array[StringName] = []

	return {
		&"q_first_rite": _make(
			&"q_first_rite", "The First Rite", &"",
			"Something in the world just moved because a hand drew a shape in the air and meant it. No one has explained this to the villages yet. They'll work it out.",
			no_ids, &"", &"rite_cast_any", false,
			[&"waking_den_stone"], no_rites, ""
		),
		&"q_ninefold_tally": _make(
			&"q_ninefold_tally", "Keeper of the Tally", &"",
			"Every god who has ever answered a mortal here got a name for it, sooner or later. The cord keeps a knot for each. Earn your first, and see how it counts you.",
			no_ids, &"", &"first_epithet_earned", false,
			[&"ninefold_tally_cord"], no_rites, "Keeper of the Tally"
		),
		&"q_fenrayt_sinking_witness": _make(
			&"q_fenrayt_sinking_witness", "What the Bog Remembers", &"fenrayt",
			"The Fenrayt lower their best work into the black water every thaw and call it settled. A god who wants their trust doesn't ask what's down there. A god who earns it gets told anyway, eventually, in a Fenrayt's own unhurried time.",
			no_ids, &"", &"culture_village_converted", false,
			[&"fenrayt_raft_bell"], [&"repair"], "Kept the Bog's Trust"
		),
		&"q_sankiln_firereading": _make(
			&"q_sankiln_firereading", "Reader of Embers", &"sankiln",
			"Bank the hearth, throw in the grain, watch what color it turns. The Sankiln have been reading their own luck this way long before any god was listening. Convert a Sankiln household and earn the right to be told what the flame said about you.",
			no_ids, &"", &"culture_village_converted", false,
			[&"sankiln_firereading_bowl"], [&"fire_arrow"], "Reader of Embers"
		),
		&"q_raimborn_wavecall": _make(
			&"q_raimborn_wavecall", "Named by the Tide", &"raimborn",
			"Before any Raimborn crew launches, they hum one note into the surf and wait for an answer. Convert a Raimborn village, and the sea starts answering back with your name in it.",
			no_ids, &"", &"culture_village_converted", false,
			[&"raimborn_wavecall_horn"], [&"rain_call"], "Named by the Tide"
		),
		&"q_vainkeeper_grafting": _make(
			&"q_vainkeeper_grafting", "Grafted into the Grove", &"vainkeeper",
			"The Vainkeeper splice a name onto a young tree and let it carry that name forward instead of a stone. Earn a Vainkeeper village's devotion, and they'll graft yours in too.",
			no_ids, &"", &"culture_village_converted", false,
			[&"vainkeeper_grafting_knife"], [&"harvest"], "Grafted into the Grove"
		),
		&"q_four_debts_remembered": _make(
			&"q_four_debts_remembered", "The Four Warnings", &"",
			"Every one of the four peoples keeps its own name for the same old crime: a debt paid in something alive and unwilling. None of them needed a god to tell them it was wrong. Having heard all four warn you unprompted, in their own words, is the only qualification that matters here.",
			[&"q_fenrayt_sinking_witness", &"q_sankiln_firereading", &"q_raimborn_wavecall", &"q_vainkeeper_grafting"],
			&"", &"", true,
			[&"warning_staves_bundle"], [&"storm"], "Keeper of the Four Warnings"
		),
		&"q_louhi_cold_wind": _make(
			&"q_louhi_cold_wind", "Louhi's Approach: The Cold Wind", &"",
			"A front rolls in out of the north with no storm behind it, just a long watching stillness over one of your villages. She hasn't taken anything yet. She's deciding whether it's worth taking.",
			no_ids, &"louhi_tier1", &"louhi_tier1_resolved", false,
			no_ids, no_rites, "Weathered Her Watching"
		),
		&"q_louhi_silence": _make(
			&"q_louhi_silence", "Louhi's Approach: The Silence", &"",
			"No word is coming back from the village she'd been watching, and none will. There's nothing left there to defend. There might still be something left to answer.",
			no_ids, &"louhi_tier2", &"louhi_tier3", false,
			no_ids, no_rites, "Remembers the Silence"
		),
		&"q_louhi_reckoning": _make(
			&"q_louhi_reckoning", "Louhi's Approach: The Reckoning", &"",
			"By morning something is simply gone from wherever it was kept — or, if there was nothing left worth taking, she's named her price instead and is waiting on an answer. Either way, she's shown her hand for this round.",
			no_ids, &"louhi_tier3", &"", true,
			no_ids, no_rites, "Marked by Pohjola"
		),
	}

static func get_quest(id: StringName) -> Quest:
	return build().get(id, null)

static func get_all_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for k in build().keys():
		out.append(k)
	return out
