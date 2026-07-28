extends BuildingType
class_name GatheringHouseBuilding
## Package H — the Gathering House. The cheapest, fastest building: a lean-to
## and a few baskets where the very young, the very old, and anyone not on
## a fishing/field/woodcutting shift bring back whatever the shoreline and
## verge give up for free. Represented as a flat passive food trickle,
## stacking with every Gathering House a village raises (see
## VillageEconomy._tick_production, FOOD_PER_GATHERING_HOUSE).
##
## No on_complete side effect needed: the bonus is computed live each tick
## by counting &"gathering_house" occurrences in village.buildings via
## BuildingType.count_in(), so there is nothing here that could fall out of
## sync with the array core/village.gd already persists.

func _init() -> void:
	id = &"gathering_house"
	display_name = "Gathering House"
	description = "A lean-to and a row of baskets. Feeds a few extra mouths from whatever the shore and verge give up for free, no shift assigned."
	cost = {&"wood": 25.0}
	build_time_seconds = 20.0
	max_per_village = -1
