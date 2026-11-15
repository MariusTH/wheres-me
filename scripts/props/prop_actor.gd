class_name PropActor
extends WorldActor
## Static scenery: props, trees, buildings, stalls. Origin = ground point.
## Parts that should cover people regardless of depth (tree canopies,
## umbrellas, stall awnings) live in a CanopyLayer child with a raised z_index.

const CANOPY_Z := 20
const FADED_ALPHA := 0.4

var canopy: CanopyLayer = null

var _entry: Dictionary = {}
var _texture: Texture2D = null
var _sliced := false


func setup(obj: WorldObjectData) -> void:
	object_id = obj.id
	name = obj.id
	asset_key = obj.asset_key
	position = obj.world_position
	flip_h = obj.flip_h
	_entry = AssetCatalog.entry(asset_key)
	_texture = AssetCatalog.texture(asset_key)
	match obj.depth_mode:
		"ground":
			z_index = -1
		"foreground":
			z_index = CANOPY_Z + 1
	var strips := AssetCatalog.strips(asset_key)
	if not strips.is_empty() and z_index == 0:
		# Isometric building: slices join the world's Y-sort individually.
		y_sort_enabled = true
		for st: Vector3 in strips:
			var slice := BuildingSlice.new()
			slice.setup(_texture, _entry, flip_h, st)
			add_child(slice)
		_texture = null
		_sliced = true
	if _entry.get("canopy", false):
		canopy = CanopyLayer.new()
		canopy.name = "Canopy"
		canopy.z_index = CANOPY_Z
		canopy.setup(asset_key, _entry, flip_h)
		add_child(canopy)
	queue_redraw()


func hit_rect(pad: float) -> Rect2:
	var r := AssetCatalog.sprite_rect(asset_key)
	if flip_h:
		r.position.x = -r.end.x
	return Rect2(global_position + r.position, r.size).grow(pad)


func set_canopy_faded(faded: bool) -> void:
	var a := FADED_ALPHA if faded else 1.0
	if canopy:
		if canopy.modulate.a != a:
			canopy.modulate.a = a
			visual_changed.emit(self)
	elif is_foreground():
		if modulate.a != a:
			modulate.a = a
			visual_changed.emit(self)


## Drawn above everything ("foreground" depth mode).
func is_foreground() -> bool:
	return z_index > CANOPY_Z


func draw_visual(ci: Variant) -> void:
	_draw_marker(ci)
	if _sliced:
		return
	if _texture:
		PlaceholderArt.draw_grounded_texture(ci, _texture, _entry, flip_h)
	else:
		PlaceholderArt.draw_prop(ci, asset_key, _entry, flip_h)


## One vertical slice of an isometric building (see AssetCatalog.strips).
class BuildingSlice:
	extends Node2D
	var _tex: Texture2D
	var _e: Dictionary
	var _flip := false
	var _strip := Vector3.ZERO

	func setup(tex: Texture2D, e: Dictionary, flip: bool, strip: Vector3) -> void:
		_tex = tex
		_e = e
		_flip = flip
		_strip = strip
		position = Vector2(0, strip.z)

	func draw_visual(ci: Variant) -> void:
		PlaceholderArt.draw_texture_strip(ci, _tex, _e, _flip, _strip)

	func _draw() -> void:
		draw_visual(self)
