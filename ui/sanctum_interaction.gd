extends Node3D
class_name SanctumInteraction
## Package T — the diegetic interaction layer for one Sanctum +
## InteriorDressing pair: no Control-node HUD panel, just proximity to real
## 3D geometry driving two small `Label3D` prompts and one keypress
## (`ui_accept` — Godot's built-in default action: Enter/Space/Kp Enter.
## Deliberately NOT a new custom InputMap action: project.godot is
## foundation-owned per docs/systems/OWNERSHIP.md and package T may not
## edit it).
##
## Two interactables, both read from real public API, never re-derived:
##
##  - "at the altar" (a devotion/faith_fraction/relics readout) is
##    `Sanctum.offering_area_entered`/`offering_area_exited`
##    (world/sanctum/sanctum.gd:144-148) — the EXISTING
##    `WorshipYard/Altar/OfferingTrigger` Area3D other systems already use
##    to detect "something is standing at the altar." This script adds no
##    collision shape of its own for the altar.
##  - "at the repair point" (attempt a repair) is
##    `InteriorDressing.repair_area_entered`/`repair_area_exited`
##    (world/sanctum_interior/interior_dressing.gd) — this package's own
##    interior-only Area3D, since Sanctum's hollow interior box ships with
##    no fixtures at all (docs/systems/sanctum.md "For package T").
##
## Repair attempts call `InteriorDressing.attempt_repair()`, which always
## calls the real `Sanctum.repair()` — this script never reimplements the
## offering-debt mercy lock; it only reads `Sanctum.can_repair()` to grey
## out the prompt text ahead of time, exactly per sanctum.md's ask
## ("package T's UI [should] grey out a repair action instead of letting
## the click silently no-op").

@export var sanctum_path: NodePath
@export var interior_dressing_path: NodePath

@onready var _altar_label: Label3D = $AltarPromptLabel
@onready var _repair_label: Label3D = $RepairPromptLabel

var _sanctum: Sanctum
var _dressing: InteriorDressing
var _at_altar := false
var _at_repair := false

func _ready() -> void:
	_sanctum = get_node_or_null(sanctum_path) as Sanctum
	_dressing = get_node_or_null(interior_dressing_path) as InteriorDressing
	_altar_label.visible = false
	_repair_label.visible = false
	if _sanctum:
		_sanctum.offering_area_entered.connect(_on_altar_entered)
		_sanctum.offering_area_exited.connect(_on_altar_exited)
		_sanctum.mercy_blocked.connect(_on_mercy_blocked)
		_sanctum.sanctum_damaged.connect(_on_sanctum_damaged)
		_sanctum.sanctum_repaired.connect(_on_sanctum_repaired)
		_sanctum.sanctum_destroyed.connect(_on_sanctum_destroyed)
		_position_altar_label()
	if _dressing:
		_dressing.repair_area_entered.connect(_on_repair_entered)
		_dressing.repair_area_exited.connect(_on_repair_exited)
		_dressing.repair_attempted.connect(_on_repair_attempted)
		_position_repair_label()

func _process(_delta: float) -> void:
	if _at_altar:
		_refresh_altar_label()
	if _at_repair:
		_refresh_repair_label()

func _unhandled_input(event: InputEvent) -> void:
	if _at_repair and _dressing and event.is_action_pressed(&"ui_accept"):
		_dressing.attempt_repair()

func _position_altar_label() -> void:
	var altar := _sanctum.get_node_or_null("WorshipYard/Altar") as Node3D
	if altar:
		_altar_label.global_position = altar.global_position + Vector3(0, 1.7, 0)

func _position_repair_label() -> void:
	_repair_label.global_position = _dressing.global_position + Vector3(0, 2.0, 0)

func _on_altar_entered(_body: Node3D) -> void:
	_at_altar = true
	_altar_label.visible = true
	_refresh_altar_label()

func _on_altar_exited(_body: Node3D) -> void:
	_at_altar = false
	_altar_label.visible = false

func _on_repair_entered(_body: Node3D) -> void:
	_at_repair = true
	_repair_label.visible = true
	_refresh_repair_label()

func _on_repair_exited(_body: Node3D) -> void:
	_at_repair = false
	_repair_label.visible = false

## Devotion/faith_fraction readout — core/game_state.gd's own documented
## fields (Village.devotion, Village.faith_fraction) plus
## GameState.relics_held, never a second copy of that state.
func _refresh_altar_label() -> void:
	if _sanctum == null:
		return
	var v := GameState.get_village(_sanctum.village_id)
	if v == null:
		_altar_label.text = "..."
		return
	_altar_label.text = "%s\ndevotion %.1f   faith %d%%\nrelics held: %d" % [
		v.display_name, v.devotion, int(round(v.faith_fraction * 100.0)), GameState.relics_held.size()
	]

func _refresh_repair_label() -> void:
	if _sanctum == null:
		return
	if _sanctum.can_repair():
		_repair_label.modulate = Color.WHITE
		_repair_label.text = "Press Enter: repair the Sanctum (hp %d%%)" % int(round(_sanctum.hp_fraction() * 100.0))
	else:
		_repair_label.modulate = Color(0.55, 0.55, 0.55, 1.0) # greyed out, per sanctum.md's ask
		_repair_label.text = "Repair refused — %s (%ds remaining)" % [
			Sacrifice.taboo_name_for(_sanctum.village_id),
			int(ceil(Sacrifice.offering_debt_seconds_remaining(_sanctum.village_id))),
		]

func _on_mercy_blocked(_village_id: StringName, _reason: StringName) -> void:
	if _at_repair:
		_refresh_repair_label()

func _on_sanctum_damaged(_village_id: StringName, _new_hp: float, _max_hp: float) -> void:
	_refresh_if_visible()

func _on_sanctum_repaired(_village_id: StringName, _new_hp: float, _max_hp: float) -> void:
	_refresh_if_visible()

func _on_sanctum_destroyed(_village_id: StringName) -> void:
	_refresh_if_visible()

func _refresh_if_visible() -> void:
	if _at_repair:
		_refresh_repair_label()
	if _at_altar:
		_refresh_altar_label()

func _on_repair_attempted(_village_id: StringName, success: bool, reason: StringName) -> void:
	if success:
		_repair_label.text = "Repaired."
	elif reason == &"mercy_blocked":
		_refresh_repair_label()
