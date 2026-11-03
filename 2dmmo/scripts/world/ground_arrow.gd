extends StaticBody2D
## An arrow that missed and stuck in the ground. Anyone can pick it up with E.
## Created by autoload/combat.gd in every window.

var arrow_id := 0
var _sprite: Sprite2D


func _ready() -> void:
	add_to_group("ground_arrow")
	collision_layer = 2  # interactable, not solid
	collision_mask = 0
	_sprite = Sprite2D.new()
	_sprite.texture = preload("res://art/arrow.png")
	_sprite.rotation = -PI / 3.0
	_sprite.scale = Vector2(0.75, 0.75)
	# Appears once the arrow in flight lands.
	_sprite.visible = false
	add_child(_sprite)
	get_tree().create_timer(Combat.ARROW_RANGE / Combat.ARROW_SPEED).timeout.connect(_land)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 4.0
	shape.shape = circle
	add_child(shape)


func _land() -> void:
	if is_instance_valid(_sprite):
		_sprite.visible = true


func get_interaction() -> String:
	return "use"


func get_prompt() -> String:
	return "Press E: pick up arrow"


func use() -> void:
	Combat.request_pickup_arrow.rpc_id(1, arrow_id)
