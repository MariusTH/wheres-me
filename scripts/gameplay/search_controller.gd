class_name SearchController
extends Node
## Search mode: the map is read-only; tap people (or, in the museum,
## critters) until you find the hider.
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


func start(town: TownController, camera: MapCamera, hud_layer: CanvasLayer, challenge: ChallengeData) -> void:
	_town = town
	_camera = camera
	_challenge = challenge
	_hud = HUD_SCENE.instantiate() as SearchHud
	hud_layer.add_child(_hud)
	_hud.setup(challenge)
	_hud.give_up_pressed.connect(give_up)
	_hud.menu_pressed.connect(func() -> void: AppState.go_menu())
	if not challenge.is_critter():
		town.ensure_unique(challenge.hider_look)
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


## "" if the challenge fits this build's town, otherwise why not. Re-runs the
## visibility rule: a mismatched map would usually bury or expose the hider.
static func verify(c: ChallengeData, map_def: MapDefinition, layout: TownLayout) -> String:
	if c.map_id != map_def.map_id:
		return "This challenge is for map '%s', not '%s'." % [c.map_id, map_def.map_id]
	if c.map_version != map_def.map_version:
		return "This challenge was made with map version %d, but this build has version %d." % [c.map_version, map_def.map_version]
	if c.generator_version != layout.generator_version:
		return "This challenge was made with town generator v%d, but this build uses v%d." % [c.generator_version, layout.generator_version]
	if c.is_critter() != (map_def.hide_subject == "critter"):
		return "This challenge doesn't match the %s map." % map_def.title
	if c.is_critter() and c.hider_critter != TownGenerator.critter_for_seed(c.map_seed):
		return "The hidden critter doesn't match this seed."
	var result := VisibilityChecker.new(map_def, layout.objects).check_subject(c.subject(), c.target_world_position)
	if not result["ok"]:
		return "The hiding spot isn't valid in this town (%s)" % String(result["reason"]).trim_suffix(".")
	return ""


func _process(delta: float) -> void:
	if _running:
		_elapsed += delta
		_hud.set_stats(_elapsed, _taps, _wrong)


## Returns the tapped person or critter (or null). Public so tests can drive it.
func handle_tap(world_pos: Vector2) -> WorldActor:
	if not _running:
		return null
	var pad := TAP_PAD_SCREEN_PX / _camera.zoom.x
	var ch: WorldActor = _town.critter_at(world_pos, pad) if _challenge.is_critter() else _town.character_at(world_pos, pad)
	if ch == null:
		_hud.toast("Tap on a critter to guess." if _challenge.is_critter() else "Tap on a person to guess.")
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
	_hud.show_result(p_found, _elapsed, _taps, _wrong,
		func() -> void: AppState.start_search(_challenge),
		func() -> void: AppState.start_hide(_challenge.map_seed, _challenge.map_id),
		func() -> void: AppState.go_menu())
