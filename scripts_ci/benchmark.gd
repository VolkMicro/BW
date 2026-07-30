extends Node
## Measures how fast this game actually runs, on whatever machine runs it.
##
## ---------------------------------------------------------------------------
## WHY THIS EXISTS
## ---------------------------------------------------------------------------
## "It runs at 5-6 fps" and "the frame rate is unmeasured on the target
## hardware" have been the two largest open questions in this project for its
## whole history, and neither can be answered from a sandbox: everything here
## renders through llvmpipe, a software rasteriser, which says nothing about
## an Intel iGPU or an RTX card.
##
## So the measurement has to travel to the machine instead of the machine
## travelling to the measurement. One command, no editor, no account, no
## remote access:
##
##     godot --path . scripts_ci/benchmark.tscn
##
## It prints a table and exits. Paste the table.
##
## ---------------------------------------------------------------------------
## WHAT IT MEASURES AND WHY IT IS NOT JUST "AVERAGE FPS"
## ---------------------------------------------------------------------------
## Average frame rate hides exactly the problem this game has. A god-sim that
## averages 30 fps but stalls for 400 ms whenever the camera swings over a new
## part of the island feels broken, and the average will not say so. So each
## segment reports the median, the 95th percentile (the slow frames you feel)
## and the single worst frame.
##
## Three camera segments, because the cost profile is completely different at
## each and knowing WHICH one is slow is the whole diagnosis:
##
##   god view  — the whole island, everything drawn, most draw calls
##   mid       — a few villages, houses and props at full detail
##   close     — one village, grass and villagers at their densest
##
## The first `WARMUP_FRAMES` are thrown away. On a cold shader cache the first
## frames of each new view include pipeline compilation, which is a real cost
## but a once-per-machine one, and mixing it into a steady-state number tells
## you nothing you can act on. It is reported separately.

## Overridable so the benchmark itself can be smoke-tested somewhere slow.
## 585 frames is a few seconds on a real GPU and over ten minutes under a
## software rasteriser, which is the only reason these are not constants.
@onready var WARMUP_FRAMES: int = int(OS.get_environment("BENCH_WARMUP")) if OS.get_environment("BENCH_WARMUP") != "" else 45
@onready var SEGMENT_FRAMES: int = int(OS.get_environment("BENCH_FRAMES")) if OS.get_environment("BENCH_FRAMES") != "" else 150

## eye, look-at, label
const SEGMENTS := [
	{"eye": Vector3(0, 420, 830), "at": Vector3(0, 0, 0), "name": "god view (whole island)"},
	{"eye": Vector3(-120, 210, 430), "at": Vector3(-40, 20, -30), "name": "mid (several villages)"},
	{"eye": Vector3(-258, 56, -140), "at": Vector3(-258, 26, -196), "name": "close (one village)"},
]

var _world: Node = null
var _camera: Camera3D = null


func _ready() -> void:
	print("")
	print("TITHE & TERROR — performance benchmark")
	print("Godot %s" % Engine.get_version_info().string)
	print("Renderer: %s" % ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"))
	print("Adapter:  %s (%s)" % [RenderingServer.get_video_adapter_name(),
		RenderingServer.get_video_adapter_vendor()])
	print("Window:   %s" % str(DisplayServer.window_get_size()))
	print("")

	var t_load := Time.get_ticks_msec()
	var packed: PackedScene = load("res://world/god_view.tscn")
	_world = packed.instantiate()
	add_child(_world)
	print("World built in %d ms (before the first frame could be drawn)"
		% (Time.get_ticks_msec() - t_load))

	var preset := get_tree().get_first_node_in_group(GraphicsPreset.GROUP_NAME)
	if preset != null:
		print("Graphics preset: %s" % GraphicsPreset.preset_name(preset.call("current")))
	var vp := get_viewport()
	print("3D scale: %.2f   render size: %s" % [vp.scaling_3d_scale, str(vp.get_visible_rect().size)])
	print("")

	await get_tree().process_frame
	_camera = vp.get_camera_3d()
	if _camera == null:
		print("BENCHMARK FAILED: no camera in the scene.")
		get_tree().quit(1)
		return
	# The rig writes the camera transform every frame; it has to stop first or
	# the segments below have no effect at all.
	var up: Node = _camera
	for i in range(4):
		if up == null:
			break
		up.set_process(false)
		up.set_physics_process(false)
		up = up.get_parent()
	_camera.set_as_top_level(true)

	print("%-26s %8s %8s %8s %8s %9s" % ["segment", "median", "avg", "95th", "worst", "median fps"])
	print("%-26s %8s %8s %8s %8s %9s" % ["", "ms", "ms", "ms", "ms", ""])
	var overall: Array[float] = []
	for seg in SEGMENTS:
		var times := await _measure(seg)
		overall.append_array(times)
		_report(String(seg.name), times)

	print("")
	_report("ALL SEGMENTS", overall)
	print("")
	print("Villagers: %d   Wildlife: %d" % [_count_villagers(), _count_wildlife()])
	print("Draw calls this frame: %d   Primitives: %d" % [
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	print("Video memory: %.0f MB" % (float(RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)) / 1048576.0))
	print("")
	print("Paste everything from the header down.")
	get_tree().quit(0)


## Parks the camera, throws away the warm-up, then times every frame.
func _measure(seg: Dictionary) -> Array[float]:
	_camera.global_position = seg.eye
	_camera.look_at(seg.at, Vector3.UP)

	var warm_start := Time.get_ticks_usec()
	for i in WARMUP_FRAMES:
		await get_tree().process_frame
	var warm_ms := float(Time.get_ticks_usec() - warm_start) / 1000.0

	var times: Array[float] = []
	for i in SEGMENT_FRAMES:
		var t := Time.get_ticks_usec()
		await get_tree().process_frame
		times.append(float(Time.get_ticks_usec() - t) / 1000.0)

	# Warm-up much slower than the steady state means pipeline compilation,
	# which is a once-per-machine cost and must not be blamed on the scene.
	var median := _percentile(times.duplicate(), 0.5)
	if warm_ms / float(WARMUP_FRAMES) > median * 2.0:
		print("   (%s: first %d frames averaged %.0f ms — shader compilation, once per machine)"
			% [seg.name, WARMUP_FRAMES, warm_ms / float(WARMUP_FRAMES)])
	return times


func _report(label: String, times: Array[float]) -> void:
	if times.is_empty():
		return
	var sorted := times.duplicate()
	sorted.sort()
	var total := 0.0
	for t in sorted:
		total += t
	var median := _percentile(sorted, 0.5)
	print("%-26s %8.1f %8.1f %8.1f %8.1f %9.1f" % [
		label, median, total / float(sorted.size()),
		_percentile(sorted, 0.95), sorted[sorted.size() - 1],
		1000.0 / maxf(median, 0.001)])


static func _percentile(sorted_times: Array[float], p: float) -> float:
	if sorted_times.is_empty():
		return 0.0
	var i := clampi(int(round(p * float(sorted_times.size() - 1))), 0, sorted_times.size() - 1)
	return sorted_times[i]


func _count_villagers() -> int:
	var crowd := _find(_world, "VillagerCrowd")
	return int(crowd.call("get_population")) if crowd != null and crowd.has_method("get_population") else -1


func _count_wildlife() -> int:
	var wl := _find(_world, "WildlifeManager")
	return int(wl.call("total_alive")) if wl != null and wl.has_method("total_alive") else -1


func _find(n: Node, wanted: String) -> Node:
	if n == null:
		return null
	if n.name == wanted or n.get_class() == wanted:
		return n
	for c in n.get_children():
		var f := _find(c, wanted)
		if f != null:
			return f
	return null
