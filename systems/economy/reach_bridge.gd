extends RefCounted
class_name EconomyReachBridge
## Package H — the documented integration point for the Far Bell Wonder's
## Reach bonus (see wonders/far_bell.gd for why this is a wrapper rather
## than an edit to systems/faith/reach.gd, which package H does not own).
##
## Any system that wants the Far-Bell-aware radius today can call
## `effective_radius()`/`can_act_at()` here instead of Reach's own
## `radius_for_village()`/`can_act_at()` — same contract, plus the bonus.

static func radius_bonus(village_id: StringName) -> float:
	var v: Village = GameState.get_village(village_id)
	if v == null:
		return 0.0
	return FarBellWonder.REACH_BONUS_METERS if FarBellWonder.is_present(v) else 0.0

## Drop-in replacement for Reach.radius_for_village(village_id) that also
## accounts for the Far Bell Wonder.
static func effective_radius(village_id: StringName) -> float:
	return Reach.radius_for_village(village_id) + radius_bonus(village_id)

## Drop-in replacement for Reach.can_act_at(world_pos) that also accounts
## for the Far Bell Wonder.
static func can_act_at(world_pos: Vector3) -> bool:
	for village in GameState.villages.values():
		if village.loyal_to_rival:
			continue
		var origin := Vector3(village.position_on_island.x, 0.0, village.position_on_island.y)
		if origin.distance_to(Vector3(world_pos.x, 0.0, world_pos.z)) <= effective_radius(village.id):
			return true
	return false
