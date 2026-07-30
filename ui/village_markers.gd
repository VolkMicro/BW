extends Node3D
class_name VillageMarkers
## A floating name and state over every village.
##
## ---------------------------------------------------------------------------
## WHY
## ---------------------------------------------------------------------------
## The island carries fifteen villages. Which one is yours, which one Louhi
## holds, which one is out of food and which one is nearly convinced existed
## only as a number in a one-line objective readout, and as a colour on a
## Sanctum roof you have to fly down to see. From god view — the view the game
## is played from — fifteen identical clusters of huts is not a board a player
## can read, and a board you cannot read is not one you can play.
##
## Each marker says the village's name, who holds it, and the one thing about
## it that most wants the player's attention right now.
##
## ---------------------------------------------------------------------------
## WHY Label3D AND NOT A SCREEN-SPACE OVERLAY
## ---------------------------------------------------------------------------
## A 2D overlay would need a world-to-screen projection per village per frame,
## its own occlusion rules, and its own scaling curve. `Label3D` with
## `billboard` and `fixed_size` already is that: the engine bills it toward
## the camera, keeps its pixel height constant at any distance, and hides it
## behind terrain for free. Fifteen of them is fifteen small draw calls, which
## on this budget is nothing next to what they buy.

## Metres above the village's ground the label floats. High enough that the
## second line clears the hillside behind it — the labels depth-test against
## the terrain on purpose, so a caption too low gets its bottom half eaten by
## the slope the village stands on.
@export var height_above_ground: float = 24.0
## Beyond this the labels switch off entirely. At full zoom-out fifteen
## captions is a wall of text over the island rather than information.
@export var visible_distance: float = 900.0
## How often the captions re-read the world, in seconds. These change on the
## scale of a shortage, not of a frame.
@export var refresh_interval: float = 0.7

const COLOR_MINE := Color(0.72, 0.90, 0.72)
const COLOR_THEIRS := Color(0.92, 0.58, 0.55)
const COLOR_NEUTRAL := Color(0.88, 0.88, 0.84)
const COLOR_WARNING := Color(0.96, 0.82, 0.45)
## Deliberately desaturated rather than alarming: a tired village is not in
## trouble, it is just not listening for a minute.
const COLOR_TIRED := Color(0.62, 0.64, 0.72)

## Store level at or below which a village is called short. Matches
## god_view.gd's NEED_WARNING_LEVEL — the HUD and the labels must not disagree
## about which villages are in trouble.
const NEED_WARNING_LEVEL := 12.0

var _labels: Dictionary = {}   # village_id -> Label3D
var _accum: float = 0.0
var _camera: Camera3D = null


## Built by the scene owner once every village is registered and has its final
## position — the same _ready() ordering problem as VillagerCrowd, for the
## same reason: children run before parents.
func build(terrain: Node) -> void:
	for child in get_children():
		child.queue_free()
	_labels.clear()

	for value in GameState.villages.values():
		var v: Village = value
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.fixed_size = true
		# Landed between two failures, both photographed: 44pt at 0.0009 piled
		# fifteen captions into an unreadable heap across the island — the
		# problem this was built to solve, in a bigger font — and 30pt at
		# 0.00034 was too small to read at the altitude the game is played
		# from. A marker has to be legible without becoming the view.
		label.pixel_size = 0.00055
		label.font_size = 34
		label.outline_size = 10
		label.modulate = COLOR_NEUTRAL
		label.outline_modulate = Color(0.03, 0.03, 0.05, 0.9)
		# Draw through terrain would let a village on the far side of a ridge
		# show through it, which reads as a bug rather than as information.
		label.no_depth_test = false
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var ground: float = terrain.sample_height(v.position_on_island) if terrain != null else 0.0
		label.position = Vector3(v.position_on_island.x,
			ground + height_above_ground, v.position_on_island.y)
		add_child(label)
		_labels[v.id] = label

	_refresh()


func _process(delta: float) -> void:
	if _labels.is_empty():
		return
	_accum += delta
	if _accum < refresh_interval:
		return
	_accum = 0.0
	_refresh()


func _refresh() -> void:
	if _camera == null or not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_3d()
	var eye: Vector3 = _camera.global_position if _camera != null else Vector3.ZERO

	for village_id in _labels:
		var v: Village = GameState.get_village(village_id)
		var label: Label3D = _labels[village_id]
		if v == null or label == null:
			continue
		label.visible = _camera == null or eye.distance_to(label.global_position) <= visible_distance
		if not label.visible:
			continue
		label.text = _caption(v)
		label.modulate = _tint(v)


## Below this, a village has heard so much of one kind of rite that the next
## one is worth almost nothing. Reach's fatigue rises 0.28 per use and decays
## over about 65 seconds, so three casts in a row take a village to ~0.16
## effectiveness — and nothing on screen said so.
const TIRED_EFFECTIVENESS := 0.45

## Name, then the one fact that most wants attention. Ordered by how much it
## matters, and only ONE line of state is shown: fifteen villages each
## reciting three numbers is the unreadable board this is meant to fix.
func _caption(v: Village) -> String:
	if v.loyal_to_rival:
		var grip: float = Reclaim.grip_of(v)
		return "%s\nPohjola's — her grip %d%%" % [v.display_name, int(round(grip * 100.0))]
	if v.is_fully_converted():
		return "%s\nyours" % v.display_name
	# FATIGUE, ABOVE EVERYTHING ELSE THAT IS NOT TERMINAL.
	#
	# This is the game's central rhythm and it was completely invisible.
	# Simulated against the shipped constants: a player who casts at one
	# village every three seconds needs 115 rites to convert it, and one who
	# waits twenty seconds between casts needs SEVEN. Fatigue is what makes
	# the whole island the play space instead of one village — and a player
	# who cannot see it just experiences the game quietly ignoring them.
	var tired: float = minf(Reach.effectiveness(v.id, &"help"),
		Reach.effectiveness(v.id, &"terror"))
	if tired < TIRED_EFFECTIVENESS:
		return "%s\nheard enough for now — %d%% yours" % [
			v.display_name, int(round(v.faith_fraction * 100.0))]
	if Stockpile.get_amount(v, &"food") <= NEED_WARNING_LEVEL:
		return "%s\nhungry — %d%% yours" % [v.display_name, int(round(v.faith_fraction * 100.0))]
	if Stockpile.get_amount(v, &"wood") <= NEED_WARNING_LEVEL:
		return "%s\nno firewood — %d%% yours" % [v.display_name, int(round(v.faith_fraction * 100.0))]
	return "%s\n%d%% yours" % [v.display_name, int(round(v.faith_fraction * 100.0))]


func _tint(v: Village) -> Color:
	if v.loyal_to_rival:
		return COLOR_THEIRS
	if v.is_fully_converted():
		return COLOR_MINE
	if minf(Reach.effectiveness(v.id, &"help"), Reach.effectiveness(v.id, &"terror")) < TIRED_EFFECTIVENESS:
		return COLOR_TIRED
	if Stockpile.get_amount(v, &"food") <= NEED_WARNING_LEVEL \
			or Stockpile.get_amount(v, &"wood") <= NEED_WARNING_LEVEL:
		return COLOR_WARNING
	# Between neutral and yours, so a village being won visibly warms up.
	return COLOR_NEUTRAL.lerp(COLOR_MINE, clampf(v.faith_fraction, 0.0, 1.0))
