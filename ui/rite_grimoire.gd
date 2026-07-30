extends Control
class_name RiteGrimoire
## The panel that shows the player what a rite actually looks like.
##
## ---------------------------------------------------------------------------
## WHY THIS REPLACED A LABEL
## ---------------------------------------------------------------------------
## The only verb in this game is drawing a shape. Until now the game explained
## those shapes in prose — "a sickle: a wide open crescent arc with a short
## straight handle flaring off one tip" — and left the player to translate a
## sentence into a stroke against a recognizer that scores them on how close
## they got. That is not a difficulty curve, it is a guessing game, and it is
## the single largest reason the game reads as unplayable to someone who has
## not read the source.
##
## `SigilTemplates` has held the exact point list for every rite since it was
## written. This draws it.
##
## ---------------------------------------------------------------------------
## DIRECTION IS PART OF THE SHAPE
## ---------------------------------------------------------------------------
## `UnistrokeRecognizer` is a $1-family recognizer: it resamples the stroke
## into an ordered point list and compares point-for-point, so a circle drawn
## anticlockwise does not match a circle drawn clockwise. A picture of the
## finished shape therefore is not enough information to reproduce it — where
## the stroke STARTS and which way it runs matter just as much. Every sigil
## here is drawn with a start dot and an arrowhead at the finish, and the line
## brightens along its length so the direction reads even at a glance.
##
## Locked rites are drawn too, as dim silhouettes: knowing that a shape exists
## and is not yet yours is the whole motivation for hunting a scroll.

const SIGIL_BOX := 84.0        ## side of the square each stroke is drawn into
const ROW_GAP := 14.0
const PAD := 16.0
const TEXT_LEFT := SIGIL_BOX + PAD * 2.0

const KNOWN_COLOR := Color(0.86, 0.90, 0.98)
const LOCKED_COLOR := Color(0.52, 0.55, 0.62, 0.55)
const GIFT_COLOR := Color(0.62, 0.86, 0.68)
const TERROR_COLOR := Color(0.92, 0.62, 0.52)
const PANEL_COLOR := Color(0.05, 0.06, 0.09, 0.82)

## Filled by the owner so this panel does not have to know the rite tables.
## rite_id -> true if the rite is a terror rite.
var terror_rites: Dictionary = {}

var _rows: Array = []   # {id, points: PackedVector2Array, known: bool, desc: String}
var _font: Font = null
var _row_height: float = 0.0


func _ready() -> void:
	_font = ThemeDB.fallback_font
	refresh()


## Rebuilds from ScrollBook. Call whenever a scroll is learned.
func refresh() -> void:
	_rows.clear()
	var known: Array[StringName] = ScrollBook.known_rite_ids()
	var raw: Dictionary = SigilTemplates.get_raw_templates()
	# Known first, then locked: the player's own kit is what they need at a
	# glance, and the locked list is a wish list underneath it.
	var ordered: Array = []
	for rite_id in known:
		ordered.append(rite_id)
	for rite_id in ScrollBook.locked_rite_ids():
		ordered.append(rite_id)

	for rite_id in ordered:
		var pts: Array = raw.get(rite_id, [])
		if pts.is_empty():
			continue
		_rows.append({
			"id": rite_id,
			"points": _fit(pts),
			"known": rite_id in known,
			"desc": String(SigilTemplates.DESCRIPTIONS.get(rite_id, "")),
		})

	_row_height = maxf(SIGIL_BOX, 62.0) + ROW_GAP
	custom_minimum_size = Vector2(custom_minimum_size.x,
		PAD * 2.0 + 30.0 + float(_rows.size()) * _row_height)
	queue_redraw()


## Scales a template's points into the drawing box, preserving aspect so a
## shape is never squashed into something the player then cannot reproduce.
func _fit(points: Array) -> PackedVector2Array:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p: Vector2 in points:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var span: Vector2 = hi - lo
	var scale: float = (SIGIL_BOX - 14.0) / maxf(maxf(span.x, span.y), 0.001)
	var offset: Vector2 = (Vector2(SIGIL_BOX, SIGIL_BOX) - span * scale) * 0.5
	var out := PackedVector2Array()
	for p: Vector2 in points:
		out.append((p - lo) * scale + offset)
	return out


func _draw() -> void:
	if _font == null:
		return
	var w: float = size.x
	draw_rect(Rect2(Vector2.ZERO, Vector2(w, custom_minimum_size.y)), PANEL_COLOR, true)
	draw_string(_font, Vector2(PAD, PAD + 16.0), tr("RITES"), HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
		Color(0.95, 0.93, 0.85))

	var y: float = PAD + 30.0
	for row in _rows:
		_draw_row(row, Vector2(PAD, y), w)
		y += _row_height


func _draw_row(row: Dictionary, at: Vector2, panel_width: float) -> void:
	var known: bool = row.known
	var line_color: Color = KNOWN_COLOR if known else LOCKED_COLOR
	var pts: PackedVector2Array = row.points

	# The stroke, brightening from start to finish.
	for i in range(pts.size() - 1):
		var t: float = float(i) / maxf(float(pts.size() - 2), 1.0)
		var c: Color = line_color * Color(1.0, 1.0, 1.0, lerpf(0.42, 1.0, t))
		draw_line(at + pts[i], at + pts[i + 1], c, 2.4, true)

	if pts.size() >= 2:
		# Start: a dot, meaning "put the mouse down here".
		draw_circle(at + pts[0], 3.6, line_color)
		# Finish: an arrowhead built off the last segment's direction.
		var tip: Vector2 = at + pts[pts.size() - 1]
		var dir: Vector2 = (pts[pts.size() - 1] - pts[pts.size() - 2]).normalized()
		if dir.length_squared() > 0.0:
			var back: Vector2 = -dir * 9.0
			var side: Vector2 = Vector2(-dir.y, dir.x) * 4.5
			draw_line(tip, tip + back + side, line_color, 2.2, true)
			draw_line(tip, tip + back - side, line_color, 2.2, true)

	var name_text: String = tr(String(row.id).replace("_", " "))
	var kind_color: Color = TERROR_COLOR if terror_rites.has(row.id) else GIFT_COLOR
	var kind_text: String = tr("terror") if terror_rites.has(row.id) else tr("gift")
	if not known:
		kind_color = LOCKED_COLOR
		kind_text = tr("not yours yet")

	var tx: float = at.x + TEXT_LEFT
	draw_string(_font, Vector2(tx, at.y + 18.0), name_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 17, KNOWN_COLOR if known else LOCKED_COLOR)
	draw_string(_font, Vector2(tx, at.y + 36.0), kind_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, kind_color)
	draw_multiline_string(_font, Vector2(tx, at.y + 54.0), tr(row.desc),
		HORIZONTAL_ALIGNMENT_LEFT, panel_width - tx - PAD, 13, 3,
		Color(0.78, 0.80, 0.86) if known else LOCKED_COLOR)
