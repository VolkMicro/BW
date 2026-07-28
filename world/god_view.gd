extends Node3D
## INTEGRATION PASS — the real vertical slice. Every package's system is
## instanced here, together, actually reading and writing the same
## GameState/Naklon/Reach state, rather than each living in its own
## standalone `*_demo.tscn`. See docs/systems/integration.md for the full
## file:line map of what's wired to what and what's still standalone.
##
## Bootstrap shape follows the pattern every existing demo already uses
## (world/sanctum/sanctum_demo.gd, actors/villagers/village_demo.gd,
## world/sanctum_interior/sanctum_interior_demo.gd): register real Village
## resources in GameState from this script's `_ready()`. Node `_ready()`
## order runs children before parents, so by the time THIS `_ready()` runs,
## `$Island` has already generated its mesh/collision (IslandTerrain's own
## `_ready()` → `regenerate()`), every Sanctum instance already ran its own
## `_ready()` (and is listening for `GameState.village_registered`, exactly
## like sanctum_demo.gd's doc comment explains), and CameraRig/LouhiDirector/
## CampaignManager have all already initialized. This script's job is purely
## the cross-system wiring: which Village goes where on the real terrain,
## which villagers belong to which village, and the few explicit signal
## connections other packages' own docs flagged as needing an integration
## pass to make (campaign.md's SigilCaster hook, campaign.md/louhi.md's
## attach_to_louhi).

const VILLAGER_SCENE: PackedScene = preload("res://actors/villagers/villager.tscn")
const CALLING_STONE_SCENE: PackedScene = preload("res://actors/villagers/calling_stone.tscn")
const OTSO_SPECIES: AvatarSpecies = preload("res://actors/avatar/species/otso.tres")

const VILLAGERS_PER_VILLAGE := 5

## One entry per village: which culture, where its container anchor lives in
## the scene tree (X/Z authored on that Node3D in world/god_view.tscn; Y is
## filled in below from the real terrain), and its starting
## devotion/faith/sanctum numbers. Three different cultures, per the brief,
## so the Sanctum/InteriorDressing culture-skin mirroring
## (world/sanctum/sanctum.gd:117-131, world/sanctum_interior/
## interior_dressing.gd:120-125) actually shows three different looks in one
## running frame, not just one culture repeated.
const VILLAGE_DEFS: Array[Dictionary] = [
	{
		"id": &"isle_fenrayt_hollow", "culture": &"fenrayt", "display": "Fenrayt Hollow",
		"anchor": "Villages/FenraytVillage",
		"population": 24, "children": 5, "devotion": 30.0, "faith_fraction": 0.55, "sanctum_hp": 85.0,
	},
	{
		"id": &"isle_sankiln_terrace", "culture": &"sankiln", "display": "Sankiln Terrace",
		"anchor": "Villages/SankilnVillage",
		"population": 20, "children": 4, "devotion": 18.0, "faith_fraction": 0.35, "sanctum_hp": 100.0,
	},
	{
		"id": &"isle_raimborn_shore", "culture": &"raimborn", "display": "Raimborn Shore",
		"anchor": "Villages/RaimbornVillage",
		"population": 18, "children": 3, "devotion": 10.0, "faith_fraction": 0.2, "sanctum_hp": 70.0,
	},
]

## Which village's Sanctum the "2" key / SanctumInteraction prompts walk
## into — arbitrary pick (the first culture), see docs/systems/integration.md.
const WALKABLE_SANCTUM_PATH := "Villages/FenraytVillage/Sanctum"

@onready var _island: IslandTerrain = $Island
@onready var _camera_rig: CameraRig = $CameraRig
@onready var _god_view_marker: Marker3D = $GodViewMarker
@onready var _campaign_manager: CampaignManager = $CampaignManager
@onready var _louhi: LouhiDirector = $LouhiDirector
@onready var _avatar: Avatar = $Avatar
@onready var _hand: Hand = $Hand
@onready var _help_label: Label = $UI/HelpLabel


func _ready() -> void:
	_place_villages_and_villagers()
	_place_avatar_and_hand()
	_wire_campaign_and_louhi()
	_camera_rig.frame_god_view(_god_view_marker.global_transform, true)
	_refresh_help_label()


# ---------------------------------------------------------------------------
# Villages: real Village resources in GameState, real terrain-sampled
# placement, real Sanctums (already instanced in the .tscn, listening for
# this registration), real spawned Villagers, one Calling Stone each.
# ---------------------------------------------------------------------------
func _place_villages_and_villagers() -> void:
	for entry in VILLAGE_DEFS:
		var anchor: Node3D = get_node(entry.anchor)
		var xz := Vector2(anchor.position.x, anchor.position.z)

		var v := Village.new()
		v.id = entry.id
		v.display_name = entry.display
		v.culture_id = entry.culture
		v.position_on_island = xz
		v.population = entry.population
		v.children = entry.children
		v.devotion = entry.devotion
		v.faith_fraction = entry.faith_fraction
		v.sanctum_built = true
		v.sanctum_hp = entry.sanctum_hp
		v.sanctum_hp_max = 100.0
		GameState.register_village(v)

		# Real terrain query (world/terrain/island_terrain.gd:104's own stated
		# use case: "village placement") rather than a guessed constant Y.
		anchor.position.y = _island.sample_height(xz)

		var ring := anchor.get_node_or_null("ReachBorderRing")
		if ring:
			ring.terrain = _island

		_spawn_villagers(entry.id, anchor)
		_spawn_calling_stone(entry.id, anchor)


func _spawn_villagers(village_id: StringName, anchor: Node3D) -> void:
	var root: Node3D = anchor.get_node("Villagers")
	var origin := anchor.global_position
	for i in range(VILLAGERS_PER_VILLAGE):
		var villager: Villager = VILLAGER_SCENE.instantiate()
		villager.village_id = village_id
		# show_debug_label defaults to true (a per-demo debug aid) and the
		# label is fixed_size (constant screen size regardless of camera
		# distance) — from god-view height, 15 villagers' worth of fixed-size
		# status text pile into one unreadable overlapping mess in the middle
		# of frame, and this game is HUD-less/diegetic by design
		# (core/game_state.gd's own doc comment) anyway. Off by default here;
		# still on in village_demo.gd's own close-up standalone demo.
		villager.show_debug_label = false
		# Node3D.global_position can only be read/written once a node is
		# inside the SceneTree (Godot logs "Condition !is_inside_tree()" and
		# silently no-ops otherwise) — add_child() BEFORE setting position,
		# not after.
		root.add_child(villager)
		# Small upward offset so gravity (villager.gd's own CharacterBody3D
		# _physics_process) settles each one onto the real terrain collision
		# rather than spawning them exactly on a possibly-uneven sample.
		villager.global_position = origin + Vector3(randf_range(-3.0, 3.0), 1.0, randf_range(-3.0, 3.0))


func _spawn_calling_stone(village_id: StringName, anchor: Node3D) -> void:
	var stone: CallingStone = CALLING_STONE_SCENE.instantiate()
	stone.village_ids = [village_id]
	anchor.add_child(stone)
	var stone_xz := Vector2(anchor.global_position.x, anchor.global_position.z) + Vector2(4.0, 4.0)
	stone.global_position = Vector3(stone_xz.x, _island.sample_height(stone_xz), stone_xz.y)
	# Preset partway up, same reasoning as village_demo.gd: a screenshot taken
	# moments after load already shows some villagers praying.
	stone.set_target_ratio(0.3)


# ---------------------------------------------------------------------------
# Avatar + Hand: real instances, placed on the real terrain near the
# island's center, away from all three villages.
# ---------------------------------------------------------------------------
func _place_avatar_and_hand() -> void:
	GameState.avatar_species = &"otso"
	_avatar.set_species(OTSO_SPECIES)
	var avatar_xz := Vector2(20.0, 15.0)
	_avatar.position = Vector3(avatar_xz.x, _island.sample_height(avatar_xz) + 1.0, avatar_xz.y)

	var hand_xz := Vector2(18.0, 12.0)
	_hand.position = Vector3(hand_xz.x, _island.sample_height(hand_xz) + 2.0, hand_xz.y)


# ---------------------------------------------------------------------------
# Cross-package signal wiring flagged by the packages' own docs as needing an
# integration pass.
# ---------------------------------------------------------------------------
func _wire_campaign_and_louhi() -> void:
	# campaign.md's own auto-discovery already finds her by name via
	# find_child(); this explicit call is the documented belt-and-suspenders
	# path CampaignManager.attach_to_louhi()'s own doc comment asks an
	# integration pass to use.
	_campaign_manager.attach_to_louhi(_louhi)

	# campaign.md's flagged hook, verbatim: "connect its rite_cast signal to
	# CampaignManager.notify_rite_cast(rite_id) once an instance exists."
	var sigil_caster: SigilCaster = _hand.get_node(^"SigilCaster")
	sigil_caster.rite_cast.connect(
		func(rite_id: StringName, _confidence: float) -> void:
			_campaign_manager.notify_rite_cast(rite_id)
	)


# ---------------------------------------------------------------------------
# Debug/demo controls — same shape as sanctum_interior_demo.gd's own
# god-view/interior camera toggle, extended with a Louhi debug hook.
# ---------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.physical_keycode:
		KEY_1:
			_camera_rig.frame_god_view(_god_view_marker.global_transform)
		KEY_2:
			_camera_rig.frame_sanctum_interior(get_node(WALKABLE_SANCTUM_PATH))
		KEY_L:
			_louhi.debug_force_evaluate()


func _refresh_help_label() -> void:
	if _help_label == null:
		return
	_help_label.text = (
		"1: god view   2: walk into Fenrayt Hollow's Sanctum (arrows to walk once inside, Enter to interact)\n" +
		"God view — arrows: pan camera   scroll: zoom   hold middle-click + drag: orbit\n" +
		"Mouse: aim the Hand   Hold Left Click: grip/throw   Hold Right Click + drag: draw a sigil\n" +
		"[ / ]: nudge Naklon toward Mercy / Cruelty   F / G: praise / chastise the Avatar   L: force Louhi to re-evaluate now"
	)
