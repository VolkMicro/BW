extends RefCounted
class_name ConstructionSite
## Package H — one in-progress build job. Cost is paid up front, in full,
## the moment the job is queued (see VillageEconomy.start_construction);
## `elapsed` then ticks toward `building.build_time_seconds` in
## VillageEconomy._process. Multiple sites can queue on the same village;
## they resolve one at a time, in order (see VillageEconomy._active_queue).

var village_id: StringName
var building: BuildingType
var elapsed: float = 0.0

func _init(p_village_id: StringName = &"", p_building: BuildingType = null) -> void:
	village_id = p_village_id
	building = p_building

func is_complete() -> bool:
	return building != null and elapsed >= building.build_time_seconds

func progress() -> float:
	if building == null or building.build_time_seconds <= 0.0:
		return 1.0
	return clampf(elapsed / building.build_time_seconds, 0.0, 1.0)

func remaining_seconds() -> float:
	if building == null:
		return 0.0
	return maxf(0.0, building.build_time_seconds - elapsed)
