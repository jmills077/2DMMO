extends Node
## Registers the keyboard controls when the game starts.
## Edit the lists below to change or add key bindings.

const BINDINGS := {
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"interact": [KEY_E],
	"roll": [KEY_SPACE],
	"inventory": [KEY_I, KEY_TAB],
	"crafting": [KEY_C],
	"save_game": [KEY_F5],
	"refill_resources": [KEY_F9],
	"close_menu": [KEY_ESCAPE],
}


func _enter_tree() -> void:
	for action: String in BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key: int in BINDINGS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)
