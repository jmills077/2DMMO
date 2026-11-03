extends StaticBody2D
## A crafting station such as the furnace or workbench.
## station_id must match the "station" field of recipes in data/recipes.json.

@export var station_id := "workbench"
@export var display_name := "Workbench"
@export var texture: Texture2D:
	set(value):
		texture = value
		if is_node_ready():
			$Sprite2D.texture = value


func _ready() -> void:
	$Sprite2D.texture = texture


func get_interaction() -> String:
	return "use"


func get_prompt() -> String:
	return "Press E: use %s" % display_name


func use() -> void:
	Events.station_opened.emit(station_id, display_name)
