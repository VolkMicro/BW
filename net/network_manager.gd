extends Node
class_name NetworkManager
## Package O — "Nine Thrones" networking: real multiplayer over Godot 4.3's
## high-level multiplayer API (ENetMultiplayerPeer + @rpc), not a
## description of one. Up to nine god-seats can contest the Ninefold Sea's
## villages in the same match — "Nine Thrones" is the in-fiction name for
## that nine-seat table, not a real-world claim about server capacity.
##
## modes/skirmish/ (this same package) is the natural place to actually
## play a match, but this file has no hard dependency on it: a
## NetworkManager works with no SkirmishScenario present at all (a future
## full-campaign multiplayer mode could drive it directly), exactly as
## SkirmishScenario works with no NetworkManager present (single-player vs.
## Louhi, or a bare sandbox).
##
## THIS NODE IS NOT AN AUTOLOAD. Package O may not edit project.godot per
## docs/systems/OWNERSHIP.md. See network_manager.tscn for a
## ready-to-instance wrapper (same shape as
## actors/louhi/louhi_director.tscn) and docs/systems/skirmish_net.md for
## exactly what's wired vs. not — including this repo's honesty norm on
## what real multi-client testing this package could NOT perform in this
## sandboxed, single-process, no-GPU dev environment.
##
## IMPORTANT, real Godot networking constraint: Godot's high-level RPC
## system dispatches by matching NodePath across peers — a `.rpc()` call
## only reaches the "same" node on a remote peer if that node sits at the
## identical path from the scene root on every peer. Whoever instances this
## node into a real scene (see docs/systems/skirmish_net.md) MUST make sure
## it's placed at the same path for the host and every joining client (e.g.
## as a fixed child of a lobby/menu scene loaded identically everywhere) —
## otherwise RPCs silently fail to route. Flagged here because it's the
## single most common real-world Godot multiplayer bug and this package
## cannot enforce it from inside its own script.
##
## THE MODEL — what must agree across peers, and what deliberately doesn't:
##
## 1. Host-authoritative shared world state. The host is whichever peer
##    calls host_game() (always ENet peer id 1 once connected). Two pieces
##    of state are synchronized because gameplay genuinely breaks if peers
##    disagree about them:
##      - the seat roster: peer_id <-> one of nine seats (`seats`)
##      - village ownership: StringName village_id -> int peer_id, 0 =
##        unclaimed (`village_owner`) — "whose god controls which
##        village," exactly what the brief asks for.
##
## 2. Naklon is deliberately NOT synchronized as authoritative shared
##    state. core/naklon.gd is a plain autoload; every peer's OS process
##    has its own independent Naklon instance representing only that
##    peer's own god. perform_conversion() below always runs its
##    Reach.convert_via_* call LOCALLY FIRST on the acting peer's own
##    machine — exactly like single-player — which is what correctly moves
##    THAT peer's own Naklon and fires THAT peer's own Voices remark, with
##    no per-player special-casing required anywhere. What IS mirrored to
##    other peers, read-only, is a plain `int peer_id -> float` snapshot
##    (`player_naklon`) purely so other gods can be shown each other's
##    alignment (e.g. a future diegetic "their throne looks colder now"
##    cue) — it is never applied to drive any other peer's own gameplay.
##
## 3. The host never calls Reach.convert_via_help/terror/missionary on
##    behalf of a REMOTE peer's action — doing so would incorrectly shift
##    the HOST's own local Naklon for another player's deed. Instead,
##    _server_recompute_gain() (below) recomputes the same
##    fatigue/ceiling-limited faith gain using ONLY Reach's public
##    constants and public methods (Reach.effectiveness(),
##    Reach.register_use(), GameState.set_faith_fraction() — see the
##    method's own doc comment for the exact reach.gd line references it
##    mirrors) and applies only the village-state side of it. This is
##    standard client-side prediction / server reconciliation: the acting
##    peer's optimistic local apply and the host's independent
##    authoritative recompute agree in the common case (nothing else
##    touched that village meanwhile, so both sides ran the identical
##    deterministic formula against the same starting fatigue state); they
##    only visibly diverge — and the host's broadcast corrects the client
##    — when two peers race on the same village in the same instant.
##
## 4. Taking an already-claimed village away from another living player is
##    NOT implemented in this pass (see docs/systems/skirmish_net.md
##    "Scoped out") — ownership only transfers unclaimed -> claimed,
##    first-valid-request-wins, arbitrated by the host. The sync primitive
##    (`village_owner`, authoritative on host, broadcast to everyone) is
##    real and ready for a future pass to add real contest rules on top of.

signal server_started(port: int)
signal join_requested(address: String, port: int)
signal joined_server()
signal connection_failed()
signal server_disconnected()
signal seat_assigned(peer_id: int, seat_index: int)
signal seat_freed(peer_id: int, seat_index: int)
signal village_ownership_changed(village_id: StringName, owner_peer_id: int)
signal player_naklon_changed(peer_id: int, value: float)
signal action_rejected(village_id: StringName, reason: String)

const MAX_SEATS := 9 ## "Nine Thrones" — nine god-seats contesting the Ninefold Sea
const DEFAULT_PORT := 9091 ## arbitrary; no real-world service is registered on this port
const UNCLAIMED := 0 ## sentinel owner id; ENet peer ids are always >= 1

@export var auto_report_local_naklon: bool = true

var seats: Dictionary = {} ## int peer_id -> int seat_index (1..MAX_SEATS)
var village_owner: Dictionary = {} ## StringName village_id -> int peer_id (0 = unclaimed)
var player_naklon: Dictionary = {} ## int peer_id -> float, read-only mirror (see class doc, point 2)

var _is_host: bool = false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	if not has_node("/root/Naklon"):
		push_warning("NetworkManager: /root/Naklon not found — per-player Naklon mirroring will no-op.")
		return
	if auto_report_local_naklon:
		Naklon.naklon_changed.connect(_on_local_naklon_changed)


# ---------------------------------------------------------------------------
# Host / join
# ---------------------------------------------------------------------------

func host_game(port: int = DEFAULT_PORT, max_players: int = MAX_SEATS) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, clampi(max_players, 1, MAX_SEATS))
	if err != OK:
		push_warning("NetworkManager: create_server failed (err %d)" % err)
		return err
	multiplayer.multiplayer_peer = peer
	_is_host = true
	seats.clear()
	village_owner.clear()
	player_naklon.clear()
	_assign_seat(multiplayer.get_unique_id())
	server_started.emit(port)
	return OK


func join_game(address: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		push_warning("NetworkManager: create_client failed (err %d)" % err)
		return err
	multiplayer.multiplayer_peer = peer
	_is_host = false
	join_requested.emit(address, port)
	return OK


func close_connection() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	_is_host = false
	seats.clear()
	village_owner.clear()
	player_naklon.clear()


func is_hosting() -> bool:
	return _is_host


func is_networked() -> bool:
	if multiplayer.multiplayer_peer == null:
		return false
	return multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func get_local_peer_id() -> int:
	return multiplayer.get_unique_id()


func get_seat_for_peer(peer_id: int) -> int:
	return seats.get(peer_id, 0)


func get_village_owner(village_id: StringName) -> int:
	return village_owner.get(village_id, UNCLAIMED)


# ---------------------------------------------------------------------------
# Connection lifecycle (host side assigns seats + syncs late joiners; every
# peer reacts to its own connection state changing)
# ---------------------------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	_assign_seat(id)
	# Late-join full sync: a peer that connects after the match is already
	# underway needs the CURRENT seat roster / village ownership / Naklon
	# mirror, not just future deltas.
	_send_full_sync.rpc_id(id, seats.duplicate(), village_owner.duplicate(), player_naklon.duplicate())


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	var seat_index: int = seats.get(id, 0)
	if seat_index != 0:
		seats.erase(id)
		seat_freed.emit(id, seat_index)
	player_naklon.erase(id)
	# Deliberately NOT reverting that peer's villages to &"unclaimed" — an
	# absent player's throne sits empty but still theirs, exactly like a
	# real ruler gone quiet, rather than the game quietly redistributing
	# their land. A reclaim/abdication rule is the natural follow-up (see
	# docs/systems/skirmish_net.md "Scoped out").


func _on_connected_to_server() -> void:
	joined_server.emit()


func _on_connection_failed() -> void:
	_is_host = false
	connection_failed.emit()


func _on_server_disconnected() -> void:
	_is_host = false
	seats.clear()
	village_owner.clear()
	player_naklon.clear()
	server_disconnected.emit()


## Host-only. Assigns the lowest free seat index (1..MAX_SEATS) rather than
## always incrementing, so a seat vacated by a disconnect can be re-taken
## by the next joiner instead of the roster only ever growing toward nine.
func _assign_seat(peer_id: int) -> void:
	if seats.has(peer_id):
		return
	if seats.size() >= MAX_SEATS:
		push_warning("NetworkManager: all nine thrones are already seated; peer %d observes only." % peer_id)
		return
	var used := {}
	for s in seats.values():
		used[s] = true
	var seat_index := 1
	while used.has(seat_index):
		seat_index += 1
	seats[peer_id] = seat_index
	seat_assigned.emit(peer_id, seat_index)


@rpc("authority", "call_remote", "reliable")
func _send_full_sync(seats_snapshot: Dictionary, village_owner_snapshot: Dictionary, naklon_snapshot: Dictionary) -> void:
	seats = seats_snapshot
	village_owner = village_owner_snapshot
	player_naklon = naklon_snapshot
	for village_id in village_owner.keys():
		village_ownership_changed.emit(village_id, village_owner[village_id])
	for peer_id in player_naklon.keys():
		player_naklon_changed.emit(peer_id, player_naklon[peer_id])


# ---------------------------------------------------------------------------
# Home village assignment (host-only)
# ---------------------------------------------------------------------------

## Host-only. Hands out starting "home" villages to every currently seated
## peer, round-robin, and broadcasts the result. Intended caller: whatever
## starts a Nine Thrones match — e.g. modes/skirmish/skirmish_scenario.gd
## via its own network_manager_path hook (duck-typed; see that file), or a
## future ui/ lobby screen. No-op if called by a non-host or with no seats
## or no candidate villages yet.
func assign_home_villages(candidate_village_ids: Array[StringName]) -> void:
	if not multiplayer.is_server():
		push_warning("NetworkManager: assign_home_villages() called on a non-host peer; ignored.")
		return
	var peer_ids := seats.keys()
	if peer_ids.is_empty() or candidate_village_ids.is_empty():
		return
	for i in candidate_village_ids.size():
		var peer_id: int = peer_ids[i % peer_ids.size()]
		var village_id: StringName = candidate_village_ids[i]
		village_owner[village_id] = peer_id
		_broadcast_village_state(village_id)


# ---------------------------------------------------------------------------
# Conversion actions — the single call site UI/campaign code should use
# ---------------------------------------------------------------------------

## The single call site any UI/campaign code should use to run a conversion
## action, whether or not a Nine Thrones match is in progress. Offline (or
## not yet connected), this is a thin pass-through to Reach — behaves
## exactly like calling Reach.convert_via_* directly, zero overhead. Once
## networked, it ALSO applies locally first (see class doc point 2: this
## correctly moves only the ACTING peer's own Naklon/Voices) and either
## resolves immediately (if this peer IS the host) or reports the action to
## the host for arbitration + broadcast (if it isn't).
## `method_id` must be &"help", &"terror", or &"missionary" — the same
## three method ids systems/faith/reach.gd's convert_via_* methods use.
func perform_conversion(village_id: StringName, method_id: StringName, amount: float) -> void:
	if amount <= 0.0:
		return
	if not is_networked():
		_apply_local(village_id, method_id, amount)
		return

	var v: Village = GameState.get_village(village_id)
	if v == null or v.loyal_to_rival:
		action_rejected.emit(village_id, "no such village, or it belongs to Louhi")
		return
	var owner_peer: int = village_owner.get(village_id, UNCLAIMED)
	var me := multiplayer.get_unique_id()
	if owner_peer != UNCLAIMED and owner_peer != me:
		action_rejected.emit(village_id, "village already claimed by another throne")
		return

	_apply_local(village_id, method_id, amount) # moves MY OWN Naklon/Voices, host or not

	if multiplayer.is_server():
		# I AM the authority for shared world state — my own GameState copy
		# IS the canonical one, so _apply_local() above already was both
		# the optimistic AND the authoritative update. Just record/broadcast
		# ownership, no second gain application.
		if owner_peer == UNCLAIMED:
			village_owner[village_id] = me
		_broadcast_village_state(village_id)
	else:
		_rpc_request_action.rpc_id(1, village_id, method_id, amount)


func _apply_local(village_id: StringName, method_id: StringName, amount: float) -> void:
	match method_id:
		&"help":
			Reach.convert_via_help(village_id, amount)
		&"terror":
			Reach.convert_via_terror(village_id, amount)
		&"missionary":
			Reach.convert_via_missionary(village_id, amount)
		_:
			push_warning("NetworkManager: unknown conversion method_id %s" % String(method_id))


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_action(village_id: StringName, method_id: StringName, amount: float) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	var owner_peer: int = village_owner.get(village_id, UNCLAIMED)
	if owner_peer != UNCLAIMED and owner_peer != sender_id:
		# Reject: tell only the requester the true current state so their
		# optimistic local apply gets corrected back to reality.
		_broadcast_village_state_to(village_id, sender_id)
		return
	var v: Village = GameState.get_village(village_id)
	if v == null or v.loyal_to_rival:
		return
	if owner_peer == UNCLAIMED:
		village_owner[village_id] = sender_id
	_server_recompute_gain(v, method_id, amount)
	_broadcast_village_state(village_id)


## Host-only. Mirrors systems/faith/reach.gd's private _grow_faith()
## (reach.gd:126-141) using ONLY Reach's public constants
## (HELP_GAIN_PER_AMOUNT/HELP_CEILING at reach.gd:25-26,
## TERROR_GAIN_PER_AMOUNT/TERROR_CEILING at reach.gd:30-31,
## MISSIONARY_CEILING at reach.gd:35) and public methods
## (Reach.effectiveness() at reach.gd:51, Reach.register_use() at
## reach.gd:60) plus GameState.set_faith_fraction() (game_state.gd:57-64).
## Deliberately never calls Reach.convert_via_help/terror/missionary
## itself, and never touches Naklon or Voices — see this file's class doc,
## point 3, for why crediting a remote peer's action to the HOST's own
## local Naklon would be wrong. This is the one place in this package that
## duplicates a formula instead of calling through to it, because Reach's
## only public entry points for this math (convert_via_*) are inseparable
## from their Naklon/Voices side effects; if reach.gd's private formula
## ever changes, this needs a matching update.
func _server_recompute_gain(v: Village, method_id: StringName, amount: float) -> void:
	var requested_gain: float
	var ceiling: float
	match method_id:
		&"help":
			requested_gain = amount * Reach.HELP_GAIN_PER_AMOUNT
			ceiling = Reach.HELP_CEILING
		&"terror":
			requested_gain = amount * Reach.TERROR_GAIN_PER_AMOUNT
			ceiling = Reach.TERROR_CEILING
		&"missionary":
			requested_gain = amount # convert_via_missionary passes amount straight through
			ceiling = Reach.MISSIONARY_CEILING
		_:
			return
	if requested_gain <= 0.0:
		return
	var eff := Reach.effectiveness(v.id, method_id)
	var headroom := clampf((ceiling - v.faith_fraction) / maxf(ceiling, 0.0001), 0.0, 1.0)
	var gain := requested_gain * eff * headroom
	if gain > 0.0:
		GameState.set_faith_fraction(v.id, minf(ceiling, v.faith_fraction + gain))
	Reach.register_use(v.id, method_id)


func _broadcast_village_state(village_id: StringName) -> void:
	var v: Village = GameState.get_village(village_id)
	if v == null:
		return
	var owner_peer: int = village_owner.get(village_id, UNCLAIMED)
	_rpc_apply_village_state.rpc(village_id, v.faith_fraction, v.loyal_to_rival, owner_peer)


func _broadcast_village_state_to(village_id: StringName, peer_id: int) -> void:
	var v: Village = GameState.get_village(village_id)
	if v == null:
		return
	var owner_peer: int = village_owner.get(village_id, UNCLAIMED)
	_rpc_apply_village_state.rpc_id(peer_id, village_id, v.faith_fraction, v.loyal_to_rival, owner_peer)


@rpc("authority", "call_local", "reliable")
func _rpc_apply_village_state(village_id: StringName, faith_fraction: float, loyal_to_rival: bool, owner_peer_id: int) -> void:
	var v: Village = GameState.get_village(village_id)
	if v != null:
		GameState.set_faith_fraction(village_id, faith_fraction)
		v.loyal_to_rival = loyal_to_rival
	if owner_peer_id == UNCLAIMED:
		village_owner.erase(village_id)
	else:
		village_owner[village_id] = owner_peer_id
	village_ownership_changed.emit(village_id, owner_peer_id)


# ---------------------------------------------------------------------------
# Per-player Naklon mirror (read-only for everyone but its own owner — see
# class doc, point 2)
# ---------------------------------------------------------------------------

func _on_local_naklon_changed(_old_value: float, new_value: float) -> void:
	if not is_networked():
		return
	var me := multiplayer.get_unique_id()
	if multiplayer.is_server():
		player_naklon[me] = new_value
		_rpc_apply_player_naklon.rpc(me, new_value)
	else:
		_rpc_report_naklon.rpc_id(1, new_value)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_report_naklon(value: float) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	player_naklon[sender_id] = value
	_rpc_apply_player_naklon.rpc(sender_id, value)


@rpc("authority", "call_local", "reliable")
func _rpc_apply_player_naklon(peer_id: int, value: float) -> void:
	player_naklon[peer_id] = value
	player_naklon_changed.emit(peer_id, value)
