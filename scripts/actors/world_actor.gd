class_name WorldActor
extends Node2D
## Base for placed things search mode can point at: people (CharacterActor)
## and props (PropActor, of which museum critters are tappable). The node
## origin is the ground point.

enum Marker { NONE, PREVIEW_OK, PREVIEW_BAD, FOUND, WRONG }

var object_id: String = ""
var asset_key: String = ""
var flip_h: bool = false
var marker: Marker = Marker.NONE:
	set(value):
		marker = value
		queue_redraw()


## Tap area in world coordinates, grown by [param pad] world pixels.
func hit_rect(pad: float) -> Rect2:
	return Rect2(global_position, Vector2.ZERO).grow(pad)


func flash_wrong() -> void:
	marker = Marker.WRONG
	var tween := create_tween()
	modulate = Color(1.0, 0.55, 0.55)
	tween.tween_property(self, "modulate", Color.WHITE, 0.6)
	tween.tween_callback(func() -> void:
		if marker == Marker.WRONG:
			marker = Marker.NONE)


## Ground ring (placement preview, found, wrong).
func _draw_marker() -> void:
	match marker:
		Marker.PREVIEW_OK, Marker.FOUND:
			draw_colored_polygon(PlaceholderArt.ellipse_points(Vector2.ZERO, 22, 8), Color(0.3, 0.9, 0.4, 0.55))
			draw_arc(Vector2.ZERO, 22, 0, TAU, 24, Color("2f9e4a"), 2.0)
		Marker.PREVIEW_BAD, Marker.WRONG:
			draw_colored_polygon(PlaceholderArt.ellipse_points(Vector2.ZERO, 22, 8), Color(0.95, 0.3, 0.3, 0.55))
