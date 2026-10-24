class_name CharacterActor
extends WorldActor
## A person in the town, drawn from a part-kit look. The node origin is the
## ground point (feet); the art is drawn upward from there, so the parent's
## Y-sort orders people by feet.

const BODY_WIDTH := 26.0
const BODY_HEIGHT := 60.0

var look: Dictionary = {}


func setup(obj: WorldObjectData) -> void:
	object_id = obj.id
	name = obj.id
	asset_key = obj.asset_key
	position = obj.world_position
	flip_h = obj.flip_h
	set_look(obj.look)


func set_look(p_look: Dictionary) -> void:
	look = AvatarKit.normalize(p_look)
	queue_redraw()


## Body rectangle in local coordinates (feet at the bottom centre).
func body_rect() -> Rect2:
	var s := PlaceholderArt.build_scale(look)
	var size := Vector2(BODY_WIDTH * s.x, BODY_HEIGHT * s.y)
	return Rect2(Vector2(-size.x / 2.0, -size.y), size)


func hit_rect(pad: float) -> Rect2:
	var r := body_rect()
	return Rect2(global_position + r.position, r.size).grow(pad)


func _draw() -> void:
	_draw_marker()
	PlaceholderArt.draw_character(self, look, flip_h)
