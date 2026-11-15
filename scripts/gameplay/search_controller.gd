class_name SearchController
extends Node
## Search mode: the map is read-only; tap people until you find the hider.
## Opens behind a "find this person" intro; the clock starts on Start.

const HUD_SCENE := preload("res://scenes/ui/search_hud.tscn")
## Extra tap tolerance around each person, in screen pixels.
const TAP_PAD_SCREEN_PX := 6.0
const REVEAL_ZOOM := 1.4

var _town: TownController
var _camera: MapCamera
var _hud: SearchHud
var _challenge: ChallengeData
var _elapsed := 0.0
var _taps := 0
var _wrong := 0
var _running := false
var found := false
## SearchHelp stages already applied this search (-1 = none yet).
var _help_stage := -1
var _help_on := true


func start(town: TownController, camera: MapCamera, hud_layer: CanvasLayer, challenge: ChallengeData) -> void:
	_town = town
	_camera = camera
	_challenge = challenge
	_hud = HUD_SCENE.instantiate() as SearchHud
	hud_layer.add_child(_hud)
	_hud.setup(challenge, _kicker())
	_hud.give_up_pressed.connect(give_up)
	_hud.menu_pressed.connect(func() -> void:
		if AppState.session.get("kind") == AppState.KIND_FRIEND:
			AppState.go_friends()
		else:
			AppState.go_menu())
	town.prepare_crowd(challenge.hider_look, challenge.decoys)
	var err := verify(challenge, town.map_def, town.layout)
	if err != "":
		push_warning("Challenge rejected: " + err)
		_hud.show_error(err, func() -> void: AppState.go_menu())
		return
	town.place_subject(challenge.subject(), challenge.target_world_position)
	camera.tapped.connect(handle_tap)
	_hud.show_intro(begin)


## Starts the clock and accepts taps. Called by the intro's Start button;
## public so tests and the --tap dev flag can skip the intro.
func begin() -> void:
	if _running or found or _town.target == null:
		return
	_hud.hide_intro()
	_elapsed = 0.0
	_running = true
	_help_on = SearchHelp.enabled()


## "" if the challenge fits this build's town, otherwise why not. Re-runs the
## visibility rule: a mismatched map would usually bury or expose the hider.
static func verify(c: ChallengeData, map_def: MapDefinition, layout: TownLayout) -> String:
	if c.map_id != map_def.map_id:
		return "This challenge is for map '%s', not '%s'." % [c.map_id, map_def.map_id]
	if c.map_version != map_def.map_version:
		return "This challenge was made with map version %d, but this build has version %d." % [c.map_version, map_def.map_version]
	if c.generator_version != layout.generator_version:
		return "This challenge was made with town generator v%d, but this build uses v%d." % [c.generator_version, layout.generator_version]
	var result := c.checker(map_def, layout).check_subject(c.subject(), c.target_world_position)
	if not result["ok"]:
		return "The hiding spot isn't valid in this town (%s)" % String(result["reason"]).trim_suffix(".")
	return ""


func _process(delta: float) -> void:
	if _running:
		_elapsed += delta
		_hud.set_stats(_elapsed, _taps, _wrong)
		var next := _help_stage + 1
		if _help_on and next < SearchHelp.STAGES.size() and _elapsed >= float(SearchHelp.STAGES[next]["after"]):
			apply_help(next)


## Makes the search easier (see SearchHelp): some of the crowd leaves and the
## hider steps out of hiding a bit. Public so tests can drive it.
func apply_help(stage: int) -> void:
	_help_stage = stage
	var st: Dictionary = SearchHelp.STAGES[stage]
	var gone := SearchHelp.leavers(_town.layout, float(st["thin"]), _town.layout.map_seed)
	for c in _town.characters():
		if c != _town.target and c.visible and gone.has(c.object_id):
			var t := c.create_tween()
			t.tween_property(c, "modulate:a", 0.0, 0.8)
			t.tween_callback(func() -> void: c.visible = false)
	var target := _town.target
	var to := SearchHelp.step_out(_town.map_def, _town.layout, _challenge.hider_look, target.position, float(st["visible"]), gone)
	if to != target.position:
		var t := target.create_tween()
		t.tween_property(target, "position", to, 1.2).set_trans(Tween.TRANS_SINE)
	_hud.toast("Hint: the crowd thinned and %s stepped out" % _hider_name(), UiKit.GOOD, 4.0)


func _hider_name() -> String:
	return _challenge.hider_name if _challenge.hider_name.strip_edges() != "" else "they"


## Returns the tapped person (or null). Public so tests can drive it.
func handle_tap(world_pos: Vector2) -> WorldActor:
	if not _running:
		return null
	var pad := TAP_PAD_SCREEN_PX / _camera.zoom.x
	var ch: WorldActor = _town.character_at(world_pos, pad)
	if ch == null:
		_hud.toast("Tap on a person to guess.")
		return null
	_taps += 1
	if ch == _town.target:
		_finish(true)
	else:
		_wrong += 1
		ch.flash_wrong()
		_hud.toast("Not them! Keep looking.", UiKit.BAD)
		if _challenge.wrong_tap_limit > 0 and _wrong >= _challenge.wrong_tap_limit:
			_finish(false)
	_hud.set_stats(_elapsed, _taps, _wrong)
	return ch


func give_up() -> void:
	if _running:
		_finish(false)


func _finish(p_found: bool) -> void:
	_running = false
	found = p_found
	var t := _town.target
	if p_found or _challenge.show_target_on_finish:
		t.marker = WorldActor.Marker.FOUND
		_town.fade_canopies_near(t.position, 110.0)
		var ring := PulseRing.new()
		ring.color = UiKit.GOOD if p_found else UiKit.ACCENT
		ring.position = t.position
		_town.add_child(ring)
		var from := _camera.position
		var from_zoom := _camera.zoom.x
		var to_zoom := maxf(from_zoom, REVEAL_ZOOM)
		var tween := create_tween()
		tween.tween_method(func(k: float) -> void:
			_camera.set_view(from.lerp(t.position + Vector2(0, 60), k), lerpf(from_zoom, to_zoom, k)), 0.0, 1.0, 0.6).set_trans(Tween.TRANS_SINE)
	var outcome := _record(p_found)
	_hud.show_result(p_found, _elapsed, _taps, _wrong, outcome["lines"], outcome["actions"])


## Small line over the intro title: "Daily #3 · Hard", "Play · Expert", "Round 4 with Alex".
func _kicker() -> String:
	var s := AppState.session
	match String(s.get("kind", "")):
		AppState.KIND_DAILY:
			return "Daily #%d · %s" % [Progress.daily_number(String(s["date"])), Difficulty.get_level(String(s["difficulty"]))["name"]]
		AppState.KIND_PLAY:
			return "Play · %s" % Difficulty.get_level(String(s["difficulty"]))["name"]
		AppState.KIND_FRIEND:
			var f := FriendsStore.get_friend(String(s.get("friend_id", "")))
			if not f.is_empty():
				return "Round %d with %s%s" % [FriendsStore.stats(f)["rounds"] / 2 + 1, f["name"], " (practice partner)" if f.get("bot") else ""]
	return ""


## Saves the result for this kind of game; returns {"lines": [...], "actions": [[text, Callable, Color]]}.
func _record(p_found: bool) -> Dictionary:
	var s := AppState.session
	var c := _challenge
	var menu := ["Menu", func() -> void: AppState.go_menu(), UiKit.MUTED]
	match String(s.get("kind", "")):
		AppState.KIND_DAILY:
			var date := String(s["date"])
			var r := Progress.record_daily(date, p_found, _elapsed, _taps, _wrong)
			var lines: Array = []
			if r["counted"]:
				lines.append("Score %d%s" % [r["score"], "  ·  New best!" if r["new_best"] else ""])
				lines.append("Your best daily score: %d  ·  Streak: %d day%s" % [r["best"], r["streak"], "" if r["streak"] == 1 else "s"])
			else:
				lines.append("Replay: only your first try today counts (score %d)." % Progress.daily_result(date).get("score", 0))
			lines.append("A new town every day. Come back tomorrow!")
			return {"lines": lines, "actions": [
				["Play a random town", func() -> void: AppState.go_menu("", "play"), UiKit.GOOD], menu]}
		AppState.KIND_PLAY:
			var diff := String(s["difficulty"])
			var r := Progress.record_play(diff, p_found, _elapsed, _wrong)
			var lines: Array = ["Score %d%s" % [r["score"], "  ·  New best!" if r["new_best"] else ""]]
			lines.append("Your best on %s: %d" % [Difficulty.get_level(diff)["name"], r["best"]])
			return {"lines": lines, "actions": [
				["Next town", func() -> void: AppState.start_play(diff), UiKit.GOOD],
				["Difficulty", func() -> void: AppState.go_menu("", "play"), UiKit.ACCENT], menu]}
		AppState.KIND_FRIEND:
			var friend_id := String(s.get("friend_id", ""))
			FriendsStore.record_my_find(friend_id, c, p_found, _elapsed, _taps, _wrong)
			var f := FriendsStore.get_friend(friend_id)
			var st := FriendsStore.stats(f)
			var lines: Array = []
			if float(st["my_best"]) > 0.0:
				lines.append("Your fastest find vs %s: %s" % [f.get("name", "them"), UiKit.format_time(st["my_best"])])
			lines.append("Now hide, and your time goes along with your code.")
			return {"lines": lines, "actions": [
				["Hide and send back", func() -> void: AppState.start_friend_hide(friend_id, String(f.get("difficulty", Difficulty.DEFAULT_ID))), UiKit.GOOD],
				["Friends", func() -> void: AppState.go_friends(), UiKit.MUTED]]}
	return {"lines": [], "actions": [
		["Retry", func() -> void: AppState.start_search(c), UiKit.ACCENT],
		["Swap roles: you hide", func() -> void: AppState.start_hide(c.map_seed, c.map_id), UiKit.GOOD],
		menu]}
