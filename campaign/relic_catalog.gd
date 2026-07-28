class_name RelicCatalog
extends RefCounted
## Static table of every real, invented relic in the game — the single
## source of truth `CampaignManager` (and anything else, e.g. a future UI
## pass) resolves `GameState.relics_held` ids against. Same shape as
## `systems/sigils/sigil_templates.gd`'s `get_raw_templates()`: a plain
## static builder function returning fresh data rather than a cached
## singleton, since lookups here are rare (quest completion, a debug/QA
## panel, a future inventory UI) and not a per-frame hot path.
##
## Every entry is checked against docs/audit/respect_audit.md's hard rules
## before being written — see each Relic's own `origin_notes` for the
## one-line rationale, and docs/systems/campaign.md's relic table for the
## full picture in one place.

static func _make(id: StringName, display_name: String, culture_id: StringName,
		flavor: String, origin_notes: String, grants_epithet: String = "") -> Relic:
	var r := Relic.new()
	r.id = id
	r.display_name = display_name
	r.culture_id = culture_id
	r.flavor = flavor
	r.origin_notes = origin_notes
	r.grants_epithet = grants_epithet
	return r

## id -> Relic. Rebuilt fresh on every call (see class doc for why that's fine).
static func build() -> Dictionary:
	return {
		&"fenrayt_raft_bell": _make(
			&"fenrayt_raft_bell",
			"Raft-Bell of the Sinking",
			&"fenrayt",
			"A hand-bell lashed to the last raft sent down before the Fenrayt bound themselves to a kinder patron. It should have gone under with the rest of that year's work. Somebody fished it back out, quietly, and never said who.",
			"Tied to Fenrayt's own vetted ritual (see ritual_notes in data/cultures/fenrayt.tres) — the Sinking is a willing, inanimate gift, explicitly the thing the Offering-Debt taboo is set against, not a version of it."
		),
		&"sankiln_firereading_bowl": _make(
			&"sankiln_firereading_bowl",
			"Firereading Bowl",
			&"sankiln",
			"Ash-grey ceramic, its inner glaze crazed white where a thousand fistfuls of grain have gone in to be read by the color the flame turns. Whatever it hears, it never repeats — that's the elders' job.",
			"Tied to Sankiln's own vetted ritual (ritual_notes in data/cultures/sankiln.tres): 'advice, not worship' — a hearth-reading practice invented for this game, not a real divination rite depicted under its own name."
		),
		&"raimborn_wavecall_horn": _make(
			&"raimborn_wavecall_horn",
			"Wavecall Horn",
			&"raimborn",
			"Whalebone, worn pale at the mouthpiece by every crew that ever hummed one held note into the surf before a launch and waited to hear if the sea answered.",
			"Tied to Raimborn's own vetted ritual (ritual_notes in data/cultures/raimborn.tres): 'costs nothing and nobody is thrown to it' — explicitly a free, harmless custom, not a real seafaring rite under its own name."
		),
		&"vainkeeper_grafting_knife": _make(
			&"vainkeeper_grafting_knife",
			"Grafting Knife of the First Name",
			&"vainkeeper",
			"A short, bark-stained blade, its handle carved with the first name anyone ever grafted into a living tree instead of cutting it into a stone that couldn't grow.",
			"Tied to Vainkeeper's own vetted ritual (ritual_notes in data/cultures/vainkeeper.tres): 'nothing is asked of it but growth' — a naming custom invented for this game."
		),
		&"warning_staves_bundle": _make(
			&"warning_staves_bundle",
			"The Four Warning-Staves",
			&"",
			"Four carved staves lashed together, one notched in each people's own hand, each recording the same warning in a different accent: never pay a debt in anything that was alive and unwilling. No two staves agree on much else.",
			"Directly embodies respect_audit.md hard rule 7 — the Offering-Debt is written as a named, in-fiction-condemned taboo, never an authentic practice. This relic is literally the four cultures' own joint memorial against it, naming each culture's already-canon taboo (Offering-Debt/Ash-Debt/Keel-Debt/Root-Debt from data/cultures/*.tres's taboo_notes) as a crime, never a practice."
		),
		&"ninefold_tally_cord": _make(
			&"ninefold_tally_cord",
			"Tally-Cord of the Ninefold Sea",
			&"",
			"A knotted cord, one knot for every name a mortal has ever given the quiet god who still answers. Nobody remembers who started it or when the ninth sea got its name; the cord just keeps gaining knots.",
			"Ties to this game's own invented frame-myth (README.md's 'Ninefold Sea', GameState.current_island &\"ostrivka_alaas\") rather than any real-world sea, cosmology, or naming tradition."
		),
		&"waking_den_stone": _make(
			&"waking_den_stone",
			"Waking-Den Stone",
			&"",
			"Worn smooth in a den no living bear, wolverine, or stag ever dug — whichever shape the Avatar first woke into, something in this stone still remembers the weight of that first waking.",
			"Deliberately generic across all three Avatar species names rather than naming one specifically, since `GameState.avatar_species` is a player choice this package can't assume. Otso/Krukk/Sarv are already cleared as 'creature names, not deity names' per respect_audit.md's sourcing table.",
			"First-Named"
		),
		&"louhi_hidden_sun_sliver": _make(
			&"louhi_hidden_sun_sliver",
			"Sliver of the Hidden Sun",
			&"",
			"A curl of dull gold, cold to the touch, the size and shape of what you'd chip off something enormous if you only dared take a sliver. It does not shine. It remembers shining.",
			"Drawn from Louhi's own already-vetted Kalevala role — she hides the sun and moon inside a mountain, the exact episode README.md's own phrase 'hoarder of the sun' already references — not an invented cruelty, and not a real sacred object; a 19th-century literary epic's own plot device, same sourcing as Louhi herself.",
			"Touched the Hidden Sun"
		),
	}

static func get_relic(id: StringName) -> Relic:
	return build().get(id, null)

static func exists(id: StringName) -> bool:
	return build().has(id)

static func get_all_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for k in build().keys():
		out.append(k)
	return out
