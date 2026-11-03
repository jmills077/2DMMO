extends Node2D
## A quick white arc in front of a player swinging a sword. Fades and frees itself.

const SECONDS := 0.15

var direction := Vector2.RIGHT
var _left := SECONDS


func _process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var angle := direction.angle()
	var alpha := clampf(_left / SECONDS, 0.0, 1.0)
	draw_arc(Vector2.ZERO, 11.0, angle - 1.0, angle + 1.0, 8, Color(1, 1, 1, alpha), 2.0)
