extends Node
## Starts a game (host), joins one (client), or runs a world with no player
## of its own (dedicated server).
##
## Pressing Play in the Godot editor hosts automatically. If another window is
## already hosting, the new window joins it instead. So with
## Debug > Customize Run Instances set to 2 or 3 windows, the first window
## hosts and the rest join, with nothing to click.
##
## Launch options (add after "--" on the command line, or in the editor under
## Debug > Customize Run Instances > Launch Arguments):
##   --server           run the world with no player (for a hosted tester server)
##   --host             host and play
##   --join=ADDRESS     join the server at ADDRESS (for example 192.168.1.20)
##   --name=NAME        the name to play as (default: Tester1, Tester2, ...)
##   --port=PORT        network port (default 24680)
##   --save=PATH        world save file used by the server (default user://world.json)
##   --fresh            start the world over (deletes that save file)

const DEFAULT_PORT := 24680
const MAX_PLAYERS := 32

## "" (not connected), "host", "client" or "server".
var mode := ""
var player_name := ""
var status := ""
var options := {}


func _ready() -> void:
	options = _parse_args()
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if options.has("bot"):
		add_child(load("res://tests/net_bot.gd").new())


func port() -> int:
	return int(options.get("port", DEFAULT_PORT))


## Called by the world scene once it has loaded.
func start_from_launch_options() -> void:
	player_name = str(options.get("name", ""))
	if options.has("server"):
		host(false)
	elif options.has("join"):
		join(str(options.join))
	elif options.has("host"):
		host(true)
	elif OS.has_feature("editor") or options.has("auto"):
		host_or_join()
	else:
		Events.show_connect_menu.emit()


func host_or_join() -> void:
	if not host(true):
		join("127.0.0.1")


## Opens the world to other players. Returns false if the port is taken,
## which usually means another window is already hosting.
func host(play: bool) -> bool:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(port(), MAX_PLAYERS) != OK:
		return false
	multiplayer.multiplayer_peer = peer
	mode = "host" if play else "server"
	Server.save_path = str(options.get("save", Server.DEFAULT_SAVE_PATH))
	if options.has("fresh"):
		Server.delete_save()
	Server.start(Server.save_path)
	if play:
		player_name = Server.add_player(1, player_name)
		_set_status("Hosting as %s (port %d)" % [player_name, port()])
	else:
		_set_status("Dedicated server on port %d" % port())
		print("Server running on port %d. Press Ctrl+C to stop." % port())
	return true


func join(address: String) -> void:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(address, port()) != OK:
		_set_status("Could not start connecting to %s" % address)
		return
	multiplayer.multiplayer_peer = peer
	mode = "client"
	_set_status("Connecting to %s..." % address)


## The server accepted us and told us our name.
func welcomed(final_name: String) -> void:
	player_name = final_name
	_set_status("Playing as %s" % player_name)


func _on_connected() -> void:
	Server.hello.rpc_id(1, player_name)


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	mode = ""
	_set_status("Could not reach the server")
	Events.show_connect_menu.emit()


func _on_server_disconnected() -> void:
	mode = ""
	_set_status("Lost connection to the server")
	Events.toast.emit("Disconnected from the server")


func _on_peer_disconnected(peer_id: int) -> void:
	if multiplayer.is_server():
		Server.remove_player(peer_id)


func _set_status(text: String) -> void:
	status = text
	Events.status_changed.emit(text)
	if player_name != "" and DisplayServer.get_name() != "headless":
		get_window().title = "2DMMO - %s" % player_name


func _parse_args() -> Dictionary:
	var parsed := {}
	for arg: String in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			continue
		var pair := arg.substr(2).split("=", true, 1)
		parsed[pair[0]] = pair[1] if pair.size() > 1 else true
	return parsed
