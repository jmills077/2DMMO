extends RefCounted
## Shared look for on-screen panels, so every menu matches.
## Change colors and sizes here to restyle the menus.

const FONT_SIZE := 8
const PANEL_COLOR := Color(0.09, 0.08, 0.12, 0.94)
const BORDER_COLOR := Color(0.55, 0.47, 0.35)
const TITLE_COLOR := Color(0.87, 0.8, 0.66)
const MUTED_COLOR := Color(0.7, 0.68, 0.74)
const GOOD_COLOR := Color(0.55, 0.9, 0.55)
const BAD_COLOR := Color(1.0, 0.45, 0.4)


static func label(text: String, color: Color = Color.WHITE) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", FONT_SIZE)
	node.add_theme_color_override("font_color", color)
	node.add_theme_color_override("font_outline_color", Color.BLACK)
	node.add_theme_constant_override("outline_size", 2)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


## A label that wraps onto several lines within a width.
static func paragraph(text: String, width: float, color: Color = MUTED_COLOR) -> Label:
	var node := label(text, color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.custom_minimum_size = Vector2(width, 0)
	return node


static func button(text: String, on_press: Callable, enabled: bool = true) -> Button:
	var node := Button.new()
	node.text = text
	node.add_theme_font_size_override("font_size", FONT_SIZE)
	node.focus_mode = Control.FOCUS_NONE
	node.disabled = not enabled
	node.pressed.connect(on_press)
	return node


static func icon(texture: Texture2D) -> TextureRect:
	var node := TextureRect.new()
	node.texture = texture
	node.custom_minimum_size = Vector2(16, 16)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


static func row(children: Array) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	for child: Control in children:
		box.add_child(child)
	return box


## An empty control that pushes the next ones to the right edge of a row.
static func spacer() -> Control:
	var node := Control.new()
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


static func box_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_content_margin_all(5)
	return style


## Returns [panel, column]. Add content to column.
static func panel() -> Array:
	var node := PanelContainer.new()
	node.add_theme_stylebox_override("panel", box_style(PANEL_COLOR, BORDER_COLOR))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	node.add_child(column)
	return [node, column]


static func heading(text: String) -> Label:
	return label(text, TITLE_COLOR)


static func divider() -> HSeparator:
	var line := HSeparator.new()
	line.add_theme_constant_override("separation", 4)
	return line
