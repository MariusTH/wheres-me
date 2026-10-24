extends Control
## Avatar creator: build your look from the part kit (data/assets/avatar_kit.json),
## name yourself, then go hide. The UI is generated from the kit, so new parts
## or colours only need a JSON change. Saved to user://my_avatar.json.

const SWATCH_SIZE := Vector2(44, 44)

var _look: Dictionary = {}
var _preview: AvatarPortrait
var _name_edit: LineEdit
var _selfie_status: Label
var _content: Control
## field -> {"row": Control, "buttons": Array[Button], "values": Array}
var _rows: Dictionary = {}


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UiKit.ACCENT
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	if AppState.has_avatar():
		_look = AvatarKit.normalize(AppState.my_avatar["look"])
	else:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		_look = AvatarKit.normalize(AvatarKit.presets()[rng.randi_range(0, AvatarKit.presets().size() - 1)]["look"])
	_build(String(AppState.my_avatar.get("name", "")))
	AppState.layout_changed.connect(func() -> void: _build(_name_edit.text))


## Desktop / landscape: preview column + parts list side by side. Phone
## portrait (narrow): compact header with a small preview, the parts list
## filling the middle, and Back / Hide me! pinned at the bottom.
func _build(name_text: String) -> void:
	if _content:
		_content.queue_free()
	_rows.clear()
	var narrow := AppState.is_narrow()
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8 if narrow else 12)
	add_child(margin)
	_content = margin
	var columns := BoxContainer.new()
	columns.vertical = narrow
	columns.add_theme_constant_override("separation", 8 if narrow else 12)
	margin.add_child(columns)

	_preview = AvatarPortrait.new()
	_preview.disabled = true
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Your name (the seeker sees it)"
	_name_edit.max_length = AvatarKit.MAX_NAME_LENGTH
	_name_edit.custom_minimum_size = Vector2(0, 48)
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text = name_text
	var random_button := UiKit.button("Randomize", _randomize, UiKit.MUTED)
	random_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var actions := UiKit.hbox(8)
	actions.add_child(UiKit.button("Back", func() -> void: AppState.go_menu(), UiKit.MUTED))
	var go := UiKit.button("Hide me!", _done, UiKit.GOOD)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(go)
	_selfie_status = UiKit.label("", 15, UiKit.MUTED)
	_selfie_status.visible = false

	var left := UiKit.vbox(8)
	if narrow:
		var header := UiKit.hbox(10)
		_preview.custom_minimum_size = Vector2(96, 120)
		header.add_child(_preview)
		var side := UiKit.vbox(8)
		side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		side.add_child(_name_edit)
		var tools := UiKit.hbox(8)
		tools.add_child(random_button)
		if SelfieBridge.available():
			tools.add_child(_selfie_button("Selfie"))
		side.add_child(tools)
		header.add_child(side)
		left.add_child(header)
		left.add_child(_selfie_status)
	else:
		left.custom_minimum_size = Vector2(240 if AppState.is_short() else 300, 0)
		left.add_child(UiKit.title("Your avatar", 30, UiKit.ACCENT))
		_preview.custom_minimum_size = Vector2(0, 110)
		_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
		left.add_child(_preview)
		left.add_child(_name_edit)
		left.add_child(random_button)
		if SelfieBridge.available():
			left.add_child(_selfie_button("Look like me (selfie)"))
		left.add_child(_selfie_status)
		left.add_child(actions)
	columns.add_child(UiKit.panel(left))

	# Presets + one row per kit field, scrollable.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = 12
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var parts := UiKit.vbox(10)
	parts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(parts)
	var right_panel := UiKit.panel(scroll)
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(right_panel)
	if narrow:
		columns.add_child(UiKit.panel(actions))

	parts.add_child(UiKit.label("Start from", 18, UiKit.MUTED, false))
	var presets := HFlowContainer.new()
	presets.add_theme_constant_override("h_separation", 6)
	presets.add_theme_constant_override("v_separation", 6)
	for preset: Dictionary in AvatarKit.presets():
		var p := AvatarPortrait.new()
		p.look = preset["look"]
		p.custom_minimum_size = Vector2(56, 70)
		p.tooltip_text = String(preset["name"])
		p.pressed.connect(func() -> void:
			_look = AvatarKit.normalize(preset["look"])
			_refresh())
		presets.add_child(p)
	parts.add_child(presets)
	for field: String in AvatarKit.field_order():
		parts.add_child(_make_row(field))
	_refresh()


func _make_row(field: String) -> Control:
	var spec := AvatarKit.field(field)
	var row := UiKit.vbox(4)
	row.add_child(UiKit.label(String(spec["label"]), 18, UiKit.INK, false))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	var buttons: Array[Button] = []
	var vals := AvatarKit.values(field)
	var labels: Array = spec.get("value_labels", [])
	for i in vals.size():
		var value: Variant = vals[i]
		var b: Button
		if AvatarKit.is_color_field(field):
			b = Button.new()
			b.custom_minimum_size = SWATCH_SIZE
			b.tooltip_text = String(value)
		else:
			b = Button.new()
			b.text = String(labels[i]) if i < labels.size() else str(value)
			b.custom_minimum_size = Vector2(0, 44)
		b.pressed.connect(func() -> void:
			_look[field] = value
			_refresh())
		flow.add_child(b)
		buttons.append(b)
	row.add_child(flow)
	_rows[field] = {"row": row, "buttons": buttons, "values": vals}
	return row


## Re-applies the selection highlight, hides irrelevant rows, redraws preview.
func _refresh() -> void:
	_preview.look = _look
	for field: String in _rows:
		var r: Dictionary = _rows[field]
		(r["row"] as Control).visible = AvatarKit.is_relevant(field, _look)
		var vals: Array = r["values"]
		var buttons: Array = r["buttons"]
		for i in buttons.size():
			var selected: bool = vals[i] == _look[field]
			var b: Button = buttons[i]
			if AvatarKit.is_color_field(field):
				var c := Color.html(String(vals[i]))
				var border := UiKit.ACCENT if selected else UiKit.INK
				for state in ["normal", "hover", "pressed", "focus"]:
					b.add_theme_stylebox_override(state, UiKit._flat(c, 22, border, 5 if selected else 2))
			else:
				var c := UiKit.ACCENT if selected else Color("8a8290")
				for state in ["normal", "hover", "pressed"]:
					b.add_theme_stylebox_override(state, UiKit._flat(c if state != "hover" else c.lightened(0.1), 12, UiKit.INK))


## "Look like me": on-device face analysis in the browser fills in skin, hair,
## top, glasses and hat; the player tweaks the rest. The photo never leaves
## the device and only the resulting look goes into the share code.
func _selfie_button(text: String) -> Button:
	# The browser opens the photo picker itself (WebTap "photo", see
	# web/selfie.js), so this button has no pressed handler of its own.
	var button := UiKit.button(text, func() -> void: pass, UiKit.ACCENT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bridge := SelfieBridge.new(button)
	button.add_child(bridge)
	bridge.analyzing.connect(func() -> void: _set_selfie_status("Looking at your photo…"))
	bridge.failed.connect(_set_selfie_status)
	bridge.finished.connect(func(features: Dictionary) -> void:
		_look = PhotoToLook.apply(_look, features)
		_refresh()
		_set_selfie_status("Done! Fix anything that's off below."))
	return button


func _set_selfie_status(text: String) -> void:
	_selfie_status.text = text
	_selfie_status.visible = text != ""


func _randomize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_look = AvatarKit.normalize(AvatarKit.random_look(rng))
	_refresh()


func _done() -> void:
	AppState.save_my_avatar(_name_edit.text, _look)
	AppState.start_hide(AppState.map_seed)
