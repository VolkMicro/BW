extends Control
class_name MainMenu
## The screen the game opens on.
##
## ---------------------------------------------------------------------------
## WHY THE GAME NEEDED ONE
## ---------------------------------------------------------------------------
## `run/main_scene` pointed straight at `world/god_view.tscn`, so launching the
## game dropped the player into a running island with no way to choose a
## language, set graphics for their machine, continue a saved game, or leave
## except by closing the window. The Escape menu covers the last of those once
## you are already in — but a person who launches the game and immediately
## wants to turn the resolution down should not have to play first.
##
## ---------------------------------------------------------------------------
## HOW IT IS BUILT
## ---------------------------------------------------------------------------
## In code, not as an authored .tscn tree. Every label here is translated at
## runtime and re-translated when the language changes, and doing that to an
## authored tree means either hunting node paths for each string or duplicating
## the layout in two places. Built here, `_retranslate()` is one function that
## walks a list it already owns.

const TITLE_TEXT := "TITHE & TERROR"

var _buttons: Dictionary = {}     # StringName -> Button
var _labels: Dictionary = {}      # StringName -> Label
var _settings_panel: Control
var _menu_box: VBoxContainer
var _subtitle: Label
var _continue: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	Settings.changed.connect(_retranslate)
	_retranslate()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.045, 0.05, 0.062)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var centre := VBoxContainer.new()
	centre.set_anchors_preset(Control.PRESET_CENTER)
	centre.grow_horizontal = Control.GROW_DIRECTION_BOTH
	centre.grow_vertical = Control.GROW_DIRECTION_BOTH
	centre.alignment = BoxContainer.ALIGNMENT_CENTER
	centre.add_theme_constant_override("separation", 8)
	add_child(centre)

	var title := Label.new()
	title.text = TITLE_TEXT
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 46)
	centre.add_child(title)

	_subtitle = Label.new()
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_font_size_override("font_size", 15)
	_subtitle.modulate = Color(0.68, 0.70, 0.76)
	centre.add_child(_subtitle)

	centre.add_child(_spacer(26))

	_menu_box = VBoxContainer.new()
	_menu_box.add_theme_constant_override("separation", 8)
	centre.add_child(_menu_box)

	_continue = _add_button(_menu_box, &"continue", _on_continue)
	_add_button(_menu_box, &"new_game", _on_new_game)
	_add_button(_menu_box, &"settings", _on_open_settings)
	_add_button(_menu_box, &"quit", _on_quit)

	_settings_panel = _build_settings()
	_settings_panel.name = "SettingsPanel"
	add_child(_settings_panel)
	_settings_panel.visible = false


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _add_button(parent: Node, key: StringName, handler: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(360, 46)
	b.pressed.connect(handler)
	parent.add_child(b)
	_buttons[key] = b
	return b


# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

func _build_settings() -> Control:
	var dim := ColorRect.new()
	# Fully opaque. At 0.96 the menu behind it stayed faintly legible and the
	# two layers of text read as a rendering fault rather than as a panel.
	dim.color = Color(0.03, 0.035, 0.045, 1.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size = Vector2(520, 0)
	dim.add_child(box)

	_labels[&"settings_title"] = _heading(box, 28)

	# Language. First, deliberately: somebody who cannot read the menu needs
	# to find this one without reading the menu, so it sits where the eye
	# lands and the options are written in their own language, never
	# translated ("Русский" stays "Русский" in the English build).
	_labels[&"language"] = _heading(box, 15)
	var lang_row := HBoxContainer.new()
	lang_row.add_theme_constant_override("separation", 8)
	box.add_child(lang_row)
	for code in Settings.LOCALES:
		var b := Button.new()
		b.text = Settings.LOCALES[code]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(160, 38)
		b.pressed.connect(func() -> void:
			Settings.set_locale(code)
			_retranslate())
		lang_row.add_child(b)
		_buttons[StringName("lang_" + code)] = b

	box.add_child(HSeparator.new())

	# Graphics.
	_labels[&"graphics"] = _heading(box, 15)
	var preset_row := HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", 8)
	box.add_child(preset_row)
	for i in 3:
		var b := Button.new()
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(160, 38)
		b.pressed.connect(func() -> void:
			Settings.set_graphics_preset(i)
			_retranslate())
		preset_row.add_child(b)
		_buttons[StringName("preset_%d" % i)] = b
	_labels[&"preset_hint"] = _heading(box, 13)
	(_labels[&"preset_hint"] as Label).modulate = Color(0.65, 0.67, 0.73)

	var fs := CheckBox.new()
	fs.button_pressed = Settings.fullscreen
	fs.toggled.connect(func(on: bool) -> void: Settings.set_fullscreen(on))
	box.add_child(fs)
	_buttons[&"fullscreen"] = fs

	box.add_child(HSeparator.new())

	# Sound.
	_labels[&"sound"] = _heading(box, 15)
	_add_slider(box, &"master", Settings.master_volume,
		func(v: float) -> void: Settings.set_master_volume(v))
	_add_slider(box, &"music", Settings.music_volume,
		func(v: float) -> void: Settings.set_music_volume(v))

	box.add_child(_spacer(10))
	_add_button(box, &"back", func() -> void: _settings_panel.visible = false)
	return dim


func _heading(parent: Node, size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l


func _add_slider(parent: Node, key: StringName, value: float, handler: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var l := Label.new()
	l.custom_minimum_size = Vector2(170, 0)
	row.add_child(l)
	_labels[key] = l
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.custom_minimum_size = Vector2(300, 24)
	s.value_changed.connect(handler)
	row.add_child(s)


# ---------------------------------------------------------------------------

## Every visible string, in one place, re-read whenever the language changes.
func _retranslate() -> void:
	_subtitle.text = tr("Two gods. One island. Only one of you will be left.")
	_buttons[&"continue"].text = tr("Continue")
	_buttons[&"new_game"].text = tr("New island")
	_buttons[&"settings"].text = tr("Settings")
	_buttons[&"quit"].text = tr("Leave")
	_continue.disabled = not SaveGame.has_save()

	_labels[&"settings_title"].text = tr("Settings")
	_labels[&"language"].text = tr("Language")
	_labels[&"graphics"].text = tr("Graphics")
	_labels[&"preset_hint"].text = tr("Low is built for laptops with integrated graphics.")
	_labels[&"sound"].text = tr("Sound")
	_labels[&"master"].text = tr("Everything")
	_labels[&"music"].text = tr("Music")
	_buttons[&"back"].text = tr("Back")
	_buttons[&"fullscreen"].text = tr("Fullscreen")

	for i in 3:
		var b: Button = _buttons[StringName("preset_%d" % i)]
		b.text = [tr("Low"), tr("Medium"), tr("High")][i]
		b.button_pressed = Settings.graphics_preset == i
	for code in Settings.LOCALES:
		(_buttons[StringName("lang_" + code)] as Button).button_pressed = Settings.locale == code


# ---------------------------------------------------------------------------

func _on_new_game() -> void:
	# A new island must not inherit the last one. Without this, starting fresh
	# and then opening the Escape menu offers to "load" a game from a world
	# that no longer exists — and loading it would write last island's faith
	# onto this island's villages, quietly, for the villages whose ids happen
	# to match.
	SaveGame.delete()
	_start_world()


func _on_continue() -> void:
	_start_world(true)


func _start_world(load_after: bool = false) -> void:
	var world: PackedScene = load("res://world/god_view.tscn")
	get_tree().change_scene_to_packed(world)
	if load_after:
		# One frame so the scene has actually booted and registered its
		# villages — the save is applied OVER a running world, never instead
		# of one (see core/save_game.gd).
		await get_tree().process_frame
		await get_tree().process_frame
		SaveGame.load_into_world()


func _on_open_settings() -> void:
	_settings_panel.visible = true
	_retranslate()


func _on_quit() -> void:
	get_tree().quit()
