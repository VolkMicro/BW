extends Node3D
## Package T — standalone demo/validation harness: registers a real test
## Village (Sankiln, not Fenrayt — proves the culture-skin mirroring isn't
## hard-coded to whichever culture package I's own demo happens to use),
## instances a real Sanctum around it, and shows InteriorDressing
## (world/sanctum_interior/interior_dressing.gd) plus CameraRig/
## SanctumInteraction (ui/) all reacting to that same real GameState/
## Naklon/Sanctum state end to end — following the same standalone-demo
## bootstrap shape as world/sanctum/sanctum_demo.tscn,
## systems/economy/economy_demo.tscn, world/ocean/ocean_demo.tscn.
##
## Run: godot --path . world/sanctum_interior/sanctum_interior_demo.tscn
##
## Controls (see HelpLabel):
##   1 — cut/transition to a god-view overview shot
##   2 — transition into the Sanctum interior framing; arrow keys then walk
##       (clamped to the real interior box)
##   3 — transition to a stand-in duel-arena focus point (`DemoDuelFocus`
##       below) — a deliberate stand-in Marker3D, NOT a dependency on
##       actors/avatar/combat/ (package L); see docs/systems/
##       sanctum_interior_ui.md "Scoped out"
##   Enter — interact (repair, only while standing at the idol's
##       RepairPoint, refused/greyed while offering-debt is active)
##   R — apply 20 damage to the Sanctum (test hook, so hp-reactive dimming
##       is actually reachable without a live combat/Louhi package wired in)
##   T — Sacrifice.offer() a generic (null) target at this Sanctum (test
##       hook — locks the mercy/repair path for 180s exactly like the real
##       mechanic, so "greyed-out repair" is provably real, not asserted)

const DEMO_VILLAGE_ID := &"demo_sankiln_reach"

@onready var _sanctum: Sanctum = $Sanctum
@onready var _camera_rig: CameraRig = $CameraRig
@onready var _god_view_marker: Marker3D = $GodViewMarker
@onready var _duel_focus: Marker3D = $DemoDuelFocus

func _ready() -> void:
	_register_demo_village()
	GameState.relics_held.append(&"demo_relic_of_reeds")
	_camera_rig.frame_god_view(_god_view_marker.global_transform, true)

func _register_demo_village() -> void:
	var v := Village.new()
	v.id = DEMO_VILLAGE_ID
	v.display_name = "Sankiln Reach (demo)"
	v.culture_id = &"sankiln"
	v.position_on_island = Vector2.ZERO
	v.population = 30
	v.children = 6
	v.devotion = 24.0
	v.faith_fraction = 0.6
	v.sanctum_built = true
	v.sanctum_hp = 80.0
	v.sanctum_hp_max = 100.0
	GameState.register_village(v)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.physical_keycode:
		KEY_1:
			_camera_rig.frame_god_view(_god_view_marker.global_transform)
		KEY_2:
			_camera_rig.frame_sanctum_interior(_sanctum)
		KEY_3:
			_camera_rig.frame_duel_arena_focus(_duel_focus)
		KEY_R:
			_sanctum.apply_damage(20.0)
		KEY_T:
			_sanctum.try_offer(null)
