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

## trigger -> Array of pairs. Each pair is a 2-element Array[VoiceLine]:
## [domovoi_line, hiisi_line], said back-to-back.
var _pairs: Dictionary = {}

func _init() -> void:
	_build_pairs()

## Picks a pair not present (by id) in `recent` when possible, formats any
## "{placeholder}" tokens against `context`, and returns fresh VoiceLine
## copies (so callers get already-formatted text without mutating the pool).
func pick_pair(trigger: StringName, context: Dictionary, recent: Array[String]) -> Array:
	var pairs: Array = _pairs.get(trigger, [])
	if pairs.is_empty():
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

	var chosen: Array = candidates[randi() % candidates.size()]
	var placeholders := _placeholders(context)
	var out: Array = []
	for line in chosen:
		var src: VoiceLine = line
		var text: String = src.text
		if text.find("{") != -1:
			text = text.format(placeholders)
		out.append(VoiceLine.new(src.id, src.speaker, text))
	return out

## Builds the {village}/{culture}/{debt}/etc. substitution table for one
## react() call. Every key always resolves to *something* sensible so a
## line never ships with a literal unfilled "{token}" in it, even when the
## caller passed a sparse context.
func _placeholders(context: Dictionary) -> Dictionary:
	var vid: StringName = context.get("village_id", &"")
	var cid: StringName = context.get("culture_id", &"")

	var village_name := "that village"
	if vid != &"":
		var v: Village = GameState.get_village(vid)
		if v:
			village_name = v.display_name
			if cid == &"":
				cid = v.culture_id

	var culture_name := "somebody's"
	var debt_name := "Old Debt"
	if cid != &"":
		var c: Culture = GameState.cultures.get(cid, null)
		if c:
			culture_name = c.display_name
		debt_name = _DEBT_NAMES.get(cid, "Old Debt")

	return {
		"village": village_name,
		"culture": culture_name,
		"debt": debt_name,
		"epithet": str(context.get("epithet", "a new name")),
		"reason": str(context.get("reason", "reasons nobody wrote down")),
		"method": str(context.get("method_id", context.get("method", "the usual method"))),
		"amount": str(context.get("amount", "some")),
	}

func _p(id: String, d_text: String, h_text: String) -> Array:
	return [VoiceLine.new(id + "_d", DOMOVOI, d_text), VoiceLine.new(id + "_h", HIISI, h_text)]

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
			"That is an {debt}, and every {culture} elder could describe it in loving, horrified detail. We just did it.",
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

## Convenience for callers who just want to know a trigger exists without
## rolling the dice — used by Voices' own doc-generation, not required by
## the public react()/pick_pair() contract.
func known_triggers() -> Array[StringName]:
	var out: Array[StringName] = []
	for k in _pairs.keys():
		out.append(k)
	return out
