extends BuildingType
class_name WorkyardBuilding
## Package H — the Workyard (craft-yard). A shared bench, kiln-adjacent
## tool rack, and enough hands-on-hands teaching that woodcutters and
## quarry-hands work measurably faster once one exists. Applied as a
## percentage bonus to wood/stone production (see
## VillageEconomy._tick_production, WORKYARD_PRODUCTION_BONUS), stacking
## additively per Workyard — this is the "structure that speeds up work"
## half of the brief's +Y villager work-speed ask; the Swift Yards Wonder
## (systems/economy/wonders/swift_yards.gd) is the Wonder-tier version of
## the same idea, bigger and one-per-village.

func _init() -> void:
	id = &"workyard"
	display_name = "Workyard"
	description = "A shared bench, a tool rack, and enough elbow room for woodcutters and quarry-hands to work off each other's rhythm instead of alone."
	cost = {&"wood": 40.0, &"stone": 25.0}
	build_time_seconds = 45.0
	max_per_village = -1
