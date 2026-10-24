class_name MapDefinition
extends RefCounted
## The authored, stable part of a town: bounds, ground, zones, paths, blocked
## areas and fixed objects. Loaded from data/maps/<map_id>.json.
## Seeded dressing is produced separately by TownGenerator.

const MAPS_DIR := "res://data/maps"

var map_id: String = ""
var map_version: int = 0
## Shown in menus and the hide HUD ("Town", "Nature museum").
var title: String = ""
## What gets hidden here: "avatar" (yourself) or "critter" (picked by seed).
var hide_subject: String = "avatar"
## Ground type painted under everything ("grass" outdoors, "wall" indoors).
var base_ground: String = "grass"
var default_seed: int = 0
var world_bounds: Rect2 = Rect2()
## Ground paint instructions, drawn in order by GroundLayer.
var ground: Array[Dictionary] = []
var zones: Array[PlacementZone] = []
var paths: Array[MapPath] = []
## Each: {"id", "label", "rect": Rect2} or {"id", "label", "center": Vector2, "radii": Vector2}.
var blocked: Array[Dictionary] = []
## Each: {"id", "asset", "pos": [x, y], "flip_h"?: bool}.
var fixed_objects: Array[Dictionary] = []


static func map_path(id: String) -> String:
	return "%s/%s.json" % [MAPS_DIR, id]


static func map_exists(id: String) -> bool:
	return FileAccess.file_exists(map_path(id))


## Loads and parses a map. Returns null (and pushes an error) on failure.
static func load_map(id: String) -> MapDefinition:
	var path := map_path(id)
	if not FileAccess.file_exists(path):
		push_error("Map file not found: %s" % path)
		return null
	var json := JSON.new()
	var err := json.parse(FileAccess.get_file_as_string(path))
	if err != OK:
		push_error("Map %s: JSON error at line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	if not json.data is Dictionary:
		push_error("Map %s: root must be an object" % path)
		return null
	return from_dict(json.data)


static func from_dict(d: Dictionary) -> MapDefinition:
	var m := MapDefinition.new()
	m.map_id = String(d["map_id"])
	m.map_version = int(d["map_version"])
	m.title = String(d.get("title", m.map_id))
	m.hide_subject = String(d.get("hide_subject", "avatar"))
	m.base_ground = String(d.get("base_ground", "grass"))
	m.default_seed = int(d.get("default_seed", 0))
	m.world_bounds = rect2(d["world_bounds"])
	for g: Dictionary in d.get("ground", []):
		m.ground.append(g)
	for z: Dictionary in d.get("zones", []):
		m.zones.append(PlacementZone.from_dict(z))
	for p: Dictionary in d.get("paths", []):
		m.paths.append(MapPath.from_dict(p))
	for b: Dictionary in d.get("blocked", []):
		var entry := {"id": String(b["id"]), "label": String(b.get("label", "blocked"))}
		if b.has("rect"):
			entry["rect"] = rect2(b["rect"])
		else:
			var e: Array = b["ellipse"]
			entry["center"] = Vector2(float(e[0]), float(e[1]))
			entry["radii"] = Vector2(float(e[2]), float(e[3]))
		m.blocked.append(entry)
	for f: Dictionary in d.get("fixed_objects", []):
		m.fixed_objects.append(f)
	return m


## Label of the blocked area containing [param p] ("" if none).
func blocked_label_at(p: Vector2) -> String:
	for b in blocked:
		if b.has("rect"):
			if (b["rect"] as Rect2).has_point(p):
				return b["label"]
		else:
			var rel: Vector2 = (p - (b["center"] as Vector2)) / (b["radii"] as Vector2)
			if rel.length_squared() <= 1.0:
				return b["label"]
	return ""


func get_zone(id: String) -> PlacementZone:
	for z in zones:
		if z.id == id:
			return z
	return null


static func vec2(v: Variant) -> Vector2:
	var a: Array = v
	return Vector2(float(a[0]), float(a[1]))


static func rect2(v: Variant) -> Rect2:
	var a: Array = v
	return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))
