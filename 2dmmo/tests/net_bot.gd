extends Node
## A pretend player used by tests/net_test.sh. Net adds it when the game is
## started with --bot=miner or --bot=watcher.
##   miner:   mines IronRock1, then stands still next to it.
##   watcher: joins later and checks it sees the same world as the miner.
##   shot:    walks to the workbench and saves a screenshot (needs a display).

var role := ""
var failures := 0
var toasts: Array[String] = []
var player: Node2D
var _zone: Array = []


func check(condition: bool, what: String) -> void:
	print("BOT %s %s %s" % [role, "ok  " if condition else "FAIL", what])
	if not condition:
		failures += 1


func _ready() -> void:
	role = str(Net.options.bot)
	Events.toast.connect(func(text: String) -> void: toasts.append(text))
	Events.local_player_ready.connect(_on_ready_to_play)
	Events.gather_zone.connect(func(_p: String, start: float, width: float) -> void: _zone = [start, width])
	get_tree().create_timer(50.0).timeout.connect(func() -> void:
		print("BOT %s FAIL timed out" % role)
		get_tree().quit(1))


func _on_ready_to_play(local_player: Node2D) -> void:
	player = local_player
	await get_tree().create_timer(0.5).timeout
	if role == "miner":
		await _miner()
	elif role == "shot":
		await _shot()
	else:
		await _watcher()
	print("BOT %s DONE %s" % [role, "PASS" if failures == 0 else "FAIL"])
	get_tree().quit(0 if failures == 0 else 1)


func _world() -> Node:
	return get_tree().current_scene


## Plays the gathering timing game. tap_at is where along the bar to tap
## (0..1); leave it negative to tap in the middle of the zone.
func _gather(target: Node2D, tap_at: float = -1.0) -> void:
	player.global_position = target.global_position + Vector2(0, 10)
	await get_tree().create_timer(0.3).timeout
	var path := Server.path_of(target)
	_zone = []
	Server.request_gather_start.rpc_id(1, path)
	var waited := 0.0
	while _zone.is_empty() and waited < 1.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if _zone.is_empty():
		return
	var ratio: float = tap_at if tap_at >= 0.0 else _zone[0] + _zone[1] / 2.0
	await get_tree().create_timer(ratio * target.gather_duration()).timeout
	Server.request_gather_finish.rpc_id(1, path)
	await get_tree().create_timer(0.5).timeout


func _miner() -> void:
	check(Net.player_name == "Miner", "joined with its name")
	var rock: Node2D = _world().get_node("Entities/IronRock1")
	await _gather(rock, 0.05)
	check(Inventory.count_of("iron_ore") == 0, "tapping outside the zone gathers nothing")
	await _gather(rock)
	check(Inventory.count_of("iron_ore") > 0, "mined iron ore through the server")
	check(rock.get_interaction() == "", "rock shows as depleted for the miner")
	Town.request_join_guild.rpc_id(1, "blacksmith")
	await get_tree().create_timer(0.3).timeout
	check(Town.guild_of("Miner") == "blacksmith", "joined the Blacksmiths")
	var stockpile: Node2D = _world().get_node("Entities/Stockpile")
	player.global_position = stockpile.global_position + Vector2(0, 12)
	await get_tree().create_timer(0.3).timeout
	Town.request_donate.rpc_id(1, Server.path_of(stockpile), "iron_ore", 1)
	await get_tree().create_timer(0.3).timeout
	check(Town.stock_of("iron_ore") == 1, "donated ore to the town")
	# Stay online for the watcher, and accept its trade.
	var waited := 0.0
	while Trade.invite_from == "" and waited < 15.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	check(Trade.invite_from == "Watcher", "got a trade invite from the watcher")
	Trade.request_answer_invite.rpc_id(1, true)
	waited = 0.0
	while (Trade.current.is_empty() or Trade.current.theirs.is_empty()) and waited < 5.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	check(Trade.current.get("theirs", {}).get("coal", 0) == 1, "sees the watcher offering 1 coal")
	Trade.request_accept.rpc_id(1, true)
	waited = 0.0
	while not Trade.current.is_empty() and waited < 5.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	check(Inventory.count_of("coal") == 1, "received the coal in the trade")
	# Fighting over the network.
	var me := multiplayer.get_unique_id()
	check(Combat.health.get(me, [0, 0])[0] == Combat.BASE_HEALTH, "the server told us our health")
	toasts.clear()
	Combat.request_attack.rpc_id(1, Vector2.RIGHT)
	await get_tree().create_timer(0.3).timeout
	check(toasts.any(func(t: String) -> bool: return t.begins_with("Equip a weapon")), "attacking with no weapon is refused")
	var wolf: Node2D = _world().get_node("Entities/Wolf1")
	player.global_position = wolf.global_position + Vector2(8, 0)
	waited = 0.0
	while Combat.health.get(me, [0, 0])[0] >= Combat.BASE_HEALTH and waited < 4.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	check(Combat.health.get(me, [0, 0])[0] < Combat.BASE_HEALTH, "a wolf bit us and our health went down")
	check(wolf.position.distance_to(player.global_position) < 30.0, "we see the wolf where the server has it")
	player.global_position = Server.SPAWN_POINT
	# An invasion, started from this window with F10.
	Invasion.request_start_now.rpc_id(1)
	waited = 0.0
	while Invasion.raiders().is_empty() and waited < 4.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	check(Invasion.state.active and Invasion.state.raiders_left == 3, "F10 started an invasion on the host")
	check(not Invasion.raiders().is_empty(), "we see the raiders arrive")
	var raider: Node2D = Invasion.raiders()[0] if not Invasion.raiders().is_empty() else null
	var raider_start := raider.global_position if raider else Vector2.ZERO
	await get_tree().create_timer(1.0).timeout
	check(raider != null and is_instance_valid(raider) and raider.global_position.distance_to(raider_start) > 5.0, "the raiders move on our screen too")
	await get_tree().create_timer(1.0).timeout


func _watcher() -> void:
	var rock: Node2D = _world().get_node("Entities/IronRock1")
	check(rock.get_interaction() == "", "sees the rock the miner depleted")
	var others: Array = get_tree().get_nodes_in_group("player").filter(
			func(p: Node) -> bool: return p != player)
	check(others.size() == 2, "sees the host and the miner")
	var miner: Node2D = null
	for other: Node2D in others:
		if other.player_name == "Miner":
			miner = other
	check(miner != null, "sees the miner by name")
	if miner:
		await get_tree().create_timer(1.0).timeout
		var stockpile: Node2D = _world().get_node("Entities/Stockpile")
		check(miner.global_position.distance_to(stockpile.global_position) < 20.0, "miner is shown where it really stands")
	check(Town.guild_of("Miner") == "blacksmith" and Town.is_online("Miner"), "sees the miner's guild")
	check(Town.stock_of("iron_ore") == 1, "sees the town stockpile the miner filled")
	check(Town.is_leader("Miner"), "miner leads the Blacksmiths")
	await _gather(rock)
	check(Inventory.count_of("iron_ore") == 0, "cannot mine a depleted rock")
	check(toasts.has("Someone got there first"), "told someone got there first")
	var coal: Node2D = _world().get_node("Entities/CoalRock1")
	await _gather(coal)
	var coal_count := Inventory.count_of("coal")
	check(coal_count > 0, "mined coal through the server")
	if miner == null:
		return
	player.global_position = miner.global_position + Vector2(14, 0)
	await get_tree().create_timer(0.4).timeout
	Trade.request_invite.rpc_id(1, miner.name.to_int())
	var waited := 0.0
	while Trade.current.is_empty() and waited < 5.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	check(Trade.current.get("partner", "") == "Miner", "trade window opened with the miner")
	Trade.request_set_offer.rpc_id(1, "coal", 1)
	await get_tree().create_timer(0.3).timeout
	Trade.request_accept.rpc_id(1, true)
	waited = 0.0
	while not Trade.current.is_empty() and waited < 5.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	check(Trade.current.is_empty() and Inventory.count_of("coal") == coal_count - 1, "trade completed: gave 1 coal")


func _shot() -> void:
	# Screenshot 1: the guild picker, before choosing.
	await get_tree().create_timer(2.0).timeout
	_save_shot("picker")
	var host := Net.mode == "host"
	Town.request_join_guild.rpc_id(1, "blacksmith" if host else "woodworker")
	await get_tree().create_timer(1.0).timeout
	var stockpile: Node2D = _world().get_node("Entities/Stockpile")
	var table: Node2D = _world().get_node("Entities/RoundTable")
	if host:
		# Fill the stockpile, build the watchtower and open a vote on the silo.
		Server.bag_of(1).add_item("log", 30)
		Server.bag_of(1).add_item("plank", 20)
		Server.bag_of(1).add_item("iron_ingot", 6)
		Server.send_bag(1)
		player.global_position = stockpile.global_position + Vector2(0, 12)
		await get_tree().create_timer(0.3).timeout
		for id: String in ["log", "plank", "iron_ingot"]:
			Town.request_donate(Server.path_of(stockpile), id, 99)
		Town.state.players["Ghost"] = {"guild": "tailor", "contribution": 0}
		player.global_position = table.global_position + Vector2(0, 12)
		await get_tree().create_timer(0.3).timeout
		Town.request_propose(Server.path_of(table), "watchtower")
		Town.state.proposal.ends_at = 0.0
		await get_tree().create_timer(1.5).timeout
		Town.request_propose(Server.path_of(table), "silo")
		await get_tree().create_timer(1.0).timeout
		Events.town_object_opened.emit("round_table", "", Server.path_of(table))
	else:
		await get_tree().create_timer(4.0).timeout
		var hall: Node2D = _world().get_node("Entities/Hall_blacksmith")
		player.global_position = hall.global_position + Vector2(0, -14)
		await get_tree().create_timer(0.5).timeout
		Events.town_object_opened.emit("guild_hall", "blacksmith", Server.path_of(hall))
	await get_tree().create_timer(1.5).timeout
	_save_shot("panel")
	Events.town_object_opened.emit("stockpile", "", Server.path_of(stockpile))
	await get_tree().create_timer(0.5).timeout
	_save_shot("stockpile")
	_world().get_node("HUD")._close_all()
	if not host:
		_world().get_node("HUD")._set_crafting_visible(true)
		await get_tree().create_timer(0.5).timeout
		_save_shot("craft")
		_world().get_node("HUD")._close_all()
	player.global_position = Vector2(23 * 16 + 8, (6 if host else 24) * 16 + 8)
	await get_tree().create_timer(1.5).timeout
	_save_shot("fields")
	# Trade: meet in the square; the host invites, the other accepts.
	player.global_position = Vector2(23 * 16 + (0 if host else 14), 15 * 16 + 8)
	if not host:
		Trade.invited.connect(func(from_name: String) -> void:
			if from_name != "":
				Trade.request_answer_invite.rpc_id(1, true), CONNECT_ONE_SHOT)
	await get_tree().create_timer(1.0).timeout
	if host:
		# Wait (up to 10s) for the other window's player to arrive in the square.
		var partner: Node2D = null
		for i in 50:
			for other: Node2D in get_tree().get_nodes_in_group("player"):
				if other != player and other.global_position.distance_to(player.global_position) <= Trade.START_DISTANCE:
					partner = other
			if partner != null:
				break
			await get_tree().create_timer(0.2).timeout
		await get_tree().create_timer(0.5).timeout
		if partner != null:
			Trade.request_invite(partner.name.to_int())
		await get_tree().create_timer(0.8).timeout
		Server.bag_of(1).add_item("log", 4)
		Server.send_bag(1)
		Trade.request_set_offer("log", 3)
		Trade.request_accept(true)
	await get_tree().create_timer(1.5).timeout
	_save_shot("trade")
	await _shot_fight(host)
	# The host stays longer so the other window isn't disconnected mid-shot.
	await get_tree().create_timer(4.0 if host else 1.0).timeout


## Fighting: the host gears up, swings and shoots; the other window is
## killed near the wolves and its spirit appears at the graveyard.
func _shot_fight(host: bool) -> void:
	var hud := _world().get_node("HUD")
	hud._close_all()
	var partner := 0
	for other: Node2D in get_tree().get_nodes_in_group("player"):
		if other != player:
			partner = other.name.to_int()
	var me := multiplayer.get_unique_id()
	if not host:
		var wolf: Node2D = _world().get_node("Entities/Wolf1")
		player.global_position = wolf.global_position + Vector2(10, 0)
		var waited := 0.0
		while not Combat.dead.has(me) and waited < 10.0:
			await get_tree().create_timer(0.1).timeout
			waited += 0.1
		await get_tree().create_timer(0.6).timeout
		_save_shot("spirit")
		await get_tree().create_timer(2.5).timeout
		return
	var bag := Server.bag_of(1)
	bag.add_item("iron_sword", 1, {"quality": "high", "stats": {"damage": 11, "speed": 5, "durability": 100}, "boosted_stat": "damage"})
	bag.add_item("leather_armor", 1, {"quality": "normal", "stats": {"armor": 5, "agility": 4, "durability": 90}})
	bag.add_item("wooden_bow", 1, {"quality": "normal", "stats": {"damage": 7, "speed": 7, "durability": 70}})
	bag.add_item("arrow", 10)
	bag.add_item("healing_salve", 2)
	Server.send_bag(1)
	_equip("iron_sword")
	_equip("leather_armor")
	hud._set_inventory_visible(true)
	await get_tree().create_timer(0.6).timeout
	_save_shot("gear")
	hud._close_all()
	var deer: Node2D = _world().get_node("Entities/Deer3")
	player.global_position = deer.global_position + Vector2(-12, 0)
	await get_tree().create_timer(0.4).timeout
	Combat.request_attack(Vector2.RIGHT)
	_equip("wooden_bow")
	Combat._ready_at.clear()
	Combat.request_attack(Vector2.LEFT)
	await get_tree().create_timer(0.5).timeout
	_equip("iron_sword")
	Combat._ready_at.clear()
	Combat.request_attack(Vector2.RIGHT)
	await get_tree().create_timer(0.04).timeout
	_save_shot("fight")
	await get_tree().create_timer(1.0).timeout
	Combat.hurt_player(partner, 999, "a Wolf")
	await get_tree().create_timer(0.3).timeout
	if Combat._bodies.has(partner):
		player.global_position = Combat._bodies[partner] + Vector2(-24, 8)
	await get_tree().create_timer(0.8).timeout
	_save_shot("body")
	# An invasion at the east gate, with a palisade and watchtower built.
	Town.state.built = ["palisade", "watchtower", "silo"]
	Town.publish()
	Invasion.start()
	while Invasion._to_spawn > 0:
		Invasion._spawn_left = 0.0
		await get_tree().physics_frame
	var raiders := Invasion.raiders()
	for i in raiders.size():
		raiders[i].global_position = Invasion.GATES[1] + Vector2(10 + i * 14, (i % 2) * 6 - 3)
	player.global_position = Invasion.GATES[1] + Vector2(-20, 10)
	_equip("wooden_bow")
	await get_tree().create_timer(2.5).timeout
	Combat._ready_at.clear()
	Combat.request_attack(Vector2.RIGHT)
	await get_tree().create_timer(0.1).timeout
	_save_shot("invasion")


func _equip(id: String) -> void:
	var bag := Server.bag_of(1)
	for i in bag.slots.size():
		if bag.slots[i].id == id:
			Combat.request_equip(i)
			return


func _save_shot(label: String) -> void:
	var path := "user://shot_%s_%s.png" % [Net.player_name, label]
	get_viewport().get_texture().get_image().save_png(path)
	print("BOT shot saved ", ProjectSettings.globalize_path(path))
