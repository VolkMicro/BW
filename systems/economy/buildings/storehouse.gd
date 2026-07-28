extends BuildingType
class_name StorehouseBuilding
## Package H — the Storehouse. Raises the village's stockpile cap for every
## resource (see Stockpile.capacity / STOREHOUSE_CAPACITY_BONUS) so surplus
## wood, food, and stone stop rotting/rusting/spoiling in the open once
## production outpaces what a bare yard can hold. Stacks with every
## Storehouse built on the same village.
##
## Like Gathering House, the bonus is read live off village.buildings
## (Stockpile.capacity() counts &"storehouse" occurrences directly) rather
## than cached anywhere, so on_complete needs no extra bookkeeping.

func _init() -> void:
	id = &"storehouse"
	display_name = "Storehouse"
	description = "Raised planks and a turfed roof over the yard. Wood, food, and stone stop spoiling in the open once there's somewhere dry to stack them."
	cost = {&"wood": 45.0, &"stone": 15.0}
	build_time_seconds = 35.0
	max_per_village = -1
