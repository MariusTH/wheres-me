extends Control
## Play with friends. Pages:
##   list    your games (whose turn, rounds, fastest finds), "Send a game",
##           "Play with random", and the box for a code a friend sent you
##   friend  one game: head-to-head numbers, round history, the next move
##   new     pick a difficulty for an invite or a random opponent
## Codes travel outside the game (chat, messages); see FriendsStore.

var _content: Control
var _message: Label
var _code: TextEdit
var _page := "list"
## Friend shown on the "friend" page.
var _friend_id := ""
## "invite" or "random" on the "new" page.
var _new_kind := "invite"
## Kept across rebuilds (phone rotation).
var _code_text := ""
var _note := ""


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.backdrop())
	_note = AppState.menu_message
	AppState.menu_message = ""
	_build()
	AppState.layout_changed.connect(_build)
	if AppState.pending_code != "":
		# Opened from a deep link: same as pasting the code and tapping Open.
		_code.text = AppState.pending_code
		AppState.pending_code = ""
		_on_open_code.call_deferred()


func _go(page: String, friend_id: String = "", note: String = "") -> void:
	if _code:
		_code_text = _code.text
	_page = page
	_friend_id = friend_id
	_note = note
	_build()


func _build() -> void:
	if _code and is_instance_valid(_code):
		_code_text = _code.text
	if _content:
		_content.queue_free()
	_code = null
	var v := UiKit.vbox(10)
	v.custom_minimum_size = Vector2(UiKit.fit_width(560.0), 0)
	match _page:
		"friend":
			_build_friend(v)
		"new":
			_build_new(v)
		_:
			_build_list(v)
	_message = UiKit.label(_note, 16, UiKit.BAD)
	_message.visible = _note != ""
	v.add_child(_message)
	_content = UiKit.scroll_center(UiKit.panel(v))
	add_child(_content)


func _say(text: String, color: Color = UiKit.BAD) -> void:
	_note = text
	_message.text = text
	_message.add_theme_color_override("font_color", color)
	_message.visible = text != ""


# --- list ------------------------------------------------------------------

func _build_list(v: VBoxContainer) -> void:
	var banner := UiKit.banner("Play with friends", minf(420.0, UiKit.fit_width(420.0)), 30)
	banner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(banner)
	if not AppState.has_avatar():
		v.add_child(UiKit.label("Make your avatar first: it's who your friends look for.", 16, UiKit.ACCENT))

	v.add_child(UiKit.button_row([
		UiKit.button("Send a game", func() -> void:
			_new_kind = "invite"
			_go("new"), UiKit.GOOD),
		UiKit.button("Play with random", func() -> void:
			_new_kind = "random"
			_go("new"), Color("5f7fb5")),
	]))

	# A code from a friend: the way games arrive.
	v.add_child(UiKit.label("Got a code from a friend?", 18, UiKit.INK, false))
	_code = TextEdit.new()
	_code.text = _code_text
	_code.placeholder_text = "Paste a WM1-… code (or their whole message)"
	_code.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_code.custom_minimum_size = Vector2(0, 56)
	v.add_child(_code)
	var load_row := UiKit.hbox(8)
	var paste := UiKit.button("Paste", _on_paste, UiKit.MUTED)
	load_row.add_child(paste)
	var open := UiKit.button("Open code", _on_open_code, UiKit.ACCENT)
	open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_row.add_child(open)
	v.add_child(load_row)
	if WebTap.available():
		var tap := WebTap.new(paste, "paste")
		tap.replied.connect(_on_web_paste)
		v.add_child(tap)
		v.add_child(WebField.new(_code))

	v.add_child(UiKit.divider(10))
	var friends := FriendsStore.list()
	var invites := FriendsStore.open_invites()
	if friends.is_empty() and invites.is_empty():
		v.add_child(UiKit.label("No games yet. Send a game to a friend, or play a random opponent to try it out.", 16, UiKit.MUTED))
	else:
		v.add_child(UiKit.label("Your games", 20, UiKit.INK, false))
	for f: Dictionary in friends:
		v.add_child(_friend_card(f))
	for inv: Dictionary in invites:
		v.add_child(_invite_card(inv))
	v.add_child(UiKit.button("Back to menu", func() -> void: AppState.go_menu(), UiKit.MUTED))


func _portrait(look: Dictionary, size: Vector2) -> AvatarPortrait:
	var p := AvatarPortrait.new()
	p.custom_minimum_size = size
	p.disabled = true
	p.look = look
	return p


## One game: portrait, name, whose turn, a stats line and the next move.
func _friend_card(f: Dictionary) -> Control:
	var id := String(f["id"])
	var st := FriendsStore.stats(f)
	var row := UiKit.hbox(10)
	var portrait := _portrait(f.get("look", {}), Vector2(56, 66))
	portrait.disabled = false
	portrait.pressed.connect(func() -> void: _go("friend", id))
	row.add_child(portrait)
	var text := UiKit.vbox(0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name := String(f.get("name", "Friend")) + ("  (practice)" if f.get("bot", false) else "")
	text.add_child(UiKit.label(name, 19, UiKit.INK, false))
	var turn := String(f.get("turn", ""))
	text.add_child(UiKit.label(FriendsStore.status_line(f), 15, UiKit.ACCENT if turn != FriendsStore.TURN_WAIT else UiKit.MUTED))
	text.add_child(UiKit.label(_stats_line(st), 13, UiKit.MUTED))
	row.add_child(text)
	var action := _next_move_button(f, true)
	action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(action)
	var card := UiKit.panel(row)
	return card


func _stats_line(st: Dictionary) -> String:
	if int(st["rounds"]) == 0:
		return "No rounds yet"
	var parts := PackedStringArray()
	parts.append("%d played" % st["rounds"])
	parts.append("You %d – %d them" % [st["my_wins"], st["their_wins"]])
	if float(st["my_best"]) > 0.0:
		parts.append("your best %s" % UiKit.format_time(st["my_best"]))
	if float(st["their_best"]) > 0.0:
		parts.append("theirs %s" % UiKit.format_time(st["their_best"]))
	return " · ".join(parts)


## Find / Hide / Details, depending on whose turn it is.
func _next_move_button(f: Dictionary, compact: bool) -> Button:
	var id := String(f["id"])
	match String(f.get("turn", "")):
		FriendsStore.TURN_FIND:
			return UiKit.button("Find" if compact else "Find %s" % f["name"], func() -> void: AppState.start_friend_search(id), UiKit.GOOD)
		FriendsStore.TURN_HIDE:
			return UiKit.button("Hide" if compact else "Hide and send back", func() -> void:
				AppState.start_friend_hide(id, String(f.get("difficulty", Difficulty.DEFAULT_ID))), UiKit.ACCENT)
	return UiKit.button("Details" if compact else "Back", func() -> void: _go("friend", id) if compact else _go("list"), UiKit.MUTED)


func _invite_card(inv: Dictionary) -> Control:
	var row := UiKit.hbox(10)
	var text := UiKit.vbox(0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(UiKit.label("Invite sent · %s" % Difficulty.get_level(String(inv.get("difficulty", ""))).get("name"), 17, UiKit.INK, false))
	text.add_child(UiKit.label("Waiting for someone to open it and send one back. Their reply starts the game here.", 13, UiKit.MUTED))
	row.add_child(text)
	var code := String(inv.get("code", ""))
	if code != "":
		row.add_child(_copy_button("Copy", code))
	var cancel := UiKit.button("✕", func() -> void:
		FriendsStore.cancel_invite(String(inv["challenge_id"]))
		_go("list"), UiKit.MUTED)
	cancel.custom_minimum_size = Vector2(52, 52)
	row.add_child(cancel)
	return UiKit.panel(row)


## Copies [param code] (a browser tap on the web, so iOS allows it).
func _copy_button(text: String, code: String) -> Control:
	var b := UiKit.button(text, func() -> void:
		if not WebTap.available():
			DisplayServer.clipboard_set(code)
			_say("Code copied.", UiKit.GOOD), UiKit.MUTED)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if WebTap.available():
		var tap := WebTap.new(b, "copy", code)
		tap.replied.connect(func(reply: Dictionary) -> void:
			_say("Code copied." if reply.get("ok", false) else "Couldn't copy here.", UiKit.GOOD if reply.get("ok", false) else UiKit.BAD))
		b.add_child(tap)
	return b


# --- one friend -------------------------------------------------------------

func _build_friend(v: VBoxContainer) -> void:
	var f := FriendsStore.get_friend(_friend_id)
	if f.is_empty():
		_page = "list"
		_build_list(v)
		return
	var st := FriendsStore.stats(f)
	var head := UiKit.hbox(12)
	head.add_child(_portrait(f.get("look", {}), Vector2(80, 94)))
	var text := UiKit.vbox(2)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(UiKit.title(String(f.get("name", "Friend")), 34, UiKit.ACCENT))
	if f.get("bot", false):
		text.add_child(UiKit.label("Practice partner (a computer player). Online matchmaking will pair you with real people here.", 14, UiKit.MUTED))
	text.add_child(UiKit.label(FriendsStore.status_line(f), 17, UiKit.INK))
	text.add_child(UiKit.label("Difficulty: %s" % Difficulty.get_level(String(f.get("difficulty", ""))).get("name"), 14, UiKit.MUTED))
	head.add_child(text)
	v.add_child(head)

	# Head to head.
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 4)
	for cell in ["", "You", String(f.get("name", "Them"))]:
		grid.add_child(UiKit.label(cell, 16, UiKit.INK, false))
	var fmt := func(t: float) -> String: return UiKit.format_time(t) if t > 0.0 else "–"
	var rows := [
		["Rounds won", str(st["my_wins"]), str(st["their_wins"])],
		["Finds", str(st["my_finds"]), str(st["their_finds"])],
		["Fastest find", fmt.call(st["my_best"]), fmt.call(st["their_best"])],
		["Average find", fmt.call(st["my_avg"]), fmt.call(st["their_avg"])],
	]
	for r: Array in rows:
		grid.add_child(UiKit.label(r[0], 15, UiKit.MUTED, false))
		grid.add_child(UiKit.label(r[1], 16, UiKit.INK, false))
		grid.add_child(UiKit.label(r[2], 16, UiKit.INK, false))
	v.add_child(UiKit.label("%d searches played" % st["rounds"], 15, UiKit.MUTED, false))
	v.add_child(grid)

	# Recent rounds, newest first.
	var rounds: Array = f.get("rounds", [])
	if not rounds.is_empty():
		v.add_child(UiKit.divider(8))
		v.add_child(UiKit.label("Recent", 17, UiKit.INK, false))
		for i in range(rounds.size() - 1, maxi(-1, rounds.size() - 9), -1):
			var r: Dictionary = rounds[i]
			var who := "You" if r["who"] == "me" else String(f.get("name", "They"))
			var what := ("found %s in %s" % ["them" if r["who"] == "me" else "you", UiKit.format_time(r["time"])]) if r["found"] \
				else "gave up after %s" % UiKit.format_time(r["time"])
			v.add_child(UiKit.label("%s %s · %d wrong" % [who, what, r.get("wrong", 0)], 14, UiKit.INK))

	v.add_child(UiKit.divider(8))
	var actions: Array = [_next_move_button(f, false)]
	var last_code := String(f.get("last_code", ""))
	if f.get("turn") == FriendsStore.TURN_WAIT and last_code != "" and not f.get("bot", false):
		actions.append(_copy_button("Copy your code again", last_code))
	if f.get("turn") != FriendsStore.TURN_WAIT or f.get("bot", false):
		actions.append(UiKit.button("Back", func() -> void: _go("list"), UiKit.MUTED))
	actions.append(UiKit.button("Remove", func() -> void:
		FriendsStore.remove(_friend_id)
		_go("list"), UiKit.BAD))
	v.add_child(UiKit.button_row(actions))


# --- new game ----------------------------------------------------------------

func _build_new(v: VBoxContainer) -> void:
	var random := _new_kind == "random"
	var banner := UiKit.banner("Play with random" if random else "Send a game", minf(420.0, UiKit.fit_width(420.0)), 30)
	banner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(banner)
	if random:
		var line := "You'll be paired with someone at this difficulty."
		if not Matchmaker.is_online():
			line = "Online matchmaking isn't live yet, so you'll play a practice partner: a computer player who hides for you and searches your spots."
		v.add_child(UiKit.label(line, 16, UiKit.MUTED))
	else:
		v.add_child(UiKit.label("You hide first. Then send the code to a friend: when they find you, they hide and send one back, and your game shows up here.", 16, UiKit.MUTED))
	v.add_child(UiKit.label("How hard?", 18, UiKit.INK, false))
	var colors := [UiKit.GOOD, Color("5f7fb5"), UiKit.ACCENT, UiKit.BAD]
	for i in Difficulty.LEVELS.size():
		var l: Dictionary = Difficulty.LEVELS[i]
		var id := String(l["id"])
		var row := UiKit.hbox(10)
		var b := UiKit.button(String(l["name"]), func() -> void: _start_new(id), colors[i % colors.size()])
		b.custom_minimum_size = Vector2(130, 56)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(b)
		var info := UiKit.label("%s Hiders must stay %d%% visible." % [l["blurb"], roundi(float(l["min_visible"]) * 100.0)], 14, UiKit.INK)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		v.add_child(row)
	v.add_child(UiKit.button("Back", func() -> void: _go("list"), UiKit.MUTED))


func _start_new(difficulty: String) -> void:
	if _new_kind == "random":
		AppState.start_bot_round(Matchmaker.find_random(difficulty))
	else:
		AppState.start_friend_hide("", difficulty)


# --- receiving a code ----------------------------------------------------------

func _on_paste() -> void:
	if not WebTap.available():
		_code.text = DisplayServer.clipboard_get()


func _on_web_paste(reply: Dictionary) -> void:
	if reply.get("ok", false):
		_code.text = String(reply.get("text", ""))
		_say("")
	elif reply.get("error") != "cancelled":
		_say("Couldn't read the clipboard. Long-press the box and choose Paste.")


func _on_open_code() -> void:
	var text := _code.text
	var result := ChallengeCodec.decode(text)
	if result["challenge"] == null:
		print("[Friends] code rejected: ", result["error"])
		_say(String(result["error"]))
		return
	var c: ChallengeData = result["challenge"]
	print("[Friends] opening challenge %s (seed %d)" % [c.challenge_id, c.map_seed])
	var code := ChallengeCodec.encode(c)
	var r := FriendsStore.receive(c, code)
	_code_text = ""
	if r["own"]:
		# Your own code: fine for passing the device, but nothing is recorded.
		AppState.start_search(c)
		return
	if String(r["friend_id"]) == "":
		# An older code without a sender: just play it.
		AppState.start_search(c)
		return
	var f := FriendsStore.get_friend(String(r["friend_id"]))
	var note := ""
	var their: Dictionary = r["their_result"]
	if not their.is_empty():
		note = ("%s found you in %s! " % [f["name"], UiKit.format_time(their["time"])]) if their["found"] else ("%s couldn't find you! " % f["name"])
	if r["already_played"]:
		note += "You've already played this code."
	elif r["is_new"]:
		note += "New game with %s. Your turn to find them." % f["name"]
	else:
		note += "Your turn to find %s." % f["name"]
	_go("friend", String(r["friend_id"]), note)
	_message.add_theme_color_override("font_color", UiKit.GOOD)
