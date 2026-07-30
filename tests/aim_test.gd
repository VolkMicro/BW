extends Node3D
## Where does a rite land? Playability regression guard.
##
## The rite used to be aimed at the Hand's position, i.e. wherever the mouse
## stopped. A recognisable sigil spans 150-300 screen pixels and a village's
## Reach circle is about 25-35, so "draw a shape over the village" finished
## far outside it and the rite hit nothing. This checks the two properties
## that fix depends on:
##
##   1. the centroid of a stroke is near the middle of the shape, not its end;
##   2. a camera ray through a viewport point lands on the terrain under it.
##
## Run: godot --headless --path . tests/aim_test.tscn

func _ready() -> void:
	var failures := 0

	# 1. Centroid vs endpoint, on the real harvest template.
	var pts: Array = SigilTemplates.get_raw_templates()[&"harvest"]
	var typed: Array[Vector2] = []
	for p: Vector2 in pts:
		typed.append(p)
	var centre := UnistrokeRecognizer.centroid(typed)
	var box := UnistrokeRecognizer.bounding_box(typed)
	var box_middle := box.position + box.size * 0.5
	var last: Vector2 = typed[typed.size() - 1]

	failures += _expect(centre.distance_to(box_middle) < box.size.length() * 0.25,
		"the centroid sits near the middle of the shape (off by %.1f of %.1f)"
			% [centre.distance_to(box_middle), box.size.length()])
	failures += _expect(last.distance_to(box_middle) > centre.distance_to(box_middle),
		"the stroke's END is further from the middle than its centroid is — which is why aiming with it missed")

	# 2. A ray through the centre of the screen hits the ground under it.
	var terrain := IslandTerrain.new()
	terrain.size_meters = 600.0
	terrain.resolution = 129
	terrain.max_height = 90.0
	terrain.auto_generate_on_ready = true
	add_child(terrain)

	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(0.0, 260.0, 300.0)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	await get_tree().process_frame

	var screen_middle: Vector2 = Vector2(get_viewport().get_visible_rect().size) * 0.5
	var hit := _march(cam, terrain, screen_middle)
	var ground := terrain.sample_height(Vector2(hit.x, hit.z))
	failures += _expect(absf(hit.y - ground) < 1.0,
		"the marched point sits ON the ground (y %.2f vs terrain %.2f)" % [hit.y, ground])

	var ray_dir := cam.project_ray_normal(screen_middle)
	var along := (hit - cam.global_position).normalized()
	failures += _expect(along.dot(ray_dir) > 0.999,
		"and it is actually on the camera ray through that pixel (dot %.4f)" % along.dot(ray_dir))

	if failures == 0:
		print("aim_test: OK")
		get_tree().quit(0)
	else:
		print("aim_test: %d FAILURE(S)" % failures)
		get_tree().quit(1)


## The same march god_view.gd does, kept here so the property is tested even
## though the production copy lives in a scene script.
func _march(cam: Camera3D, terrain: IslandTerrain, point: Vector2) -> Vector3:
	var origin := cam.project_ray_origin(point)
	var dir := cam.project_ray_normal(point)
	var t := 0.0
	var step := 12.0
	var last_above := true
	for i in 200:
		var p := origin + dir * t
		var above := p.y > terrain.sample_height(Vector2(p.x, p.z))
		if i > 0 and above != last_above:
			var lo := t - step
			var hi := t
			for _b in 12:
				var mid := (lo + hi) * 0.5
				var q := origin + dir * mid
				if q.y > terrain.sample_height(Vector2(q.x, q.z)):
					lo = mid
				else:
					hi = mid
			return origin + dir * ((lo + hi) * 0.5)
		last_above = above
		t += step
	return origin + dir * t


func _expect(condition: bool, what: String) -> int:
	if condition:
		return 0
	print("  FAIL: %s" % what)
	return 1
