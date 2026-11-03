extends Control
## The town panels: choosing a guild, the stockpile, the round table and
## the guild halls. Buttons send requests to the server (autoload/town.gd);
## the panels redraw whenever the town changes.

signal open_changed

const UI := preload("res://scripts/ui/ui_kit.gd")
const WIDTH := 290.0

var _kind := ""
var _guild_id := ""
var _path := ""
var _window: PanelContainer
var _body: VBoxContainer
var _picker: PanelContainer
var _clock := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var parts: Array = UI.panel()
	_window = parts[0]
	_body = parts[1]
	_window.custom_minimum_size = Vector2(WIDTH, 0)
	_window.visible = false
	add_child(_window)

	_picker = _build_picker()
	_picker.visible = false
	add_child(_picker)

	Events.town_object_opened.connect(open)
	Town.changed.connect(_on_town_changed)
	Inventory.changed.connect(_refresh)
	Events.status_changed.connect(func(_text: String) -> void: _check_guild())


## A panel or the guild picker is showing (the player should not move).
func is_open() -> bool:
	return _window.visible or _picker.visible


func open(kind: String, guild_id: String, path: String) -> void:
	_kind = kind
	_guild_id = guild_id
	_path = path
	_window.visible = true
	_refresh()
	open_changed.emit()


func close() -> void:
	_window.visible = false
	_kind = ""
	open_changed.emit()


func _process(delta: float) -> void:
	# Keep the vote countdown ticking.
	_clock += delta
	if _clock >= 1.0:
		_clock = 0.0
		if _window.visible and _kind == "round_table" and not Town.state.proposal.is_empty():
			_refresh()


func _on_town_changed() -> void:
	_check_guild()
	_refresh()


func _me() -> String:
	return Net.player_name


# --- Choosing a guild ---

func _check_guild() -> void:
	var playing := Net.mode == "host" or Net.mode == "client"
	var needs: bool = playing and _me() != "" and Town.guild_of(_me()) == "" and Town.state.online.has(_me())
	if needs != _picker.visible:
		_picker.visible = needs
		if needs:
			_center_picker.call_deferred()
		open_changed.emit()


func _center_picker() -> void:
	_picker.reset_size()
	_picker.position = ((get_viewport_rect().size - _picker.size) / 2.0).floor()


func _build_picker() -> PanelContainer:
	var parts: Array = UI.panel()
	var panel: PanelContainer = parts[0]
	var column: VBoxContainer = parts[1]
	column.add_child(UI.heading("Choose your crafting guild"))
	column.add_child(UI.paragraph("Your guild is your crafting class. You can't change it later.", 300))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	for guild: Dictionary in GameData.guilds:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 1)
		var pick := UI.button("Become a %s" % guild.member, _join.bind(str(guild.id)))
		pick.add_theme_color_override("font_color", Color(str(guild.color)))
		cell.add_child(pick)
		cell.add_child(UI.paragraph(str(guild.description), 145))
		grid.add_child(cell)
	column.add_child(grid)
	return panel


func _join(guild_id: String) -> void:
	Town.request_join_guild.rpc_id(1, guild_id)


# --- Drawing the open panel ---

func _refresh() -> void:
	if not _window.visible:
		return
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	match _kind:
		"stockpile":
			_draw_stockpile()
		"round_table":
			_draw_round_table()
		"guild_hall":
			_draw_guild_hall()
	_body.add_child(UI.label("Esc to close", UI.MUTED_COLOR))
	_window.reset_size()
	_window.position = Vector2(24, 24)


func _draw_stockpile() -> void:
	_body.add_child(UI.heading("Town Stockpile"))
	_body.add_child(UI.paragraph("Everything here belongs to the town. Guild leaders spend it on upgrades at the round table.", WIDTH))
	var stock := HFlowContainer.new()
	stock.add_theme_constant_override("h_separation", 8)
	for id: String in Town.state.stockpile:
		stock.add_child(UI.row([UI.icon(GameData.item_icon(id)), UI.label("%d" % Town.stock_of(id))]))
	if Town.state.stockpile.is_empty():
		stock.add_child(UI.label("Empty", UI.MUTED_COLOR))
	_body.add_child(stock)
	_body.add_child(UI.divider())

	_body.add_child(UI.heading("Donate from your bag"))
	_body.add_child(UI.paragraph("Each item you give is 1 point of contribution. Your guild's top contributor leads it.", WIDTH))
	var listed := {}
	for slot: Dictionary in Inventory.slots:
		var id := str(slot.id)
		if listed.has(id) or not GameData.is_donatable(id):
			continue
		listed[id] = true
		var have := Inventory.count_of(id)
		_body.add_child(UI.row([
			UI.icon(GameData.item_icon(id)),
			UI.label("%s (%d)" % [GameData.item_name(id), have]),
			UI.spacer(),
			UI.button("Give 1", _donate.bind(id, 1)),
			UI.button("Give all", _donate.bind(id, have)),
		]))
	if listed.is_empty():
		_body.add_child(UI.label("Nothing to donate. Gear can't be donated.", UI.MUTED_COLOR))
	_body.add_child(UI.label("Your contribution: %d" % Town.contribution_of(_me()), UI.TITLE_COLOR))


func _donate(item_id: String, count: int) -> void:
	Town.request_donate.rpc_id(1, _path, item_id, count)


func _draw_round_table() -> void:
	_body.add_child(UI.heading("Round Table: town upgrades"))
	var me_leader := Town.is_leader(_me())
	var open_vote: bool = not Town.state.proposal.is_empty()
	for upgrade: Dictionary in GameData.upgrades:
		var cost_parts: Array[String] = []
		for id: String in upgrade.cost:
			var need := int(upgrade.cost[id])
			var have := Town.stock_of(id)
			var color := "#8ce68c" if have >= need else "#ff7366"
			cost_parts.append("[color=%s]%d %s (%d)[/color]" % [color, need, GameData.item_name(id), have])
		var title := UI.label(str(upgrade.name), UI.TITLE_COLOR)
		var action: Control
		if Town.is_built(upgrade.id):
			action = UI.label("Built", UI.GOOD_COLOR)
		else:
			var can := me_leader and not open_vote and Town.can_afford(upgrade.cost)
			action = UI.button("Propose", _propose.bind(str(upgrade.id)), can)
		_body.add_child(UI.row([title, UI.spacer(), action]))
		_body.add_child(_rich(", ".join(cost_parts)))
		_body.add_child(UI.paragraph(str(upgrade.description), WIDTH))
	_body.add_child(UI.divider())

	if not open_vote:
		var note := "No vote is open. "
		note += "As your guild's leader, you can propose an upgrade the stockpile can pay for." if me_leader \
				else "Guild leaders propose upgrades. Donate to the stockpile to become your guild's leader."
		_body.add_child(UI.paragraph(note, WIDTH))
		return

	var proposal: Dictionary = Town.state.proposal
	var upgrade := GameData.get_upgrade(str(proposal.upgrade))
	var left := Town.vote_seconds_left()
	_body.add_child(UI.heading("Vote: build the %s?" % upgrade.name))
	_body.add_child(UI.label("Proposed by %s. %d:%02d left." % [proposal.by, left / 60, left % 60], UI.MUTED_COLOR))
	for guild_id: String in Town.active_guilds():
		var guild := GameData.get_guild(guild_id)
		var yes := 0
		var no := 0
		for member: String in Town.members(guild_id):
			if proposal.advice.has(member) and not Town.has_seat(member):
				if proposal.advice[member]:
					yes += 1
				else:
					no += 1
		var cells: Array = [UI.label(str(guild.name), Color(str(guild.color)))]
		for seat: String in [Town.leader(guild_id), Town.assistant(guild_id)]:
			if seat == "":
				continue
			var vote := "?"
			var color := UI.MUTED_COLOR
			if proposal.votes.has(seat):
				vote = "yes" if proposal.votes[seat] else "no"
				color = UI.GOOD_COLOR if proposal.votes[seat] else UI.BAD_COLOR
			cells.append(UI.label("%s:" % seat, UI.MUTED_COLOR))
			cells.append(UI.label(vote, color))
		cells.append(UI.spacer())
		cells.append(UI.label("members %d/%d" % [yes, no], UI.MUTED_COLOR))
		_body.add_child(UI.row(cells))
	var verb := "Vote" if Town.has_seat(_me()) else "Advise"
	if Town.guild_of(_me()) != "":
		_body.add_child(UI.row([
			UI.spacer(),
			UI.button("%s yes" % verb, _vote.bind(true)),
			UI.button("%s no" % verb, _vote.bind(false)),
		]))
	_body.add_child(UI.label("Leaders and assistants vote; members advise (yes/no).", UI.MUTED_COLOR))


func _propose(upgrade_id: String) -> void:
	Town.request_propose.rpc_id(1, _path, upgrade_id)


func _vote(yes: bool) -> void:
	Town.request_vote.rpc_id(1, _path, yes)


func _draw_guild_hall() -> void:
	var guild := GameData.get_guild(_guild_id)
	_body.add_child(UI.label("%s Hall" % guild.name, Color(str(guild.color))))
	_body.add_child(UI.paragraph(str(guild.description), WIDTH))
	var list := Town.members(_guild_id)
	var total := 0
	for member: String in list:
		total += Town.contribution_of(member)
	_body.add_child(UI.label("Leader: %s" % (Town.leader(_guild_id) if not list.is_empty() else "nobody yet"), UI.TITLE_COLOR))
	var helper := Town.assistant(_guild_id)
	_body.add_child(UI.label("Assistant: %s" % (helper if helper != "" else "none appointed"), UI.TITLE_COLOR))
	var i_lead := Town.leader(_guild_id) == _me()
	_body.add_child(UI.label("Members: %d    Total contribution: %d" % [list.size(), total], UI.MUTED_COLOR))
	for member: String in list:
		var online := Town.is_online(member)
		var cells: Array = [
			UI.label("*" if online else " ", UI.GOOD_COLOR),
			UI.label(member + ("  (you)" if member == _me() else "")),
			UI.spacer(),
		]
		if i_lead and member != _me() and member != helper:
			cells.append(UI.button("Make assistant", _appoint.bind(member)))
		cells.append(UI.label("%d" % Town.contribution_of(member), UI.MUTED_COLOR))
		_body.add_child(UI.row(cells))
	if list.is_empty():
		_body.add_child(UI.label("No members yet.", UI.MUTED_COLOR))
	_body.add_child(UI.label("* online now", UI.MUTED_COLOR))


func _appoint(member: String) -> void:
	Town.request_appoint.rpc_id(1, _path, member)


func _rich(bbcode: String) -> RichTextLabel:
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.custom_minimum_size = Vector2(WIDTH, 0)
	text.add_theme_font_size_override("normal_font_size", UI.FONT_SIZE)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.text = bbcode
	return text
