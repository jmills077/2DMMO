extends Node
## The town: crafting guilds, the shared stockpile, and round-table votes
## on town upgrades.
##
## How it works:
## - Every player joins one crafting guild, once, the first time they play.
## - Players donate raw materials to the town stockpile. Each item donated
##   adds one point of contribution for that player.
## - The top contributor in each guild is its leader.
## - A leader proposes an upgrade at the round table. Each guild's leader
##   casts that guild's vote; members advise their leader with their own vote.
## - The upgrade passes when more than half of the guilds vote yes, or, when
##   the vote time runs out, if more guilds said yes than no.
## - A passed upgrade takes its cost from the stockpile and appears in town.
##
## The server decides everything. Every window keeps a copy of `state`
## to draw the panels, and is told whenever it changes.

signal changed

## How long a vote stays open, in seconds.
const VOTE_SECONDS := 300.0

## {"stockpile": {item: count}, "players": {name: {"guild", "contribution"}},
##  "built": [upgrade ids], "proposal": {} or {"upgrade", "by", "votes", "advice", "ends_at"},
##  "online": [names]}
var state := {}

var _rendered := {}  # upgrade id -> true, for buildings already placed in this window


func _ready() -> void:
	reset()
	changed.connect(_place_buildings)


func reset() -> void:
	state = {"stockpile": {}, "players": {}, "built": [], "proposal": {}, "online": []}


# --- Reading the town (works in every window) ---

func guild_of(player_name: String) -> String:
	return str(state.players.get(player_name, {}).get("guild", ""))


func contribution_of(player_name: String) -> int:
	return int(state.players.get(player_name, {}).get("contribution", 0))


## Guild members, top contributor first.
func members(guild_id: String) -> Array:
	var list: Array = state.players.keys().filter(
			func(n: String) -> bool: return guild_of(n) == guild_id)
	list.sort_custom(func(a: String, b: String) -> bool:
		if contribution_of(a) != contribution_of(b):
			return contribution_of(a) > contribution_of(b)
		return a < b)
	return list


func leader(guild_id: String) -> String:
	var list := members(guild_id)
	return list[0] if not list.is_empty() else ""


func is_leader(player_name: String) -> bool:
	var guild := guild_of(player_name)
	return guild != "" and leader(guild) == player_name


## Guilds with at least one member. Only these vote.
func active_guilds() -> Array:
	var ids: Array = []
	for guild: Dictionary in GameData.guilds:
		if not members(guild.id).is_empty():
			ids.append(guild.id)
	return ids


func is_online(player_name: String) -> bool:
	return player_name in state.online


func is_built(upgrade_id: String) -> bool:
	return upgrade_id in state.built


func stock_of(item_id: String) -> int:
	return int(state.stockpile.get(item_id, 0))


func can_afford(cost: Dictionary) -> bool:
	for id: String in cost:
		if stock_of(id) < int(cost[id]):
			return false
	return true


## Seconds left on the open vote.
func vote_seconds_left() -> int:
	if state.proposal.is_empty():
		return 0
	return maxi(0, ceili(float(state.proposal.ends_at) - Time.get_unix_time_from_system()))


# --- Server: joining and leaving ---

func player_joined(player_name: String) -> void:
	if not player_name in state.online:
		state.online.append(player_name)
	publish()


func player_left(player_name: String) -> void:
	state.online.erase(player_name)
	publish()


func to_save_data() -> Dictionary:
	var data := state.duplicate(true)
	data.erase("online")
	return data


func load_save_data(data: Dictionary) -> void:
	reset()
	for key: String in ["stockpile", "players", "built", "proposal"]:
		if data.has(key):
			state[key] = data[key]
	publish()


func _process(_delta: float) -> void:
	if Server.running and not state.proposal.is_empty() and vote_seconds_left() <= 0:
		_resolve_vote(true)
		publish()


# --- Requests from players (each runs on the server) ---

@rpc("any_peer", "call_local", "reliable")
func request_join_guild(guild_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := Server.sender()
	var player_name := Server.name_of(peer)
	if player_name == "" or guild_of(player_name) != "" or GameData.get_guild(guild_id).is_empty():
		return
	state.players[player_name] = {"guild": guild_id, "contribution": 0}
	publish()
	Server.toast(peer, "Welcome to the %s!" % GameData.get_guild(guild_id).name)


@rpc("any_peer", "call_local", "reliable")
func request_donate(path: String, item_id: String, count: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := Server.sender()
	var player_name := Server.name_of(peer)
	var bag := Server.bag_of(peer)
	if bag == null or not _at(peer, path, "stockpile") or not GameData.is_donatable(item_id):
		return
	if guild_of(player_name) == "":
		Server.toast(peer, "Join a guild first")
		return
	count = mini(count, bag.count_of(item_id))
	if count <= 0 or not bag.remove_item(item_id, count):
		return
	state.stockpile[item_id] = stock_of(item_id) + count
	state.players[player_name].contribution = contribution_of(player_name) + count
	Server.send_bag(peer)
	publish()
	Server.toast(peer, "Donated %d %s" % [count, GameData.item_name(item_id)])


@rpc("any_peer", "call_local", "reliable")
func request_propose(path: String, upgrade_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := Server.sender()
	var player_name := Server.name_of(peer)
	var upgrade := GameData.get_upgrade(upgrade_id)
	if upgrade.is_empty() or not _at(peer, path, "round_table"):
		return
	var reason := ""
	if not is_leader(player_name):
		reason = "Only a guild leader can propose"
	elif not state.proposal.is_empty():
		reason = "A vote is already open"
	elif is_built(upgrade_id):
		reason = "Already built"
	elif not can_afford(upgrade.cost):
		reason = "The stockpile can't pay for that yet"
	if reason != "":
		Server.toast(peer, reason)
		return
	state.proposal = {
		"upgrade": upgrade_id,
		"by": player_name,
		"votes": {guild_of(player_name): true},
		"advice": {player_name: true},
		"ends_at": Time.get_unix_time_from_system() + VOTE_SECONDS,
	}
	Server.toast_all("%s proposes building the %s. Leaders vote at the round table." % [player_name, upgrade.name])
	_resolve_vote(false)
	publish()


@rpc("any_peer", "call_local", "reliable")
func request_vote(path: String, yes: bool) -> void:
	if not multiplayer.is_server():
		return
	var peer := Server.sender()
	var player_name := Server.name_of(peer)
	if state.proposal.is_empty() or not _at(peer, path, "round_table"):
		return
	var guild := guild_of(player_name)
	if guild == "":
		Server.toast(peer, "Join a guild first")
		return
	state.proposal.advice[player_name] = yes
	if is_leader(player_name):
		state.proposal.votes[guild] = yes
		Server.toast(peer, "You voted %s for the %s" % ["yes" if yes else "no", GameData.get_guild(guild).name])
	else:
		Server.toast(peer, "You advised %s to vote %s" % [leader(guild), "yes" if yes else "no"])
	_resolve_vote(false)
	publish()


# --- Server helpers ---

## Sends the town to every window, including this one.
func publish() -> void:
	changed.emit()
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	for peer: int in multiplayer.get_peers():
		_receive_state.rpc_id(peer, state)


@rpc("authority", "call_remote", "reliable")
func _receive_state(new_state: Dictionary) -> void:
	state = new_state
	changed.emit()


func _at(peer_id: int, path: String, kind: String) -> bool:
	var target := Server.reachable(peer_id, path)
	return target != null and target.get("kind") == kind


func _resolve_vote(time_up: bool) -> void:
	var proposal: Dictionary = state.proposal
	if proposal.is_empty():
		return
	var voters := active_guilds()
	var yes := 0
	var no := 0
	for guild: String in proposal.votes:
		if guild in voters:
			if proposal.votes[guild]:
				yes += 1
			else:
				no += 1
	var majority := voters.size() / 2 + 1
	var passed := yes >= majority
	var failed := no > voters.size() - majority
	if time_up and not passed and not failed:
		passed = yes > no
		failed = not passed
	if not passed and not failed:
		return
	var upgrade := GameData.get_upgrade(str(proposal.upgrade))
	state.proposal = {}
	if failed:
		Server.toast_all("The vote to build the %s failed" % upgrade.name)
	elif not can_afford(upgrade.cost):
		Server.toast_all("The %s passed, but the stockpile is short. Donate and vote again." % upgrade.name)
	else:
		for id: String in upgrade.cost:
			state.stockpile[id] = stock_of(id) - int(upgrade.cost[id])
			if state.stockpile[id] <= 0:
				state.stockpile.erase(id)
		state.built.append(upgrade.id)
		Server.toast_all("The town built the %s!" % upgrade.name)


# --- Buildings on the map (every window) ---

func _place_buildings() -> void:
	var entities: Node = Server.world.get_node_or_null("Entities") if Server.world else null
	if entities == null:
		return
	for upgrade_id: String in state.built:
		if _rendered.has(upgrade_id):
			continue
		_rendered[upgrade_id] = true
		var upgrade := GameData.get_upgrade(upgrade_id)
		var texture: Texture2D = load(str(upgrade.art))
		for cell: Vector2i in upgrade_tiles(upgrade):
			var holder := Node2D.new()
			holder.name = "Upgrade_%s_%d_%d" % [upgrade_id, cell.x, cell.y]
			holder.position = Vector2(cell * 16) + Vector2(8, 8)
			var sprite := Sprite2D.new()
			sprite.texture = texture
			# Keep the bottom of tall buildings on their tile.
			sprite.position = Vector2(0, 8 - texture.get_height() / 2.0)
			holder.add_child(sprite)
			entities.add_child(holder)


## The map tiles an upgrade's art is drawn on.
func upgrade_tiles(upgrade: Dictionary) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for pair: Array in upgrade.get("tiles", []):
		cells.append(Vector2i(int(pair[0]), int(pair[1])))
	var ring: Array = upgrade.get("ring", [])
	if ring.size() == 4:
		var gaps: Array[Vector2i] = []
		for pair: Array in upgrade.get("gaps", []):
			gaps.append(Vector2i(int(pair[0]), int(pair[1])))
		for x in range(int(ring[0]), int(ring[2]) + 1):
			for y in range(int(ring[1]), int(ring[3]) + 1):
				var edge := x == int(ring[0]) or x == int(ring[2]) or y == int(ring[1]) or y == int(ring[3])
				var cell := Vector2i(x, y)
				if edge and not cell in gaps:
					cells.append(cell)
	return cells


## Forget placed buildings, for when a window leaves a world.
func clear_buildings() -> void:
	_rendered.clear()
