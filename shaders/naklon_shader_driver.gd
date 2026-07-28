extends Node
## NaklonShaderDriver
##
## Broadcasts `Naklon.unit()` to every shader in the game as ONE
## RenderingServer global shader uniform (`naklon_unit`), so any .gdshader
## that `#include`s res://shaders/naklon_globals.gdshaderinc reacts to
## Naklon live, with zero per-material wiring and zero polling.
##
## WHY THIS EXISTS: Godot's `global uniform` shader values are a runtime
## registry owned by RenderingServer, not something a plain Resource/material
## can push to on its own. Something has to call
## RenderingServer.global_shader_parameter_set() whenever Naklon changes.
## This Node is that something — deliberately tiny, deliberately not an
## autoload (project.godot is foundation-owned; see docs/systems/OWNERSHIP.md),
## and safe to instantiate more than once.
##
## HOW TO USE (read this if you are NOT package D):
## Add exactly one instance of this Node anywhere in your own scene, as
## early as you conveniently can (a direct child of your scene root is
## fine), so it exists before the first frame that draws a
## Naklon-reactive material. From then on it needs nothing else from you.
##
##   In a .tscn:
##     [node name="NaklonShaderDriver" type="Node" parent="."]
##     script = ExtResource("res://shaders/naklon_shader_driver.gd")
##
##   Purely from code:
##     var driver := Node.new()
##     driver.set_script(load("res://shaders/naklon_shader_driver.gd"))
##     add_child(driver)
##
## It is idempotent: _ready() checks whether the global shader parameter
## already exists before adding it, so having this Node alive in more than
## one scene/package at once (e.g. the god_view world AND a Sanctum
## interior loaded alongside it) is harmless — every instance ends up
## pushing the same value to the same global slot.
##
## PUBLIC SURFACE:
##   - No exported properties, no signals of its own. It is a bridge, not
##     a system. Read `Naklon.unit()` / listen to `Naklon.naklon_changed`
##     directly if your own script needs the value on the GDScript side —
##     this Node only exists to get the value INTO shader-land.
##   - Global shader uniform name: `naklon_unit` (float, 0..1). Any shader
##     can read it directly with `global uniform float naklon_unit;` even
##     without including naklon_globals.gdshaderinc, though the include
##     also gives you the mixing/noise helpers built on top of it.

const PARAM_NAME := &"naklon_unit"

func _ready() -> void:
	_ensure_global_param()
	_push_current()
	if not Naklon.naklon_changed.is_connected(_on_naklon_changed):
		Naklon.naklon_changed.connect(_on_naklon_changed)

func _exit_tree() -> void:
	if Naklon.naklon_changed.is_connected(_on_naklon_changed):
		Naklon.naklon_changed.disconnect(_on_naklon_changed)

func _ensure_global_param() -> void:
	var existing: PackedStringArray = RenderingServer.global_shader_parameter_get_list()
	if not existing.has(PARAM_NAME):
		RenderingServer.global_shader_parameter_add(
			PARAM_NAME, RenderingServer.GLOBAL_VAR_TYPE_FLOAT, Naklon.unit()
		)

func _on_naklon_changed(_old_value: float, _new_value: float) -> void:
	_push_current()

func _push_current() -> void:
	RenderingServer.global_shader_parameter_set(PARAM_NAME, Naklon.unit())
