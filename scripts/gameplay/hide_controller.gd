class_name HideController
extends Node
## Hide mode: tap anywhere to place your avatar (or, in the museum, the
## critter the seed picked), drag it to fine-tune, and confirm once at least
## VisibilityChecker.MIN_VISIBLE of it shows on screen.
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


## [param subject]: VisibilityChecker.subject_for_look() or subject_for_critter().
func start(town: TownController, camera: MapCamera, hud_layer: CanvasLayer, subject: WorldObjectData, hider_name: String) -> void:
	_town = town
	_camera = camera
	_subject = subject
	_name = hider_name
	if not VisibilityChecker.is_critter(subject):
		subject.look = AvatarKit.normalize(subject.look)
		town.ensure_unique(subject.look)
	_checker = VisibilityChecker.new(town.map_def, town.layout.objects)
	_hud = HUD_SCENE.instantiate() as HideHud
	hud_layer.add_child(_hud)
	_hud.setup(subject, _name, town.map_def.title, town.layout.map_seed)
	_hud.confirm_pressed.connect(confirm)
	_hud.back_pressed.connect(func() -> void: AppState.go_menu())
	_hud.edit_pressed.connect(func() -> void: AppState.start_creator(town.layout.map_seed))
	camera.tapped.connect(func(p: Vector2) -> void: place_at(p + TAP_TO_FEET))
	camera.drag_interceptor = _grab
	camera.object_dragged.connect(func(p: Vector2) -> void: place_at(p + _grab_offset))
	camera.object_released.connect(func(p: Vector2) -> void: place_at(p + _grab_offset))


## Moves the avatar's feet to [param feet] and re-checks how visible it is.
func place_at(feet: Vector2) -> Dictionary:
	if _confirmed:
		return last_check
	_feet = feet.round()
	var target := _town.place_subject(_subject, _feet)
	last_check = _checker.check_subject(_subject, _feet)
	target.marker = WorldActor.Marker.PREVIEW_OK if last_check["ok"] else WorldActor.Marker.PREVIEW_BAD
	_hud.show_check(last_check)
	return last_check


func confirm() -> ChallengeData:
	if _confirmed or last_check.is_empty() or not last_check["ok"]:
		return null
	_confirmed = true
	var c: ChallengeData
	if VisibilityChecker.is_critter(_subject):
		c = ChallengeData.create_critter(_town.layout, _subject.asset_key, _name, _feet)
	else:
		c = ChallengeData.create(_town.layout, _subject.look, _name, _feet)
	AppState.challenge = c
	var path := ChallengeCodec.save_to_file(c)
	_town.target.marker = WorldActor.Marker.NONE
	_hud.show_share(ChallengeCodec.encode(c), path,
		func() -> void: AppState.start_search(c),
		func() -> void: AppState.start_hide(c.map_seed, c.map_id),
		func() -> void: AppState.go_menu())
	return c


## Starts an avatar drag when a press lands on the placed avatar.
func _grab(world_pos: Vector2) -> bool:
	if _confirmed or _town.target == null:
		return false
	if not _town.target.hit_rect(GRAB_PAD_SCREEN_PX / _camera.zoom.x).has_point(world_pos):
		return false
	_grab_offset = _town.target.position - world_pos
	return true
