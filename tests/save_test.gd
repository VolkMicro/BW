extends Node
## Headless check of the save/load round trip (core/save_game.gd).
##
## Run: godot --headless --path . tests/save_test.tscn
##
## A scene, not a `--script` SceneTree run: autoloads are not registered when
## a custom SceneTree replaces the main loop, and every line here needs them.

func _ready() -> void:
	var failures := 0
	SaveGame.delete()
	failures += _expect(not SaveGame.has_save(), "starts with no save")

	var a := Village.new()
	a.id = &"save_test_a"
	a.display_name = "Test A"
	a.population = 21
	a.faith_fraction = 0.44
	a.sanctum_hp = 71.0
	GameState.register_village(a)
	Stockpile.ensure(a)
	Stockpile.add(a, &"food", 63.0)
	Stockpile.add(a, &"wood", 12.5)
	GameState.add_devotion(a.id, 19.0)

	var b := Village.new()
	b.id = &"save_test_b"
	b.display_name = "Test B"
	b.loyal_to_rival = true
	GameState.register_village(b)
	Reclaim.press(b, 8.0)          # she is holding it, but less than fully
	var grip_before := Reclaim.grip_of(b)

	GameState.scrolls_known = [&"repair"] as Array[StringName]
	GameState.epithets = ["The One Who Counts"] as Array[String]
	Naklon.value = -0.34

	failures += _expect(SaveGame.save(), "saving writes a file")
	failures += _expect(SaveGame.has_save(), "the file is there afterwards")

	# Wreck everything the save is supposed to restore.
	a.faith_fraction = 0.0
	a.devotion = 0.0
	a.sanctum_hp = 3.0
	a.population = 1
	Stockpile.ensure(a)[&"food"] = 0.0
	Stockpile.ensure(a)[&"wood"] = 0.0
	b.loyal_to_rival = false
	b.remove_meta(Reclaim.META_KEY)
	GameState.scrolls_known = [] as Array[StringName]
	GameState.epithets = [] as Array[String]
	Naklon.value = 0.9

	failures += _expect(SaveGame.load_into_world(), "loading reports success")
	failures += _expect(is_equal_approx(a.faith_fraction, 0.44), "faith came back (%f)" % a.faith_fraction)
	failures += _expect(is_equal_approx(a.devotion, 19.0), "devotion came back (%f)" % a.devotion)
	failures += _expect(is_equal_approx(a.sanctum_hp, 71.0), "sanctum hp came back")
	failures += _expect(a.population == 21, "population came back")
	failures += _expect(is_equal_approx(Stockpile.get_amount(a, &"food"), 63.0),
		"food came back exactly, not clamped or re-stocked (%f)" % Stockpile.get_amount(a, &"food"))
	failures += _expect(is_equal_approx(Stockpile.get_amount(a, &"wood"), 12.5), "wood came back")
	failures += _expect(b.loyal_to_rival, "a taken village is still taken")
	failures += _expect(is_equal_approx(Reclaim.grip_of(b), grip_before),
		"her partial grip survived (%f, was %f)" % [Reclaim.grip_of(b), grip_before])
	failures += _expect(GameState.scrolls_known.has(&"repair"), "learned scrolls came back")
	failures += _expect(GameState.epithets.has("The One Who Counts"), "epithets came back")
	failures += _expect(is_equal_approx(Naklon.value, -0.34), "Naklon came back (%f)" % Naklon.value)

	# A village in the save that this island does not have must be skipped,
	# not invented — the seed or the planner may have changed under it.
	GameState.villages.erase(&"save_test_a")
	failures += _expect(SaveGame.load_into_world(), "a save naming an absent village still loads")

	SaveGame.delete()
	failures += _expect(not SaveGame.has_save(), "delete removes it")

	if failures == 0:
		print("save_test: OK")
		get_tree().quit(0)
	else:
		print("save_test: %d FAILURE(S)" % failures)
		get_tree().quit(1)


func _expect(condition: bool, what: String) -> int:
	if condition:
		return 0
	print("  FAIL: %s" % what)
	return 1
