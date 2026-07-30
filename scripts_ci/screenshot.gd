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

func _find_named(n: Node, wanted: String) -> Node:
	if n.name == wanted:
		return n
	for c in n.get_children():
		var f := _find_named(c, wanted)
		if f != null:
			return f
	return null

func _find_crowd(n: Node) -> Node:
	if n is VillagerCrowd:
		return n
	for c in n.get_children():
		var f := _find_crowd(c)
		if f != null:
			return f
	return null

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

	# SHOT_DAY_PHASE=0..1: jump the world clock (0 = sunrise, 0.25 = noon,
	# 0.5 = sunset, 0.75 = midnight). The day is ten real minutes long, so
	# without this a shot can only ever show the minute the harness booted in.
	var phase_spec := OS.get_environment("SHOT_DAY_PHASE")
	if not phase_spec.is_empty():
		Weather.set("_elapsed", float(phase_spec) * Weather.DAY_LENGTH_SECONDS)

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

	# SHOT_DUMP_ECONOMY: print each village's stores and live job counts. The
	# whole point of Phase 2 is that these numbers move and answer each other,
	# and a screenshot cannot show a ledger.
	if OS.get_environment("SHOT_DUMP_ECONOMY") != "":
		var crowd: Node = _find_crowd(self)
		for v_id in GameState.villages:
			var v: Village = GameState.villages[v_id]
			var line := "ECON %s | food %.1f | wood %.1f | devotion %.1f" % [
				v.display_name,
				Stockpile.get_amount(v, &"food"), Stockpile.get_amount(v, &"wood"), v.devotion]
			if crowd != null:
				line += " | field %d fish %d wood %d family %d idle %d" % [
					crowd.count_job(v.id, VillagerCrowd.Job.FIELD),
					crowd.count_job(v.id, VillagerCrowd.Job.FISHING),
					crowd.count_job(v.id, VillagerCrowd.Job.WOODCUTTING),
					crowd.count_job(v.id, VillagerCrowd.Job.FAMILY),
					crowd.count_job(v.id, VillagerCrowd.Job.IDLE)]
			print(line)

	# SHOT_DUMP_REACH: how big a target each village actually is, in metres
	# and in screen pixels at the current camera. The playability question
	# "can a person hit this" is a pixel question, not a design one.
	if OS.get_environment("SHOT_DUMP_REACH") != "":
		var cam3 := get_viewport().get_camera_3d()
		for v_id in GameState.villages:
			var v: Village = GameState.villages[v_id]
			var r: float = Reach.radius_for_village(v.id) + Godhood.reach_bonus()
			var px := -1.0
			if cam3 != null:
				var centre := Vector3(v.position_on_island.x, 0.0, v.position_on_island.y)
				var edge := centre + Vector3(r, 0.0, 0.0)
				if not cam3.is_position_behind(centre):
					px = cam3.unproject_position(centre).distance_to(cam3.unproject_position(edge))
			print("REACH %s | faith %.2f pop %d | radius %.1f m | %.0f px" % [
				v.display_name, v.faith_fraction, v.population, r, px])

	# SHOT_DUMP_AVATAR: where the player's creature actually is, and whether
	# that is above water.
	if OS.get_environment("SHOT_DUMP_AVATAR") != "":
		var av := _find_named(self, "Avatar")
		var isl := _find_named(self, "Island")
		if av is Node3D:
			var p3: Vector3 = (av as Node3D).global_position
			var ground := 0.0
			if isl != null and isl.has_method("sample_height"):
				ground = isl.call("sample_height", Vector2(p3.x, p3.z))
			print("AVATAR at %s | terrain here %.2f m | %s" % [
				p3, ground, "ON LAND" if ground > 0.5 else "UNDER WATER / IN THE SEA"])

	# SHOT_SHOW: comma-separated node names under the loaded scene to force
	# visible before the capture. Panels bound to a keypress cannot otherwise
	# be photographed by a harness that has no keyboard.
	var show_spec := OS.get_environment("SHOT_SHOW")
	if not show_spec.is_empty():
		for wanted in show_spec.split(","):
			var n := _find_named(self, wanted.strip_edges())
			if n == null:
				continue
			# open() where a panel has one (the pause menu also has to pause
			# the tree and fill in its own status line), plain visibility
			# otherwise. CanvasLayer is not a CanvasItem, so the obvious
			# `n is CanvasItem` test silently skips exactly the overlays most
			# worth photographing.
			if n.has_method("open_for"):
				# The village panel needs to be told WHICH village. Any of
				# them will do for a screenshot; the first registered one is
				# deterministic.
				var ids: Array = GameState.villages.keys()
				if not ids.is_empty():
					n.call("open_for", ids[0], _find_crowd(self))
			elif n.has_method("open"):
				n.call("open")
			elif "visible" in n:
				n.set("visible", true)
		for i in range(3):
			await get_tree().process_frame

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
