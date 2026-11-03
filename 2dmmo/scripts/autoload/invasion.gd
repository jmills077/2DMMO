extends Node
## Invasions: goblin raiders march down the road from both map edges and
## attack the town square. They ignore players; players fight them.
##
## - The town has health (shown at the top of the screen during an invasion).
##   Every raider that reaches the square chips away at it.
## - Kill every raider and the town holds.
## - Town upgrades help: the palisade holds raiders at its gates for a while,
##   the watchtower shoots the nearest raider, and engineers' spike traps
##   (click one in your bag to set it where you stand) hurt the first raider
##   that steps on them.
## - If the town's health runs out, a built Supply Silo saves it: the silo is
##   destroyed and the stockpile loses half its stock. With no silo the town
##   falls: the stockpile is emptied and every upgrade is destroyed.
##
## For testing, an invasion comes every 10 minutes and F10 starts one now.
## (The real schedule, 1 day, 2 days, 4 days..., comes with the tester server.)

signal changed

const INTERVAL_SECONDS := 600.0
const TOWN_HEALTH := 300
## The town square raiders head for: tile (23, 15).
const TOWN_CENTER := Vector2(23 * 16 + 8, 15 * 16 + 8)
## Where raiders appear: the two ends of the road.
const ENTRANCES := [Vector2(1 * 16 + 8, 15 * 16 + 8), Vector2(46 * 16 + 8, 15 * 16 + 8)]
## The palisade's two gates (see data/upgrades.json).
const GATES := [Vector2(17 * 16 + 8, 15 * 16 + 8), Vector2(30 * 16 + 8, 15 * 16 + 8)]
const PALISADE_HOLD_SECONDS := 8.0
const WATCHTOWER := Vector2(29 * 16 + 8, 11 * 16 + 8)
const WATCHTOWER_RANGE := 110.0
const WATCHTOWER_DAMAGE := 6
const WATCHTOWER_SECONDS := 2.0
const TRAP_DAMAGE := 15
const TRAP_RADIUS := 8.0
const MAX_RAIDERS := 15
const SPAWN_GAP_SECONDS := 1.5

## {"number": invasions so far, "seconds_left": until the next one,
##  "active": bool, "town_health", "town_max", "raiders_left"}
var state := {}
## Spike traps set in the world: id -> position.
var traps := {}

# Server only.
var _to_spawn := 0
var _spawn_left := 0.0
var _tower_left := WATCHTOWER_SECONDS
var _next_id := 1
var _next_trap := 1
var _publish_left := 0.0


func _ready() -> void:
	reset()


func reset() -> void:
	state = {"number": 0, "seconds_left": INTERVAL_SECONDS, "active": false,
		"town_health": TOWN_HEALTH, "town_max": TOWN_HEALTH, "raiders_left": 0}
	traps = {}
	_to_spawn = 0


func _process(delta: float) -> void:
	if not state.active:
		state.seconds_left = maxf(float(state.seconds_left) - delta, 0.0)
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server() or not Server.running:
		return
	if not state.active:
		if state.seconds_left <= 0.0:
			start()
		return
	if _to_spawn > 0:
		_spawn_left -= delta
		if _spawn_left <= 0.0:
			_spawn_left = SPAWN_GAP_SECONDS
			_to_spawn -= 1
			_spawn_raider(ENTRANCES[_to_spawn % 2])
	if Town.is_built("watchtower"):
		_tower_left -= delta
		if _tower_left <= 0.0:
			_tower_left = WATCHTOWER_SECONDS
			_watchtower_shoot()
	_check_traps()
	_publish_left -= delta
	if _publish_left <= 0.0:
		_publish_left = 1.0
		publish()


# --- Questions anyone can ask ---

func raiders() -> Array:
	return get_tree().get_nodes_in_group("raider")


## The palisade gate a raider at this point must get through, or INF if there
## is no palisade or it is already inside.
func gate_for(point: Vector2) -> Vector2:
	if not Town.is_built("palisade"):
		return Vector2.INF
	return GATES[0] if point.x < TOWN_CENTER.x else GATES[1]


# --- Running an invasion (server) ---

func start() -> void:
	if state.active:
		return
	state.number = int(state.number) + 1
	state.active = true
	state.town_health = TOWN_HEALTH
	state.town_max = TOWN_HEALTH
	_to_spawn = mini(3 + 2 * (int(state.number) - 1), MAX_RAIDERS)
	state.raiders_left = _to_spawn
	_spawn_left = 0.0
	_tower_left = WATCHTOWER_SECONDS
	Server.toast_all("Invasion %d! %d goblin raiders are coming down the road. Defend the town square!" % [state.number, _to_spawn])
	publish()


## A raider reached the square and hit the town.
func hurt_town(amount: int) -> void:
	if not state.active:
		return
	state.town_health = maxi(int(state.town_health) - amount, 0)
	if state.town_health <= 0:
		_town_falls()
	publish()


func raider_died(raider: Node) -> void:
	state.raiders_left = maxi(int(state.raiders_left) - 1, 0)
	# Leave the body a moment, then take it away everywhere.
	get_tree().create_timer(1.5).timeout.connect(func() -> void:
		if is_instance_valid(raider):
			raider.queue_free()
			_send_raiders.call_deferred())
	if state.raiders_left <= 0 and _to_spawn <= 0 and state.active:
		_end()
		Server.toast_all("The town held! Invasion %d is over." % state.number)
	publish()


func _town_falls() -> void:
	if Town.is_built("silo"):
		Town.state.built.erase("silo")
		for id: String in Town.state.stockpile.keys():
			Town.state.stockpile[id] = int(Town.state.stockpile[id]) / 2
		Server.toast_all("The raiders broke through, but the Supply Silo saved the town. The silo is gone and the stockpile lost half its stock.")
	else:
		Town.state.stockpile = {}
		Town.state.built = []
		Server.toast_all("The town has fallen. The raiders emptied the stockpile and wrecked every upgrade.")
	Town.publish()
	_end()


func _end() -> void:
	state.active = false
	state.raiders_left = 0
	state.seconds_left = INTERVAL_SECONDS
	_to_spawn = 0
	for raider: Node in raiders():
		raider.queue_free()
	_send_raiders.call_deferred()
	publish()


func _spawn_raider(where: Vector2) -> void:
	var raider := _make_raider(_next_id, where)
	_next_id += 1
	if raider:
		raider.state_changed.connect(Server._broadcast_state.bind(raider))
	_send_raiders()


func _watchtower_shoot() -> void:
	var best: Node2D = null
	var best_distance := WATCHTOWER_RANGE
	for raider: Node2D in raiders():
		var distance := raider.global_position.distance_to(WATCHTOWER)
		if raider.is_alive() and distance <= best_distance:
			best = raider
			best_distance = distance
	if best:
		Combat._rpc_all("_receive_arrow", [WATCHTOWER + Vector2(0, -12), best.global_position])
		best.take_damage(WATCHTOWER_DAMAGE, 0)


func _check_traps() -> void:
	for id: int in traps.keys():
		for raider: Node2D in raiders():
			if raider.is_alive() and raider.global_position.distance_to(traps[id]) <= TRAP_RADIUS:
				traps.erase(id)
				raider.take_damage(TRAP_DAMAGE, 0)
				_send_traps()
				break


# --- Requests from players ---

## Click a spike trap in your bag to set it where you stand.
@rpc("any_peer", "call_local", "reliable")
func request_place_trap(bag_index: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := Server.sender()
	var bag := Server.bag_of(peer)
	var node := Server.player_node(peer)
	if bag == null or node == null or bag_index < 0 or bag_index >= bag.slots.size():
		return
	if bag.slots[bag_index].id != "spike_trap" or Combat.is_dead(peer):
		return
	bag.remove_item("spike_trap", 1)
	traps[_next_trap] = node.global_position
	_next_trap += 1
	Server.send_bag(peer)
	_send_traps()
	Server.toast(peer, "Spike trap set. The first raider to step on it gets hurt.")


## Testing shortcut (F10): start an invasion now.
@rpc("any_peer", "call_local", "reliable")
func request_start_now() -> void:
	if not multiplayer.is_server():
		return
	if not OS.is_debug_build():
		Server.toast(Server.sender(), "Starting invasions is only for testing")
		return
	if state.active:
		Server.toast(Server.sender(), "An invasion is already on")
		return
	start()


# --- Joining and saving (server) ---

func player_joined(peer_id: int) -> void:
	_call_on(peer_id, "_receive_state", [state])
	_call_on(peer_id, "_receive_raiders", [_raider_list()])
	_call_on(peer_id, "_receive_traps", [traps])


func to_save_data() -> Dictionary:
	var saved_traps: Array = []
	for id: int in traps:
		saved_traps.append([traps[id].x, traps[id].y])
	return {"number": state.number, "seconds_left": state.seconds_left, "traps": saved_traps}


func load_save_data(data: Dictionary) -> void:
	reset()
	state.number = int(data.get("number", 0))
	state.seconds_left = float(data.get("seconds_left", INTERVAL_SECONDS))
	for pair: Variant in data.get("traps", []):
		if pair is Array and pair.size() == 2:
			traps[_next_trap] = Vector2(float(pair[0]), float(pair[1]))
			_next_trap += 1
	_update_traps()


func publish() -> void:
	changed.emit()
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	for peer: int in multiplayer.get_peers():
		_receive_state.rpc_id(peer, state)


# --- Messages from the server (each runs on a player's machine) ---

@rpc("authority", "call_remote", "reliable")
func _receive_state(new_state: Dictionary) -> void:
	state = new_state
	changed.emit()


@rpc("authority", "call_remote", "reliable")
func _receive_raiders(list: Array) -> void:
	var wanted := {}
	for entry: Array in list:
		wanted[int(entry[0])] = true
		var entities := _entities()
		if entities and entities.get_node_or_null("Raider_%d" % int(entry[0])) == null:
			_make_raider(int(entry[0]), entry[1])
	for raider: Node in raiders():
		if not wanted.has(int(raider.get_meta("raider_id", 0))):
			raider.queue_free()


@rpc("authority", "call_local", "reliable")
func _receive_traps(new_traps: Dictionary) -> void:
	traps = new_traps.duplicate()
	_update_traps()


# --- Helpers ---

func _make_raider(id: int, where: Vector2) -> Node2D:
	var entities := _entities()
	if entities == null:
		return null
	var raider: Node2D = load("res://scenes/mob.tscn").instantiate()
	raider.name = "Raider_%d" % id
	raider.set_meta("raider_id", id)
	raider.set("display_name", "Goblin Raider")
	raider.set("max_health", 25)
	raider.set("raider", true)
	raider.set("persistent", false)
	raider.set("damage", 4)
	raider.set("attack_seconds", 1.5)
	raider.set("speed", 24.0)
	raider.set("respawn_seconds", 0.0)
	raider.position = where
	raider.add_to_group("raider")
	(raider.get_node("Sprite2D") as Sprite2D).texture = preload("res://art/goblin.png")
	entities.add_child(raider)
	return raider


func _raider_list() -> Array:
	var list: Array = []
	for raider: Node2D in raiders():
		if not raider.is_queued_for_deletion():
			list.append([int(raider.get_meta("raider_id", 0)), raider.global_position])
	return list


func _send_raiders() -> void:
	var list := _raider_list()
	for peer: int in multiplayer.get_peers():
		_receive_raiders.rpc_id(peer, list)


func _send_traps() -> void:
	_update_traps()
	for peer: int in multiplayer.get_peers():
		_receive_traps.rpc_id(peer, traps)


func _update_traps() -> void:
	var entities := _entities()
	if entities == null:
		return
	for node: Node in get_tree().get_nodes_in_group("spike_trap"):
		if not traps.has(int(node.get_meta("trap_id", 0))):
			node.queue_free()
	for id: int in traps:
		if entities.get_node_or_null("Trap_%d" % id) == null:
			var sprite := Sprite2D.new()
			sprite.name = "Trap_%d" % id
			sprite.texture = preload("res://art/icon_spike_trap.png")
			sprite.position = traps[id]
			sprite.z_index = -1
			sprite.set_meta("trap_id", id)
			sprite.add_to_group("spike_trap")
			entities.add_child(sprite)


func _entities() -> Node:
	return Server.world.get_node_or_null("Entities") if Server.world else null


func _call_on(peer_id: int, method: StringName, args: Array) -> void:
	if peer_id == multiplayer.get_unique_id():
		callv(method, args)
	else:
		callv("rpc_id", [peer_id, method] + args)
