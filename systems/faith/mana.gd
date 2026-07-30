extends RefCounted
class_name Mana
## What prayer buys, and what miracles cost.
##
## ---------------------------------------------------------------------------
## WHY THE GAME NEEDED A COST
## ---------------------------------------------------------------------------
## Rites were free. Unlimited, instant, and limited only by how fast a person
## can draw — the only brake was Reach's per-village fatigue, which pushes you
## to spread out but never asks you to stop. A god with infinite miracles is
## not a god making decisions, and every other number in the game had nothing
## to spend itself on: devotion fed the Avatar and nothing else, and a village
## praying harder changed nothing the player could feel.
##
## Mana is the missing edge. Villagers pray; prayer becomes mana; mana becomes
## miracles. That closes the loop the whole design rests on — **the more of
## the island believes in you, the more you can do**, which is the same
## sentence as the win condition.
##
## ---------------------------------------------------------------------------
## TUNED AGAINST THE RHYTHM THAT ALREADY EXISTS
## ---------------------------------------------------------------------------
## Reach's fatigue makes patience worth roughly sixteen times what spamming is
## (7 rites to convert a village at 20 s apart, 115 at 3 s apart — measured,
## see docs/audit/playability_audit.md). Mana is deliberately tuned to the
## SAME rhythm rather than to a second, different one: at the opening island
## — fifteen villages, faith around 0.15, roughly four hundred people — the
## pool refills a help rite about every ten seconds. Two brakes that disagree
## would feel arbitrary; two that agree feel like a tempo.
##
## ---------------------------------------------------------------------------
## STATIC STATE
## ---------------------------------------------------------------------------
## One god, one pool, no instance to pass around, and every caller
## (god_view, the HUD, the save) wants the same number. Reset explicitly by
## `reset()` when a new island starts — a static that quietly survives a scene
## change is exactly the bug this comment exists to prevent.

## Mana per second, per person who actually prays to you. Multiplied by
## `faith_fraction * population`, so a half-converted village of thirty
## contributes what a fully converted village of fifteen does.
const PER_BELIEVER_PER_SEC := 0.02

## The Sanctum concentrates prayer: a village with one standing contributes
## this much more. Gives the player a reason to care that a Sanctum has been
## burnt down beyond the faith it costs them.
const SANCTUM_BONUS := 1.35

## Base ceiling, plus what godhood adds. A god nobody has heard of cannot
## hold much; one the island believes in can bank several miracles.
const BASE_CAP := 45.0
const CAP_PER_GODHOOD := 165.0

## What things cost. Help is cheaper than terror — not for balance reasons
## but because it is the same statement Reach's ceilings already make: fear is
## the expensive way to be believed in.
const COST := {
	&"ward": 8.0,
	&"harvest": 12.0,
	&"rain_call": 11.0,
	&"lumber": 10.0,
	&"repair": 10.0,
	&"path_gate": 9.0,
	&"fire_arrow": 14.0,
	&"lightning": 18.0,
	&"storm": 26.0,
}
const DEFAULT_COST := 12.0

static var _amount: float = 20.0


static func amount() -> float:
	return _amount


static func capacity() -> float:
	return BASE_CAP + Godhood.unit() * CAP_PER_GODHOOD


static func fraction() -> float:
	var cap := capacity()
	return clampf(_amount / cap, 0.0, 1.0) if cap > 0.0 else 0.0


## Mana per second the island is currently praying into existence.
static func income_per_sec() -> float:
	var total := 0.0
	for value in GameState.villages.values():
		var v: Village = value
		if v.loyal_to_rival:
			continue
		var believers: float = v.faith_fraction * float(v.population)
		var mult: float = SANCTUM_BONUS if v.sanctum_built and v.sanctum_hp > 0.0 else 1.0
		total += believers * PER_BELIEVER_PER_SEC * mult
	return total


static func tick(delta: float) -> void:
	_amount = minf(_amount + income_per_sec() * delta, capacity())


static func cost_of(rite_id: StringName) -> float:
	return float(COST.get(rite_id, DEFAULT_COST))


static func can_afford(rite_id: StringName) -> bool:
	return _amount >= cost_of(rite_id) - 0.001


## Spends if it can. Returns false and changes nothing if it cannot — the
## caller must check this rather than assuming, because a rite that fires
## having failed to pay is worse than one that never fired.
static func spend(rite_id: StringName) -> bool:
	var c := cost_of(rite_id)
	if _amount < c - 0.001:
		return false
	_amount = maxf(_amount - c, 0.0)
	return true


## Devotion offered at an altar converts straight to mana. This is the
## Sanctum's offering trigger finally meaning something to the player rather
## than only to the village's own books.
static func offer(devotion: float) -> void:
	_amount = minf(_amount + maxf(devotion, 0.0), capacity())


static func set_amount(value: float) -> void:
	_amount = clampf(value, 0.0, capacity())


## A new island. Static state does not reset itself when the scene changes,
## and a second game inheriting the first one's full pool would be a very
## confusing way to start.
static func reset() -> void:
	_amount = 20.0
