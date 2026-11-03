extends Node2D
## The root of the game world. Loads the saved game when play starts.


func _ready() -> void:
	SaveGame.load_game.call_deferred()
