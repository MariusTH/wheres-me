extends Control
## Home menu: hide in the town or the museum, or paste a friend's code and
## search. Lays itself out for desktop, phone portrait (narrow) and phone
## landscape (short), and rebuilds when the size class changes.

var _seed_text: LineEdit
var _code: TextEdit
var _message: Label
var _museum: Button
var _content: Control


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
	_build(str(AppState.map_seed), "", AppState.menu_message)
	AppState.menu_message = ""
	AppState.layout_changed.connect(func() -> void: _build(_seed_text.text, _code.text, _message.text))


func _build(seed_text: String, code_text: String, message: String) -> void:
	if _content:
		_content.queue_free()
	var narrow := AppState.is_narrow()
	var width := UiKit.fit_width(600.0)

	var v := UiKit.vbox(9)
	v.custom_minimum_size = Vector2(width, 0)
	var head := UiKit.hbox(0)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	if not narrow:
		head.add_child(UiKit.icon("ui_magnifier", 96))
	head.add_child(UiKit.banner("Where's Me", minf(440.0, width - 20.0), 46))
	if not narrow:
		head.add_child(UiKit.icon("ui_hat", 70))
	v.add_child(head)
	var sub := UiKit.label("Hide in the crowd, send the puzzle, and see if your friend can find you.", 17, UiKit.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)

	# A plain number field: SpinBox arrows are too small to hit on a phone.
	var seed_row := UiKit.hbox(8)
	seed_row.add_child(UiKit.label("Seed", 17, UiKit.INK, false))
	_seed_text = LineEdit.new()
	_seed_text.text = seed_text
	_seed_text.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_seed_text.custom_minimum_size = Vector2(0, 48)
	_seed_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_text.text_changed.connect(func(_t: String) -> void: _update_museum_label())
	seed_row.add_child(_seed_text)
	seed_row.add_child(UiKit.button("Random", _on_random_seed, UiKit.MUTED))
	v.add_child(seed_row)

	var hide_row := UiKit.hbox(8)
	var hide := UiKit.button("Hide in town", func() -> void: AppState.start_hide(_seed(), AppState.TOWN_MAP_ID), UiKit.GOOD)
	hide.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hide_row.add_child(hide)
	hide_row.add_child(UiKit.button("Edit avatar" if AppState.has_avatar() else "Create avatar", func() -> void:
		AppState.map_id = AppState.TOWN_MAP_ID
		AppState.start_creator(_seed()), UiKit.MUTED))
	v.add_child(hide_row)
	_museum = UiKit.button("", func() -> void: AppState.start_hide(_seed(), AppState.MUSEUM_MAP_ID), UiKit.ACCENT)
	v.add_child(_museum)
	_update_museum_label()

	v.add_child(UiKit.stripes(10))
	v.add_child(UiKit.label("Got a code from a friend?", 19))
	_code = TextEdit.new()
	_code.text = code_text
	_code.placeholder_text = "Paste a WM1-… code here"
	_code.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_code.custom_minimum_size = Vector2(0, 60)
	v.add_child(_code)
	var load_row := UiKit.hbox(8)
	var paste := UiKit.button("Paste", _on_paste, UiKit.MUTED)
	load_row.add_child(paste)
	var search := UiKit.button("Search for them!", _on_search_code)
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_row.add_child(search)
	v.add_child(load_row)
	if WebTap.available():
		# The browser reads the system clipboard inside the tap itself.
		var tap := WebTap.new(paste, "paste")
		tap.replied.connect(_on_web_paste)
		v.add_child(tap)

	var misc_row := UiKit.hbox(8)
	var saved := ChallengeCodec.list_saved()
	var latest := UiKit.button("Load latest saved (%d)" % saved.size(), _on_load_latest, UiKit.MUTED)
	latest.disabled = saved.is_empty()
	latest.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	misc_row.add_child(latest)
	if OS.is_debug_build():
		misc_row.add_child(UiKit.button("Debug map", func() -> void:
			AppState.map_id = AppState.TOWN_MAP_ID
			AppState.start_debug(_seed()), UiKit.MUTED))
	v.add_child(misc_row)
	_message = UiKit.label(message, 16, UiKit.BAD)
	v.add_child(_message)

	_content = UiKit.scroll_center(UiKit.panel(v))
	add_child(_content)


func _seed() -> int:
	return clampi(int(_seed_text.text.strip_edges()), 0, ChallengeCodec.MAX_SEED)


func _update_museum_label() -> void:
	_museum.text = "Hide the %s in the museum" % AssetCatalog.label(TownGenerator.critter_for_seed(_seed()))


func _on_random_seed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_seed_text.text = str(rng.randi_range(0, 999999))
	_update_museum_label()


func _on_paste() -> void:
	# On the web, WebTap already asked the browser (see _on_web_paste).
	if not WebTap.available():
		_code.text = DisplayServer.clipboard_get()


func _on_web_paste(reply: Dictionary) -> void:
	if reply.get("ok", false):
		_code.text = String(reply.get("text", ""))
		_message.text = ""
	elif reply.get("error") != "cancelled":
		_message.text = "Couldn't read the clipboard. Long-press the box above and choose Paste."


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
