class_name SearchHud
extends Control
## Search-mode UI: intro card, who to find, running clock, taps, toasts,
## result and error dialogs. Desktop: who-card left, clock centre, stats
## right. Phone portrait: the clock gets its own top row with a small portrait
## and the buttons below it. Rebuilds when the screen's size class changes.

signal give_up_pressed
signal menu_pressed

## The clock turns orange, then red, and pulses each second past these marks.
const WARN_AFTER_S := 60.0
const ALARM_AFTER_S := 120.0

var _challenge: ChallengeData
var _root: Control
var _intro: Control
var _clock: PanelContainer
var _time: Label
var _last_second := -1
var _taps: Label
var _toast: PanelContainer
var _toast_label: Label
var _toast_tween: Tween
var _give_up: Button
var _bottom: VBoxContainer

## Kept so a rebuild (phone rotated) restores what was on screen.
var _stats := [0.0, 0, 0]
var _on_start: Callable
var _result_args: Array = []
var _error_args: Array = []


func _ready() -> void:
	theme = UiKit.theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	AppState.layout_changed.connect(_rebuild)


func setup(challenge: ChallengeData) -> void:
	_challenge = challenge
	_rebuild()


func _rebuild() -> void:
	if _challenge == null:
		return
	if _root:
		_root.queue_free()
	_intro = null
	var narrow := AppState.is_narrow()
	_root = _ignore(Control.new())
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8 if narrow else 12)
	_root.add_child(margin)
	var column := _ignore(UiKit.vbox(8))
	margin.add_child(column)

	var clock_box := UiKit.hbox(6)
	clock_box.add_child(UiKit.icon("ui_stopwatch", 40 if narrow else 52))
	_time = UiKit.title("0:00", 36 if narrow else 44, UiKit.INK)
	_time.add_theme_constant_override("outline_size", 0)
	_time.custom_minimum_size = Vector2(100 if narrow else 120, 0)
	clock_box.add_child(_time)
	_clock = UiKit.panel(clock_box)
	_clock.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var portrait := AvatarPortrait.new()
	portrait.show_subject(_challenge.subject())
	portrait.disabled = true
	_taps = UiKit.label("", 15 if narrow else 16, UiKit.MUTED, false)
	_give_up = UiKit.button("Give up", func() -> void: give_up_pressed.emit(), UiKit.MUTED)
	_give_up.disabled = not _result_args.is_empty()
	var menu := UiKit.button("Menu", func() -> void: menu_pressed.emit(), UiKit.MUTED)

	if narrow:
		var clock_row := _ignore(CenterContainer.new())
		clock_row.add_child(_clock)
		column.add_child(clock_row)
		var top := _ignore(UiKit.hbox(8))
		portrait.custom_minimum_size = Vector2(60, 72)
		var who := UiKit.panel(portrait)
		who.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		top.add_child(who)
		var spacer := _ignore(Control.new())
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(spacer)
		var stats := UiKit.vbox(6)
		var buttons := UiKit.hbox(8)
		buttons.add_child(_give_up)
		buttons.add_child(menu)
		stats.add_child(buttons)
		_taps.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		stats.add_child(_taps)
		var right := UiKit.panel(stats)
		right.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		top.add_child(right)
		column.add_child(top)
	else:
		var top := _ignore(UiKit.hbox(8))
		column.add_child(top)
		var who := UiKit.hbox(12)
		portrait.custom_minimum_size = Vector2(84, 96)
		who.add_child(portrait)
		var text := UiKit.vbox(2)
		text.add_child(UiKit.label(_challenge.seeker_title(), 24, UiKit.INK, false))
		var hint_line := UiKit.label(_hint_line(), 16, UiKit.MUTED)
		hint_line.custom_minimum_size = Vector2(230, 0)
		text.add_child(hint_line)
		who.add_child(text)
		var left := UiKit.panel(who)
		left.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		top.add_child(left)
		var spacer := _ignore(Control.new())
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(spacer)
		var stats := UiKit.vbox(6)
		stats.add_child(_taps)
		var buttons := UiKit.hbox(8)
		buttons.add_child(_give_up)
		buttons.add_child(menu)
		stats.add_child(buttons)
		var right := UiKit.panel(stats)
		right.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		top.add_child(right)
		# Running clock, top centre, independent of the side cards' widths.
		var clock_row := _ignore(CenterContainer.new())
		clock_row.set_anchors_preset(Control.PRESET_TOP_WIDE)
		clock_row.offset_top = 12
		clock_row.add_child(_clock)
		_root.add_child(clock_row)

	var fill := _ignore(Control.new())
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(fill)
	_bottom = _ignore(UiKit.vbox(8))
	_bottom.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(_bottom)
	_toast_label = UiKit.label("", 20, UiKit.INK, false)
	_toast = UiKit.panel(_toast_label)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_toast.modulate.a = 0.0
	_bottom.add_child(_toast)

	var what := "Tap a critter to guess" if _challenge.is_critter() else "Tap a person to guess"
	var hint := UiKit.label(what + ("  ·  Pinch to zoom" if narrow else "  ·  Drag to pan  ·  Scroll or pinch to zoom"), 13, Color.WHITE, false)
	hint.add_theme_color_override("font_outline_color", UiKit.INK)
	hint.add_theme_constant_override("outline_size", 4)
	column.add_child(hint)

	set_stats(_stats[0], _stats[1], _stats[2])
	if _on_start.is_valid():
		show_intro(_on_start)
	if not _result_args.is_empty():
		_show_result_card()
	if not _error_args.is_empty():
		_show_error_dialog()


func _ignore(c: Control) -> Control:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Big "find this person" card over a near-opaque backdrop, so nobody gets a
## head start scanning the map. [param on_start] starts the clock. On short
## screens (phone in landscape) the magnifier sits beside the text.
func show_intro(on_start: Callable) -> void:
	_on_start = on_start
	if _intro:
		_intro.queue_free()
	var short := AppState.is_short()
	var width := UiKit.fit_width(460.0)
	var portrait := AvatarPortrait.new()
	portrait.show_subject(_challenge.subject())
	portrait.disabled = true
	portrait.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	var glass := UiKit.magnified(portrait, 230 if short else minf(300.0, width * 0.7))
	glass.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	glass.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var heading := UiKit.banner(_challenge.seeker_title(), minf(width, 380.0) if short else width, 28 if short else 30)
	heading.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var info := UiKit.label(_intro_line(), 16 if short else 18, UiKit.MUTED)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var row := UiKit.hbox()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var start := UiKit.button("Start", func() -> void: _on_start.call(), UiKit.GOOD)
	start.custom_minimum_size = Vector2(180, 64)
	start.add_theme_font_size_override("font_size", 26)
	row.add_child(start)
	row.add_child(UiKit.button("Menu", func() -> void: menu_pressed.emit(), UiKit.MUTED))

	var content: Control
	if short:
		var text := UiKit.vbox(10)
		text.custom_minimum_size = Vector2(minf(380.0, UiKit.viewport_size().x - 300.0), 0)
		text.alignment = BoxContainer.ALIGNMENT_CENTER
		text.add_child(heading)
		text.add_child(info)
		text.add_child(row)
		var side := UiKit.hbox(16)
		side.add_child(glass)
		side.add_child(text)
		content = side
	else:
		var v := UiKit.vbox(12)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.custom_minimum_size = Vector2(width, 0)
		v.add_child(heading)
		v.add_child(glass)
		v.add_child(info)
		v.add_child(row)
		content = v
	_intro = UiKit.modal(content)
	(_intro as ColorRect).color = Color(0.1, 0.08, 0.14, 0.94)
	_root.add_child(_intro)
	start.grab_focus.call_deferred()


func _hint_line() -> String:
	if _challenge.is_critter():
		return "Only this one has these colours."
	return "They look like this and are hiding somewhere in town."


func _intro_line() -> String:
	if _challenge.is_critter():
		var by := " %s hid it" % _challenge.hider_name if _challenge.hider_name != "" else " It's hiding"
		return "%s somewhere in the museum. Lots of look-alikes, but only this one has these colours. The clock starts when you press Start." % by.strip_edges()
	return "Remember this look. They're hiding somewhere in the crowd. The clock starts when you press Start."


func hide_intro() -> void:
	_on_start = Callable()
	if _intro:
		_intro.queue_free()
		_intro = null


func set_stats(elapsed: float, taps: int, wrong: int) -> void:
	_stats = [elapsed, taps, wrong]
	_time.text = UiKit.format_time(elapsed)
	var color := UiKit.BAD if elapsed >= ALARM_AFTER_S else (UiKit.ACCENT if elapsed >= WARN_AFTER_S else UiKit.INK)
	_time.add_theme_color_override("font_color", color)
	var second := int(elapsed)
	if second != _last_second:
		_last_second = second
		if elapsed >= WARN_AFTER_S:
			_clock.pivot_offset = _clock.size / 2.0
			_clock.scale = Vector2.ONE * 1.12
			create_tween().tween_property(_clock, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_SINE)
	_taps.text = "Taps %d  ·  Wrong %d" % [taps, wrong]


func toast(text: String, color: Color = UiKit.INK) -> void:
	_toast_label.text = text
	_toast_label.add_theme_color_override("font_color", color)
	if _toast_tween:
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.2)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.4)


func show_result(found: bool, elapsed: float, taps: int, wrong: int, on_retry: Callable, on_swap: Callable, on_menu: Callable) -> void:
	_result_args = [found, elapsed, taps, wrong, on_retry, on_swap, on_menu]
	_give_up.disabled = true
	_show_result_card()


func _show_result_card() -> void:
	var found: bool = _result_args[0]
	var v := UiKit.vbox(10)
	v.custom_minimum_size = Vector2(UiKit.fit_width(440.0), 0)
	v.add_child(UiKit.title("Found!" if found else "Not found this time", 34 if AppState.is_narrow() else 40, UiKit.GOOD if found else UiKit.ACCENT))
	var line := UiKit.label("Time %s  ·  %d taps  ·  %d wrong" % [UiKit.format_time(_result_args[1]), _result_args[2], _result_args[3]], 18)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(line)
	if not found:
		v.add_child(UiKit.label("The hiding spot is marked on the map.", 16, UiKit.MUTED))
	v.add_child(UiKit.button_row([
		UiKit.button("Retry", _result_args[4]),
		UiKit.button("Swap roles: you hide", _result_args[5], UiKit.GOOD),
		UiKit.button("Menu", _result_args[6], UiKit.MUTED),
	]))
	# Result card sits at the bottom so the revealed target stays visible.
	var card := UiKit.panel(v)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_bottom.add_child(card)


func show_error(message: String, on_menu: Callable) -> void:
	_error_args = [message, on_menu]
	_show_error_dialog()


func _show_error_dialog() -> void:
	var v := UiKit.vbox(12)
	v.custom_minimum_size = Vector2(UiKit.fit_width(480.0), 0)
	v.add_child(UiKit.label("Can't play this challenge", 28, UiKit.BAD))
	v.add_child(UiKit.label(_error_args[0], 18))
	v.add_child(UiKit.button("Back to menu", _error_args[1]))
	_root.add_child(UiKit.modal(v))
