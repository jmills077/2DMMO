extends Node2D
## The root of the game world. Starts or joins a game once loaded, and
## creates player characters when the server says someone joined.

@onready var spawner: MultiplayerSpawner = $PlayerSpawner


func _ready() -> void:
	Server.world = self
	spawner.spawn_function = _make_player
	Net.start_from_launch_options.call_deferred()


## Server only: adds a player character to every window.
func spawn_player(data: Dictionary) -> Node:
	return spawner.spawn(data)


func _make_player(data: Dictionary) -> Node:
	var player: Node2D = load("res://scenes/player.tscn").instantiate()
	player.name = str(data.id)
	player.position = Vector2(float(data.x), float(data.y))
	player.player_name = str(data.name)
	return player
