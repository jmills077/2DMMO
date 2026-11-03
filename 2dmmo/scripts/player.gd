extends CharacterBody2D
## A player character. Every window has one of these for each player online.
## The one this window controls moves with the keyboard and picks the nearest
## thing to interact with; the others just follow what the network says.
## Gathering, planting and crafting are requests to the server (server.gd).

signal target_changed(prompt: String)
signal gather_progress(ratio: float, zone_start: float, zone_width: float)
## The gathering timing game was missed (the HUD shakes the bar red).
signal gather_failed

## Walking speed in pixels per second (raised from 80 for testing).
const SPEED := 110.0
## Roll (Space): a short burst in the direction you're moving.
const ROLL_SPEED_MULTIPLIER := 1.6
const ROLL_SECONDS := 0.22
const ROLL_COOLDOWN := 0.6
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
## How far through a roll the sprite has spun (radians), sent to other windows.
@export var roll_angle := 0.0

var _target: Node2D = null
var _gather_elapsed := 0.0
var _gather_state := ""  # "", "waiting" (for the server's zone) or "filling"
var _gather_path := ""
var _zone_start := 0.0
var _zone_width := 0.0
var _cooldown := 0.0
var _roll_left := 0.0
var _roll_cooldown := 0.0
var _roll_direction := Vector2.RIGHT
var _last_direction := Vector2.RIGHT
var _reach_query := PhysicsShapeQueryParameters2D.new()
var _name_label: Label
var _health_bar: Node2D
var _attack_cooldown := 0.0
var _last_health := -1

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
	_health_bar = preload("res://scripts/world/health_bar.gd").new()
	_health_bar.position = Vector2(0, -14)
	add_child(_health_bar)
	Combat.health_changed.connect(_on_health_changed)
	Combat.dead_changed.connect(_on_dead_changed)
	_on_dead_changed.call_deferred(peer_id())
	_on_health_changed.call_deferred(peer_id())

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


func peer_id() -> int:
	return name.to_int()


## A spirit: dead, walking back to its body.
func is_spirit() -> bool:
	return Combat.dead.has(peer_id())


## The server moved this character (to the graveyard when it dies).
func teleport(where: Vector2) -> void:
	global_position = where
	sync_position = where
	_reset_gather()


func _on_health_changed(peer: int) -> void:
	if peer != peer_id():
		return
	var entry: Array = Combat.health.get(peer, [0, 0])
	if int(entry[1]) <= 0:
		return
	_health_bar.ratio = float(entry[0]) / float(entry[1]) if not is_spirit() else 1.0
	# Flash red when hurt.
	if _last_health >= 0 and int(entry[0]) < _last_health and not is_spirit():
		sprite.modulate = Color(1.0, 0.35, 0.35)
		create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.25)
	_last_health = int(entry[0])


func _on_dead_changed(peer: int) -> void:
	if peer != peer_id():
		return
	# A spirit is pale and see-through.
	modulate = Color(0.7, 0.85, 1.0, 0.55) if is_spirit() else Color.WHITE
	_health_bar.visible = not is_spirit()
	_update_label()


## The name over the character, in its guild's color.
func _update_label() -> void:
	var guild := GameData.get_guild(Town.guild_of(player_name))
	_name_label.text = player_name + (" (spirit)" if is_spirit() else "")
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
	if direction != Vector2.ZERO:
		_last_direction = direction.normalized()
	_roll_cooldown = maxf(_roll_cooldown - delta, 0.0)
	if Input.is_action_just_pressed("roll") and not Events.ui_blocking and _roll_left <= 0.0 and _roll_cooldown <= 0.0:
		_roll_left = ROLL_SECONDS
		_roll_cooldown = ROLL_COOLDOWN
		# Keep going the way you're moving; standing still rolls the way you face.
		_roll_direction = _last_direction if direction != Vector2.ZERO else Vector2(-1.0 if facing_left else 1.0, 0.0)
		_reset_gather()
	if _roll_left > 0.0:
		_roll_left -= delta
		velocity = _roll_direction * SPEED * ROLL_SPEED_MULTIPLIER
		var spin := 1.0 - maxf(_roll_left, 0.0) / ROLL_SECONDS
		roll_angle = TAU * spin * (-1.0 if _roll_direction.x < 0.0 else 1.0)
		if _roll_left <= 0.0:
			roll_angle = 0.0
	else:
		velocity = direction * SPEED
	move_and_slide()
	if direction.x != 0.0:
		facing_left = direction.x < 0.0
	sprite.flip_h = facing_left
	sprite.rotation = roll_angle
	sync_position = position

	_cooldown = maxf(_cooldown - delta, 0.0)
	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	if Input.is_action_just_pressed("attack") and not Events.ui_blocking and _attack_cooldown <= 0.0:
		_attack()
	_update_target()
	_handle_interaction(delta)


func _follow_network(delta: float) -> void:
	if position.distance_to(sync_position) > SNAP_DISTANCE:
		position = sync_position
	else:
		position = position.lerp(sync_position, minf(1.0, delta * 15.0))
	sprite.flip_h = facing_left
	sprite.rotation = roll_angle


func _update_target() -> void:
	var best: Node2D = null
	var best_distance := INF
	_reach_query.transform = Transform2D(0.0, global_position)
	for hit: Dictionary in get_world_2d().direct_space_state.intersect_shape(_reach_query, 16):
		var node := hit.collider as Node2D
		if node == null or not node.has_method("get_prompt") or node.get_prompt() == "":
			continue
		# A spirit can only get back into its body.
		if is_spirit() and not node.is_in_group("corpse"):
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


## R: attack the way you last moved. The server checks the weapon and the hit.
func _attack() -> void:
	if is_spirit():
		return
	var weapon: Dictionary = Combat.equipment.get("weapon", {})
	_attack_cooldown = Combat.attack_seconds(weapon) if not weapon.is_empty() else 0.3
	_reset_gather()
	Combat.request_attack.rpc_id(1, _last_direction)


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
			gather_failed.emit()
		_reset_gather()
		_cooldown = 0.3
	elif ratio >= 1.0:
		gather_failed.emit()
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
