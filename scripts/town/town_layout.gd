class_name TownLayout
extends RefCounted
## Everything TownGenerator placed for one (map, map_version, seed).

var map_id: String = ""
var map_version: int = 0
var generator_version: int = 0
var map_seed: int = 0
var objects: Array[WorldObjectData] = []
## Placement rules that could not be fully satisfied (surfaced as warnings).
var shortfalls: PackedStringArray = PackedStringArray()


func get_object(id: String) -> WorldObjectData:
	for o in objects:
		if o.id == id:
			return o
	return null


func count_people() -> int:
	var n := 0
	for o in objects:
		if o.is_interactive:
			n += 1
	return n


## Canonical text of every id/asset/position/flip/look, for determinism checks.
func signature() -> String:
	var lines := PackedStringArray()
	for o in objects:
		var look_text := AvatarKit.look_key(o.look) if o.is_interactive else ""
		var line := "%s|%s|%d|%d|%s|%s" % [o.id, o.asset_key, int(o.world_position.x), int(o.world_position.y), o.flip_h, look_text]
		if o.hue != 0.0:
			line += "|%.4f" % o.hue
		lines.append(line)
	return "\n".join(lines)
