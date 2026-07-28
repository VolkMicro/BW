extends Node
## Autoload. The Two Voices: Domovoi (hearth spirit, exasperated and
## practical) and Hiisi (forest trickster, theatrical, thinks every problem
## is solved by eating someone). They comment on triggers fired elsewhere
## in the game; they never agree twice the same way. See
## systems/voices/voice_lines.gd for the actual line pools and
## docs/systems/voices.md for the comedic-target rule this file enforces:
## the joke is always on the player's bureaucracy or hypocrisy, never on a
## real belief system.

signal remark(speaker: StringName, line: String) # speaker: &"domovoi" or &"hiisi"

var _recent_line_ids: Array[String] = [] # last N line ids said, to avoid back-to-back repeats
const RECENT_MEMORY := 12

var _pool: VoiceLinePool

func _ready() -> void:
	_pool = load("res://systems/voices/voice_lines.gd").new()

## `trigger` is a StringName like &"sacrifice_offered", &"village_converted",
## &"avatar_ate_a_villager", &"first_rite_cast". `context` carries whatever
## the specific system wants to interpolate (village name, method, etc).
func react(trigger: StringName, context: Dictionary = {}) -> void:
	var pair := _pool.pick_pair(trigger, context, _recent_line_ids)
	if pair.is_empty():
		return
	for line in pair:
		_recent_line_ids.append(line.id)
		if _recent_line_ids.size() > RECENT_MEMORY:
			_recent_line_ids.pop_front()
		remark.emit(line.speaker, line.text)
