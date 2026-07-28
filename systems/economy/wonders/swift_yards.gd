extends Wonder
class_name SwiftYardsWonder
## Package H — the Swift Yards. The Wonder-tier version of a Workyard: every
## woodcutter and quarry-hand in the village works as if the whole village
## were leaning over their shoulder helping. Real persistent effect: +35%
## to this village's wood and stone production rate, stacking additively
## with any Workyard buildings already raised (see
## VillageEconomy._tick_production).
##
## This is package H's own reading of the brief's "+Y villager work speed"
## Wonder: it speeds up the *economy system's* production tick, which is
## the whole of what this package owns and can honestly claim to move.
## Actually slowing/quickening the Villager state-machine's animation or
## per-task duration lives in actors/villagers/villager.gd (package G) and
## is out of this package's write access — scoped out here rather than
## silently faked; see "Scoped out" in docs/systems/economy.md for the
## one-line hook G could add (checking this Wonder's is_present()) if a
## future pass wants the visible walk/chop animation itself to speed up
## too, not just its output.

const PRODUCTION_BONUS_MULTIPLIER: float = 0.35

func _init() -> void:
	super._init()
	id = &"wonder_swift_yards"
	display_name = "The Swift Yards"
	description = "Every bench and bin turned to face every other. Wood and stone come off this village's yards more than a third faster."
	cost = {&"wood": 110.0, &"stone": 60.0}
	build_time_seconds = 120.0

static func is_present(village: Village) -> bool:
	return village != null and (&"wonder_swift_yards" in village.wonders)
