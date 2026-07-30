extends Node3D
## INTEGRATION PASS — the real vertical slice. Every package's system is
## instanced here, together, actually reading and writing the same
## GameState/Naklon/Reach state, rather than each living in its own
## standalone `*_demo.tscn`. See docs/systems/integration.md for the full
## file:line map of what's wired to what and what's still standalone.
##
## GAMEPLAY-LOOP PASS (second pass over this file) — the verdict on the
## previous build was, bluntly, "there is no gameplay": every system ran,
## and none of them added up to something a player could win, lose, or even
## understand. This pass does not add a system. It closes the circuit
## between the ones that already exist:
##
##   * rites now DO something (nothing in the shipped scene called
##     Reach.convert_via_help/terror — the only callers in the whole repo
##     were the skirmish demo and the netcode, so a single-player village
##     could never be converted by anything the player did);
##   * the Two Voices are now actually shown (nothing in god_view.tscn was
##     connected to Voices.remark — 474 authored lines went to nobody);
##   * there is a visible objective, driven by CampaignManager's real quest
##     signals and by real village state;
##   * there is a win state, a lose state, and a partial ("divided") state,
##     so the island ends instead of running forever;
##   * the Avatar can actually grow (nothing ever called feed_devotion(),
##     and no context tag was ever open, so praise/chastise were inert).
##
## The full step-by-step trace, including the places the loop is still thin,
## is in docs/systems/gameplay_loop.md.
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
const SANCTUM_SCENE: PackedScene = preload("res://world/sanctum/sanctum.tscn")
const REACH_BORDER_SCRIPT: Script = preload("res://world/terrain/reach_border.gd")

const VILLAGERS_PER_VILLAGE := 5

## How many villages the island carries in total, the three authored ones
## included. The rest are planned onto the real terrain by SettlementPlanner —
## see world/village/settlement_planner.gd for why they are not authored.
const TOTAL_VILLAGES := 15

## Store level at or below which the objective line calls a village short.
## Not zero: by the time a granary is actually empty the village has already
## been losing devotion for a while, and a warning that arrives with the
## damage is not a warning.
const NEED_WARNING_LEVEL := 12.0

## Below this method effectiveness, a rite is announced as "they have heard
## enough of that" rather than as a clean landing. Matches
## ui/village_markers.gd's TIRED_EFFECTIVENESS — the sound and the caption
## must not disagree about whether a village is listening.
const RITE_TIRED_EFFECTIVENESS := 0.45

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

# ---------------------------------------------------------------------------
# THE LOOP — rite → conversion.
#
# `systems/faith/reach.gd` has had convert_via_help()/convert_via_terror()
# since package J landed, with tuned per-method fatigue and per-method
# ceilings. Nothing in the single-player scene ever called either of them
# (verified by grep: the only callers anywhere were
# modes/skirmish/skirmish_scenario_demo.gd:91 and net/network_manager.gd:333,
# neither of which runs here). So the player's only real verb — draw a sigil
# — landed on nothing at all. These two tables are that missing edge.
#
# The `amount` numbers are "how much help/terror", NOT a faith delta —
# reach.gd multiplies by HELP_GAIN_PER_AMOUNT (0.05) / TERROR_GAIN_PER_AMOUNT
# (0.07), then by this village+method's remaining effectiveness (fatigue
# rises 0.28 per use and decays over ~65s), then by the headroom left under
# that method's ceiling.
#
# Tuned, not guessed: with a player casting roughly every five seconds the
# help pool settles at about 27% effectiveness, so a `harvest` (6.0) is worth
# +0.48·(1−faith) on the first cast and about +0.16·(1−faith) at that
# equilibrium. A village starting at 0.20 reaches the tipping point below in
# about fifteen casts; one starting at 0.55 in about nine. Walking away for a
# minute lets the fatigue decay all the way back, which makes patience a real
# and rewarded tactic rather than a phrase in a design doc.
#
# Split by meaning, not by convenience: every rite that GIVES a village
# something is help; every rite that happens TO a village is terror. Terror
# is capped at 0.85 by reach.gd — below the tipping point — so a player who
# only ever throws lightning hits a wall and has to change tactics. The
# objective line says so out loud when it happens (_build_objective_text).
# ---------------------------------------------------------------------------
const HELP_RITE_AMOUNT: Dictionary = {
	&"harvest": 6.0,    # food out of nothing
	&"rain_call": 5.4,  # water for the fields
	&"repair": 5.0,     # mend what broke
	&"ward": 4.4,       # protection, the first rite anyone asks an unproven god for
	&"lumber": 4.4,     # timber
	&"path_gate": 3.8,  # a way through
}
const TERROR_RITE_AMOUNT: Dictionary = {
	&"fire_arrow": 3.6,
	&"lightning": 4.4,
	&"storm": 5.0,
}

## THE ONE PLACE THIS FILE OVERRIDES ANOTHER PACKAGE'S CURVE, stated openly.
##
## `Village.is_fully_converted()` (core/village.gd:36) requires
## `faith_fraction >= 0.999`. `Reach._grow_faith()` (systems/faith/reach.gd:131)
## multiplies every gain by the remaining headroom under the ceiling, so the
## gain is proportional to (1 − faith): the curve is asymptotic and **0.999
## is mathematically unreachable**. Verified by running it, not by reading
## it — 400 consecutive `harvest` rites on one village took it from 0.55 to
## 0.783 and it was still climbing by thousandths. Left alone, the central
## verb of the game can never complete, which is a large part of why the
## previous build had no loop.
##
## The honest fixes were (a) edit reach.gd's curve, which belongs to package J
## and is used by the netcode's mirrored copy too, or (b) decide at the
## integration layer when "convinced enough" becomes "converted". This is (b):
## once nine villagers in ten pray to you, the last one follows the village.
## Deliberately set ABOVE reach.gd's TERROR_CEILING (0.85) so that terror
## alone still cannot take a village — that design rule survives intact.
const CONVERSION_TIPPING_POINT := 0.90

## Fraction of every point of village devotion that also feeds the Avatar.
## Villagers generate devotion for real (actors/villagers/villager.gd:860 for
## prayer, :984 for ambient labour) and GameState.devotion_changed has always
## been emitted — but `Avatar.feed_devotion()` had no caller anywhere outside
## actors/avatar/avatar_demo.gd, so the Avatar could never leave stage "Cub"
## no matter how long the game ran.
##
## Measured, not estimated (two headless runs of this scene, 30 s and 90 s of
## real game time at boot population): the three villages together generate
## roughly 0.9-1.4 devotion/second from prayer and ambient labour, varying
## with how many villagers the Calling Stones currently hold. At 0.35 the
## Avatar is fed ~0.3-0.5/s, putting "Juvenile" (30 devotion, avatar.gd:84)
## at 1-2 minutes and "Grown" (120) at 4-7 minutes — one sitting, not
## instant. The devotion half is only half the gate: both stages also need
## praise (6 and 16 presses of F), which is the player's own input and cannot
## be idled through.
const AVATAR_DEVOTION_SHARE := 0.35

## How often the objective/end-state check runs. Everything in it is a few
## dozen float ops over three villages; at 1 Hz it is not measurable.
const SLOW_TICK_SEC := 1.0

## The opening exchange. Authored HERE rather than in
## systems/voices/voice_lines.gd because that file belongs to package M and
## has no `game_start` trigger to hang these on; they are pushed straight
## into the VoiceLog, which renders them identically to a real
## `Voices.react()` pair. Original writing, checked against
## docs/audit/respect_audit.md rule 6: the joke is on the god's own
## self-importance and Hiisi's appetite, never on belief or believers.
##
## Content requirement from the brief: no tutorial popups — the player is
## told what they are, what the verb is, and what winning means, by the two
## characters who are going to be talking anyway.
const OPENING_EXCHANGE: Array[Dictionary] = [
	{"t": 1.5, "speaker": &"domovoi", "text": "You're awake. Fifteen villages on this rock, and not one of them has settled on what you are."},
	{"t": 6.0, "speaker": &"hiisi", "text": "Two of them have barely heard of you at all. I say we introduce ourselves. Loudly."},
	{"t": 11.0, "speaker": &"domovoi", "text": "Quietly. Hold the right mouse button and drag a shape over a village — that is a rite. They will feel it. Then they will argue about it for a week."},
	{"t": 16.5, "speaker": &"hiisi", "text": "And when all three say your name without being asked, the island is yours and I am going to sleep for a year."},
]

## Two teaching nudges, fired only if the player has not discovered the thing
## on their own. This is the "teach through the Voices and through your own
## mistakes" rule from the brief — a hint that never appears for a player who
## already worked it out.
const NUDGE_CAMERA_AFTER := 14.0
const NUDGE_RITE_AFTER := 26.0

## DIVIDED is retired, not deleted: it is still in the enum so nothing that
## saved or logged the value breaks, but it can no longer be declared. It
## meant "every village is either yours or hers, and the ones that are hers
## can never come back", which stopped being true when
## systems/faith/reclaim.gd landed. See _check_end_state().
enum Ending { NONE, VICTORY, DIVIDED, DEFEAT }

@onready var _island: IslandTerrain = $Island
@onready var _camera_rig: CameraRig = $CameraRig
@onready var _god_view_marker: Marker3D = $GodViewMarker
@onready var _campaign_manager: CampaignManager = $CampaignManager
@onready var _louhi: LouhiDirector = $LouhiDirector
@onready var _avatar: Avatar = $Avatar
@onready var _hand: Hand = $Hand
@onready var _graphics_preset: GraphicsPreset = $GraphicsPreset
@onready var _help_label: Label = $UI/HelpLabel
@onready var _objective_label: Label = $UI/ObjectiveLabel
@onready var _rites_label: RiteGrimoire = $UI/RitesLabel
@onready var _first_lessons: FirstLessons = get_node_or_null(^"FirstLessons")
## Resolved in _ready() from under the Hand — see the wiring pass below.
var _sigil_caster: SigilCaster = null
@onready var _end_card: Label = $UI/EndCard
@onready var _voice_log: VoiceLog = $UI/VoiceLog

var _sanctums: Array[Sanctum] = []
var _last_devotion: Dictionary = {}      # StringName -> float, for the Avatar feed delta
var _ending: int = Ending.NONE
var _first_rite_cast: bool = false
var _camera_moved: bool = false
var _camera_anchor: Vector3 = Vector3.ZERO
var _avatar_context: StringName = &""
var _louhi_note: String = ""
var _objective_cache: String = ""

var _elapsed: float = 0.0
var _slow_tick: float = 0.0
var _opening_index: int = 0
var _nudged_camera: bool = false
var _nudged_rite: bool = false


func _ready() -> void:
	# _build_far_sea() is deliberately NOT called — see its own comment.
	_place_villages_and_villagers()
	_place_avatar_and_hand()
	_wire_campaign_and_louhi()
	_wire_gameplay_loop()
	_camera_rig.frame_god_view(_god_view_marker.global_transform, true)
	_refresh_help_label()
	_refresh_rites_label()
	_refresh_objective()
	# Every child's _ready() has run by now, including CampaignManager's,
	# which activates six quests and therefore emitted twelve boot-time
	# Voices lines nobody should have to read before touching the mouse.
	# Opening the log here drops exactly those and nothing else.
	_voice_log.unmute()


## The Gerstner ocean ($OceanSurface) is a finite plane — it has to be, since
## every vertex carries a baked sea-floor depth for the cheap shoreline (see
## world/ocean/ocean_surface.gd) and its subdivision has to stay fine enough
## near the coast for the waves to read. At god-view height its far edge was
## plainly visible as a straight cut with sky behind it: "you can see the
## edge of the world".
##
## NOT CALLED — kept only as a record of an approach that looked right and
## measurably was not. The standard two-plane trick (detailed wave plane over
## one enormous flat quad) put large dark angular patches all over the island
## the moment it was added: a 9 km, two-triangle quad reaches far past the
## camera's 4 km far plane, and the depth its huge clipped triangles resolve
## to is not reliable enough to lose the depth test against terrain hundreds
## of metres closer. Verified by bisection — the patches appeared in the
## render that introduced this and vanished in the render that removed it,
## with sun shadows disabled in both, which had already ruled out shadow acne.
##
## The horizon is instead fixed by simply enlarging the real wave plane
## (2400 m at 112 subdivisions ~= 21 m quads) so its edge sits deep inside the
## fog. Coarser distant waves are a cheap price; the fog hides them, and the
## near-shore quads are still fine enough to read.
##
## Left in the file rather than deleted because "just add a big flat plane
## under it" is the obvious next idea anyone will have here, and it is worth
## knowing it was tried, why it failed, and how that was established.
const FAR_SEA_EXTENT := 9000.0
const FAR_SEA_DEPTH_OFFSET := -0.6

func _build_far_sea() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(FAR_SEA_EXTENT, FAR_SEA_EXTENT)
	mesh.subdivide_width = 0
	mesh.subdivide_depth = 0

	var mat := StandardMaterial3D.new()
	# Matches world/ocean/ocean.gdshader's own color_deep default so the two
	# planes read as one body of water where they meet.
	mat.albedo_color = Color(0.016, 0.078, 0.153)
	mat.roughness = 0.75
	mat.metallic = 0.0

	var far_sea := MeshInstance3D.new()
	far_sea.name = "FarSea"
	far_sea.mesh = mesh
	far_sea.material_override = mat
	far_sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(far_sea)
	far_sea.global_position = Vector3(0.0, FAR_SEA_DEPTH_OFFSET, 0.0)


# ---------------------------------------------------------------------------
# Villages: real Village resources in GameState, real terrain-sampled
# placement, real Sanctums (already instanced in the .tscn, listening for
# this registration), real spawned Villagers, one Calling Stone each.
# ---------------------------------------------------------------------------
func _place_villages_and_villagers() -> void:
	var taken: Array[Vector2] = []

	# The three authored villages come first. They are authored not because
	# their positions matter — those are still resolved against the terrain —
	# but because they carry scene wiring the generated ones do not: the
	# walkable Sanctum interior, the InteriorDressing, the opening dialogue's
	# named subject. Resolving them first also means the planner spreads the
	# other twelve around them rather than the other way round.
	var reserved: Array[Dictionary] = []
	for entry in VILLAGE_DEFS:
		var anchor: Node3D = get_node(entry.anchor)
		# The authored X/Z is a WISH, not a position. Since the island became a
		# lobed, domain-warped landmass (island_generator.gd's _land_mask) its
		# coastline is different for every seed, so a hard-coded anchor can
		# easily land in the sea or on a cliff. _find_village_site() keeps the
		# authored spot when it is good and otherwise spirals outward for the
		# nearest place a village could actually stand.
		var xz := _find_village_site(Vector2(anchor.position.x, anchor.position.z), taken)
		taken.append(xz)
		var resolved := entry.duplicate()
		resolved["xz"] = xz
		reserved.append(resolved)

	var plan := SettlementPlanner.plan(_island, TOTAL_VILLAGES, _island.island_seed,
		VILLAGE_MIN_SEPARATION, reserved)

	for entry in plan:
		var xz: Vector2 = entry.xz
		# Authored villages already have their anchor in the scene; planned ones
		# get an equivalent one built here.
		var anchor: Node3D = get_node(entry.anchor) if entry.has("anchor") else _build_village_anchor(entry)
		anchor.position.x = xz.x
		anchor.position.z = xz.y

		var v := Village.new()
		v.id = entry.id
		# The three authored villages carry English display names in
		# VILLAGE_DEFS; the twelve planned ones were already localised by
		# SettlementPlanner. Both paths end up translated here.
		v.display_name = tr(entry.display)
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
		_last_devotion[v.id] = v.devotion

		# Real terrain query (world/terrain/island_terrain.gd:104's own stated
		# use case: "village placement") rather than a guessed constant Y.
		anchor.position.y = _island.sample_height(xz)

		var ring := anchor.get_node_or_null("ReachBorderRing")
		if ring:
			ring.terrain = _island

		var sanctum := anchor.get_node_or_null("Sanctum") as Sanctum
		if sanctum:
			_sanctums.append(sanctum)

		# NOTE: individual villager nodes are no longer spawned here. The whole
		# island's population now lives in the VillagerCrowd node as packed
		# arrays drawn by one MultiMesh — see actors/villagers/villager_crowd.gd
		# for why 600 CharacterBody3D villagers is a different program, not a
		# bigger one. The crowd populates itself from GameState after every
		# village has registered, which is why it is kicked off at the END of
		# _place_villages_and_villagers() rather than per village here.
		_spawn_calling_stone(entry.id, anchor)

	# Scatter runs at its own _ready(), which is BEFORE this function — children
	# before parents — so at build time it could only have known the authored
	# wishes, and nothing at all about the twelve planned villages. Rather than
	# scatter grass through fifteen settlements, it now waits: the exclusions go
	# in here, once every village has its final position, and it builds after.
	var scatter := get_node_or_null(^"TerrainScatter")
	if scatter:
		for v_id in GameState.villages:
			var vv: Village = GameState.villages[v_id]
			scatter.add_exclusion(vv.position_on_island, 30.0)
		scatter.rebuild()

	# Every village is registered now, so the crowd can be built. This is the
	# _ready() ordering trap documented in world/sanctum/sanctum_demo.gd:
	# children run their _ready() before their parent, so VillagerCrowd cannot
	# populate itself — at its own _ready() GameState is still empty.
	var crowd := get_node_or_null(^"VillagerCrowd") as VillagerCrowd
	if crowd:
		crowd.populate()
	# Same ordering reason: houses need the villages' final positions, and the
	# temple superstructure needs every Sanctum to have finished its own
	# _ready() (it has, children run first).
	var buildings := get_node_or_null(^"VillageBuildings") as VillageBuildings
	if buildings:
		buildings.build()
	# Same ordering reason again: the markers need every village's final
	# terrain-resolved position to float above the right piece of ground.
	var markers := get_node_or_null(^"VillageMarkers") as VillageMarkers
	if markers:
		markers.build(_island)

	# Phase 3: a village that grows gains people and houses; one that starves
	# loses both. Wired here rather than inside the economy because the crowd
	# and the buildings are scene nodes and systems/economy/ does not know
	# about the scene (docs/systems/OWNERSHIP.md).
	var economy := get_node_or_null(^"VillageEconomy") as VillageEconomy
	if economy and not economy.population_changed.is_connected(_on_population_changed):
		economy.population_changed.connect(_on_population_changed)


## Builds the scene-side half of a planned village: the anchor, its Sanctum,
## its Reach border ring and the container the Calling Stone hangs off.
##
## Deliberately NOT a scene file. A `village.tscn` would have to hard-code a
## village_id, and every planned village has a different one, so instancing it
## would mean instantiating and then overwriting the very thing that makes the
## scene a scene. The three authored villages in world/god_view.tscn stay
## authored because they carry more than this — a walkable interior and its
## dressing — and this must match the parts of them that matter.
func _build_village_anchor(entry: Dictionary) -> Node3D:
	var villages_root: Node3D = get_node(^"Villages")
	var anchor := Node3D.new()
	anchor.name = String(entry.display).to_pascal_case()
	villages_root.add_child(anchor)

	var sanctum := SANCTUM_SCENE.instantiate()
	sanctum.name = "Sanctum"
	sanctum.village_id = entry.id
	anchor.add_child(sanctum)

	var ring := MeshInstance3D.new()
	ring.name = "ReachBorderRing"
	ring.set_script(REACH_BORDER_SCRIPT)
	ring.village_id = entry.id
	anchor.add_child(ring)

	var villagers := Node3D.new()
	villagers.name = "Villagers"
	anchor.add_child(villagers)
	return anchor


func _on_population_changed(village_id: StringName, new_population: int) -> void:
	var crowd := get_node_or_null(^"VillagerCrowd") as VillagerCrowd
	if crowd:
		crowd.set_village_population(village_id, new_population)
	var buildings := get_node_or_null(^"VillageBuildings") as VillageBuildings
	if buildings:
		buildings.queue_rebuild()


## Minimum height a village will settle at — above the surf, not on a beach
## that the shoreline foam is already washing over.
const VILLAGE_MIN_HEIGHT := 3.0
## Villages need reasonably level ground; this is the largest height spread
## tolerated across a site's footprint.
const VILLAGE_MAX_RELIEF := 5.0
## Roughly the Sanctum's worship-yard radius, so "level" is measured over the
## area a village actually occupies rather than at a single point.
const VILLAGE_FOOTPRINT := 11.0
## On a 1200 m island 55 m put fifteen villages shoulder to shoulder in
## whichever corner had the best ground. This is the distance at which two
## settlements read as separate places from the air.
const VILLAGE_MIN_SEPARATION := 105.0

## Returns a spot near `wish` where a village can actually stand: above the
## waterline, level enough, and clear of the villages already placed. Spirals
## outward from the wish, so an authored layout is preserved when the terrain
## allows it and only nudged when it does not.
func _find_village_site(wish: Vector2, taken: Array[Vector2]) -> Vector2:
	if _site_ok(wish, taken):
		return wish
	var half: float = float(_island.size_meters) * 0.5
	# Spiral out in rings. 24 samples per ring is enough to not miss a valley
	# mouth, and the ring step is a little under the footprint so nothing is
	# skipped between rings.
	var radius := 8.0
	while radius < half:
		for i in 24:
			var a := TAU * float(i) / 24.0
			var candidate := wish + Vector2(cos(a), sin(a)) * radius
			if absf(candidate.x) > half or absf(candidate.y) > half:
				continue
			if _site_ok(candidate, taken):
				return candidate
		radius += 9.0
	# Nowhere suitable at all. Return the wish rather than silently teleporting
	# the village to the middle of the map — a village visibly in the surf is a
	# bug someone will notice and fix, a village mysteriously relocated is not.
	push_warning("god_view: no valid village site near %s; leaving it where it was asked for." % wish)
	return wish

func _site_ok(xz: Vector2, taken: Array[Vector2]) -> bool:
	for t in taken:
		if t.distance_to(xz) < VILLAGE_MIN_SEPARATION:
			return false
	var centre: float = _island.sample_height(xz)
	if centre < VILLAGE_MIN_HEIGHT:
		return false
	var lo := centre
	var hi := centre
	for i in 8:
		var a := TAU * float(i) / 8.0
		var h: float = _island.sample_height(xz + Vector2(cos(a), sin(a)) * VILLAGE_FOOTPRINT)
		lo = minf(lo, h)
		hi = maxf(hi, h)
	return (hi - lo) <= VILLAGE_MAX_RELIEF

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
	# Moved (was 20,15 — the empty middle of the island) to just outside
	# Fenrayt Hollow's Reach ring. Reason, stated plainly: `actors/avatar/`
	# implements a full learning model but NO locomotion — avatar.gd's only
	# `_physics_process` applies gravity and nothing else, so the Avatar
	# never walks anywhere on its own. Parked in the middle of nowhere it was
	# permanently in the `explore_new_place` context and praising it taught it
	# about scenery. Standing at a village, praise (F) reinforces
	# `guard_village`, which is a thing a god might actually want a bear to
	# learn. See _update_avatar_context() and docs/systems/gameplay_loop.md.
	var avatar_xz := Vector2(-56.0, -50.0)
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
	_sigil_caster = sigil_caster
	sigil_caster.rite_cast.connect(
		func(rite_id: StringName, _confidence: float) -> void:
			_campaign_manager.notify_rite_cast(rite_id)
	)
	# ...and the gameplay half of the same signal, which nothing owned.
	sigil_caster.rite_cast.connect(_on_rite_cast)


# ---------------------------------------------------------------------------
# THE GAMEPLAY LOOP. Everything below this line is the second pass.
# ---------------------------------------------------------------------------
func _wire_gameplay_loop() -> void:
	GameState.village_converted.connect(_on_village_converted)
	GameState.village_lost.connect(_on_village_lost)
	GameState.devotion_changed.connect(_on_devotion_changed)
	GameState.epithet_earned.connect(_on_epithet_earned)

	_campaign_manager.quest_activated.connect(_on_quest_changed)
	_campaign_manager.quest_completed.connect(_on_quest_changed)
	_campaign_manager.scroll_learned.connect(_on_scroll_learned)

	_louhi.sign_occurred.connect(_on_louhi_sign)
	_louhi.sign_relented.connect(_on_louhi_relented)

	for sanctum in _sanctums:
		sanctum.sanctum_destroyed.connect(_on_sanctum_destroyed)


## One `_process` for the whole loop: a couple of float subtractions and one
## compare per frame in the steady state, everything real behind either the
## 1 Hz slow tick or a one-shot flag. Deliberately not four separate Timers.
func _process(delta: float) -> void:
	_elapsed += delta

	# Opening exchange — a scheduled list, not a chain of awaits, so it can
	# never leave a dangling coroutine if the scene is freed mid-line.
	if _opening_index < OPENING_EXCHANGE.size():
		var beat: Dictionary = OPENING_EXCHANGE[_opening_index]
		if _elapsed >= float(beat["t"]):
			var speaker: StringName = beat["speaker"]
			_voice_log.push_line(speaker, String(beat["text"]))
			_opening_index += 1

	_slow_tick -= delta
	if _slow_tick > 0.0:
		return
	_slow_tick = SLOW_TICK_SEC
	_slow_update()


func _slow_update() -> void:
	_update_camera_discovery()
	_update_avatar_context()
	_update_nudges()
	if _ending == Ending.NONE:
		_check_end_state()
	_refresh_objective()


# --- teaching without popups ------------------------------------------------

func _update_camera_discovery() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if _camera_anchor == Vector3.ZERO:
		_camera_anchor = cam.global_position
		return
	if not _camera_moved and cam.global_position.distance_to(_camera_anchor) > 6.0:
		_camera_moved = true


func _update_nudges() -> void:
	if _ending != Ending.NONE:
		return
	if not _nudged_camera and not _camera_moved and _elapsed > NUDGE_CAMERA_AFTER:
		_nudged_camera = true
		_voice_log.push_line(&"domovoi",
			"You are looking at one corner of your own island. Arrow keys move the eye, the wheel brings it down. Nobody is going to do it for you.")
	if not _nudged_rite and not _first_rite_cast and _elapsed > NUDGE_RITE_AFTER:
		_nudged_rite = true
		_voice_log.push_line(&"hiisi",
			"Still nothing? Right mouse button, drag a circle over a village. A circle. The shape you have been drawing since you were a puddle.")


# --- rites actually doing something -----------------------------------------

## Resolves a recognized sigil into a real conversion act on a real village.
## Target is the village whose Reach circle the Hand is currently over —
## the same circle world/terrain/reach_border.gd is already drawing on the
## ground every frame, so "where can I cast" is a thing the player can see
## rather than a rule they have to be told.
func _on_rite_cast(rite_id: StringName, confidence: float) -> void:
	if _ending != Ending.NONE:
		return
	# The MIDDLE of the shape the player just drew, not the Hand's position.
	# See SigilCaster.last_stroke_centre: the Hand is wherever the mouse
	# stopped, which for a 200-pixel sigil is far outside the 25-35 pixel
	# circle the player was aiming at.
	var world_pos: Vector3 = _ground_under_viewport_point(_sigil_caster.last_stroke_centre)
	var target: Village = _village_in_reach_of(world_pos)

	# CONTESTING A VILLAGE LOUHI HOLDS.
	#
	# _village_in_reach_of() skips those on purpose — Reach's radius for them
	# is 0, which is what her holding them means. Before this they could only
	# be looked at. A rite cast over one now pries at her grip instead of
	# persuading anybody, because nobody there is listening; see
	# systems/faith/reclaim.gd for why grip and faith must not share a number.
	if target == null:
		var taken: Village = Reclaim.contested_village_at(world_pos)
		if taken != null:
			_contest_rite(taken, rite_id, confidence, world_pos)
			return

	if target == null:
		# Refused: the Hand flashes (actors/hand/hand.gd:194) and the Voices
		# explain jurisdiction. This is the single most important teaching
		# moment in the game — it is how a player learns Reach exists.
		_hand.request_refusal_flash(&"rite_out_of_reach")
		MusicDirector.play_rite_outcome(&"rite_refused", world_pos)
		if _first_lessons != null:
			_first_lessons.saw_rite_refused_out_of_reach = true
		var nearest: Village = _nearest_village(world_pos)
		Voices.react(&"offering_out_of_reach", {
			"village_id": nearest.id if nearest != null else &"",
			"kind": "rite",
		})
		return

	if _first_lessons != null:
		_first_lessons.saw_rite_cast = true
	if not _first_rite_cast:
		_first_rite_cast = true
		Voices.react(&"first_rite_cast", {"rite_id": rite_id, "village_id": target.id})

	# A one-shot procedural particle burst from systems/sigils/rite_vfx.gd,
	# which frees itself. This is the only visual confirmation that a rite
	# landed HERE rather than somewhere else.
	RiteVFX.spawn(rite_id, world_pos, self)

	# Confidence never drops below the recognizer's 0.75 threshold, so this
	# is a 0.875..1.0 nudge — a scruffy sigil is worth slightly less, it is
	# not a punishment.
	# Godhood: a god twelve villages deep casts harder than one nobody has
	# heard of. See systems/faith/godhood.gd — this is the player's half of
	# the compounding the endgame needs, mirroring Louhi's shortening clock.
	var quality := (0.5 + 0.5 * clampf(confidence, 0.0, 1.0)) * Godhood.rite_multiplier()
	# Told apart by ear: a rite that landed, and one that landed on a village
	# which has heard enough of that method for now. Read BEFORE the call,
	# because convert_via_* registers the use and moves the fatigue itself.
	var method: StringName = &"terror" if TERROR_RITE_AMOUNT.has(rite_id) else &"help"
	var landed_well: bool = Reach.effectiveness(target.id, method) >= RITE_TIRED_EFFECTIVENESS
	MusicDirector.play_rite_outcome(
		&"rite_landed" if landed_well else &"rite_tired", world_pos)

	if HELP_RITE_AMOUNT.has(rite_id):
		# Fires Voices &"village_helped" and shifts Naklon toward mercy —
		# both already implemented in systems/faith/reach.gd:146-154.
		Reach.convert_via_help(target.id, float(HELP_RITE_AMOUNT[rite_id]) * quality)
		_deliver_rite_goods(target, rite_id, quality)
	elif TERROR_RITE_AMOUNT.has(rite_id):
		Reach.convert_via_terror(target.id, float(TERROR_RITE_AMOUNT[rite_id]) * quality)
		_deliver_rite_harm(target, rite_id, quality)
	# Any other recognized rite id has no conversion meaning; the VFX and the
	# campaign's notify_rite_cast() still fire. There are none today — the
	# two tables cover all nine SigilTemplates ids.

	_maybe_tip_over(target)
	_refresh_objective()


## WHAT A HELP RITE ACTUALLY PUTS IN THE STORE.
##
## `harvest` is called a harvest. Before this it produced no food — it moved a
## faith number and nothing else, which was survivable while nobody ate, and
## became a lie the moment villagers started going hungry and the objective
## line started telling the player to cast it at them. A god who answers a
## famine with a rite named harvest has to actually fill the granary.
##
## The amounts are one workday, not a season: RITE_GOODS values are roughly
## what a village's food workers produce in half a minute, so a rite relieves
## a shortage and buys time to fix the cause. It does not remove the need to
## have people in the fields, which is the thing that makes the village a
## simulation rather than a vending machine.
const RITE_GOODS: Dictionary = {
	&"harvest": {&"food": 42.0},
	&"rain_call": {&"food": 24.0},   # water for the fields, not food in hand
	&"lumber": {&"wood": 38.0},
	&"repair": {&"wood": 14.0},      # timber for the mending, spent on the way
}

func _deliver_rite_goods(v: Village, rite_id: StringName, quality: float) -> void:
	var goods: Dictionary = RITE_GOODS.get(rite_id, {})
	for resource in goods:
		Stockpile.add(v, resource, float(goods[resource]) * quality)


## WHAT A TERROR RITE ACTUALLY DOES TO A PLACE.
##
## The mirror of the harvest problem, and worse, because terror is the half of
## the game that is supposed to feel like a mistake you can make. Throwing
## lightning at a village used to raise a fear number and leave the village
## untouched — no fire, no damage, nothing anyone would have to clean up. A
## god whose worst act has no consequences is not frightening, they are
## ignorable, and the whole Mercy/Cruelty axis rests on the player being able
## to see what cruelty costs.
##
## The costs are deliberately asymmetric with the gifts. A harvest fills a
## granary; lightning burns down part of the roof AND spoils stores, so the
## village you frightened into believing is a poorer village afterwards, and
## the fear you bought has to be paid for by somebody. Reach's terror ceiling
## (0.85) already stops fear alone from converting anyone — this is why that
## rule bites: keep going and there is nothing left worth converting.
const RITE_HARM: Dictionary = {
	&"lightning": {"sanctum": 14.0, "food": -10.0},
	&"fire_arrow": {"sanctum": 9.0, "wood": -18.0},   # timber burns first
	&"storm": {"sanctum": 6.0, "food": -16.0, "wood": -8.0},
}

func _deliver_rite_harm(v: Village, rite_id: StringName, quality: float) -> void:
	var harm: Dictionary = RITE_HARM.get(rite_id, {})
	for key in harm:
		var amount: float = float(harm[key]) * quality
		if key == "sanctum":
			var sanctum := _sanctum_for(v.id)
			if sanctum != null:
				sanctum.apply_damage(amount, self)
			else:
				# No Sanctum node for this village (nothing should be in this
				# state, but a missing node must not silently swallow the
				# damage): take it off the number the Sanctum would have.
				v.sanctum_hp = maxf(0.0, v.sanctum_hp - amount)
		else:
			Stockpile.add(v, StringName(key), amount)
	# A storm is a storm. The weather system already knows how to run one over
	# the island, and a rite that summons weather should summon weather rather
	# than describing it in a Voices line.
	if rite_id == &"storm":
		Weather.summon_storm()


func _sanctum_for(village_id: StringName) -> Sanctum:
	for s in _sanctums:
		if s != null and is_instance_valid(s) and s.village_id == village_id:
			return s
	return null


## One rite cast at a village Louhi holds.
##
## Any rite works, help or terror: prying her loose is not persuasion and does
## not care whether the player is being kind about it. What it costs is
## repetition — nine or ten clean rites while she is busy elsewhere.
func _contest_rite(v: Village, rite_id: StringName, confidence: float, world_pos: Vector3) -> void:
	var quality := (0.5 + 0.5 * clampf(confidence, 0.0, 1.0)) * Godhood.reclaim_multiplier()
	var amount: float = float(HELP_RITE_AMOUNT.get(rite_id,
		TERROR_RITE_AMOUNT.get(rite_id, 4.0)))
	RiteVFX.spawn(rite_id, world_pos, self)
	var result := Reclaim.press(v, amount * quality)
	MusicDirector.play_rite_outcome(
		&"village_reclaimed" if result.released else &"rite_landed", world_pos)
	if not result.released:
		Voices.react(&"village_contested", {
			"village_id": v.id, "village_name": v.display_name,
			"grip": result.grip,
		})
	_refresh_objective()


## Where a viewport point lands on the island.
##
## Uses the terrain's own heightmap by marching the camera ray rather than a
## physics raycast: the ray is cast every time a rite is drawn, the answer has
## to agree with the surface villages were placed on (which is the smoothed,
## eroded grid — see island_generator.sample_smoothed_height), and a physics
## query would also happily hit a villager or a thrown boulder.
func _ground_under_viewport_point(point: Vector2) -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return _hand.get_target_position()
	var origin := cam.project_ray_origin(point)
	var dir := cam.project_ray_normal(point)
	if absf(dir.y) < 0.0001:
		return _hand.get_target_position()

	# Coarse march to find the step that crosses the ground, then bisect. A
	# closed-form solve is impossible against a heightmap, and 64 + 12 samples
	# of a cached array costs nothing on the one frame a rite is cast.
	var t := 0.0
	var step := 12.0
	var last_above := true
	for i in 200:
		var p := origin + dir * t
		var above := p.y > _island.sample_height(Vector2(p.x, p.z))
		if i > 0 and above != last_above:
			var lo := t - step
			var hi := t
			for _b in 12:
				var mid := (lo + hi) * 0.5
				var q := origin + dir * mid
				if q.y > _island.sample_height(Vector2(q.x, q.z)):
					lo = mid
				else:
					hi = mid
			var hit := origin + dir * ((lo + hi) * 0.5)
			return hit
		last_above = above
		t += step
		if t > 6000.0:
			break
	# Never crossed the ground: the player drew over open sea or sky. Fall
	# back to the sea plane so the caller still gets a sane world position and
	# refuses the rite for being out of reach, rather than aiming at the Hand.
	var to_sea := -origin.y / dir.y
	if to_sea > 0.0:
		var sea := origin + dir * to_sea
		return sea
	return _hand.get_target_position()


## See CONVERSION_TIPPING_POINT. Emits through GameState.set_faith_fraction()
## so `village_converted` fires exactly once, through the normal path, and
## every existing listener (CampaignManager's culture quests, the Reach ring,
## the Voices) reacts the way it always would.
func _maybe_tip_over(v: Village) -> void:
	if v.loyal_to_rival or v.is_fully_converted():
		return
	if v.faith_fraction >= CONVERSION_TIPPING_POINT:
		GameState.set_faith_fraction(v.id, 1.0)


func _village_in_reach_of(world_pos: Vector3) -> Village:
	var flat := Vector3(world_pos.x, 0.0, world_pos.z)
	var best: Village = null
	var best_d := INF
	for value in GameState.villages.values():
		var v: Village = value
		if v.loyal_to_rival:
			continue
		var origin := Vector3(v.position_on_island.x, 0.0, v.position_on_island.y)
		var d := origin.distance_to(flat)
		if d <= Reach.radius_for_village(v.id) + Godhood.reach_bonus() and d < best_d:
			best_d = d
			best = v
	return best


func _nearest_village(world_pos: Vector3) -> Village:
	var flat := Vector3(world_pos.x, 0.0, world_pos.z)
	var best: Village = null
	var best_d := INF
	for value in GameState.villages.values():
		var v: Village = value
		var origin := Vector3(v.position_on_island.x, 0.0, v.position_on_island.y)
		var d := origin.distance_to(flat)
		if d < best_d:
			best_d = d
			best = v
	return best


# --- the Avatar actually growing --------------------------------------------

## Every point of devotion a villager prays or works into the village
## stockpile also feeds the Avatar a fraction of itself. This is the missing
## half of "grow the Avatar": praise (F) supplies the praise_count half of
## avatar.gd's GROWTH_STAGES gate, this supplies the devotion half.
func _on_devotion_changed(village_id: StringName, new_amount: float) -> void:
	var last: float = float(_last_devotion.get(village_id, 0.0))
	_last_devotion[village_id] = new_amount
	var gained := new_amount - last
	if gained > 0.0:
		_avatar.feed_devotion(gained * AVATAR_DEVOTION_SHARE)


## Keeps exactly one context tag open on the Avatar at all times, chosen from
## where it actually is. Without this, praise_avatar/chastise_avatar
## (already bound in project.godot, already handled by avatar.gd:299) had no
## tag to reinforce, so pressing F taught the creature nothing — flagged as
## an open gap by docs/systems/integration.md's own "Standalone / inert"
## section. Two tags is deliberately the whole vocabulary here: a real
## behaviour-driven tag set belongs to actors/avatar/, not to this file.
func _update_avatar_context() -> void:
	if not is_instance_valid(_avatar):
		return
	var apos := _avatar.global_position
	var flat := Vector3(apos.x, 0.0, apos.z)
	var near_village := false
	for value in GameState.villages.values():
		var v: Village = value
		if v.loyal_to_rival:
			continue
		var origin := Vector3(v.position_on_island.x, 0.0, v.position_on_island.y)
		if origin.distance_to(flat) <= Reach.radius_for_village(v.id) + 6.0:
			near_village = true
			break
	var want: StringName = &"guard_village" if near_village else &"explore_new_place"
	if want == _avatar_context:
		return
	if _avatar_context != &"":
		_avatar.end_context(_avatar_context)
	_avatar_context = want
	_avatar.begin_context(want)


# --- reacting to the world ---------------------------------------------------

func _on_village_converted(village_id: StringName) -> void:
	# GameState.village_converted has always been emitted (game_state.gd:64)
	# and voice_lines.gd has always had a six-pair pool for it — but nothing
	# in the repo ever called Voices.react(&"village_converted"). This is
	# the payoff line for the game's central verb; it should not be silent.
	Voices.react(&"village_converted", {"village_id": village_id})
	_check_end_state()
	_refresh_objective()


func _on_village_lost(village_id: StringName) -> void:
	var v: Village = GameState.get_village(village_id)
	if v != null:
		_louhi_note = "%s is beyond you now." % v.display_name
	_check_end_state()
	_refresh_objective()


func _on_sanctum_destroyed(village_id: StringName) -> void:
	# sanctum.gd:197 resets that village's faith to zero on destruction —
	# a setback, not a defeat (the village is still there and still
	# convertible). Surfaced so the player knows why the ring shrank.
	var v: Village = GameState.get_village(village_id)
	if v != null:
		_louhi_note = "%s's Sanctum is rubble. Their faith went with it." % v.display_name
	_refresh_objective()


func _on_quest_changed(_quest_id: StringName) -> void:
	_refresh_objective()


func _on_scroll_learned(_rite_id: StringName) -> void:
	_refresh_rites_label()
	_refresh_objective()


func _on_epithet_earned(_epithet: String, _reason: String) -> void:
	_refresh_objective()


func _on_louhi_sign(tier: int, village_id: StringName, description: String) -> void:
	var v: Village = GameState.get_village(village_id)
	var vname: String = v.display_name if v != null else "somewhere"
	_louhi_note = "Louhi, at %s (sign %d): %s" % [vname, tier, description]
	_check_end_state()
	_refresh_objective()


func _on_louhi_relented(village_id: StringName, _from_tier: int) -> void:
	var v: Village = GameState.get_village(village_id)
	if v != null:
		_louhi_note = "Louhi has stopped looking at %s. For now." % v.display_name
	_refresh_objective()


# --- win, lose, and the honest third option ----------------------------------

## A village is out of the game when Pohjola owns it (louhi_director.gd:321)
## or when there is nobody left in it (villager.gd:1040). There is no reclaim
## mechanic anywhere in this codebase — Louhi's own doc calls tier 2 "a
## one-way door" — so this is genuinely terminal for that village.
func _village_is_lost(v: Village) -> bool:
	return v.loyal_to_rival or v.population <= 0


func _check_end_state() -> void:
	if _ending != Ending.NONE:
		return
	var total := 0
	var converted := 0
	var lost := 0
	for value in GameState.villages.values():
		var v: Village = value
		total += 1
		if _village_is_lost(v):
			lost += 1
		elif v.is_fully_converted():
			converted += 1
	if total == 0:
		return
	if lost >= total:
		_declare_ending(Ending.DEFEAT, converted, lost, total)
	elif converted >= total:
		_declare_ending(Ending.VICTORY, converted, lost, total)
	# NO DIVIDED ENDING WHILE ANYTHING IS STILL CONTESTABLE.
	#
	# This used to end the island as DIVIDED the moment every village was
	# either converted or lost, on the reasoning that a lost village "can
	# never be taken back" and grinding at one would be cruel. That was true
	# when it was written and is not true any more —
	# `systems/faith/reclaim.gd` makes every village she holds contestable, so
	# calling the island finished while ten rites would win one back is the
	# game giving up on the player's behalf.
	#
	# What is left is the design's own end state: the island runs until one
	# god holds all of it. A long stalemate is not a bug in that; it is two
	# gods who are evenly matched, and she gets faster every time she wins,
	# so it will not stay even.


func _declare_ending(ending: int, converted: int, lost: int, total: int) -> void:
	_ending = ending
	var title := ""
	var body := ""
	match ending:
		Ending.VICTORY:
			title = tr("THE ISLAND IS YOURS")
			body = tr("All %d villages say your name without being asked for it.") % total
		Ending.DEFEAT:
			title = tr("THE ISLAND IS HERS")
			body = tr("Every village on this rock answers to Louhi. You are still awake. That is the whole of what you are now.")
	var named := tr("Nobody got around to naming you.")
	if not GameState.epithets.is_empty():
		# GameState.epithets IS the player's real scorecard — core/game_state.gd
		# says so in its own doc comment, and until now nothing ever showed it.
		var earned: PackedStringArray = PackedStringArray()
		for e in GameState.epithets:
			earned.append("    " + String(e))
		named = tr("They called you:\n") + "\n".join(earned)
	_end_card.text = tr("%s\n\n%s\n\n%s\n\nNothing further will happen here.") % [title, body, named]
	_end_card.visible = true
	match ending:
		Ending.VICTORY:
			_voice_log.push_line(&"domovoi", "That is the whole island. I would like it on record that the ledger balanced, which has never once happened before.")
			_voice_log.push_line(&"hiisi", "Record it, frame it, eat it. I am going to sleep in the biggest hall on the island and nobody is to wake me.")
		Ending.DEFEAT:
			_voice_log.push_line(&"domovoi", "She did not hurry. That is the part I would like you to sit with.")
			_voice_log.push_line(&"hiisi", "I would make a joke here. I have looked at it from three sides. There isn't one.")
	_refresh_objective()


# --- the objective line ------------------------------------------------------

func _refresh_objective() -> void:
	var text := _build_objective_text()
	# Only assign when it actually changed: a Label re-lays-out its text on
	# every assignment, and this runs once a second forever.
	if text == _objective_cache:
		return
	_objective_cache = text
	_objective_label.text = text


func _build_objective_text() -> String:
	if _ending != Ending.NONE:
		return tr("This island is finished.")

	var total := 0
	var mine := 0
	var lost := 0
	var target: Village = null
	var best_faith := -1.0
	for value in GameState.villages.values():
		var v: Village = value
		total += 1
		if _village_is_lost(v):
			lost += 1
			continue
		if v.is_fully_converted():
			mine += 1
			continue
		# Nearest to done first: finishing a village is worth more than
		# starting one, and it keeps the objective from flapping.
		if v.faith_fraction > best_faith:
			best_faith = v.faith_fraction
			target = v

	var lines: PackedStringArray = PackedStringArray()
	var header := tr("Yours: %d of %d villages.") % [mine, total]
	if lost > 0:
		header += tr("   Lost to Pohjola: %d.") % lost
	lines.append(header)

	if target != null:
		var pct := int(round(target.faith_fraction * 100.0))
		if target.faith_fraction >= Reach.TERROR_CEILING - 0.005:
			lines.append(tr("Now — %s (%d%%): fear has carried them as far as fear goes. The rest has to be given: harvest, rain, mending, a ward.") % [target.display_name, pct])
		else:
			lines.append(tr("Now — %s (%d%% theirs): hold right mouse and drag a rite over it.") % [target.display_name, pct])

	# WHAT THE ISLAND NEEDS, in words the player can act on.
	#
	# The villagers now genuinely eat and burn firewood (see
	# systems/economy/village_economy.gd), and a village going short loses
	# devotion for it — but from 300 m up that is invisible, and an invisible
	# simulation is the same as no simulation. This names the shortage and,
	# because each shortage has a rite that answers it, doubles as the hint:
	# hungry wants `harvest`, cold wants `lumber`.
	var hungry: int = 0
	var cold: int = 0
	for value in GameState.villages.values():
		var v: Village = value
		if _village_is_lost(v):
			continue
		if Stockpile.get_amount(v, &"food") <= NEED_WARNING_LEVEL:
			hungry += 1
		if Stockpile.get_amount(v, &"wood") <= NEED_WARNING_LEVEL:
			cold += 1
	lines.append(tr("You are %s.") % tr(Godhood.title()))
	if lost > 0:
		lines.append(tr("Pohjola holds %d. A rite cast over one pries her grip loose — it takes several.") % lost)
	if hungry > 0 or cold > 0:
		var parts: PackedStringArray = PackedStringArray()
		if hungry > 0:
			parts.append(tr("%d hungry (harvest)") % hungry)
		if cold > 0:
			parts.append(tr("%d out of firewood (lumber)") % cold)
		lines.append(tr("On the island: ") + ", ".join(parts) + ".")

	var active_title := _current_quest_title(target)
	if active_title != "":
		lines.append(tr("Spoken of: \"%s\"") % active_title)

	if _louhi_note != "":
		lines.append(_louhi_note)

	return "\n".join(lines)


## Prefer a Louhi quest (she is the clock), then a quest about the village
## the player is actually being pointed at, then whatever else is live.
func _current_quest_title(target: Village) -> String:
	var active: Array[StringName] = _campaign_manager.get_active_quests()
	if active.is_empty():
		return ""
	var fallback := ""
	var culture_match := ""
	for quest_id in active:
		var q: Quest = _campaign_manager.get_quest_def(quest_id)
		if q == null:
			continue
		if String(quest_id).begins_with("q_louhi"):
			return q.title
		if target != null and q.culture_id == target.culture_id:
			culture_match = q.title
		if fallback == "":
			fallback = q.title
	return culture_match if culture_match != "" else fallback


# --- the rites the player has actually been taught ---------------------------

## Discovery problem, stated plainly: a gesture game in which the player is
## never told what to draw is not a game. `campaign/scroll_book.gd` already
## tracks which rites are known and `systems/sigils/sigil_templates.gd`
## already carries a one-sentence English description of every shape — they
## had simply never been shown to anybody. Toggled with 3, hidden by default,
## because a permanently-open list is a HUD and this game does not have one.
## The panel draws the actual stroke for every rite now (ui/rite_grimoire.gd),
## so this only has to tell it which ids are terror — the panel deliberately
## does not know this file's rite tables.
func _refresh_rites_label() -> void:
	_rites_label.terror_rites = TERROR_RITE_AMOUNT
	_rites_label.refresh()


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
		KEY_3:
			_rites_label.visible = not _rites_label.visible
			if _rites_label.visible and _first_lessons != null:
				_first_lessons.saw_rite_panel = true
		KEY_P:
			# environment/graphics_preset.gd: LOW -> MEDIUM -> HIGH -> LOW.
			_graphics_preset.cycle()
			_refresh_help_label()
		KEY_BRACKETLEFT:
			# The old help text promised these two keys and nothing in this
			# file implemented them — only actors/hand/hand_demo.gd did.
			Naklon.shift(-0.1, 1.0)
		KEY_BRACKETRIGHT:
			Naklon.shift(0.1, 1.0)
		KEY_L:
			_louhi.debug_force_evaluate()


func _refresh_help_label() -> void:
	if _help_label == null:
		return
	var preset_text: String = GraphicsPreset.preset_name(_graphics_preset.current()) if _graphics_preset != null else "Low"
	# The walkable Sanctum's village is substituted rather than spelled out:
	# the line used to name Fenrayt Hollow in English prose, which a
	# translation would have had to hard-code in every language.
	var walkable := GameState.get_village(&"isle_fenrayt_hollow")
	var walkable_name: String = walkable.display_name if walkable != null else "Fenrayt Hollow"
	_help_label.text = (
		tr("Mouse: aim the Hand   Hold Left Click: grip/throw   Hold Right Click + drag: draw a rite over a village") + "\n" +
		tr("Arrows: pan   Scroll: zoom   Middle-drag: orbit   3: rites you know (shapes)   Esc: pause / save / leave   1: god view   2: walk into %s's Sanctum (Enter to interact)") % walkable_name + "\n" +
		tr("[ / ]: nudge Naklon toward Mercy / Cruelty   F / G: praise / chastise the Avatar   L: force Louhi to re-evaluate now   P: graphics preset (now: %s)") % tr(preset_text)
	)
