extends Node
## The rules of the world, decided in one place: the machine hosting the game.
##
## Players never change the world or their bags directly. Their game asks
## ("request_..."), the server checks the request makes sense (close enough,
## held long enough, has the materials), applies it, then tells everyone
## what changed. That keeps every window showing the same world and makes
## cheating much harder.
##
## The server also saves the world and every player's bag and position.

const Bag := preload("res://scripts/bag.gd")
const DEFAULT_SAVE_PATH := "user://world.json"
const SAVE_VERSION := 3
const AUTOSAVE_SECONDS := 60.0
## Where new players appear: town square, tile (23, 17).
const SPAWN_POINT := Vector2(23 * 16 + 8, 17 * 16 + 8)
## How far (in pixels) a player can be from what they use. A bit more than the
## player's reach, to allow for network delay.
const MAX_USE_DISTANCE := 40.0
## Gathering is a timing game: the bar fills over the gather time and the
## player taps E again inside a highlighted zone. The server picks the zone
## and checks the tap landed in it.
const GATHER_ZONE_WIDTH := 0.2
const GATHER_ZONE_EARLIEST := 0.3
const GATHER_ZONE_LATEST := 0.75
## Extra share of the bar allowed either side of the zone, for network delay.
const GATHER_TIMING_SLACK := 0.12

## The loaded world scene (main.tscn). It registers itself when it loads.
var world: Node
var running := false
var save_path := DEFAULT_SAVE_PATH
## Tests turn this off to gather instantly.
var check_gather_time := true

var _names := {}          # peer id -> player name
var _bags := {}           # peer id -> Bag
var _gathering := {}      # peer id -> {"path": String, "since": msec}
var _saved_players := {}  # player name -> {"x", "y", "inventory"}
var _autosave_left := AUTOSAVE_SECONDS


func _ready() -> void:
	get_tree().set_auto_accept_quit(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if running:
			save_world()
		get_tree().quit()


func _process(delta: float) -> void:
	if not running:
		return
	_autosave_left -= delta
	if _autosave_left <= 0.0:
		_autosave_left = AUTOSAVE_SECONDS
		save_world()


# --- Starting, joining and leaving ---

func start(path: String) -> void:
	save_path = path
	running = true
	_load_world()
	for node: Node in get_tree().get_nodes_in_group("persist"):
		if node.state_changed.get_connections().is_empty():
			node.state_changed.connect(_broadcast_state.bind(node))


## Puts a player in the world and returns the name they were given.
func add_player(peer_id: int, wanted_name: String) -> String:
	var player_name := _pick_name(wanted_name)
	var record: Dictionary = _saved_players.get(player_name, {})
	var bag := Bag.new()
	bag.load_save_data(record.get("inventory", []))
	_names[peer_id] = player_name
	_bags[peer_id] = bag
	world.spawn_player({
		"id": peer_id,
		"name": player_name,
		"x": float(record.get("x", SPAWN_POINT.x)),
		"y": float(record.get("y", SPAWN_POINT.y)),
	})
	send_bag(peer_id)
	Town.player_joined(player_name)
	toast_all("%s joined" % player_name)
	return player_name


func remove_player(peer_id: int) -> void:
	if not _names.has(peer_id):
		return
	var player_name: String = _names[peer_id]
	_store_player(peer_id)
	var node := player_node(peer_id)
	if node:
		node.queue_free()
	_names.erase(peer_id)
	_bags.erase(peer_id)
	_gathering.erase(peer_id)
	Town.player_left(player_name)
	toast_all("%s left" % player_name)
	save_world()


func bag_of(peer_id: int) -> Bag:
	return _bags.get(peer_id)


func player_node(peer_id: int) -> Node2D:
	var entities := world.get_node_or_null("Entities")
	return entities.get_node_or_null(str(peer_id)) if entities else null


func player_names() -> Array:
	return _names.values()


func name_of(peer_id: int) -> String:
	return str(_names.get(peer_id, ""))


# --- Requests from players (each runs on the server) ---

@rpc("any_peer", "call_local", "reliable")
func hello(wanted_name: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := sender()
	if _names.has(peer):
		return
	for node: Node in get_tree().get_nodes_in_group("persist"):
		_receive_state.rpc_id(peer, path_of(node), node.get_save_state())
	var final_name := add_player(peer, wanted_name)
	_receive_welcome.rpc_id(peer, final_name)


@rpc("any_peer", "call_local", "reliable")
func request_gather_start(path: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := sender()
	var target := reachable(peer, path)
	if target == null or not target.has_method("harvest"):
		return
	if target.get_interaction() != "gather":
		toast(peer, "Someone got there first")
		return
	var zone_start := randf_range(GATHER_ZONE_EARLIEST, GATHER_ZONE_LATEST)
	_gathering[peer] = {"path": path, "since": Time.get_ticks_msec(), "zone": zone_start}
	_call_on(peer, "_receive_gather_zone", [path, zone_start, GATHER_ZONE_WIDTH])


@rpc("any_peer", "call_local", "reliable")
func request_gather_finish(path: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := sender()
	var started: Dictionary = _gathering.get(peer, {})
	_gathering.erase(peer)
	var target := reachable(peer, path)
	if target == null or not target.has_method("harvest"):
		return
	if target.get_interaction() != "gather":
		toast(peer, "Someone got there first")
		return
	if check_gather_time:
		if started.get("path", "") != path:
			return
		var ratio: float = (Time.get_ticks_msec() - int(started.since)) / (target.gather_duration() * 1000.0)
		var zone := float(started.zone)
		if ratio < zone - GATHER_TIMING_SLACK or ratio > zone + GATHER_ZONE_WIDTH + GATHER_TIMING_SLACK:
			toast(peer, "Missed!")
			return
	_give(peer, target.harvest())


@rpc("any_peer", "call_local", "reliable")
func request_use(path: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := sender()
	var target := reachable(peer, path)
	if target == null or not target.has_method("server_use"):
		return
	var message: String = target.server_use(bag_of(peer))
	send_bag(peer)
	if message != "":
		toast(peer, message)


@rpc("any_peer", "call_local", "reliable")
func request_craft(recipe_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := sender()
	var recipe := Crafting.find_recipe(recipe_id)
	if recipe.is_empty() or bag_of(peer) == null:
		return
	var guild := str(recipe.get("guild", ""))
	if not Town.knows_recipe(name_of(peer), recipe_id):
		toast(peer, "You don't know that recipe")
		return
	if guild != "" and Town.guild_of(name_of(peer)) != guild:
		toast(peer, "Only %s can craft that" % GameData.get_guild(guild).get("name", guild))
		return
	var result := Crafting.craft(bag_of(peer), recipe)
	send_bag(peer)
	if not result.ok:
		toast(peer, result.reason)
	elif result.high_quality:
		toast(peer, "High quality %s!" % GameData.item_name(result.item))
	else:
		toast(peer, "Crafted %s" % GameData.item_name(result.item))


## Testing shortcut (F9): every rock, sheep, deer, herb and tree comes back.
## Only works in test builds (running from the Godot editor), never on a
## released server.
@rpc("any_peer", "call_local", "reliable")
func request_refill_resources() -> void:
	if not multiplayer.is_server():
		return
	if not OS.is_debug_build():
		toast(sender(), "Refilling is only for testing")
		return
	for node: Node in get_tree().get_nodes_in_group("persist"):
		node.apply_save_state({})
		_broadcast_state(node)
	toast_all("%s refilled every resource (F9)" % name_of(sender()))


@rpc("any_peer", "call_local", "reliable")
func request_save() -> void:
	if multiplayer.is_server():
		save_world()
		toast(sender(), "World saved")


# --- Messages from the server (each runs on a player's machine) ---

@rpc("authority", "call_local", "reliable")
func _receive_bag(slots: Array) -> void:
	Inventory.set_slots(slots)


@rpc("authority", "call_local", "reliable")
func _receive_gather_zone(path: String, zone_start: float, zone_width: float) -> void:
	Events.gather_zone.emit(path, zone_start, zone_width)


@rpc("authority", "call_local", "reliable")
func _receive_toast(text: String) -> void:
	Events.toast.emit(text)


@rpc("authority", "call_remote", "reliable")
func _receive_state(path: String, state: Dictionary) -> void:
	var node := world.get_node_or_null(path)
	if node and node.has_method("apply_save_state"):
		node.apply_save_state(state)


@rpc("authority", "call_local", "reliable")
func _receive_welcome(final_name: String) -> void:
	Net.welcomed(final_name)


# --- Saving ---

func save_world() -> void:
	if not running:
		return
	for peer: int in _names:
		_store_player(peer)
	var objects := {}
	for node: Node in get_tree().get_nodes_in_group("persist"):
		objects[path_of(node)] = node.get_save_state()
	var data := {"version": SAVE_VERSION, "world": objects, "players": _saved_players, "town": Town.to_save_data()}
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write %s" % save_path)
		return
	file.store_string(JSON.stringify(data, "\t"))


func _load_world() -> void:
	_saved_players = {}
	Town.reset()
	if not FileAccess.file_exists(save_path):
		Town.publish()
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not parsed is Dictionary:
		push_warning("World save unreadable, starting fresh")
		return
	var data: Dictionary = parsed
	var objects: Dictionary = data.get("world", {})
	for path: String in objects:
		var node := world.get_node_or_null(path)
		if node and node.has_method("apply_save_state"):
			node.apply_save_state(objects[path])
	_saved_players = data.get("players", {})
	Town.load_save_data(data.get("town", {}))


func delete_save() -> void:
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


func _store_player(peer_id: int) -> void:
	var node := player_node(peer_id)
	if node == null or not _names.has(peer_id):
		return
	_saved_players[_names[peer_id]] = {
		"x": node.global_position.x,
		"y": node.global_position.y,
		"inventory": _bags[peer_id].to_save_data(),
	}


# --- Helpers ---

func path_of(node: Node) -> String:
	return str(world.get_path_to(node))


func sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else multiplayer.get_unique_id()


## The world object at path, if the player is close enough to use it.
func reachable(peer_id: int, path: String) -> Node2D:
	var entities := world.get_node_or_null("Entities")
	var target := world.get_node_or_null(path) as Node2D
	var player := player_node(peer_id)
	if entities == null or target == null or player == null or not entities.is_ancestor_of(target):
		return null
	if player.global_position.distance_to(target.global_position) > MAX_USE_DISTANCE:
		toast(peer_id, "Too far away")
		return null
	return target


func _give(peer_id: int, rewards: Dictionary) -> void:
	var bag := bag_of(peer_id)
	if bag == null:
		return
	var parts: Array[String] = []
	var lost: Array[String] = []
	for id: String in rewards:
		var left := bag.add_item(id, int(rewards[id]))
		parts.append("+%d %s" % [int(rewards[id]) - left, GameData.item_name(id)])
		if left > 0:
			lost.append("%d %s" % [left, GameData.item_name(id)])
	send_bag(peer_id)
	toast(peer_id, ", ".join(parts))
	if not lost.is_empty():
		toast(peer_id, "Bag full: lost " + ", ".join(lost))


func _pick_name(wanted: String) -> String:
	wanted = wanted.strip_edges().left(16)
	var online := _names.values()
	if wanted == "":
		var i := 1
		while ("Tester%d" % i) in online:
			i += 1
		return "Tester%d" % i
	var candidate := wanted
	var n := 2
	while candidate in online:
		candidate = "%s%d" % [wanted, n]
		n += 1
	return candidate


func _broadcast_state(node: Node) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	var path := path_of(node)
	var state: Dictionary = node.get_save_state()
	for peer: int in multiplayer.get_peers():
		_receive_state.rpc_id(peer, path, state)


func send_bag(peer_id: int) -> void:
	if _bags.has(peer_id):
		_call_on(peer_id, "_receive_bag", [_bags[peer_id].to_save_data()])


func toast(peer_id: int, text: String) -> void:
	_call_on(peer_id, "_receive_toast", [text])


func toast_all(text: String) -> void:
	for peer: int in _names:
		toast(peer, text)


## Runs a message on one player's machine (directly, if that player is us).
func _call_on(peer_id: int, method: StringName, args: Array) -> void:
	if peer_id == multiplayer.get_unique_id():
		callv(method, args)
	else:
		callv("rpc_id", [peer_id, method] + args)
