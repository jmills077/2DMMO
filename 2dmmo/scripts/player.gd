extends CharacterBody2D
## The player: moves, picks the nearest thing to interact with,
## gathers by holding the interact key and uses stations with a press.

signal target_changed(prompt: String)
signal gather_progress(ratio: float)

const SPEED := 80.0
## How far away (in pixels) the player can reach rocks, trees and stations.
const REACH := 16.0
## Physics layer 2 holds everything the player can interact with.
const INTERACT_MASK := 2

var _target: Node2D = null
var _gather_elapsed := 0.0
var _reach_query := PhysicsShapeQueryParameters2D.new()

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	add_to_group("player")
	var circle := CircleShape2D.new()
	circle.radius = REACH
	_reach_query.shape = circle
	_reach_query.collision_mask = INTERACT_MASK


func _physics_process(delta: float) -> void:
	var direction := Vector2.ZERO
	if not Events.ui_blocking:
		direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = direction * SPEED
	move_and_slide()
	if direction.x != 0.0:
		sprite.flip_h = direction.x < 0.0

	_update_target()
	_handle_interaction(delta)


func _update_target() -> void:
	var best: Node2D = null
	var best_distance := INF
	_reach_query.transform = Transform2D(0.0, global_position)
	for hit: Dictionary in get_world_2d().direct_space_state.intersect_shape(_reach_query, 16):
		var node := hit.collider as Node2D
		if node == null or not node.has_method("get_prompt") or node.get_prompt() == "":
			continue
		var distance := global_position.distance_squared_to(node.global_position)
		if distance < best_distance:
			best_distance = distance
			best = node
	if best != _target:
		_target = best
		_reset_gather()
	target_changed.emit(_target.get_prompt() if _target else "")


func _handle_interaction(delta: float) -> void:
	if _target == null or Events.ui_blocking:
		_reset_gather()
		return
	match _target.get_interaction():
		"gather":
			if Input.is_action_pressed("interact"):
				_gather_elapsed += delta
				var duration: float = _target.gather_duration()
				gather_progress.emit(clampf(_gather_elapsed / duration, 0.0, 1.0))
				if _gather_elapsed >= duration:
					_target.gather()
					_reset_gather()
			else:
				_reset_gather()
		"use":
			if Input.is_action_just_pressed("interact"):
				_target.use()
		_:
			_reset_gather()


func _reset_gather() -> void:
	if _gather_elapsed > 0.0:
		_gather_elapsed = 0.0
	gather_progress.emit(0.0)
