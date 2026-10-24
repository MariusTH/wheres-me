class_name AvatarKit
extends RefCounted
## The part kit (data/assets/avatar_kit.json) shared by the avatar creator and
## the generated crowd. A "look" is a Dictionary with one value per field in
## field_order (skin, build, hair_style, hair, hat, ...), drawn by
## PlaceholderArt.draw_character().

const PATH := "res://data/assets/avatar_kit.json"
const MAX_NAME_LENGTH := 24

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(PATH)) != OK:
			push_error("Avatar kit JSON error at line %d: %s" % [json.get_error_line(), json.get_error_message()])
			return {}
		_data = json.data
	return _data


static func field_order() -> Array:
	return data()["field_order"]


static func field(name: String) -> Dictionary:
	return data()["fields"][name]


## Allowed values of a field (palette colours or explicit values).
static func values(name: String) -> Array:
	var f := field(name)
	if f.has("palette"):
		return data()["palettes"][f["palette"]]
	return f["values"]


static func is_color_field(name: String) -> bool:
	return field(name).has("palette")


static func presets() -> Array:
	return data()["presets"]


## Whether the field matters for this look (e.g. hat colour without a hat).
static func is_relevant(name: String, look: Dictionary) -> bool:
	var hidden: Dictionary = field(name).get("hidden_if", {})
	for other: String in hidden:
		if (hidden[other] as Array).has(look.get(other)):
			return false
	return true


## Complete look with every field present (missing fields get defaults).
static func normalize(look: Dictionary) -> Dictionary:
	var out := {}
	for name: String in field_order():
		out[name] = look.get(name, field(name)["default"])
	return out


static func default_look() -> Dictionary:
	return normalize(presets()[0]["look"])


## "" when every field holds an allowed value, otherwise what is wrong.
static func validate(look: Variant) -> String:
	if not look is Dictionary:
		return "The avatar description is missing."
	for name: String in (look as Dictionary):
		if not field_order().has(name):
			return "Unknown avatar part '%s'." % name
		if not values(name).has(look[name]):
			return "Avatar part '%s' has an unsupported value." % name
	return ""


## Canonical string for comparing looks.
static func look_key(look: Dictionary) -> String:
	return JSON.stringify(normalize(look), "", true)


## Random look. Consumes exactly one RNG value per field, in field_order, so
## crowds stay stable as long as the kit's field_order and weights don't change.
static func random_look(rng: RandomNumberGenerator) -> Dictionary:
	var look := {}
	for name: String in field_order():
		var vals := values(name)
		var weights: Array = field(name).get("weights", [])
		var roll := rng.randf()
		var pick: Variant = vals[mini(int(roll * vals.size()), vals.size() - 1)]
		if weights.size() == vals.size():
			var total := 0.0
			for w: float in weights:
				total += w
			var acc := 0.0
			for i in vals.size():
				acc += float(weights[i]) / total
				if roll < acc:
					pick = vals[i]
					break
		look[name] = pick
	return look


## Deterministically changes [param look] so it differs from [param avoid]
## (used when a crowd member would be an exact twin of the hider).
static func make_distinct(look: Dictionary, avoid: Dictionary) -> Dictionary:
	var out := normalize(look)
	var shirts := values("shirt")
	var i := shirts.find(out["shirt"])
	out["shirt"] = shirts[(i + 1) % shirts.size()]
	if look_key(out) == look_key(avoid):
		out["shirt"] = shirts[(i + 2) % shirts.size()]
	return out
