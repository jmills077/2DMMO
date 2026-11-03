extends Node
## Global signals that let unrelated parts of the game talk to each other.

## Show a short message in the corner of the screen.
signal toast(text: String)
## A town object was used. The town panels open.
signal town_object_opened(kind: String, guild_id: String, path: String)
## The server started this player's gathering bar, with the zone to hit (0..1).
signal gather_zone(path: String, zone_start: float, zone_width: float)
## The player this window controls has appeared in the world.
signal local_player_ready(player: Node)
## The connection line at the top of the screen changed.
signal status_changed(text: String)
## No launch option said whether to host or join, so ask on screen.
signal show_connect_menu

## True while a menu is open, so the player stops moving.
var ui_blocking := false
