class_name WorldActor
extends Node2D
## Base for placed things search mode can point at: people (CharacterActor)
## and props (PropActor). The node origin is the ground point.
##
## The town is normally drawn from merged meshes (TownBake), not from these
## nodes. Anything that changes how an actor looks must therefore go through
## this API (marker, flash_wrong, walk_to, leave, set_look, set_canopy_faded…),
## which emits [signal visual_changed] so the bake draws that actor live.

signal visual_changed(actor: WorldActor)

enum Marker { NONE, PREVIEW_OK, PREVIEW_BAD, FOUND, WRONG }

var object_id: String = ""
var asset_key: String = ""
var flip_h: bool = false
var marker: Marker = Marker.NONE:
	set(value):
		marker = value
		queue_redraw()
		visual_changed.emit(self)

## Tween currently animating this actor (flash, fade, walk), if any.
var anim: Tween = null


## Tap area in world coordinates, grown by [param pad] world pixels.
func hit_rect(pad: float) -> Rect2:
	return Rect2(global_position, Vector2.ZERO).grow(pad)


func flash_wrong() -> void:
	marker = Marker.WRONG
	_animate()
	modulate = Color(1.0, 0.55, 0.55)
	anim.tween_property(self, "modulate", Color.WHITE, 0.6)
	anim.tween_callback(func() -> void:
		if marker == Marker.WRONG:
			marker = Marker.NONE)
	visual_changed.emit(self)


## Moves to [param to] over [param seconds].
func walk_to(to: Vector2, seconds: float) -> void:
	_animate()
	anim.tween_property(self, "position", to, seconds).set_trans(Tween.TRANS_SINE)
	visual_changed.emit(self)


## Fades out over [param seconds], then is hidden (and no longer tappable).
func leave(seconds: float) -> void:
	_animate()
	anim.tween_property(self, "modulate:a", 0.0, seconds)
	anim.tween_callback(func() -> void: visible = false)
	visual_changed.emit(self)


## Moves to [param at] right away.
func move_to(at: Vector2) -> void:
	position = at
	visual_changed.emit(self)


func _animate() -> void:
	if anim and anim.is_valid():
		anim.kill()
	anim = create_tween()


## True while a flash, fade or walk is running.
func animating() -> bool:
	return anim != null and anim.is_valid() and anim.is_running()


## Draws this actor (relative to its ground point) on [param ci]: the node
## itself, a TownBake stand-in, or a MeshCanvas.
func draw_visual(ci: Variant) -> void:
	_draw_marker(ci)


func _draw() -> void:
	draw_visual(self)


## Ground ring (placement preview, found, wrong).
func _draw_marker(ci: Variant) -> void:
	match marker:
		Marker.PREVIEW_OK, Marker.FOUND:
			ci.draw_colored_polygon(PlaceholderArt.ellipse_points(Vector2.ZERO, 22, 8), Color(0.3, 0.9, 0.4, 0.55))
			ci.draw_arc(Vector2.ZERO, 22, 0, TAU, 24, Color("2f9e4a"), 2.0)
		Marker.PREVIEW_BAD, Marker.WRONG:
			ci.draw_colored_polygon(PlaceholderArt.ellipse_points(Vector2.ZERO, 22, 8), Color(0.95, 0.3, 0.3, 0.55))
