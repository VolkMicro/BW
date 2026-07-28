extends BuildingType
class_name Wonder
## Package H — base class for a Wonder: a one-per-village, expensive,
## slow-to-build structure with a real, persistent, game-affecting effect
## that outlives its own construction (unlike a Gathering House's food
## trickle, a Wonder's effect is meant to feel like a landmark decision).
##
## Every concrete Wonder below exposes its bonus as a plain constant plus a
## `static`-style query helper other systems can call directly — see each
## file for exactly which foundation system it hooks (GameState, this
## package's own production tick, or the Reach bridge). is_wonder=true here
## means VillageEconomy appends the finished id to village.wonders (a
## separate Array[StringName] field core/village.gd already exposes,
## distinct from village.buildings) instead of the buildings array.

func _init() -> void:
	is_wonder = true
	max_per_village = 1
