extends Node
## Global mode and the challenge being played (autoload "AppState").
## Scene changes go through here so the town scene always starts clean.
##
## Developer flags (pass after `--` on the Godot command line):
##   --mode=create|hide|search|debug   jump straight into a mode
##   --map=ID                   map for hide/debug/--at (town_demo_01, museum_01)
##   --seed=N                   map seed for hide/debug
##   --preset=N                 use avatar preset N (0-7) as "my avatar"
##   --challenge=PATH_OR_CODE   challenge for --mode=search
##   --at=X,Y                   build a search challenge on the fly with the
##                              hider's feet at X,Y (uses --preset look)
##   --place=X,Y [--confirm]    hide mode: put the avatar's feet at X,Y
##   --center=X,Y --zoom=Z      initial camera view
##   --debug=1|2                debug overlay level
##   --start                    search: skip the intro and start the clock
##   --tap=X,Y                  simulate a tap (world coords) after loading (implies --start)
##   --shot=PATH [--shot-delay=S]  save a screenshot and quit

enum Mode { MENU, CREATE, HIDE, SEARCH, DEBUG_VIEW }

const TOWN_MAP_ID := "town_demo_01"
const MUSEUM_MAP_ID := "museum_01"
const DEFAULT_SEED := 481516
const MENU_SCENE := "res://scenes/main_menu.tscn"
const TOWN_SCENE := "res://scenes/town/town_demo.tscn"
const CREATOR_SCENE := "res://scenes/ui/avatar_creator.tscn"
const MY_AVATAR_PATH := "user://my_avatar.json"

var mode: Mode = Mode.MENU
var map_seed: int = DEFAULT_SEED
## Map for hide and debug mode (search uses the challenge's map).
var map_id: String = TOWN_MAP_ID
var challenge: ChallengeData = null
## Shown once on the main menu (errors that sent the player back).
var menu_message: String = ""
var dev_args: Dictionary = {}
## The player's own avatar: {"name": String, "look": Dictionary}. Saved locally.
var my_avatar: Dictionary = {}


func _ready() -> void:
	dev_args = parse_args(OS.get_cmdline_user_args())
	if dev_args.has("seed"):
		map_seed = int(dev_args["seed"])
	if dev_args.has("map"):
		map_id = String(dev_args["map"])
	my_avatar = load_my_avatar()
	if dev_args.has("preset"):
		var preset: Dictionary = AvatarKit.presets()[clampi(int(dev_args["preset"]), 0, AvatarKit.presets().size() - 1)]
		my_avatar = {"name": preset["name"], "look": AvatarKit.normalize(preset["look"])}
	if dev_args.has("shot"):
		_screenshot_later(String(dev_args["shot"]), float(dev_args.get("shot-delay", "2.5")))
	if dev_args.has("mode"):
		_apply_dev_mode.call_deferred()


## Avatar creator; continues to hide mode with [param p_seed] when done.
func start_creator(p_seed: int) -> void:
	mode = Mode.CREATE
	map_seed = p_seed
	challenge = null
	_go(CREATOR_SCENE)


func has_avatar() -> bool:
	return not my_avatar.is_empty()


func load_my_avatar() -> Dictionary:
	if not FileAccess.file_exists(MY_AVATAR_PATH):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MY_AVATAR_PATH))
	if not data is Dictionary or AvatarKit.validate(data.get("look")) != "":
		push_warning("Ignoring invalid saved avatar at %s" % MY_AVATAR_PATH)
		return {}
	return {"name": String(data.get("name", "")).left(AvatarKit.MAX_NAME_LENGTH), "look": AvatarKit.normalize(data["look"])}


func save_my_avatar(avatar_name: String, look: Dictionary) -> void:
	my_avatar = {"name": avatar_name.strip_edges().left(AvatarKit.MAX_NAME_LENGTH), "look": AvatarKit.normalize(look)}
	var f := FileAccess.open(MY_AVATAR_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Could not save avatar to %s: %s" % [MY_AVATAR_PATH, error_string(FileAccess.get_open_error())])
		return
	f.store_string(JSON.stringify(my_avatar, "  "))


## Hide mode on [param p_map_id] (default: the current map). Maps where you
## hide yourself go to the creator first if there's no avatar yet; the
## museum hides a critter and needs none.
func start_hide(p_seed: int, p_map_id: String = map_id) -> void:
	map_id = p_map_id
	if not has_avatar() and map_hides_avatar(map_id):
		start_creator(p_seed)
		return
	mode = Mode.HIDE
	map_seed = p_seed
	challenge = null
	_go(TOWN_SCENE)


func start_search(c: ChallengeData) -> void:
	mode = Mode.SEARCH
	challenge = c
	map_seed = c.map_seed
	map_id = c.map_id
	_go(TOWN_SCENE)


static func map_hides_avatar(id: String) -> bool:
	var m := MapDefinition.load_map(id)
	return m == null or m.hide_subject != "critter"


func start_debug(p_seed: int) -> void:
	mode = Mode.DEBUG_VIEW
	map_seed = p_seed
	challenge = null
	_go(TOWN_SCENE)


func go_menu(message: String = "") -> void:
	mode = Mode.MENU
	menu_message = message
	_go(MENU_SCENE)


func _go(path: String) -> void:
	get_tree().change_scene_to_file.call_deferred(path)


static func parse_args(args: PackedStringArray) -> Dictionary:
	var out := {}
	for a in args:
		if not a.begins_with("--"):
			continue
		var kv := a.substr(2).split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return out


static func parse_vec2(text: String) -> Vector2:
	var parts := text.split(",")
	return Vector2(float(parts[0]), float(parts[1])) if parts.size() == 2 else Vector2.INF


func _apply_dev_mode() -> void:
	match String(dev_args["mode"]):
		"create":
			start_creator(map_seed)
		"hide":
			start_hide(map_seed)
		"debug":
			start_debug(map_seed)
		"search":
			var c := _dev_challenge()
			if c:
				start_search(c)


func _dev_challenge() -> ChallengeData:
	if dev_args.has("challenge"):
		var src := String(dev_args["challenge"])
		var result := ChallengeCodec.load_from_file(src) if FileAccess.file_exists(src) else ChallengeCodec.decode(src)
		if result["challenge"] == null:
			push_error("--challenge: %s" % result["error"])
		return result["challenge"]
	var map_def := MapDefinition.load_map(map_id)
	var layout := TownGenerator.generate(map_def, map_seed)
	var avatar := my_avatar if has_avatar() else {"name": "", "look": AvatarKit.default_look()}
	var at := parse_vec2(String(dev_args.get("at", "720,700")))
	if map_def.hide_subject == "critter":
		return ChallengeData.create_critter(layout, TownGenerator.critter_for_seed(map_seed), avatar["name"], at)
	return ChallengeData.create(layout, avatar["look"], avatar["name"], at)


func _screenshot_later(path: String, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	if err != OK:
		push_error("Screenshot failed (%s): %s" % [path, error_string(err)])
	else:
		print("Screenshot saved: ", path)
	get_tree().quit()
