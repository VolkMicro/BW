class_name SigilCaster
extends Node3D
## Component: attach as a child of (or near) the Hand once package E lands
## `actors/hand/`. Records one gesture stroke, recognizes it against
## `SigilTemplates` via `UnistrokeRecognizer`, and on a confident match
## emits `rite_cast`. Any system can `connect()` to that signal without
## depending on how the stroke was physically drawn.
##
## Two input sources feed the same 2D stroke buffer, documented explicitly
## per the brief:
##
## 1. Mouse-drag (the default, working end-to-end today): holding the
##    existing `hand_sigil_draw` input action (mapped in project.godot to
##    the right mouse button) and dragging records raw viewport-space mouse
##    positions directly as the stroke's points.
## 2. Hand-tip-driven (for package E to wire in once the Hand exists): call
##    `begin_stroke()` / `add_point_3d(hand_tip_world_position)` once per
##    frame while its own "drawing" input is held, then `end_stroke()`. Each
##    3D point is unprojected through the current Camera3D into the same
##    viewport-space the mouse path uses (`Camera3D.unproject_position`),
##    so both sources are recognized identically — the recognizer never
##    sees anything but flat 2D points.
##
## Recognition is intentionally forgiving ("распознавание снисходительное
## и волшебное" — the brief's own phrase): `score_threshold` defaults to
## 0.75 on the $1 recognizer's 0..1 normalized score, well below "strict".

signal rite_cast(rite_id: StringName, confidence: float)
signal stroke_started()
## Fires on every completed stroke attempt, matched or not, so a debug HUD
## or the Two Voices can react even to failed casts.
signal stroke_finished(matched: bool, rite_id: StringName, confidence: float)

@export var enabled: bool = true
@export var input_action: StringName = &"hand_sigil_draw"
@export_range(0.0, 1.0, 0.01) var score_threshold: float = 0.75
@export var min_points_required: int = 6
@export var min_stroke_span_px: float = 40.0 # filters accidental taps/jitter
@export var max_stroke_duration: float = 6.0 # seconds; aborts a stroke left open too long
@export var min_sample_spacing_px: float = 2.0 # drop near-duplicate points while drawing

## Visual feedback: draws the in-progress stroke as a fading 2D line so the
## gesture reads as "ink in the air" rather than invisible input. Purely
## cosmetic polish scoped to this package (systems/sigils/); it does not
## touch any other package's UI.
@export var show_trail: bool = true
@export var trail_width: float = 4.0
@export var trail_fade_time: float = 0.35

var _recognizer: UnistrokeRecognizer
var _points: Array[Vector2] = []
var _drawing: bool = false
var _stroke_time: float = 0.0

var _trail_layer: CanvasLayer
var _trail_line: Line2D

func _ready() -> void:
	_recognizer = UnistrokeRecognizer.new(SigilTemplates.get_raw_templates())
	if show_trail:
		_setup_trail()

func _setup_trail() -> void:
	_trail_layer = CanvasLayer.new()
	_trail_layer.layer = 50
	add_child(_trail_layer)
	_trail_line = Line2D.new()
	_trail_line.width = trail_width
	_trail_line.default_color = Color(1.0, 0.92, 0.65, 0.9)
	_trail_line.joint_mode = Line2D.LINE_JOINT_ROUND
	_trail_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_trail_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	_trail_layer.add_child(_trail_line)

func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event.is_action_pressed(input_action):
		begin_stroke()
		get_viewport().set_input_as_handled()
	elif event.is_action_released(input_action):
		end_stroke()
		get_viewport().set_input_as_handled()
	elif _drawing and event is InputEventMouseMotion:
		add_point(event.position)

func _process(delta: float) -> void:
	if _drawing:
		_stroke_time += delta
		if _stroke_time > max_stroke_duration:
			_abort_stroke()

## Starts recording a new stroke, discarding anything buffered before it.
func begin_stroke() -> void:
	_points.clear()
	_drawing = true
	_stroke_time = 0.0
	if _trail_line:
		_trail_line.clear_points()
		_trail_line.modulate.a = 1.0
	stroke_started.emit()

## Feeds one viewport-space point directly. This is what the mouse path
## calls internally; a bespoke drawing surface (a UI canvas, a controller
## trackpad) could call it too.
func add_point(viewport_point: Vector2) -> void:
	if not _drawing:
		return
	if _points.is_empty() or _points.back().distance_to(viewport_point) > min_sample_spacing_px:
		_points.append(viewport_point)
		if _trail_line:
			_trail_line.add_point(viewport_point)

## Feeds a 3D world-space point (the Hand's fingertip, projected onto
## whatever drawing plane package E's Hand uses) by unprojecting it through
## `camera` (defaults to the viewport's current Camera3D) into the same
## viewport-space the mouse path shares.
func add_point_3d(world_pos: Vector3, camera: Camera3D = null) -> void:
	if not _drawing:
		return
	var cam := camera if camera != null else get_viewport().get_camera_3d()
	if cam == null:
		return
	add_point(cam.unproject_position(world_pos))

## Ends the stroke and runs recognition. Emits `stroke_finished` always,
## and `rite_cast` only when the score clears `score_threshold`.
func end_stroke() -> void:
	if not _drawing:
		return
	_drawing = false
	_fade_trail()
	_try_recognize()

func _abort_stroke() -> void:
	_drawing = false
	_points.clear()
	_fade_trail()

func _fade_trail() -> void:
	if _trail_line == null:
		return
	var tw := create_tween()
	tw.tween_property(_trail_line, "modulate:a", 0.0, trail_fade_time)
	tw.tween_callback(_trail_line.clear_points)

func _try_recognize() -> void:
	var points := _points
	_points = []
	if points.size() < min_points_required:
		return
	if _stroke_span(points) < min_stroke_span_px:
		return

	var result := _recognizer.recognize(points)
	var rite_id: StringName = result.get("rite_id", &"")
	var score: float = result.get("score", 0.0)
	var matched := rite_id != &"" and score >= score_threshold

	stroke_finished.emit(matched, rite_id, score)
	if matched:
		rite_cast.emit(rite_id, score)
		Voices.react(&"sigil_recognized", {"rite_id": rite_id, "confidence": score})
	else:
		Voices.react(&"sigil_rejected", {"best_guess": rite_id, "confidence": score})

static func _stroke_span(points: Array[Vector2]) -> float:
	var min_x: float = points[0].x
	var max_x: float = points[0].x
	var min_y: float = points[0].y
	var max_y: float = points[0].y
	for p in points:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)
	return maxf(max_x - min_x, max_y - min_y)
