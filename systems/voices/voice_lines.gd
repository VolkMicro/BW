class_name VoiceLinePool
## The Two Voices' actual content: Domovoi (hearth spirit — fussy, practical,
## endlessly disappointed; keeps the ledger nobody asked for) and Hiisi
## (forest trickster, half-raven half-fox, theatrical, convinced every
## problem — political, spiritual, structural — is solved by eating someone
## or something). They speak in back-to-back PAIRS: Domovoi reacts first,
## Hiisi answers, needling him.
##
## COMEDIC-TARGET RULE (audited, veto power): every joke lands on the
## player's own bureaucracy/hypocrisy running this operation, or on the two
## advisors' own absurdity (Domovoi's fussiness, Hiisi's appetite). Never on
## real belief, real ritual, or real people. The "Debt" names below
## (Offering-Debt, Ash-Debt, Keel-Debt, Root-Debt) are the invented tribal
## taboos already canon in data/cultures/*.tres — not stand-ins for any real
## rite.
##
## See docs/systems/voices_content.md for the full trigger list and how the
## anti-repeat logic works.

class VoiceLine:
	var id: String
	var speaker: StringName
	var text: String
	func _init(p_id: String, p_speaker: StringName, p_text: String) -> void:
		id = p_id
		speaker = p_speaker
		text = p_text

const DOMOVOI := &"domovoi"
const HIISI := &"hiisi"

## culture_id -> the invented taboo name that culture's elders use for "a
## living, willing-or-not sacrifice" (see each culture's taboo_notes). Used
## to make offering_taboo commentary specific instead of generic.
const _DEBT_NAMES := {
	&"fenrayt": "Offering-Debt",
	&"sankiln": "Ash-Debt",
	&"raimborn": "Keel-Debt",
	&"vainkeeper": "Root-Debt",
}

## finish_type (from combat/duel_arena.gd's `_end_duel`) -> a phrase that
## reads as English inside a sentence, so "{finish}" never ships a raw
## snake_case id into a spoken line.
const _FINISH_PHRASES := {
	"finished_while_downed": "with the loser already on the ground",
	"defeated_in_exchange": "in a straight exchange",
	"timeout": "on the timer",
	"timeout_draw": "in a draw on the timer",
	"double_defeat": "with both of them face-down",
}

## Pacing table: trigger -> minimum milliseconds between remarks on THAT
## trigger. Only high-frequency, low-stakes triggers appear here (the Hand
## grabbing/throwing, sigil reads, per-tick faith gains, birth/collapse
## churn in a busy village). Without this the advisors talk over every
## single grab, which is exhausting rather than characterful. Anything
## morally load-bearing — offering_taboo, villager_died_praying,
## villager_forced_to_kneel, mercy_blocked_by_debt, sanctum_destroyed,
## village_lost — is deliberately ABSENT here and always speaks.
##
## Cost: one Dictionary lookup + one Time.get_ticks_msec() per react() call.
## No per-frame work of any kind is added by this file.
const _PACING_COOLDOWN_MSEC := {
	&"hand_grabbed_object": 11000,
	&"hand_threw_object": 11000,
	&"sigil_recognized": 14000,
	&"sigil_rejected": 9000,
	&"village_helped": 20000,
	&"village_terrorized": 20000,
	&"villager_collapsed": 18000,
	&"village_child_born": 25000,
	&"village_child_matured": 25000,
	&"stockpile_overflow": 30000,
	&"village_hungry": 25000,
	&"village_cold": 25000,
	&"construction_started": 12000,
	&"construction_completed": 12000,
	&"avatar_surprised_expectation": 15000,
	&"storm_forming": 20000,
	&"storm_passed": 20000,
	&"missionary_arrived": 12000,
	&"missionary_recalled": 12000,
	&"sanctum_damaged": 8000,
}

## Set false from a debug/QA panel to hear every trigger the instant it
## fires, ignoring _PACING_COOLDOWN_MSEC. Never changed at runtime by the
## game itself.
var respect_pacing: bool = true

## trigger -> Array of pairs. Each pair is [domovoi_line, hiisi_line] and
## MAY carry an optional third element, a float relative weight (default
## 1.0) used by the weighted pick — that's how a rarer "big swing" variant
## is kept rare without removing it from the pool.
var _pairs: Dictionary = {}

## trigger -> Time.get_ticks_msec() at the last remark actually emitted.
var _last_spoke_msec: Dictionary = {}

func _init() -> void:
	_build_pairs()

## Picks a pair not present (by id) in `recent` when possible, formats any
## "{placeholder}" tokens against `context`, and returns fresh VoiceLine
## copies (so callers get already-formatted text without mutating the pool).
func pick_pair(trigger: StringName, context: Dictionary, recent: Array[String]) -> Array:
	var pairs: Array = _pairs.get(trigger, [])
	if pairs.is_empty():
		return []
	if not _may_speak(trigger):
		return []

	var candidates: Array = []
	for pair in pairs:
		var line_a: VoiceLine = pair[0]
		var line_b: VoiceLine = pair[1]
		if not (line_a.id in recent) and not (line_b.id in recent):
			candidates.append(pair)
	if candidates.is_empty():
		# Every variant has been said recently (small pool, active game) —
		# fall back to the full set rather than going silent.
		candidates = pairs

	var chosen: Array = _weighted_pick(candidates)
	var placeholders := _placeholders(context)
	var out: Array = []
	# Exactly the first two elements: a pair may carry a third (weight).
	for i in 2:
		var src: VoiceLine = chosen[i]
		var text: String = src.text
		if text.find("{") != -1:
			text = text.format(placeholders)
			# A substitution at the head of a line ("{village} has started
			# on a {building}.") reads wrong whenever the placeholder
			# resolved to a lowercase fallback ("that village", "wood").
			# One character check per line, only on lines that actually
			# interpolate.
			text = _sentence_case(text)
		out.append(VoiceLine.new(src.id, src.speaker, text))
	_last_spoke_msec[trigger] = Time.get_ticks_msec()
	return out

func _sentence_case(text: String) -> String:
	if text.is_empty():
		return text
	var head := text.substr(0, 1)
	var upper := head.to_upper()
	if head == upper:
		return text
	return upper + text.substr(1)

## True unless this trigger is in the pacing table and spoke too recently.
func _may_speak(trigger: StringName) -> bool:
	if not respect_pacing:
		return true
	var cooldown_ms: int = int(_PACING_COOLDOWN_MSEC.get(trigger, 0))
	if cooldown_ms <= 0:
		return true
	if not _last_spoke_msec.has(trigger):
		return true
	var last: int = int(_last_spoke_msec[trigger])
	return Time.get_ticks_msec() - last >= cooldown_ms

func _weight_of(pair: Array) -> float:
	if pair.size() > 2:
		return maxf(0.0, float(pair[2]))
	return 1.0

## Relative-weight pick. Falls back to a uniform pick if every surviving
## candidate somehow weighs zero.
func _weighted_pick(candidates: Array) -> Array:
	var total: float = 0.0
	for entry in candidates:
		var pair: Array = entry
		total += _weight_of(pair)
	if total <= 0.0:
		var uniform: Array = candidates[randi() % candidates.size()]
		return uniform
	var roll: float = randf() * total
	for entry in candidates:
		var weighted: Array = entry
		roll -= _weight_of(weighted)
		if roll <= 0.0:
			return weighted
	var last: Array = candidates[candidates.size() - 1]
	return last

## Builds the {village}/{culture}/{debt}/etc. substitution table for one
## react() call. Every key always resolves to *something* sensible so a
## line never ships with a literal unfilled "{token}" in it, even when the
## caller passed a sparse context.
func _placeholders(context: Dictionary) -> Dictionary:
	var vid := _as_name(context.get("village_id", &""))
	var cid := _as_name(context.get("culture_id", &""))

	var village_name := "that village"
	if vid != &"":
		var v: Village = GameState.get_village(vid)
		if v:
			village_name = v.display_name
			if cid == &"":
				cid = v.culture_id
	if village_name == "that village" and context.has("village_name"):
		# Economy passes a display name alongside the id; use it if the id
		# lookup came up empty (e.g. a village torn down mid-tick).
		village_name = str(context["village_name"])

	var culture_name := "somebody's"
	var debt_name := "Old Debt"
	if cid != &"":
		var c: Culture = GameState.cultures.get(cid, null)
		if c:
			culture_name = c.display_name
		debt_name = _DEBT_NAMES.get(cid, "Old Debt")
	# sacrifice.gd and sanctum.gd both pass the resolved taboo name directly;
	# prefer theirs over our culture-id lookup so the two can never disagree.
	if context.has("debt_name") and str(context["debt_name"]) != "":
		debt_name = str(context["debt_name"])

	return {
		"village": village_name,
		"culture": culture_name,
		"debt": debt_name,
		"epithet": str(context.get("epithet", "a new name")),
		"reason": str(context.get("reason", "reasons nobody wrote down")),
		"method": str(context.get("method_id", context.get("method", "the usual method"))),
		"amount": _num(context.get("amount", "some")),
		# --- added for the second content pass -----------------------------
		"target_village": _village_display(_as_name(context.get("target_village_id", &"")), "wherever they were sent"),
		"home_village": _village_display(_as_name(context.get("home_village_id", &"")), "home"),
		"building": str(context.get("building_name", "the new building")),
		"resource": str(context.get("resource", "something")),
		"quest": str(context.get("quest_title", "that matter")),
		"relic": _relic_display(context),
		"rite": _rite_display(context),
		"thing": _thing_display(context),
		"kind": str(context.get("kind", "an offering")),
		"species": _creature_display(context.get("species", &""), "something"),
		"predator": _creature_display(context.get("predator", &""), "something bigger"),
		"stage": str(context.get("stage", "bigger")),
		"tag": String(_as_name(context.get("tag", &""))).replace("_", " ") if context.has("tag") else "that",
		"chance": _pct(context.get("probability", 0.0)),
		"confidence": _pct(context.get("confidence", 0.0)),
		"gain": _pct(context.get("gain", 0.0)),
		"speed": _num(context.get("speed", 0.0)),
		"wind": _num(context.get("wind_speed", 0.0)),
		"seconds": _num(context.get("seconds_remaining", 0.0)),
		"winner": str(context.get("winner", "the winner")),
		"loser": str(context.get("loser", "the loser")),
		"downed": str(context.get("downed", "the one on the ground")),
		"finisher": str(context.get("finisher", "the one still standing")),
		"sparer": str(context.get("spared_by", "the one still standing")),
		"finish": _FINISH_PHRASES.get(str(context.get("finish_type", "")), "the way these things end"),
	}

## StringName-or-String -> StringName, anything else -> &"". Callers across
## the repo pass ids both ways; this keeps a sloppy context from throwing.
func _as_name(v: Variant) -> StringName:
	if v is StringName or v is String:
		return StringName(String(v))
	return &""

func _village_display(vid: StringName, fallback: String) -> String:
	if vid == &"":
		return fallback
	var v: Village = GameState.get_village(vid)
	if v:
		return v.display_name
	return fallback

## Numbers spoken aloud: whole where whole, one decimal otherwise, never a
## raw float tail like "13.700000".
func _num(v: Variant) -> String:
	if v is int:
		return str(v)
	if v is float:
		var f: float = v
		if is_equal_approx(f, roundf(f)):
			return str(int(roundf(f)))
		return String.num(f, 1)
	return str(v)

## 0..1 -> "62%" (one decimal only when it would otherwise round to zero).
func _pct(v: Variant) -> String:
	if not (v is float or v is int):
		return str(v)
	var f: float = float(v) * 100.0
	if f < 1.0 and f > 0.0:
		return String.num(f, 1) + "%"
	return str(int(roundf(f))) + "%"

func _relic_display(context: Dictionary) -> String:
	var rid := _as_name(context.get("relic_id", context.get("relic", &"")))
	if rid == &"":
		return "that old thing"
	var r: Relic = RelicCatalog.get_relic(rid)
	if r and r.display_name != "":
		return r.display_name
	return String(rid).capitalize()

func _rite_display(context: Dictionary) -> String:
	var rid := _as_name(context.get("rite_id", context.get("best_guess", &"")))
	if rid == &"":
		return "no rite at all"
	return String(rid).capitalize()

## Species/creature ids ("snow_hare", "unknown") spoken as plain words.
func _creature_display(v: Variant, fallback: String) -> String:
	var id := _as_name(v)
	if id == &"" or id == &"unknown":
		return fallback
	return String(id).replace("_", " ")

func _thing_display(context: Dictionary) -> String:
	var n := str(context.get("node_name", ""))
	if n == "":
		return "something"
	# Scene node names are CamelCase/underscored ("PineLog", "fish_crate").
	return n.replace("_", " ").capitalize().to_lower()

func _p(id: String, d_text: String, h_text: String) -> Array:
	return [VoiceLine.new(id + "_d", DOMOVOI, d_text), VoiceLine.new(id + "_h", HIISI, h_text)]

## Same as _p(), with an explicit relative weight (1.0 = as likely as a
## plain _p pair). Used to keep the biggest swings rare rather than absent.
func _pw(weight: float, id: String, d_text: String, h_text: String) -> Array:
	return [VoiceLine.new(id + "_d", DOMOVOI, d_text), VoiceLine.new(id + "_h", HIISI, h_text), weight]

func _build_pairs() -> void:
	_pairs[&"first_rite_cast"] = [
		_p("frc1",
			"First rite's cast. I've already found two things wrong with it.",
			"I found one thing right with it: it's over. Can we eat now?"),
		_p("frc2",
			"No incense budget, no cleanup crew, and somehow a rite happened anyway.",
			"That's called improvising. I do it every single meal."),
		_p("frc3",
			"It worked. I'm choosing to be disappointed about that later, on principle.",
			"Later? Why wait? I'm disappointed in advance, it saves time."),
		_p("frc4",
			"One rite in and already the bookkeeping is a disgrace.",
			"The bookkeeping was always a disgrace. Now it's a disgrace with sparkles."),
		_p("frc5",
			"Congratulations. You've performed your first miracle and your first liability.",
			"Liabilities are delicious if you fry them first."),
		_p("frc6",
			"Well. It's done. Someone ought to write down which god did that before we forget.",
			"I never forget a good rite. I forget where I put my other wing sometimes, never a rite."),
	]

	_pairs[&"village_converted"] = [
		_p("vc1",
			"{village} converted. Someone go check they still have enough grain to be grateful with.",
			"Grateful villages taste better anyway. More seasoning in it."),
		_p("vc2",
			"Another village signed on. Do try not to let this one starve like the last one.",
			"The last one didn't starve. I just visited a lot."),
		_p("vc3",
			"{village} is ours now, which means {village}'s problems are now also ours.",
			"Problems, schmoblems. I solve every problem the same way."),
		_p("vc4",
			"Faith's in, devotion's rising, and somebody still has to fix their roof. It won't be the god.",
			"Roofs are for people who plan to stay indoors. I never plan anything."),
		_p("vc5",
			"Well, {village} believes now. Let's see how long that survives contact with our management.",
			"Ohh, will we be terrible at this? I love when we're terrible at this."),
		_p("vc6",
			"Convert one more village and I'm requisitioning a second ledger.",
			"Requisition a second cook while you're at it."),
	]

	_pairs[&"village_lost"] = [
		_p("vl1",
			"{village} is gone. Add it to the list of things I warned you about and you cast anyway.",
			"Gone doesn't mean gone-gone. Something's still down there. I could go check. With my mouth."),
		_p("vl2",
			"We lost {village}. That's not a statistic, that's a whole harvest calendar undone.",
			"I liked their calendar. Smelled nice. Mostly grain, some fear."),
		_p("vl3",
			"{village} is lost, and I want it noted that I said this exact thing would happen.",
			"You always say that. You said it about the last one too. You were right that time also."),
		_p("vl4",
			"That's another village we won't be collecting devotion from. Ever. At all.",
			"More for the rest of us, then! Wait, no, that isn't how devotion works, is it."),
		_p("vl5",
			"I don't have a tidy way to say this. {village} is gone, and it goes on the ledger as a loss, not a lesson.",
			"I'd say a little something for them, but I already ate all my nice words earlier."),
	]

	# Domovoi genuinely appalled, Hiisi weirdly delighted — per brief this
	# reaction is what locks the mercy path in the player's mind.
	_pairs[&"offering_taboo"] = [
		_p("ot1",
			"That is the {debt}, and every {culture} elder could describe it in loving, horrified detail. We just did it.",
			"Finally! A rule with teeth! I love rules with teeth, they're the only kind worth breaking."),
		_p("ot2",
			"You have no idea what you just asked for. That is the one thing they told us, unprompted, never to take.",
			"Never is such a strong word. I prefer 'not yet.'"),
		_p("ot3",
			"This crosses the one line every culture on this island agrees is a line. Every single one of them.",
			"A unanimous taboo! Do you know how rare that is? We should frame it."),
		_p("ot4",
			"I need a moment. That was the {debt}. The actual one. Not a metaphor.",
			"Not a metaphor is my favorite kind of afternoon."),
		_p("ot5",
			"There is a word for what just happened and the word is 'no.' We did it anyway.",
			"There's another word for it and that word is 'lunch,' but nobody asked me."),
		_p("ot6",
			"Every one of them warned us about exactly this, the very first day we met them. And here we are.",
			"Here we are indeed. Wonderfully, deliciously here."),
	]

	_pairs[&"avatar_praised"] = [
		_p("ap1",
			"They're praising the Avatar again. I'd like it on record that I did the actual paperwork.",
			"Paperwork doesn't have teeth. Teeth get praised. That's just how praising works."),
		_p("ap2",
			"Lovely, more adoration. None of it converts into devotion I can actually spend.",
			"I'll take the adoration then. I can eat almost anything, including compliments."),
		_p("ap3",
			"The Avatar preens, I catalogue. Guess which one of us gets remembered.",
			"They'll remember whoever looked the most dramatic doing it. That's usually me."),
		_p("ap4",
			"Praise received, filed, and — I notice — entirely unearned by the paperwork side of this operation.",
			"Nobody ever throws a parade for the paperwork side. I've checked."),
		_p("ap5",
			"One more compliment and the Avatar is going to start believing its own reviews.",
			"Reviews are just prayers with better grammar. Let it believe them."),
	]

	_pairs[&"avatar_chastised"] = [
		_p("ac1",
			"The Avatar's being scolded. Good. Someone other than me finally said it.",
			"Scolded, chastised, corrected — such fussy words for 'somebody's cranky.'"),
		_p("ac2",
			"About time. I've been chastising quietly for ages and nobody writes that down.",
			"I never chastise quietly. Where's the fun in a quiet chastising."),
		_p("ac3",
			"They're getting told off, and rightly, and I intend to enjoy every second of not saying it myself for once.",
			"I'd enjoy it more with snacks involved. There's always room for snacks in a scolding."),
		_p("ac4",
			"Chastised again. At this rate I'll need a second ledger just for reprimands.",
			"Ledgers are so permanent. I forget my reprimands the moment they're finished. Freeing, really."),
		_p("ac5",
			"Somebody finally said what needed saying to the Avatar. Wasn't me this time, and I'm almost disappointed.",
			"You wanted to say it! You should have said it! Now it's someone else's line."),
	]

	_pairs[&"avatar_grew"] = [
		_p("ag1",
			"The Avatar's grown again. Wonderful. Now I need to refit every door in the Sanctum.",
			"Bigger Avatar means bigger portions. Best news I've had all week."),
		_p("ag2",
			"Growth noted. Also noted: nobody consulted me about the structural load-bearing implications.",
			"Structural load-bearing is just a fancy way of saying 'it'll probably hold.' Probably!"),
		_p("ag3",
			"They're bigger now. I don't know what that means for the budget, but I assume it means more budget.",
			"It means more of them to admire! And, if it ever came to that, more of them to — never mind."),
		_p("ag4",
			"Another growth spurt. I've stopped measuring doorframes. I measure disappointment now.",
			"I measure everything in bites. Saves time."),
		_p("ag5",
			"The Avatar keeps growing and nobody's growing the storerooms to match. That's on somebody's ledger.",
			"Growth is good! Bigger things cast bigger shadows, and bigger shadows are so much more theatrical."),
	]

	_pairs[&"louhi_sighted"] = [
		_p("ls1",
			"Louhi's been sighted again. Lock up anything that isn't nailed down, and half of what is.",
			"Louhi! Finally, someone interesting. Do you think she'd let me follow along? Just to watch. Mostly to watch."),
		_p("ls2",
			"Louhi. Wonderful. As if my ledger weren't complicated enough without a second god-adjacent nuisance in it.",
			"She's not a nuisance, she's a colleague. An extremely dangerous, extremely stylish colleague."),
		_p("ls3",
			"There's a sighting report on Louhi and it's already three sentences longer than any of ours.",
			"That's because her sightings have flair. Ours are just 'stood around being holy.'"),
		_p("ls4",
			"Louhi again. If she takes so much as one more sheep I am filing a formal complaint with — with somebody.",
			"File it with me! I'll eat it immediately and you'll feel much better."),
		_p("ls5",
			"She's back. I want it noted I trust her motives, her methods, and her timing not at all.",
			"I trust all three! Mostly the timing. Very theatrical timing."),
	]

	_pairs[&"missionary_sent"] = [
		_p("ms1",
			"A missionary's off to spread the word. Do try to remember the word this time.",
			"I remember the important part: knock politely, then, if that fails, don't."),
		_p("ms2",
			"Missionary dispatched. That's one fewer set of useful hands back home and one more mouth to worry about out there.",
			"One more mouth out there is one more mouth I might get to feed personally, if it comes to that."),
		_p("ms3",
			"Sending missionaries is slow, patient, thankless work. Naturally nobody thanked the missionary.",
			"I'd thank them! With a nice meal! For them, not — well. For them, mostly."),
		_p("ms4",
			"There goes another missionary, off to convert strangers to a religion we're still writing the rules for.",
			"Making up rules as you go is the only honest way to run a religion. I'd know, I've run several."),
		_p("ms5",
			"Missionary sent. Add 'pray they come back' to the ledger, under 'unfunded mandates.'",
			"I'll pray too! Loudly! It scares off the smaller predators."),
	]

	_pairs[&"first_duel_won"] = [
		_p("fdw1",
			"First duel won. I'll allow one moment of pride before the paperwork ruins it.",
			"One moment? I intend to savor this all week. Possibly with the loser's boots as a souvenir."),
		_p("fdw2",
			"A win's a win. Somebody still has to clean the arena, and it certainly won't be the winner.",
			"I'll clean it. With my teeth. Very efficient system, ask anyone."),
		_p("fdw3",
			"The Avatar's first duel, won. I'm relieved, mostly, and slightly annoyed I have to be relieved out loud now.",
			"Announce it properly! Trumpets! Fanfare! Something involving me being fed."),
		_p("fdw4",
			"One victory and already they're strutting. I saw that. I'm writing it down.",
			"Write down that I strutted too, on principle. Somebody should get credit for good posture."),
		_p("fdw5",
			"First duel won cleanly, which is more than I expected and rather less than the Avatar will ever admit.",
			"Cleanly's boring! Next time, more biting. For flavor, not cruelty. Purely for flavor."),
	]

	_pairs[&"drought"] = [
		_p("dr1",
			"Drought again. The wells are down, the fields are cracking, and somehow it's still my job to say so calmly.",
			"Cracking fields! Wonderful sightlines. Everything's easier to catch when it can't hide in tall grass."),
		_p("dr2",
			"A drought is no small thing. Whole villages measure the difference between 'lean year' and 'last year' in weeks like this.",
			"I measure it in how thin everything's gotten. Concerning, really, from a purely dining perspective."),
		_p("dr3",
			"The rains haven't come and the ledger's filling up with words like 'rationing' and 'unrest.'",
			"Unrest just means everyone's outside arguing instead of indoors being boring. I prefer it, frankly."),
		_p("dr4",
			"Another dry season. I'd pray for rain myself if I thought anyone up there was doing their job.",
			"I'd pray for rain too. Mostly so things grow back and I've more to choose from later."),
		_p("dr5",
			"Drought's here, and somebody's going to ask the Avatar to fix the weather like that's a small ask.",
			"Is it a big ask? Everything's a small ask if you're theatrical enough about granting it."),
	]

	# =====================================================================
	# SECOND CONTENT PASS — the 34 triggers other packages were already
	# firing into silence, plus &"wonder_completed". Same voices, same
	# pair shape, same audited comedic target. Placeholders used per
	# trigger are only ever keys that trigger's ACTUAL call site provides
	# (verified by grepping every Voices.react() in the repo) — see
	# docs/systems/voices_content.md for the trigger/key table.
	# =====================================================================

	# --- The Avatar -------------------------------------------------------
	# actors/avatar/avatar.gd: {tag, probability, result, species}
	_pairs[&"avatar_surprised_expectation"] = [
		_p("ase1",
			"The Avatar just did the opposite of everything it has ever been taught about {tag}. I had a column for that. The column was wrong.",
			"The column was BORING. It did a surprise! Nobody has ever surprised me by doing the expected thing."),
		_p("ase2",
			"By my reckoning there was a {chance} chance of that. It happened anyway. I'd like a word with whoever runs the numbers.",
			"You run the numbers. You have been talking to yourself again. It's fine, I do it constantly."),
		_p("ase3",
			"Note for the ledger: the beast is not a machine, and it has just proved it in front of witnesses.",
			"It has a mind! A small, damp, marvellous mind, and today it used it to embarrass you specifically."),
		_p("ase4",
			"That went against every lesson we ever gave it about {tag}. Teaching a thing is apparently not the same as owning it.",
			"Nobody owns anything. I've tried. It runs off, or it bites, or it gets eaten. Usually the last one."),
		_pw(0.6, "ase5",
			"It surprised itself, too. I watched it stand there afterwards working out what it had just become.",
			"That's the best part. That's the part I'd keep in a jar, if I had jars. Or hands. Or a cellar."),
	]

	# --- Economy: construction (systems/economy/village_economy.gd) -------
	# {village_id, village_name, building_id, building_name}
	_pairs[&"construction_started"] = [
		_p("cs1",
			"{village} has started on a {building}. Somebody has done a sensible thing unprompted and I intend to note it before it falls over.",
			"It's mostly a hole so far. I love a hole. Anything at all could be at the bottom of a hole."),
		_p("cs2",
			"Foundations down for the {building}. The stone's spent, the wood's spent, and the roof is still theoretical.",
			"Theoretical roofs are the finest kind. No thatching, no gutters, no me falling off them."),
		_p("cs3",
			"A {building} is going up in {village}. Half the village is carrying things instead of praying, which somebody upstairs will notice.",
			"Let them carry. Praying doesn't raise walls, and walls keep the interesting things out. Or in."),
		_p("cs4",
			"They've begun the {building}. I give it four days, two arguments, and one complete rebuild of the near corner.",
			"I give it a week and a small fire. I always say that. I'm usually only half right."),
		_p("cs5",
			"Construction started at {village}. The materials are already spent, so if this gets abandoned halfway that's a loss, not a lesson.",
			"Half a building is still a building. It's just a building that gave up, like most of us."),
	]

	_pairs[&"construction_completed"] = [
		_p("cc1",
			"The {building} in {village} is finished. It stands, it's level, and nobody thanked the people who hauled the stone.",
			"I'd thank them, but my mouth is busy admiring the beams."),
		_p("cc2",
			"{building} complete. Write it down, because in a month everyone will assume it was always there.",
			"That's how you know it's good. The best things feel like they were always there. Like me. Like hunger."),
		_p("cc3",
			"Done, and under cost, which I say with suspicion rather than pride.",
			"Under cost means leftovers. Where are the leftovers, Domovoi. Where."),
		_p("cc4",
			"They've built a {building}. That's a real thing standing in the world, and it took not one miracle from us.",
			"No miracle at all. Just people being irritatingly capable. It's almost rude."),
		_p("cc5",
			"New {building} in {village}. I'll add it to the maintenance list, which is the ledger nobody ever wants to hear about.",
			"Nobody wants to hear about ANY of your lists. That's what makes them yours."),
	]

	# Fired by the same call site when building.is_wonder — rarer, bigger.
	_pairs[&"wonder_completed"] = [
		_p("wc1",
			"A wonder. An actual wonder, finished, at {village}. I have kept this line ready in the ledger for years and never once used it.",
			"Say it louder! Say it with the whole chest! I'm doing a lap of the roof!"),
		_p("wc2",
			"{building} is done. Generations of them will point at it and misremember entirely who paid for it.",
			"They'll say it was me. I'll allow that. I'll encourage that, actually."),
		_p("wc3",
			"A wonder stands at {village}. I would like it noted, calmly, that I am not calm.",
			"He's not calm! Look at him! This is the happiest I have ever seen the little soot-cloud."),
		_p("wc4",
			"That is the largest thing anyone in {village} has ever built, and they built it for us. That's a debt running the other way for once.",
			"A debt where WE owe THEM? Disgusting. Novel. I may weep. I'll eat something first."),
	]

	# --- Duels (actors/avatar/combat/duel_arena.gd) -----------------------
	# duel_ended: {winner, loser, finish_type}
	_pairs[&"duel_ended"] = [
		_p("de1",
			"{winner} is standing, {loser} isn't. That's the whole report, and it took less time than the arguing beforehand.",
			"The arguing beforehand is the best part. The fight is only the arguing, but honest."),
		_p("de2",
			"Duel's over. {winner} took it. I'll go and find out what it cost, since nobody else ever asks.",
			"It cost {loser} some dignity and possibly a tooth. I'd like the tooth. For the crown."),
		_p("de3",
			"{loser} is finished. Not dead, mind — finished. There's a difference and I'd like us to keep hold of it.",
			"There's a difference, yes, and it is measured almost entirely in how loudly they complain afterwards."),
		_p("de4",
			"Result: {winner}. I'd celebrate, but somebody has to count the arena repairs, and it is always somebody, and it is always me.",
			"Repairs! Bah. A cracked wall is only a wall with a story in it."),
		_p("de5",
			"The duel ended {finish}. I've written it exactly as it happened, because the version they tell tonight will be much grander.",
			"Mine will be grander AND better. In mine there are three of them and I'm the one who wins."),
	]

	# duel_foe_finished_while_downed: {finisher, downed}. Naklon has already
	# shifted toward cruelty by the time this fires; Domovoi names the cost.
	_pairs[&"duel_foe_finished_while_downed"] = [
		_p("dfd1",
			"{downed} was already down. {finisher} finished them anyway. That isn't a victory, that's an errand.",
			"It's a very memorable errand. People will be describing it at supper for a year."),
		_p("dfd2",
			"Down means beaten. Beaten means done. {finisher} decided otherwise, and the beast will remember being allowed to.",
			"It'll remember it fondly. Those are always the best memories. The ones you shouldn't have."),
		_p("dfd3",
			"I want it in the record that {downed} could not stand, and was killed for it.",
			"Put it in twice. Once for the record, once because you're going to grind your teeth about it all night regardless."),
		_p("dfd4",
			"The Avatar learns from whatever we let it do. It has just learned something I would rather it hadn't.",
			"It learned a SKILL. Skills aren't wicked. They're only quick."),
		_p("dfd5",
			"That fight was already won. Everything after 'won' is just something we'll be explaining later.",
			"Explanations are for people who get caught. We're gods. Nobody catches us. Nobody even writes to us."),
	]

	# duel_mercy_shown: {spared_by, downed}
	_pairs[&"duel_mercy_shown"] = [
		_p("dms1",
			"{sparer} let {downed} back up. I've read that twice now and it still says the same thing.",
			"Mercy! In MY arena! I'm disgusted. I'm moved. I don't know what I am and it's very upsetting."),
		_p("dms2",
			"The beast had the finish and didn't take it. That was a choice, and it made it on its own.",
			"Nobody TAUGHT it that. Which means somebody did. Somebody sneaky. Don't look at me, I was napping."),
		_p("dms3",
			"{downed} walks away. That's one fewer name I have to write into the wrong column tonight.",
			"Your columns. Always the columns. Fine — it was a good thing. I said it. Don't repeat it."),
		_p("dms4",
			"Mercy shown, and the crowd didn't jeer. I had two coins on the crowd jeering.",
			"The crowd is fickle and stupid and I adore them. They'd cheer a rock if it stood up dramatically enough."),
		_p("dms5",
			"It could have finished it. It chose not to. Whatever we've been teaching, some of it landed.",
			"Some of it landed on ME, and I resent it deeply, and I'm still not going to stop watching."),
	]

	# --- The Hand (actors/hand/hand.gd) -----------------------------------
	# hand_grabbed_object: {node_name}
	_pairs[&"hand_grabbed_object"] = [
		_p("hg1",
			"You've picked up the {thing}. Wonderful. It was perfectly fine where it was.",
			"Nothing is fine where it was! Everything is better somewhere else, preferably in the air."),
		_p("hg2",
			"That's a {thing} in the divine hand. Do you know how much of my day is spent putting things back?",
			"Do you know how much of MY day is spent watching you put things back? It's my favourite entertainment."),
		_p("hg3",
			"Held. Whatever it is, please remember it has a place, and the place is not 'the sky.'",
			"The sky IS a place. The best one. Nothing has ever been boring in the sky."),
		_p("hg4",
			"You've got hold of the {thing}. I'd ask what the plan is, but I've been here a long while and there's never a plan.",
			"There's always a plan. Grab, admire, throw. That's three whole steps, that's practically architecture."),
		_p("hg5",
			"Picked up. Somebody down there has just watched a god take their belongings with no way at all to comment.",
			"They can comment. They can shout. It's very good shouting. I collect the shouting."),
	]

	# hand_threw_object: {node_name, speed}
	_pairs[&"hand_threw_object"] = [
		_p("ht1",
			"And it's thrown. The {thing}, airborne, at a speed I would rather not have measured. I measured it. {speed} paces a second.",
			"{speed}! Say it again! Say it with feeling!"),
		_p("ht2",
			"You threw the {thing}. Somewhere down there it is now somebody's problem, and that somebody is not us.",
			"That's the beauty of throwing. Ownership transfers mid-flight. Practically law."),
		_p("ht3",
			"Released, spinning, gone. I'll wait for the noise before I write down what it hit.",
			"Ohh, the waiting is the best part. Little pause. Then — crunch. Perfect."),
		_p("ht4",
			"That was in somebody's hands this morning. It is now in a field. That's the entire divine intervention for today.",
			"Best one yet, then. Efficient. Very little paperwork."),
		_p("ht5",
			"I would remind you that everything you throw lands on something, but you have never once let me finish that sentence.",
			"Because it's a boring sentence! Everything lands! That's what makes throwing worth doing!"),
	]

	# --- Louhi (actors/louhi/louhi_director.gd) ---------------------------
	# louhi_duel_challenge: {village_id}
	_pairs[&"louhi_duel_challenge"] = [
		_p("ldc1",
			"Louhi is asking for a reckoning at {village}. She's named her price and she's content to wait for it. She always is.",
			"A reckoning! Formal! With rules and everything! Do we choose the venue? I have opinions about venues."),
		_p("ldc2",
			"She's challenged us openly. That isn't a threat, that's an invoice with a date on it.",
			"I love an invoice with a date. It means somebody's planned ahead. It means somebody's serious."),
		_p("ldc3",
			"There's nothing left worth taking at {village}, so she's asked for a fight instead. Sit with what that says about {village}.",
			"It says we've been dreadful landlords. Come along, let's go and be dreadful somewhere else too."),
		_p("ldc4",
			"A challenge from Louhi. She is patient, she is precise, and she has never once made an offer that was good for us.",
			"That's only negotiating. I'd make her an offer too, but everything I own is either eaten or on fire."),
		_pw(0.7, "ldc5",
			"She waits. That's the part I can't get past. She is genuinely, comfortably happy to wait.",
			"Waiting is a skill. I've never had it. I respect it the way you respect weather."),
	]

	# louhi_relic_stolen: {village_id, relic}
	_pairs[&"louhi_relic_stolen"] = [
		_p("lrs1",
			"The {relic} is gone from {village}. No door forced, no witness, no noise. That's her signature, and it's a tidy one.",
			"Tidy! Ugh! If I stole a thing there'd be feathers everywhere and at least one small fire."),
		_p("lrs2",
			"She took the {relic}. Didn't smash it, didn't curse it — took it. She wanted it, so now it's hers.",
			"A hoarder with taste. Terrifying. Enviable. I'd hoard too if I could stop eating the hoard."),
		_p("lrs3",
			"Add the {relic} to the list of things we no longer have and never actually guarded.",
			"We guarded it beautifully. With our hopes. With our very good intentions."),
		_p("lrs4",
			"{village} will notice the {relic} missing by morning, and they'll look at us, not at her.",
			"Correctly! They should! We're so much easier to shout at."),
		_p("lrs5",
			"This is how she does it. One quiet thing at a time, until one day you count the shelf and the shelf is a shelf.",
			"You'd know. You're the one with the shelf. And the count. And the little sad face about the count."),
	]

	# --- The Sanctum (world/sanctum/sanctum.gd) ---------------------------
	# mercy_blocked_by_debt: {village_id, debt_name, seconds_remaining}.
	# Hard rule 7 lives here: the lockout is the fiction agreeing with the
	# taboo. BOTH voices condemn — Hiisi refuses to make his usual joke.
	_pairs[&"mercy_blocked_by_debt"] = [
		_p("mbd1",
			"No. The altar at {village} is still wet from the {debt}. You do not get to take a life at that stone and then mend the roof with the same hand.",
			"Even I won't touch this one. And I touch everything."),
		_p("mbd2",
			"The {debt} still stands over this village. Mercy waits {seconds} seconds, and the waiting is the entire point of it.",
			"You want the good half of a god without the bill for the bad half. That isn't divine. That's shopping."),
		_p("mbd3",
			"You cannot mend at the same altar, in the same hour, what you broke there. I won't file it. The stone won't take it.",
			"He's right and I hate it. Don't tell him. Tell him later, when I'm not here."),
		_p("mbd4",
			"{village} would have to watch you repair the wall with the hand that made the offering. They'd know. Every one of them would know.",
			"They'd smell it. I'd smell it. It smells like a god trying to have it both ways."),
		_p("mbd5",
			"Refused. Come back when the {debt} has run its course, and understand that 'run its course' is not the same as 'been forgiven.'",
			"Nothing gets forgiven. Things only get further away. That's the whole trick of being old."),
	]

	# offering_out_of_reach: {village_id}. The taboo act refused on a
	# jurisdictional technicality — Domovoi is quietly relieved, and the
	# joke is squarely on divine bureaucracy.
	_pairs[&"offering_out_of_reach"] = [
		_p("oor1",
			"You have no purchase at {village}. The offering doesn't land. It doesn't even get read.",
			"A god who can't be heard, trying to take something anyway. Undignified. I'd have watched it twice."),
		_p("oor2",
			"Out of reach. The stone won't take it, and I find I am not sorry to be the one telling you that.",
			"He's delighted. Look at him. He's got colour in his soot."),
		_p("oor3",
			"That village is beyond us. Faith goes out first and the taking comes after, and you've tried it backwards.",
			"Backwards! Always backwards! Very consistent, at least."),
		_p("oor4",
			"Refused on jurisdiction, of all things. There is a version of this where the answer was 'no' for a much better reason.",
			"Bureaucracy has saved more lives than mercy ever has. Nobody carves that on a temple."),
		_p("oor5",
			"Nothing happened. The hand closed on nothing, at a stone that does not answer to you.",
			"The most divine thing you've done all week: absolutely nothing, in front of witnesses."),
	]

	# sanctum_damaged: {village_id, amount, hp_fraction, source}
	_pairs[&"sanctum_damaged"] = [
		_p("sdm1",
			"The Sanctum at {village} has taken {amount} damage. Stone does not heal on its own, whatever the Avatar believes.",
			"Cracks are only windows that haven't committed yet."),
		_p("sdm2",
			"Something has struck the Sanctum. I want the wall mended before I want the culprit found, and that tells you the state of the wall.",
			"I'll find the culprit. I'll bring back a piece of them. A small piece. A polite piece."),
		_p("sdm3",
			"Damage at {village}'s Sanctum. Our name is on that building, and our name is currently somewhat dented.",
			"Dents are character! Look at me! I am entirely dents!"),
		_p("sdm4",
			"{amount} off the Sanctum. That isn't abstract — that's a roof somebody will be standing under during the next storm.",
			"Ohh. That's a good point. I hate it when you make good points, it ruins the whole mood."),
		_p("sdm5",
			"Struck again. Every one of these gets repaired by hand or by rite, and only one of those is something we can afford.",
			"Do the rite! Do the flashy one! Repairs are so much better when they sparkle."),
	]

	# sanctum_destroyed: {village_id, culture_id}
	_pairs[&"sanctum_destroyed"] = [
		_p("sdx1",
			"The Sanctum at {village} is down. Not damaged. Down. Every scrap of faith it held goes with it.",
			"...Well. That's quiet. I don't like it quiet."),
		_p("sdx2",
			"It's rubble. Everything the {culture} of {village} gave us at that altar has nowhere left to be given.",
			"They'll build another. People always build another. It's their most annoying quality and their best one."),
		_p("sdx3",
			"Gone. I won't dress it up. We had one building in {village} and now we have a hole and a story.",
			"Bad hole. I said I like holes. This is a bad hole."),
		_p("sdx4",
			"The Sanctum's fallen. A year of hauling, a season of carving, and a great many people's evenings, undone in a moment.",
			"Say the number of evenings. He knows the number of evenings. He always knows."),
		_p("sdx5",
			"Devotion at {village} is nothing now, because the place it lived in is on the ground.",
			"Then we go and stand there ourselves. In person. That's what we're for, isn't it? Isn't it."),
	]

	# --- Campaign (campaign/campaign_manager.gd) --------------------------
	# quest_activated: {quest_id, quest_title}
	_pairs[&"quest_activated"] = [
		_p("qa1",
			"New matter opened: {quest}. I've given it a page. Try to fill the page before you open another one.",
			"Open six! Open all of them! Pages are free!"),
		_p("qa2",
			"{quest}. Somebody, somewhere, has decided this is our problem now.",
			"That somebody is you. You decided it. You've forgotten already, haven't you."),
		_p("qa3",
			"'{quest}' is on the ledger. I note, as ever, that the ledger has never once got shorter.",
			"Ledgers only grow. Like appetites. Like me, on a good week."),
		_p("qa4",
			"Fresh work: {quest}. I'd ask who's doing it, but I have a horrible feeling I know who's doing it.",
			"It's the beast! It's always the beast! The beast does everything and gets fed once!"),
		_p("qa5",
			"{quest} begins. I'll believe it's begun when somebody moves in the direction of it.",
			"I moved! I moved just then! Did you see? Write that down as progress."),
	]

	_pairs[&"quest_completed"] = [
		_p("qc1",
			"{quest} — done. Closed, signed, shelved. I'd like one moment with it before the next thing starts.",
			"No moments! Momentum! What's next! Who are we bothering!"),
		_p("qc2",
			"That's {quest} finished. I am allowing myself to be pleased about this one for the length of one page-turn.",
			"One page-turn of joy. Truly, the hearth-spirit's great festival."),
		_p("qc3",
			"Completed. Whatever it cost has already been paid, so let's at least admit out loud that it worked.",
			"It worked! Louder! I want the villages to hear us being competent, it'll confuse them for days."),
		_p("qc4",
			"{quest} is closed, and the reward is real, which makes a pleasant change from the promises.",
			"A reward! Is it edible? It's never edible. Nothing good is ever edible."),
		_p("qc5",
			"Done and recorded. In fifty years somebody will read that line and assume it was easy.",
			"It WAS easy. For me. I supervised. Loudly."),
	]

	# relic_found: {relic_id}
	_pairs[&"relic_found"] = [
		_p("rf1",
			"The {relic} is ours. Which is to say it's mine to log, mine to store, and mine to explain when it goes missing.",
			"Nothing goes missing. Things go elsewhere. Usually inside something."),
		_p("rf2",
			"We've recovered the {relic}. Old thing. Older than our interest in it, which is the part that ought to be humbling.",
			"Humbling! Ha! I've been humbled twice and I ate both of them."),
		_p("rf3",
			"The {relic}, recovered and intact. Somebody kept this safe a very long time before we turned up and called it a find.",
			"'Find' is a strong word for 'took off a shelf.' I approve, mind. Strong words are free."),
		_p("rf4",
			"New relic in the Sanctum. I'll need a plinth, a label, and somebody to stop Hiisi licking it.",
			"One lick! One! To learn whether it's the sort of old that tastes of copper!"),
		_p("rf5",
			"The {relic}. It's real, it's here, and it has a history that does not care about us in the slightest.",
			"Rude of it. I'd like history to care about me. I'd settle for history flinching."),
	]

	# scroll_learned: {rite_id}
	_pairs[&"scroll_learned"] = [
		_p("sl1",
			"The {rite} rite is learned. Now please practise it somewhere that isn't directly above a village.",
			"Practise it above a village! That's where the audience is!"),
		_p("sl2",
			"{rite} added to the book. I've written the gesture down twice, in case somebody forgets it mid-crisis.",
			"Somebody always forgets it mid-crisis. That somebody has a beautiful crown of teeth."),
		_p("sl3",
			"A new rite: {rite}. Real power, learned properly off a scroll, instead of guessed at.",
			"Guessing is faster. Guessing is how I learned everything. ...I know four things."),
		_p("sl4",
			"{rite}, learned. I'd remind everyone that a rite you can cast is not the same as a rite you ought to.",
			"Wrong. Utterly wrong. Every rite I can cast is a rite I should. Immediately. Twice."),
		_p("sl5",
			"Scroll read, rite understood. Somebody wrote that down long ago, hoping somebody competent would find it.",
			"And instead they got us. What a lovely little tragedy."),
	]

	# --- Sigils (systems/sigils/sigil_caster.gd) --------------------------
	# sigil_recognized: {rite_id, confidence}
	_pairs[&"sigil_recognized"] = [
		_p("sr1",
			"That's {rite}, read cleanly — {confidence} sure. Even I can't fault that stroke.",
			"He's faulting it. Look at his face. He's faulting it internally, which is the worst kind."),
		_p("sr2",
			"{rite}. Recognised. Draw it exactly that way again and I'll withhold advice for a whole minute.",
			"A whole minute! Cast it again! Cast it forever!"),
		_p("sr3",
			"Read as {rite} at {confidence}. The shape held all the way round, which is usually exactly where it comes apart.",
			"The end is where everything comes apart. Rites, feasts, friendships."),
		_p("sr4",
			"{rite} it is. Good, clean gesture. I'd frame it, if gestures could be framed.",
			"You'd frame anything. You framed a receipt once."),
		_p("sr5",
			"Clean stroke, clear rite. That's the whole art of it: draw the thing you mean, and mean it the entire way through.",
			"That's my philosophy of eating as well. Commit to the bite."),
	]

	# sigil_rejected: {best_guess, confidence}. This is the teaching moment —
	# Domovoi actually says what went wrong with the stroke.
	_pairs[&"sigil_rejected"] = [
		_p("sj1",
			"That read as nothing. Nearest was {rite}, at {confidence} — nowhere close. Draw it larger and slower.",
			"Or draw it wilder! One of us is right and I shan't say which."),
		_p("sj2",
			"Rejected. The shape wandered. A rite has to close where it says it closes.",
			"MY shapes never close. That's precisely why I'm not allowed near the altar."),
		_p("sj3",
			"It thought you were reaching for {rite} and couldn't commit. Half a gesture is worse than no gesture.",
			"Half a gesture is also how you get a very confused sky. Ask me how I know."),
		_p("sj4",
			"Nothing cast. {confidence} confidence isn't a rite, it's a guess with good posture.",
			"I love a guess with good posture! That is my entire personality!"),
		_p("sj5",
			"The stroke was too small to read. Give it room. The sky is not short of room.",
			"Take the WHOLE sky. Why are you drawing as if someone's watching? Someone IS watching. It's us. We don't count."),
		_p("sj6",
			"Failed to read. No power spent, no harm done, and the next attempt is free. That's the kindest thing this whole system does.",
			"Free attempts! In this economy! Domovoi, is that even legal?"),
	]

	# --- Economy: daily needs (systems/economy/village_economy.gd) --------
	# village_hungry / village_cold: {village_id, village_name}
	#
	# These fire when a village has actually gone without for six seconds, not
	# on a one-frame dip. Both Voices read the same fact differently, which is
	# the point of having two of them: Domovoi counts the cost, Hiisi enjoys
	# the drama.
	_pairs[&"village_hungry"] = [
		_p("vh1",
			"{village} has eaten the last of it. Whatever they do tomorrow, they will do it hungry.",
			"Hungry people are wonderfully decisive. Nobody deliberates on an empty stomach."),
		_p("vh2",
			"No food left in {village}. They will pray harder now, and mean it less.",
			"Mean it less! Domovoi, that is nearly a joke. I am so proud."),
		_p("vh3",
			"The stores at {village} are empty. Send them a harvest or watch what they decide about you.",
			"Watch either way. That is the good part."),
	]
	_pairs[&"village_cold"] = [
		_p("vc1",
			"{village} is burning the last of its wood. After that it is just people and the weather.",
			"And the weather has never once lost that argument."),
		_p("vc2",
			"No firewood at {village}. Cold does not kill them tonight, but they will remember who let it in.",
			"They always remember the cold. Never the summers. Very poor bookkeeping."),
		_p("vc3",
			"The fires are out in {village}. Someone should have been in the trees this afternoon.",
			"Someone was! Fishing. I watched. It was a beautiful waste of a day."),
	]

	# --- Economy: stockpile (systems/economy/village_economy.gd) ----------
	# stockpile_overflow: {village_id, village_name, resource}
	_pairs[&"stockpile_overflow"] = [
		_p("so1",
			"{village}'s store of {resource} is overflowing. It's sitting in the open now, rotting on principle.",
			"Rotting {resource}! My favourite sort! So much more character in it!"),
		_p("so2",
			"There is more {resource} in {village} than there is roof to keep it under. Build a store or stop hauling.",
			"Or eat the surplus. I keep offering. Nobody takes me up on it. I am a solution, Domovoi."),
		_p("so3",
			"Overflow at {village}. Every sack past the wall is work somebody did for nothing.",
			"For NOTHING? No, no. For the rain. The rain is extremely grateful."),
		_p("so4",
			"{resource} spilling out of {village}'s stores. That isn't wealth, that's waste with good manners.",
			"Waste with good manners is still a party, if you arrive early enough."),
		_p("so5",
			"They've filled the store past its limit again. I would like a granary. I have wanted a granary for some time.",
			"He's wanted a granary since before there was grain. It's very moving."),
	]

	# --- Weather (systems/weather/weather.gd) -----------------------------
	# storm_forming: {wind_speed} (+ optional forced flag)
	_pairs[&"storm_forming"] = [
		_p("stf1",
			"There's a front building out on the water. Wind's at {wind} paces a second. Get the boats in and the shutters down.",
			"Or leave them out! Boats are so much more interesting once they're airborne!"),
		_p("stf2",
			"Storm forming. It will cross the island whether or not anyone is ready, so I would suggest ready.",
			"Nobody is ever ready. That's what makes weather the best of all the gods."),
		_p("stf3",
			"Wind's at {wind} and climbing. The ones who fish are already tying things down; the rest are still arguing about it.",
			"The arguing ones are my favourites. They'll argue right up until the roof leaves."),
		_p("stf4",
			"There's weather coming. Real weather, not a rite — nobody cast this and nobody can un-cast it.",
			"Something bigger than us and not remotely interested in us. Refreshing!"),
		_p("stf5",
			"A front's turning storm. I'll say this once: the fields don't need saving. The people under the roofs do.",
			"Roofs! Roofs are the enemy! ...No. Wait. I've got that backwards. Roofs are the friend. Sorry. Sorry."),
	]

	# storm_broke: {wind_speed} (+ optional source flag)
	_pairs[&"storm_broke"] = [
		_p("stb1",
			"It's broken over us. {wind} paces a second of wind, and everything not lashed down is now somebody's memory.",
			"MAGNIFICENT. Look at it! Look at the water going sideways!"),
		_p("stb2",
			"Storm's on us. Nobody's working, nobody's praying, everybody's holding a door shut.",
			"Holding a door shut is a kind of prayer. A very physical one. I approve."),
		_p("stb3",
			"It hit. Roofs will go, boats will go, and we'll be counting in the morning as we always do.",
			"Count in the morning, dance now! Nobody's watching, the sky's far too loud to notice!"),
		_p("stb4",
			"{wind} paces a second. That isn't a squall, that's a season's worth of wind in one afternoon.",
			"Say a bigger number! Lie a little! It's more fun for everyone!"),
		_p("stb5",
			"The storm's broken. This is the part of being a god that is largely watching.",
			"Watching is underrated. It's what I do best. That, and the other thing."),
	]

	# storm_calmed: {} — no context keys at all, so no placeholders here.
	_pairs[&"storm_calmed"] = [
		_p("stc1",
			"It's calmed. Everything's dripping, nothing's alight, and I'll take that as a good day.",
			"Nothing's alight? Give it an hour."),
		_p("stc2",
			"Storm's off us. Get people onto the roofs before the next one, not after.",
			"After is more dramatic. But fine! Fine! Be practical! See if I care!"),
		_p("stc3",
			"Wind's down. That quiet you can hear is a great many people deciding they survived.",
			"That quiet is my least favourite noise. Let's ruin it. Let's ring something."),
		_p("stc4",
			"Calm again. The sea is still cross about something, but it's cross quietly now.",
			"The sea's always cross. It hasn't any arms. I'd be cross too."),
	]

	# storm_passed: {age} — a storm front leaving the sea entirely.
	_pairs[&"storm_passed"] = [
		_p("stp1",
			"The storm's gone off over the water. Whatever it does out there isn't ours to write down.",
			"Somebody else's problem! The sweetest four words in any language."),
		_p("stp2",
			"It's passed. Off it goes to bother the horizon, which frankly has it coming.",
			"Give the horizon my regards. And my compliments to the lightning."),
		_p("stp3",
			"Front's out of range. I'll close the entry: some roofs, no lives. This time.",
			"'This time' is carrying an enormous amount of weight in that sentence, little ledger."),
		_p("stp4",
			"Gone. And already the fields look as though nothing happened, which is exactly how nobody ever remembers to build the sea wall.",
			"Nobody ever builds the sea wall. It's tradition. It's practically a rite."),
	]

	# --- Missionaries (systems/faith/missionary.gd) ------------------------
	# missionary_arrived: {village_id}
	_pairs[&"missionary_arrived"] = [
		_p("mia1",
			"The missionary's reached {village}. Now comes the part that isn't walking: standing there being tolerated.",
			"Tolerated is the first course. Believed is the third. There's a lot of soup in between."),
		_p("mia2",
			"Arrived at {village}, footsore and unpaid. I'd budget for boots, if anyone let me budget for anything.",
			"Boots! Now there's a thing I've eaten. Not recently. Not proudly."),
		_p("mia3",
			"They're in place at {village}. Faith moves at walking speed, which is the one honest thing about it.",
			"Walking speed! Dreadful. I'd fly there and convert them all by descending impressively."),
		_p("mia4",
			"The missionary is stationed. Whether anybody actually listens is an entirely separate matter, and always has been.",
			"Nobody listens the first time. Nobody listens the second. The third time they claim it was their own idea."),
	]

	# missionary_recalled: {village_id = the abandoned target, home_village_id}
	_pairs[&"missionary_recalled"] = [
		_p("mir1",
			"Missionary recalled from {village}. Back to {home_village}, with nothing to show and a long walk to think about it.",
			"Long walks are where the good grudges get made. I'm excited about their grudge."),
		_p("mir2",
			"We've pulled them out of {village}. Whatever seed was planted there, we have just stopped watering it.",
			"Seeds are patient. Unlike me. Unlike you. Unlike anybody in this administration."),
		_p("mir3",
			"Recalled. Somebody in {village} will notice the preaching stopped and draw their own conclusions.",
			"Their conclusion will be that we got bored. Their conclusion will be correct."),
		_p("mir4",
			"Back to {home_village}, then. I'll mark the effort as spent, because it was, whatever we tell ourselves.",
			"Tell yourselves it was reconnaissance. That's what I say when I come home with nothing."),
	]

	# --- Reach / Faith (systems/faith/reach.gd) ---------------------------
	# village_helped: {village_id, amount, gain}
	_pairs[&"village_helped"] = [
		_p("vh1",
			"We've done {village} an actual kindness. Faith's up {gain}, and it will stay up, which is more than terror ever manages.",
			"Slow devotion. Dull devotion. Reliable devotion. I hate that it works."),
		_p("vh2",
			"Help given at {village}. That's the sort that compounds — they'll remember it next season, not just next morning.",
			"Next SEASON? I can't hold a thought past a meal. However do people manage it."),
		_p("vh3",
			"{village} was struggling and now it isn't, and the ledger is cleaner for it. Do more of this.",
			"He said do more of it. Out loud. In front of witnesses. You will never hear him say it again."),
		_p("vh4",
			"Devotion up {gain} at {village}, honestly earned. Nobody had to be frightened into it.",
			"Nobody frightened? Nobody at all? What a wasteful afternoon."),
		_p("vh5",
			"That is what the reach is for. Not smiting. Reaching. The name was rather a hint.",
			"The name was NOT a hint. Nothing is ever a hint. Everything should be shouted."),
	]

	# village_terrorized: {village_id, amount, gain}
	_pairs[&"village_terrorized"] = [
		_p("vt1",
			"{village} is terrified of us. Faith's up {gain}, and every point of it evaporates the moment they stop being afraid.",
			"Then keep them afraid! Simple! Sustainable! Exhausting! ...Oh. Oh, I've argued myself out of it."),
		_p("vt2",
			"Fear buys compliance. It has never once bought the last of anyone's devotion, and it never will.",
			"There's a ceiling on fear? Who put a ceiling on fear? I want their name."),
		_p("vt3",
			"We frightened {village} into line. They'll do as they're told and mean none of it.",
			"Meaning it is overrated. ...Is it? You've got the ledger. Is it?"),
		_p("vt4",
			"Terror at {village}, {gain} gained. I'll note the number, and I'll note the smell of the place afterwards.",
			"The smell is the worst part. Fear smells like wet metal. Nothing tastes right in a room that smells like that."),
		_p("vt5",
			"That's the fast way. Fast ways are fast because somebody else pays the difference later.",
			"Somebody else always pays. I'd know. I've been somebody else."),
	]

	# --- Villagers (actors/villagers/villager.gd) --------------------------
	# village_child_born: {village_id, culture_id}. Hiisi's appetite jokes
	# never point at a child — he refuses the joke himself, which is both
	# funnier and inside the audited comedic-target rule.
	_pairs[&"village_child_born"] = [
		_p("vcb1",
			"A child's been born in {village}. Put it in the good column. There isn't a great deal in the good column.",
			"A small one! With the tiny hands! I'm not making my usual joke. I've decided. Don't ask me again."),
		_p("vcb2",
			"New child in {village}. That's another mouth, another pair of hands eventually, and about fifteen years of somebody worrying.",
			"Fifteen years! I can't plan fifteen minutes! Astonishing creatures, people."),
		_p("vcb3",
			"Born healthy, as far as anyone can tell. The {culture} will name them properly at the proper time; that's their business, not ours.",
			"Not ours! Look at us! Respecting a custom! Somebody mark the day."),
		_p("vcb4",
			"{village} has a new child. They'll grow up assuming whatever we do is normal, which is a horrifying responsibility nobody assigned us.",
			"It's the best sort of responsibility. The sort you can't be dismissed from."),
		_p("vcb5",
			"One more in {village}. Let the record show this happened without a single rite, miracle, or intervention from us.",
			"People simply making more people. No divine input whatsoever. Frankly it undermines the entire department."),
	]

	_pairs[&"village_child_matured"] = [
		_p("vcm1",
			"The child in {village} is grown. Straight onto the work rota, no ceremony, because there is never time for ceremony.",
			"There is ALWAYS time for ceremony. I'd hold one now. I'd eat the ceremony."),
		_p("vcm2",
			"That's a new adult in {village}. They'll be praying, hauling and complaining by evening, like everybody else.",
			"Complaining is the true rite of adulthood. Nobody teaches it. Everyone learns it."),
		_p("vcm3",
			"Grown. I remember when that one was a line in the ledger. Now it's a line in the ledger with opinions.",
			"Opinions! Ugh. I liked them better when they only gurgled."),
		_p("vcm4",
			"{village}'s count is up by one, honestly come by, no miracle involved. Enjoy the novelty.",
			"Nothing we did! Nothing at all! We are the least necessary gods on this sea and I love it here."),
	]

	# villager_collapsed: {village_id, culture_id} — prayer fatigue. This is
	# the game teaching the player the calling-stone limit before the worse
	# version of the lesson arrives.
	_pairs[&"villager_collapsed"] = [
		_p("vco1",
			"Someone in {village} has collapsed at the stone. They were praying past what a body has in it.",
			"Rest them. I say that rarely and I mean it rarely, and I mean it: rest them."),
		_p("vco2",
			"Down in the dirt at {village}. Devotion isn't free — it comes out of the same body that does the hauling.",
			"Nobody warned me that worship was strenuous."),
		_p("vco3",
			"That's fatigue, not weakness. Ease off the calling stone and they'll be back on their feet.",
			"And if you don't ease off, they won't be. That's not a threat, that's arithmetic. I hate that I know arithmetic."),
		_p("vco4",
			"Collapsed. They'll recover, if left alone. That 'if' is doing an enormous amount of work.",
			"Your ifs are always doing enormous amounts of work. Let the poor ifs rest as well."),
		_p("vco5",
			"One down at {village}. The stone doesn't know when to stop asking. We're the ones who are supposed to.",
			"We're supposed to do a great many things. This one, though — this one, let's actually do."),
	]

	# villager_died_praying: {village_id, culture_id}. Hard rule 7 territory.
	# Both voices condemn it outright; Hiisi explicitly refuses his own bit.
	# Nothing here may read as a good trade, because it never is one — the
	# call site itself shifts Naklon toward cruelty and earns the player the
	# epithet "The One Who Prayed Them to Death".
	_pairs[&"villager_died_praying"] = [
		_p("vdp1",
			"Someone in {village} has died at prayer. Not for us. At us. There is no version of this ledger where that is a gain.",
			"I make a joke about eating everything. I am not making one about this."),
		_p("vdp2",
			"They knelt until the body gave out, because we kept asking. Write the name. Write it properly.",
			"Write it twice. And put the real reason beside it, not the tidy one."),
		_p("vdp3",
			"That's a death and it belongs to us. No enemy, no storm, no rival god. Us.",
			"I'd blame Louhi. I'd love to blame Louhi. She wasn't here."),
		_p("vdp4",
			"{village} has lost somebody to the calling stone. They'll keep praying anyway. That is the part I can't get out of my throat.",
			"They shouldn't. If I were them I'd have gone into the trees and stayed there."),
		_p("vdp5",
			"There is nothing to gain here. Devotion bought this way costs more than it pays, in every ledger I have ever kept.",
			"Even I know that. And I'm the one who's meant to want the worst thing in the room."),
		_pw(0.6, "vdp6",
			"A god that prays its people to death has run out of things to call itself.",
			"It has one name left, and it's a bad one, and somebody is already writing it down."),
	]

	# villager_forced_to_kneel: {village_id, culture_id}. Fires only when a
	# collapsed villager was dragged back to prayer and survived the roll.
	_pairs[&"villager_forced_to_kneel"] = [
		_p("vfk1",
			"They were on the ground, and we put them back on their knees. That isn't devotion. That's a hand on the back of a neck.",
			"And they survived it. This time. Don't make me say 'this time' again."),
		_p("vfk2",
			"Forced back to prayer while collapsed. There was a real chance that killed them. There will be again.",
			"Roll the bones often enough and the bones stop being funny."),
		_p("vfk3",
			"That one couldn't stand and prayed regardless, because we wanted the numbers. I'd like the numbers to know that.",
			"Numbers can't know things. That's why you keep them. Very convenient for you."),
		_p("vfk4",
			"The calling stone asked for more than {village} has, and we answered by taking it out of a body with nothing left in it.",
			"There's a word for that and the word isn't 'faith.'"),
		_p("vfk5",
			"They knelt. They didn't choose to. Whatever devotion we get from this is worth precisely what it sounds like.",
			"It sounds like a man being helped to his knees by a god. I have heard nicer sounds."),
	]

	# --- Wildlife (actors/wildlife/wildlife_manager.gd) -------------------
	# Landed in the repo while this pass was being written; that package
	# says in its own comment that it can't edit this file, so the pools
	# are authored here. wildlife_kill: {species, predator};
	# wildlife_scattered: {species}. That package already rate-limits its
	# own alarm trigger, so neither appears in _PACING_COOLDOWN_MSEC.
	_pairs[&"wildlife_kill"] = [
		_p("wk1",
			"A {species} has been taken by a {predator} out in the open. That's the island working as intended, and I still don't have to enjoy it.",
			"THAT is how it's done! No altar, no rite, no forms! Just appetite and follow-through!"),
		_p("wk2",
			"One fewer {species} on the hill. Nothing we did, nothing we can bill anyone for.",
			"Nothing we did? I cheered. Cheering is participation."),
		_p("wk3",
			"The {predator} has eaten. The villagers will tell it wrong by evening and there'll be a monster in it.",
			"There should be a monster in it! Tell them there were two! Tell them one of them was me!"),
		_p("wk4",
			"Kill on the slope. I mention it only because it's the sort of thing that empties a snare line and then a larder.",
			"Everything empties a larder eventually. That's what larders are for. Ask anyone. Ask me."),
	]

	_pairs[&"wildlife_scattered"] = [
		_p("ws1",
			"Something's put the {species} to flight. When the animals leave a hillside, the hunters find out a day later and hungrier.",
			"They ran! Look at them go! I do love a good scattering, it's the most honest thing a crowd can do."),
		_p("ws2",
			"The {species} have scattered. Whatever startled them was probably us, and it usually is.",
			"It was definitely us. It's always us. We're enormous and we shout."),
		_p("ws3",
			"Game's bolted off the slope. That's tomorrow's hunt walking away over the ridge.",
			"Then chase it! ...No? Nobody? Fine. I'll simply think about it very hard instead."),
		_p("ws4",
			"Every animal on that hillside moved at once. They know something, and they aren't in the habit of explaining.",
			"They never explain. Rudest neighbours on the island, and I include the bog in that."),
	]

## Convenience for callers who just want to know a trigger exists without
## rolling the dice — used by Voices' own doc-generation, not required by
## the public react()/pick_pair() contract.
func known_triggers() -> Array[StringName]:
	var out: Array[StringName] = []
	for k in _pairs.keys():
		out.append(k)
	return out
