extends Node3D
## The Hand pulling things out of the world (systems/economy/hand_gathering.gd).
##
## Run: godot --headless --path . tests/gathering_test.tscn

var _scatter: Node = null

func _ready() -> void:
	# A parse error anywhere in this file leaves the scene with no script and
	# the headless run hangs forever with no output. This is the backstop that
	# turns that into a visible failure. (It happened. Twice.)
	get_tree().create_timer(45.0).timeout.connect(func() -> void:
		print("gathering_test: TIMED OUT")
		get_tree().quit(1))
	var failures := 0

	var terrain := IslandTerrain.new()
	terrain.size_meters = 600.0
	terrain.resolution = 129
	terrain.max_height = 90.0
	add_child(terrain)

	# A village on real ground, with room in its stores.
	var v := Village.new()
	v.id = &"gather_test"
	v.display_name = "Gather Test"
	v.population = 20
	GameState.villages.clear()
	GameState.register_village(v)
	var site := Vector2.ZERO
	for r: float in [0.0, 40.0, 80.0, 120.0, 160.0]:
		for i in 12:
			var a: float = TAU * float(i) / 12.0
			var p: Vector2 = Vector2(cos(a), sin(a)) * r
			if terrain.sample_height(p) > 4.0:
				site = p
				break
		if site != Vector2.ZERO:
			break
	v.position_on_island = site
	Stockpile.ensure(v)

	_scatter = preload("res://world/terrain/scatter/terrain_scatter.gd").new()
	_scatter.set("terrain_path", NodePath(""))
	_scatter.set("auto_scatter_on_ready", false)
	_scatter.set("grass_count", 0)
	_scatter.set("tree_count", 300)
	_scatter.set("rock_count", 120)
	add_child(_scatter)
	_scatter.call("rebuild")
	await get_tree().process_frame

	var at := Vector3(site.x, terrain.sample_height(site), site.y)
	var trees_before: int = _scatter.call("count_near", 1, site, 300.0)
	failures += _expect(trees_before > 0, "the test island has trees to pull up (%d)" % trees_before)

	# Somewhere with nothing near it must fail as "nothing here", not silently.
	var far := Vector3(9000.0, 0.0, 9000.0)
	var nothing := HandGathering.take_at(_scatter, far)
	failures += _expect(not nothing.ok and nothing.reason == &"nothing_here",
		"empty ground reports nothing_here (got %s)" % nothing.reason)

	# A real take credits the village AND removes the thing from the world.
	var wood_before := Stockpile.get_amount(v, &"wood")
	var naklon_before := Naklon.value
	var took := HandGathering.take_at(_scatter, at)
	if took.ok and took.resource == &"wood":
		failures += _expect(Stockpile.get_amount(v, &"wood") > wood_before,
			"the village gained wood")
		failures += _expect(_scatter.call("count_near", 1, site, 300.0) == trees_before - 1,
			"exactly one tree left the world")
		failures += _expect(Naklon.value < naklon_before,
			"giving to a village shifts Naklon toward mercy (%f -> %f)" % [naklon_before, Naklon.value])
	else:
		# Nearest thing was a rock, or the village's own field. Both are valid
		# results of the same key press; assert the shared contract instead.
		failures += _expect(took.ok, "something was taken (reason %s)" % took.reason)
		failures += _expect(took.village == v, "it went to the only village there is")

	# A full store must refuse BEFORE destroying anything.
	var store := Stockpile.ensure(v)
	store[&"wood"] = Stockpile.capacity(v, &"wood")
	store[&"stone"] = Stockpile.capacity(v, &"stone")
	store[&"food"] = Stockpile.capacity(v, &"food")
	v.set_meta(Stockpile.META_KEY, store)
	var standing: int = _scatter.call("count_near", 1, site, 300.0)
	var full := HandGathering.take_at(_scatter, at)
	failures += _expect(not full.ok and full.reason == &"stores_full",
		"a full store refuses (got %s)" % full.reason)
	failures += _expect(_scatter.call("count_near", 1, site, 300.0) == standing,
		"and nothing was destroyed doing it")

	if failures == 0:
		print("gathering_test: OK")
		get_tree().quit(0)
	else:
		print("gathering_test: %d FAILURE(S)" % failures)
		get_tree().quit(1)


func _expect(condition: bool, what: String) -> int:
	if condition:
		return 0
	print("  FAIL: %s" % what)
	return 1
