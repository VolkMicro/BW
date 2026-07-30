extends Node
## Phase 3: a fed village grows, a starving one shrinks, and the crowd and
## the houses follow. Drives the economy directly rather than waiting out the
## ~2.5 real minutes a birth takes in play.
##
## Run: godot --headless --path . tests/growth_test.tscn

func _ready() -> void:
	var failures := 0

	var econ := VillageEconomy.new()
	add_child(econ)

	var v := Village.new()
	v.id = &"growth_test"
	v.display_name = "Growth Test"
	v.population = 20
	GameState.register_village(v)

	var grew: Array[int] = []
	econ.population_changed.connect(func(_id: StringName, n: int) -> void: grew.append(n))

	# Full larder: people arrive.
	var store := Stockpile.ensure(v)
	store[&"food"] = Stockpile.capacity(v, &"food")
	v.set_meta(Stockpile.META_KEY, store)
	for _i in int(VillageEconomy.SECONDS_PER_BIRTH) + 2:
		econ._tick_growth(v, 1.0)
	failures += _expect(v.population == 21, "a full larder adds one person (pop %d)" % v.population)
	failures += _expect(grew.size() == 1 and grew[0] == 21, "population_changed fired once with the new count")

	# Empty larder: people leave.
	store = Stockpile.ensure(v)
	store[&"food"] = 0.0
	v.set_meta(Stockpile.META_KEY, store)
	for _i in int(VillageEconomy.SECONDS_PER_LOSS) + 2:
		econ._tick_growth(v, 1.0)
	failures += _expect(v.population == 20, "an empty larder takes one back (pop %d)" % v.population)

	# The middle is not a slow ratchet: a village that hovers must not bank
	# half a birth forever and then cash it in the moment it eats.
	store = Stockpile.ensure(v)
	store[&"food"] = Stockpile.capacity(v, &"food") * 0.20   # between the thresholds
	v.set_meta(Stockpile.META_KEY, store)
	for _i in 400:
		econ._tick_growth(v, 1.0)
	failures += _expect(v.population == 20, "hovering between thresholds changes nothing (pop %d)" % v.population)

	# Floors and ceilings hold.
	v.population = VillageEconomy.MIN_POPULATION
	store = Stockpile.ensure(v)
	store[&"food"] = 0.0
	v.set_meta(Stockpile.META_KEY, store)
	for _i in int(VillageEconomy.SECONDS_PER_LOSS) * 3:
		econ._tick_growth(v, 1.0)
	failures += _expect(v.population == VillageEconomy.MIN_POPULATION,
		"a village cannot starve below the floor (pop %d)" % v.population)

	if failures == 0:
		print("growth_test: OK")
		get_tree().quit(0)
	else:
		print("growth_test: %d FAILURE(S)" % failures)
		get_tree().quit(1)


func _expect(condition: bool, what: String) -> int:
	if condition:
		return 0
	print("  FAIL: %s" % what)
	return 1
