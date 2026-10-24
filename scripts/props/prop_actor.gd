class_name PropActor
extends WorldActor
## Static scenery: props, trees, buildings, stalls, and museum critters
## (which can be tapped and may be hue-shifted decoys). Origin = ground point.
## Parts that should cover people regardless of depth (tree canopies,
## umbrellas, stall awnings) live in a CanopyLayer child with a raised z_index.

const CANOPY_Z := 20
const FADED_ALPHA := 0.4
const HUE_SHADER := preload("res://shaders/hue_shift.gdshader")

var canopy: CanopyLayer = null

var _entry: Dictionary = {}
var _texture: Texture2D = null


func setup(obj: WorldObjectData) -> void:
	object_id = obj.id
	name = obj.id
	asset_key = obj.asset_key
	position = obj.world_position
	flip_h = obj.flip_h
	_entry = AssetCatalog.entry(asset_key)
	_texture = AssetCatalog.texture(asset_key)
	set_hue(obj.hue)
	match obj.depth_mode:
		"ground":
			z_index = -1
		"foreground":
			z_index = CANOPY_Z + 1
	if _entry.get("canopy", false):
		canopy = CanopyLayer.new()
		canopy.name = "Canopy"
		canopy.z_index = CANOPY_Z
		canopy.setup(asset_key, _entry, flip_h)
		add_child(canopy)
	queue_redraw()


func set_hue(hue: float) -> void:
	if hue == 0.0:
		material = null
		return
	var m := ShaderMaterial.new()
	m.shader = HUE_SHADER
	m.set_shader_parameter("hue", hue)
	material = m


func is_critter() -> bool:
	return AssetCatalog.is_critter(asset_key)


func hit_rect(pad: float) -> Rect2:
	var r := AssetCatalog.sprite_rect(asset_key)
	if flip_h:
		r.position.x = -r.end.x
	return Rect2(global_position + r.position, r.size).grow(pad)


func set_canopy_faded(faded: bool) -> void:
	if canopy:
		canopy.modulate.a = FADED_ALPHA if faded else 1.0
	elif is_foreground():
		modulate.a = FADED_ALPHA if faded else 1.0


## Drawn above everything (e.g. the whale skeleton hanging in the museum).
func is_foreground() -> bool:
	return z_index > CANOPY_Z


func _draw() -> void:
	_draw_marker()
	if _texture:
		PlaceholderArt.draw_grounded_texture(self, _texture, _entry, flip_h)
	else:
		PlaceholderArt.draw_prop(self, asset_key, _entry, flip_h)
