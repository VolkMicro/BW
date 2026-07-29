extends Node3D
class_name WildlifeManager
## PACKAGE W (wildlife) — the one node that owns the island's animals.
##
## Drop ONE of these into a world scene, point `terrain_path` at the
## `IslandTerrain`, and it spawns and drives the whole population. See
## docs/systems/wildlife.md for exact instancing instructions.
##
## Signals other systems can consume:
##   creature_spawned(creature: WildCreature)
##   creature_alarmed(creature: WildCreature, threat_position: Vector3)
##   prey_killed(prey_species: StringName, predator_species: StringName, world_position: Vector3)
##
## ---------------------------------------------------------------------------
## WHY A MANAGER AT ALL (this is the performance design, not architecture
## taste). Target hardware: Dell Latitude 5411, integrated Intel graphics
## only, ~5-6 fps baseline — see docs/systems/performance_notes.md.
##
## The naive version of "animals flee the Avatar" has every creature search
## the scene tree for the Avatar and the Hand, every frame: N tree walks +
## N group queries + N distance calls per frame. Instead:
##
##   - This node rebuilds ONE shared threat cache (`god_threats`,
##     `predator_points`) every `cache_interval` seconds (default 0.5s) for
##     the entire population, and computes each herd's centroid in the same
##     single O(N) pass. A creature then reads at most ~5 cached Vector3s on
##     its own staggered think tick and does squared-distance compares only.
##   - Node references (Avatar, Hand, terrain) are resolved ONCE and only
##     re-resolved if they go invalid — no per-frame `get_first_node_in_group`,
##     no per-frame `find_child`.
##   - The predator's prey scan runs here, on demand, only while a predator
##     is actually hungry, over a per-species list this node already
##     maintains — not a group query over the whole tree.
##
## Total per-frame cost of this node itself: one `_process` callback doing
## three float subtractions. The O(N) cache rebuild happens twice a second.

signal creature_spawned(creature: WildCreature)
signal creature_alarmed(creature: WildCreature, threat_position: Vector3)
signal prey_killed(prey_species: StringName, predator_species: StringName, world_position: Vector3)

const SPECIES_DIR := "res://actors/wildlife/species/"
const CREATURE_SCENE_PATH := "res://actors/wildlife/wild_creature.tscn"
const SPAWN_DROP_HEIGHT := 0.8      # matches the villager spawn convention: drop, let gravity settle
const SPAWN_TRIES := 24
const ALARM_VOICE_COOLDOWN := 12.0

# --- Wiring -----------------------------------------------------------------
## The IslandTerrain to place animals on. If left empty this node looks for
## an IslandTerrain among the current scene's descendants once, then falls
## back to a flat plane at `fallback_ground_y` (which is what the standalone
## demo and any flat test scene get).
@export var terrain_path: NodePath = ^""
@export var fallback_ground_y: float = 0.0
## Optional explicit paths. Both are auto-discovered if left empty: the
## Avatar via its own &"avatar" group (actors/avatar/avatar.gd:144), the Hand
## by a one-time typed search (hand.gd registers no group, so there is
## nothing cheaper available without editing package E's file).
@export var avatar_path: NodePath = ^""
@export var hand_path: NodePath = ^""
## Anything else that should scare animals (a Louhi manifestation, a future
## player proxy). Positions are read from these every cache rebuild.
@export var extra_threat_paths: Array[NodePath] = []

# --- Population --------------------------------------------------------------
@export var spawn_on_ready: bool = true
## Centre of the spawn disc in WORLD XZ. Defaults to this node's own origin.
@export var spawn_center_xz: Vector2 = Vector2.ZERO
@export var spawn_radius: float = 110.0
@export var rimefleece_count: int = 12
@export var snagbill_count: int = 6
@export var thawjaw_count: int = 1
## Rimefleeces spawn in tight clumps rather than uniformly, so a herd starts
## as a herd instead of taking two minutes to find itself.
@export var herd_clump_radius: float = 12.0
@export var show_debug_labels: bool = false

# --- Naklon reaction ---------------------------------------------------------
## Under a cruel god animals are scarcer and spook from further away; under a
## merciful god they are calmer and slightly more numerous. Costs nothing per
## frame — population is scaled once at spawn, and the skittishness scale is
## pushed to creatures only when Naklon.naklon_changed actually fires.
@export var naklon_affects_wildlife: bool = true
@export var fear_scale_at_mercy: float = 0.75
@export var fear_scale_at_cruelty: float = 1.4
@export var population_scale_at_mercy: float = 1.2
@export var population_scale_at_cruelty: float = 0.7

# --- Upkeep ------------------------------------------------------------------
@export var cache_interval: float = 0.5
## A hunted-out island stays interesting: one grazer wanders back in from the
## coast every `respawn_interval` seconds, up to the original count. Set false
## for a scenario where extinction should be permanent.
@export var respawn_prey: bool = true
@export var respawn_interval: float = 90.0

# --- Public read-only shared cache (creatures read these directly) -----------
var god_threats: PackedVector3Array = PackedVector3Array()
var predator_points: PackedVector3Array = PackedVector3Array()

var _terrain: IslandTerrain = null
var _avatar: Node3D = null
var _hand: Node3D = null
var _extra: Array[Node3D] = []
var _hand_search_done: bool = false

var _alive: Array[WildCreature] = []
var _by_species: Dictionary = {}       # StringName -> Array[WildCreature]
var _centroids: Dictionary = {}        # StringName -> Vector3
var _target_counts: Dictionary = {}    # StringName -> int (post-Naklon spawn target)

var _cache_timer: float = 0.0
var _respawn_timer: float = 0.0
var _last_alarm_voice: float = -1000.0
var _creature_scene: PackedScene = null


func _ready() -> void:
	# load(), not preload(): wild_creature.gd names WildlifeManager as a type,
	# so preloading its scene here would be a parse-time cycle. ResourceLoader
	# caches by path, so this costs one lookup, once.
	_creature_scene = load(CREATURE_SCENE_PATH)
	_resolve_terrain()
	for p in extra_threat_paths:
		var n := get_node_or_null(p) as Node3D
		if n:
			_extra.append(n)
	if spawn_center_xz == Vector2.ZERO:
		spawn_center_xz = Vector2(global_position.x, global_position.z)
	if naklon_affects_wildlife and not Naklon.naklon_changed.is_connected(_on_naklon_changed):
		Naklon.naklon_changed.connect(_on_naklon_changed)
	_respawn_timer = respawn_interval
	if spawn_on_ready:
		# Deferred, not immediate: a parent's own _ready() runs AFTER its
		# children's, so anything connecting to `creature_spawned` from the
		# scene that owns this node would miss every single spawn if we
		# populated inline here. Verified by an actual headless run, not
		# assumed — the first version of this file emitted 19 spawns to
		# nobody.
		populate.call_deferred()
	_rebuild_cache()


# ---------------------------------------------------------------------------
# Spawning
# ---------------------------------------------------------------------------
## Spawns the configured population. Safe to call again later (it adds to
## whatever is already alive) — nothing here despawns existing creatures.
func populate() -> void:
	_spawn_species(&"rimefleece", rimefleece_count, true)
	_spawn_species(&"snagbill", snagbill_count, false)
	_spawn_species(&"thawjaw", thawjaw_count, false)


func _spawn_species(sid: StringName, base_count: int, clumped: bool) -> void:
	var species: WildlifeSpecies = load(SPECIES_DIR + String(sid) + ".tres") as WildlifeSpecies
	if species == null:
		push_warning("WildlifeManager: no species resource for '%s'." % sid)
		return
	var count := _naklon_scaled_count(base_count)
	_target_counts[sid] = count
	if count <= 0:
		return

	var clump_center := Vector3.ZERO
	var have_clump := false
	for i in range(count):
		var spot := Vector3.ZERO
		if clumped and have_clump and randf() < 0.8:
			spot = _find_spawn_point(species, Vector2(clump_center.x, clump_center.z), herd_clump_radius)
		else:
			spot = _find_spawn_point(species, spawn_center_xz, spawn_radius)
		if spot == Vector3.INF:
			continue
		if clumped and not have_clump:
			clump_center = spot
			have_clump = true
		var creature := _instance_creature(species, spot)
		if creature:
			creature_spawned.emit(creature)


func _instance_creature(species: WildlifeSpecies, spot: Vector3) -> WildCreature:
	var creature: WildCreature = _creature_scene.instantiate()
	creature.species = species
	creature.manager = self
	creature.show_debug_label = show_debug_labels
	# add_child FIRST, then position. Setting global_position on a node that
	# is not yet in the SceneTree is silently discarded — the exact bug
	# docs/systems/integration.md records for the villager spawner.
	add_child(creature)
	creature.place_at(spot)
	creature.set_fear_scale(_current_fear_scale())
	creature.killed.connect(_on_creature_killed)
	_register(creature)
	return creature


## Rejection sampling for a dry, high-enough spot. Costs at most SPAWN_TRIES
## bilinear height lookups per animal, once, at spawn — no raycasts.
## Returns Vector3.INF if it could not find anywhere in SPAWN_TRIES attempts.
func _find_spawn_point(species: WildlifeSpecies, center: Vector2, radius: float) -> Vector3:
	for _i in range(SPAWN_TRIES):
		var angle := randf() * TAU
		# sqrt() keeps the sample uniform over the disc instead of clustering
		# everything at the centre.
		var r := sqrt(randf()) * radius
		var xz := center + Vector2(cos(angle) * r, sin(angle) * r)
		var h := terrain_height(xz)
		if h >= species.min_ground_height:
			return Vector3(xz.x, h + SPAWN_DROP_HEIGHT, xz.y)
	return Vector3.INF


func _register(creature: WildCreature) -> void:
	_alive.append(creature)
	var sid := creature.species_id()
	if not _by_species.has(sid):
		var fresh: Array[WildCreature] = []
		_by_species[sid] = fresh
	var bucket: Array[WildCreature] = _by_species[sid]
	bucket.append(creature)


func _unregister(creature: WildCreature) -> void:
	_alive.erase(creature)
	var sid := creature.species_id()
	if _by_species.has(sid):
		var bucket: Array[WildCreature] = _by_species[sid]
		bucket.erase(creature)


# ---------------------------------------------------------------------------
# Terrain queries — a bilinear lookup into an already-built height array
# (island_generator.gd:265), NOT a physics raycast.
# ---------------------------------------------------------------------------
func terrain_height(world_xz: Vector2) -> float:
	if _terrain and is_instance_valid(_terrain):
		return _terrain.sample_height(world_xz)
	return fallback_ground_y


func is_walkable(world_xz: Vector2, min_height: float) -> bool:
	if _terrain == null or not is_instance_valid(_terrain):
		return true   # flat test scene: everywhere is walkable
	return _terrain.sample_height(world_xz) >= min_height


func _resolve_terrain() -> void:
	if terrain_path != ^"":
		_terrain = get_node_or_null(terrain_path) as IslandTerrain
	if _terrain == null:
		var scene := get_tree().current_scene
		if scene:
			# Type search, not a name search: world/god_view.tscn happens to
			# call its terrain "Island", but nothing guarantees that, and an
			# IslandTerrain is the only thing sample_height() lives on.
			_terrain = _first_terrain_under(scene) as IslandTerrain


func _first_terrain_under(node: Node) -> Node:
	for child in node.get_children():
		if child is IslandTerrain:
			return child
		var deeper := _first_terrain_under(child)
		if deeper:
			return deeper
	return null


# ---------------------------------------------------------------------------
# The shared cache. One O(N) pass, twice a second, for the whole population.
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	_cache_timer -= delta
	if _cache_timer <= 0.0:
		_cache_timer = cache_interval
		_rebuild_cache()
	if respawn_prey:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_respawn_timer = respawn_interval
			_try_respawn()


func _rebuild_cache() -> void:
	god_threats.clear()
	predator_points.clear()

	if _avatar == null or not is_instance_valid(_avatar):
		_avatar = _resolve_avatar()
	if _avatar:
		god_threats.append(_avatar.global_position)

	if _hand == null or not is_instance_valid(_hand):
		_hand = _resolve_hand()
	if _hand:
		god_threats.append(_hand.global_position)

	for node in _extra:
		if is_instance_valid(node):
			god_threats.append(node.global_position)

	# One pass over the population: prune the dead, sum per-species positions
	# for the herd centroids, and collect predator positions. Everything the
	# creatures need for a whole half-second is produced right here.
	var sums: Dictionary = {}
	var counts: Dictionary = {}
	for i in range(_alive.size() - 1, -1, -1):
		var c: WildCreature = _alive[i]
		# Prune here rather than anywhere hot: this is the one place the whole
		# population is already being walked once per cache rebuild.
		if not is_instance_valid(c):
			_alive.remove_at(i)
			continue
		if not c.is_alive() or c.species == null:
			_unregister(c)
			continue
		var sid: StringName = c.species_id()
		var pos: Vector3 = c.global_position
		if c.species.is_predator:
			predator_points.append(pos)
		if c.species.is_herd:
			var running: Vector3 = sums.get(sid, Vector3.ZERO)
			sums[sid] = running + pos
			counts[sid] = int(counts.get(sid, 0)) + 1

	_centroids.clear()
	for key in counts:
		var herd_id: StringName = key
		var n: int = counts[herd_id]
		if n > 0:
			var total: Vector3 = sums[herd_id]
			_centroids[herd_id] = total / float(n)


func _resolve_avatar() -> Node3D:
	if avatar_path != ^"":
		var explicit := get_node_or_null(avatar_path) as Node3D
		if explicit:
			return explicit
	return get_tree().get_first_node_in_group(&"avatar") as Node3D


func _resolve_hand() -> Node3D:
	if hand_path != ^"":
		var explicit := get_node_or_null(hand_path) as Node3D
		if explicit:
			return explicit
	# hand.gd registers no group and this package may not edit it (see
	# docs/systems/OWNERSHIP.md), so a one-time typed search is the cheapest
	# honest option. Done once, not per frame.
	if _hand_search_done:
		return null
	_hand_search_done = true
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var found := scene.find_child("Hand", true, false)
	if found is Hand:
		return found as Node3D
	return null


# ---------------------------------------------------------------------------
# Queries the creatures make
# ---------------------------------------------------------------------------
func herd_centroid(sid: StringName, fallback: Vector3) -> Vector3:
	if _centroids.has(sid):
		var c: Vector3 = _centroids[sid]
		return c
	return fallback


## Nearest living animal of a species this predator actually hunts, within
## its hunt_radius. Only called while a predator is hungry and targetless
## (~once every 5s per predator, at most), and only iterates the species
## buckets that predator cares about — not the whole scene tree.
func find_prey_for(predator: WildCreature) -> WildCreature:
	if predator == null or predator.species == null:
		return null
	var wanted := predator.species.hunts
	if wanted.is_empty():
		return null
	var here := predator.global_position
	var limit_sq := predator.species.hunt_radius * predator.species.hunt_radius
	var best: WildCreature = null
	var best_d2 := limit_sq
	for name_str in wanted:
		var sid := StringName(name_str)
		if not _by_species.has(sid):
			continue
		var bucket: Array[WildCreature] = _by_species[sid]
		for candidate in bucket:
			if not is_instance_valid(candidate) or not candidate.is_alive():
				continue
			var d := candidate.global_position - here
			d.y = 0.0
			var d2 := d.length_squared()
			if d2 < best_d2:
				best_d2 = d2
				best = candidate
	return best


func living_count(sid: StringName) -> int:
	if not _by_species.has(sid):
		return 0
	var bucket: Array[WildCreature] = _by_species[sid]
	var n := 0
	for c in bucket:
		if is_instance_valid(c) and c.is_alive():
			n += 1
	return n


func total_alive() -> int:
	return _alive.size()


## How many living prey animals are within `radius` of a point.
##
## Added for the villagers' hunting job (actors/villagers/villager_crowd.gd,
## systems/economy/village_economy.gd): a hunt should only feed a village when
## there is actually game on that hillside. Predators are excluded — a village
## hunting party is not going after the thawjaw.
func prey_near(world_xz: Vector2, radius: float) -> int:
	var r2 := radius * radius
	var n := 0
	for c in _alive:
		if not is_instance_valid(c) or not c.is_alive():
			continue
		if c.species != null and not c.species.is_prey:
			continue
		var p: Vector3 = c.global_position
		var dx: float = p.x - world_xz.x
		var dz: float = p.z - world_xz.y
		if dx * dx + dz * dz <= r2:
			n += 1
	return n


## Takes one prey animal near `world_xz` — the villagers' kill. Returns true
## if something was actually taken.
##
## Routed through report_kill() rather than quietly despawning, so a hunted
## animal is the same event as a predated one: the scavengers hear about the
## carcass, the Voices remark, and `prey_killed` fires for anything else
## listening. A village's hunt genuinely thins the herd, and `respawn_prey`
## brings it back over `respawn_interval` — so hunting the same hillside
## every day stops paying, which is the whole point of having animals rather
## than a food button.
func take_prey(world_xz: Vector2, radius: float) -> bool:
	var r2 := radius * radius
	var best: WildCreature = null
	var best_d := INF
	for c in _alive:
		if not is_instance_valid(c) or not c.is_alive():
			continue
		if c.species != null and not c.species.is_prey:
			continue
		var p: Vector3 = c.global_position
		var dx: float = p.x - world_xz.x
		var dz: float = p.z - world_xz.y
		var d: float = dx * dx + dz * dz
		if d <= r2 and d < best_d:
			best_d = d
			best = c
	if best == null:
		return false
	report_kill(best, null)
	if is_instance_valid(best):
		best.queue_free()
	return true


# ---------------------------------------------------------------------------
# Events the creatures report back
# ---------------------------------------------------------------------------
func report_alarm(creature: WildCreature, threat_position: Vector3) -> void:
	creature_alarmed.emit(creature, threat_position)
	# Voices trigger. No lines are authored for this yet (systems/voices/ is
	# package M's file and this package may not edit it) — Voices.react()
	# no-ops cleanly on an unknown trigger (voice_lines.gd's pick_pair returns
	# [] for a missing key), so this is a live hook, not a fake feature.
	var now := float(Time.get_ticks_msec()) * 0.001
	if now - _last_alarm_voice >= ALARM_VOICE_COOLDOWN:
		_last_alarm_voice = now
		Voices.react(&"wildlife_scattered", {"species": creature.species_id()})


func report_kill(prey: WildCreature, killer: WildCreature) -> void:
	var prey_sid := prey.species_id()
	var killer_sid: StringName = killer.species_id() if killer else &"unknown"
	var where := prey.global_position
	_unregister(prey)
	prey_killed.emit(prey_sid, killer_sid, where)
	Voices.react(&"wildlife_kill", {"species": prey_sid, "predator": killer_sid})
	# Tell the scavengers. One pass over the population, only when something
	# actually dies — this is not per-frame work.
	for c in _alive:
		if is_instance_valid(c) and c.is_alive() and c.species and c.species.scavenges:
			c.notify_carcass(where)


func _on_creature_killed(creature: WildCreature, _killer: WildCreature) -> void:
	# report_kill() already unregisters when the kill came through a predator;
	# this covers any other caller of kill_by() (a future miracle, a duel).
	if _alive.has(creature):
		_unregister(creature)


# ---------------------------------------------------------------------------
# Naklon reaction (cheap: signal-driven, never polled)
# ---------------------------------------------------------------------------
func _on_naklon_changed(_old: float, _new_value: float) -> void:
	var f := _current_fear_scale()
	for c in _alive:
		if is_instance_valid(c):
			c.set_fear_scale(f)


func _current_fear_scale() -> float:
	if not naklon_affects_wildlife:
		return 1.0
	return _piecewise(fear_scale_at_mercy, 1.0, fear_scale_at_cruelty, Naklon.unit())


func _naklon_scaled_count(base_count: int) -> int:
	if not naklon_affects_wildlife:
		return base_count
	var s := _piecewise(population_scale_at_mercy, 1.0, population_scale_at_cruelty, Naklon.unit())
	return maxi(0, int(round(float(base_count) * s)))


## mercy -> neutral -> cruelty, piecewise, so a player who has never acted
## (Naklon.value == 0.0, unit() == 0.5) gets EXACTLY the authored numbers
## rather than a midpoint of the two poles. This is the same reasoning
## environment/naklon_environment_driver.gd already documents in
## docs/systems/performance_notes.md ("Deviation from art_direction.md §4").
func _piecewise(at_mercy: float, at_neutral: float, at_cruelty: float, unit: float) -> float:
	if unit <= 0.5:
		return lerpf(at_mercy, at_neutral, unit * 2.0)
	return lerpf(at_neutral, at_cruelty, (unit - 0.5) * 2.0)


# ---------------------------------------------------------------------------
# Slow repopulation
# ---------------------------------------------------------------------------
func _try_respawn() -> void:
	for key in _target_counts:
		var sid: StringName = key
		var target: int = _target_counts[sid]
		if living_count(sid) >= target:
			continue
		var species: WildlifeSpecies = load(SPECIES_DIR + String(sid) + ".tres") as WildlifeSpecies
		if species == null or species.is_predator:
			continue   # predators do not wander back; an island loses its thawjaw for good
		# Come in from the edge of the range, not out of thin air in the middle.
		var edge := spawn_center_xz + Vector2(cos(randf() * TAU), sin(randf() * TAU)) * spawn_radius * 0.9
		var spot := _find_spawn_point(species, edge, spawn_radius * 0.25)
		if spot == Vector3.INF:
			return
		var creature := _instance_creature(species, spot)
		if creature:
			creature_spawned.emit(creature)
		return   # at most one per interval


# ---------------------------------------------------------------------------
# QA hook (mirrors LouhiDirector.debug_force_evaluate()'s convention)
# ---------------------------------------------------------------------------
func debug_force_hunt() -> void:
	for c in _alive:
		if is_instance_valid(c) and c.species and c.species.is_predator:
			c.debug_make_hungry()
