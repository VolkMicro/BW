extends RefCounted
class_name Sacrifice
## Package I — the Offering mechanic.
##
## THIS IS THE IN-FICTION TABOO, NOT A RITE ANY CULTURE PRACTICES WILLINGLY.
## See docs/systems/sanctum.md ("The taboo, in fiction") for the full
## framing: every one of the four cultures in data/cultures/*.tres names
## this exact act as the one crime that voids their real, willingly-kept
## rite (the Sinking / the Wavecall / the Firereading / the Grafting), and
## names it themselves — Offering-Debt, Keel-Debt, Ash-Debt, Root-Debt.
## `offer()` is the mechanical enforcement of "this always costs you
## something and everyone in the fiction says so": it is never devotion-
## neutral, it always shifts Naklon hard toward cruelty, it always tells
## the Two Voices to react with disapproval, and it always locks the
## Sanctum's gentle repair path (see sanctum.gd `repair()`) for a real
## cooldown window afterward — a player cannot buy devotion in blood and
## then immediately paper over the damage.
##
## `offer()` is written as a set of static functions (no autoload needed,
## no instance to pass around) so any system — the Hand (actors/hand/),
## a campaign quest (campaign/), the economy tick (systems/economy/) — can
## call `Sacrifice.offer(village_id, target)` directly. Package I's own
## Sanctum node (sanctum.gd) forwards its `try_offer()` here rather than
## duplicating this logic.

## What `target` is understood to be. A generic goods/treasure offering
## needs no Node at all (pass null). A living offering is classified via
## (in priority order):
##   1. target.has_method(&"get_offering_kind") -> String/StringName
##      one of "child", "adult", anything else counts as an object.
##      This is the preferred contract for actors/villagers/ (package G)
##      and actors/avatar/ (package K) to implement explicitly.
##   2. target.is_in_group(&"villager_child") -> child
##      target.is_in_group(&"villager") or &"villager_adult" -> adult
##   3. Duck-typed properties: target.is_child == true -> child,
##      target.is_living == true -> adult (checked with the `in` operator
##      so a target missing the property entirely doesn't error).
## Anything that doesn't match any of the above (a prop, a stack of goods,
## an heirloom, a null target) is Kind.OBJECT.
enum Kind { OBJECT, LIVING_ADULT, LIVING_CHILD }

const KIND_LABEL := {
	Kind.OBJECT: &"object",
	Kind.LIVING_ADULT: &"living_adult",
	Kind.LIVING_CHILD: &"living_child",
}

## Instant devotion granted. Deliberately steep: an object is a token
## gesture, a living adult is a real crime, a child is the worst thing a
## god in this setting can be handed and is priced accordingly. Tunable —
## see docs/systems/sanctum.md "Scoped out" re: balance against
## systems/economy/'s passive devotion income once that lands.
const DEVOTION_GAIN := {
	Kind.OBJECT: 8.0,
	Kind.LIVING_ADULT: 40.0,
	Kind.LIVING_CHILD: 90.0,
}

## Naklon shift amount (before `weight`), always toward cruelty (positive).
const NAKLON_SHIFT := {
	Kind.OBJECT: 0.05,
	Kind.LIVING_ADULT: 0.3,
	Kind.LIVING_CHILD: 0.55,
}

## "shifts Naklon hard toward cruelty" per the brief — a heavy weight so a
## single offering moves the scalar far more than routine small actions do.
const NAKLON_WEIGHT := 3.0

## How long, in seconds, a village's Sanctum refuses its gentle repair path
## after any offering resolves there. Refreshed (not stacked) by each new
## offering. See is_offering_debt_active() / sanctum.gd `repair()`.
const COOLDOWN_SECONDS := 180.0

const TABOO_NAME_BY_CULTURE := {
	&"fenrayt": "Offering-Debt",
	&"sankiln": "Ash-Debt",
	&"raimborn": "Keel-Debt",
	&"vainkeeper": "Root-Debt",
}
const DEFAULT_TABOO_NAME := "Offering-Debt"

## village_id (StringName) -> Time.get_ticks_msec() value at which the
## offering-debt cooldown for that village clears.
static var _cooldown_until_msec: Dictionary = {}

## Static functions can't emit a signal declared on this class directly
## (there is no `self` instance), so cross-system listeners that want an
## "an offering just happened" event distinct from the generic
## GameState.devotion_changed / Naklon.naklon_changed signals can connect
## to this single shared bus instead: `Sacrifice.bus().offering_made.connect(...)`.
class SacrificeBus extends RefCounted:
	signal offering_made(village_id: StringName, kind: StringName, devotion_gained: float)

static var _bus_instance: SacrificeBus

static func bus() -> SacrificeBus:
	if _bus_instance == null:
		_bus_instance = SacrificeBus.new()
	return _bus_instance

## The offering itself. Always resolves (there is no roll to fail) —
## the taboo isn't that it might not work, it's that it always works and
## always costs you. See class doc above for how `target` is classified.
static func offer(village_id: StringName, target: Node) -> void:
	var village: Village = GameState.get_village(village_id)
	if village == null:
		push_warning("Sacrifice.offer: unknown village_id %s" % village_id)
		return

	var kind := _classify(target)
	var devotion_gain: float = DEVOTION_GAIN[kind]
	var naklon_amount: float = NAKLON_SHIFT[kind]

	# "read Village.children" per the brief: a living-child offering costs
	# the village one of its own (population and the named children count
	# both drop), same as a living-adult offering costs one population —
	# this is a person leaving the village permanently, not an abstraction.
	match kind:
		Kind.LIVING_CHILD:
			village.children = maxi(0, village.children - 1)
			village.population = maxi(0, village.population - 1)
		Kind.LIVING_ADULT:
			village.population = maxi(0, village.population - 1)
		_:
			pass

	GameState.add_devotion(village_id, devotion_gain)
	Naklon.shift(naklon_amount, NAKLON_WEIGHT)

	_cooldown_until_msec[village_id] = Time.get_ticks_msec() + int(COOLDOWN_SECONDS * 1000.0)

	var debt_name: String = TABOO_NAME_BY_CULTURE.get(village.culture_id, DEFAULT_TABOO_NAME)
	Voices.react(&"offering_taboo", {
		"village_id": village_id,
		"culture_id": village.culture_id,
		"kind": KIND_LABEL[kind],
		"devotion_gained": devotion_gain,
		"debt_name": debt_name,
	})
	bus().offering_made.emit(village_id, KIND_LABEL[kind], devotion_gain)

static func _classify(target: Node) -> Kind:
	if target == null:
		return Kind.OBJECT
	if target.has_method(&"get_offering_kind"):
		match String(target.call(&"get_offering_kind")):
			"child":
				return Kind.LIVING_CHILD
			"adult":
				return Kind.LIVING_ADULT
			_:
				return Kind.OBJECT
	if target.is_in_group(&"villager_child"):
		return Kind.LIVING_CHILD
	if target.is_in_group(&"villager") or target.is_in_group(&"villager_adult"):
		return Kind.LIVING_ADULT
	if ("is_child" in target) and bool(target.get("is_child")):
		return Kind.LIVING_CHILD
	if ("is_living" in target) and bool(target.get("is_living")):
		return Kind.LIVING_ADULT
	return Kind.OBJECT

## True while `village_id`'s Sanctum is still under offering-debt and its
## repair() path must refuse to run. Real enforcement lives in sanctum.gd;
## this is the flag it (and anyone else — UI, campaign text) checks.
static func is_offering_debt_active(village_id: StringName) -> bool:
	var until: int = _cooldown_until_msec.get(village_id, -1)
	return Time.get_ticks_msec() < until

static func offering_debt_seconds_remaining(village_id: StringName) -> float:
	var until: int = _cooldown_until_msec.get(village_id, -1)
	var remaining_msec: int = until - Time.get_ticks_msec()
	return maxf(0.0, remaining_msec / 1000.0)

static func taboo_name_for(village_id: StringName) -> String:
	var village: Village = GameState.get_village(village_id)
	if village == null:
		return DEFAULT_TABOO_NAME
	return TABOO_NAME_BY_CULTURE.get(village.culture_id, DEFAULT_TABOO_NAME)
