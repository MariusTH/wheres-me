extends Node
## Global mode and the challenge being played (autoload "AppState").
## Scene changes go through here so the town scene always starts clean.
##
## Developer flags (pass after `--` on the Godot command line):
##   --mode=create|hide|search|debug|play|daily|friends   jump straight into a mode
##   --difficulty=ID            difficulty for --mode=play (easy, normal, hard, expert)
##   --map=ID                   map for hide/debug/--at (default town_iso)
##   --size=S|M|L|XL            town size for hide/debug
##   --seed=N                   map seed for hide/debug
##   --preset=N                 use avatar preset N (0-7) as "my avatar"
##   --challenge=PATH_OR_CODE   challenge for --mode=search
##   --at=X,Y                   build a search challenge on the fly with the
##                              hider's feet at X,Y (uses --preset look)
##   --place=X,Y [--confirm]    hide mode: put the avatar's feet at X,Y
##   --center=X,Y --zoom=Z      initial camera view
##   --debug=1|2                debug overlay level
##   --hud=0                    hide the HUD (clean screenshots)
##   --start                    search: skip the intro and start the clock
##   --tap=X,Y                  simulate a tap (world coords) after loading (implies --start)
##   --shot=PATH [--shot-delay=S]  save a screenshot and quit

enum Mode { MENU, CREATE, HIDE, SEARCH, DEBUG_VIEW }

## Emitted when the screen's size class (narrow / short) changes, e.g. when a
## phone rotates. Screens rebuild their layout on it.
signal layout_changed

## UI scale: the shorter side of the window, in device-independent pixels, is
## mapped to this many UI units, clamped. Desktop windows (720+ px) keep the
## 1280x720 design size; a phone (393 px short side) gets 480 units, so a 52-unit
## button is ~43 px, about Apple's 44 pt minimum tap size.
const UI_SHORT_MIN := 480.0
const UI_SHORT_MAX := 720.0
## Below this viewport width layouts stack vertically (phone in portrait).
const NARROW_WIDTH := 700.0
## Below this viewport height layouts get compact (phone in landscape).
const SHORT_HEIGHT := 600.0

const TOWN_MAP_ID := "town_iso"
const DEFAULT_SEED := 481516
const MENU_SCENE := "res://scenes/main_menu.tscn"
const TOWN_SCENE := "res://scenes/town/town.tscn"
const CREATOR_SCENE := "res://scenes/ui/avatar_creator.tscn"
const MY_AVATAR_PATH := "user://my_avatar.json"
const FRIENDS_SCENE := "res://scenes/ui/friends_screen.tscn"
const PROFILE_FILE := "profile.json"

## What the current round is part of. The town scene's controllers read it to
## decide what to record and which buttons to offer when the round ends.
const KIND_QUICK := "quick"    ## a pasted code without a sender, or your own code
const KIND_PLAY := "play"      ## solo, computer hider, chosen difficulty
const KIND_DAILY := "daily"    ## solo, today's town, same for everyone
const KIND_FRIEND := "friend"  ## a game with a friend or a practice partner

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
## Random id that travels in your friend codes so replies find their game.
var player_id: String = ""
## Town size for hide and debug mode (search uses the challenge's).
var map_size: String = ""
## {"kind": KIND_*, "difficulty": id, "friend_id": id, "date": "YYYY-MM-DD"}.
var session: Dictionary = {"kind": KIND_QUICK}
## Search with a computer hider: the town scene builds the map, then asks
## AutoHider for the challenge. {"difficulty": id, "who": {"name", "look"} or {}}.
var auto_hide: Dictionary = {}
## Main menu page to open on ("" = home, "play" = difficulty picker).
var menu_page: String = ""
## A challenge code from a deep link, opened by the friends screen. See DeepLink.
var pending_code: String = ""


func _ready() -> void:
	get_tree().root.size_changed.connect(_apply_ui_scale)
	_apply_ui_scale()
	dev_args = parse_args(OS.get_cmdline_user_args())
	if dev_args.has("seed"):
		map_seed = int(dev_args["seed"])
	if dev_args.has("map"):
		map_id = String(dev_args["map"])
	if dev_args.has("size"):
		map_size = String(dev_args["size"])
	my_avatar = load_my_avatar()
	player_id = load_player_id()
	if dev_args.has("preset"):
		var preset: Dictionary = AvatarKit.presets()[clampi(int(dev_args["preset"]), 0, AvatarKit.presets().size() - 1)]
		my_avatar = {"name": preset["name"], "look": AvatarKit.normalize(preset["look"])}
	if dev_args.has("shot"):
		_screenshot_later(String(dev_args["shot"]), float(dev_args.get("shot-delay", "2.5")))
	if dev_args.has("mode"):
		_apply_dev_mode.call_deferred()
	_watch_deep_links()


## Size class of the current viewport, see NARROW_WIDTH / SHORT_HEIGHT.
static func is_narrow() -> bool:
	return viewport_size().x < NARROW_WIDTH


static func is_short() -> bool:
	return viewport_size().y < SHORT_HEIGHT


static func viewport_size() -> Vector2:
	return (Engine.get_main_loop() as SceneTree).root.get_visible_rect().size


var _size_class := ""


func _apply_ui_scale() -> void:
	# Headless runs (tests) have no real screen; keep the design size.
	if DisplayServer.get_name() == "headless":
		return
	var win := get_window()
	# The web canvas is sized in physical pixels (scale = devicePixelRatio);
	# desktop windows already report logical pixels.
	var dpr := DisplayServer.screen_get_scale() if OS.has_feature("web") else 1.0
	var css := Vector2(win.size) / maxf(dpr, 1.0)
	if css.x <= 0.0 or css.y <= 0.0:
		return
	var short := minf(css.x, css.y)
	var units := clampf(short, UI_SHORT_MIN, UI_SHORT_MAX)
	win.content_scale_size = Vector2i(roundi(units * css.x / short), roundi(units * css.y / short))
	var size_class := "%s%s" % [is_narrow(), is_short()]
	if size_class != _size_class:
		_size_class = size_class
		layout_changed.emit()


## Avatar creator; continues to hide mode with [param p_seed] when done.
## [param keep_session]: return to the same game (e.g. a friend hide) after.
func start_creator(p_seed: int, keep_session: bool = false) -> void:
	mode = Mode.CREATE
	map_seed = p_seed
	challenge = null
	if not keep_session:
		session = {"kind": KIND_QUICK}
		map_size = ""
	_go(CREATOR_SCENE)


## The creator's "Hide me!": hide in the game the creator was opened from.
func finish_creator() -> void:
	_enter_hide(map_seed)


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


## The id saved in user://profile.json, made on first launch.
func load_player_id() -> String:
	var p := JsonStore.load_dict(PROFILE_FILE)
	var id := String(p.get("player_id", ""))
	if id.length() < 8:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		id = "%08x%04x" % [rng.randi(), rng.randi() & 0xFFFF]
		p["player_id"] = id
		JsonStore.save_dict(PROFILE_FILE, p)
	return id


## Hide mode on [param p_map_id] (default: the current map). Goes to the
## creator first if there's no avatar yet. A quick game: the classic rule on
## the classic town, nothing recorded.
func start_hide(p_seed: int, p_map_id: String = map_id) -> void:
	map_id = p_map_id
	map_size = ""
	session = {"kind": KIND_QUICK}
	_enter_hide(p_seed)


func _enter_hide(p_seed: int) -> void:
	map_seed = p_seed
	if not has_avatar():
		start_creator(p_seed, true)
		return
	mode = Mode.HIDE
	challenge = null
	auto_hide = {}
	_go(TOWN_SCENE)


## Hide for a friend game. [param friend_id] "" = a new invite (whoever opens
## the code becomes your friend). Size and hide rule come from the difficulty.
func start_friend_hide(friend_id: String, difficulty: String) -> void:
	map_id = TOWN_MAP_ID
	map_size = String(Difficulty.get_level(difficulty)["size"])
	session = {"kind": KIND_FRIEND, "friend_id": friend_id, "difficulty": difficulty}
	_enter_hide(random_seed())


## Searches [param c]. [param p_session] says what the round counts for
## (default: a quick game).
func start_search(c: ChallengeData, p_session: Dictionary = {"kind": KIND_QUICK}) -> void:
	mode = Mode.SEARCH
	challenge = c
	auto_hide = {}
	session = p_session
	map_seed = c.map_seed
	map_id = c.map_id
	map_size = c.town_size
	_go(TOWN_SCENE)


## Search a town where the computer hid someone ([param who] {} = random).
func _start_auto(p_seed: int, difficulty: String, p_session: Dictionary, who: Dictionary = {}) -> void:
	mode = Mode.SEARCH
	challenge = null
	session = p_session
	auto_hide = {"difficulty": difficulty, "who": who}
	map_seed = p_seed
	map_id = TOWN_MAP_ID
	map_size = String(Difficulty.get_level(difficulty)["size"])
	_go(TOWN_SCENE)


## Play: a new random town at [param difficulty].
func start_play(difficulty: String) -> void:
	_start_auto(random_seed(), difficulty, {"kind": KIND_PLAY, "difficulty": difficulty})


## Today's Daily challenge: the same town and hider for everyone today.
func start_daily() -> void:
	var date := Progress.today()
	var difficulty := Progress.daily_difficulty(date)
	_start_auto(Progress.daily_seed(date), difficulty, {"kind": KIND_DAILY, "difficulty": difficulty, "date": date})


## A round against a practice partner: they hide (the computer picks the spot).
func start_bot_round(friend_id: String) -> void:
	var f := FriendsStore.get_friend(friend_id)
	if f.is_empty():
		go_friends("That game is gone.")
		return
	var difficulty := String(f.get("difficulty", Difficulty.DEFAULT_ID))
	_start_auto(random_seed(), difficulty, {"kind": KIND_FRIEND, "friend_id": friend_id, "difficulty": difficulty, "bot": true},
		{"name": f["name"], "look": f["look"]})


## Plays the code waiting from [param friend_id].
func start_friend_search(friend_id: String) -> void:
	var f := FriendsStore.get_friend(friend_id)
	if bool(f.get("bot", false)):
		start_bot_round(friend_id)
		return
	var result := ChallengeCodec.decode(String(f.get("inbox", "")))
	if result["challenge"] == null:
		go_friends(String(result["error"]))
		return
	var c: ChallengeData = result["challenge"]
	start_search(c, {"kind": KIND_FRIEND, "friend_id": friend_id, "difficulty": c.difficulty})


func go_friends(message: String = "") -> void:
	mode = Mode.MENU
	menu_message = message
	_go(FRIENDS_SCENE)


static func random_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi_range(0, 999999)


func start_debug(p_seed: int) -> void:
	mode = Mode.DEBUG_VIEW
	map_seed = p_seed
	challenge = null
	auto_hide = {}
	_go(TOWN_SCENE)


func go_menu(message: String = "", page: String = "") -> void:
	mode = Mode.MENU
	menu_message = message
	menu_page = page
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


## Opens links at startup and, on iOS, whenever one arrives later (the native
## side drops it in a file; polling is cheaper than wiring a callback).
func _watch_deep_links() -> void:
	var first := DeepLink.code_from(String(dev_args.get("link", ""))) if dev_args.has("link") else DeepLink.from_web_page()
	if first != "":
		open_code.call_deferred(first)
	if OS.get_name() == "iOS":
		var timer := Timer.new()
		timer.wait_time = 0.5
		timer.autostart = true
		timer.timeout.connect(func() -> void:
			var code := DeepLink.take()
			if code != "":
				open_code(code))
		add_child(timer)


## Opens a challenge code (from a deep link) the same way as pasting it on
## the friends screen: records the friend game, then plays it.
func open_code(code: String) -> void:
	print("[DeepLink] opening code (%d chars) from mode %s" % [code.length(), mode])
	pending_code = code
	go_friends()


func _apply_dev_mode() -> void:
	match String(dev_args["mode"]):
		"create":
			start_creator(map_seed)
		"hide":
			start_hide(map_seed)
		"debug":
			start_debug(map_seed)
		"play":
			var diff := String(dev_args.get("difficulty", Difficulty.DEFAULT_ID))
			_start_auto(map_seed, diff, {"kind": KIND_PLAY, "difficulty": diff})
		"daily":
			start_daily()
		"friends":
			go_friends()
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
	var map_def := MapDefinition.load_map(map_id, map_seed, map_size)
	var layout := TownGenerator.generate(map_def, map_seed)
	var avatar := my_avatar if has_avatar() else {"name": "", "look": AvatarKit.default_look()}
	var at := parse_vec2(String(dev_args.get("at", "720,700")))
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
