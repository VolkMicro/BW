extends Resource
class_name BuildingType
## Package H — base definition for one constructable building or Wonder
## type. A BuildingType is data + a hook (`on_complete`); the actual
## construction-time bookkeeping (elapsed time, queueing) lives in
## construction_site.gd and village_economy.gd, not here.
##
## Concrete building types (systems/economy/buildings/*.gd) and Wonders
## (systems/economy/wonders/*.gd, which extend the Wonder subclass below)
## set their fields in `_init()` and are registered once in
## building_catalog.gd. This mirrors how core/culture.gd instances are
## plain Resources rather than needing one script per culture — the
## difference here is these types carry a little behavior (`on_complete`),
## so they're .gd Resource subclasses rather than .tres data files.

@export var id: StringName
@export var display_name: String
@export var description: String

## resource -> amount, e.g. {&"wood": 40.0, &"stone": 10.0}. Keys must match
## Stockpile.RESOURCE_KEYS (see stockpile.gd) to actually be payable.
@export var cost: Dictionary = {}
@export var build_time_seconds: float = 30.0

## Wonders set this true in their own _init() (see wonders/wonder.gd) so
## VillageEconomy knows to append the finished id to village.wonders
## instead of village.buildings, matching the two separate Array fields
## core/village.gd already exposes.
@export var is_wonder: bool = false

## -1 = no limit (e.g. you can build any number of Gathering Houses).
## Wonders default to 1 (a village only ever raises one of each Wonder).
@export var max_per_village: int = -1

## Called exactly once, the instant construction finishes, before the id
## is appended to the village's buildings/wonders array. Override in a
## concrete subclass for one-time setup; ongoing persistent effects
## (production multipliers, devotion bonus, Reach bonus) are instead
## computed live by counting occurrences of `id` in the relevant array
## (see `count_in`) each time VillageEconomy or a Wonder helper needs the
## current bonus — that keeps the *only* durable state the two arrays
## core/village.gd already persists, with nothing of this package's own
## state at risk of falling out of sync with a save/load pass it doesn't
## own.
func on_complete(_village: Village) -> void:
	pass

func target_array(village: Village) -> Array:
	return village.wonders if is_wonder else village.buildings

func count_in(village: Village) -> int:
	var n := 0
	for entry in target_array(village):
		if entry == id:
			n += 1
	return n

func has_reached_limit(village: Village) -> bool:
	return max_per_village >= 0 and count_in(village) >= max_per_village

func can_afford(village: Village) -> bool:
	return Stockpile.can_afford(village, cost)
