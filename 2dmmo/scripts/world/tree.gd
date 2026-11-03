extends StaticBody2D
## Forestry: a tree can be felled for logs and saplings.
## A felled tree leaves a stump that stays bare until someone plants a sapling,
## and the sapling grows back into a full tree over time.
## The server decides all changes; other windows just show them.

enum Stage { GROWN, STUMP, SAPLING }

## Emitted on the server whenever this tree changes, so every window updates.
signal state_changed

@export var stage: Stage = Stage.GROWN
@export var fell_seconds := 2.5
@export var grow_seconds := 90.0
@export var logs_min := 2
@export var logs_max := 3
@export var extra_sapling_chance := 0.3

var _grow_left := 0.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var grown_texture: Texture2D = preload("res://art/tree.png")
@onready var stump_texture: Texture2D = preload("res://art/stump.png")
@onready var sapling_texture: Texture2D = preload("res://art/sapling.png")


func _ready() -> void:
	add_to_group("persist")
	_refresh()


func _process(delta: float) -> void:
	if stage != Stage.SAPLING:
		return
	_grow_left = maxf(_grow_left - delta, 0.0)
	if _grow_left <= 0.0 and multiplayer.is_server():
		stage = Stage.GROWN
		_refresh()
		state_changed.emit()


func get_interaction() -> String:
	match stage:
		Stage.GROWN:
			return "gather"
		Stage.STUMP:
			return "use"
	return ""


func get_prompt() -> String:
	match stage:
		Stage.GROWN:
			return "Press E: fell tree"
		Stage.STUMP:
			return "Press E: plant a sapling" if Inventory.count_of("sapling") > 0 else "Stump: needs a sapling to replant"
		Stage.SAPLING:
			return "Sapling: fully grown in %ds" % ceili(_grow_left)
	return ""


func gather_duration() -> float:
	return fell_seconds


## Pressed E on the stump: ask the server to plant.
func use() -> void:
	Server.request_use.rpc_id(1, Server.path_of(self))


## Server only: fells the tree and returns what the player gets.
func harvest() -> Dictionary:
	stage = Stage.STUMP
	_refresh()
	state_changed.emit()
	return {
		"log": randi_range(logs_min, logs_max),
		"sapling": 1 + (1 if randf() < extra_sapling_chance else 0),
	}


## Server only: plants a sapling from the player's bag. Returns a message.
func server_use(bag: RefCounted) -> String:
	if stage != Stage.STUMP:
		return ""
	if not bag.remove_item("sapling", 1):
		return "You need a sapling"
	stage = Stage.SAPLING
	_grow_left = grow_seconds
	_refresh()
	state_changed.emit()
	return "Sapling planted"


func get_save_state() -> Dictionary:
	return {"stage": stage, "grow_left": _grow_left}


func apply_save_state(state: Dictionary) -> void:
	stage = int(state.get("stage", Stage.GROWN)) as Stage
	_grow_left = float(state.get("grow_left", 0.0))
	_refresh()


func _refresh() -> void:
	if sprite == null:
		return
	match stage:
		Stage.GROWN:
			sprite.texture = grown_texture
		Stage.STUMP:
			sprite.texture = stump_texture
		Stage.SAPLING:
			sprite.texture = sapling_texture
	# Keep the base of every texture on the tile the tree stands on.
	sprite.position = Vector2(0, 8 - sprite.texture.get_height() / 2.0)
