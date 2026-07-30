extends Node
## Phase 5: the player god's power compounds with how much of the island
## believes. Run: godot --headless --path . tests/godhood_test.tscn

func _ready() -> void:
	var failures := 0
	GameState.villages.clear()

	failures += _expect(is_equal_approx(Godhood.unit(), 0.0), "an empty island is no godhood")

	var a := Village.new()
	a.id = &"gh_a"; a.population = 30; a.faith_fraction = 0.0
	GameState.register_village(a)
	var b := Village.new()
	b.id = &"gh_b"; b.population = 10; b.faith_fraction = 0.0
	GameState.register_village(b)

	failures += _expect(is_equal_approx(Godhood.unit(), 0.0), "nobody believing is 0")
	failures += _expect(is_equal_approx(Godhood.rite_multiplier(), 1.0), "no bonus at 0")

	# Counted in heads, not in villages: half of the big village is worth more
	# than all of the small one.
	a.faith_fraction = 0.5
	b.faith_fraction = 0.0
	var big_half := Godhood.unit()
	a.faith_fraction = 0.0
	b.faith_fraction = 1.0
	var small_all := Godhood.unit()
	failures += _expect(big_half > small_all,
		"half of thirty beats all of ten (%f vs %f)" % [big_half, small_all])

	# Everyone believes.
	a.faith_fraction = 1.0
	b.faith_fraction = 1.0
	failures += _expect(is_equal_approx(Godhood.unit(), 1.0), "a fully converted island is 1")
	failures += _expect(is_equal_approx(Godhood.rite_multiplier(), 1.0 + Godhood.MAX_RITE_BONUS),
		"full godhood gives the full rite bonus")
	failures += _expect(is_equal_approx(Godhood.reach_bonus(), Godhood.MAX_REACH_BONUS_M),
		"full godhood gives the full reach bonus")

	# A village Louhi holds contributes nothing — but must not count twice
	# against you, or a bad position becomes unrecoverable and the whole
	# reclaim mechanic is pointless.
	a.loyal_to_rival = true
	var with_loss := Godhood.unit()
	failures += _expect(with_loss > 0.0 and with_loss < 1.0,
		"a lost village zeroes its own contribution, no more (%f)" % with_loss)
	failures += _expect(is_equal_approx(with_loss, 10.0 / 40.0),
		"exactly its own heads are gone (%f, expected %f)" % [with_loss, 10.0 / 40.0])

	if failures == 0:
		print("godhood_test: OK")
		get_tree().quit(0)
	else:
		print("godhood_test: %d FAILURE(S)" % failures)
		get_tree().quit(1)


func _expect(condition: bool, what: String) -> int:
	if condition:
		return 0
	print("  FAIL: %s" % what)
	return 1
