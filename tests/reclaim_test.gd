extends Node
## Headless check of the reclaim loop (systems/faith/reclaim.gd).
##
## Run with:
##   godot --headless --path . tests/reclaim_test.tscn
##
## A scene rather than a `--script` SceneTree: autoloads (GameState, Voices)
## are not registered when a custom SceneTree replaces the main loop, and
## every line of this test needs them.
##
## Exists because a reclaim takes nine or ten rites and several minutes of
## Louhi's clock to reach in the running game, which is far too slow a loop to
## debug a rule in. This drives the same code directly.

func _ready() -> void:
	var failures := 0

	var v := Village.new()
	v.id = &"test_village"
	v.display_name = "Test Hollow"
	v.population = 20
	v.faith_fraction = 0.62
	GameState.register_village(v)

	# A village nobody holds has no grip to pry at.
	failures += _expect(Reclaim.grip_of(v) == 0.0, "unheld village has no grip")
	failures += _expect(Reclaim.press(v, 5.0).released == false, "pressing an unheld village does nothing")

	# Louhi takes it.
	v.loyal_to_rival = true
	failures += _expect(is_equal_approx(Reclaim.grip_of(v), 1.0), "a freshly taken village is held completely")

	# Prying: a 4.4 rite is worth 0.11 of her grip.
	var first := Reclaim.press(v, 4.4)
	failures += _expect(not first.released, "one rite does not free a village")
	failures += _expect(is_equal_approx(first.grip, 0.89), "a 4.4 rite costs her 0.11 grip, got %f" % first.grip)

	# Keep going until it breaks. Nine more should do it.
	var casts := 1
	var released := false
	for _i in 30:
		casts += 1
		var r := Reclaim.press(v, 4.4)
		if r.released:
			released = true
			break
	failures += _expect(released, "the village can be freed at all")
	failures += _expect(casts == 10, "it takes ten clean rites, took %d" % casts)

	# And what comes back is a village that has been through something.
	failures += _expect(not v.loyal_to_rival, "a freed village is no longer hers")
	failures += _expect(is_equal_approx(v.faith_fraction, Reclaim.FAITH_ON_RETURN),
		"a freed village comes back at low faith, not the 0.62 it left with (got %f)" % v.faith_fraction)
	failures += _expect(Reclaim.grip_of(v) == 0.0, "grip is cleared on release")

	if failures == 0:
		print("reclaim_test: OK")
		get_tree().quit(0)
	else:
		print("reclaim_test: %d FAILURE(S)" % failures)
		get_tree().quit(1)


func _expect(condition: bool, what: String) -> int:
	if condition:
		return 0
	print("  FAIL: %s" % what)
	return 1
