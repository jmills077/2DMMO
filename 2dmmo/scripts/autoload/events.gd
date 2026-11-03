extends Node
## Global signals that let unrelated parts of the game talk to each other.

## Show a short message in the corner of the screen.
signal toast(text: String)
## A crafting station was used. The HUD opens its crafting panel.
signal station_opened(station_id: String, display_name: String)

## True while a menu is open, so the player stops moving.
var ui_blocking := false
