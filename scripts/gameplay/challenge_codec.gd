class_name ChallengeCodec
extends RefCounted
## Converts challenges to/from JSON, a copyable share code ("WM1-" + base64url
## of the JSON) and files under user://challenges/.
## decode()/from_dict() return {"challenge": ChallengeData or null, "error": String}.

const CODE_PREFIX := "WM1-"
## Codes from before the rename to Where's Me (same payload).
const LEGACY_PREFIXES: Array[String] = ["HF1-"]
const SAVE_DIR := "user://challenges"
const MAX_SEED := 2147483647


static func to_json(c: ChallengeData) -> String:
	return JSON.stringify(c.to_dict(), "  ")


static func encode(c: ChallengeData) -> String:
	var b64 := Marshalls.utf8_to_base64(JSON.stringify(c.to_dict()))
	return CODE_PREFIX + b64.replace("+", "-").replace("/", "_").rstrip("=")


## Accepts a share code or raw challenge JSON.
static func decode(text: String) -> Dictionary:
	var s := text.strip_edges()
	if s == "":
		return _fail("Paste a challenge code first.")
	var json_text := s
	var prefix := ""
	for p: String in [CODE_PREFIX] + LEGACY_PREFIXES:
		if s.begins_with(p):
			prefix = p
	if prefix != "":
		var b64 := s.substr(prefix.length()).replace("\n", "").replace("\r", "").replace(" ", "")
		b64 = b64.replace("-", "+").replace("_", "/")
		if b64 == "" or not _is_base64(b64):
			return _fail("The code is damaged: it contains characters that can't be part of a code.")
		while b64.length() % 4 != 0:
			b64 += "="
		json_text = Marshalls.base64_to_utf8(b64)
		if json_text == "":
			return _fail("The code is damaged and could not be decoded.")
	elif not s.begins_with("{"):
		return _fail("That doesn't look like a Where's Me code (codes start with %s)." % CODE_PREFIX)
	var json := JSON.new()
	if json.parse(json_text) != OK:
		return _fail("The challenge data is not valid JSON (line %d: %s)." % [json.get_error_line(), json.get_error_message()])
	if not json.data is Dictionary:
		return _fail("The challenge data must be a JSON object.")
	return from_dict(json.data)


static func from_dict(d: Dictionary) -> Dictionary:
	if not _is_int(d.get("schema_version")):
		return _fail("Missing schema_version.")
	var version := int(d["schema_version"])
	if version < ChallengeData.MIN_SCHEMA_VERSION:
		return _fail("This code was made with an older version of Where's Me and can't be played any more.")
	if version > ChallengeData.SCHEMA_VERSION:
		return _fail("This code needs a newer version of Where's Me (format %d, this build reads %d)." % [version, ChallengeData.SCHEMA_VERSION])
	for key in ["map_id", "challenge_id"]:
		if not d.get(key) is String or String(d[key]) == "":
			return _fail("Missing or invalid field: %s." % key)
	for key in ["map_version", "generator_version", "seed"]:
		if not _is_int(d.get(key)):
			return _fail("Missing or invalid field: %s (must be a whole number)." % key)
	var seed_value := int(d["seed"])
	if seed_value < 0 or seed_value > MAX_SEED:
		return _fail("Seed %d is out of range." % seed_value)
	if not MapDefinition.map_exists(String(d["map_id"])):
		return _fail("Unknown map '%s' (this build may be older than the challenge)." % d["map_id"])
	var hider: Variant = d.get("hider")
	if not hider is Dictionary:
		return _fail("Missing hider.")
	var name_value: Variant = hider.get("name", "")
	if not name_value is String:
		return _fail("Hider name must be text.")
	var critter := ""
	if hider.has("critter"):
		if version < 3 or not hider["critter"] is String or not AssetCatalog.has(hider["critter"]) or not AssetCatalog.is_critter(hider["critter"]):
			return _fail("Unknown hidden critter (this build may be older than the challenge).")
		critter = String(hider["critter"])
	else:
		var look_error := AvatarKit.validate(hider.get("look"))
		if look_error != "":
			return _fail(look_error)
	var target: Variant = d.get("target")
	if not target is Dictionary:
		return _fail("Missing target.")
	var pos: Variant = target.get("world_position")
	if not pos is Array or (pos as Array).size() != 2 or not _is_number(pos[0]) or not _is_number(pos[1]):
		return _fail("Target position must be [x, y].")
	if not target.get("object_id") is String:
		return _fail("Target needs an object_id.")
	var c := ChallengeData.new()
	c.schema_version = version
	c.map_id = String(d["map_id"])
	c.map_version = int(d["map_version"])
	c.generator_version = int(d["generator_version"])
	c.map_seed = seed_value
	c.challenge_id = String(d["challenge_id"])
	c.hider_name = String(name_value).strip_edges().left(AvatarKit.MAX_NAME_LENGTH)
	c.hider_critter = critter
	c.hider_look = {} if critter != "" else AvatarKit.normalize(hider["look"])
	c.target_object_id = String(target["object_id"])
	c.target_world_position = Vector2(float(pos[0]), float(pos[1]))
	var rules: Variant = d.get("rules", {})
	if rules is Dictionary:
		if _is_int(rules.get("wrong_tap_limit", 0)):
			c.wrong_tap_limit = maxi(0, int(rules.get("wrong_tap_limit", 0)))
		c.show_target_on_finish = bool(rules.get("show_target_on_finish", true))
	return {"challenge": c, "error": ""}


## Writes the challenge JSON and returns its path ("" on failure).
static func save_to_file(c: ChallengeData) -> String:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var path := "%s/%s.json" % [SAVE_DIR, c.challenge_id]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("Could not save challenge to %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return ""
	f.store_string(to_json(c))
	f.close()
	return path


static func load_from_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail("File not found: %s" % path)
	return decode(FileAccess.get_file_as_string(path))


## Saved challenge files, newest first.
static func list_saved() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".json"):
			out.append("%s/%s" % [SAVE_DIR, f])
	out.sort_custom(func(a: String, b: String) -> bool: return FileAccess.get_modified_time(a) > FileAccess.get_modified_time(b))
	return out


static func _fail(msg: String) -> Dictionary:
	return {"challenge": null, "error": msg}


static func _is_number(v: Variant) -> bool:
	return v is int or v is float


static func _is_int(v: Variant) -> bool:
	return v is int or (v is float and is_finite(v) and float(v) == floorf(v))


static func _is_base64(s: String) -> bool:
	for ch in s:
		if not (ch >= "A" and ch <= "Z" or ch >= "a" and ch <= "z" or ch >= "0" and ch <= "9" or ch == "+" or ch == "/" or ch == "="):
			return false
	return true
