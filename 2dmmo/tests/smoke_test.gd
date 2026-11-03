extends Node
## Plays through the crafting loop as a host (one window) without a screen,
## and reports any failures.
## Run from the 2dmmo folder:  godot --headless --path . res://tests/smoke_test.tscn

const SAVE := "user://test_world.json"
const Bag := preload("res://scripts/bag.gd")

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


## Tests switch guilds freely; real players choose once.
func as_guild(guild_id: String) -> void:
	if guild_id == "":
		Town.state.players.erase("Smoke")
	else:
		Town.state.players["Smoke"] = {"guild": guild_id, "contribution": 0}


## Presses and releases E for one physics frame.
func tap_interact() -> void:
	Input.action_press("interact")
	await get_tree().physics_frame
	Input.action_release("interact")
	await get_tree().physics_frame


func use_spot(target: Node2D) -> void:
	player.global_position = target.global_position + Vector2(0, 12)


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
	check(GameData.recipes_for_guild("woodworker").size() == 4, "woodworker recipes loaded")
	check(InputMap.has_action("interact") and InputMap.has_action("crafting"), "controls registered")
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
	as_guild("blacksmith")
	player.global_position = Vector2(60, 60)
	while Crafting.can_craft(Inventory.bag, Crafting.find_recipe("smelt_iron")):
		craft("smelt_iron")
	check(Inventory.count_of("iron_ingot") >= 3, "blacksmith smelted iron ingots, away from any station")
	check(Town.known_recipes("Smoke").size() == 2, "a blacksmith knows the 2 blacksmith recipes")
	craft("saw_planks")
	check(Inventory.count_of("plank") == 0, "a blacksmith can't use woodworker recipes")
	as_guild("woodworker")
	for i in 3:
		craft("saw_planks")
	craft("carve_handle")
	check(Inventory.count_of("handle") == 2, "woodworker carved handles")
	craft("wooden_shield")
	check(Inventory.count_of("wooden_shield") == 1, "woodworker crafted a wooden shield")
	as_guild("blacksmith")
	craft("iron_sword")
	check(Inventory.count_of("iron_sword") == 1, "blacksmith forged an iron sword")
	var learned_only := {"id": "secret", "guild": "blacksmith", "starter": false, "inputs": {}, "output": {"item": "coal", "count": 1}}
	GameData.recipes.append(learned_only)
	check(not Town.knows_recipe("Smoke", "secret"), "a non-starter recipe must be learned first")
	Town.state.players.Smoke["learned"] = ["secret"]
	check(Town.knows_recipe("Smoke", "secret"), "a learned recipe shows up")
	GameData.recipes.erase(learned_only)

	print("Guild materials")
	for spec: Array in [["Sheep1", "wool"], ["Deer1", "hide"], ["Herb1", "herb"]]:
		var node: Node2D = main.get_node("Entities/" + spec[0])
		gather(node)
		check(Inventory.count_of(spec[1]) >= 1, "gathered %s from %s" % [spec[1], spec[0]])
	check(not main.get_node("Entities/Deer1/Sprite2D").visible, "a hunted deer disappears until it respawns")
	Server.bag_of(1).add_item("wool", 8)
	Server.bag_of(1).add_item("hide", 6)
	as_guild("tailor")
	craft("spin_string")
	craft("spin_string")
	craft("weave_cloth")
	check(Inventory.count_of("string") == 4 and Inventory.count_of("cloth") == 1, "tailor spun string and wove cloth")
	as_guild("leatherworker")
	for i in 3:
		craft("tan_leather")
	craft("leather_armor")
	check(Inventory.count_of("leather_armor") == 1, "leatherworker made armor with the tailor's string")
	as_guild("")

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

	print("Town and guilds")
	check(Town.guild_of("Smoke") == "", "new player has no guild yet")
	Town.request_join_guild("blacksmith")
	check(Town.guild_of("Smoke") == "blacksmith", "joined the Blacksmiths")
	Town.request_join_guild("woodworker")
	check(Town.guild_of("Smoke") == "blacksmith", "guild can't be changed")
	var stockpile: Node2D = main.get_node("Entities/Stockpile")
	var table: Node2D = main.get_node("Entities/RoundTable")
	var logs := Inventory.count_of("log")
	player.global_position = Vector2(50, 50)
	Town.request_donate(Server.path_of(stockpile), "log", 1)
	check(Town.stock_of("log") == 0, "donating away from the stockpile is refused")
	use_spot(stockpile)
	Town.request_donate(Server.path_of(stockpile), "log", 2)
	check(Town.stock_of("log") == 2 and Inventory.count_of("log") == logs - 2, "donated logs to the stockpile")
	check(Town.contribution_of("Smoke") == 2, "donation counts as contribution")
	Town.request_donate(Server.path_of(stockpile), "iron_sword", 1)
	check(Town.stock_of("iron_sword") == 0, "gear can't be donated")
	check(Town.is_leader("Smoke"), "top contributor leads the guild")
	Town.state.players["Ghost"] = {"guild": "woodworker", "contribution": 0}
	check(Town.active_guilds().size() == 2, "two guilds have members")
	Town.state.stockpile = {"log": 15, "plank": 10, "iron_ingot": 4}
	Town.request_propose(Server.path_of(table), "watchtower")
	check(Town.state.proposal.is_empty(), "proposing away from the round table is refused")
	use_spot(table)
	Town.request_propose(Server.path_of(table), "palisade")
	check(Town.state.proposal.is_empty(), "can't propose what the stockpile can't pay for")
	Town.request_propose(Server.path_of(table), "watchtower")
	check(not Town.state.proposal.is_empty(), "leader proposed the watchtower")
	check(not Town.is_built("watchtower"), "one of two guilds is not a majority")
	Town.state.proposal.ends_at = 0.0
	Town._process(0.0)
	check(Town.is_built("watchtower"), "vote passed when time ran out with more yes than no")
	check(Town.stock_of("log") == 7 and Town.stock_of("iron_ingot") == 2, "upgrade cost taken from the stockpile")
	check(main.get_node_or_null("Entities/Upgrade_watchtower_29_11") != null, "watchtower appears in town")
	var hall: Node2D = main.get_node("Entities/Hall_blacksmith")
	Town.state.players["Helper"] = {"guild": "blacksmith", "contribution": 1}
	use_spot(hall)
	Town.request_appoint(Server.path_of(hall), "Helper")
	check(Town.assistant("blacksmith") == "Helper", "leader appointed an assistant")
	check(Town.seats().size() == 3, "leaders and the assistant hold seats")
	Town.state.stockpile = {"log": 30, "plank": 20, "iron_ingot": 4}
	use_spot(table)
	Town.request_propose(Server.path_of(table), "silo")
	check(not Town.is_built("silo"), "one of three seats is not a majority")
	Town.state.proposal.votes["Helper"] = true
	Town._resolve_vote(false)
	check(Town.is_built("silo"), "the assistant's vote made the majority")
	Town.request_propose(Server.path_of(table), "palisade")
	Town.request_vote(Server.path_of(table), false)
	check(not Town.state.proposal.is_empty(), "the proposer changing their vote alone doesn't end it")
	Town.state.proposal.votes["Ghost"] = false
	Town._resolve_vote(false)
	check(Town.state.proposal.is_empty() and not Town.is_built("palisade"), "a majority of no votes defeats a proposal")
	Town.state.players.erase("Ghost")
	Town.state.players.erase("Helper")

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
	check(Town.guild_of("Smoke") == "blacksmith", "guild restored on restart")
	check(Town.is_built("watchtower"), "built upgrades restored on restart")

	print("Interaction from the player")
	player.global_position = iron.global_position + Vector2(0, 12)
	iron.apply_save_state({"depleted": false})
	for i in 10:
		await get_tree().physics_frame
	check(player._target == iron, "player targets the nearest rock")

	print("Gathering timing game")
	Server.check_gather_time = true
	Town.state.players["Smoke"] = {"guild": "blacksmith", "contribution": 0}
	var ore_before := Inventory.count_of("iron_ore")
	await tap_interact()
	check(player._gather_state == "filling", "tapping E starts the bar")
	await tap_interact()
	check(player._gather_state == "", "tapping outside the zone resets the bar")
	check(Inventory.count_of("iron_ore") == ore_before, "a miss gathers nothing")
	for i in 20:
		await get_tree().physics_frame
	await tap_interact()
	var zone_middle: float = player._zone_start + player._zone_width / 2.0
	while player._gather_state == "filling" and player._gather_elapsed / iron.gather_duration() < zone_middle:
		await get_tree().physics_frame
	await tap_interact()
	await get_tree().process_frame
	check(Inventory.count_of("iron_ore") > ore_before, "tapping inside the zone gathers ore")
	iron.apply_save_state({"depleted": false})
	await tap_interact()
	while player._gather_state == "filling":
		await get_tree().physics_frame
	check(player._gather_state == "", "letting the bar run out resets it")

	print("Trading")
	var bag_a := Bag.new()
	var bag_b := Bag.new()
	bag_a.add_item("log", 5)
	bag_a.add_item("iron_sword", 1, {"quality": "high", "stats": {"damage": 11, "speed": 5, "durability": 100}})
	bag_b.add_item("wool", 3)
	check(Trade.swap(bag_a, {"log": 2, "iron_sword": 1}, bag_b, {"wool": 3}) == "", "a fair trade goes through")
	check(bag_a.count_of("wool") == 3 and bag_a.count_of("log") == 3 and bag_a.count_of("iron_sword") == 0, "first bag got wool and kept 3 logs")
	check(bag_b.count_of("log") == 2 and bag_b.count_of("wool") == 0, "second bag got the logs")
	var traded_sword: Dictionary = bag_b.slots.filter(func(s: Dictionary) -> bool: return s.id == "iron_sword")[0]
	check(traded_sword.data.quality == "high", "traded gear keeps its high quality")
	check(Trade.swap(bag_a, {"log": 99}, bag_b, {}) != "", "can't trade items you don't have")
	var full := Bag.new()
	for i in Bag.MAX_SLOTS:
		full.add_item("iron_sword", 1, {"quality": "normal"})
	check(Trade.swap(bag_a, {"log": 1}, full, {}) != "" and bag_a.count_of("log") == 3, "a full bag stops the trade and nothing is lost")

	print("Testing shortcut")
	Server.check_gather_time = false
	gather(iron)
	gather(tree)
	check(iron.get_interaction() == "" and tree.get_interaction() == "use", "rock and tree used up")
	Server.request_refill_resources()
	check(iron.get_interaction() == "gather" and tree.get_interaction() == "gather", "F9 refills every resource")

	print("Movement")
	var hud: Node = main.get_node("HUD")
	var fails := [0]
	player.gather_failed.connect(func() -> void: fails[0] += 1)
	iron.apply_save_state({"depleted": false})
	for i in 30:
		await get_tree().physics_frame
	await tap_interact()
	await tap_interact()
	check(fails[0] == 1 and hud._fail_left > 0.0, "a miss flashes the bar red")
	player.global_position = Vector2(23 * 16 + 8, 15 * 16 + 8)
	await get_tree().physics_frame
	var start := player.global_position
	Input.action_press("roll")
	await get_tree().physics_frame
	Input.action_release("roll")
	for i in 20:
		await get_tree().physics_frame
	var rolled := player.global_position.distance_to(start)
	check(rolled > 20.0 and rolled < 60.0, "space rolls a short way (%d px)" % rolled)
	check(player.roll_angle == 0.0, "the roll spin finishes")

	Server.delete_save()
	print("")
	if failures.is_empty():
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED" % failures.size())
	get_tree().quit(1 if not failures.is_empty() else 0)
