extends Control
## The trade invite prompt and the trade window. Buttons send requests to the
## server (autoload/trade.gd); the window redraws whenever the trade changes.

signal open_changed

const UI := preload("res://scripts/ui/ui_kit.gd")
const WIDTH := 300.0

var _invite: PanelContainer
var _invite_text: Label
var _window: PanelContainer
var _body: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var invite_parts: Array = UI.panel()
	_invite = invite_parts[0]
	_invite_text = UI.label("")
	invite_parts[1].add_child(_invite_text)
	invite_parts[1].add_child(UI.row([
		UI.spacer(),
		UI.button("Trade", _answer.bind(true)),
		UI.button("No thanks", _answer.bind(false)),
	]))
	_invite.visible = false
	add_child(_invite)

	var parts: Array = UI.panel()
	_window = parts[0]
	_body = parts[1]
	_window.custom_minimum_size = Vector2(WIDTH, 0)
	_window.position = Vector2(24, 24)
	_window.visible = false
	add_child(_window)

	Trade.changed.connect(_refresh)
	Trade.invited.connect(_on_invited)
	Inventory.changed.connect(_refresh)


## The trade window is showing (the player should not move).
func is_open() -> bool:
	return _window.visible


## T pressed: ask the nearest other player to trade.
func invite_nearest() -> void:
	var me := get_tree().get_first_node_in_group("local_player") as Node2D
	if me == null or is_open():
		return
	var best: Node2D = null
	var best_distance := Trade.START_DISTANCE
	for other: Node2D in get_tree().get_nodes_in_group("player"):
		var distance := other.global_position.distance_to(me.global_position)
		if other != me and distance <= best_distance:
			best = other
			best_distance = distance
	if best == null:
		Events.toast.emit("Stand next to another player and press T to trade")
		return
	Trade.request_invite.rpc_id(1, best.name.to_int())


## Esc: cancel the trade.
func close() -> void:
	if _window.visible:
		Trade.request_cancel.rpc_id(1)


func _on_invited(from_name: String) -> void:
	_invite.visible = from_name != ""
	if from_name == "":
		return
	_invite_text.text = "%s wants to trade with you." % from_name
	_invite.reset_size()
	var screen := get_viewport_rect().size
	_invite.position = Vector2(floorf((screen.x - _invite.size.x) / 2.0), screen.y - _invite.size.y - 48)


func _answer(accept: bool) -> void:
	_invite.visible = false
	Trade.request_answer_invite.rpc_id(1, accept)


func _refresh() -> void:
	var open := not Trade.current.is_empty()
	if open != _window.visible:
		_window.visible = open
		open_changed.emit()
	if not open:
		return
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var trade: Dictionary = Trade.current
	_body.add_child(UI.heading("Trading with %s" % trade.partner))

	# What each side is giving.
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 10)
	columns.add_child(_offer_column("You give", trade.mine, trade.my_ok, true))
	columns.add_child(_offer_column("%s gives" % trade.partner, trade.theirs, trade.their_ok, false))
	_body.add_child(columns)
	_body.add_child(UI.divider())

	# Your bag, to add items to your offer.
	_body.add_child(UI.label("Add from your bag:", UI.TITLE_COLOR))
	var listed := {}
	for slot: Dictionary in Inventory.slots:
		var id := str(slot.id)
		if listed.has(id):
			continue
		listed[id] = true
		var have := Inventory.count_of(id)
		var offered := int(trade.mine.get(id, 0))
		if have - offered <= 0:
			continue
		_body.add_child(UI.row([
			UI.icon(GameData.item_icon(id)),
			UI.label("%s (%d)" % [GameData.item_name(id), have - offered]),
			UI.spacer(),
			UI.button("+1", _set_offer.bind(id, offered + 1)),
			UI.button("All", _set_offer.bind(id, have)),
		]))
	if listed.is_empty():
		_body.add_child(UI.label("Your bag is empty.", UI.MUTED_COLOR))
	_body.add_child(UI.divider())

	var accept_text := "Accepted (waiting)" if trade.my_ok else "Accept trade"
	_body.add_child(UI.row([
		UI.button(accept_text, _accept.bind(not trade.my_ok)),
		UI.spacer(),
		UI.button("Cancel", close),
	]))
	_body.add_child(UI.paragraph("Changing an offer clears both accepts. The swap happens when you both accept.", WIDTH))
	_window.reset_size()


func _offer_column(title: String, offer: Dictionary, ok: bool, mine: bool) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(WIDTH / 2.0 - 8.0, 0)
	column.add_theme_constant_override("separation", 2)
	column.add_child(UI.row([
		UI.label(title, UI.TITLE_COLOR),
		UI.spacer(),
		UI.label("ACCEPTED" if ok else "", UI.GOOD_COLOR),
	]))
	for id: String in offer:
		var cells: Array = [UI.icon(GameData.item_icon(id)), UI.label("%d %s" % [int(offer[id]), GameData.item_name(id)])]
		if mine:
			cells.append(UI.spacer())
			cells.append(UI.button("-1", _set_offer.bind(id, int(offer[id]) - 1)))
		column.add_child(UI.row(cells))
	if offer.is_empty():
		column.add_child(UI.label("Nothing yet", UI.MUTED_COLOR))
	return column


func _set_offer(item_id: String, count: int) -> void:
	Trade.request_set_offer.rpc_id(1, item_id, count)


func _accept(ok: bool) -> void:
	Trade.request_accept.rpc_id(1, ok)
