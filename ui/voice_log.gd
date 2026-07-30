extends RichTextLabel
class_name VoiceLog
## The Two Voices, made visible.
##
## WHY THIS EXISTS: `systems/voices/voices.gd` is an autoload that emits
## `remark(speaker, line)` on every `Voices.react()` call, and
## `systems/voices/voice_lines.gd` holds 48 authored trigger pools / 474
## lines. Before this file, in the shipped scene (`world/god_view.tscn`)
## **nothing was connected to that signal** — only three standalone demo
## scenes and `audio/music_director.gd` (which listens purely to duck the
## music, and never shows the text). Every line the game says was being
## thrown away on the way to the screen.
##
## This is deliberately the smallest possible presenter: a transcript of the
## last few remarks, bottom-left, that ages itself out and disappears. The
## game is HUD-less by design (`core/game_state.gd`'s own doc comment), so
## this never draws a panel, a portrait, a frame or a background — it is
## text over the world, the same register as the existing `UI/HelpLabel`.
##
## SCOPED OUT, deliberately: no queueing, no priority, no interruption. If
## two triggers fire in the same frame the player gets four lines at once,
## exactly as `docs/systems/voices_content.md` says (sequencing belongs to
## `voices.gd`, which this file may not edit). No audio — there are no voice
## recordings in the project. No speaker portraits — no art for them exists.
##
## PER-FRAME COST: none while idle. `_process` is disabled whenever the
## transcript is empty and re-enabled by a remark, so a silent minute costs
## exactly zero callbacks. While lines are on screen `_process` does one
## float subtract + compare per entry (at most `MAX_LINES`) and one alpha
## write; the BBCode string is only rebuilt when an entry actually expires
## or arrives, i.e. a few times a minute, never per frame.

## How long one line stays fully readable before it starts to go.
@export var line_hold_sec: float = 11.0
## Seconds of fade at the tail of the last surviving line.
@export var fade_sec: float = 1.6
## Hard cap on transcript length. A Voices pair is 2 lines, so this is
## "the last three exchanges".
@export var max_lines: int = 6
## Start swallowing remarks until `unmute()` is called.
##
## This is not cosmetic. `campaign/campaign_manager.gd` activates six quests
## inside its own `_ready()`, and each one calls `Voices.react(&"quest_activated")`
## — twelve lines of dialogue dumped at frame 0, before the player has done
## anything. A parent's `_ready()` runs after all of its children's, so
## `world/god_view.gd` calls `unmute()` at the end of its own `_ready()`:
## everything any sibling said while booting is dropped deterministically,
## rather than depending on this node happening to sit lower in the scene
## tree than CampaignManager.
@export var start_muted: bool = true

## Speaker colours. Domovoi is hearth/ember, Hiisi is cold forest — the same
## split `docs/systems/voices_content.md` describes for the two characters.
## Kept as plain BBCode colour tags rather than a theme so this node needs
## no theme resource and no art dependency.
const SPEAKER_COLORS: Dictionary = {
	&"domovoi": "d8a15e",
	&"hiisi": "8fc48c",
}
## Translated at display time (see _rebuild). The keys stay English because
## every trigger, save file and log line refers to the speakers by these ids.
const SPEAKER_NAMES: Dictionary = {
	&"domovoi": "Domovoi",
	&"hiisi": "Hiisi",
}

var _entries: Array[Dictionary] = [] # {speaker: StringName, text: String, life: float}
var _muted: bool = false


## Let remarks through. Idempotent. See `start_muted`.
func unmute() -> void:
	_muted = false


func mute() -> void:
	_muted = true


func _ready() -> void:
	_muted = start_muted
	bbcode_enabled = true
	scroll_active = false
	fit_content = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	text = ""
	set_process(false)
	# Voices is a foundation autoload (project.godot), guaranteed present —
	# the same assumption systems/faith/reach.gd and campaign/campaign_manager.gd
	# already make.
	if not Voices.remark.is_connected(_on_remark):
		Voices.remark.connect(_on_remark)


## Public: push a line that did not come through `Voices.react()`. Used by
## `world/god_view.gd` for the opening exchange, whose lines are authored in
## that file because `systems/voices/voice_lines.gd` belongs to another
## package and has no `game_start` trigger. Same rendering, same ageing.
func push_line(speaker: StringName, line: String) -> void:
	_on_remark(speaker, line)


func _on_remark(speaker: StringName, line: String) -> void:
	if _muted or line.strip_edges().is_empty():
		return
	_entries.append({"speaker": speaker, "text": line, "life": line_hold_sec})
	while _entries.size() > max_lines:
		_entries.pop_front()
	_rebuild()
	modulate.a = 1.0
	set_process(true)


func _process(delta: float) -> void:
	var dropped := false
	var i := 0
	while i < _entries.size():
		var e: Dictionary = _entries[i]
		e["life"] = float(e["life"]) - delta
		if float(e["life"]) <= 0.0:
			_entries.remove_at(i)
			dropped = true
		else:
			i += 1

	if _entries.is_empty():
		if dropped:
			text = ""
		modulate.a = 1.0
		set_process(false)
		return

	if dropped:
		_rebuild()

	# `_entries` is append-ordered, so the last element always has the most
	# life left. Fade the whole block only once even that one is nearly gone,
	# which reads as "the conversation trails off" rather than as six lines
	# each blinking out on their own schedule.
	var newest: float = float(_entries[_entries.size() - 1]["life"])
	modulate.a = clampf(newest / maxf(fade_sec, 0.01), 0.0, 1.0)


func _rebuild() -> void:
	var parts: PackedStringArray = PackedStringArray()
	for e in _entries:
		var sp: StringName = e["speaker"]
		var color: String = SPEAKER_COLORS.get(sp, "cfcfcf")
		var name_text: String = tr(SPEAKER_NAMES.get(sp, String(sp).capitalize()))
		parts.append("[color=#%s]%s[/color]  %s" % [color, name_text, String(e["text"])])
	text = "\n".join(parts)
