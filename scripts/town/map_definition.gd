class_name MapDefinition
extends RefCounted
## The authored, stable part of a town: bounds, ground, zones, paths, blocked
## areas and fixed objects. Loaded from data/maps/<map_id>.json.
## Seeded dressing is produced separately by TownGenerator.

const MAPS_DIR := "res://data/maps"

var map_id: String = ""
var map_version: int = 0
## Shown in the hide HUD and messages ("Wonky town").
var title: String = ""
## Ground type painted under everything.
var base_ground: String = "grass"
## "" = flat colours drawn in code; otherwise GroundLayer tiles textures from
## res://art/ground/ground_<type>.png where they exist (e.g. "storybook").
var ground_style: String = ""
var default_seed: int = 0
var world_bounds: Rect2 = Rect2()
## Isometric maps ("projection" in the map data): ground is authored on a flat
## plan and GroundLayer draws it through this transform; everything else
## (zones, blocked areas, objects) is already in screen/world space.
## Identity for ordinary top-down maps.
var ground_transform: Transform2D = Transform2D.IDENTITY
## Plan-space area the ground covers (world_bounds when not projected).
var plan_bounds: Rect2 = Rect2()
## Ground paint instructions, drawn in order by GroundLayer.
var ground: Array[Dictionary] = []
var zones: Array[PlacementZone] = []
var paths: Array[MapPath] = []
## Each: {"id", "label"} plus "rect": Rect2, "polygon": PackedVector2Array or
## "center": Vector2 + "radii": Vector2 (ellipse).
var blocked: Array[Dictionary] = []
## Each: {"id", "asset", "pos": [x, y], "flip_h"?: bool}.
var fixed_objects: Array[Dictionary] = []


static func map_path(id: String) -> String:
	return "%s/%s.json" % [MAPS_DIR, id]


static func map_exists(id: String) -> bool:
	return FileAccess.file_exists(map_path(id))


## Loads and parses a map. Returns null (and pushes an error) on failure.
## Procedural maps ("procedural": "wfc") are built from [param map_seed]
## (the map's default_seed when it is negative), so pass the seed being played.
## [param size] picks one of the template's "sizes" (S, M, L, XL); "" or an
## unknown size means the template as written (L).
static func load_map(id: String, map_seed: int = -1, size: String = "") -> MapDefinition:
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
	var d: Dictionary = apply_size(json.data, size)
	if String(d.get("procedural", "")) == "wfc":
		d = WfcTown.build(d, map_seed if map_seed >= 0 else int(d.get("default_seed", 0)))
	return from_dict(d)


## Town sizes this map offers (keys of "sizes", in file order).
static func sizes(id: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not map_exists(id):
		return out
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(map_path(id)))
	if d is Dictionary and d.get("sizes") is Dictionary:
		for k: String in d["sizes"]:
			if not k.begins_with("_"):
				out.append(k)
	return out


## [param template] with the overrides of size [param size] merged in (one
## level deep, so {"grid": {"cols": 38}} keeps the other grid keys).
static func apply_size(template: Dictionary, size: String) -> Dictionary:
	var all: Variant = template.get("sizes", {})
	if size == "" or not all is Dictionary or not (all as Dictionary).get(size) is Dictionary:
		return template
	var out := template.duplicate(true)
	var over: Dictionary = all[size]
	for key: String in over:
		if over[key] is Dictionary and out.get(key) is Dictionary:
			(out[key] as Dictionary).merge(over[key], true)
		else:
			out[key] = over[key]
	return out


static func from_dict(d: Dictionary) -> MapDefinition:
	var m := MapDefinition.new()
	m.map_id = String(d["map_id"])
	m.map_version = int(d["map_version"])
	m.title = String(d.get("title", m.map_id))
	m.base_ground = String(d.get("base_ground", "grass"))
	m.ground_style = String(d.get("ground_style", ""))
	m.default_seed = int(d.get("default_seed", 0))
	m.world_bounds = rect2(d["world_bounds"])
	m.plan_bounds = m.world_bounds
	if d.has("projection"):
		var pr: Dictionary = d["projection"]
		m.ground_transform = Transform2D(vec2(pr["x"]), vec2(pr["y"]), vec2(pr["origin"]))
		m.plan_bounds = rect2(pr["plan_bounds"])
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
		elif b.has("polygon"):
			entry["polygon"] = polygon(b["polygon"])
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
		elif b.has("polygon"):
			if Geometry2D.is_point_in_polygon(p, b["polygon"]):
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


static func polygon(v: Variant) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Variant in v:
		out.append(vec2(p))
	return out


static func rect2(v: Variant) -> Rect2:
	var a: Array = v
	return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))
