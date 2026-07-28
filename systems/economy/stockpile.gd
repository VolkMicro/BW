extends RefCounted
class_name Stockpile
## Package H — per-village resource storage.
##
## core/village.gd (foundation, not owned by this package) has no wood/food/
## stone fields, and Package H does not edit core/ files. Instead every
## village's stockpile is attached to the Village *Resource instance itself*
## at runtime via Godot's built-in Object.set_meta/get_meta, under exactly
## one key:
##
##     const META_KEY: StringName = &"economy_stockpile"
##
## Dictionary shape stored under that key: { &"wood": float, &"food": float,
## &"stone": float } — all three keys always present after first touch
## (see `ensure()`). Any other package (villagers, sanctum, campaign, UI)
## can read the same convention directly without calling into this class:
##
##     var stock: Dictionary = village.get_meta(&"economy_stockpile", {})
##     var wood: float = stock.get(&"wood", 0.0)
##
## ...but going through Stockpile's static helpers is preferred because they
## also enforce the storage cap (see `capacity()`) and keep values >= 0.
##
## Requires-foundation-change note: the clean, permanent fix — once the
## foundation package is willing to take the change — is one line added to
## core/village.gd's export block:
##
##     @export var resources: Dictionary = {"wood": 0.0, "food": 0.0, "stone": 0.0}
##
## which would let this whole file collapse to plain field reads. This
## package does not make that edit itself (core/ is not ours to write to);
## this comment is the proposal, left here for whoever owns core/ next.

const META_KEY: StringName = &"economy_stockpile"
const RESOURCE_KEYS: Array[StringName] = [&"wood", &"food", &"stone"]

## Base storage cap per resource before a Storehouse is built. See
## systems/economy/buildings/storehouse.gd for the per-building bonus.
const BASE_CAPACITY: float = 120.0
const STOREHOUSE_CAPACITY_BONUS: float = 180.0

## Returns the village's stockpile dictionary, creating and attaching a
## fresh all-zero one on first use. Always returns the SAME dictionary the
## village carries (Dictionary is a reference type in GDScript), so callers
## may mutate the returned dictionary directly if they really want to, but
## prefer add()/spend() below so the capacity cap is respected everywhere.
static func ensure(village: Village) -> Dictionary:
	if village == null:
		return {}
	if not village.has_meta(META_KEY):
		var initial: Dictionary = {}
		for key in RESOURCE_KEYS:
			initial[key] = 0.0
		village.set_meta(META_KEY, initial)
	return village.get_meta(META_KEY)

static func get_amount(village: Village, resource: StringName) -> float:
	return ensure(village).get(resource, 0.0)

## Current storage cap for one resource on this village. A Storehouse
## building (systems/economy/buildings/storehouse.gd) raises this; without
## one, production that would overflow the cap is lost, exactly like grain
## rotting in the open — Voices.react(&"stockpile_overflow", ...) fires the
## first time this happens per village per resource per playthrough-ish
## (see VillageEconomy._tick_production).
static func capacity(village: Village, resource: StringName) -> float:
	if village == null:
		return BASE_CAPACITY
	var storehouses := 0
	for b in village.buildings:
		if b == &"storehouse":
			storehouses += 1
	return BASE_CAPACITY + float(storehouses) * STOREHOUSE_CAPACITY_BONUS

## Adds (or, with a negative amount, removes) a resource, clamped to
## [0, capacity]. Returns the resulting stored amount. Returns the amount
## that was actually absorbed (may be less than `amount` if the stockpile
## was near its cap) via the `absorbed` output — GDScript has no out
## params, so this returns a small result dictionary when `amount` is
## positive and simple float is not enough info; callers that don't care
## about overflow can ignore the extra field.
static func add(village: Village, resource: StringName, amount: float) -> Dictionary:
	var stock := ensure(village)
	var before: float = stock.get(resource, 0.0)
	var cap := capacity(village, resource)
	var after := clampf(before + amount, 0.0, cap)
	stock[resource] = after
	village.set_meta(META_KEY, stock)
	return {
		"new_amount": after,
		"absorbed": after - before,
		"overflowed": amount > 0.0 and (after - before) < amount - 0.0001,
	}

static func can_afford(village: Village, cost: Dictionary) -> bool:
	var stock := ensure(village)
	for resource in cost.keys():
		if stock.get(resource, 0.0) < float(cost[resource]):
			return false
	return true

## Deducts `cost` (a Dictionary of resource -> amount) all at once if
## affordable. Returns false and changes nothing if not affordable.
static func spend(village: Village, cost: Dictionary) -> bool:
	if not can_afford(village, cost):
		return false
	var stock := ensure(village)
	for resource in cost.keys():
		stock[resource] = stock.get(resource, 0.0) - float(cost[resource])
	village.set_meta(META_KEY, stock)
	return true

## Convenience for UI/other packages: a plain snapshot dictionary safe to
## hand to a HUD-less diegetic display without exposing the live reference.
static func snapshot(village: Village) -> Dictionary:
	return ensure(village).duplicate()
