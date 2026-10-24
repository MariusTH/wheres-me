extends Node2D
## Town scene root: builds the map for the current seed, then runs the mode
## chosen in AppState (hide, search or debug view).

@onready var town: TownController = $Town
@onready var camera: MapCamera = $MapCamera
@onready var debug_overlay: MapDebugOverlay = $DebugOverlay
@onready var hud_layer: CanvasLayer = $HUD

var map_def: MapDefinition
var layout: TownLayout
var controller: Node = null


func _ready() -> void:
	map_def = MapDefinition.load_map(AppState.map_id)
	if map_def == null:
		AppState.go_menu("Could not load map '%s'. See the console for details." % AppState.map_id)
		return
	var map_seed := AppState.map_seed
	if AppState.mode == AppState.Mode.SEARCH and AppState.challenge:
		map_seed = AppState.challenge.map_seed
	layout = TownGenerator.generate(map_def, map_seed)
	for s in layout.shortfalls:
		push_warning("Generator shortfall: " + s)
	town.build(map_def, layout)
	camera.setup(map_def.world_bounds)
	debug_overlay.setup(map_def, layout, town)

	match AppState.mode:
		AppState.Mode.HIDE:
			var hider_name := String(AppState.my_avatar.get("name", ""))
			var subject: WorldObjectData
			if map_def.hide_subject == "critter":
				subject = VisibilityChecker.subject_for_critter(TownGenerator.critter_for_seed(map_seed))
			elif AppState.has_avatar():
				subject = VisibilityChecker.subject_for_look(AppState.my_avatar["look"])
			else:
				AppState.start_creator(map_seed)
				return
			var hc := HideController.new()
			hc.name = "HideController"
			add_child(hc)
			hc.start(town, camera, hud_layer, subject, hider_name)
			controller = hc
		AppState.Mode.SEARCH:
			if AppState.challenge == null:
				AppState.go_menu("No challenge loaded.")
				return
			var sc := SearchController.new()
			sc.name = "SearchController"
			add_child(sc)
			sc.start(town, camera, hud_layer, AppState.challenge)
			controller = sc
		_:
			var hud := DebugHud.new()
			hud_layer.add_child(hud)
			hud.setup(layout)
			debug_overlay.level = MapDebugOverlay.Level.SHAPES
	_apply_dev_args()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == KEY_F1:
		debug_overlay.cycle()
		get_viewport().set_input_as_handled()


func _apply_dev_args() -> void:
	var a := AppState.dev_args
	if a.has("center") or a.has("zoom"):
		var c := AppState.parse_vec2(String(a.get("center", "")))
		camera.set_view(c if c.is_finite() else camera.position, float(a.get("zoom", "1.0")))
	if a.has("debug"):
		debug_overlay.level = clampi(int(a["debug"]), 0, 2) as MapDebugOverlay.Level
	if controller is HideController:
		if a.has("place"):
			controller.place_at(AppState.parse_vec2(String(a["place"])))
		if a.has("confirm"):
			controller.confirm()
	if controller is SearchController and (a.has("tap") or a.has("start")):
		controller.begin()
	if controller is SearchController and a.has("tap"):
		controller.handle_tap(AppState.parse_vec2(String(a["tap"])))
