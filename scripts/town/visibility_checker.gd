class_name VisibilityChecker
extends RefCounted
## The hide rule: the hider may stand anywhere on the map as long as at least
## MIN_HEAD of their head and at least MIN_VISIBLE of them overall are visible in
## the rendered scene. The head comes first: feet and legs look much the same on
## everyone, so it's the face, hair and hat a seeker recognises.
##
## Visibility is measured by replaying the real drawing code into MaskCanvas:
## the avatar's opaque pixels (sampled every SAMPLE_STEP px) are tested
## against everything drawn on top of it: people and props standing in front
## (larger ground-point y, same Y-sort layer), foreground-layer props, and every
## canopy (tree crowns, awnings, parasols), which always draw above people.

const MIN_VISIBLE := 0.70
## Floor for every mode: at least half the head always shows. Difficulty levels
## may ask for more, never less (old codes without the rule use 0.0).
const MIN_HEAD := 0.50
const SAMPLE_STEP := 2.0
## Only objects this close (feet to feet) can overlap the avatar on screen.
const NEIGHBOUR_DX := 180.0
const NEIGHBOUR_DY := 520.0
## Avatar bounds relative to its feet, generous enough for hats and balloons.
const AVATAR_REGION := Rect2(-40, -120, 80, 126)
## The face, hair and hat, relative to the feet (see PlaceholderArt.draw_character:
## the neck is at y -44, the tallest hats reach about -70). Where's Wally almost
## always shows his head: the face and hat are what the seeker recognises, so
## harder difficulties may hide more of the body but keep some head showing.
const HEAD_REGION := Rect2(-14, -72, 28, 30)

var _map: MapDefinition
var _objects: Array[WorldObjectData]
## The rule being checked: at least [member min_visible] of the whole avatar and
## at least [member min_head] of its head must show. Defaults: the classic rule.
var min_visible := MIN_VISIBLE
var min_head := MIN_HEAD


func _init(map_def: MapDefinition, objects: Array[WorldObjectData], p_min_visible: float = MIN_VISIBLE, p_min_head: float = MIN_HEAD) -> void:
	_map = map_def
	_objects = objects
	min_visible = p_min_visible
	min_head = p_min_head


## Avatar check. {"fraction": float 0..1, "head": float 0..1, "ok": bool, "reason": String ("" when ok)}.
func check(look: Dictionary, feet: Vector2) -> Dictionary:
	return check_subject(subject_for_look(look), feet)


## Same rule for a subject from subject_for_look().
func check_subject(subject: WorldObjectData, feet: Vector2) -> Dictionary:
	var body := Rect2(feet + Vector2(-14, -64), Vector2(28, 64))
	if not _map.world_bounds.encloses(body):
		return {"fraction": 0.0, "head": 0.0, "ok": false, "reason": "That's outside the %s." % _map.title.to_lower()}
	var m := measure(subject, feet)
	var fraction: float = m["fraction"]
	var head: float = m["head"]
	# Head first: it's what the seeker recognises.
	if head + 0.0005 < min_head:
		return {"fraction": fraction, "head": head, "ok": false,
			"reason": "Your head is too hidden (%d%% shows). At least %d%% of your head must show." % [floori(head * 100.0), roundi(min_head * 100.0)]}
	if fraction + 0.0005 < min_visible:
		return {"fraction": fraction, "head": head, "ok": false,
			"reason": "Only %d%% of you is visible. At least %d%% must show." % [floori(fraction * 100.0), roundi(min_visible * 100.0)]}
	return {"fraction": fraction, "head": head, "ok": true, "reason": ""}


static func subject_for_look(look: Dictionary) -> WorldObjectData:
	var obj := WorldObjectData.new()
	obj.asset_key = TownGenerator.CROWD_ASSET
	obj.look = look
	return obj


func visible_fraction(look: Dictionary, feet: Vector2) -> float:
	return visible_fraction_of(subject_for_look(look), feet)


func visible_fraction_of(subject: WorldObjectData, feet: Vector2) -> float:
	return measure(subject, feet)["fraction"]


## {"fraction": visible share of the whole avatar, "head": visible share of its head}.
func measure(subject: WorldObjectData, feet: Vector2) -> Dictionary:
	var region := AVATAR_REGION
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
		return {"fraction": 0.0, "head": 0.0}
	var occ := MaskCanvas.new(body)
	for obj in _objects:
		if obj == subject:
			continue
		var d := obj.world_position - feet
		if absf(d.x) > NEIGHBOUR_DX or absf(d.y) > NEIGHBOUR_DY:
			continue
		draw_cover(occ, obj, feet.y)
	var head_rect := Rect2(feet + HEAD_REGION.position, HEAD_REGION.size)
	var head_total := 0
	var head_seen := 0
	for i in body.size():
		if head_rect.has_point(body[i]):
			head_total += 1
			if occ.hit[i] == 0:
				head_seen += 1
	return {
		"fraction": 1.0 - float(occ.covered_count()) / float(body.size()),
		"head": float(head_seen) / float(head_total) if head_total > 0 else 0.0,
	}


static func _draw_subject(canvas: MaskCanvas, subject: WorldObjectData) -> void:
	PlaceholderArt.draw_character(canvas, subject.look, false)


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
	var strips := AssetCatalog.strips(obj.asset_key)
	if not strips.is_empty() and obj.depth_mode == "y_sort":
		# Isometric building: each slice sorts at its own front edge.
		var tex := AssetCatalog.texture(obj.asset_key)
		for st: Vector3 in strips:
			if obj.world_position.y + st.z > feet_y:
				canvas.begin_object(obj.world_position + Vector2(0, st.z))
				PlaceholderArt.draw_texture_strip(canvas, tex, e, obj.flip_h, st)
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
