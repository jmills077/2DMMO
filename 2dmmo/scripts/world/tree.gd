extends StaticBody2D
## Forestry: a tree can be felled for logs and saplings.
## A felled tree leaves a stump that stays bare until someone plants a sapling,
## and the sapling grows back into a full tree over time.

enum Stage { GROWN, STUMP, SAPLING }

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
	if stage == Stage.SAPLING:
		_grow_left -= delta
		if _grow_left <= 0.0:
			stage = Stage.GROWN
			_refresh()


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
			return "Hold E: fell tree"
		Stage.STUMP:
			return "Press E: plant a sapling" if Inventory.count_of("sapling") > 0 else "Stump: needs a sapling to replant"
		Stage.SAPLING:
			return "Sapling: fully grown in %ds" % ceili(_grow_left)
	return ""


func gather_duration() -> float:
	return fell_seconds


func gather() -> void:
	var logs := randi_range(logs_min, logs_max)
	var saplings := 1 + (1 if randf() < extra_sapling_chance else 0)
	Inventory.add_item("log", logs)
	Inventory.add_item("sapling", saplings)
	Events.toast.emit("+%d Log, +%d Sapling" % [logs, saplings])
	stage = Stage.STUMP
	_refresh()


func use() -> void:
	if stage == Stage.STUMP and Inventory.remove_item("sapling", 1):
		stage = Stage.SAPLING
		_grow_left = grow_seconds
		Events.toast.emit("Sapling planted")
		_refresh()


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
