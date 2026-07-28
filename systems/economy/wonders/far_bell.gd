extends Wonder
class_name FarBellWonder
## Package H — the Far Bell. A cast bell hung high enough that its sound
## (and, the village insists, whatever rides along with it) carries well
## past the village's own converts. Real persistent effect: +6m flat bonus
## to this village's Reach radius.
##
## Reach.radius_for_village() (systems/faith/reach.gd) is owned by package
## J, and this package does not edit systems/faith/ — but the bonus is
## still real and queryable today via the wrapper functions in
## systems/economy/reach_bridge.gd (EconomyReachBridge.effective_radius /
## .can_act_at), which any caller can use right now in place of Reach's own
## functions to get the boosted number. The clean long-term integration
## is a one-line addition to Reach.radius_for_village():
##
##     return 8.0 + converts * BASE_REACH_PER_HEAD + EconomyReachBridge.radius_bonus(village_id)
##
## which package J (or whoever next owns systems/faith/) can add without
## breaking Reach's existing public API (the OWNERSHIP.md constraint on
## that file) — it's an additive term, not a signature change. Documented
## here and in docs/systems/economy.md rather than made by this package,
## since systems/faith/ is not this package's directory to write to.

const REACH_BONUS_METERS: float = 6.0

func _init() -> void:
	super._init()
	id = &"wonder_far_bell"
	display_name = "The Far Bell"
	description = "Cast bronze hung high enough that its sound, and whatever rides along with it, carries a fair distance past where the village's own faith already reaches."
	cost = {&"stone": 70.0, &"wood": 50.0}
	build_time_seconds = 110.0

static func is_present(village: Village) -> bool:
	return village != null and (&"wonder_far_bell" in village.wonders)
