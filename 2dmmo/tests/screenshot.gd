extends Node
## Takes screenshots of the game for checking layout. Needs a real display.

func _ready() -> void:
	SaveGame.delete_save()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	get_tree().current_scene = main
	var player: Node2D = main.get_node("Entities/Player")
	var tree: Node2D = main.get_node("Entities/Tree9")
	player.global_position = tree.global_position + Vector2(0, 14)
	for i in 40: await get_tree().process_frame
	_shot("user://shot_forest.png")
	player.global_position = main.get_node("Entities/IronRock3").global_position + Vector2(-14, 4)
	for i in 40: await get_tree().process_frame
	_shot("user://shot_hills.png")
	for i in 5:
		Inventory.add_item("iron_ore", 4); Inventory.add_item("coal", 2); Inventory.add_item("log", 3)
	Crafting.craft({"inputs": {}, "output": {"item": "iron_sword"}, "high_quality_chance": 1.0})
	player.global_position = main.get_node("Entities/Workbench").global_position + Vector2(0, 14)
	for i in 30: await get_tree().process_frame
	Events.station_opened.emit("workbench", "Workbench")
	for i in 10: await get_tree().process_frame
	_shot("user://shot_craft.png")
	SaveGame.delete_save()
	get_tree().quit()

func _shot(path: String) -> void:
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
