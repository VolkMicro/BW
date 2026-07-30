extends CanvasLayer
class_name VillagePanel
## Look at one village properly, and tell it what to work on.
##
## ---------------------------------------------------------------------------
## WHY
## ---------------------------------------------------------------------------
## The markers over each village say one thing about it, chosen by priority,
## because fifteen captions each reciting three numbers is unreadable from the
## air. That is right for the board and wrong for the one settlement the
## player has decided to care about — for that one you want the whole ledger:
## how many people, what they are all doing, what is in the stores, how much
## of it believes in you, and what the god's standing orders are.
##
## ---------------------------------------------------------------------------
## ORDERS ARE QUOTAS, NOT ASSIGNMENTS
## ---------------------------------------------------------------------------
## The arrows set how many people the god WANTS on a job.
## `VillagerCrowd.set_quota` then weights that job up until the village has
## that many. Nobody is pinned: a starving village still sends people to eat,
## a storm still drives everyone indoors, and a burning Sanctum still pulls
## hands onto the roof. See the note on the crowd's side for why hard
## assignment would mean fighting the entire needs-driven decision loop, or
## switching it off.
##
## Consequently the numbers you set are a target, and the numbers you see are
## reality. They disagree, often, and that disagreement IS the information:
## six ordered and two working means the village cannot spare four.

signal closed

const JOBS := [
	{"job": 1, "key": "Fishing"},        # VillagerCrowd.Job.FISHING
	{"job": 2, "key": "Fields"},         # FIELD
	{"job": 3, "key": "Woodcutting"},    # WOODCUTTING
	{"job": 6, "key": "Hunting"},        # HUNTING
	{"job": 4, "key": "Building"},       # BUILDING
	{"job": 5, "key": "At home"},        # FAMILY
]

var village_id: StringName = &""

var _crowd: VillagerCrowd = null
var _panel: PanelContainer
var _title: Label
var _summary: Label
var _stores: Label
var _rows: Array = []          # {job, count: Label, quota: Label}
var _refresh_accum: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	layer = 12
	_build()
	visible = false


func open_for(id: StringName, crowd: VillagerCrowd) -> void:
	village_id = id
	_crowd = crowd
	visible = true
	_refresh()


func close() -> void:
	visible = false
	closed.emit()


func _process(delta: float) -> void:
	if not visible:
		return
	# Twice a second. These numbers move on the scale of a villager changing
	# their mind, and rebuilding a dozen labels every frame to watch that is
	# work nobody can see.
	_refresh_accum += delta
	if _refresh_accum < 0.5:
		return
	_refresh_accum = 0.0
	_refresh()


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.offset_right = -24.0
	add_child(_panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	_panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.custom_minimum_size = Vector2(380, 0)
	margin.add_child(box)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	box.add_child(_title)

	_summary = Label.new()
	_summary.add_theme_font_size_override("font_size", 14)
	_summary.modulate = Color(0.78, 0.80, 0.86)
	box.add_child(_summary)

	_stores = Label.new()
	_stores.add_theme_font_size_override("font_size", 14)
	box.add_child(_stores)

	box.add_child(HSeparator.new())

	var header := Label.new()
	header.text = tr("Work — ordered / actually doing it")
	header.add_theme_font_size_override("font_size", 13)
	header.modulate = Color(0.68, 0.70, 0.77)
	box.add_child(header)

	for entry in JOBS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		box.add_child(row)

		var name_label := Label.new()
		name_label.text = tr(entry.key)
		name_label.custom_minimum_size = Vector2(150, 0)
		row.add_child(name_label)

		var minus := Button.new()
		minus.text = "−"
		minus.custom_minimum_size = Vector2(34, 30)
		row.add_child(minus)

		var quota := Label.new()
		quota.custom_minimum_size = Vector2(34, 0)
		quota.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(quota)

		var plus := Button.new()
		plus.text = "+"
		plus.custom_minimum_size = Vector2(34, 30)
		row.add_child(plus)

		var count := Label.new()
		count.custom_minimum_size = Vector2(80, 0)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(count)

		var job_id: int = entry.job
		minus.pressed.connect(func() -> void: _nudge(job_id, -1))
		plus.pressed.connect(func() -> void: _nudge(job_id, 1))
		_rows.append({"job": job_id, "count": count, "quota": quota})

	box.add_child(HSeparator.new())
	var clear := Button.new()
	clear.text = tr("Let them decide")
	clear.custom_minimum_size = Vector2(0, 34)
	clear.pressed.connect(func() -> void:
		if _crowd != null:
			_crowd.clear_quotas(village_id)
		_refresh())
	box.add_child(clear)

	var close_button := Button.new()
	close_button.text = tr("Close")
	close_button.custom_minimum_size = Vector2(0, 34)
	close_button.pressed.connect(close)
	box.add_child(close_button)


func _nudge(job: int, by: int) -> void:
	if _crowd == null:
		return
	var wanted: int = _crowd.get_quota(village_id, job) + by
	# Cannot order more people than the village has. An order that can never
	# be met would sit there pulling forever and reading as a bug.
	_crowd.set_quota(village_id, job,
		clampi(wanted, 0, _crowd.village_population(village_id)))
	_refresh()


func _refresh() -> void:
	var v: Village = GameState.get_village(village_id)
	if v == null:
		close()
		return
	_title.text = v.display_name
	_summary.text = tr("%d people · %d%% believe in you") % [
		v.population, int(round(v.faith_fraction * 100.0))]
	_stores.text = tr("Food %d/%d · Wood %d/%d · Stone %d/%d") % [
		int(Stockpile.get_amount(v, &"food")), int(Stockpile.capacity(v, &"food")),
		int(Stockpile.get_amount(v, &"wood")), int(Stockpile.capacity(v, &"wood")),
		int(Stockpile.get_amount(v, &"stone")), int(Stockpile.capacity(v, &"stone"))]

	for row in _rows:
		var job: int = row.job
		var wanted: int = _crowd.get_quota(village_id, job) if _crowd != null else 0
		var have: int = _crowd.count_job(village_id, job) if _crowd != null else 0
		(row.quota as Label).text = "—" if wanted <= 0 else str(wanted)
		(row.count as Label).text = str(have)
		# Amber when the village cannot meet an order — the disagreement is
		# the information, so it has to be visible at a glance rather than
		# something the player works out by comparing two numbers.
		(row.count as Label).modulate = Color(0.96, 0.82, 0.45) if wanted > have \
			else Color(0.86, 0.90, 0.98)
