extends Node
## Plays through the milestone 1 loop without a window and reports any failures.
## Run from the 2dmmo folder:  godot --headless --path . res://tests/smoke_test.tscn

var failures: Array[String] = []


func check(condition: bool, what: String) -> void:
	if condition:
		print("  ok   ", what)
	else:
		print("  FAIL ", what)
		failures.append(what)


func _ready() -> void:
	SaveGame.delete_save()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	get_tree().current_scene = main
	await get_tree().process_frame
	await get_tree().physics_frame

	print("Data")
	check(GameData.items.size() >= 9, "items loaded")
	check(GameData.recipes_for_station("workbench").size() == 4, "workbench recipes loaded")
	check(InputMap.has_action("interact"), "controls registered")

	print("Gathering")
	var iron: Node = main.get_node("Entities/IronRock1")
	var coal: Node = main.get_node("Entities/CoalRock1")
	for i in 6:
		iron.gather()
		iron.apply_save_state({"depleted": false})
	for i in 3:
		coal.gather()
		coal.apply_save_state({"depleted": false})
	check(Inventory.count_of("iron_ore") >= 6, "mined iron ore")
	check(Inventory.count_of("coal") >= 3, "mined coal")
	iron.gather()
	check(iron.get_interaction() == "", "rock is depleted after mining")

	print("Forestry")
	var tree: Node = main.get_node("Entities/Tree1")
	tree.gather()
	check(Inventory.count_of("log") >= 2, "felled tree gives logs")
	check(Inventory.count_of("sapling") >= 1, "felled tree gives a sapling")
	check(tree.get_interaction() == "use", "tree became a stump")
	var saplings := Inventory.count_of("sapling")
	tree.use()
	check(Inventory.count_of("sapling") == saplings - 1, "planting uses a sapling")
	check(tree.get_prompt().begins_with("Sapling"), "stump became a sapling")
	tree._process(1000.0)
	check(tree.get_interaction() == "gather", "sapling grew back into a tree")
	for i in 3:
		tree.gather()
		tree.use()
		tree._process(1000.0)

	print("Crafting")
	var recipes := {}
	for r: Dictionary in GameData.recipes:
		recipes[r.id] = r
	while Crafting.can_craft(recipes.smelt_iron):
		Crafting.craft(recipes.smelt_iron)
	check(Inventory.count_of("iron_ingot") >= 3, "smelted iron ingots")
	Crafting.craft(recipes.saw_planks)
	Crafting.craft(recipes.saw_planks)
	Crafting.craft(recipes.saw_planks)
	Crafting.craft(recipes.carve_handle)
	check(Inventory.count_of("handle") == 2, "carved handles")
	var sword := Crafting.craft(recipes.iron_sword)
	check(sword.ok and Inventory.count_of("iron_sword") == 1, "crafted an iron sword")
	var shield := Crafting.craft(recipes.wooden_shield)
	check(shield.ok and Inventory.count_of("wooden_shield") == 1, "crafted a wooden shield")
	var missing := Crafting.craft({"inputs": {"iron_ingot": 999}, "output": {"item": "iron_sword"}})
	check(not missing.ok, "crafting without materials is refused")

	print("High quality roll")
	var hq := {"id": "t", "inputs": {}, "output": {"item": "iron_sword", "count": 1}, "high_quality_chance": 1.0}
	Crafting.craft(hq)
	var last: Dictionary = Inventory.slots[-1]
	check(last.data.quality == "high", "forced high quality roll marks the item")
	check(last.data.stats.damage > 10 or last.data.stats.speed > 5, "high quality raised a stat")
	check(last.data.stats.durability == 100, "durability is never boosted")

	print("Save and load")
	var player: Node2D = main.get_node("Entities/Player")
	player.global_position = Vector2(123, 145)
	var before := Inventory.slots.duplicate(true)
	SaveGame.save_game(false)
	Inventory.load_save_data([])
	player.global_position = Vector2.ZERO
	iron.apply_save_state({"depleted": false})
	check(SaveGame.load_game(), "save file loads")
	check(player.global_position.distance_to(Vector2(123, 145)) < 0.1, "player position restored")
	check(Inventory.slots.size() == before.size(), "inventory restored")
	check(Inventory.count_of("iron_sword") == 2, "crafted gear restored")
	check(iron.get_interaction() == "", "depleted rock restored")

	print("Interaction from the player")
	player.global_position = iron.global_position + Vector2(0, 12)
	iron.apply_save_state({"depleted": false})
	for i in 10:
		await get_tree().physics_frame
	check(player._target == iron, "player targets the nearest rock")

	SaveGame.delete_save()
	print("")
	if failures.is_empty():
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED" % failures.size())
	get_tree().quit(1 if not failures.is_empty() else 0)
