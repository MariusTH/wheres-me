class_name WorldObjectData
extends RefCounted
## One placed thing in the town (person, prop, tree, building).
## Pure data: the visual node is created from this by TownController.

var id: String = ""
var asset_key: String = ""
## Ground point (feet / base) in world coordinates. Used for Y-sorting.
var world_position: Vector2 = Vector2.ZERO
## Sprite pixel that sits on the ground point (from the asset catalog).
var ground_point_offset: Vector2 = Vector2.ZERO
## "y_sort" (default), "ground" (flat decal, always below) or "foreground".
var depth_mode: String = "y_sort"
var tags: PackedStringArray = PackedStringArray()
## "none", "opaque" (y-sorted cover) or "foreground_occluder" (canopy etc.).
var occlusion_role: String = "none"
## Only interactive objects (people) can be tapped in search mode.
var is_interactive: bool = false
var flip_h: bool = false
## For people: the part-kit look (see AvatarKit). Empty for scenery.
var look: Dictionary = {}
## For critters: hue rotation in turns (0 = the original colours, which only
## the hidden critter has; decoys are always shifted).
var hue: float = 0.0
## "fixed" (authored), "generated" (seeded) or "target" (the hider).
var source: String = "generated"


func to_dict() -> Dictionary:
	return {
		"id": id,
		"asset_key": asset_key,
		"world_position": [world_position.x, world_position.y],
		"ground_point_offset": [ground_point_offset.x, ground_point_offset.y],
		"depth_mode": depth_mode,
		"tags": Array(tags),
		"occlusion_role": occlusion_role,
		"is_interactive": is_interactive,
		"flip_h": flip_h,
		"look": look,
		"hue": hue,
		"source": source,
	}
