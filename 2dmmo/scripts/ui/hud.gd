extends CanvasLayer
## Everything drawn on top of the world: the connection line, the interaction
## prompt, the gather bar, messages, the inventory, the crafting panel and the
## host/join menu.
## The layout is built in code so it stays easy to restyle in one place.

const FONT_SIZE := 8
const SLOT_SIZE := 22
const PANEL_COLOR := Color(0.09, 0.08, 0.12, 0.92)
const BORDER_COLOR := Color(0.55, 0.47, 0.35)
const HIGH_QUALITY_COLOR := Color(0.55, 0.85, 1.0)
const MISSING_COLOR := Color(1.0, 0.45, 0.4)

var _root: Control
var _prompt: Label
var _gather_bar: ProgressBar
var _toasts: VBoxContainer
var _inventory_panel: PanelContainer
var _inventory_grid: GridContainer
var _item_details: Label
var _craft_panel: PanelContainer
var _craft_title: Label
var _craft_list: VBoxContainer
var _current_station := ""
var _status: Label
var _connect_panel: PanelContainer
var _name_field: LineEdit
var _address_field: LineEdit
var _town_ui: Control


func _ready() -> void:
	_build_layout()
	Inventory.changed.connect(_refresh_inventory)
	Inventory.changed.connect(_refresh_crafting)
	Town.changed.connect(_refresh_crafting)
	Events.toast.connect(_show_toast)
	Events.station_opened.connect(_open_station)
	Events.local_player_ready.connect(_on_local_player_ready)
	Events.status_changed.connect(func(text: String) -> void: _status.text = text)
	Events.show_connect_menu.connect(_show_connect_menu)
	_status.text = Net.status
	_refresh_inventory()


func _on_local_player_ready(player: Node) -> void:
	player.target_changed.connect(_on_target_changed)
	player.gather_progress.connect(_on_gather_progress)
	_connect_panel.visible = false
	_update_blocking()


func _unhandled_input(event: InputEvent) -> void:
	if _connect_panel.visible:
		return
	if event.is_action_pressed("save_game"):
		if Net.mode != "":
			Server.request_save.rpc_id(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory"):
		_set_inventory_visible(not _inventory_panel.visible)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("close_menu"):
		_close_all()
		get_viewport().set_input_as_handled()


# --- Prompt, gather bar and messages ---

func _on_target_changed(prompt: String) -> void:
	_prompt.text = prompt
	_prompt.visible = prompt != "" and not Events.ui_blocking


func _on_gather_progress(ratio: float) -> void:
	_gather_bar.value = ratio
	_gather_bar.visible = ratio > 0.0


func _show_toast(text: String) -> void:
	var label := _label(text)
	_toasts.add_child(label)
	var tween := create_tween()
	tween.tween_interval(2.0)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(label.queue_free)
	if _toasts.get_child_count() > 5:
		_toasts.get_child(0).queue_free()


# --- Inventory ---

func _set_inventory_visible(show: bool) -> void:
	_inventory_panel.visible = show
	if not show:
		_craft_panel.visible = false
		_current_station = ""
	_update_blocking()


func _refresh_inventory() -> void:
	for child in _inventory_grid.get_children():
		child.queue_free()
	for i in Inventory.MAX_SLOTS:
		var slot: Dictionary = Inventory.slots[i] if i < Inventory.slots.size() else {}
		_inventory_grid.add_child(_make_slot(slot))


func _make_slot(slot: Dictionary) -> Control:
	var box := Panel.new()
	box.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	box.add_theme_stylebox_override("panel", _box_style(Color(0.16, 0.14, 0.2), BORDER_COLOR.darkened(0.3)))
	if slot.is_empty():
		return box
	var icon := TextureRect.new()
	icon.texture = GameData.item_icon(slot.id)
	icon.position = Vector2(3, 3)
	icon.size = Vector2(16, 16)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)
	if int(slot.count) > 1:
		var count := _label(str(slot.count))
		count.position = Vector2(1, 11)
		count.size = Vector2(SLOT_SIZE - 2, 10)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		box.add_child(count)
	if str(slot.data.get("quality", "")) == "high":
		box.add_theme_stylebox_override("panel", _box_style(Color(0.16, 0.14, 0.2), HIGH_QUALITY_COLOR))
	box.mouse_entered.connect(func() -> void: _item_details.text = _describe(slot))
	box.mouse_exited.connect(func() -> void: _item_details.text = "")
	return box


func _describe(slot: Dictionary) -> String:
	var item := GameData.get_item(slot.id)
	var lines: Array[String] = []
	var title := GameData.item_name(slot.id)
	if str(slot.data.get("quality", "")) == "high":
		title = "High quality " + title
	lines.append(title)
	var stats: Dictionary = slot.data.get("stats", {})
	for stat: String in stats:
		var line := "%s: %d" % [stat.capitalize(), int(stats[stat])]
		if slot.data.get("boosted_stat", "") == stat:
			line += " (boosted)"
		lines.append(line)
	if item.has("description"):
		lines.append(str(item.description))
	return "\n".join(lines)


# --- Crafting ---

func _open_station(station_id: String, display_name: String) -> void:
	_current_station = station_id
	_craft_title.text = display_name
	_craft_panel.visible = true
	_set_inventory_visible(true)
	_refresh_crafting()


func _refresh_crafting() -> void:
	if _current_station == "":
		return
	for child in _craft_list.get_children():
		child.queue_free()
	for recipe: Dictionary in GameData.recipes_for_station(_current_station):
		_craft_list.add_child(_make_recipe_row(recipe))


func _make_recipe_row(recipe: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var output: Dictionary = recipe.output
	var icon := TextureRect.new()
	icon.texture = GameData.item_icon(output.item)
	icon.custom_minimum_size = Vector2(16, 16)
	row.add_child(icon)

	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var count := int(output.get("count", 1))
	var title := ("%d x " % count if count > 1 else "") + GameData.item_name(output.item)
	var guild := GameData.get_guild(str(recipe.get("guild", "")))
	var mine: bool = guild.is_empty() or Town.guild_of(Net.player_name) == guild.id
	if not mine:
		title += "  (%s only)" % guild.name
	var title_label := _label(title)
	if not mine:
		title_label.modulate.a = 0.55
	text.add_child(title_label)
	var needs := RichTextLabel.new()
	needs.bbcode_enabled = true
	needs.fit_content = true
	needs.scroll_active = false
	needs.autowrap_mode = TextServer.AUTOWRAP_OFF
	needs.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	var parts: Array[String] = []
	for id: String in recipe.inputs:
		var need := int(recipe.inputs[id])
		var have := Inventory.count_of(id)
		var color := "white" if have >= need else "#" + MISSING_COLOR.to_html(false)
		parts.append("[color=%s]%d %s (%d)[/color]" % [color, need, GameData.item_name(id), have])
	needs.text = ", ".join(parts)
	text.add_child(needs)
	row.add_child(text)

	var button := Button.new()
	button.text = "Craft"
	button.add_theme_font_size_override("font_size", FONT_SIZE)
	button.disabled = not mine or not Crafting.can_craft(Inventory.bag, recipe)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(_craft.bind(recipe))
	row.add_child(button)
	return row


## The server crafts and replies with a message and the updated bag.
func _craft(recipe: Dictionary) -> void:
	Server.request_craft.rpc_id(1, str(recipe.id))


# --- Host or join menu (shown when the game is not started from the editor) ---

func _show_connect_menu() -> void:
	_connect_panel.visible = true
	_update_blocking()


func _on_host_pressed() -> void:
	Net.player_name = _name_field.text
	if Net.host(true):
		_connect_panel.visible = false
		_update_blocking()
	else:
		_status.text = "Could not host: port %d is in use" % Net.port()


func _on_join_pressed() -> void:
	Net.player_name = _name_field.text
	var address := _address_field.text.strip_edges()
	Net.join(address if address != "" else "127.0.0.1")
	_connect_panel.visible = false
	_update_blocking()


# --- Helpers ---

func _close_all() -> void:
	_set_inventory_visible(false)
	_town_ui.close()


func _update_blocking() -> void:
	Events.ui_blocking = _inventory_panel.visible or _craft_panel.visible or _connect_panel.visible \
			or _town_ui.is_open()
	_prompt.visible = _prompt.text != "" and not Events.ui_blocking


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _box_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_content_margin_all(4)
	return style


func _panel(title: String) -> Array:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box_style(PANEL_COLOR, BORDER_COLOR))
	panel.visible = false
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	panel.add_child(column)
	var heading := _label(title)
	heading.add_theme_color_override("font_color", BORDER_COLOR.lightened(0.4))
	column.add_child(heading)
	return [panel, column, heading]


## Pins a control to a point of the screen (0..1 on each axis) with a rect relative to it.
func _anchor(control: Control, point: Vector2, rect: Rect2) -> void:
	control.anchor_left = point.x
	control.anchor_right = point.x
	control.anchor_top = point.y
	control.anchor_bottom = point.y
	control.offset_left = rect.position.x
	control.offset_top = rect.position.y
	control.offset_right = rect.end.x
	control.offset_bottom = rect.end.y


func _build_layout() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var help := _label("WASD move   E interact   I bag   F5 save   Esc close")
	help.position = Vector2(4, 2)
	help.modulate.a = 0.75
	_root.add_child(help)

	_status = _label("")
	_status.position = Vector2(4, 12)
	_status.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	_root.add_child(_status)

	_prompt = _label("")
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor(_prompt, Vector2(0.5, 1.0), Rect2(-150, -26, 300, 12))
	_root.add_child(_prompt)

	_gather_bar = ProgressBar.new()
	_gather_bar.custom_minimum_size = Vector2(60, 5)
	_anchor(_gather_bar, Vector2(0.5, 1.0), Rect2(-30, -36, 60, 5))
	_gather_bar.max_value = 1.0
	_gather_bar.show_percentage = false
	_gather_bar.add_theme_stylebox_override("background", _box_style(Color(0, 0, 0, 0.6), Color.BLACK))
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.95, 0.8, 0.35)
	_gather_bar.add_theme_stylebox_override("fill", fill)
	_gather_bar.visible = false
	_root.add_child(_gather_bar)

	_toasts = VBoxContainer.new()
	_anchor(_toasts, Vector2(1.0, 0.0), Rect2(-164, 4, 160, 80))
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toasts)

	var inv: Array = _panel("Bag")
	_inventory_panel = inv[0]
	_inventory_panel.position = Vector2(340, 40)
	_inventory_grid = GridContainer.new()
	_inventory_grid.columns = 6
	_inventory_grid.add_theme_constant_override("h_separation", 2)
	_inventory_grid.add_theme_constant_override("v_separation", 2)
	inv[1].add_child(_inventory_grid)
	_item_details = _label("")
	_item_details.custom_minimum_size = Vector2(0, 52)
	_item_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_item_details.custom_minimum_size.x = 6 * (SLOT_SIZE + 2)
	inv[1].add_child(_item_details)
	_root.add_child(_inventory_panel)

	var craft: Array = _panel("Crafting")
	_craft_panel = craft[0]
	_craft_title = craft[2]
	_craft_panel.position = Vector2(24, 40)
	_craft_panel.custom_minimum_size = Vector2(300, 0)
	_craft_list = VBoxContainer.new()
	_craft_list.add_theme_constant_override("separation", 4)
	craft[1].add_child(_craft_list)
	_root.add_child(_craft_panel)

	_town_ui = preload("res://scripts/ui/town_ui.gd").new()
	_root.add_child(_town_ui)
	_town_ui.open_changed.connect(_update_blocking)

	var menu: Array = _panel("Play")
	_connect_panel = menu[0]
	_anchor(_connect_panel, Vector2(0.5, 0.5), Rect2(-90, -60, 180, 0))
	menu[1].add_child(_label("Your name (blank for Tester1, Tester2...)"))
	_name_field = _line_edit("")
	menu[1].add_child(_name_field)
	menu[1].add_child(_label("Server address (to join)"))
	_address_field = _line_edit("127.0.0.1")
	menu[1].add_child(_address_field)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	for pair: Array in [["Host a game", _on_host_pressed], ["Join", _on_join_pressed]]:
		var button := Button.new()
		button.text = pair[0]
		button.add_theme_font_size_override("font_size", FONT_SIZE)
		button.pressed.connect(pair[1])
		buttons.add_child(button)
	menu[1].add_child(buttons)
	_root.add_child(_connect_panel)


func _line_edit(text: String) -> LineEdit:
	var field := LineEdit.new()
	field.text = text
	field.add_theme_font_size_override("font_size", FONT_SIZE)
	return field
