extends Node3D
## PACKAGE W (wildlife) — standalone demo, same convention every other
## package uses (`village_demo.tscn`, `avatar_demo.tscn`, `ocean_demo.tscn`):
## a runnable scene that exercises this package's real code against a real
## IslandTerrain, without depending on world/god_view.tscn.
##
## Controls:
##   Arrow keys / WASD  — move the "GodProxy" marker around. It is registered
##                        in the &"avatar" group, so the WildlifeManager picks
##                        it up as a real threat: walk it into a rimefleece
##                        herd and watch the herd actually scatter and then
##                        re-form.
##   K                  — force the thawjaw hungry right now
##                        (WildlifeManager.debug_force_hunt()), instead of
##                        waiting out its 85s hunger timer.
##   [ / ]              — shift Naklon toward mercy / cruelty and watch the
##                        flee radii change (calmer / spookier animals).
##   L                  — print a live population + state census to stdout.

const PROXY_SPEED := 16.0

@onready var _manager: WildlifeManager = $WildlifeManager
@onready var _proxy: Node3D = $GodProxy
@onready var _island: IslandTerrain = $Island
@onready var _log: Label = $UI/Log


func _ready() -> void:
	# The proxy stands in for the Avatar so this demo needs no dependency on
	# package K. WildlifeManager finds it exactly the way it finds the real
	# Avatar in world/god_view.tscn: via the &"avatar" group.
	_proxy.add_to_group(&"avatar")
	_manager.creature_alarmed.connect(_on_alarmed)
	_manager.prey_killed.connect(_on_prey_killed)
	_manager.creature_spawned.connect(_on_spawned)
	_write_log("wildlife demo ready")


func _process(delta: float) -> void:
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		move.z += 1.0
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		move.z -= 1.0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		move.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		move.x += 1.0
	if move != Vector3.ZERO:
		var p := _proxy.global_position + move.normalized() * PROXY_SPEED * delta
		p.y = _island.sample_height(Vector2(p.x, p.z)) + 2.0
		_proxy.global_position = p


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	match key.keycode:
		KEY_K:
			_manager.debug_force_hunt()
			_write_log("thawjaw made hungry")
		KEY_BRACKETLEFT:
			Naklon.shift(-0.2)
			_write_log("Naklon -> %.2f (calmer animals)" % Naklon.value)
		KEY_BRACKETRIGHT:
			Naklon.shift(0.2)
			_write_log("Naklon -> %.2f (spookier animals)" % Naklon.value)
		KEY_L:
			_census()


func _census() -> void:
	var lines: Array[String] = []
	lines.append("alive=%d rimefleece=%d snagbill=%d thawjaw=%d" % [
		_manager.total_alive(),
		_manager.living_count(&"rimefleece"),
		_manager.living_count(&"snagbill"),
		_manager.living_count(&"thawjaw"),
	])
	var states: Dictionary = {}
	for node in get_tree().get_nodes_in_group(&"wildlife"):
		var c := node as WildCreature
		if c == null:
			continue
		var key: String = c.state_name()
		states[key] = int(states.get(key, 0)) + 1
	for key in states:
		var state_key: String = key
		lines.append("  %s: %d" % [state_key, int(states[state_key])])
	var text: String = "\n".join(lines)
	print(text)
	_write_log(text)


func _on_alarmed(creature: WildCreature, _threat_position: Vector3) -> void:
	_write_log("%s alarmed" % creature.species.display_name)


func _on_prey_killed(prey_species: StringName, predator_species: StringName, where: Vector3) -> void:
	var line := "%s killed a %s at (%.0f, %.0f)" % [predator_species, prey_species, where.x, where.z]
	print(line)
	_write_log(line)


func _on_spawned(creature: WildCreature) -> void:
	if _log:
		_write_log("spawned %s" % creature.species.display_name)


func _write_log(text: String) -> void:
	if _log:
		_log.text = text
