extends Node
## Saves and loads the game to a file on this computer.
## Anything in the "persist" group with get_save_state() and
## apply_save_state() is saved automatically, keyed by its node path.

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1
const AUTOSAVE_SECONDS := 60.0

var _autosave_left := AUTOSAVE_SECONDS


func _ready() -> void:
	get_tree().set_auto_accept_quit(false)


func _process(delta: float) -> void:
	_autosave_left -= delta
	if _autosave_left <= 0.0:
		_autosave_left = AUTOSAVE_SECONDS
		save_game(false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("save_game"):
		save_game(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game(false)
		get_tree().quit()


func save_game(announce: bool) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	var world := {}
	for node: Node in get_tree().get_nodes_in_group("persist"):
		world[str(get_tree().current_scene.get_path_to(node))] = node.get_save_state()
	var data := {
		"version": SAVE_VERSION,
		"player": {"x": player.global_position.x, "y": player.global_position.y},
		"inventory": Inventory.to_save_data(),
		"world": world,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not write save file")
		return
	file.store_string(JSON.stringify(data, "\t"))
	if announce:
		Events.toast.emit("Game saved")


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not parsed is Dictionary:
		push_warning("Save file unreadable, starting fresh")
		return false
	var data: Dictionary = parsed
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player and data.has("player"):
		player.global_position = Vector2(float(data.player.x), float(data.player.y))
	Inventory.load_save_data(data.get("inventory", []))
	var world: Dictionary = data.get("world", {})
	for path: String in world:
		var node := get_tree().current_scene.get_node_or_null(path)
		if node and node.has_method("apply_save_state"):
			node.apply_save_state(world[path])
	return true


func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
