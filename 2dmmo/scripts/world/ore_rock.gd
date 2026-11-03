extends StaticBody2D
## A rock that gives ore when mined, then respawns after a while.
## Set item_id, the textures and timings in the Inspector.

@export var display_name := "Iron Rock"
@export var item_id := "iron_ore"
@export var yield_min := 1
@export var yield_max := 2
@export var gather_seconds := 1.5
@export var respawn_seconds := 45.0
@export var full_texture: Texture2D
@export var depleted_texture: Texture2D

var depleted := false
var _respawn_left := 0.0

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	add_to_group("persist")
	_refresh()


func _process(delta: float) -> void:
	if depleted:
		_respawn_left -= delta
		if _respawn_left <= 0.0:
			depleted = false
			_refresh()


func get_interaction() -> String:
	return "" if depleted else "gather"


func get_prompt() -> String:
	return "" if depleted else "Hold E: mine %s" % display_name


func gather_duration() -> float:
	return gather_seconds


func gather() -> void:
	var amount := randi_range(yield_min, yield_max)
	Inventory.add_item(item_id, amount)
	Events.toast.emit("+%d %s" % [amount, GameData.item_name(item_id)])
	depleted = true
	_respawn_left = respawn_seconds
	_refresh()


func get_save_state() -> Dictionary:
	return {"depleted": depleted, "respawn_left": _respawn_left}


func apply_save_state(state: Dictionary) -> void:
	depleted = bool(state.get("depleted", false))
	_respawn_left = float(state.get("respawn_left", 0.0))
	_refresh()


func _refresh() -> void:
	if sprite:
		sprite.texture = depleted_texture if depleted else full_texture
