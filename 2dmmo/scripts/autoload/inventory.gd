extends Node
## This player's bag, as last reported by the server.
## Only the server changes bags (see autoload/server.gd). This copy is what
## the screen shows: the bag panel, recipe counts and prompts.

signal changed

const Bag := preload("res://scripts/bag.gd")
const MAX_SLOTS := Bag.MAX_SLOTS

var bag := Bag.new()
var slots: Array:
	get:
		return bag.slots


func count_of(id: String) -> int:
	return bag.count_of(id)


func set_slots(new_slots: Array) -> void:
	bag.load_save_data(new_slots)
	changed.emit()
