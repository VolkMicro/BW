extends Node
## Autoload. Everything the player chose about how the game runs, and the file
## it survives in.
##
## ---------------------------------------------------------------------------
## WHY THIS IS SEPARATE FROM SaveGame
## ---------------------------------------------------------------------------
## `core/save_game.gd` writes an ISLAND — one game in progress. This writes
## facts about the PERSON: their language, how loud they want it, what their
## machine can render. Those outlive any particular island and must not be
## restored when an old save is loaded, or loading a game from last week would
## silently change the language back.
##
## Same reasoning as `ui/first_lessons.gd` keeping its seen-flags out of the
## save.

const CONFIG_PATH := "user://settings.cfg"

signal changed

## Godot locale codes. English is the source language — every string in the
## game is authored in it, and the translation table is keyed by the English
## text, so a missing Russian line falls back to readable English rather than
## to a placeholder key.
const LOCALES := {
	"ru": "Русский",
	"en": "English",
}

var locale: String = "ru"
var graphics_preset: int = 0        # GraphicsPreset.Preset: 0 Low, 1 Medium, 2 High
var master_volume: float = 0.8      # 0..1, mapped to dB on the Master bus
var music_volume: float = 0.7
var fullscreen: bool = false

var _config := ConfigFile.new()


func _ready() -> void:
	load_settings()
	apply_all()


func load_settings() -> void:
	if _config.load(CONFIG_PATH) != OK:
		# No file yet. Defaults above stand — including Russian, because the
		# person this is being built for reads Russian, and a first launch
		# should not make them go and find the language menu.
		return
	locale = str(_config.get_value("general", "locale", locale))
	graphics_preset = int(_config.get_value("video", "preset", graphics_preset))
	fullscreen = bool(_config.get_value("video", "fullscreen", fullscreen))
	master_volume = float(_config.get_value("audio", "master", master_volume))
	music_volume = float(_config.get_value("audio", "music", music_volume))


func save_settings() -> void:
	_config.set_value("general", "locale", locale)
	_config.set_value("video", "preset", graphics_preset)
	_config.set_value("video", "fullscreen", fullscreen)
	_config.set_value("audio", "master", master_volume)
	_config.set_value("audio", "music", music_volume)
	_config.save(CONFIG_PATH)


## Pushes every setting into the engine. Safe to call at any time.
func apply_all() -> void:
	TranslationServer.set_locale(locale)
	_apply_volume()
	_apply_window()
	_apply_graphics()
	changed.emit()


func set_locale(value: String) -> void:
	if not LOCALES.has(value) or value == locale:
		return
	locale = value
	TranslationServer.set_locale(locale)
	save_settings()
	changed.emit()


func set_graphics_preset(value: int) -> void:
	graphics_preset = clampi(value, 0, 2)
	_apply_graphics()
	save_settings()
	changed.emit()


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_apply_volume()
	save_settings()
	changed.emit()


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_apply_volume()
	save_settings()
	changed.emit()


func set_fullscreen(value: bool) -> void:
	fullscreen = value
	_apply_window()
	save_settings()
	changed.emit()


func _apply_graphics() -> void:
	# The preset node lives in whatever scene is running and may not exist yet
	# (the main menu has no world). Applying it is therefore best-effort here
	# and re-applied by the preset node's own _ready() through `graphics_preset`
	# below.
	var node := get_tree().get_first_node_in_group(GraphicsPreset.GROUP_NAME)
	if node != null and node.has_method("apply"):
		node.call("apply", graphics_preset)


func _apply_volume() -> void:
	AudioServer.set_bus_volume_db(0, _to_db(master_volume))
	AudioServer.set_bus_mute(0, master_volume <= 0.001)


## Linear slider to decibels. A linear slider mapped straight onto dB feels
## broken — everything happens in the top tenth — so this is the usual
## perceptual curve, with the bottom of the slider being true silence rather
## than a very quiet sound.
func _to_db(linear: float) -> float:
	if linear <= 0.001:
		return -80.0
	return linear_to_db(linear)


func _apply_window() -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen
		else DisplayServer.WINDOW_MODE_WINDOWED)
