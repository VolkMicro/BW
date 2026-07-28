extends Node3D
class_name Sanctum
## Package I — the Sanctum: a walkable exterior + worship-yard, plus a
## simple hollow interior shell (package T dresses the inside further, see
## docs/systems/sanctum.md "For package T").
##
## The one rule this script exists to enforce: damage to this building and
## damage to the owning Village are the SAME NUMBER. `apply_damage()` and
## `repair()` read and write `GameState.get_village(village_id).sanctum_hp`
## directly — there is no separate "building hp" anywhere. If that number
## hits zero the village's faith is zeroed via
## `GameState.set_faith_fraction(id, 0.0)`, exactly per the brief's
## "урон Санктуму = урон деревне, физически одно и то же."
##
## Re-skins itself per the owning Village's culture (color_primary /
## color_accent from data/cultures/*.tres) at runtime, so one scene file
## serves all four cultures without hand-authoring four buildings.

signal sanctum_damaged(village_id: StringName, new_hp: float, max_hp: float)
signal sanctum_destroyed(village_id: StringName)
signal sanctum_repaired(village_id: StringName, new_hp: float, max_hp: float)
signal mercy_blocked(village_id: StringName, reason: StringName)
signal offering_area_entered(body: Node3D)
signal offering_area_exited(body: Node3D)

## Which Village (GameState.villages key) this physical Sanctum belongs to.
## Set this before or right after instancing — everything else (skin, hp
## sync, devotion hookups) is driven off it.
@export var village_id: StringName = &""

const SCORCH_COLOR := Color(0.05, 0.045, 0.045)
## Fraction of the scorch color mixed in at 0 hp (never fully black — it
## should still read as "a burned building," not a silhouette).
const MAX_SCORCH_MIX := 0.75
## Emission strength of the altar's prayer-glow at full faith_fraction.
const ALTAR_GLOW_AT_FULL_FAITH := 0.9

@onready var _exterior: Node3D = $Exterior
@onready var _walls: CSGCombiner3D = $Exterior/Walls
@onready var _shell: CSGBox3D = $Exterior/Walls/Shell
@onready var _hollow: CSGBox3D = $Exterior/Walls/Hollow
@onready var _door_cut: CSGBox3D = $Exterior/Walls/DoorCut
@onready var _window_l: CSGBox3D = $Exterior/Walls/WindowCutL
@onready var _window_r: CSGBox3D = $Exterior/Walls/WindowCutR
@onready var _roof: CSGCylinder3D = $Exterior/Roof
@onready var _platform: CSGCylinder3D = $WorshipYard/Platform
@onready var _altar: CSGBox3D = $WorshipYard/Altar
@onready var _offering_trigger: Area3D = $WorshipYard/Altar/OfferingTrigger
@onready var _standing_stones: Node3D = $WorshipYard/StandingStones
@onready var _glow_tick: Timer = $GlowTick

var _wall_mat: StandardMaterial3D
var _roof_mat: StandardMaterial3D
var _altar_mat: StandardMaterial3D
var _platform_mat: StandardMaterial3D
var _stone_mat: StandardMaterial3D

var _base_wall_color: Color
var _base_roof_color: Color
var _base_altar_emission: Color

var _destroyed := false
var _default_collision_layer := 1

func _ready() -> void:
	_default_collision_layer = _walls.collision_layer
	_duplicate_materials()
	if not GameState.village_registered.is_connected(_on_village_registered):
		GameState.village_registered.connect(_on_village_registered)
	if not GameState.devotion_changed.is_connected(_on_devotion_changed):
		GameState.devotion_changed.connect(_on_devotion_changed)
	if not _offering_trigger.body_entered.is_connected(_on_offering_area_entered):
		_offering_trigger.body_entered.connect(_on_offering_area_entered)
	if not _offering_trigger.body_exited.is_connected(_on_offering_area_exited):
		_offering_trigger.body_exited.connect(_on_offering_area_exited)
	if not _glow_tick.timeout.is_connected(_refresh_altar_glow):
		_glow_tick.timeout.connect(_refresh_altar_glow)
	_apply_culture_skin()
	_refresh_visual_from_hp()
	_refresh_altar_glow()

## Duplicates every template material once per Sanctum instance so multiple
## villages (each with their own instanced sanctum.tscn) never share a live
## Material and stomp each other's culture skin / damage tint.
func _duplicate_materials() -> void:
	_wall_mat = (_shell.material as StandardMaterial3D).duplicate() as StandardMaterial3D
	_roof_mat = (_roof.material as StandardMaterial3D).duplicate() as StandardMaterial3D
	_altar_mat = (_altar.material as StandardMaterial3D).duplicate() as StandardMaterial3D
	_platform_mat = (_platform.material as StandardMaterial3D).duplicate() as StandardMaterial3D
	var stone_template := (_standing_stones.get_child(0) as MeshInstance3D).get_active_material(0) as StandardMaterial3D
	_stone_mat = stone_template.duplicate() as StandardMaterial3D

	_shell.material = _wall_mat
	_hollow.material = _wall_mat
	_door_cut.material = _wall_mat
	_window_l.material = _wall_mat
	_window_r.material = _wall_mat
	_roof.material = _roof_mat
	_altar.material = _altar_mat
	_platform.material = _platform_mat
	for stone in _standing_stones.get_children():
		(stone as MeshInstance3D).material_override = _stone_mat

func _get_village() -> Village:
	return GameState.get_village(village_id)

func _get_culture() -> Culture:
	var v := _get_village()
	if v == null:
		return null
	return GameState.cultures.get(v.culture_id, null)

## Re-tints exterior/roof/altar/stones from the owning Village's culture.
## Safe to call before the Village is registered (falls back to whatever
## color the template material shipped with) and again later once
## `village_registered` fires with a matching id.
func _apply_culture_skin() -> void:
	var culture := _get_culture()
	if culture == null:
		_base_wall_color = _wall_mat.albedo_color
		_base_roof_color = _roof_mat.albedo_color
		_base_altar_emission = _altar_mat.emission
		return
	_base_wall_color = culture.color_primary
	_base_roof_color = culture.color_accent
	_platform_mat.albedo_color = culture.color_primary.lightened(0.15)
	_stone_mat.albedo_color = culture.color_primary.darkened(0.2)
	_base_altar_emission = culture.color_accent
	_altar_mat.emission = culture.color_accent
	_wall_mat.albedo_color = _base_wall_color
	_roof_mat.albedo_color = _base_roof_color

func _on_village_registered(v: Village) -> void:
	if v.id != village_id:
		return
	_apply_culture_skin()
	_refresh_visual_from_hp()
	_refresh_altar_glow()

func _on_devotion_changed(id: StringName, _amount: float) -> void:
	if id == village_id:
		_refresh_altar_glow()

func _on_offering_area_entered(body: Node3D) -> void:
	offering_area_entered.emit(body)

func _on_offering_area_exited(body: Node3D) -> void:
	offering_area_exited.emit(body)

## --- HP: read/write straight through to the Village resource ---

func current_hp() -> float:
	var v := _get_village()
	if v == null:
		return 0.0
	return v.sanctum_hp

func max_hp() -> float:
	var v := _get_village()
	if v == null:
		return 0.0
	return v.sanctum_hp_max

func hp_fraction() -> float:
	var v := _get_village()
	if v == null or v.sanctum_hp_max <= 0.0:
		return 0.0
	return clampf(v.sanctum_hp / v.sanctum_hp_max, 0.0, 1.0)

## Physically damages the Sanctum by writing directly to the owning
## Village's sanctum_hp — package I's building and package core's Village
## are the same number, per the brief. Emits `sanctum_damaged`, tells the
## Two Voices, updates the scorch visual, and — if this brings hp to 0 —
## zeroes the village's faith_fraction and triggers the fall.
func apply_damage(amount: float, source: Node = null) -> void:
	if amount <= 0.0:
		return
	var v := _get_village()
	if v == null:
		return
	var was_alive := v.sanctum_hp > 0.0
	v.sanctum_hp = maxf(0.0, v.sanctum_hp - amount)
	sanctum_damaged.emit(village_id, v.sanctum_hp, v.sanctum_hp_max)
	Voices.react(&"sanctum_damaged", {
		"village_id": village_id,
		"amount": amount,
		"hp_fraction": hp_fraction(),
		"source": source,
	})
	_refresh_visual_from_hp()
	if was_alive and v.sanctum_hp <= 0.0:
		_on_sanctum_fallen(v)

func _on_sanctum_fallen(v: Village) -> void:
	_destroyed = true
	v.sanctum_built = false
	GameState.set_faith_fraction(village_id, 0.0)
	sanctum_destroyed.emit(village_id)
	Voices.react(&"sanctum_destroyed", {
		"village_id": village_id,
		"culture_id": v.culture_id,
	})
	_play_collapse()

func _play_collapse() -> void:
	_walls.collision_layer = 0
	_roof.collision_layer = 0
	var tween := create_tween()
	tween.tween_property(_exterior, "position:y", _exterior.position.y - 1.6, 1.4).set_trans(Tween.TRANS_CUBIC)
	tween.parallel().tween_property(_exterior, "rotation:z", deg_to_rad(9.0), 1.4)

## Gently restores hp — the "mercy path." Refuses to run while the village
## is under active offering-debt (see Sacrifice.is_offering_debt_active):
## a player cannot buy devotion in blood and immediately paper over the
## damage at the same altar. Real lockout, not just documented — this
## early-returns and emits `mercy_blocked` instead of touching hp.
func repair(amount: float) -> void:
	if amount <= 0.0:
		return
	if _mercy_locked():
		mercy_blocked.emit(village_id, &"offering_debt_active")
		Voices.react(&"mercy_blocked_by_debt", {
			"village_id": village_id,
			"debt_name": Sacrifice.taboo_name_for(village_id),
			"seconds_remaining": Sacrifice.offering_debt_seconds_remaining(village_id),
		})
		return
	var v := _get_village()
	if v == null:
		return
	var was_destroyed := v.sanctum_hp <= 0.0
	v.sanctum_hp = minf(v.sanctum_hp_max, v.sanctum_hp + amount)
	if was_destroyed and v.sanctum_hp > 0.0:
		_on_sanctum_restored(v)
	sanctum_repaired.emit(village_id, v.sanctum_hp, v.sanctum_hp_max)
	_refresh_visual_from_hp()

func _on_sanctum_restored(v: Village) -> void:
	_destroyed = false
	v.sanctum_built = true
	_walls.collision_layer = _default_collision_layer
	_roof.collision_layer = _default_collision_layer
	var tween := create_tween()
	tween.tween_property(_exterior, "position:y", 2.2, 1.0).set_trans(Tween.TRANS_CUBIC)
	tween.parallel().tween_property(_exterior, "rotation:z", 0.0, 1.0)

func can_repair() -> bool:
	return not _mercy_locked()

func _mercy_locked() -> bool:
	return Sacrifice.is_offering_debt_active(village_id)

## Forwards to Sacrifice.offer() using this Sanctum's own village_id, so
## callers (the Hand, campaign events) just need a reference to the
## Sanctum they're standing at rather than threading village_id through
## separately. See sacrifice.gd for how `target` is classified.
##
## Gated on Reach.can_act_at() — a Sanctum whose village has fully fallen
## to the rival (loyal_to_rival, Reach radius 0) and isn't covered by any
## neighboring village's reach refuses the offering outright: a god with
## no purchase here can't be handed anything to begin with.
func try_offer(target: Node) -> void:
	if not Reach.can_act_at(global_position):
		Voices.react(&"offering_out_of_reach", {"village_id": village_id})
		return
	Sacrifice.offer(village_id, target)

func debt_name() -> String:
	return Sacrifice.taboo_name_for(village_id)

## --- Visuals ---

func _refresh_visual_from_hp() -> void:
	var frac := hp_fraction()
	var scorch_mix := (1.0 - frac) * MAX_SCORCH_MIX
	_wall_mat.albedo_color = _base_wall_color.lerp(SCORCH_COLOR, scorch_mix)
	_roof_mat.albedo_color = _base_roof_color.lerp(SCORCH_COLOR, scorch_mix)

func _refresh_altar_glow() -> void:
	var v := _get_village()
	var faith := 0.0
	if v != null:
		faith = v.faith_fraction
	_altar_mat.emission_enabled = faith > 0.01
	_altar_mat.emission = _base_altar_emission
	_altar_mat.emission_energy_multiplier = faith * ALTAR_GLOW_AT_FULL_FAITH
