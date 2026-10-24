class_name VisibilityChecker
extends RefCounted
## The hide rule: the hider (an avatar, or a critter in the museum) may stand
## anywhere on the map as long as at least MIN_VISIBLE of it is visible in the
## rendered scene.
##
## Visibility is measured by replaying the real drawing code into MaskCanvas:
## the avatar's opaque pixels (sampled every SAMPLE_STEP px) are tested
## against everything drawn on top of it: people and props standing in front
## (larger ground-point y, same Y-sort layer), foreground-layer props, and every
## canopy (tree crowns, awnings, parasols), which always draw above people.

const MIN_VISIBLE := 0.70
const SAMPLE_STEP := 2.0
## Only objects this close (feet to feet) can overlap the avatar on screen.
const NEIGHBOUR_DX := 180.0
const NEIGHBOUR_DY := 340.0
## Avatar bounds relative to its feet, generous enough for hats and balloons.
const AVATAR_REGION := Rect2(-40, -120, 80, 126)

var _map: MapDefinition
var _objects: Array[WorldObjectData]


func _init(map_def: MapDefinition, objects: Array[WorldObjectData]) -> void:
	_map = map_def
	_objects = objects


## Avatar check. {"fraction": float 0..1, "ok": bool, "reason": String ("" when ok)}.
func check(look: Dictionary, feet: Vector2) -> Dictionary:
	return check_subject(subject_for_look(look), feet)


## Same rule for any subject (see subject_for_look / subject_for_critter).
func check_subject(subject: WorldObjectData, feet: Vector2) -> Dictionary:
	var you := "it" if is_critter(subject) else "you"
	var body := Rect2(feet + Vector2(-14, -64), Vector2(28, 64))
	if is_critter(subject):
		body = AssetCatalog.sprite_rect(subject.asset_key)
		body.position += feet
	if not _map.world_bounds.encloses(body):
		return {"fraction": 0.0, "ok": false, "reason": "That's outside the %s." % _map.title.to_lower()}
	var fraction := visible_fraction_of(subject, feet)
	if fraction + 0.0005 < MIN_VISIBLE:
		return {"fraction": fraction, "ok": false,
			"reason": "Only %d%% of %s is visible. At least %d%% must show." % [floori(fraction * 100.0), you, roundi(MIN_VISIBLE * 100.0)]}
	return {"fraction": fraction, "ok": true, "reason": ""}


static func subject_for_look(look: Dictionary) -> WorldObjectData:
	var obj := WorldObjectData.new()
	obj.asset_key = TownGenerator.CROWD_ASSET
	obj.look = look
	return obj


static func subject_for_critter(key: String) -> WorldObjectData:
	var obj := WorldObjectData.new()
	obj.asset_key = key
	return obj


static func is_critter(subject: WorldObjectData) -> bool:
	return AssetCatalog.is_critter(subject.asset_key)


func visible_fraction(look: Dictionary, feet: Vector2) -> float:
	return visible_fraction_of(subject_for_look(look), feet)


func visible_fraction_of(subject: WorldObjectData, feet: Vector2) -> float:
	var region := AVATAR_REGION
	if is_critter(subject):
		region = AssetCatalog.sprite_rect(subject.asset_key).grow(2.0)
	var grid := PackedVector2Array()
	var y := region.position.y
	while y < region.end.y:
		var x := region.position.x
		while x < region.end.x:
			grid.append(feet + Vector2(x, y) + Vector2.ONE * (SAMPLE_STEP * 0.5))
			x += SAMPLE_STEP
		y += SAMPLE_STEP
	var avatar := MaskCanvas.new(grid)
	avatar.begin_object(feet)
	_draw_subject(avatar, subject)
	var body := avatar.covered_points()
	if body.is_empty():
		return 0.0
	var occ := MaskCanvas.new(body)
	for obj in _objects:
		if obj == subject:
			continue
		var d := obj.world_position - feet
		if absf(d.x) > NEIGHBOUR_DX or absf(d.y) > NEIGHBOUR_DY:
			continue
		draw_cover(occ, obj, feet.y)
	return 1.0 - float(occ.covered_count()) / float(body.size())


static func _draw_subject(canvas: MaskCanvas, subject: WorldObjectData) -> void:
	if not is_critter(subject):
		PlaceholderArt.draw_character(canvas, subject.look, false)
		return
	var tex := AssetCatalog.texture(subject.asset_key)
	if tex:
		PlaceholderArt.draw_grounded_texture(canvas, tex, AssetCatalog.entry(subject.asset_key), subject.flip_h)
	else:
		PlaceholderArt.draw_prop(canvas, subject.asset_key, AssetCatalog.entry(subject.asset_key), subject.flip_h)


## Draws the parts of [param obj] that render above a character whose feet
## are at [param feet_y].
static func draw_cover(canvas: MaskCanvas, obj: WorldObjectData, feet_y: float) -> void:
	if obj.depth_mode == "ground":
		return
	var in_front := obj.world_position.y > feet_y or obj.depth_mode == "foreground"
	var e := AssetCatalog.entry(obj.asset_key)
	canvas.begin_object(obj.world_position)
	if obj.is_interactive:
		if in_front:
			PlaceholderArt.draw_character(canvas, obj.look, obj.flip_h)
		return
	if in_front:
		var tex := AssetCatalog.texture(obj.asset_key)
		if tex:
			PlaceholderArt.draw_grounded_texture(canvas, tex, e, obj.flip_h)
		else:
			PlaceholderArt.draw_prop(canvas, obj.asset_key, e, obj.flip_h)
	if e.get("canopy", false):
		canvas.begin_object(obj.world_position)
		var ctex := AssetCatalog.texture(obj.asset_key, "canopy_texture")
		if ctex:
			PlaceholderArt.draw_grounded_texture(canvas, ctex, e, obj.flip_h, "canopy_ground_point", "canopy_height_px")
		else:
			PlaceholderArt.draw_canopy(canvas, obj.asset_key, e, obj.flip_h)
