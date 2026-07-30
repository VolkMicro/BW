extends RefCounted
class_name Godhood
## How strong the player god currently is, and what that buys.
##
## ---------------------------------------------------------------------------
## WHY
## ---------------------------------------------------------------------------
## The design ends with one god left standing, which only means anything if
## both sides compound: every village a god holds has to make the next one
## easier to take. Louhi's half of that landed with her evaluation interval
## shortening per village held (actors/louhi/louhi_director.gd). This is the
## player's half.
##
## Before it, the player's power curve was almost flat. Devotion fed the
## Avatar, and `Reach.radius_for_village()` grew with a village's OWN
## converts — so a god who held twelve villages reached no further into the
## thirteenth than a god who held none. Twelve villages of worshippers bought
## nothing outside their own fences, and the endgame got harder the closer you
## came to winning, because Louhi was accelerating and you were not.
##
## ---------------------------------------------------------------------------
## WHAT IT IS MEASURED FROM
## ---------------------------------------------------------------------------
## Believing PEOPLE, not villages. `faith_fraction * population` summed across
## the island, over the island's whole population. A god who has half-won five
## big villages is stronger than one who fully owns two small ones, which is
## the right answer: faith here has always been counted in heads
## (`Reach.radius_for_village` does the same arithmetic locally).
##
## Villages Louhi holds count as zero rather than as negative. Losing one
## already costs you everything it was contributing; charging twice for it
## turns a bad position into an unrecoverable one, and the reclaim mechanic
## exists precisely so that a bad position is recoverable.

## Rite effect at full godhood, as a multiplier. Deliberately modest: this is
## meant to reward a god who is already winning with momentum, not to make the
## last five villages fall over by themselves. At 1.0 the player is casting
## rites 45% stronger than they did on an island that had never heard of them.
const MAX_RITE_BONUS: float = 0.45

## Extra metres of Reach at full godhood, on top of whatever the village's own
## converts earn. A well-established god's presence is felt past the edge of
## the last farm that prays to them.
const MAX_REACH_BONUS_M: float = 34.0

## Extra prying force against Louhi's grip at full godhood. Higher than the
## rite bonus on purpose — the moment a god is strong enough to contest her is
## the moment the war should start moving, rather than settling into an
## indefinite stalemate over the same three villages.
const MAX_RECLAIM_BONUS: float = 0.8


## 0 (nobody on the island prays to you) .. 1 (all of it does).
static func unit() -> float:
	var believing := 0.0
	var total := 0.0
	for value in GameState.villages.values():
		var v: Village = value
		total += float(v.population)
		if v.loyal_to_rival:
			continue
		believing += v.faith_fraction * float(v.population)
	if total <= 0.0:
		return 0.0
	return clampf(believing / total, 0.0, 1.0)


## Multiplier on the amount of any rite the player casts.
static func rite_multiplier() -> float:
	return 1.0 + unit() * MAX_RITE_BONUS


## Extra Reach radius, in metres, added to every village the player can act on.
static func reach_bonus() -> float:
	return unit() * MAX_REACH_BONUS_M


## Multiplier on how hard a rite pries at Louhi's grip.
static func reclaim_multiplier() -> float:
	return 1.0 + unit() * MAX_RECLAIM_BONUS


## A short line for the HUD. Named rather than numeric: this game does not
## show the player a power bar anywhere else, and a bare percentage would be
## the only raw stat on screen.
static func title() -> String:
	var u := unit()
	if u < 0.06:
		return "barely spoken of"
	if u < 0.18:
		return "spoken of"
	if u < 0.34:
		return "believed in"
	if u < 0.55:
		return "widely believed in"
	if u < 0.78:
		return "a power on this island"
	return "the god of this island"
