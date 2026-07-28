extends Node
## Generic screenshot harness. Loads whatever scene SHOT_SCENE points at as
## a child, lets SHOT_FRAMES frames pass (so TAA/SDFGI/SSAO have time to
## converge past their first, noisiest frame), captures the viewport, and
## quits. Invoke via:
##
##   SHOT_SCENE=res://world/god_view.tscn SHOT_OUT=/tmp/out.png \
##     xvfb-run -a godot --path . scripts_ci/screenshot_runner.tscn --rendering-driver vulkan
##
## Never run with --headless: that disables the rendering server entirely
## and produces a blank/failed capture (see docs/rendering.md).

func _ready() -> void:
	var scene_path := OS.get_environment("SHOT_SCENE")
	var out_path := OS.get_environment("SHOT_OUT")
	var frames := int(OS.get_environment("SHOT_FRAMES")) if OS.get_environment("SHOT_FRAMES") != "" else 20

	if scene_path.is_empty() or out_path.is_empty():
		push_error("screenshot.gd requires SHOT_SCENE and SHOT_OUT env vars")
		get_tree().quit(1)
		return

	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("Could not load scene: %s" % scene_path)
		get_tree().quit(1)
		return

	var instance := packed.instantiate()
	add_child(instance)

	for i in range(frames):
		await get_tree().process_frame

	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(out_path)
	if err != OK:
		push_error("Failed to save screenshot to %s (err %d)" % [out_path, err])
		get_tree().quit(1)
		return

	print("Screenshot saved: %s" % out_path)
	get_tree().quit(0)
