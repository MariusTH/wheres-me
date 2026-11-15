class_name AvatarPortrait
extends Button
## Full-body portrait of a part-kit look. Used in the avatar creator
## (presets, preview), on the menu and as the "find this" card.

var look: Dictionary = {}:
	set(value):
		look = AvatarKit.normalize(value)
		queue_redraw()
## Shows whatever [param subject] (see VisibilityChecker) describes.
func show_subject(subject: WorldObjectData) -> void:
	look = subject.look


func _init() -> void:
	custom_minimum_size = Vector2(96, 104)
	add_theme_stylebox_override("normal", UiKit._flat(Color("efe6d4"), 12, Color("c9c2b8"), 2))
	add_theme_stylebox_override("hover", UiKit._flat(Color("f7efdf"), 12, UiKit.ACCENT, 2))
	add_theme_stylebox_override("pressed", UiKit._flat(Color("fff6e0"), 12, UiKit.ACCENT, 4))
	add_theme_stylebox_override("disabled", UiKit._flat(Color("efe6d4"), 12, Color("c9c2b8"), 2))


func _draw() -> void:
	if look.is_empty():
		return
	# Tallest look (top hat on a tall build) is ~80 units above the feet.
	# Fit both ways: the tallest look is ~84 units high and ~44 wide.
	var scale := minf((size.y - 16.0) / 84.0, (size.x - 12.0) / 44.0)
	draw_set_transform(Vector2(size.x / 2.0, size.y - 8.0), 0.0, Vector2(scale, scale))
	draw_mesh(MeshCanvas.character_mesh(look, false), null)
	draw_set_transform(Vector2.ZERO)
