extends Node
## Manual, human-in-the-loop test harness for network_manager.gd — NOT an
## automated test, and NOT something this session could execute end-to-end
## (this repo's sandbox has no GPU and cannot launch two separate Godot
## client processes against each other — see
## docs/systems/skirmish_net.md's honesty section). This scene's actual
## network behavior has therefore NOT been exercised here. It is written
## and reasoned through carefully against Godot 4.3's documented
## high-level multiplayer API (ENetMultiplayerPeer, MultiplayerAPI, @rpc)
## rather than verified by running it.
##
## To really test it: run two separate instances of this project (two
## processes on the same machine, or two machines on a LAN), open this
## scene in both, click Host in one and Join (127.0.0.1, same port, if
## local) in the other, then watch both feeds for seat_assigned /
## village_ownership_changed events on each side.

@onready var _network_manager: NetworkManager = $NetworkManager
@onready var _feed_label: Label = $UI/FeedLabel
@onready var _status_label: Label = $UI/StatusLabel
@onready var _host_button: Button = $UI/HostButton
@onready var _join_button: Button = $UI/JoinButton
@onready var _address_field: LineEdit = $UI/AddressField

var _feed_lines: Array[String] = []
const MAX_FEED_LINES := 20


func _ready() -> void:
	_host_button.pressed.connect(_on_host_pressed)
	_join_button.pressed.connect(_on_join_pressed)

	_network_manager.server_started.connect(_on_server_started)
	_network_manager.joined_server.connect(_on_joined_server)
	_network_manager.connection_failed.connect(_on_connection_failed)
	_network_manager.server_disconnected.connect(_on_server_disconnected)
	_network_manager.seat_assigned.connect(_on_seat_assigned)
	_network_manager.seat_freed.connect(_on_seat_freed)
	_network_manager.village_ownership_changed.connect(_on_village_ownership_changed)
	_network_manager.player_naklon_changed.connect(_on_player_naklon_changed)
	_network_manager.action_rejected.connect(_on_action_rejected)

	_address_field.text = "127.0.0.1"


func _on_server_started(port: int) -> void:
	_push_feed("Hosting on port %d (my peer id %d)" % [port, _network_manager.get_local_peer_id()])


func _on_joined_server() -> void:
	_push_feed("Joined (my peer id %d)" % _network_manager.get_local_peer_id())


func _on_connection_failed() -> void:
	_push_feed("Connection failed")


func _on_server_disconnected() -> void:
	_push_feed("Server disconnected")


func _on_seat_assigned(peer_id: int, seat_index: int) -> void:
	_push_feed("Seat %d claimed by peer %d" % [seat_index, peer_id])


func _on_seat_freed(peer_id: int, seat_index: int) -> void:
	_push_feed("Seat %d (peer %d) vacated" % [seat_index, peer_id])


func _on_village_ownership_changed(village_id: StringName, owner_peer_id: int) -> void:
	_push_feed("%s now owned by peer %d" % [String(village_id), owner_peer_id])


func _on_player_naklon_changed(peer_id: int, value: float) -> void:
	_push_feed("peer %d Naklon -> %.2f" % [peer_id, value])


func _on_action_rejected(village_id: StringName, reason: String) -> void:
	_push_feed("rejected: %s (%s)" % [String(village_id), reason])


func _process(_delta: float) -> void:
	_status_label.text = "networked: %s   hosting: %s   local peer id: %d   seats: %s" % [
		_network_manager.is_networked(), _network_manager.is_hosting(),
		_network_manager.get_local_peer_id(), str(_network_manager.seats),
	]


func _on_host_pressed() -> void:
	var err := _network_manager.host_game()
	if err != OK:
		_push_feed("host_game() failed: err %d" % err)


func _on_join_pressed() -> void:
	var err := _network_manager.join_game(_address_field.text, NetworkManager.DEFAULT_PORT)
	if err != OK:
		_push_feed("join_game() failed: err %d" % err)


func _push_feed(text: String) -> void:
	_feed_lines.append(text)
	if _feed_lines.size() > MAX_FEED_LINES:
		_feed_lines.pop_front()
	_feed_label.text = "\n".join(_feed_lines)
