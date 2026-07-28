extends Node3D
## Standalone preview/test bed for package D's Naklon-reactive material
## system (shaders/naklon_reactive.gdshader + materials/naklon_*.tres).
## Not part of the game's main scene tree — this is the demo scene named in
## the driver's own doc comment, kept in shaders/ since that's package D's
## owned directory. Other packages should copy the NaklonShaderDriver
## instancing pattern shown in naklon_demo.tscn into their own scenes rather
## than depending on this file.
##
## Controls (keyboard, no input-map action needed — project.godot is
## foundation-owned so this deliberately avoids InputMap):
##   Left Arrow  -> shift Naklon toward Mercy (-1)
##   Right Arrow -> shift Naklon toward Cruelty (+1)
##   Space       -> snap Naklon back to neutral (0)

@onready var _readout: Label3D = $NaklonReadout

func _process(delta: float) -> void:
	if Input.is_key_pressed(KEY_LEFT):
		Naklon.shift(-0.6 * delta)
	if Input.is_key_pressed(KEY_RIGHT):
		Naklon.shift(0.6 * delta)
	if Input.is_key_pressed(KEY_SPACE):
		Naklon.value = 0.0
	if _readout:
		_readout.text = "Naklon: %.2f  (unit %.2f)" % [Naklon.value, Naklon.unit()]
