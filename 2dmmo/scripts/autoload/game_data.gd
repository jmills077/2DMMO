extends Node
## Loads item and recipe definitions from the data folder.
## To add or rebalance items and recipes, edit data/items.json and
## data/recipes.json. No code changes are needed.

const ITEMS_PATH := "res://data/items.json"
const RECIPES_PATH := "res://data/recipes.json"

var items: Dictionary = {}
var recipes: Array = []
var _icon_cache: Dictionary = {}


func _enter_tree() -> void:
	var loaded_items: Variant = _load_json(ITEMS_PATH)
	if loaded_items is Dictionary:
		items = loaded_items
	var loaded_recipes: Variant = _load_json(RECIPES_PATH)
	if loaded_recipes is Array:
		recipes = loaded_recipes


func get_item(id: String) -> Dictionary:
	return items.get(id, {})


func item_name(id: String) -> String:
	return str(get_item(id).get("name", id))


func item_icon(id: String) -> Texture2D:
	if _icon_cache.has(id):
		return _icon_cache[id]
	var path := str(get_item(id).get("icon", ""))
	var texture: Texture2D = load(path) if path != "" and ResourceLoader.exists(path) else null
	_icon_cache[id] = texture
	return texture


func stack_size(id: String) -> int:
	return int(get_item(id).get("stack", 99))


func recipes_for_station(station_id: String) -> Array:
	return recipes.filter(func(r: Dictionary) -> bool: return r.get("station") == station_id)


func _load_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Missing data file: %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null:
		push_error("Could not read %s. Check it for a JSON typo." % path)
	return parsed
