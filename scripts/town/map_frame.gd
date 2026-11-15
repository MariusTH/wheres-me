class_name MapFrame
extends Node2D
## The edge of the map: a plain paper margin of PAD world px all round the
## town, with a double ink line where the town stops. The camera may pan into
## the margin, so the seeker can see there is an end and nothing past it.
## Drawn above the town (covers whatever pokes past the bounds) but below the
## paper grain, so it reads as the same sheet. Purely cosmetic.

const PAD := 140.0
const MARGIN := Color("efe4cf")
const INK := Color(0.24, 0.16, 0.12, 0.85)

var _inner: Rect2


## The area the camera may show: [param bounds] plus the margin.
static func padded(bounds: Rect2) -> Rect2:
	return bounds.grow(PAD)


func setup(bounds: Rect2) -> void:
	_inner = bounds
	z_index = 99
	queue_redraw()


func _draw() -> void:
	var outer := padded(_inner).grow(4.0)
	var i := _inner
	# Four strips around the town.
	draw_rect(Rect2(outer.position, Vector2(outer.size.x, i.position.y - outer.position.y)), MARGIN)
	draw_rect(Rect2(Vector2(outer.position.x, i.end.y), Vector2(outer.size.x, outer.end.y - i.end.y)), MARGIN)
	draw_rect(Rect2(Vector2(outer.position.x, i.position.y), Vector2(i.position.x - outer.position.x, i.size.y)), MARGIN)
	draw_rect(Rect2(Vector2(i.end.x, i.position.y), Vector2(outer.end.x - i.end.x, i.size.y)), MARGIN)
	# Soft shadow just inside the edge, then a thick and a thin rule outside it.
	for k in 4:
		draw_rect(i.grow(-2.0 - k * 3.0), Color(0.24, 0.16, 0.12, 0.05), false, 3.0)
	draw_rect(i, INK, false, 4.0)
	draw_rect(i.grow(12.0), Color(INK, 0.5), false, 1.5)
