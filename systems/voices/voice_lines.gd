class_name VoiceLinePool
## Line-pool stub for the Two Voices. Package M (systems/voices/) replaces
## this with the full trigger->line-set table; kept minimal here so the
## Voices autoload boots standalone during early integration.

class VoiceLine:
	var id: String
	var speaker: StringName
	var text: String
	func _init(p_id: String, p_speaker: StringName, p_text: String) -> void:
		id = p_id
		speaker = p_speaker
		text = p_text

func pick_pair(_trigger: StringName, _context: Dictionary, _recent: Array[String]) -> Array:
	return []
