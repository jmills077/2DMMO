extends Node2D
## A small red bar over a hurt player or creature. Hidden at full health.

var width := 14.0
var ratio := 1.0:
	set(value):
		ratio = clampf(value, 0.0, 1.0)
		queue_redraw()


func _draw() -> void:
	if ratio >= 1.0:
		return
	draw_rect(Rect2(-width / 2.0 - 1.0, -1.0, width + 2.0, 4.0), Color(0, 0, 0, 0.75))
	draw_rect(Rect2(-width / 2.0, 0.0, width * ratio, 2.0), Color(0.9, 0.2, 0.2))
