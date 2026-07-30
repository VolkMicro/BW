extends CanvasLayer
class_name PauseMenu
## Escape: stop the island, and let the player leave, save, or come back.
##
## ---------------------------------------------------------------------------
## WHY
## ---------------------------------------------------------------------------
## Before this the only way out of the game was to close the window, and the
## only way to stop the world turning was to stop playing. Neither is a
## feature you can leave out of something a person is meant to sit down with:
## a session runs for tens of minutes, and a god who cannot look away from the
## island for thirty seconds is not a god, they are a hostage.
##
## ---------------------------------------------------------------------------
## PAUSING ACTUALLY PAUSES
## ---------------------------------------------------------------------------
## `get_tree().paused` stops every node whose `process_mode` is INHERIT, which
## is everything in this game — the weather, the crowd, the economy, Louhi's
## clock. This layer sets its own mode to ALWAYS so it keeps running while
## everything under it is frozen.
##
## That matters beyond convenience: the economy charges upkeep per second and
## Louhi counts down in real time, so a game that kept simulating behind a
## menu would starve villages while the player read the controls.

signal resumed

const BUTTON_MIN := Vector2(320.0, 44.0)

var _panel: PanelContainer
var _status: Label
var _load_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_build()
	visible = false


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.04, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_panel.add_child(box)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	_panel.remove_child(box)
	_panel.add_child(margin)
	margin.add_child(box)

	var title := Label.new()
	title.text = tr("THE ISLAND WAITS")
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 14)
	_status.modulate = Color(0.72, 0.74, 0.8)
	box.add_child(_status)

	box.add_child(HSeparator.new())

	_add_button(box, tr("Back to the island"), _on_resume)
	_add_button(box, tr("Write it down (save)"), _on_save)
	_load_button = _add_button(box, tr("Go back to the last writing (load)"), _on_load)
	box.add_child(HSeparator.new())
	_add_button(box, tr("Leave"), _on_quit)


func _add_button(parent: Node, text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = BUTTON_MIN
	b.pressed.connect(handler)
	parent.add_child(b)
	return b


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if (event as InputEventKey).physical_keycode != KEY_ESCAPE:
		return
	# Consumed either way, so Escape never falls through to whatever is behind
	# the menu — closing it must not also cast a rite.
	get_viewport().set_input_as_handled()
	if visible:
		_on_resume()
	else:
		open()


func open() -> void:
	_status.text = tr("Saved: %s") % (tr("yes, there is a writing to go back to") if SaveGame.has_save()
		else tr("nothing written down yet"))
	_load_button.disabled = not SaveGame.has_save()
	visible = true
	get_tree().paused = true


func close() -> void:
	visible = false
	get_tree().paused = false
	resumed.emit()


func _on_resume() -> void:
	close()


func _on_save() -> void:
	if SaveGame.save():
		_status.text = tr("Written down.")
		_load_button.disabled = false
	else:
		_status.text = tr("It would not write. Check that the save directory is writable.")


func _on_load() -> void:
	if SaveGame.load_into_world():
		_status.text = tr("Back to the last writing.")
		close()
	else:
		_status.text = tr("That writing could not be read — see the log.")


func _on_quit() -> void:
	# Unpause first: a quit request that arrives while the tree is paused
	# still runs the normal shutdown path, and leaving the flag set has bitten
	# projects that later reuse the tree.
	get_tree().paused = false
	get_tree().quit()
