extends StaticBody2D
## Something you gather by holding E, which then comes back after a while:
## ore rocks, sheep (wool grows back), deer (a new one arrives) and herbs.
## Set item_id, the verb, the textures and timings in the Inspector.
## Turn on hide_when_depleted to make it disappear while depleted (deer).
## The server decides when it is mined and when it respawns; other windows
## just show what the server tells them.

## Emitted on the server whenever this rock changes, so every window updates.
signal state_changed

@export var display_name := "Iron Rock"
@export var item_id := "iron_ore"
## Shown in the prompt: "Hold E: <verb> <display_name>".
@export var verb := "mine"
@export var yield_min := 1
@export var yield_max := 2
@export var gather_seconds := 1.5
@export var respawn_seconds := 45.0
@export var full_texture: Texture2D
@export var depleted_texture: Texture2D
@export var hide_when_depleted := false

var depleted := false
var _respawn_left := 0.0

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	add_to_group("persist")
	_refresh()


func _process(delta: float) -> void:
	if not depleted:
		return
	_respawn_left = maxf(_respawn_left - delta, 0.0)
	if _respawn_left <= 0.0 and multiplayer.is_server():
		depleted = false
		_refresh()
		state_changed.emit()


func get_interaction() -> String:
	return "" if depleted else "gather"


func get_prompt() -> String:
	return "" if depleted else "Hold E: %s %s" % [verb, display_name]


func gather_duration() -> float:
	return gather_seconds


## Server only: mines the rock and returns what the player gets.
func harvest() -> Dictionary:
	depleted = true
	_respawn_left = respawn_seconds
	_refresh()
	state_changed.emit()
	return {item_id: randi_range(yield_min, yield_max)}


func get_save_state() -> Dictionary:
	return {"depleted": depleted, "respawn_left": _respawn_left}


func apply_save_state(state: Dictionary) -> void:
	depleted = bool(state.get("depleted", false))
	_respawn_left = float(state.get("respawn_left", 0.0))
	_refresh()


func _refresh() -> void:
	if sprite == null:
		return
	sprite.texture = depleted_texture if depleted else full_texture
	if hide_when_depleted:
		sprite.visible = not depleted
		$CollisionShape2D.set_deferred("disabled", depleted)
