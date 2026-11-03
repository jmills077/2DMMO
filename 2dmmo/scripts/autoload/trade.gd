extends Node
## Player-to-player trading.
##
## 1. Stand next to another player and press T. They get an invite.
## 2. If they accept, a trade window opens for both. Each player puts items
##    from their bag into their offer.
## 3. Both press Accept. Changing either offer clears both accepts, so nobody
##    can swap something in at the last second.
## 4. The server checks both players still have the items and room for what
##    they're getting, then swaps everything at once. Crafted gear keeps its
##    quality and stats.
## Walking away, closing the window or disconnecting cancels the trade.
##
## The server decides everything; each window gets a copy of its own trade
## in `current` to draw the window.

signal changed
signal invited(from_name: String)

const Bag := preload("res://scripts/bag.gd")
## How close (pixels) two players must be to start a trade.
const START_DISTANCE := 40.0
## A trade is cancelled if the players drift further apart than this.
const KEEP_DISTANCE := 96.0
const INVITE_SECONDS := 20.0

## This window's trade: {} or {"partner": name, "mine": {item: n},
## "theirs": {item: n}, "my_ok": bool, "their_ok": bool}.
var current := {}
## Name of whoever is inviting this window to trade ("" if nobody).
var invite_from := ""

# Server only.
var _invites := {}  # invited peer -> {"from": peer, "until": msec}
var _trades := {}   # peer -> trade dict shared by both peers
                    # {"a": peer, "b": peer, "offers": {peer: {item: n}}, "ok": {peer: bool}}


func _process(_delta: float) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	for peer: int in _trades.keys():
		if not _trades.has(peer):
			continue
		var trade: Dictionary = _trades[peer]
		if not _close_enough(trade.a, trade.b, KEEP_DISTANCE):
			_cancel(trade, "Trade cancelled: you walked too far apart")


# --- Requests from players (each runs on the server) ---

@rpc("any_peer", "call_local", "reliable")
func request_invite(target_peer: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := Server.sender()
	if peer == target_peer or Server.name_of(target_peer) == "":
		return
	if Combat.is_dead(peer) or Combat.is_dead(target_peer):
		Server.toast(peer, "Spirits can't trade")
		return
	if _trades.has(peer) or _trades.has(target_peer):
		Server.toast(peer, "%s is busy trading" % Server.name_of(target_peer) if _trades.has(target_peer) else "Finish your current trade first")
		return
	if not _close_enough(peer, target_peer, START_DISTANCE):
		Server.toast(peer, "Stand next to someone to trade with them")
		return
	_invites[target_peer] = {"from": peer, "until": Time.get_ticks_msec() + int(INVITE_SECONDS * 1000)}
	_call_on(target_peer, "_receive_invite", [Server.name_of(peer)])
	Server.toast(peer, "Asked %s to trade" % Server.name_of(target_peer))


@rpc("any_peer", "call_local", "reliable")
func request_answer_invite(accept: bool) -> void:
	if not multiplayer.is_server():
		return
	var peer := Server.sender()
	var invite: Dictionary = _invites.get(peer, {})
	_invites.erase(peer)
	_call_on(peer, "_receive_invite", [""])
	if invite.is_empty() or Time.get_ticks_msec() > int(invite.until):
		return
	var from: int = invite.from
	if not accept:
		Server.toast(from, "%s declined the trade" % Server.name_of(peer))
		return
	if _trades.has(from) or _trades.has(peer) or Server.name_of(from) == "":
		return
	if not _close_enough(peer, from, KEEP_DISTANCE):
		Server.toast(peer, "Too far away to trade")
		return
	var trade := {"a": from, "b": peer, "offers": {from: {}, peer: {}}, "ok": {from: false, peer: false}}
	_trades[from] = trade
	_trades[peer] = trade
	_send(trade)


## Sets how many of an item this player is offering (0 removes it).
@rpc("any_peer", "call_local", "reliable")
func request_set_offer(item_id: String, count: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := Server.sender()
	var trade: Dictionary = _trades.get(peer, {})
	var bag := Server.bag_of(peer)
	if trade.is_empty() or bag == null or not GameData.items.has(item_id):
		return
	count = clampi(count, 0, bag.count_of(item_id))
	if count == 0:
		trade.offers[peer].erase(item_id)
	else:
		trade.offers[peer][item_id] = count
	# Any change means both players must look again and re-accept.
	for p: int in trade.ok:
		trade.ok[p] = false
	_send(trade)


@rpc("any_peer", "call_local", "reliable")
func request_accept(ok: bool) -> void:
	if not multiplayer.is_server():
		return
	var peer := Server.sender()
	var trade: Dictionary = _trades.get(peer, {})
	if trade.is_empty():
		return
	trade.ok[peer] = ok
	if trade.ok[trade.a] and trade.ok[trade.b]:
		_complete(trade)
	else:
		_send(trade)


@rpc("any_peer", "call_local", "reliable")
func request_cancel() -> void:
	if not multiplayer.is_server():
		return
	var peer := Server.sender()
	if _trades.has(peer):
		_cancel(_trades[peer], "%s cancelled the trade" % Server.name_of(peer))


## Server: a player left the game.
func player_left(peer_id: int) -> void:
	_invites.erase(peer_id)
	if _trades.has(peer_id):
		_cancel(_trades[peer_id], "Trade cancelled: %s left" % Server.name_of(peer_id))


## Server: cancels this player's trade, if any (for example when they die).
func cancel_for(peer_id: int, message: String) -> void:
	_invites.erase(peer_id)
	if _trades.has(peer_id):
		_cancel(_trades[peer_id], message)


# --- Messages from the server (each runs on a player's machine) ---

@rpc("authority", "call_local", "reliable")
func _receive_trade(trade_view: Dictionary) -> void:
	current = trade_view
	changed.emit()


@rpc("authority", "call_local", "reliable")
func _receive_invite(from_name: String) -> void:
	invite_from = from_name
	invited.emit(from_name)


# --- The swap ---

## Swaps two offers between two bags, all or nothing. Returns "" on success
## or the reason it couldn't happen. Gear keeps its quality and stats.
static func swap(bag_a: RefCounted, offer_a: Dictionary, bag_b: RefCounted, offer_b: Dictionary) -> String:
	for id: String in offer_a:
		if bag_a.count_of(id) < int(offer_a[id]):
			return "Items changed. Check the offers and accept again."
	for id: String in offer_b:
		if bag_b.count_of(id) < int(offer_b[id]):
			return "Items changed. Check the offers and accept again."
	# Try it on copies first so a full bag can't lose anything.
	var test_a := Bag.new()
	test_a.load_save_data(bag_a.to_save_data())
	var test_b := Bag.new()
	test_b.load_save_data(bag_b.to_save_data())
	var from_a := _take(test_a, offer_a)
	var from_b := _take(test_b, offer_b)
	if not _put(test_a, from_b) or not _put(test_b, from_a):
		return "Not enough room in a bag"
	bag_a.slots = test_a.slots
	bag_b.slots = test_b.slots
	return ""


static func _take(bag: RefCounted, offer: Dictionary) -> Array:
	var taken: Array = []
	for id: String in offer:
		var left := int(offer[id])
		for i in range(bag.slots.size() - 1, -1, -1):
			if left == 0:
				break
			var slot: Dictionary = bag.slots[i]
			if slot.id != id:
				continue
			var n := mini(int(slot.count), left)
			taken.append({"id": id, "count": n, "data": slot.data.duplicate(true)})
			slot.count = int(slot.count) - n
			left -= n
			if slot.count <= 0:
				bag.slots.remove_at(i)
	return taken


static func _put(bag: RefCounted, items: Array) -> bool:
	for item: Dictionary in items:
		if bag.add_item(item.id, int(item.count), item.data) > 0:
			return false
	return true


# --- Server helpers ---

func _complete(trade: Dictionary) -> void:
	var a: int = trade.a
	var b: int = trade.b
	var reason := swap(Server.bag_of(a), trade.offers[a], Server.bag_of(b), trade.offers[b])
	if reason != "":
		for p: int in trade.ok:
			trade.ok[p] = false
		_send(trade)
		Server.toast(a, reason)
		Server.toast(b, reason)
		return
	_trades.erase(a)
	_trades.erase(b)
	Server.send_bag(a)
	Server.send_bag(b)
	_call_on(a, "_receive_trade", [{}])
	_call_on(b, "_receive_trade", [{}])
	Server.toast(a, "Trade with %s complete" % Server.name_of(b))
	Server.toast(b, "Trade with %s complete" % Server.name_of(a))


func _cancel(trade: Dictionary, message: String) -> void:
	for p: int in [trade.a, trade.b]:
		_trades.erase(p)
		if Server.name_of(p) != "":
			_call_on(p, "_receive_trade", [{}])
			Server.toast(p, message)


## Sends each player their own view of the trade.
func _send(trade: Dictionary) -> void:
	for pair: Array in [[trade.a, trade.b], [trade.b, trade.a]]:
		var me: int = pair[0]
		var them: int = pair[1]
		_call_on(me, "_receive_trade", [{
			"partner": Server.name_of(them),
			"mine": trade.offers[me],
			"theirs": trade.offers[them],
			"my_ok": trade.ok[me],
			"their_ok": trade.ok[them],
		}])


func _close_enough(a: int, b: int, distance: float) -> bool:
	var node_a := Server.player_node(a)
	var node_b := Server.player_node(b)
	return node_a != null and node_b != null and \
			node_a.global_position.distance_to(node_b.global_position) <= distance


func _call_on(peer_id: int, method: StringName, args: Array) -> void:
	if peer_id == multiplayer.get_unique_id():
		callv(method, args)
	else:
		callv("rpc_id", [peer_id, method] + args)
