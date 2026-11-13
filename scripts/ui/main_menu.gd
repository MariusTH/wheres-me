extends Control
## Home menu: hide yourself in a town (the number picks the town), or paste a
## friend's code and search. Sits on a painting of the real town. Lays itself
## out for desktop, phone portrait (narrow) and phone landscape (short), and
## rebuilds when the size class changes.

var _seed_text: LineEdit
var _code: TextEdit
var _message: Label
var _content: Control


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.backdrop())
	_build(str(AppState.map_seed), "", AppState.menu_message)
	AppState.menu_message = ""
	AppState.layout_changed.connect(func() -> void: _build(_seed_text.text, _code.text, _message.text))


func _build(seed_text: String, code_text: String, message: String) -> void:
	if _content:
		_content.queue_free()
	var narrow := AppState.is_narrow()
	var width := UiKit.fit_width(520.0)

	var v := UiKit.vbox(10)
	v.custom_minimum_size = Vector2(width, 0)

	var head := UiKit.hbox(10)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(UiKit.icon("ui_magnifier", 64 if narrow else 84))
	head.add_child(UiKit.title("Where's Me", 46 if narrow else 58))
	v.add_child(head)
	var sub := UiKit.label("Hide in the crowd. Send the puzzle. See if your friend can find you.", 16, UiKit.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)

	# You: portrait, name and an edit button.
	var me := UiKit.hbox(12)
	var portrait := AvatarPortrait.new()
	portrait.custom_minimum_size = Vector2(64, 74)
	portrait.disabled = true
	if AppState.has_avatar():
		portrait.look = AppState.my_avatar["look"]
	me.add_child(portrait)
	var who := UiKit.vbox(2)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.alignment = BoxContainer.ALIGNMENT_CENTER
	var name_text := String(AppState.my_avatar.get("name", ""))
	who.add_child(UiKit.label(("You're %s" % name_text) if name_text != "" else ("Your avatar" if AppState.has_avatar() else "No avatar yet"), 20, UiKit.INK, false))
	who.add_child(UiKit.label("This is who your friend looks for." if AppState.has_avatar() else "Make one first, it only takes a minute.", 14, UiKit.MUTED))
	me.add_child(who)
	var edit := UiKit.button("Edit" if AppState.has_avatar() else "Create", func() -> void:
		AppState.map_id = AppState.TOWN_MAP_ID
		AppState.start_creator(_seed()), UiKit.MUTED)
	edit.custom_minimum_size = Vector2(96, 48)
	edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	me.add_child(edit)
	v.add_child(me)

	var hide := UiKit.button("Hide in this town", func() -> void: AppState.start_hide(_seed(), AppState.TOWN_MAP_ID), UiKit.GOOD)
	hide.custom_minimum_size = Vector2(0, 62)
	hide.add_theme_font_size_override("font_size", 26)
	v.add_child(hide)
	# The town number: a plain number field, since SpinBox arrows are too
	# small to hit on a phone. Every number is a different town.
	var town_row := UiKit.hbox(8)
	town_row.add_child(UiKit.label("Town no.", 16, UiKit.MUTED, false))
	_seed_text = LineEdit.new()
	_seed_text.text = seed_text
	_seed_text.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_seed_text.custom_minimum_size = Vector2(0, 44)
	_seed_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	town_row.add_child(_seed_text)
	var shuffle := UiKit.button("New town", _on_random_seed, UiKit.MUTED)
	shuffle.custom_minimum_size = Vector2(0, 44)
	shuffle.add_theme_font_size_override("font_size", 18)
	town_row.add_child(shuffle)
	v.add_child(town_row)

	v.add_child(UiKit.divider(12))
	v.add_child(UiKit.label("Got a code from a friend?", 19, UiKit.INK, false))
	_code = TextEdit.new()
	_code.text = code_text
	_code.placeholder_text = "Paste a WM1-… code here"
	_code.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_code.custom_minimum_size = Vector2(0, 56)
	v.add_child(_code)
	var load_row := UiKit.hbox(8)
	var paste := UiKit.button("Paste", _on_paste, UiKit.MUTED)
	load_row.add_child(paste)
	var search := UiKit.button("Find them!", _on_search_code, UiKit.ACCENT)
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_row.add_child(search)
	v.add_child(load_row)
	if WebTap.available():
		# The browser reads the system clipboard inside the tap itself.
		var tap := WebTap.new(paste, "paste")
		tap.replied.connect(_on_web_paste)
		v.add_child(tap)
		# A real browser text box, so long-press → Paste works on phones.
		v.add_child(WebField.new(_code))

	# Small extras: last saved challenge and (debug builds) the map viewer.
	var misc_row := UiKit.hbox(14)
	misc_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var saved := ChallengeCodec.list_saved()
	if not saved.is_empty():
		misc_row.add_child(_link("Open last saved (%d)" % saved.size(), _on_load_latest))
	if OS.is_debug_build():
		misc_row.add_child(_link("Debug map", func() -> void:
			AppState.map_id = AppState.TOWN_MAP_ID
			AppState.start_debug(_seed())))
	if misc_row.get_child_count() > 0:
		v.add_child(misc_row)
	_message = UiKit.label("", 16, UiKit.BAD)
	v.add_child(_message)
	_say(message)

	_content = UiKit.scroll_center(UiKit.panel(v))
	add_child(_content)


## Quiet text button for the less important actions.
func _link(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.custom_minimum_size = Vector2(0, 40)
	b.add_theme_font_override("font", get_theme_default_font())
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_constant_override("outline_size", 0)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, UiKit.MUTED if state == "font_color" else UiKit.INK)
	for box in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(box, StyleBoxEmpty.new())
	b.pressed.connect(on_pressed)
	return b


## Shows [param text] under the panel (hidden when empty, so it takes no room).
func _say(text: String) -> void:
	_message.text = text
	_message.visible = text != ""


func _seed() -> int:
	return clampi(int(_seed_text.text.strip_edges()), 0, ChallengeCodec.MAX_SEED)


func _on_random_seed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_seed_text.text = str(rng.randi_range(0, 999999))


func _on_paste() -> void:
	# On the web, WebTap already asked the browser (see _on_web_paste).
	if not WebTap.available():
		_code.text = DisplayServer.clipboard_get()


func _on_web_paste(reply: Dictionary) -> void:
	if reply.get("ok", false):
		_code.text = String(reply.get("text", ""))
		_say("")
	elif reply.get("error") != "cancelled":
		_say("Couldn't read the clipboard. Long-press the box above and choose Paste.")


func _on_search_code() -> void:
	_start_from(ChallengeCodec.decode(_code.text))


func _on_load_latest() -> void:
	var saved := ChallengeCodec.list_saved()
	if saved.is_empty():
		_say("No saved challenges yet.")
		return
	_start_from(ChallengeCodec.load_from_file(saved[0]))


func _start_from(result: Dictionary) -> void:
	if result["challenge"] == null:
		_say(result["error"])
		return
	AppState.start_search(result["challenge"])
