extends CanvasLayer
class_name FirstLessons

## The first two minutes, taught by watching rather than by telling.
##
## ---------------------------------------------------------------------------
## WHY
## ---------------------------------------------------------------------------
## The only verb in this game is drawing a shape over a village, and nothing
## on screen ever said so in a way a new player could act on. The Voices hint
## at it in character ("hold the right mouse button and drag a shape over a
## village"), but they hint once, in a scrolling log, next to forty other
## lines about snagbills. The rite panel exists and is bound to a key nobody
## is told to press until the help line at the bottom, which is where a
## player looks last.
##
## ---------------------------------------------------------------------------
## HOW IT WORKS, AND WHAT IT REFUSES TO DO
## ---------------------------------------------------------------------------
## Each lesson watches for the thing it asked for and clears itself when the
## player does it — no "click here to continue", no forced camera, no modal
## that has to be dismissed. If the player works it out on their own and casts
## a rite before being told to, the lessons about casting are already
## satisfied and simply never appear.
##
## It does not gate anything. Every control is live from the first frame; this
## only puts one sentence at a time where the eye already is.
##
## Seen-ness is stored per lesson in user config rather than in the save,
## because it is a fact about the PERSON, not about the island: starting a new
## game should not re-teach someone who has played before.

const CONFIG_PATH := "user://first_lessons.cfg"
const SECTION := "seen"

## Nothing appears until the opening Voices exchange has had a moment. Landing
## a tutorial line on top of the first line of dialogue reads as noise.
const OPENING_GRACE := 6.0

## A lesson that has been on screen this long without being satisfied steps
## aside anyway. A prompt that will not go away stops being help.
const PATIENCE := 75.0

var _label: Label
var _panel: PanelContainer
var _config := ConfigFile.new()
var _lessons: Array = []
var _index: int = -1
var _elapsed: float = 0.0
var _grace: float = 0.0

## Set true by the owner when the thing happened. Simpler and far more robust
## than each lesson holding its own signal connections into five subsystems.
var saw_rite_panel: bool = false
var saw_rite_cast: bool = false
var saw_rite_refused_out_of_reach: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	layer = 15
	_config.load(CONFIG_PATH)
	_build()
	_lessons = [
		{
			"id": "look",
			"text": "Fifteen villages. None of them have decided what you are yet.\nEach one says what it needs above its own roofs.",
			"done": func() -> bool: return false,   # time only: this is a look, not a task
			"seconds": 11.0,
		},
		{
			"id": "panel",
			"text": "Press 3. That is every rite you know, drawn as the shape you have to make —\nthe dot is where you start, the arrow is where you finish.",
			"done": func() -> bool: return saw_rite_panel,
		},
		{
			"id": "cast",
			"text": "Hold the RIGHT mouse button over a village and draw one.\nHarvest is the sickle: a wide crescent, then flick the handle off the tip.",
			"done": func() -> bool: return saw_rite_cast,
		},
		{
			"id": "reach",
			"text": "A rite only lands where you are already believed in.\nThe further a village is from anyone who prays to you, the less of it you can touch.",
			"done": func() -> bool: return false,
			"seconds": 12.0,
			"only_if": func() -> bool: return saw_rite_refused_out_of_reach,
		},
	]
	_advance()


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_bottom = -120.0
	_panel.modulate = Color(1, 1, 1, 0)
	add_child(_panel)

	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 26)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	_panel.add_child(margin)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 17)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	margin.add_child(_label)


func _process(delta: float) -> void:
	if _grace < OPENING_GRACE:
		_grace += delta
		return
	if _index < 0 or _index >= _lessons.size():
		return
	_elapsed += delta
	var lesson: Dictionary = _lessons[_index]
	var limit: float = float(lesson.get("seconds", PATIENCE))
	var done: Callable = lesson.done
	if done.call() or _elapsed >= limit:
		_mark_seen(String(lesson.id))
		_advance()


## Moves to the next lesson this player has not already been taught and whose
## precondition (if any) is currently true.
func _advance() -> void:
	_elapsed = 0.0
	_index += 1
	while _index < _lessons.size():
		var lesson: Dictionary = _lessons[_index]
		if _seen(String(lesson.id)):
			_index += 1
			continue
		if lesson.has("only_if") and not (lesson.only_if as Callable).call():
			# Not relevant yet. Skipped rather than waited on — the reach
			# lesson only means something to somebody who has just been
			# refused, and until then it is a sentence about nothing.
			_index += 1
			continue
		# Already satisfied before being asked: the player worked it out. Do
		# not congratulate them for it, just move on.
		if (lesson.done as Callable).call():
			_mark_seen(String(lesson.id))
			_index += 1
			continue
		_show(String(lesson.text))
		return
	_hide()


func _show(text: String) -> void:
	_label.text = text
	var tw := create_tween()
	tw.tween_property(_panel, "modulate:a", 1.0, 0.4)


func _hide() -> void:
	var tw := create_tween()
	tw.tween_property(_panel, "modulate:a", 0.0, 0.5)


func _seen(id: String) -> bool:
	return bool(_config.get_value(SECTION, id, false))


func _mark_seen(id: String) -> void:
	_config.set_value(SECTION, id, true)
	_config.save(CONFIG_PATH)


## Debug/QA: forget everything this player has been taught.
func reset() -> void:
	_config.clear()
	_config.save(CONFIG_PATH)
