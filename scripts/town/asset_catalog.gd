class_name AssetCatalog
extends RefCounted
## Read-only view of data/assets/asset_catalog.json.
## Each asset has a "kind" (character, prop, tree, building), spacing radius,
## tags, optional occluder shapes, and either a "texture" or placeholder
## parameters. Art is swapped by adding "texture" fields; no code changes.

const PATH := "res://data/assets/asset_catalog.json"

static var _assets: Dictionary = {}
static var _textures: Dictionary = {}
static var _loaded := false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var json := JSON.new()
	var err := json.parse(FileAccess.get_file_as_string(PATH))
	if err != OK:
		push_error("Asset catalog JSON error at line %d: %s" % [json.get_error_line(), json.get_error_message()])
		return
	_assets = (json.data as Dictionary).get("assets", {})


static func has(key: String) -> bool:
	_ensure_loaded()
	return _assets.has(key)


static func entry(key: String) -> Dictionary:
	_ensure_loaded()
	if not _assets.has(key):
		push_error("Unknown asset key: %s" % key)
		return {}
	return _assets[key]


static func kind(key: String) -> String:
	return String(entry(key).get("kind", ""))


static func is_critter(key: String) -> bool:
	return kind(key) == "critter"


## Hideable critters (museum mode), in catalog order.
static func critters() -> Array[String]:
	_ensure_loaded()
	var out: Array[String] = []
	for key: String in _assets:
		if String(_assets[key].get("kind", "")) == "critter":
			out.append(key)
	return out


## Display name ("baby T-rex"), falling back to the key.
static func label(key: String) -> String:
	return String(entry(key).get("label", key.replace("_", " ")))


static func radius(key: String) -> float:
	return float(entry(key).get("radius", 0.0))


## Drawn area of a textured asset relative to its ground point, in game px
## (the placeholder box when there is no texture yet).
static func sprite_rect(key: String) -> Rect2:
	var tex := texture(key)
	if tex == null:
		return Rect2(-10, -20, 20, 20)
	var e := entry(key)
	var size := tex.get_size()
	var gp := MapDefinition.vec2(e.get("ground_point", [size.x * 0.5, size.y]))
	var s := float(e.get("height_px", size.y)) / size.y
	return Rect2(-gp * s, size * s)


## Texture referenced by [param field] of the entry, or null when the asset is
## still a code-drawn placeholder.
static func texture(key: String, field: String = "texture") -> Texture2D:
	var path := String(entry(key).get(field, ""))
	if path == "":
		return null
	if _textures.has(path):
		return _textures[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null:
		push_warning("Asset %s: texture %s missing, using placeholder art" % [key, path])
	_textures[path] = tex
	return tex
