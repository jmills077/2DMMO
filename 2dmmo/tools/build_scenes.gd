extends Node
## Generates the prototype's scenes and tile set.
## Run from the 2dmmo folder:
##   godot --headless --path . res://tools/build_scenes.tscn
## (or open tools/build_scenes.tscn in the editor and press F6)
## After the first run, scenes can be edited normally in the Godot editor.
## Running this again overwrites scenes/ and art/terrain_tileset.tres.

const TILE := 16
const MAP_W := 48
const MAP_H := 30

# Terrain atlas columns in art/terrain.png
const GRASS := Vector2i(0, 0)
const FLOWERS := Vector2i(1, 0)
const PATH := Vector2i(2, 0)
const WATER := Vector2i(3, 0)
const FLOOR := Vector2i(4, 0)

# Physics layers: 1 = solid world, 2 = interactable, 3 = player
const LAYER_SOLID := 1
const LAYER_INTERACT := 2
const LAYER_PLAYER := 4


func _ready() -> void:
	var tileset := _build_tileset()
	ResourceSaver.save(tileset, "res://art/terrain_tileset.tres")
	_save(_build_player(), "res://scenes/player.tscn")
	_save(_build_ore_rock(), "res://scenes/ore_rock.tscn")
	_save(_build_tree(), "res://scenes/tree.tscn")
	_save(_build_station(), "res://scenes/station.tscn")
	_save(_build_town_object(), "res://scenes/town_object.tscn")
	_save(_build_main(load("res://art/terrain_tileset.tres")), "res://scenes/main.tscn")
	print("Scenes built.")
	get_tree().quit()


func _save(root: Node, path: String) -> void:
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		push_error("Could not pack %s: %s" % [path, err])
		return
	err = ResourceSaver.save(packed, path)
	if err != OK:
		push_error("Could not save %s: %s" % [path, err])
	root.free()


func _own(node: Node, owner_node: Node) -> void:
	node.owner = owner_node


func _add(parent: Node, child: Node, owner_node: Node) -> Node:
	parent.add_child(child)
	child.owner = owner_node
	return child


func _rect_shape(size: Vector2, offset: Vector2) -> CollisionShape2D:
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	shape.position = offset
	return shape


func _build_tileset() -> TileSet:
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(TILE, TILE)
	tileset.add_physics_layer()
	tileset.set_physics_layer_collision_layer(0, LAYER_SOLID)
	var source := TileSetAtlasSource.new()
	source.texture = load("res://art/terrain.png")
	source.texture_region_size = Vector2i(TILE, TILE)
	for coords: Vector2i in [GRASS, FLOWERS, PATH, WATER, FLOOR]:
		source.create_tile(coords)
	tileset.add_source(source, 0)
	var water := source.get_tile_data(WATER, 0)
	water.add_collision_polygon(0)
	var h := TILE / 2.0
	water.set_collision_polygon_points(0, 0, PackedVector2Array([
		Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)]))
	return tileset


func _build_player() -> Node:
	var player := CharacterBody2D.new()
	player.name = "Player"
	player.set_script(load("res://scripts/player.gd"))
	player.collision_layer = LAYER_PLAYER
	player.collision_mask = LAYER_SOLID
	player.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING

	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.texture = load("res://art/player.png")
	sprite.position = Vector2(0, -4)
	_add(player, sprite, player)
	_add(player, _rect_shape(Vector2(8, 5), Vector2(0, 2)), player)

	var camera := Camera2D.new()
	camera.name = "Camera2D"
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = MAP_W * TILE
	camera.limit_bottom = MAP_H * TILE
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	_add(player, camera, player)

	# Sends this character's position to the other windows. The player who
	# controls the character owns it (set in player.gd).
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	var config := SceneReplicationConfig.new()
	for property: String in [".:sync_position", ".:facing_left"]:
		config.add_property(NodePath(property))
		config.property_set_spawn(NodePath(property), true)
		config.property_set_replication_mode(NodePath(property),
				SceneReplicationConfig.REPLICATION_MODE_ALWAYS if property == ".:sync_position"
				else SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	sync.replication_config = config
	_add(player, sync, player)

	return player


func _static_body(name: String, script_path: String) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = name
	body.set_script(load(script_path))
	body.collision_layer = LAYER_SOLID | LAYER_INTERACT
	body.collision_mask = 0
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	_add(body, sprite, body)
	return body


func _build_ore_rock() -> Node:
	var rock := _static_body("OreRock", "res://scripts/world/ore_rock.gd")
	rock.set("full_texture", load("res://art/iron_rock.png"))
	rock.set("depleted_texture", load("res://art/rock_depleted.png"))
	(rock.get_node("Sprite2D") as Sprite2D).texture = load("res://art/iron_rock.png")
	_add(rock, _rect_shape(Vector2(12, 7), Vector2(0, 3)), rock)
	return rock


func _build_tree() -> Node:
	var tree := _static_body("Tree", "res://scripts/world/tree.gd")
	var sprite := tree.get_node("Sprite2D") as Sprite2D
	sprite.texture = load("res://art/tree.png")
	sprite.position = Vector2(0, -8)
	_add(tree, _rect_shape(Vector2(6, 5), Vector2(0, 5)), tree)
	return tree


func _build_station() -> Node:
	var station := _static_body("Station", "res://scripts/world/station.gd")
	station.set("texture", load("res://art/workbench.png"))
	(station.get_node("Sprite2D") as Sprite2D).texture = load("res://art/workbench.png")
	_add(station, _rect_shape(Vector2(14, 9), Vector2(0, 2)), station)
	return station


func _build_town_object() -> Node:
	var thing := _static_body("TownObject", "res://scripts/world/town_object.gd")
	thing.set("texture", load("res://art/stockpile.png"))
	(thing.get_node("Sprite2D") as Sprite2D).texture = load("res://art/stockpile.png")
	var cloth := Sprite2D.new()
	cloth.name = "Cloth"
	cloth.texture = load("res://art/banner_cloth.png")
	cloth.visible = false
	_add(thing, cloth, thing)
	_add(thing, _rect_shape(Vector2(12, 6), Vector2(0, 4)), thing)
	return thing


func _tile_center(cell: Vector2i) -> Vector2:
	return Vector2(cell * TILE) + Vector2(TILE, TILE) / 2.0


func _build_main(tileset: TileSet) -> Node:
	var main := Node2D.new()
	main.name = "Main"
	main.set_script(load("res://scripts/world/main.gd"))

	var ground := TileMapLayer.new()
	ground.name = "Ground"
	ground.tile_set = tileset
	_add(main, ground, main)
	_paint_ground(ground)

	var entities := Node2D.new()
	entities.name = "Entities"
	entities.y_sort_enabled = true
	_add(main, entities, main)

	# Players are added while the game runs (see main.gd and server.gd).
	var spawner := MultiplayerSpawner.new()
	spawner.name = "PlayerSpawner"
	_add(main, spawner, main)
	spawner.spawn_path = spawner.get_path_to(entities)

	var station_scene: PackedScene = load("res://scenes/station.tscn")
	var furnace: Node2D = station_scene.instantiate()
	furnace.name = "Furnace"
	furnace.set("station_id", "furnace")
	furnace.set("display_name", "Furnace")
	furnace.set("texture", load("res://art/furnace.png"))
	furnace.position = _tile_center(Vector2i(21, 13))
	_add(entities, furnace, main)
	var workbench: Node2D = station_scene.instantiate()
	workbench.name = "Workbench"
	workbench.set("station_id", "workbench")
	workbench.set("display_name", "Workbench")
	workbench.position = _tile_center(Vector2i(26, 13))
	_add(entities, workbench, main)

	# Town: stockpile, round table, and a banner for each guild hall.
	var town_scene: PackedScene = load("res://scenes/town_object.tscn")
	var stockpile: Node2D = town_scene.instantiate()
	stockpile.name = "Stockpile"
	stockpile.position = _tile_center(Vector2i(19, 13))
	_add(entities, stockpile, main)
	var table: Node2D = town_scene.instantiate()
	table.name = "RoundTable"
	table.set("kind", "round_table")
	table.set("display_name", "Round Table")
	table.set("texture", load("res://art/round_table.png"))
	(table.get_node("Sprite2D") as Sprite2D).texture = load("res://art/round_table.png")
	table.position = _tile_center(Vector2i(23, 12))
	_add(entities, table, main)
	var guild_ids := ["blacksmith", "woodworker", "tailor", "leatherworker", "apothecary", "engineer"]
	for i in guild_ids.size():
		var banner: Node2D = town_scene.instantiate()
		banner.name = "Hall_%s" % guild_ids[i]
		banner.set("kind", "guild_hall")
		banner.set("guild_id", guild_ids[i])
		banner.set("display_name", "Guild Hall")
		banner.set("texture", load("res://art/banner_pole.png"))
		(banner.get_node("Sprite2D") as Sprite2D).texture = load("res://art/banner_pole.png")
		banner.position = _tile_center(Vector2i(19 + i * 2, 19))
		_add(entities, banner, main)

	# Guild stations: loom (tailors), tanning rack (leatherworkers), brewing stand (apothecaries).
	for spec: Array in [["Loom", "loom", "Loom", Vector2i(20, 17)],
			["TanningRack", "tanning_rack", "Tanning Rack", Vector2i(27, 17)],
			["BrewingStand", "brewing_stand", "Brewing Stand", Vector2i(28, 13)]]:
		var station: Node2D = station_scene.instantiate()
		station.name = spec[0]
		station.set("station_id", spec[1])
		station.set("display_name", spec[2])
		station.set("texture", load("res://art/%s.png" % spec[1]))
		station.position = _tile_center(spec[3])
		_add(entities, station, main)

	var tree_scene: PackedScene = load("res://scenes/tree.tscn")
	var trees := [
		Vector2i(3, 4), Vector2i(6, 3), Vector2i(9, 5), Vector2i(12, 4), Vector2i(4, 8),
		Vector2i(8, 9), Vector2i(13, 8), Vector2i(5, 12), Vector2i(10, 12), Vector2i(14, 11),
		Vector2i(3, 18), Vector2i(7, 19), Vector2i(11, 18), Vector2i(4, 22), Vector2i(9, 23),
		Vector2i(13, 21), Vector2i(6, 26), Vector2i(12, 26),
	]
	for i in trees.size():
		var tree: Node2D = tree_scene.instantiate()
		tree.name = "Tree%d" % (i + 1)
		tree.position = _tile_center(trees[i])
		_add(entities, tree, main)

	var rock_scene: PackedScene = load("res://scenes/ore_rock.tscn")
	var iron := [Vector2i(38, 5), Vector2i(42, 7), Vector2i(39, 10), Vector2i(44, 12),
		Vector2i(40, 19), Vector2i(43, 23)]
	for i in iron.size():
		var rock: Node2D = rock_scene.instantiate()
		rock.name = "IronRock%d" % (i + 1)
		rock.position = _tile_center(iron[i])
		_add(entities, rock, main)
	var coal := [Vector2i(41, 4), Vector2i(37, 13), Vector2i(42, 17), Vector2i(38, 24)]
	for i in coal.size():
		var rock: Node2D = rock_scene.instantiate()
		rock.name = "CoalRock%d" % (i + 1)
		rock.set("display_name", "Coal Rock")
		rock.set("item_id", "coal")
		rock.set("full_texture", load("res://art/coal_rock.png"))
		(rock.get_node("Sprite2D") as Sprite2D).texture = load("res://art/coal_rock.png")
		rock.position = _tile_center(coal[i])
		_add(entities, rock, main)

	# Pasture north of town: sheep. Meadow south of town: deer. Herbs at the forest edges.
	var critters := [
		["Sheep", "Sheep", "wool", "shear", 2.0, 60.0, 2, 3, "sheep", "sheep_sheared",
			[Vector2i(18, 4), Vector2i(21, 6), Vector2i(24, 3), Vector2i(27, 5), Vector2i(29, 7)]],
		["Deer", "Deer", "hide", "hunt", 2.5, 90.0, 1, 2, "deer", "",
			[Vector2i(18, 24), Vector2i(22, 26), Vector2i(26, 23), Vector2i(29, 26)]],
		["Herb", "Herbs", "herb", "pick", 1.0, 40.0, 1, 3, "herb", "herb_picked",
			[Vector2i(15, 3), Vector2i(16, 8), Vector2i(15, 21), Vector2i(16, 26), Vector2i(31, 22), Vector2i(31, 4)]],
	]
	for spec: Array in critters:
		var cells: Array = spec[10]
		for i in cells.size():
			var node: Node2D = rock_scene.instantiate()
			node.name = "%s%d" % [spec[0], i + 1]
			node.set("display_name", spec[1])
			node.set("item_id", spec[2])
			node.set("verb", spec[3])
			node.set("gather_seconds", spec[4])
			node.set("respawn_seconds", spec[5])
			node.set("yield_min", spec[6])
			node.set("yield_max", spec[7])
			var full: Texture2D = load("res://art/%s.png" % spec[8])
			node.set("full_texture", full)
			if spec[9] != "":
				node.set("depleted_texture", load("res://art/%s.png" % spec[9]))
			else:
				node.set("hide_when_depleted", true)
			(node.get_node("Sprite2D") as Sprite2D).texture = full
			node.position = _tile_center(cells[i])
			_add(entities, node, main)

	var hud := CanvasLayer.new()
	hud.name = "HUD"
	hud.set_script(load("res://scripts/ui/hud.gd"))
	_add(main, hud, main)
	return main


func _paint_ground(ground: TileMapLayer) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	for y in MAP_H:
		for x in MAP_W:
			var cell := Vector2i(x, y)
			var tile := FLOWERS if rng.randf() < 0.08 else GRASS
			var border := x == 0 or y == 0 or x == MAP_W - 1 or y == MAP_H - 1
			var river := x >= 33 and x <= 34
			if border or river:
				tile = WATER
			if y == 15 and x >= 1 and x <= MAP_W - 2:
				tile = PATH
			if x >= 18 and x <= 29 and y >= 11 and y <= 19:
				tile = FLOOR
			ground.set_cell(cell, 0, tile)
