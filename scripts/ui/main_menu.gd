extends Control
## Home menu: your avatar, then the three ways to play:
##   Play with friends  →  the Friends screen (games, invites, codes)
##   Daily challenge    →  today's town, same for everyone, best score + streak
##   Play               →  pick a difficulty, the computer hides
## Sits on a painting of the real town. Lays itself out for desktop, phone
## portrait (narrow) and phone landscape (short), and rebuilds when the size
## class changes.

var _message: Label
var _content: Control
## "" = home, "play" = difficulty picker.
var _page := ""
## Buttons with someone hiding behind them (see PeekButton).
var _peekers: Array[PeekButton] = []
var _sneak_timer: Timer


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.backdrop())
	_page = AppState.menu_page
	AppState.menu_page = ""
	_build(AppState.menu_message)
	AppState.menu_message = ""
	AppState.layout_changed.connect(func() -> void: _build(_message.text))
	# Every few seconds someone sneaks a look over a button's edge.
	_sneak_timer = Timer.new()
	_sneak_timer.one_shot = true
	_sneak_timer.timeout.connect(_on_sneak)
	add_child(_sneak_timer)
	_sneak_timer.start(1.2)


func _on_sneak() -> void:
	var idle := _peekers.filter(func(p: PeekButton) -> bool: return is_instance_valid(p) and not p.is_up())
	if not idle.is_empty():
		(idle.pick_random() as PeekButton).sneak()
	_sneak_timer.start(randf_range(2.2, 4.5))


func _build(message: String) -> void:
	if _content:
		_content.queue_free()
	_peekers.clear()
	var v := UiKit.vbox(6 if _page == "" else 10)
	v.custom_minimum_size = Vector2(UiKit.fit_width(520.0), 0)
	if _page == "play":
		_build_play(v)
	else:
		_build_home(v)
	_message = UiKit.label("", 16, UiKit.BAD)
	v.add_child(_message)
	_say(message)
	_content = UiKit.scroll_center(UiKit.panel(v))
	add_child(_content)


func _go_page(page: String) -> void:
	_page = page
	_build("")


func _build_home(v: VBoxContainer) -> void:
	var narrow := AppState.is_narrow()
	var head := UiKit.hbox(10)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(_swaying(UiKit.icon("ui_magnifier", 64 if narrow else 84)))
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
	who.add_child(UiKit.label("This is who your friends look for." if AppState.has_avatar() else "Make one first, it only takes a minute.", 14, UiKit.MUTED))
	me.add_child(who)
	var edit := UiKit.button("Edit" if AppState.has_avatar() else "Create", func() -> void:
		AppState.map_id = AppState.TOWN_MAP_ID
		AppState.start_creator(AppState.map_seed), UiKit.MUTED)
	edit.custom_minimum_size = Vector2(96, 48)
	edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	me.add_child(edit)
	v.add_child(me)
	v.add_child(UiKit.divider(8))

	# Play with friends: the heart of the game.
	var waiting := FriendsStore.your_turn_count()
	var friends_note := ("%d game%s waiting for you" % [waiting, "" if waiting == 1 else "s"]) if waiting > 0 \
		else "Hide, send a code, find each other in turns."
	# You're the one hiding behind this one.
	var you: Dictionary = AppState.my_avatar.get("look", {}) if AppState.has_avatar() else {}
	v.add_child(_mode_button("Play with friends", friends_note, func() -> void: AppState.go_friends(), UiKit.ACCENT, waiting > 0, you))

	# Daily challenge: same town for everyone today.
	var date := Progress.today()
	var done := Progress.daily_result(date)
	var diff := Difficulty.get_level(Progress.daily_difficulty(date))
	var best := Progress.best_daily_score()
	var streak := Progress.daily_streak()
	var daily_note := "#%d · %s" % [Progress.daily_number(date), diff["name"]]
	if not done.is_empty():
		daily_note += " · Done today: %d points" % int(done.get("score", 0))
	if best > 0:
		daily_note += " · Best %d" % best
	if streak > 0:
		daily_note += " · Streak %d" % streak
	v.add_child(_mode_button("Daily challenge", daily_note, func() -> void: AppState.start_daily(), UiKit.GOOD))

	v.add_child(_mode_button("Play", "Pick a difficulty. The computer hides someone.", func() -> void: _go_page("play"), Color("5f7fb5")))

	# Small extras: last saved challenge and (debug builds) the map viewer.
	var misc_row := UiKit.hbox(14)
	misc_row.alignment = BoxContainer.ALIGNMENT_CENTER
	misc_row.add_child(_link("Hide (classic)", func() -> void: AppState.start_hide(AppState.random_seed(), AppState.TOWN_MAP_ID)))
	var saved := ChallengeCodec.list_saved()
	if not saved.is_empty():
		misc_row.add_child(_link("Open last saved", _on_load_latest))
	if OS.is_debug_build():
		misc_row.add_child(_link("Debug map", func() -> void:
			AppState.map_id = AppState.TOWN_MAP_ID
			AppState.map_size = ""
			AppState.start_debug(AppState.map_seed)))
	v.add_child(misc_row)


## A big mode button with a note under it.
func _mode_button(text: String, note: String, on_pressed: Callable, color: Color, highlight: bool = false, look: Dictionary = {}) -> Control:
	var box := UiKit.vbox(2)
	var b := UiKit.button(text, on_pressed, color)
	b.custom_minimum_size = Vector2(0, 60)
	b.add_theme_font_size_override("font_size", 26)
	box.add_child(_peek(b, 1.0, look))
	var l := UiKit.label(note, 15, UiKit.ACCENT if highlight else UiKit.MUTED)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
	return box


func _build_play(v: VBoxContainer) -> void:
	var title := UiKit.banner("Play", minf(360.0, UiKit.fit_width(360.0)), 32)
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(title)
	v.add_child(UiKit.label("The computer hides someone in a new town. Harder means a bigger town, more of them hidden, and look-alikes in the crowd.", 16, UiKit.MUTED))
	var colors := [UiKit.GOOD, Color("5f7fb5"), UiKit.ACCENT, UiKit.BAD]
	for i in Difficulty.LEVELS.size():
		var l: Dictionary = Difficulty.LEVELS[i]
		var id := String(l["id"])
		var row := UiKit.hbox(10)
		var b := UiKit.button(String(l["name"]), func() -> void: AppState.start_play(id), colors[i % colors.size()])
		b.custom_minimum_size = Vector2(130, 56)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		# How far they peek hints how much of the hider shows on this level.
		row.add_child(_peek(b, clampf(float(l["min_visible"]) * 1.15, 0.35, 1.0)))
		var text := UiKit.vbox(0)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_child(UiKit.label(String(l["blurb"]), 15, UiKit.INK))
		var st := Progress.play_stats(id)
		var rec := "Not played yet"
		if int(st["played"]) > 0:
			rec = "Best %d · found %d of %d" % [st["best_score"], st["found"], st["played"]]
			if float(st["best_time"]) > 0.0:
				rec += " · fastest %s" % UiKit.format_time(st["best_time"])
		text.add_child(UiKit.label(rec, 13, UiKit.MUTED))
		row.add_child(text)
		v.add_child(row)
	v.add_child(_help_toggle())
	v.add_child(UiKit.button("Back", func() -> void: _go_page(""), UiKit.MUTED))


## "Help when stuck" (SearchHelp): after 5 minutes the crowd thins and the
## hider steps out of hiding a bit. Applies to every search.
func _help_toggle() -> Control:
	var row := UiKit.hbox(10)
	var b := UiKit.button("", func() -> void: pass, UiKit.MUTED)
	b.custom_minimum_size = Vector2(130, 48)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var paint := func() -> void:
		var on := SearchHelp.enabled()
		b.text = "Help: On" if on else "Help: Off"
		for state in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(state, UiKit._button_box(UiKit.GOOD if on else UiKit.MUTED, state == "pressed"))
	b.pressed.connect(func() -> void:
		SearchHelp.set_enabled(not SearchHelp.enabled())
		paint.call())
	paint.call()
	row.add_child(b)
	var note := UiKit.label("Stuck for %d minutes? Some of the crowd goes home and the hider steps out a bit." % roundi(float(SearchHelp.STAGES[0]["after"]) / 60.0), 14, UiKit.MUTED)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(note)
	return row


func _peek(b: Button, reveal: float, look: Dictionary = {}) -> PeekButton:
	var p := PeekButton.wrap(b, reveal, look)
	_peekers.append(p)
	return p


## Gently rocks [param c] back and forth, like a magnifier being waved about.
func _swaying(c: Control) -> Control:
	c.resized.connect(func() -> void: c.pivot_offset = c.size / 2.0)
	c.ready.connect(func() -> void:
		var t := c.create_tween().set_loops()
		t.tween_property(c, "rotation", 0.09, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		t.tween_property(c, "rotation", -0.09, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT))
	return c


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


func _on_load_latest() -> void:
	var saved := ChallengeCodec.list_saved()
	if saved.is_empty():
		_say("No saved challenges yet.")
		return
	var result := ChallengeCodec.load_from_file(saved[0])
	if result["challenge"] == null:
		_say(result["error"])
		return
	AppState.start_search(result["challenge"])
