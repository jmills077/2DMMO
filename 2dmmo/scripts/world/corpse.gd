extends StaticBody2D
## A dead player's body, lying where they fell. Only its owner's spirit can
## use it: press E next to it to come back to life here.
## Created by autoload/combat.gd in every window.

var owner_peer := 0


func _ready() -> void:
	add_to_group("corpse")
	collision_layer = 2  # interactable, not solid
	collision_mask = 0
	var sprite := Sprite2D.new()
	sprite.texture = preload("res://art/player.png")
	sprite.rotation = PI / 2.0
	sprite.position = Vector2(0, 2)
	sprite.modulate = Color(0.8, 0.8, 0.8)
	add_child(sprite)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(14, 8)
	shape.shape = rect
	add_child(shape)


func is_mine() -> bool:
	return multiplayer.has_multiplayer_peer() and owner_peer == multiplayer.get_unique_id()


func get_interaction() -> String:
	return "use" if is_mine() else ""


func get_prompt() -> String:
	return "Press E: return to your body" if is_mine() else ""


func use() -> void:
	Combat.request_resurrect.rpc_id(1)
