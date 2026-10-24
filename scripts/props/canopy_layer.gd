class_name CanopyLayer
extends Node2D
## Foreground occluder part of a prop (tree crown, parasol, stall awning).
## Its z_index puts it above all y-sorted people, so someone standing under a
## tree is covered by the crown while their legs stay visible.

var _key: String = ""
var _entry: Dictionary = {}
var _flip: bool = false
var _texture: Texture2D = null


func setup(key: String, entry: Dictionary, flip: bool) -> void:
	_key = key
	_entry = entry
	_flip = flip
	_texture = AssetCatalog.texture(key, "canopy_texture")
	queue_redraw()


func _draw() -> void:
	if _texture:
		PlaceholderArt.draw_grounded_texture(self, _texture, _entry, _flip, "canopy_ground_point", "canopy_height_px")
	else:
		PlaceholderArt.draw_canopy(self, _key, _entry, _flip)
