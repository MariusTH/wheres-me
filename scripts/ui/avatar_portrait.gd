class_name AvatarPortrait
extends Button
## Full-body portrait of a part-kit look, or of a museum critter. Used in the
## avatar creator (presets, preview) and as the "find this" card.

var look: Dictionary = {}:
	set(value):
		look = AvatarKit.normalize(value)
		queue_redraw()
## Critter asset key; when set, the critter is drawn instead of the look.
var critter: String = "":
	set(value):
		critter = value
		queue_redraw()


## Shows whatever [param subject] (see VisibilityChecker) describes.
func show_subject(subject: WorldObjectData) -> void:
	if VisibilityChecker.is_critter(subject):
		critter = subject.asset_key
	else:
		look = subject.look


func _init() -> void:
	custom_minimum_size = Vector2(96, 104)
	add_theme_stylebox_override("normal", UiKit._flat(Color("efe6d4"), 12, Color("c9c2b8"), 2))
	add_theme_stylebox_override("hover", UiKit._flat(Color("f7efdf"), 12, UiKit.ACCENT, 2))
	add_theme_stylebox_override("pressed", UiKit._flat(Color("fff6e0"), 12, UiKit.ACCENT, 4))
	add_theme_stylebox_override("disabled", UiKit._flat(Color("efe6d4"), 12, Color("c9c2b8"), 2))


func _draw() -> void:
	if critter != "":
		_draw_critter()
		return
	if look.is_empty():
		return
	# Tallest look (top hat on a tall build) is ~80 units above the feet.
	var scale := (size.y - 16.0) / 84.0
	PlaceholderArt.draw_character(self, look, false, Vector2(size.x / 2.0, size.y - 8.0), scale)


func _draw_critter() -> void:
	var tex := AssetCatalog.texture(critter)
	if tex == null:
		return
	var area := Rect2(Vector2(10, 10), size - Vector2(20, 20))
	var k := minf(area.size.x / tex.get_width(), area.size.y / tex.get_height())
	var draw_size := tex.get_size() * k
	draw_texture_rect(tex, Rect2(area.position + (area.size - draw_size) / 2.0, draw_size), false)
