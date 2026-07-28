extends Node3D
class_name InteriorDressing
## Package T — the Sanctum's interior dressing: a simple stone idol on a
## pedestal, meant to be instanced as a child of a Sanctum instance's
## `InteriorAnchor` (Marker3D, Sanctum-local `(0, 0.6, -1.5)` — see
## world/sanctum/sanctum.gd:38-50 and docs/systems/sanctum.md "For package
## T"). Sanctum's own interior shell ships with no fixtures at all; this is
## the fixture.
##
## Two independent, live reactions, both driven by real signals/state, never
## polled or re-derived from scratch each frame:
##
## 1. CULTURE SKIN — mirrors world/sanctum/sanctum.gd's own
##    `_duplicate_materials()` / `_apply_culture_skin()` pattern exactly
##    (sanctum.gd:85-131): duplicate template materials once per instance so
##    multiple Sanctum/InteriorDressing pairs never share a live Material,
##    read `color_primary`/`color_accent` off
##    `GameState.cultures[village.culture_id]`, fall back to the template's
##    shipped color if the village/culture isn't registered yet, and
##    re-apply on `GameState.village_registered`. Deliberately the *same*
##    mechanism, not a second one, per the brief's own instruction.
##
## 2. NAKLON + HP REACTIVE GLOW — the idol's emission color lerps between a
##    mercy color and a cruelty color off `Naklon.unit()` (core/naklon.gd),
##    updated live via `Naklon.naklon_changed` (no polling), and the glow's
##    *energy* is scaled by the owning Sanctum's `hp_fraction()` (read via
##    `sanctum_damaged`/`sanctum_repaired`/`sanctum_destroyed` — never by
##    re-reading `GameState.villages` directly), mirroring
##    `Sanctum._refresh_visual_from_hp()`'s scorch-mix idea (sanctum.gd:273-
##    277): the idol dims as the building takes damage, but never goes
##    fully dark (`MIN_GLOW_FRACTION`) — it reads as "an idol nobody's
##    tending," not a blackout.
##
## This uses a plain `StandardMaterial3D` + direct signal listening — the
## same pattern `sanctum.gd` already uses for its own altar glow — rather
## than `shaders/naklon_shader_driver.gd`'s global-shader-uniform approach.
## That driver exists for *shader*-side consumers; a `.gdshader`/material
## resource is package D's territory (`shaders/`, `materials/` per
## docs/systems/OWNERSHIP.md), and a per-instance script-side material lerp
## is both simpler and consistent with how the sibling package (I) already
## does the exact same kind of thing on this exact same building.

## Fired when this Sanctum's mercy-repair action is attempted from this
## idol's RepairPoint (see below). `reason` is `&""` on success,
## `&"mercy_blocked"` if `Sanctum.can_repair()` was false, `&"no_sanctum"`
## if `sanctum_path` never resolved.
signal repair_attempted(village_id: StringName, success: bool, reason: StringName)
signal repair_area_entered(body: Node3D)
signal repair_area_exited(body: Node3D)

## Defaults to the InteriorAnchor's own parent-of-parent when instanced
## directly under `Sanctum/InteriorAnchor` per the doc'd hookup; override if
## a scene instances this somewhere else.
@export var sanctum_path: NodePath = NodePath("../..")

const MERCY_COLOR := Color(0.55, 0.78, 0.95)
const CRUELTY_COLOR := Color(0.85, 0.16, 0.12)
const IDOL_GLOW_AT_FULL_HP := 0.85
## Never fully dark, even at 0 hp — matches sanctum.gd's own
## MAX_SCORCH_MIX < 1.0 reasoning ("a burned building," not a silhouette).
const MIN_GLOW_FRACTION := 0.15
const REPAIR_AMOUNT_PER_ATTEMPT := 15.0

@onready var _pedestal: CSGCylinder3D = $Pedestal
@onready var _idol_column: CSGCylinder3D = $IdolColumn
@onready var _idol_head: CSGSphere3D = $IdolHead
@onready var _repair_area: Area3D = $RepairPoint

var _pedestal_mat: StandardMaterial3D
var _idol_mat: StandardMaterial3D
var _sanctum: Sanctum
var _hp_fraction: float = 1.0

func _ready() -> void:
	_sanctum = get_node_or_null(sanctum_path) as Sanctum
	_duplicate_materials()
	if not GameState.village_registered.is_connected(_on_village_registered):
		GameState.village_registered.connect(_on_village_registered)
	if not Naklon.naklon_changed.is_connected(_on_naklon_changed):
		Naklon.naklon_changed.connect(_on_naklon_changed)
	if _sanctum:
		if not _sanctum.sanctum_damaged.is_connected(_on_sanctum_damaged):
			_sanctum.sanctum_damaged.connect(_on_sanctum_damaged)
		if not _sanctum.sanctum_repaired.is_connected(_on_sanctum_repaired):
			_sanctum.sanctum_repaired.connect(_on_sanctum_repaired)
		if not _sanctum.sanctum_destroyed.is_connected(_on_sanctum_destroyed):
			_sanctum.sanctum_destroyed.connect(_on_sanctum_destroyed)
		_hp_fraction = _sanctum.hp_fraction()
	if not _repair_area.body_entered.is_connected(_on_repair_entered):
		_repair_area.body_entered.connect(_on_repair_entered)
	if not _repair_area.body_exited.is_connected(_on_repair_exited):
		_repair_area.body_exited.connect(_on_repair_exited)
	_apply_culture_skin()
	_refresh_glow()

## Same "duplicate template materials once per instance" reasoning as
## sanctum.gd:85-102 — the head and column share one live material so both
## glow together, but each InteriorDressing instance gets its own copy.
func _duplicate_materials() -> void:
	_pedestal_mat = (_pedestal.material as StandardMaterial3D).duplicate() as StandardMaterial3D
	_idol_mat = (_idol_column.material as StandardMaterial3D).duplicate() as StandardMaterial3D
	_pedestal.material = _pedestal_mat
	_idol_column.material = _idol_mat
	_idol_head.material = _idol_mat

func _get_village() -> Village:
	if _sanctum == null:
		return null
	return GameState.get_village(_sanctum.village_id)

func _get_culture() -> Culture:
	var v := _get_village()
	if v == null:
		return null
	return GameState.cultures.get(v.culture_id, null)

## Mirrors Sanctum._apply_culture_skin() (sanctum.gd:117-131): safe to call
## before the Village is registered (keeps the template's shipped color),
## re-applied on GameState.village_registered.
func _apply_culture_skin() -> void:
	var culture := _get_culture()
	if culture == null:
		return
	_pedestal_mat.albedo_color = culture.color_primary.darkened(0.25)
	_idol_mat.albedo_color = culture.color_accent

func _on_village_registered(v: Village) -> void:
	if _sanctum == null or v.id != _sanctum.village_id:
		return
	_apply_culture_skin()
	_refresh_glow()

func _on_naklon_changed(_old_value: float, _new_value: float) -> void:
	_refresh_glow()

func _on_sanctum_damaged(_village_id: StringName, _new_hp: float, _max_hp: float) -> void:
	_hp_fraction = _sanctum.hp_fraction()
	_refresh_glow()

func _on_sanctum_repaired(_village_id: StringName, _new_hp: float, _max_hp: float) -> void:
	_hp_fraction = _sanctum.hp_fraction()
	_refresh_glow()

func _on_sanctum_destroyed(_village_id: StringName) -> void:
	_hp_fraction = 0.0
	_refresh_glow()

func _refresh_glow() -> void:
	var tint := MERCY_COLOR.lerp(CRUELTY_COLOR, Naklon.unit())
	_idol_mat.emission_enabled = true
	_idol_mat.emission = tint
	var hp_mult := lerpf(MIN_GLOW_FRACTION, 1.0, _hp_fraction)
	_idol_mat.emission_energy_multiplier = IDOL_GLOW_AT_FULL_HP * hp_mult

func _on_repair_entered(body: Node3D) -> void:
	repair_area_entered.emit(body)

func _on_repair_exited(body: Node3D) -> void:
	repair_area_exited.emit(body)

## Read-only: for a UI to grey out its own repair prompt BEFORE the player
## commits to pressing anything (docs/systems/sanctum.md: "can_repair() ...
## exposed for package T's UI to grey out a repair action instead of
## letting the click silently no-op"). Forwards to Sanctum.can_repair() —
## never reimplements the offering-debt lock.
func can_repair() -> bool:
	return _sanctum != null and _sanctum.can_repair()

## Always calls the REAL Sanctum.repair() (so Sanctum's own
## `mercy_blocked`/`sanctum_repaired` signals and Voices reaction fire for
## real, exactly as if any other caller had asked) — this method only adds
## a synchronous, UI-friendly success/reason readout on top, via
## `can_repair()` checked immediately before the call.
func attempt_repair() -> bool:
	if _sanctum == null:
		repair_attempted.emit(&"", false, &"no_sanctum")
		return false
	var was_possible := _sanctum.can_repair()
	_sanctum.repair(REPAIR_AMOUNT_PER_ATTEMPT)
	var reason: StringName = &"" if was_possible else &"mercy_blocked"
	repair_attempted.emit(_sanctum.village_id, was_possible, reason)
	return was_possible
