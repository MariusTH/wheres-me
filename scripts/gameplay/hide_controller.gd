class_name HideController
extends Node
## Hide mode: tap anywhere to place your avatar, drag it to fine-tune, and
## confirm once at least VisibilityChecker.MIN_VISIBLE of it shows on screen.
## Canopies stay opaque here so the hider sees exactly what the seeker will.

const HUD_SCENE := preload("res://scenes/ui/hide_hud.tscn")
## A tap marks the avatar's middle (so the finger doesn't cover it); the feet
## go this far below the tap.
const TAP_TO_FEET := Vector2(0, 30)
## Extra grab area around the avatar, in screen pixels (fingers are wide).
const GRAB_PAD_SCREEN_PX := 14.0

## Result of the latest visibility check ({fraction, ok, reason}).
var last_check: Dictionary = {}

var _town: TownController
var _camera: MapCamera
var _hud: HideHud
var _checker: VisibilityChecker
var _subject: WorldObjectData
var _name: String = ""
var _feet := Vector2.INF
var _grab_offset := Vector2.ZERO
var _confirmed := false
var _difficulty := ""


## [param subject]: VisibilityChecker.subject_for_look(). [param difficulty]:
## a Difficulty id for friend games ("" = the classic 70% rule, no decoys).
func start(town: TownController, camera: MapCamera, hud_layer: CanvasLayer, subject: WorldObjectData, hider_name: String, difficulty: String = "") -> void:
	_town = town
	_camera = camera
	_subject = subject
	_name = hider_name
	_difficulty = difficulty
	subject.look = AvatarKit.normalize(subject.look)
	var min_visible := VisibilityChecker.MIN_VISIBLE
	var min_head := VisibilityChecker.MIN_HEAD
	var decoys := 0
	if difficulty != "":
		var l := Difficulty.get_level(difficulty)
		min_visible = float(l["min_visible"])
		min_head = maxf(float(l["min_head"]), VisibilityChecker.MIN_HEAD)
		decoys = int(l["decoys"])
	town.prepare_crowd(subject.look, decoys)
	_checker = VisibilityChecker.new(town.map_def, town.layout.objects, min_visible, min_head)
	_hud = HUD_SCENE.instantiate() as HideHud
	hud_layer.add_child(_hud)
	_hud.setup(subject, _name, town.map_def.title, town.layout.map_seed, min_visible, min_head, _context_line())
	_hud.confirm_pressed.connect(confirm)
	_hud.back_pressed.connect(func() -> void:
		if AppState.session.get("kind") == AppState.KIND_FRIEND:
			AppState.go_friends()
		else:
			AppState.go_menu())
	_hud.edit_pressed.connect(func() -> void: AppState.start_creator(town.layout.map_seed, true))
	camera.tapped.connect(func(p: Vector2) -> void: place_at(p + TAP_TO_FEET))
	camera.drag_interceptor = _grab
	camera.object_dragged.connect(func(p: Vector2) -> void: place_at(p + _grab_offset))
	camera.object_released.connect(func(p: Vector2) -> void: place_at(p + _grab_offset))


## "Hiding for Alex · Hard" etc., shown in the HUD.
func _context_line() -> String:
	if AppState.session.get("kind") != AppState.KIND_FRIEND:
		return ""
	var f := FriendsStore.get_friend(String(AppState.session.get("friend_id", "")))
	var who := ("Hiding for %s" % f["name"]) if not f.is_empty() else "New game: whoever opens your code"
	return "%s · %s" % [who, Difficulty.get_level(_difficulty)["name"]]


## Moves the avatar's feet to [param feet] and re-checks how visible it is.
func place_at(feet: Vector2) -> Dictionary:
	if _confirmed:
		return last_check
	# Stay inside the town: the margin round the map (MapFrame) is empty paper.
	var b := _town.map_def.world_bounds
	_feet = Vector2(clampf(feet.x, b.position.x + 16.0, b.end.x - 16.0), clampf(feet.y, b.position.y + 80.0, b.end.y - 4.0)).round()
	var target := _town.place_subject(_subject, _feet)
	last_check = _checker.check_subject(_subject, _feet)
	target.marker = WorldActor.Marker.PREVIEW_OK if last_check["ok"] else WorldActor.Marker.PREVIEW_BAD
	_hud.show_check(last_check)
	return last_check


func confirm() -> ChallengeData:
	if _confirmed or last_check.is_empty() or not last_check["ok"]:
		return null
	_confirmed = true
	var c := ChallengeData.create(_town.layout, _subject.look, _name, _feet)
	if _difficulty != "":
		c.apply_difficulty(_difficulty)
	var session := AppState.session
	var friend_id := String(session.get("friend_id", ""))
	if session.get("kind") == AppState.KIND_FRIEND:
		c.from_id = AppState.player_id
		c.round = FriendsStore.next_round(friend_id)
		c.reply = FriendsStore.pending_reply(friend_id)
	AppState.challenge = c
	var path := ChallengeCodec.save_to_file(c)
	_town.target.marker = WorldActor.Marker.NONE
	if session.get("kind") != AppState.KIND_FRIEND:
		_hud.show_share(ChallengeCodec.encode(c), path, {}, [
			["Search now (pass the device)", func() -> void: AppState.start_search(c), UiKit.GOOD],
			["Hide again", func() -> void: AppState.start_hide(c.map_seed, c.map_id), UiKit.ACCENT],
			["Menu", func() -> void: AppState.go_menu(), UiKit.MUTED],
		])
		return c
	FriendsStore.record_sent(friend_id, c, ChallengeCodec.encode(c))
	var f := FriendsStore.get_friend(friend_id)
	if bool(f.get("bot", false)):
		# A practice partner searches right away.
		var r := FriendsStore.bot_searches(friend_id, c, float(last_check["fraction"]))
		var title := ("%s found you!" % f["name"]) if r["found"] else ("%s gave up!" % f["name"])
		var line := ("It took them %s with %d wrong taps." % [UiKit.format_time(r["time"]), r["wrong"]]) if r["found"] \
			else "They searched for %s and never spotted you." % UiKit.format_time(r["time"])
		_hud.show_notice(title, [line, "Now it's their turn to hide."], [
			["Find %s" % f["name"], func() -> void: AppState.start_bot_round(friend_id), UiKit.GOOD],
			["Friends", func() -> void: AppState.go_friends(), UiKit.MUTED],
		])
		return c
	var to := String(f.get("name", "")) if not f.is_empty() else ""
	var hint := "Send this code to %s. When they've found you, they hide and send one back. Paste it in Friends." % to if to != "" \
		else "Send this code to a friend. They paste it in Where's Me under Friends, find you, and send one back."
	var message := "Round %d: can you find me in Where's Me? Tap the link to play (or paste it under Friends at %s):\n\n%s" % [c.round, HideHud.GAME_URL, DeepLink.make(ChallengeCodec.encode(c))]
	if not c.reply.is_empty():
		message = "I found you in %s! Your turn: %s" % [UiKit.format_time(float(c.reply["time"])), message] if c.reply["found"] \
			else "You beat me that time! Your turn: %s" % message
	_hud.show_share(ChallengeCodec.encode(c), path, {"title": "Send it to %s!" % to if to != "" else "Invite ready!", "hint": hint, "message": message}, [
		["Friends", func() -> void: AppState.go_friends(), UiKit.GOOD],
		["Menu", func() -> void: AppState.go_menu(), UiKit.MUTED],
	])
	return c


## Starts an avatar drag when a press lands on the placed avatar.
func _grab(world_pos: Vector2) -> bool:
	if _confirmed or _town.target == null:
		return false
	if not _town.target.hit_rect(GRAB_PAD_SCREEN_PX / _camera.zoom.x).has_point(world_pos):
		return false
	_grab_offset = _town.target.position - world_pos
	return true
