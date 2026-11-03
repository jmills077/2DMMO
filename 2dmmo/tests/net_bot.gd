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


func check(condition: bool, what: String) -> void:
	print("BOT %s %s %s" % [role, "ok  " if condition else "FAIL", what])
	if not condition:
		failures += 1


func _ready() -> void:
	role = str(Net.options.bot)
	Events.toast.connect(func(text: String) -> void: toasts.append(text))
	Events.local_player_ready.connect(_on_ready_to_play)
	get_tree().create_timer(30.0).timeout.connect(func() -> void:
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


func _gather(target: Node2D, hold_seconds: float) -> void:
	player.global_position = target.global_position + Vector2(0, 10)
	await get_tree().create_timer(0.3).timeout
	var path := Server.path_of(target)
	Server.request_gather_start.rpc_id(1, path)
	await get_tree().create_timer(hold_seconds).timeout
	Server.request_gather_finish.rpc_id(1, path)
	await get_tree().create_timer(0.5).timeout


func _miner() -> void:
	check(Net.player_name == "Miner", "joined with its name")
	var rock: Node2D = _world().get_node("Entities/IronRock1")
	await _gather(rock, 0.2)
	check(Inventory.count_of("iron_ore") == 0, "gathering too fast is refused")
	await _gather(rock, 1.6)
	check(Inventory.count_of("iron_ore") > 0, "mined iron ore through the server")
	check(rock.get_interaction() == "", "rock shows as depleted for the miner")
	# Stay online so the watcher can see this character.
	await get_tree().create_timer(8.0).timeout


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
		check(miner.global_position.distance_to(rock.global_position) < 20.0, "miner is shown where it really stands")
	await _gather(rock, 1.6)
	check(Inventory.count_of("iron_ore") == 0, "cannot mine a depleted rock")
	check(toasts.has("Someone got there first"), "told someone got there first")
	var coal: Node2D = _world().get_node("Entities/CoalRock1")
	await _gather(coal, 1.6)
	check(Inventory.count_of("coal") > 0, "mined coal through the server")


func _shot() -> void:
	var bench: Node2D = _world().get_node("Entities/Workbench")
	var offset := Vector2(-12, 16) if Net.mode == "host" else Vector2(12, 16)
	player.global_position = bench.global_position + offset
	await get_tree().create_timer(4.0).timeout
	var path := "user://shot_%s.png" % Net.player_name
	get_viewport().get_texture().get_image().save_png(path)
	print("BOT shot saved ", ProjectSettings.globalize_path(path))
	await get_tree().create_timer(2.0).timeout
