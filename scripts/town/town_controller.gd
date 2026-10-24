class_name TownController
extends Node2D
## Builds the visible town from a MapDefinition + TownLayout and answers
## spatial queries (which character is under a point). Owns no game rules.

const CHARACTER_SCENE := preload("res://scenes/actors/character.tscn")
const PROP_SCENE := preload("res://scenes/props/prop_base.tscn")
const TARGET_ID := "target_player"

var map_def: MapDefinition
var layout: TownLayout
var ground: GroundLayer
## All objects that interleave by depth live here, Y-sorted by ground point.
var world: Node2D
## The hider: a CharacterActor (avatar) or a PropActor (museum critter).
var target: WorldActor = null

var _characters: Array[CharacterActor] = []
var _props: Array[PropActor] = []


func build(p_map: MapDefinition, p_layout: TownLayout) -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	_characters.clear()
	_props.clear()
	target = null
	map_def = p_map
	layout = p_layout
	ground = GroundLayer.new()
	ground.name = "Ground"
	add_child(ground)
	ground.setup(map_def)
	world = Node2D.new()
	world.name = "World"
	world.y_sort_enabled = true
	add_child(world)
	for obj in layout.objects:
		spawn(obj)


func spawn(obj: WorldObjectData) -> Node2D:
	if AssetCatalog.kind(obj.asset_key) == "character":
		var c := CHARACTER_SCENE.instantiate() as CharacterActor
		c.setup(obj)
		world.add_child(c)
		_characters.append(c)
		return c
	var p := PROP_SCENE.instantiate() as PropActor
	p.setup(obj)
	world.add_child(p)
	_props.append(p)
	return p


## Puts (or moves) the hider's avatar at [param at]. There is only ever one.
func place_target(look: Dictionary, at: Vector2) -> WorldActor:
	if target == null:
		var obj := TownGenerator.make_object(TARGET_ID, TownGenerator.CROWD_ASSET, at, "target")
		obj.look = look
		target = spawn(obj) as CharacterActor
	else:
		(target as CharacterActor).set_look(look)
		target.position = at
	return target


## Puts (or moves) the hidden critter, in its original colours, at [param at].
func place_critter_target(key: String, at: Vector2) -> WorldActor:
	if target == null:
		target = spawn(TownGenerator.make_object(TARGET_ID, key, at, "target")) as PropActor
	else:
		target.position = at
	return target


## Puts the hider described by [param subject] (see VisibilityChecker) at [param at].
func place_subject(subject: WorldObjectData, at: Vector2) -> WorldActor:
	if VisibilityChecker.is_critter(subject):
		return place_critter_target(subject.asset_key, at)
	return place_target(subject.look, at)


## Gives any crowd member who is an exact twin of [param look] a different
## top colour, in both the layout data and the visible node. Deterministic, so
## hider and seeker see the same crowd. Returns the ids that were changed.
func ensure_unique(look: Dictionary) -> PackedStringArray:
	var changed := PackedStringArray()
	var key := AvatarKit.look_key(look)
	for obj in layout.objects:
		if obj.is_interactive and AvatarKit.look_key(obj.look) == key:
			obj.look = AvatarKit.make_distinct(obj.look, look)
			var node := world.get_node_or_null(NodePath(obj.id)) as CharacterActor
			if node:
				node.set_look(obj.look)
			changed.append(obj.id)
	return changed


func clear_target() -> void:
	if target:
		if target is CharacterActor:
			_characters.erase(target)
		else:
			_props.erase(target)
		target.queue_free()
		target = null


func characters() -> Array[CharacterActor]:
	return _characters


func props() -> Array[PropActor]:
	return _props


## Front-most (largest feet y) character whose tap area contains [param world_pos].
func character_at(world_pos: Vector2, pad: float) -> CharacterActor:
	var best: CharacterActor = null
	for c in _characters:
		if not c.visible or not c.hit_rect(pad).has_point(world_pos):
			continue
		if best == null or c.position.y > best.position.y or (c.position.y == best.position.y and c.object_id > best.object_id):
			best = c
	return best


## Front-most critter whose tap area contains [param world_pos] (museum).
func critter_at(world_pos: Vector2, pad: float) -> PropActor:
	var best: PropActor = null
	for p in _props:
		if not p.visible or not p.is_critter() or not p.hit_rect(pad).has_point(world_pos):
			continue
		if best == null or p.position.y > best.position.y or (p.position.y == best.position.y and p.object_id > best.object_id):
			best = p
	return best


## Fades tree crowns / awnings near [param p] so a hider can see their avatar.
func fade_canopies_near(p: Vector2, radius: float) -> void:
	for prop in _props:
		var near := prop.canopy != null and prop.position.distance_to(p) < radius
		near = near or (prop.is_foreground() and prop.hit_rect(radius * 0.5).has_point(p))
		prop.set_canopy_faded(near)
