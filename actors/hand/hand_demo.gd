extends Node3D
## Standalone test harness for the Hand actor (actors/hand/hand_demo.tscn).
## Registers a small demo village so Reach.can_act_at() has something to
## say yes to near the origin (Reach.can_act_at returns false everywhere
## if GameState.villages is empty — with no village at all the Hand could
## never grab anything), then reports live Hand/Reach state on screen.

@onready var _hand: Hand = $Hand
@onready var _status_label: Label = $UI/StatusLabel
@onready var _feed_label: Label = $UI/FeedLabel

const DEMO_VILLAGE_ID := &"demo_hearth"
var _feed_lines: Array[String] = []


func _ready() -> void:
	_register_demo_village()
	_hand.grabbed.connect(_on_hand_grabbed)
	_hand.released.connect(_on_hand_released)
	_hand.action_refused.connect(_on_hand_refused)


func _register_demo_village() -> void:
	var v := Village.new()
	v.id = DEMO_VILLAGE_ID
	v.display_name = "Demo Hearth"
	v.culture_id = &"fenrayt"
	v.position_on_island = Vector2(0, 0)
	v.population = 10
	v.faith_fraction = 0.4
	GameState.register_village(v)


func _process(_delta: float) -> void:
	if _status_label:
		var reach_radius := Reach.radius_for_village(DEMO_VILLAGE_ID)
		var in_reach := Reach.can_act_at(_hand.get_target_position())
		_status_label.text = "Reach radius: %.1fm   Hand target in reach: %s   Holding: %s\nNaklon: %.2f (unit %.2f)   Hold Left Click to grip, release to throw." % [
			reach_radius, str(in_reach), str(_hand.is_holding()), Naklon.value, Naklon.unit()
		]


func _push_feed(line: String) -> void:
	_feed_lines.append(line)
	if _feed_lines.size() > 6:
		_feed_lines.pop_front()
	if _feed_label:
		_feed_label.text = "\n".join(_feed_lines)


func _on_hand_grabbed(node: Node3D) -> void:
	_push_feed("grabbed: %s" % node.name)


func _on_hand_released(node: Node3D, velocity: Vector3) -> void:
	_push_feed("threw: %s at %.1f m/s" % [node.name, velocity.length()])


func _on_hand_refused(reason: StringName, world_pos: Vector3) -> void:
	_push_feed("refused (%s) at %s" % [reason, world_pos])


## Debug helper: nudge Naklon from the demo scene without needing the full
## sigil/villager systems wired up, so the material/trail reaction is easy
## to see in isolation. Bound to keys in _unhandled_input below.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_BRACKETLEFT:
			Naklon.shift(-0.1)
		elif event.physical_keycode == KEY_BRACKETRIGHT:
			Naklon.shift(0.1)
