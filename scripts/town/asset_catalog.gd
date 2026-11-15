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
static var _strips: Dictionary = {}

## Width (game px) of the vertical slices an isometric building is drawn in.
const STRIP_W := 12.0


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
	if not TextureAtlas.built():
		TextureAtlas.build(all_texture_paths())
	var tex: Texture2D = TextureAtlas.get_texture(path)
	if tex == null and ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null:
		push_warning("Asset %s: texture %s missing, using placeholder art" % [key, path])
	_textures[path] = tex
	return tex


## Every texture the catalog refers to ("texture" and "canopy_texture").
static func all_texture_paths() -> Array:
	_ensure_loaded()
	var out := {}
	for key: String in _assets:
		for field in ["texture", "canopy_texture"]:
			var p := String((_assets[key] as Dictionary).get(field, ""))
			if p != "":
				out[p] = true
	return out.keys()


## Isometric buildings ("footprint": [plan x, plan y] in the catalog) sit on a
## diamond whose bottom corner is the ground point. A single sort point can't
## order such a sprite against people standing beside its walls, so it is
## drawn as vertical slices, each Y-sorted at the front edge of the footprint
## below it. Returns [Vector3(x_from, x_to, sort_dy)] in game px relative to
## the ground point (unmirrored), or [] for ordinary sprites.
static func strips(key: String) -> Array:
	if _strips.has(key):
		return _strips[key]
	var out: Array = []
	var e := entry(key)
	if e.has("footprint") and texture(key) != null:
		var fp := MapDefinition.vec2(e["footprint"])
		var r := sprite_rect(key)
		var x := r.position.x
		while x < r.end.x:
			var b := minf(x + STRIP_W, r.end.x)
			# Front edges: y = -|x| / 2 between the left (-fp.y) and right (fp.x) corners.
			var lo := clampf(x, -fp.y, fp.x)
			var hi := clampf(b, -fp.y, fp.x)
			var nearest := 0.0 if (lo <= 0.0 and hi >= 0.0) else minf(absf(lo), absf(hi))
			out.append(Vector3(x, b, -nearest * 0.5))
			x = b
	_strips[key] = out
	return out
