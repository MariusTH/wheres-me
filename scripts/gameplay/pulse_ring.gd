class_name PulseRing
extends Node2D
## Pulsing highlight drawn above everything to reveal the found / hidden target.

var color: Color = UiKit.GOOD
var _t := 0.0


func _ready() -> void:
	z_index = 40


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var pulse := 0.5 + 0.5 * sin(_t * 5.0)
	draw_arc(Vector2(0, -30), 42.0 + pulse * 8.0, 0.0, TAU, 40, color, 4.0)
	draw_arc(Vector2(0, -30), 52.0 + pulse * 8.0, 0.0, TAU, 40, Color(color, 0.4), 2.0)
