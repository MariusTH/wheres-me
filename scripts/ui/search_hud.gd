class_name SearchHud
extends Control
## Search-mode UI: intro card, who to find, running clock, taps, toasts,
## result and error dialogs.

signal give_up_pressed
signal menu_pressed

## The clock turns orange, then red, and pulses each second past these marks.
const WARN_AFTER_S := 60.0
const ALARM_AFTER_S := 120.0

var _challenge: ChallengeData
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


func _ready() -> void:
	theme = UiKit.theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func setup(challenge: ChallengeData) -> void:
	_challenge = challenge
	var title := challenge.seeker_title()
	# Container layout: top bar (who + stats), free space, bottom column
	# (toast / result card), hint line.
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var column := _ignore(UiKit.vbox(8))
	margin.add_child(column)

	var top := _ignore(UiKit.hbox(8))
	column.add_child(top)
	var who := UiKit.hbox(12)
	var portrait := AvatarPortrait.new()
	portrait.show_subject(challenge.subject())
	portrait.disabled = true
	portrait.custom_minimum_size = Vector2(84, 96)
	who.add_child(portrait)
	var text := UiKit.vbox(2)
	text.add_child(UiKit.label(title, 24, UiKit.INK, false))
	text.add_child(UiKit.label(_hint_line(), 16, UiKit.MUTED, false))
	who.add_child(text)
	var left := UiKit.panel(who)
	left.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(left)
	var spacer := _ignore(Control.new())
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var stats := UiKit.vbox(6)
	_taps = UiKit.label("Taps 0  ·  Wrong 0", 16, UiKit.MUTED, false)
	stats.add_child(_taps)
	var buttons := UiKit.hbox(8)
	_give_up = UiKit.button("Give up", func() -> void: give_up_pressed.emit(), UiKit.MUTED)
	buttons.add_child(_give_up)
	buttons.add_child(UiKit.button("Menu", func() -> void: menu_pressed.emit(), UiKit.MUTED))
	stats.add_child(buttons)
	var right := UiKit.panel(stats)
	right.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(right)

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

	var hint := UiKit.label(("Tap a critter to guess" if challenge.is_critter() else "Tap a person to guess") + "  ·  Drag to pan  ·  Scroll or pinch to zoom  ·  F1 debug", 13, Color.WHITE, false)
	hint.add_theme_color_override("font_outline_color", UiKit.INK)
	hint.add_theme_constant_override("outline_size", 4)
	column.add_child(hint)

	# Running clock, top centre, independent of the side cards' widths.
	var clock_row := _ignore(CenterContainer.new())
	clock_row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	clock_row.offset_top = 12
	add_child(clock_row)
	var clock_box := UiKit.hbox(6)
	clock_box.add_child(UiKit.icon("ui_stopwatch", 52))
	_time = UiKit.title("0:00", 44, UiKit.INK)
	_time.add_theme_constant_override("outline_size", 0)
	_time.custom_minimum_size = Vector2(120, 0)
	clock_box.add_child(_time)
	_clock = UiKit.panel(clock_box)
	_clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clock_row.add_child(_clock)


func _ignore(c: Control) -> Control:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Big "find this person" card over a near-opaque backdrop, so nobody gets a
## head start scanning the map. [param on_start] starts the clock.
func show_intro(on_start: Callable) -> void:
	var v := UiKit.vbox(14)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.custom_minimum_size = Vector2(420, 0)
	var heading := UiKit.banner(_challenge.seeker_title(), 460, 30)
	heading.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(heading)
	var portrait := AvatarPortrait.new()
	portrait.show_subject(_challenge.subject())
	portrait.disabled = true
	portrait.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	var glass := UiKit.magnified(portrait, 300)
	glass.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(glass)
	var info := UiKit.label(_intro_line(), 18, UiKit.MUTED)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(info)
	var row := UiKit.hbox()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var start := UiKit.button("Start", on_start, UiKit.GOOD)
	start.custom_minimum_size = Vector2(200, 64)
	start.add_theme_font_size_override("font_size", 26)
	row.add_child(start)
	row.add_child(UiKit.button("Menu", func() -> void: menu_pressed.emit(), UiKit.MUTED))
	v.add_child(row)
	_intro = UiKit.modal(v)
	(_intro as ColorRect).color = Color(0.1, 0.08, 0.14, 0.94)
	add_child(_intro)
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
	if _intro:
		_intro.queue_free()
		_intro = null


func set_stats(elapsed: float, taps: int, wrong: int) -> void:
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
	_give_up.disabled = true
	var v := UiKit.vbox(12)
	v.custom_minimum_size = Vector2(440, 0)
	var headline := UiKit.title("Found!" if found else "Not found this time", 40, UiKit.GOOD if found else UiKit.ACCENT)
	v.add_child(headline)
	v.add_child(UiKit.label("Time %s  ·  %d taps  ·  %d wrong" % [UiKit.format_time(elapsed), taps, wrong], 18))
	if not found:
		v.add_child(UiKit.label("Their hiding spot is marked on the map.", 16, UiKit.MUTED))
	var row := UiKit.hbox()
	row.add_child(UiKit.button("Retry", on_retry))
	row.add_child(UiKit.button("Swap roles: you hide", on_swap, UiKit.GOOD))
	row.add_child(UiKit.button("Menu", on_menu, UiKit.MUTED))
	v.add_child(row)
	# Result card sits at the bottom so the revealed target stays visible.
	var card := UiKit.panel(v)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_bottom.add_child(card)


func show_error(message: String, on_menu: Callable) -> void:
	var v := UiKit.vbox(12)
	v.custom_minimum_size = Vector2(480, 0)
	v.add_child(UiKit.label("Can't play this challenge", 28, UiKit.BAD))
	v.add_child(UiKit.label(message, 18))
	v.add_child(UiKit.button("Back to menu", on_menu))
	add_child(UiKit.modal(v))
