extends CharacterBody2D
## A creature: deer wander and run when hit; wolves chase and bite players
## who come too close, then give up when led too far from home.
## A creature with a carcass_item (deer) leaves a body to gather with E.
## The server moves creatures and decides hits (autoload/combat.gd); other
## windows just follow where the server says they are.
## Set everything in the Inspector or in tools/build_scenes.gd.

## Emitted on the server whenever this creature's state or health changes.
signal state_changed

@export var display_name := "Deer"
@export var max_health := 15
## Hostile creatures chase and bite; others wander and flee when hurt.
@export var hostile := false
@export var damage := 0
@export var attack_seconds := 1.2
@export var speed := 30.0
@export var aggro_range := 56.0
## Hostile creatures stop chasing once a player leads them this far from home.
@export var leash_range := 110.0
@export var respawn_seconds := 90.0
## What's gathered from its body ("" = nothing; it just disappears).
@export var carcass_item := ""
@export var carcass_verb := "skin"
@export var yield_min := 1
@export var yield_max := 2
@export var gather_seconds := 2.0

const ATTACK_RANGE := 14.0
const WANDER_RADIUS := 28.0
const FLEE_SECONDS := 1.5
const HealthBar := preload("res://scripts/world/health_bar.gd")

var health := 0
## "alive", "carcass" (dead, can be gathered) or "gone" (waiting to respawn).
var state := "alive"
var home := Vector2.ZERO
var facing_left := false
var _net_position := Vector2.ZERO
var _respawn_left := 0.0
var _attack_left := 0.0
var _target_peer := 0
var _wander_to := Vector2.ZERO
var _wander_wait := 0.0
var _flee_left := 0.0
var _flee_from := Vector2.ZERO
var _bar: Node2D

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	add_to_group("persist")
	add_to_group("mob")
	home = position
	_net_position = position
	_wander_to = position
	health = max_health
	_bar = HealthBar.new()
	_bar.position = Vector2(0, -14)
	add_child(_bar)
	_refresh()


func is_alive() -> bool:
	return state == "alive"


## Roughly how big it is, for hits.
func size_radius() -> float:
	return 5.0


# --- Gathering the body (same as rocks, see ore_rock.gd) ---

func get_interaction() -> String:
	return "gather" if state == "carcass" else ""


func get_prompt() -> String:
	return "Press E: %s %s" % [carcass_verb, display_name] if state == "carcass" else ""


func gather_duration() -> float:
	return gather_seconds


func harvest() -> Dictionary:
	state = "gone"
	_refresh()
	state_changed.emit()
	return {carcass_item: randi_range(yield_min, yield_max)}


# --- Server ---

## Returns true if this hit killed it.
func take_damage(amount: int, attacker_peer: int) -> bool:
	if state != "alive":
		return false
	health = maxi(health - amount, 0)
	var attacker := Server.player_node(attacker_peer)
	if hostile:
		_target_peer = attacker_peer
	elif attacker:
		_flee_left = FLEE_SECONDS
		_flee_from = attacker.global_position
	if health <= 0:
		state = "carcass" if carcass_item != "" else "gone"
		_respawn_left = respawn_seconds
	_refresh()
	state_changed.emit()
	return health <= 0


func _physics_process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		_follow_network(delta)
		return
	if state != "alive":
		_respawn_left -= delta
		if _respawn_left <= 0.0:
			apply_save_state({})
			state_changed.emit()
		return
	velocity = _think(delta)
	move_and_slide()
	if absf(velocity.x) > 0.1:
		facing_left = velocity.x < 0.0
	sprite.flip_h = facing_left


func _think(delta: float) -> Vector2:
	_attack_left -= delta
	if hostile:
		var target := _pick_target()
		if target:
			var to_target := target.global_position - global_position
			if to_target.length() <= ATTACK_RANGE:
				if _attack_left <= 0.0:
					_attack_left = attack_seconds
					Combat.hurt_player(_target_peer, damage, "a " + display_name)
				return Vector2.ZERO
			return to_target.normalized() * speed * 1.5
		if global_position.distance_to(home) > 6.0:
			if health < max_health:
				health = max_health
				state_changed.emit()
			return (home - global_position).normalized() * speed
	if _flee_left > 0.0:
		_flee_left -= delta
		if global_position.distance_to(home) < leash_range:
			return (global_position - _flee_from).normalized() * speed * 2.0
	# Wander around home.
	if _wander_wait > 0.0:
		_wander_wait -= delta
		return Vector2.ZERO
	var to := _wander_to - global_position
	if to.length() < 2.0:
		_wander_wait = randf_range(1.0, 3.5)
		_wander_to = home + Vector2.from_angle(randf() * TAU) * randf() * WANDER_RADIUS
		return Vector2.ZERO
	return to.normalized() * speed * 0.5


## The player this creature is after, or null.
func _pick_target() -> Node2D:
	var best: Node2D = null
	var best_distance := aggro_range
	for pair: Array in Combat.living_players():
		var node: Node2D = pair[1]
		if node.global_position.distance_to(home) > leash_range:
			continue
		if pair[0] == _target_peer:
			return node
		var distance := node.global_position.distance_to(global_position)
		if distance <= best_distance:
			best = node
			best_distance = distance
			_target_peer = pair[0]
	if best == null:
		_target_peer = 0
	return best


# --- Other windows ---

func set_network_position(where: Vector2, left: bool) -> void:
	_net_position = where
	facing_left = left


func _follow_network(delta: float) -> void:
	if position.distance_to(_net_position) > 48.0:
		position = _net_position
	else:
		position = position.lerp(_net_position, minf(1.0, delta * 12.0))
	sprite.flip_h = facing_left


# --- Saving and syncing ---

func get_save_state() -> Dictionary:
	return {"state": state, "health": health, "respawn_left": _respawn_left}


func apply_save_state(saved: Dictionary) -> void:
	var was := state
	state = str(saved.get("state", "alive"))
	health = int(saved.get("health", max_health))
	_respawn_left = float(saved.get("respawn_left", 0.0))
	if state == "alive" and was != "alive":
		position = home
		_net_position = home
		_target_peer = 0
	_refresh()


func _refresh() -> void:
	if sprite == null:
		return
	sprite.visible = state != "gone"
	# A body lies on its side.
	sprite.rotation = PI / 2.0 if state == "carcass" else 0.0
	sprite.modulate = Color(0.75, 0.7, 0.7) if state == "carcass" else Color.WHITE
	$CollisionShape2D.set_deferred("disabled", state == "gone")
	if _bar:
		_bar.ratio = float(health) / max_health if state == "alive" else 1.0
