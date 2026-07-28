extends RefCounted
class_name BuildingCatalog
## Package H — the registry of every constructable BuildingType/Wonder,
## keyed by id. VillageEconomy.start_construction() looks types up here by
## StringName so callers (UI, campaign, a future build-menu) only ever need
## to know the id, e.g. &"gathering_house" or &"wonder_far_bell".

static var _catalog: Dictionary = {} # StringName -> BuildingType

static func all() -> Dictionary:
	if _catalog.is_empty():
		_register(GatheringHouseBuilding.new())
		_register(StorehouseBuilding.new())
		_register(WorkyardBuilding.new())
		_register(TithingStoneWonder.new())
		_register(SwiftYardsWonder.new())
		_register(FarBellWonder.new())
	return _catalog

static func _register(building: BuildingType) -> void:
	_catalog[building.id] = building

static func get_type(id: StringName) -> BuildingType:
	return all().get(id, null)

static func buildings_only() -> Array[BuildingType]:
	var out: Array[BuildingType] = []
	for b in all().values():
		if not b.is_wonder:
			out.append(b)
	return out

static func wonders_only() -> Array[BuildingType]:
	var out: Array[BuildingType] = []
	for b in all().values():
		if b.is_wonder:
			out.append(b)
	return out
