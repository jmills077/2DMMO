extends Node
## Health, gear, fighting, dying and coming back.
##
## - Gear: click a sword, bow, shield or armor in your bag to wear it (I).
## - R attacks the way you last moved. A sword hits what's right in front of
##   you; a bow shoots an arrow 50 pixels. A missed arrow stays on the ground
##   until someone picks it up with E.
## - Wolves bite. At 0 health your body stays where it fell and your spirit
##   appears at the graveyard. Walk back to your body and press E to come back
##   to life there, with half your health.
## - Health slowly comes back when nothing has hurt you for a few seconds.
##   Healing salve (click it in your bag) heals straight away.
##
## As everywhere else, the server decides. Each window keeps a copy of
## everyone's health, who is dead and where, and its own gear.

signal health_changed(peer_id: int)
signal dead_changed(peer_id: int)
signal equipment_changed
signal ground_arrows_changed

const BASE_HEALTH := 50
## Where spirits appear: the graveyard west of town, tile (16, 17).
const GRAVEYARD := Vector2(16 * 16 + 8, 17 * 16 + 8)
## How close (pixels) a spirit must be to its body to come back.
const RESURRECT_DISTANCE := 24.0
const RESURRECT_HEALTH_SHARE := 0.5
const ARROW_RANGE := 50.0
const ARROW_SPEED := 250.0
## An arrow hits a creature this close to its flight line.
const ARROW_HIT_RADIUS := 4.0
## A sword swing hits creatures this close to a point just in front of you.
const SWING_RADIUS := 12.0
const DEFAULT_REACH := 12.0
const REGEN_DELAY_MS := 6000
const REGEN_PER_SECOND := 2
const MOB_SYNC_SECONDS := 0.1
const SLOTS := ["weapon", "offhand", "armor"]

## Every player's health as this window last heard: peer -> [health, max].
var health := {}
## Dead players: peer -> where their body lies.
var dead := {}
## This window's gear: slot name -> bag-style slot ({} when empty).
var equipment := {"weapon": {}, "offhand": {}, "armor": {}}
## Arrows lying on the ground: id -> position.
var ground_arrows := {}

# Server only.
var _hp := {}            # peer -> int
var _gear := {}          # peer -> {"weapon": slot, "offhand": slot, "armor": slot}
var _bodies := {}        # peer -> Vector2 (dead players only)
var _ready_at := {}      # peer -> msec when they may attack again
var _hurt_at := {}       # peer -> msec they were last hurt
var _arrows := {}        # id -> Vector2
var _next_arrow := 1
var _regen_left := 1.0
var _sync_left := 0.0


func _process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server() or not Server.running:
		return
	_regen_left -= delta
	if _regen_left <= 0.0:
		_regen_left = 1.0
		_regenerate()
	_sync_left -= delta
	if _sync_left <= 0.0:
		_sync_left = MOB_SYNC_SECONDS
		_sync_mobs()


# --- Questions anyone can ask ---

func is_dead(peer_id: int) -> bool:
	return dead.has(peer_id) or _bodies.has(peer_id)


func max_health(_peer_id: int) -> int:
	return BASE_HEALTH


## Bag-style slot of what this player wears in a slot (server).
func gear_of(peer_id: int, slot: String) -> Dictionary:
	return _gear.get(peer_id, {}).get(slot, {})


## Total armor from everything worn (server).
func armor_of(peer_id: int) -> int:
	var total := 0
	for slot: String in SLOTS:
		total += int(_stats(gear_of(peer_id, slot)).get("armor", 0))
	return total


## Living players and their characters (server): [[peer, node], ...].
func living_players() -> Array:
	var result: Array = []
	for peer: int in _hp:
		var node := Server.player_node(peer)
		if node != null and not _bodies.has(peer):
			result.append([peer, node])
	return result


# --- Joining, leaving and saving (server) ---

func player_joined(peer_id: int, record: Dictionary) -> void:
	_gear[peer_id] = {"weapon": {}, "offhand": {}, "armor": {}}
	var saved_gear: Dictionary = record.get("equipment", {})
	for slot: String in SLOTS:
		var item: Variant = saved_gear.get(slot, {})
		if item is Dictionary and GameData.items.has(str(item.get("id", ""))):
			_gear[peer_id][slot] = {"id": str(item.id), "count": 1, "data": item.get("data", {})}
	_hp[peer_id] = clampi(int(record.get("health", max_health(peer_id))), 0, max_health(peer_id))
	var body: Variant = record.get("dead", null)
	if body is Array and body.size() == 2:
		_bodies[peer_id] = Vector2(float(body[0]), float(body[1]))
	elif _hp[peer_id] <= 0:
		_hp[peer_id] = max_health(peer_id)
	# Tell the newcomer about everyone, and everyone about the newcomer.
	for other: int in _hp:
		if other != peer_id:
			_call_on(peer_id, "_receive_health", [other, _hp[other], max_health(other)])
			_call_on(peer_id, "_receive_dead", [other, _bodies.has(other), _bodies.get(other, Vector2.ZERO)])
	_call_on(peer_id, "_receive_ground_arrows", [_arrows])
	_send_gear(peer_id)
	_broadcast_health(peer_id)
	_broadcast_dead(peer_id)


func player_record(peer_id: int) -> Dictionary:
	var gear := {}
	for slot: String in SLOTS:
		gear[slot] = gear_of(peer_id, slot).duplicate(true)
	var body: Variant = null
	if _bodies.has(peer_id):
		body = [_bodies[peer_id].x, _bodies[peer_id].y]
	return {"health": int(_hp.get(peer_id, max_health(peer_id))), "equipment": gear, "dead": body}


func player_left(peer_id: int) -> void:
	for table: Dictionary in [_hp, _gear, _bodies, _ready_at, _hurt_at]:
		table.erase(peer_id)
	_rpc_all("_receive_dead", [peer_id, false, Vector2.ZERO])
	_rpc_all("_receive_health", [peer_id, 0, 0])


## Testing and tests: back to full health and alive where you stand.
func reset_player(peer_id: int) -> void:
	_bodies.erase(peer_id)
	_hp[peer_id] = max_health(peer_id)
	_broadcast_dead(peer_id)
	_broadcast_health(peer_id)


# --- Requests from players (each runs on the server) ---

## R: attack in a direction with whatever weapon you hold.
@rpc("any_peer", "call_local", "reliable")
func request_attack(direction: Vector2) -> void:
	if not multiplayer.is_server():
		return
	var peer := Server.sender()
	var node := Server.player_node(peer)
	if node == null or _bodies.has(peer) or not _hp.has(peer):
		return
	var weapon := gear_of(peer, "weapon")
	if weapon.is_empty():
		Server.toast(peer, "Equip a weapon first: click it in your bag (I)")
		return
	var now := Time.get_ticks_msec()
	if now < int(_ready_at.get(peer, 0)) - 80:
		return
	var stats := _stats(weapon)
	_ready_at[peer] = now + int(attack_seconds(weapon) * 1000.0)
	direction = direction.normalized() if direction.length() > 0.01 else Vector2.RIGHT
	var damage := int(stats.get("damage", 1))
	if bool(GameData.get_item(weapon.id).get("ranged", false)):
		_shoot(peer, node, direction, damage)
	else:
		_swing(peer, node, direction, damage, float(GameData.get_item(weapon.id).get("reach", DEFAULT_REACH)))


## Wear the item in this bag slot. Whatever was worn there goes back in the bag.
@rpc("any_peer", "call_local", "reliable")
func request_equip(bag_index: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := Server.sender()
	var bag := Server.bag_of(peer)
	if bag == null or not _gear.has(peer) or bag_index < 0 or bag_index >= bag.slots.size():
		return
	var item: Dictionary = bag.slots[bag_index]
	var slot := str(GameData.get_item(item.id).get("slot", ""))
	if slot not in SLOTS:
		return
	bag.slots.remove_at(bag_index)
	var old := gear_of(peer, slot)
	_gear[peer][slot] = {"id": item.id, "count": 1, "data": item.data}
	if not old.is_empty():
		bag.slots.insert(bag_index, old)
	Server.send_bag(peer)
	_send_gear(peer)


## Take off what's worn in a slot and put it in the bag.
@rpc("any_peer", "call_local", "reliable")
func request_unequip(slot: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := Server.sender()
	var bag := Server.bag_of(peer)
	var item := gear_of(peer, slot)
	if bag == null or item.is_empty():
		return
	if not bag.has_space_for(item.id, 1, item.data):
		Server.toast(peer, "No room in your bag")
		return
	bag.add_item(item.id, 1, item.data)
	_gear[peer][slot] = {}
	Server.send_bag(peer)
	_send_gear(peer)


## Use something from the bag, like a healing salve.
@rpc("any_peer", "call_local", "reliable")
func request_use_item(bag_index: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := Server.sender()
	var bag := Server.bag_of(peer)
	if bag == null or bag_index < 0 or bag_index >= bag.slots.size() or _bodies.has(peer):
		return
	var id := str(bag.slots[bag_index].id)
	var heal := int(GameData.get_item(id).get("heal", 0))
	if heal <= 0:
		return
	if int(_hp.get(peer, 0)) >= max_health(peer):
		Server.toast(peer, "Already at full health")
		return
	bag.remove_item(id, 1)
	_hp[peer] = mini(int(_hp[peer]) + heal, max_health(peer))
	Server.send_bag(peer)
	_broadcast_health(peer)
	Server.toast(peer, "+%d health" % heal)


## E next to an arrow on the ground.
@rpc("any_peer", "call_local", "reliable")
func request_pickup_arrow(arrow_id: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := Server.sender()
	var node := Server.player_node(peer)
	var bag := Server.bag_of(peer)
	if node == null or bag == null or not _arrows.has(arrow_id) or _bodies.has(peer):
		return
	if node.global_position.distance_to(_arrows[arrow_id]) > Server.MAX_USE_DISTANCE:
		return
	if bag.add_item("arrow", 1) > 0:
		Server.toast(peer, "No room in your bag")
		return
	_arrows.erase(arrow_id)
	Server.send_bag(peer)
	_rpc_all("_receive_ground_arrows", [_arrows])


## E next to your own body while you're a spirit.
@rpc("any_peer", "call_local", "reliable")
func request_resurrect() -> void:
	if not multiplayer.is_server():
		return
	var peer := Server.sender()
	var node := Server.player_node(peer)
	if node == null or not _bodies.has(peer):
		return
	if node.global_position.distance_to(_bodies[peer]) > RESURRECT_DISTANCE:
		Server.toast(peer, "Walk right up to your body")
		return
	_bodies.erase(peer)
	_hp[peer] = maxi(1, int(max_health(peer) * RESURRECT_HEALTH_SHARE))
	_hurt_at[peer] = Time.get_ticks_msec()
	_broadcast_dead(peer)
	_broadcast_health(peer)
	Server.toast(peer, "You're back!")


# --- Damage (server) ---

## A creature hurts a player. Armor takes some of it off.
func hurt_player(peer_id: int, amount: int, by: String) -> void:
	if not _hp.has(peer_id) or _bodies.has(peer_id):
		return
	var taken := maxi(1, amount - armor_of(peer_id) / 3)
	_hp[peer_id] = maxi(int(_hp[peer_id]) - taken, 0)
	_hurt_at[peer_id] = Time.get_ticks_msec()
	_broadcast_health(peer_id)
	if _hp[peer_id] <= 0:
		_kill(peer_id, by)


func _kill(peer_id: int, by: String) -> void:
	var node := Server.player_node(peer_id)
	if node == null:
		return
	_bodies[peer_id] = node.global_position
	Trade.cancel_for(peer_id, "Trade cancelled: %s died" % Server.name_of(peer_id))
	_broadcast_dead(peer_id)
	_call_on(peer_id, "_receive_teleport", [GRAVEYARD])
	Server.toast(peer_id, "You died. Walk back to your body and press E.")
	for other: int in _hp:
		if other != peer_id:
			Server.toast(other, "%s was killed by %s" % [Server.name_of(peer_id), by])


func _swing(peer: int, node: Node2D, direction: Vector2, damage: int, reach: float) -> void:
	var center := node.global_position + direction * reach
	_rpc_all("_receive_swing", [peer, direction])
	for mob: Node2D in get_tree().get_nodes_in_group("mob"):
		if mob.is_alive() and mob.global_position.distance_to(center) <= SWING_RADIUS + mob.size_radius():
			_hit_mob(peer, mob, damage)


func _shoot(peer: int, node: Node2D, direction: Vector2, damage: int) -> void:
	var bag := Server.bag_of(peer)
	if bag == null or not bag.remove_item("arrow", 1):
		Server.toast(peer, "No arrows. Make some in your bag (I)")
		return
	Server.send_bag(peer)
	var from := node.global_position
	var to := from + direction * ARROW_RANGE
	# The first creature along the arrow's path is hit.
	var hit: Node2D = null
	var hit_along := INF
	for mob: Node2D in get_tree().get_nodes_in_group("mob"):
		if not mob.is_alive():
			continue
		var along := (mob.global_position - from).dot(direction)
		if along < 2.0 or along > ARROW_RANGE + mob.size_radius():
			continue
		var off := mob.global_position.distance_to(from + direction * along)
		if off <= ARROW_HIT_RADIUS + mob.size_radius() and along < hit_along:
			hit = mob
			hit_along = along
	if hit != null:
		to = from + direction * minf(hit_along, ARROW_RANGE)
		_rpc_all("_receive_arrow", [from, to])
		_hit_mob(peer, hit, damage)
		return
	_rpc_all("_receive_arrow", [from, to])
	if _is_water(to):
		return
	_arrows[_next_arrow] = to
	_next_arrow += 1
	_rpc_all("_receive_ground_arrows", [_arrows])


func _hit_mob(peer: int, mob: Node2D, damage: int) -> void:
	if mob.take_damage(damage, peer):
		if mob.carcass_item != "":
			Server.toast(peer, "%s down. Press E to %s it." % [mob.display_name, mob.carcass_verb])
		else:
			Server.toast(peer, "You beat the %s" % mob.display_name)


func _regenerate() -> void:
	var now := Time.get_ticks_msec()
	for peer: int in _hp:
		if _bodies.has(peer) or int(_hp[peer]) >= max_health(peer):
			continue
		if now - int(_hurt_at.get(peer, 0)) < REGEN_DELAY_MS:
			continue
		_hp[peer] = mini(int(_hp[peer]) + REGEN_PER_SECOND, max_health(peer))
		_broadcast_health(peer)


func _sync_mobs() -> void:
	var data: Array = []
	for mob: Node2D in get_tree().get_nodes_in_group("mob"):
		if mob.is_alive():
			data.append([Server.path_of(mob), mob.global_position, mob.facing_left])
	if not data.is_empty():
		for peer: int in multiplayer.get_peers():
			_receive_mobs.rpc_id(peer, data)


# --- Messages from the server (each runs on a player's machine) ---

@rpc("authority", "call_local", "reliable")
func _receive_health(peer_id: int, hp: int, max_hp: int) -> void:
	if max_hp <= 0:
		health.erase(peer_id)
	else:
		health[peer_id] = [hp, max_hp]
	health_changed.emit(peer_id)


@rpc("authority", "call_local", "reliable")
func _receive_dead(peer_id: int, is_dead_now: bool, body: Vector2) -> void:
	if is_dead_now:
		dead[peer_id] = body
	else:
		dead.erase(peer_id)
	_update_corpse(peer_id)
	dead_changed.emit(peer_id)


@rpc("authority", "call_local", "reliable")
func _receive_teleport(position: Vector2) -> void:
	var me := get_tree().get_first_node_in_group("local_player") as Node2D
	if me:
		me.teleport(position)


@rpc("authority", "call_local", "reliable")
func _receive_gear(gear: Dictionary) -> void:
	equipment = gear
	equipment_changed.emit()


@rpc("authority", "call_local", "reliable")
func _receive_ground_arrows(arrows: Dictionary) -> void:
	ground_arrows = arrows.duplicate()
	_update_ground_arrows()
	ground_arrows_changed.emit()


@rpc("authority", "call_local", "reliable")
func _receive_arrow(from: Vector2, to: Vector2) -> void:
	var entities := _entities()
	if entities == null or DisplayServer.get_name() == "headless":
		return
	var arrow := Sprite2D.new()
	arrow.texture = preload("res://art/arrow.png")
	arrow.position = from + Vector2(0, -4)
	arrow.rotation = (to - from).angle()
	arrow.z_index = 5
	entities.get_parent().add_child(arrow)
	var tween := arrow.create_tween()
	tween.tween_property(arrow, "position", to + Vector2(0, -4), from.distance_to(to) / ARROW_SPEED)
	tween.tween_callback(arrow.queue_free)


@rpc("authority", "call_local", "reliable")
func _receive_swing(peer_id: int, direction: Vector2) -> void:
	var entities := _entities()
	var node := entities.get_node_or_null(str(peer_id)) as Node2D if entities else null
	if node == null or DisplayServer.get_name() == "headless":
		return
	var slash := preload("res://scripts/world/slash.gd").new()
	slash.direction = direction
	slash.position = Vector2(0, -4)
	node.add_child(slash)


@rpc("authority", "call_remote", "unreliable_ordered")
func _receive_mobs(data: Array) -> void:
	if Server.world == null:
		return
	for entry: Array in data:
		var mob := Server.world.get_node_or_null(str(entry[0]))
		if mob and mob.has_method("set_network_position"):
			mob.set_network_position(entry[1], entry[2])


# --- Bodies and arrows on the ground (every window) ---

func _update_corpse(peer_id: int) -> void:
	var entities := _entities()
	if entities == null:
		return
	var corpse := entities.get_node_or_null("Corpse_%d" % peer_id)
	if not dead.has(peer_id):
		if corpse:
			corpse.queue_free()
		return
	if corpse == null:
		corpse = preload("res://scripts/world/corpse.gd").new()
		corpse.name = "Corpse_%d" % peer_id
		corpse.owner_peer = peer_id
		entities.add_child(corpse)
	corpse.global_position = dead[peer_id]


func _update_ground_arrows() -> void:
	var entities := _entities()
	if entities == null:
		return
	for node: Node in get_tree().get_nodes_in_group("ground_arrow"):
		if not ground_arrows.has(node.arrow_id):
			node.queue_free()
	for id: int in ground_arrows:
		if entities.get_node_or_null("Arrow_%d" % id) == null:
			var arrow := preload("res://scripts/world/ground_arrow.gd").new()
			arrow.name = "Arrow_%d" % id
			arrow.arrow_id = id
			arrow.position = ground_arrows[id]
			entities.add_child(arrow)


# --- Helpers ---

## Seconds between attacks: faster weapons (higher speed) swing sooner.
func attack_seconds(weapon: Dictionary) -> float:
	return clampf(1.2 - int(_stats(weapon).get("speed", 5)) * 0.08, 0.35, 1.2)


func _stats(item: Dictionary) -> Dictionary:
	if item.is_empty():
		return {}
	var data: Dictionary = item.get("data", {})
	if data.has("stats"):
		return data.stats
	return GameData.get_item(item.id).get("stats", {})


func _is_water(point: Vector2) -> bool:
	var ground := Server.world.get_node_or_null("Ground") as TileMapLayer if Server.world else null
	if ground == null:
		return false
	return ground.get_cell_atlas_coords(ground.local_to_map(point)) == Vector2i(3, 0)


func _entities() -> Node:
	return Server.world.get_node_or_null("Entities") if Server.world else null


func _send_gear(peer_id: int) -> void:
	_call_on(peer_id, "_receive_gear", [_gear.get(peer_id, {}).duplicate(true)])


func _broadcast_health(peer_id: int) -> void:
	_rpc_all("_receive_health", [peer_id, int(_hp.get(peer_id, 0)), max_health(peer_id)])


func _broadcast_dead(peer_id: int) -> void:
	_rpc_all("_receive_dead", [peer_id, _bodies.has(peer_id), _bodies.get(peer_id, Vector2.ZERO)])


func _rpc_all(method: StringName, args: Array) -> void:
	callv(method, args)
	for peer: int in multiplayer.get_peers():
		callv("rpc_id", [peer, method] + args)


func _call_on(peer_id: int, method: StringName, args: Array) -> void:
	if peer_id == multiplayer.get_unique_id():
		callv(method, args)
	else:
		callv("rpc_id", [peer_id, method] + args)
