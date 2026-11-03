extends CharacterBody2D
## A player character. Every window has one of these for each player online.
## The one this window controls moves with the keyboard and picks the nearest
## thing to interact with; the others just follow what the network says.
## Gathering, planting and crafting are requests to the server (server.gd).

signal target_changed(prompt: String)
signal gather_progress(ratio: float, zone_start: float, zone_width: float)

const SPEED := 80.0
## How far away (in pixels) the player can reach rocks, trees and stations.
const REACH := 16.0
## Physics layer 2 holds everything the player can interact with.
const INTERACT_MASK := 2
## Other players further than this from where the network says they are snap there.
const SNAP_DISTANCE := 48.0

## Shown above the character.
@export var player_name := "":
	set(value):
		player_name = value
		if _name_label:
			_update_label()
## Where this character is, as sent over the network.
@export var sync_position := Vector2.ZERO
@export var facing_left := false

var _target: Node2D = null
var _gather_elapsed := 0.0
var _gather_state := ""  # "", "waiting" (for the server's zone) or "filling"
var _gather_path := ""
var _zone_start := 0.0
var _zone_width := 0.0
var _cooldown := 0.0
var _reach_query := PhysicsShapeQueryParameters2D.new()
var _name_label: Label

@onready var sprite: Sprite2D = $Sprite2D
@onready var camera: Camera2D = $Camera2D


func _enter_tree() -> void:
	if name.is_valid_int():
		set_multiplayer_authority(name.to_int())


func _ready() -> void:
	add_to_group("player")
	sync_position = position
	_name_label = Label.new()
	_name_label.text = player_name
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.position = Vector2(-40, -24)
	_name_label.size = Vector2(80, 10)
	_name_label.add_theme_font_size_override("font_size", 8)
	_name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_name_label.add_theme_constant_override("outline_size", 2)
	add_child(_name_label)
	Town.changed.connect(_update_label)

	var circle := CircleShape2D.new()
	circle.radius = REACH
	_reach_query.shape = circle
	_reach_query.collision_mask = INTERACT_MASK

	camera.enabled = is_local()
	if is_local():
		camera.make_current()
		add_to_group("local_player")
		Events.gather_zone.connect(_on_gather_zone)
		Events.local_player_ready.emit(self)
	_update_label()


## True for the character this window controls.
func is_local() -> bool:
	return multiplayer.multiplayer_peer != null and is_multiplayer_authority()


## The name over the character, in its guild's color.
func _update_label() -> void:
	var guild := GameData.get_guild(Town.guild_of(player_name))
	_name_label.text = player_name
	var color := Color(str(guild.color)) if not guild.is_empty() else Color.WHITE
	_name_label.add_theme_color_override("font_color", color)
	_name_label.tooltip_text = str(guild.get("member", ""))


func _physics_process(delta: float) -> void:
	if not is_local():
		_follow_network(delta)
		return
	var direction := Vector2.ZERO
	if not Events.ui_blocking:
		direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = direction * SPEED
	move_and_slide()
	if direction.x != 0.0:
		facing_left = direction.x < 0.0
	sprite.flip_h = facing_left
	sync_position = position

	_cooldown = maxf(_cooldown - delta, 0.0)
	_update_target()
	_handle_interaction(delta)


func _follow_network(delta: float) -> void:
	if position.distance_to(sync_position) > SNAP_DISTANCE:
		position = sync_position
	else:
		position = position.lerp(sync_position, minf(1.0, delta * 15.0))
	sprite.flip_h = facing_left


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
			_handle_gathering(delta)
		"use":
			if Input.is_action_just_pressed("interact"):
				_target.use()
		_:
			_reset_gather()


## Gathering timing game: tap E to start the bar (the server picks a zone),
## then tap E again while the bar is inside the zone. Miss and it resets.
func _handle_gathering(delta: float) -> void:
	var tapped := Input.is_action_just_pressed("interact")
	if _gather_state == "":
		if tapped and _cooldown <= 0.0:
			_gather_state = "waiting"
			_gather_path = Server.path_of(_target)
			Server.request_gather_start.rpc_id(1, _gather_path)
		return
	if _gather_state == "waiting":
		# The server said no (someone got there first) or the reply was lost.
		_gather_elapsed += delta
		if _gather_elapsed > 1.0:
			_reset_gather()
		return
	_gather_elapsed += delta
	var ratio := _gather_elapsed / maxf(_target.gather_duration(), 0.1)
	gather_progress.emit(clampf(ratio, 0.0, 1.0), _zone_start, _zone_width)
	if tapped:
		if ratio >= _zone_start and ratio <= _zone_start + _zone_width:
			Server.request_gather_finish.rpc_id(1, _gather_path)
		else:
			Events.toast.emit("Missed! Press E to try again")
		_reset_gather()
		_cooldown = 0.3
	elif ratio >= 1.0:
		Events.toast.emit("Too slow! Press E to try again")
		_reset_gather()
		_cooldown = 0.3


func _on_gather_zone(path: String, zone_start: float, zone_width: float) -> void:
	if _gather_state != "waiting" or path != _gather_path:
		return
	_gather_state = "filling"
	_gather_elapsed = 0.0
	_zone_start = zone_start
	_zone_width = zone_width


func _reset_gather() -> void:
	if _gather_state == "" and _gather_elapsed == 0.0:
		return
	_gather_state = ""
	_gather_elapsed = 0.0
	gather_progress.emit(0.0, 0.0, 0.0)
