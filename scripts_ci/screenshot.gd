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

	# SHOT_DUMP_VILLAGES: print every registered village with its final,
	# terrain-resolved position. The layout is planned at runtime now
	# (world/village/settlement_planner.gd), so this is the only way to find
	# out where the villages actually ended up.
	if OS.get_environment("SHOT_DUMP_VILLAGES") != "":
		for v_id in GameState.villages:
			var v: Village = GameState.villages[v_id]
			print("VILLAGE %s | %s | %s | pop %d | faith %.2f"
				% [v.id, v.display_name, v.position_on_island, v.population, v.faith_fraction])

	# SHOT_CAM="x,y,z,tx,ty,tz": park the active camera at x/y/z looking at
	# tx/ty/tz. Without it a shot is stuck with whatever the scene authored,
	# which is useless for checking one particular village out of fifteen.
	var cam_spec := OS.get_environment("SHOT_CAM")
	if not cam_spec.is_empty():
		var n: PackedStringArray = cam_spec.split(",")
		var cam := get_viewport().get_camera_3d()
		if cam != null and n.size() >= 6:
			# The camera rig writes the camera's transform every frame, so
			# parking the camera is not enough — the rig has to stop driving it
			# first, or the next frame puts it straight back.
			var up: Node = cam
			for i in range(4):
				if up == null:
					break
				up.set_process(false)
				up.set_physics_process(false)
				up = up.get_parent()
			cam.set_as_top_level(true)
			cam.global_position = Vector3(float(n[0]), float(n[1]), float(n[2]))
			cam.look_at(Vector3(float(n[3]), float(n[4]), float(n[5])), Vector3.UP)
			# Let the moved camera actually render before the capture.
			for i in range(3):
				await get_tree().process_frame

	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(out_path)
	if err != OK:
		push_error("Failed to save screenshot to %s (err %d)" % [out_path, err])
		get_tree().quit(1)
		return

	print("Screenshot saved: %s" % out_path)
	get_tree().quit(0)
