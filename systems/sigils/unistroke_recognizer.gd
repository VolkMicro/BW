class_name UnistrokeRecognizer
extends RefCounted
## A from-scratch reimplementation of the $1 Unistroke Recognizer
## (Wobbrock, Wilson & Li, "Gestures without Libraries, Toolkits or Training:
## A $1 Recognizer for User Interface Prototypes", UIST 2007 — a published
## academic method, public domain algorithm description, not any game's
## proprietary asset). Every step below (resample, indicative-angle
## rotation, non-uniform scale to a reference square, translate-to-origin,
## golden-section-search rotation alignment) follows the paper's published
## pseudocode, reimplemented here in typed GDScript.
##
## This class is deliberately dependency-free (extends RefCounted, no
## autoload, no scene) so it can be unit-tested in isolation and reused by
## anything that produces a 2D point path — SigilCaster is the only
## current caller, but nothing here assumes it.

const RESAMPLE_POINTS := 64
const SQUARE_SIZE := 250.0
const ANGLE_RANGE := 45.0 # degrees, +/- search range for best-angle alignment
const ANGLE_PRECISION := 2.0 # degrees, golden-section search stops within this
const HALF_DIAGONAL := 0.5 * SQUARE_SIZE * 1.4142135623730951 # 0.5 * sqrt(2*size^2)

## StringName -> Array[Vector2], already resampled/rotated/scaled/translated
## (i.e. in the same normalized space `recognize()` puts the candidate in).
var _templates: Dictionary = {}

func _init(raw_templates: Dictionary = {}) -> void:
	if not raw_templates.is_empty():
		load_templates(raw_templates)

## Adds (or overwrites) templates. `raw_templates` is StringName -> Array of
## Vector2 in the template author's own arbitrary coordinate space — this
## function normalizes them through the identical pipeline `recognize()`
## puts a live stroke through, which is what makes the two comparable.
func load_templates(raw_templates: Dictionary) -> void:
	for rite_id in raw_templates.keys():
		var pts: Array[Vector2] = _coerce(raw_templates[rite_id])
		_templates[rite_id] = _normalize(pts)

func has_template(rite_id: StringName) -> bool:
	return _templates.has(rite_id)

func template_ids() -> Array:
	return _templates.keys()

## Recognizes a raw, un-normalized stroke (screen-space or any consistent
## 2D unit) against every loaded template and returns
## {"rite_id": StringName, "score": float 0..1}. `score` is 1.0 for a
## perfect match and falls off with point-cloud distance; empty rite_id
## (&"") with score 0.0 means "no templates loaded" or "degenerate stroke".
func recognize(raw_points: Array) -> Dictionary:
	var points: Array[Vector2] = _coerce(raw_points)
	if points.size() < 2 or _templates.is_empty():
		return {"rite_id": &"", "score": 0.0}

	var candidate := _normalize(points)
	var best_id: StringName = &""
	var best_distance := INF
	for rite_id in _templates.keys():
		var template: Array[Vector2] = _templates[rite_id]
		var d := distance_at_best_angle(
			candidate, template,
			deg_to_rad(-ANGLE_RANGE), deg_to_rad(ANGLE_RANGE), deg_to_rad(ANGLE_PRECISION)
		)
		if d < best_distance:
			best_distance = d
			best_id = rite_id

	var score: float = 1.0 - (best_distance / HALF_DIAGONAL)
	return {"rite_id": best_id, "score": maxf(score, 0.0)}

# ---------------------------------------------------------------------------
# $1 pipeline steps (static, individually testable)
# ---------------------------------------------------------------------------

static func _coerce(raw_points: Array) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for p in raw_points:
		out.append(p as Vector2)
	return out

static func _normalize(points: Array[Vector2]) -> Array[Vector2]:
	var pts := resample(points, RESAMPLE_POINTS)
	var radians := indicative_angle(pts)
	pts = rotate_by(pts, -radians)
	pts = scale_to_square(pts, SQUARE_SIZE)
	pts = translate_to_origin(pts)
	return pts

static func path_length(points: Array[Vector2]) -> float:
	var d := 0.0
	for i in range(1, points.size()):
		d += points[i - 1].distance_to(points[i])
	return d

## Resamples an arbitrary-density polyline into exactly `n` equidistant
## points along its length, per the $1 paper's Resample() step.
static func resample(points: Array[Vector2], n: int) -> Array[Vector2]:
	var pts: Array[Vector2] = points.duplicate()
	if pts.size() < 2:
		var single: Array[Vector2] = []
		var fill: Vector2 = pts[0] if pts.size() > 0 else Vector2.ZERO
		for i in range(n):
			single.append(fill)
		return single

	var total_length := path_length(pts)
	if total_length <= 0.0001:
		var degenerate: Array[Vector2] = []
		for i in range(n):
			degenerate.append(pts[0])
		return degenerate

	var interval: float = total_length / float(n - 1)
	var d := 0.0
	var new_points: Array[Vector2] = [pts[0]]
	var i := 1
	while i < pts.size():
		var dist: float = pts[i - 1].distance_to(pts[i])
		if dist > 0.0 and (d + dist) >= interval:
			var t: float = (interval - d) / dist
			var q := pts[i - 1].lerp(pts[i], t)
			new_points.append(q)
			pts.insert(i, q) # walk the new point as if it had always been there
			d = 0.0
		else:
			d += dist
		i += 1

	# Floating-point drift can leave us one point short; the paper's
	# reference implementations pad with the final point when this happens.
	while new_points.size() < n:
		new_points.append(pts[pts.size() - 1])
	if new_points.size() > n:
		new_points.resize(n)
	return new_points

static func centroid(points: Array[Vector2]) -> Vector2:
	var sum := Vector2.ZERO
	for p in points:
		sum += p
	return sum / float(points.size())

## Angle from the centroid to the stroke's first point — the "indicative
## angle" the $1 paper rotates out so gestures drawn at any starting
## orientation still compare fairly.
static func indicative_angle(points: Array[Vector2]) -> float:
	var c := centroid(points)
	return atan2(points[0].y - c.y, points[0].x - c.x)

static func rotate_by(points: Array[Vector2], radians: float) -> Array[Vector2]:
	var c := centroid(points)
	var cos_r := cos(radians)
	var sin_r := sin(radians)
	var out: Array[Vector2] = []
	for p in points:
		var dx: float = p.x - c.x
		var dy: float = p.y - c.y
		var nx: float = dx * cos_r - dy * sin_r + c.x
		var ny: float = dx * sin_r + dy * cos_r + c.y
		out.append(Vector2(nx, ny))
	return out

static func bounding_box(points: Array[Vector2]) -> Rect2:
	var min_x: float = points[0].x
	var max_x: float = points[0].x
	var min_y: float = points[0].y
	var max_y: float = points[0].y
	for p in points:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)
	return Rect2(min_x, min_y, max_x - min_x, max_y - min_y)

## Non-uniform scale to a reference square, per the paper (this is what
## makes the recognizer indifferent to whether a gesture was drawn tall,
## wide, or small — the "distortion" the paper explicitly accepts as
## harmless for its accuracy target).
static func scale_to_square(points: Array[Vector2], size: float) -> Array[Vector2]:
	var box := bounding_box(points)
	var w: float = box.size.x if box.size.x > 0.0001 else 0.0001
	var h: float = box.size.y if box.size.y > 0.0001 else 0.0001
	var out: Array[Vector2] = []
	for p in points:
		out.append(Vector2(p.x * (size / w), p.y * (size / h)))
	return out

static func translate_to_origin(points: Array[Vector2]) -> Array[Vector2]:
	var c := centroid(points)
	var out: Array[Vector2] = []
	for p in points:
		out.append(p - c)
	return out

## Mean point-to-point distance between two equal-length, index-aligned
## point clouds (the paper's PathDistance()).
static func path_distance(a: Array[Vector2], b: Array[Vector2]) -> float:
	var n: int = mini(a.size(), b.size())
	if n == 0:
		return 0.0
	var d := 0.0
	for i in range(n):
		d += a[i].distance_to(b[i])
	return d / float(n)

static func distance_at_angle(points: Array[Vector2], template: Array[Vector2], radians: float) -> float:
	return path_distance(rotate_by(points, radians), template)

## Golden-section search for the rotation (within +/- angle_range) that
## minimizes path distance between the candidate and one template — the
## paper's DistanceAtBestAngle(), used instead of a brute-force angle scan
## because it converges in ~O(log) evaluations.
static func distance_at_best_angle(
	points: Array[Vector2], template: Array[Vector2],
	angle_a: float, angle_b: float, threshold: float
) -> float:
	var phi: float = 0.5 * (-1.0 + sqrt(5.0))
	var a := angle_a
	var b := angle_b
	var x1: float = phi * a + (1.0 - phi) * b
	var f1: float = distance_at_angle(points, template, x1)
	var x2: float = (1.0 - phi) * a + phi * b
	var f2: float = distance_at_angle(points, template, x2)
	while absf(b - a) > threshold:
		if f1 < f2:
			b = x2
			x2 = x1
			f2 = f1
			x1 = phi * a + (1.0 - phi) * b
			f1 = distance_at_angle(points, template, x1)
		else:
			a = x1
			x1 = x2
			f1 = f2
			x2 = (1.0 - phi) * a + phi * b
			f2 = distance_at_angle(points, template, x2)
	return minf(f1, f2)
