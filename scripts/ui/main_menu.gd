extends Control
## Home / test menu: start a hide challenge, load one, or open the debug view.

var _seed_box: SpinBox
var _code: TextEdit
var _message: Label


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("9cc56f")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var paper := UiKit.icon("ui_map_paper", 100)
	if paper.texture:
		paper.stretch_mode = TextureRect.STRETCH_SCALE
		paper.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.color = UiKit.ACCENT
		add_child(paper)
	var crowd := _MenuCrowd.new()
	crowd.set_anchors_preset(Control.PRESET_FULL_RECT)
	crowd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(crowd)

	var v := UiKit.vbox(9)
	v.custom_minimum_size = Vector2(600, 0)
	var head := UiKit.hbox(0)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(UiKit.icon("ui_magnifier", 96))
	head.add_child(UiKit.banner("Where's Me", 440, 46))
	head.add_child(UiKit.icon("ui_hat", 70))
	v.add_child(head)
	var sub := UiKit.label("Hide in the crowd, send the puzzle, and see if your friend can find you.", 17, UiKit.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)

	var seed_row := UiKit.hbox(8)
	seed_row.add_child(UiKit.label("Seed", 17, UiKit.INK, false))
	_seed_box = SpinBox.new()
	_seed_box.min_value = 0
	_seed_box.max_value = ChallengeCodec.MAX_SEED
	_seed_box.value = AppState.map_seed
	_seed_box.custom_minimum_size = Vector2(180, 0)
	seed_row.add_child(_seed_box)
	var random_seed := UiKit.button("Random", _on_random_seed, UiKit.MUTED)
	random_seed.custom_minimum_size = Vector2(0, 40)
	seed_row.add_child(random_seed)
	v.add_child(seed_row)
	var hide_row := UiKit.hbox(8)
	var hide := UiKit.button("Hide yourself in town", func() -> void: AppState.start_hide(int(_seed_box.value), AppState.TOWN_MAP_ID), UiKit.GOOD)
	hide.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hide_row.add_child(hide)
	hide_row.add_child(UiKit.button("Edit avatar" if AppState.has_avatar() else "Create avatar", func() -> void:
		AppState.map_id = AppState.TOWN_MAP_ID
		AppState.start_creator(int(_seed_box.value)), UiKit.MUTED))
	v.add_child(hide_row)
	var museum := UiKit.button("Hide the %s in the museum" % AssetCatalog.label(TownGenerator.critter_for_seed(int(_seed_box.value))), func() -> void: AppState.start_hide(int(_seed_box.value), AppState.MUSEUM_MAP_ID), UiKit.ACCENT)
	_seed_box.value_changed.connect(func(value: float) -> void:
		museum.text = "Hide the %s in the museum" % AssetCatalog.label(TownGenerator.critter_for_seed(int(value))))
	v.add_child(museum)

	v.add_child(UiKit.stripes(10))
	v.add_child(UiKit.label("Got a code from a friend?", 19))
	_code = TextEdit.new()
	_code.placeholder_text = "Paste a WM1-… code or challenge JSON here"
	_code.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_code.custom_minimum_size = Vector2(580, 60)
	v.add_child(_code)
	var load_row := UiKit.hbox(8)
	load_row.add_child(UiKit.button("Paste", func() -> void: _code.text = DisplayServer.clipboard_get(), UiKit.MUTED))
	var search := UiKit.button("Search for them!", _on_search_code)
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_row.add_child(search)
	v.add_child(load_row)
	var saved := ChallengeCodec.list_saved()
	var latest := UiKit.button("Load latest saved (%d)" % saved.size(), _on_load_latest, UiKit.MUTED)
	latest.disabled = saved.is_empty()
	latest.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var misc_row := UiKit.hbox(8)
	misc_row.add_child(latest)
	misc_row.add_child(UiKit.button("Map debug view", func() -> void:
		AppState.map_id = AppState.TOWN_MAP_ID
		AppState.start_debug(int(_seed_box.value)), UiKit.MUTED))
	v.add_child(misc_row)
	_message = UiKit.label(AppState.menu_message, 16, UiKit.BAD)
	AppState.menu_message = ""
	v.add_child(_message)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.add_child(UiKit.panel(v))


func _on_random_seed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_seed_box.value = rng.randi_range(0, 999999)


func _on_search_code() -> void:
	_start_from(ChallengeCodec.decode(_code.text))


func _on_load_latest() -> void:
	var saved := ChallengeCodec.list_saved()
	if saved.is_empty():
		_message.text = "No saved challenges yet."
		return
	_start_from(ChallengeCodec.load_from_file(saved[0]))


func _start_from(result: Dictionary) -> void:
	if result["challenge"] == null:
		_message.text = result["error"]
		return
	AppState.start_search(result["challenge"])


## Decorative row of kit-generated people along the bottom of the menu.
class _MenuCrowd extends Control:
	func _draw() -> void:
		var rng := DetHash.make_rng(1, "menu_crowd")
		var x := 30.0
		var i := 0
		while x < size.x:
			PlaceholderArt.draw_character(self, AvatarKit.random_look(rng), i % 3 == 0, Vector2(x, size.y - 12.0 - float(i % 2) * 18.0), 1.4)
			x += 46.0
			i += 1
