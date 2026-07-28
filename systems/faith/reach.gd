extends Node
## Autoload. Reach = the radius around converted villages where the god can
## touch anything at all (Hand grabs, rites resolve, sigils are even legible
## to the world). Reach grows with total converted population. This node
## also owns per-village, per-method conversion fatigue: hammering a village
## with the same miracle over and over should visibly stop working.

const BASE_REACH_PER_HEAD := 0.6 # meters of radius per convert, tuned against island scale in world/terrain
const FATIGUE_RISE_PER_USE := 0.28
const FATIGUE_DECAY_PER_SECOND := 0.015 # ~65s to fully forget a method if left alone

# --- Package J additions below: missionary/help/terror conversion curves,----
# --- and eased (non-instant) radius readback for cosmetic consumers. -------
# Public API added here is documented in docs/systems/reach_faith.md.

## village_id -> currently-eased radius (see smoothed_radius_for_village()).
## Separate from radius_for_village(), which stays instant/authoritative so
## gameplay gating never lags behind true state.
var _smoothed_radius: Dictionary = {}
const RADIUS_SMOOTH_RATE := 0.35 # exponential closing rate; ~3s to close 90% of a sudden gap

## Requested faith_fraction gain -> actual gain multiplier constants per
## conversion method. See convert_via_help/convert_via_terror/
## convert_via_missionary below for how these combine with effectiveness().
const HELP_GAIN_PER_AMOUNT := 0.05
const HELP_CEILING := 1.0 # a fed, healed village can come all the way to genuine devotion
const HELP_NAKLON_SHIFT_PER_AMOUNT := -0.01 # mercy
const HELP_NAKLON_WEIGHT := 0.4

const TERROR_GAIN_PER_AMOUNT := 0.07 # terror lands harder per "unit" than help does...
const TERROR_CEILING := 0.85 # ...but fear-compliance alone never becomes full devotion.
const TERROR_NAKLON_SHIFT_PER_AMOUNT := 0.015 # cruelty
const TERROR_NAKLON_WEIGHT := 0.6

const MISSIONARY_CEILING := 1.0 # slow, patient conversion can go all the way

func _process(delta: float) -> void:
	for village in GameState.villages.values():
		_decay_fatigue(village, delta)
		_update_smoothed_radius(village, delta)

func _decay_fatigue(village: Village, delta: float) -> void:
	for method_id in village.method_fatigue.keys():
		var entry: Dictionary = village.method_fatigue[method_id]
		entry.fatigue = maxf(0.0, entry.fatigue - FATIGUE_DECAY_PER_SECOND * delta)
		village.method_fatigue[method_id] = entry

## Returns 0..1 multiplier applied to a conversion method's effectiveness on
## a given village. 1.0 = fresh (full effect), approaching 0 = "they glance
## up without putting down their tools."
func effectiveness(village_id: StringName, method_id: StringName) -> float:
	var v: Village = GameState.get_village(village_id)
	if v == null:
		return 0.0
	var entry: Dictionary = v.method_fatigue.get(method_id, {"uses": 0, "fatigue": 0.0})
	return 1.0 - entry.fatigue

## Call after resolving a conversion-relevant miracle (fire from clear sky,
## a healed plague, a missionary sermon, the Avatar simply being seen).
func register_use(village_id: StringName, method_id: StringName) -> void:
	var v: Village = GameState.get_village(village_id)
	if v == null:
		return
	var entry: Dictionary = v.method_fatigue.get(method_id, {"uses": 0, "fatigue": 0.0})
	entry.uses += 1
	entry.fatigue = clampf(entry.fatigue + FATIGUE_RISE_PER_USE * (1.0 - entry.fatigue), 0.0, 1.0)
	v.method_fatigue[method_id] = entry

## Total radius, in meters, the god can currently act within. Territory
## rendering (world/terrain/reach_border.gdshader) reads this per village
## rather than drawing any UI overlay, per design brief.
func radius_for_village(village_id: StringName) -> float:
	var v: Village = GameState.get_village(village_id)
	if v == null or v.loyal_to_rival:
		return 0.0
	var converts := v.population * v.faith_fraction
	return 8.0 + converts * BASE_REACH_PER_HEAD

func can_act_at(world_pos: Vector3) -> bool:
	for village in GameState.villages.values():
		if village.loyal_to_rival:
			continue
		var origin := Vector3(village.position_on_island.x, 0.0, village.position_on_island.y)
		if origin.distance_to(Vector3(world_pos.x, 0.0, world_pos.z)) <= radius_for_village(village.id):
			return true
	return false

func _update_smoothed_radius(village: Village, delta: float) -> void:
	var target := radius_for_village(village.id)
	var current: float = _smoothed_radius.get(village.id, target)
	var t := 1.0 - exp(-RADIUS_SMOOTH_RATE * delta)
	_smoothed_radius[village.id] = lerpf(current, target, t)

## Same number as radius_for_village(), but exponentially eased instead of
## snapping the instant population/faith_fraction change (a villager dying
## to a wolf, or ten converts landing in one prayer tick, shouldn't make
## whatever is reading this pop visibly). Verified: growth is already
## implicit because radius_for_village() reads population*faith_fraction
## live every call, so nothing further was needed to make Reach "grow with
## population" per the design note at the top of this file — the one real
## gap was that it had no continuity for cosmetic consumers, which this
## fixes without touching the authoritative instant getter. Gameplay gating
## (can_act_at, and radius_for_village itself) deliberately keeps reading
## the instant value so "can I act here" never lags true state.
func smoothed_radius_for_village(village_id: StringName) -> float:
	return _smoothed_radius.get(village_id, radius_for_village(village_id))


# ---------------------------------------------------------------------------
# Conversion methods beyond raw miracles. Each runs the requested amount
# through effectiveness()/register_use() exactly like calling_stone_prayer
# (systems/villagers/villager.gd) does, so repeated use fatigues per
# village AND per method automatically — no extra bookkeeping needed by
# callers. See docs/systems/reach_faith.md for the full method_id table.
# ---------------------------------------------------------------------------

## Shared growth curve: a requested fractional gain is scaled by this
## method's current effectiveness on this village (miracle fatigue) and by
## how much headroom is left before this method's ceiling, then applied to
## Village.faith_fraction. Returns the actual gain applied (0 if none).
## (Note: the &"calling_stone_prayer" method_id used by
## actors/villagers/villager.gd calls effectiveness()/register_use()
## directly rather than through this helper, since prayer devotion income
## and faith_fraction conversion are different currencies there — see
## docs/systems/reach_faith.md for the full method_id table.)
func _grow_faith(v: Village, method_id: StringName, requested_gain: float, ceiling: float) -> float:
	if requested_gain <= 0.0:
		return 0.0
	var eff := effectiveness(v.id, method_id)
	var headroom := clampf((ceiling - v.faith_fraction) / maxf(ceiling, 0.0001), 0.0, 1.0)
	var gain := requested_gain * eff * headroom
	if gain > 0.0:
		GameState.set_faith_fraction(v.id, minf(ceiling, v.faith_fraction + gain))
	register_use(v.id, method_id)
	return gain

## Helpful acts (feeding, healing, gifts). Method id: &"help".
## `amount` is caller-defined "how much help" (e.g. food units delivered,
## HP healed) — not a faith_fraction delta directly. Approaches full
## devotion (ceiling 1.0) with diminishing returns as the village nears it,
## and nudges Naklon toward mercy proportional to the act's size. Intended
## callers: systems/economy (H), any feeding/healing rite from sigils (F).
func convert_via_help(village_id: StringName, amount: float) -> float:
	var v: Village = GameState.get_village(village_id)
	if v == null or v.loyal_to_rival or amount <= 0.0:
		return 0.0
	var gain := _grow_faith(v, &"help", amount * HELP_GAIN_PER_AMOUNT, HELP_CEILING)
	Naklon.shift(HELP_NAKLON_SHIFT_PER_AMOUNT * amount, HELP_NAKLON_WEIGHT)
	Voices.react(&"village_helped", {"village_id": village_id, "amount": amount, "gain": gain})
	return gain

## Terror acts (lightning, fire-rain, plague made visible, etc). Method id:
## &"terror". `amount` is caller-defined "how much terror" (e.g. buildings
## struck, villagers burned). Capped at TERROR_CEILING (0.85) — fear buys
## compliance, never the last sliver of genuine devotion; combine with
## help/missionary/miracles to close the gap. Nudges Naklon toward cruelty.
## Intended callers: systems/sigils (F) lightning/fire-rain rites, Louhi (N)
## reprisals, etc.
func convert_via_terror(village_id: StringName, amount: float) -> float:
	var v: Village = GameState.get_village(village_id)
	if v == null or v.loyal_to_rival or amount <= 0.0:
		return 0.0
	var gain := _grow_faith(v, &"terror", amount * TERROR_GAIN_PER_AMOUNT, TERROR_CEILING)
	Naklon.shift(TERROR_NAKLON_SHIFT_PER_AMOUNT * amount, TERROR_NAKLON_WEIGHT)
	Voices.react(&"village_terrorized", {"village_id": village_id, "amount": amount, "gain": gain})
	return gain

## Missionary sermons. Method id: &"missionary". Called by
## systems/faith/missionary.gd once per station-tick while a Missionary is
## stood in a village; not intended to be called directly by other
## packages (call Missionary.spawn() instead), but left public since a
## future package may want to grant a one-off "sermon" without a physical
## missionary unit. Uncapped (ceiling 1.0): patient, present, un-fatigued
## missionary work can fully convert a village on its own, slowly.
func convert_via_missionary(village_id: StringName, amount: float) -> float:
	var v: Village = GameState.get_village(village_id)
	if v == null or v.loyal_to_rival or amount <= 0.0:
		return 0.0
	return _grow_faith(v, &"missionary", amount, MISSIONARY_CEILING)
