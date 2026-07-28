class_name SigilTemplates
extends RefCounted
## Original sigil shapes for the nine base rites. Every shape here is an
## invented geometric gesture (a ripple-with-a-tail, a saw-tooth zigzag, an
## in/out spiral, a sickle arc, a doorway arch, a chevron-tipped arrow, a
## lightning zig, a plain warding circle) — none of them are a real runic
## alphabet, a real sacred symbol, or a swastika-family motif in any
## rotation. Shapes are generated parametrically (arcs/spirals/waves sampled
## as point lists, straight edges given as bare corner vertices) rather than
## typed in as raw coordinate literals, which keeps the geometry exact and
## avoids hand-transcription typos — the resulting Array[Vector2] lists are
## exactly the same shape data a hand-authored template would be.
##
## Coordinates use a y-down convention (matches screen space / mouse
## position, which is what SigilCaster feeds the recognizer at runtime) in
## an arbitrary local unit square roughly [-100, 100]; UnistrokeRecognizer
## rescales everything to its own reference square, so the absolute unit
## doesn't matter, only the shape.

## rite_id -> human-readable description, single source of truth also used
## by docs/systems/sigils.md's rite table.
const DESCRIPTIONS: Dictionary = {
	&"rain_call": "A rippling sine-wave (2 gentle humps) with a short tail dropping straight down at the end, like a raindrop falling off the last ripple.",
	&"path_gate": "A doorway arch: straight post up, a rounded lintel arcing over the top, straight post back down — drawn in one continuous stroke.",
	&"harvest": "A sickle: a wide open crescent arc with a short straight handle flaring off one tip.",
	&"lumber": "A tight, even saw-tooth zigzag (four sharp peaks), like a ripsaw's edge.",
	&"repair": "An inward spiral: starts wide and winds down to a tight center, like binding a wound closed.",
	&"ward": "A plain closed circle with a short straight tail stub at the top where the stroke enters it, like a ward drawn in the air before the hand closes the loop.",
	&"fire_arrow": "A diagonal shaft rising left-to-right with a small chevron notch doubled back at the tip, like a nocked arrow's fletching.",
	&"lightning": "A jagged, asymmetric bolt: three sharp long-short-long angles, unlike lumber's small even teeth.",
	&"storm": "An outward-growing spiral (opposite winding sense and more turns than repair's), like a gyre widening from a calm eye.",
}

static func get_raw_templates() -> Dictionary:
	return {
		&"rain_call": _rain_call(),
		&"path_gate": _path_gate(),
		&"harvest": _harvest(),
		&"lumber": _lumber(),
		&"repair": _repair(),
		&"ward": _ward(),
		&"fire_arrow": _fire_arrow(),
		&"lightning": _lightning(),
		&"storm": _storm(),
	}

static func get_descriptions() -> Dictionary:
	return DESCRIPTIONS

# ---------------------------------------------------------------------------
# Parametric shape helpers
# ---------------------------------------------------------------------------

static func _line(from: Vector2, to: Vector2, steps: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in range(steps + 1):
		out.append(from.lerp(to, float(i) / float(steps)))
	return out

static func _arc(center: Vector2, radius: float, start_deg: float, end_deg: float, steps: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in range(steps + 1):
		var deg: float = lerpf(start_deg, end_deg, float(i) / float(steps))
		var rad: float = deg_to_rad(deg)
		out.append(center + Vector2(cos(rad), sin(rad)) * radius)
	return out

static func _spiral(center: Vector2, start_radius: float, end_radius: float, start_deg: float, turns: float, steps: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var end_deg: float = start_deg + turns * 360.0
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var deg: float = lerpf(start_deg, end_deg, t)
		var radius: float = lerpf(start_radius, end_radius, t)
		var rad: float = deg_to_rad(deg)
		out.append(center + Vector2(cos(rad), sin(rad)) * radius)
	return out

static func _sine_wave(from_x: float, to_x: float, y: float, amplitude: float, cycles: float, steps: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var x: float = lerpf(from_x, to_x, t)
		var yy: float = y + sin(t * TAU * cycles) * amplitude
		out.append(Vector2(x, yy))
	return out

# ---------------------------------------------------------------------------
# The nine rites
# ---------------------------------------------------------------------------

## Water/Rain-call: ripple wave, then a short tail falling away downward.
static func _rain_call() -> Array[Vector2]:
	var pts := _sine_wave(-80.0, 40.0, 10.0, 22.0, 1.75, 28)
	pts.append_array(_line(pts[pts.size() - 1], pts[pts.size() - 1] + Vector2(8.0, 65.0), 8))
	return pts

## Path-Gate: an arch/doorway drawn in one stroke, up - over - down.
static func _path_gate() -> Array[Vector2]:
	var pts := _line(Vector2(-55.0, 85.0), Vector2(-55.0, -15.0), 10)
	pts.append_array(_arc(Vector2(0.0, -15.0), 55.0, 180.0, 0.0, 18))
	pts.append_array(_line(Vector2(55.0, -15.0), Vector2(55.0, 85.0), 10))
	return pts

## Harvest: a sickle blade (wide crescent) with a short handle flare.
static func _harvest() -> Array[Vector2]:
	var pts := _arc(Vector2.ZERO, 70.0, 205.0, -25.0, 26)
	var start_point: Vector2 = pts[0]
	var handle_end: Vector2 = start_point + start_point.normalized() * 28.0
	var handle := _line(start_point, handle_end, 6)
	handle.reverse()
	handle.append_array(pts)
	return handle

## Lumber: a tight, even ripsaw zigzag.
static func _lumber() -> Array[Vector2]:
	var verts: Array[Vector2] = [
		Vector2(-80.0, 45.0), Vector2(-56.0, -45.0),
		Vector2(-32.0, 45.0), Vector2(-8.0, -45.0),
		Vector2(16.0, 45.0), Vector2(40.0, -45.0),
		Vector2(64.0, 45.0), Vector2(80.0, -20.0),
	]
	return verts

## Repair: winds inward, tight at the center — "binding closed".
static func _repair() -> Array[Vector2]:
	return _spiral(Vector2.ZERO, 82.0, 6.0, 0.0, 2.25, 44)

## Ward: a plain closed protective circle with a short entry tail.
static func _ward() -> Array[Vector2]:
	var tail := _line(Vector2(0.0, -100.0), Vector2(0.0, -68.0), 6)
	tail.append_array(_arc(Vector2.ZERO, 68.0, -90.0, 270.0, 32))
	return tail

## Fire-Arrow: a rising diagonal shaft with a small chevron arrowhead.
static func _fire_arrow() -> Array[Vector2]:
	return [
		Vector2(-72.0, 72.0),
		Vector2(72.0, -72.0), # tip
		Vector2(34.0, -38.0), # barb A, back down along one side
		Vector2(72.0, -72.0), # return to tip
		Vector2(34.0, -95.0), # barb B, back along the other side
	]

## Lightning: a jagged, irregular bolt — long/short/long segments.
static func _lightning() -> Array[Vector2]:
	return [
		Vector2(-22.0, -92.0),
		Vector2(18.0, -8.0),
		Vector2(-14.0, -8.0),
		Vector2(28.0, 92.0),
	]

## Storm: a wide, multi-turn outward gyre — opposite winding and more
## turns than Repair so the recognizer's shape distance tells them apart.
static func _storm() -> Array[Vector2]:
	return _spiral(Vector2.ZERO, 8.0, 95.0, 0.0, -3.0, 52)
