extends StaticBody2D
## Something in town that opens a town panel: the stockpile, the round table,
## or a guild hall banner. The panels live in scripts/ui/town_ui.gd.

## "stockpile", "round_table" or "guild_hall".
@export var kind := "stockpile"
## For guild halls: which guild (an id from data/guilds.json).
@export var guild_id := ""
@export var display_name := "Town Stockpile"
@export var texture: Texture2D:
	set(value):
		texture = value
		if is_node_ready():
			$Sprite2D.texture = value


func _ready() -> void:
	$Sprite2D.texture = texture
	var cloth := get_node_or_null("Cloth") as Sprite2D
	if cloth:
		cloth.visible = kind == "guild_hall"
		var guild := GameData.get_guild(guild_id)
		if not guild.is_empty():
			cloth.modulate = Color(str(guild.color))
			display_name = "%s Hall" % guild.name


func get_interaction() -> String:
	return "use"


func get_prompt() -> String:
	return "Press E: %s" % display_name


func use() -> void:
	Events.town_object_opened.emit(kind, guild_id, Server.path_of(self))
