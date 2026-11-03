extends Node
## Plays through the crafting loop as a host (one window) without a screen,
## and reports any failures.
## Run from the 2dmmo folder:  godot --headless --path . res://tests/smoke_test.tscn

const SAVE := "user://test_world.json"

var failures: Array[String] = []
var main: Node
var player: Node2D


func check(condition: bool, what: String) -> void:
	if condition:
		print("  ok   ", what)
	else:
		print("  FAIL ", what)
		failures.append(what)


## Stands the player next to a world object, then asks the server to gather it.
func gather(target: Node2D) -> void:
	player.global_position = target.global_position + Vector2(0, 10)
	Server.request_gather_finish(Server.path_of(target))


func use(target: Node2D) -> void:
	player.global_position = target.global_position + Vector2(0, 10)
	Server.request_use(Server.path_of(target))


func craft(recipe_id: String) -> void:
	Server.request_craft(recipe_id)


func _ready() -> void:
	Net.options = {"host": true, "port": 24691, "save": SAVE, "name": "Smoke"}
	Server.save_path = SAVE
	Server.delete_save()
	Server.check_gather_time = false
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	get_tree().current_scene = main
	for i in 3:
		await get_tree().process_frame
	await get_tree().physics_frame

	print("Data and hosting")
	check(GameData.items.size() >= 9, "items loaded")
	check(GameData.recipes_for_station("workbench").size() == 4, "workbench recipes loaded")
	check(InputMap.has_action("interact"), "controls registered")
	check(Net.mode == "host", "hosting a game")
	player = main.get_node_or_null("Entities/1")
	check(player != null, "host player spawned")
	check(Net.player_name == "Smoke", "host player has its name")
	check(player.is_local(), "host controls its own character")

	print("Gathering")
	var iron: Node2D = main.get_node("Entities/IronRock1")
	var coal: Node2D = main.get_node("Entities/CoalRock1")
	for i in 6:
		gather(iron)
		iron.apply_save_state({"depleted": false})
	for i in 3:
		gather(coal)
		coal.apply_save_state({"depleted": false})
	check(Inventory.count_of("iron_ore") >= 6, "mined iron ore (screen copy of bag updated)")
	check(Inventory.count_of("coal") >= 3, "mined coal")
	gather(iron)
	check(iron.get_interaction() == "", "rock is depleted after mining")
	var ore := Inventory.count_of("iron_ore")
	gather(iron)
	check(Inventory.count_of("iron_ore") == ore, "a depleted rock gives nothing")
	iron.apply_save_state({"depleted": false})
	Server.request_gather_finish(Server.path_of(main.get_node("Entities/IronRock6")))
	check(Inventory.count_of("iron_ore") == ore, "a rock too far away gives nothing")

	print("Forestry")
	var tree: Node2D = main.get_node("Entities/Tree1")
	gather(tree)
	check(Inventory.count_of("log") >= 2, "felled tree gives logs")
	check(Inventory.count_of("sapling") >= 1, "felled tree gives a sapling")
	check(tree.get_interaction() == "use", "tree became a stump")
	var saplings := Inventory.count_of("sapling")
	use(tree)
	check(Inventory.count_of("sapling") == saplings - 1, "planting uses a sapling")
	check(tree.get_prompt().begins_with("Sapling"), "stump became a sapling")
	tree._process(1000.0)
	check(tree.get_interaction() == "gather", "sapling grew back into a tree")
	for i in 3:
		gather(tree)
		use(tree)
		tree._process(1000.0)

	print("Crafting")
	var furnace: Node2D = main.get_node("Entities/Furnace")
	var workbench: Node2D = main.get_node("Entities/Workbench")
	craft("smelt_iron")
	check(Inventory.count_of("iron_ingot") == 0, "crafting away from the station is refused")
	player.global_position = furnace.global_position + Vector2(0, 12)
	while Crafting.can_craft(Inventory.bag, Crafting.find_recipe("smelt_iron")):
		craft("smelt_iron")
	check(Inventory.count_of("iron_ingot") >= 3, "smelted iron ingots")
	player.global_position = workbench.global_position + Vector2(0, 12)
	for i in 3:
		craft("saw_planks")
	craft("carve_handle")
	check(Inventory.count_of("handle") == 2, "carved handles")
	craft("iron_sword")
	check(Inventory.count_of("iron_sword") == 1, "crafted an iron sword")
	craft("wooden_shield")
	check(Inventory.count_of("wooden_shield") == 1, "crafted a wooden shield")
	var bag := Server.bag_of(1)
	var missing := Crafting.craft(bag, {"inputs": {"iron_ingot": 999}, "output": {"item": "iron_sword"}})
	check(not missing.ok, "crafting without materials is refused")

	print("High quality roll")
	var hq := {"id": "t", "inputs": {}, "output": {"item": "iron_sword", "count": 1}, "high_quality_chance": 1.0}
	Crafting.craft(bag, hq)
	var last: Dictionary = bag.slots[-1]
	check(last.data.quality == "high", "forced high quality roll marks the item")
	check(last.data.stats.damage > 10 or last.data.stats.speed > 5, "high quality raised a stat")
	check(last.data.stats.durability == 100, "durability is never boosted")

	print("Saving")
	player.global_position = Vector2(123, 145)
	gather(iron)
	player.global_position = Vector2(123, 145)
	Server.save_world()
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
	check(saved.players.has("Smoke"), "player saved by name")
	check(absf(float(saved.players.Smoke.x) - 123.0) < 0.1, "player position saved")
	check(saved.players.Smoke.inventory.size() == bag.slots.size(), "player bag saved")
	check(saved.world["Entities/IronRock1"].depleted, "depleted rock saved")
	Server.remove_player(1)
	check(main.get_node_or_null("Entities/1") == null or main.get_node("Entities/1").is_queued_for_deletion(), "leaving removes the character")
	Server.running = false
	iron.apply_save_state({"depleted": false})
	Server.start(SAVE)
	check(iron.get_interaction() == "", "depleted rock restored on restart")
	await get_tree().process_frame
	Server.add_player(1, "Smoke")
	await get_tree().process_frame
	player = main.get_node("Entities/1")
	check(player.global_position.distance_to(Vector2(123, 145)) < 0.1, "player position restored on rejoin")
	check(Inventory.count_of("iron_sword") == 2, "crafted gear restored on rejoin")

	print("Interaction from the player")
	player.global_position = iron.global_position + Vector2(0, 12)
	iron.apply_save_state({"depleted": false})
	for i in 10:
		await get_tree().physics_frame
	check(player._target == iron, "player targets the nearest rock")

	Server.delete_save()
	print("")
	if failures.is_empty():
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED" % failures.size())
	get_tree().quit(1 if not failures.is_empty() else 0)
