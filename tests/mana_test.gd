extends Node
## Prayer becomes mana, mana buys miracles (systems/faith/mana.gd).
##
## Run: godot --headless --path . tests/mana_test.tscn

func _ready() -> void:
	get_tree().create_timer(30.0).timeout.connect(func() -> void:
		print("mana_test: TIMED OUT")
		get_tree().quit(1))
	var failures := 0

	GameState.villages.clear()
	Mana.reset()
	failures += _expect(is_equal_approx(Mana.amount(), 20.0), "a new island starts with a little")
	failures += _expect(is_zero_approx(Mana.income_per_sec()),
		"an island with no believers prays nothing")

	var v := Village.new()
	v.id = &"mana_test"
	v.display_name = "Mana Test"
	v.population = 100
	v.faith_fraction = 0.5
	v.sanctum_built = false
	GameState.register_village(v)

	# 100 people, half of them praying, no Sanctum: 50 * 0.02 = 1.0/s.
	failures += _expect(is_equal_approx(Mana.income_per_sec(), 1.0),
		"income is per believing head (%f)" % Mana.income_per_sec())

	v.sanctum_built = true
	v.sanctum_hp = 80.0
	failures += _expect(is_equal_approx(Mana.income_per_sec(), Mana.SANCTUM_BONUS),
		"a standing Sanctum concentrates prayer (%f)" % Mana.income_per_sec())

	# A village Louhi holds prays to HER.
	v.loyal_to_rival = true
	failures += _expect(is_zero_approx(Mana.income_per_sec()),
		"a village she holds contributes nothing")
	v.loyal_to_rival = false

	# Spending.
	Mana.set_amount(20.0)
	failures += _expect(Mana.can_afford(&"harvest"), "20 pays for a harvest")
	failures += _expect(Mana.spend(&"harvest"), "and the spend goes through")
	failures += _expect(is_equal_approx(Mana.amount(), 20.0 - Mana.cost_of(&"harvest")),
		"exactly the cost came off (%f)" % Mana.amount())

	# The expensive one, with an empty pool: refused, and NOTHING changes.
	Mana.set_amount(3.0)
	failures += _expect(not Mana.can_afford(&"storm"), "3 does not pay for a storm")
	failures += _expect(not Mana.spend(&"storm"), "the spend is refused")
	failures += _expect(is_equal_approx(Mana.amount(), 3.0),
		"and a refused spend changes nothing (%f)" % Mana.amount())

	# The ceiling grows with godhood, and ticking cannot exceed it.
	var cap_before := Mana.capacity()
	v.faith_fraction = 1.0
	failures += _expect(Mana.capacity() > cap_before,
		"godhood raises the ceiling (%f -> %f)" % [cap_before, Mana.capacity()])
	Mana.set_amount(Mana.capacity())
	Mana.tick(100.0)
	failures += _expect(Mana.amount() <= Mana.capacity() + 0.001,
		"a full pool does not overflow (%f of %f)" % [Mana.amount(), Mana.capacity()])

	# Terror costs more than help — the same statement Reach's ceilings make.
	failures += _expect(Mana.cost_of(&"lightning") > Mana.cost_of(&"harvest"),
		"fear is the expensive way to be believed in")

	if failures == 0:
		print("mana_test: OK")
		get_tree().quit(0)
	else:
		print("mana_test: %d FAILURE(S)" % failures)
		get_tree().quit(1)


func _expect(condition: bool, what: String) -> int:
	if condition:
		return 0
	print("  FAIL: %s" % what)
	return 1
