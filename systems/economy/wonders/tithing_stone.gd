extends Wonder
class_name TithingStoneWonder
## Package H — the Tithing Stone. A carved marker the village keeps at its
## heart, insisting every gift given up the hill be counted twice. Real
## persistent effect: +20% devotion generation, for as long as the Wonder
## stands, on every bit of devotion this village produces afterward.
##
## Hooked directly into the foundation: GameState.add_devotion() (see
## core/game_state.gd) already emits `devotion_changed(village_id,
## new_amount)` every time ANY system credits a village with devotion —
## villagers praying at a Calling Stone (actors/villagers/villager.gd,
## package G) being the current caller. VillageEconomy listens to that
## signal (see village_economy.gd, `_on_devotion_changed`) and, when this
## Wonder is present, immediately grants a top-up equal to
## DEVOTION_BONUS_MULTIPLIER * (whatever delta just landed), via another
## GameState.add_devotion call. This means the bonus applies automatically
## to devotion from ANY current or future source that goes through
## GameState.add_devotion, without this package needing to know who's
## calling it or editing package G's files.

const DEVOTION_BONUS_MULTIPLIER: float = 0.20

func _init() -> void:
	super._init()
	id = &"wonder_tithing_stone"
	display_name = "The Tithing Stone"
	description = "A carved marker at the village heart that insists every gift given upward be counted twice. Devotion produced here afterward is worth a fifth more."
	cost = {&"stone": 90.0, &"wood": 20.0}
	build_time_seconds = 100.0

static func is_present(village: Village) -> bool:
	return village != null and (&"wonder_tithing_stone" in village.wonders)
