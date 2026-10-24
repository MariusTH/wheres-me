class_name HideHud
extends Control
## Hide-mode UI: who or what is hiding, live visibility readout, Confirm, and
## the share dialog. Emits intents only; HideController owns the rules.
## Desktop: a side panel. Phones: a compact bottom sheet, so most of the map
## stays visible. Rebuilds when the screen's size class changes.

signal confirm_pressed
signal back_pressed
signal edit_pressed

const GAME_URL := "https://parchnipp.itch.io/wheres-me"

var _visible_label: Label
var _status: Label
var _confirm: Button
var _root: Control
var _share: Control

var _subject: WorldObjectData
var _hider_name: String
var _map_title: String
var _map_seed: int
var _last_check: Dictionary = {}
## Arguments of show_share() while the dialog is open, to rebuild it.
var _share_args: Array = []


func _ready() -> void:
	theme = UiKit.theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	AppState.layout_changed.connect(_rebuild)


func setup(subject: WorldObjectData, hider_name: String, map_title: String, map_seed: int) -> void:
	_subject = subject
	_hider_name = hider_name
	_map_title = map_title
	_map_seed = map_seed
	_rebuild()


func _rebuild() -> void:
	if _subject == null:
		return
	if _root:
		_root.queue_free()
	var compact := AppState.is_narrow() or AppState.is_short()
	var critter := VisibilityChecker.is_critter(_subject)
	var what := "it" if critter else "you"

	var portrait := AvatarPortrait.new()
	portrait.show_subject(_subject)
	portrait.disabled = true
	portrait.custom_minimum_size = Vector2(56, 66) if compact else Vector2(76, 90)
	var who_text := UiKit.vbox(4)
	who_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var heading := "Hide the %s!" % AssetCatalog.label(_subject.asset_key) if critter else (_hider_name if _hider_name != "" else "You")
	who_text.add_child(UiKit.label(heading, 20 if compact else 22, UiKit.INK, false))
	_visible_label = UiKit.label("Visible: –", 22 if compact else 26, UiKit.INK, false)
	_status = UiKit.label("Tap the map to hide %s." % what if compact else "", 15 if compact else 16)
	_status.custom_minimum_size = Vector2(0, 40 if compact else 44)
	_confirm = UiKit.button("Confirm spot" if compact else "Confirm hiding spot", func() -> void: confirm_pressed.emit(), UiKit.GOOD)
	_confirm.disabled = true
	_confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var back := UiKit.button("Back", func() -> void: back_pressed.emit(), UiKit.MUTED)

	var v := UiKit.vbox(6 if compact else 8)
	v.add_child(UiKit.stripes(8))
	var who := UiKit.hbox(10)
	who.add_child(portrait)
	who.add_child(who_text)
	v.add_child(who)
	if compact:
		who_text.add_child(_visible_label)
		v.add_child(_status)
		var row := UiKit.hbox(8)
		row.add_child(back)
		if not critter:
			row.add_child(UiKit.button("Avatar", func() -> void: edit_pressed.emit(), UiKit.MUTED))
		row.add_child(_confirm)
		v.add_child(row)
		var sheet := UiKit.panel(v)
		sheet.custom_minimum_size = Vector2(UiKit.fit_width(560.0), 0)
		var anchor := CenterContainer.new()
		anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		anchor.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		anchor.offset_top = -8
		anchor.offset_bottom = -8
		anchor.grow_vertical = Control.GROW_DIRECTION_BEGIN
		anchor.add_child(sheet)
		_root = anchor
	else:
		v.custom_minimum_size = Vector2(290, 0)
		if critter:
			who_text.add_child(UiKit.label("New seed = new critter", 14, UiKit.MUTED, false))
		else:
			var edit := UiKit.button("Edit avatar", func() -> void: edit_pressed.emit(), UiKit.MUTED)
			edit.custom_minimum_size = Vector2(0, 44)
			who_text.add_child(edit)
		v.add_child(UiKit.label("Tap the map to hide %s there. Drag to fine-tune. At least %d%% of %s must stay visible." % [what, roundi(VisibilityChecker.MIN_VISIBLE * 100.0), what], 16, UiKit.MUTED))
		v.add_child(_visible_label)
		v.add_child(_status)
		v.add_child(_confirm)
		v.add_child(back)
		v.add_child(UiKit.label("%s seed %d  ·  Pinch or scroll to zoom" % [_map_title, _map_seed], 13, UiKit.MUTED))
		var side := UiKit.panel(v)
		side.position = Vector2(12, 12)
		_root = side
	add_child(_root)
	if not _last_check.is_empty():
		show_check(_last_check)
	if not _share_args.is_empty():
		_show_share_dialog()


## Shows a VisibilityChecker result.
func show_check(result: Dictionary) -> void:
	_last_check = result
	var ok: bool = result["ok"]
	_visible_label.text = "Visible: %d%%" % floori(float(result["fraction"]) * 100.0)
	_visible_label.add_theme_color_override("font_color", UiKit.GOOD if ok else UiKit.BAD)
	_status.text = "Nice spot! Confirm when you're happy." if ok else String(result["reason"])
	_status.add_theme_color_override("font_color", UiKit.INK if ok else UiKit.BAD)
	_confirm.disabled = not ok


func show_share(code: String, saved_path: String, on_search_now: Callable, on_hide_again: Callable, on_menu: Callable) -> void:
	_share_args = [code, saved_path, on_search_now, on_hide_again, on_menu]
	_show_share_dialog()


func _show_share_dialog() -> void:
	if _share:
		_share.queue_free()
	var code: String = _share_args[0]
	var saved_path: String = _share_args[1]
	var width := UiKit.fit_width(620.0)
	var v := UiKit.vbox(12)
	v.custom_minimum_size = Vector2(width, 0)
	var banner := UiKit.banner("Challenge ready!", minf(420.0, width), 28)
	banner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(banner)
	v.add_child(UiKit.label("Send this code to a friend. They paste it on the main menu and try to find it.", 17, UiKit.MUTED))
	var code_box := TextEdit.new()
	code_box.text = code
	code_box.editable = false
	code_box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	code_box.custom_minimum_size = Vector2(0, 90 if AppState.is_short() else 120)
	v.add_child(code_box)
	var feedback := UiKit.label("", 15, UiKit.GOOD, false)
	var message := "Can you find me in Where's Me? Paste this code at %s\n\n%s" % [GAME_URL, code]
	var copy := UiKit.button("Copy code", func() -> void:
		if not WebTap.available():
			DisplayServer.clipboard_set(code)
			feedback.text = "Copied to clipboard.")
	var share_buttons: Array = [copy]
	var taps: Array[WebTap] = []
	if WebTap.available():
		taps.append(WebTap.new(copy, "copy", code))
		if WebTap.can_share():
			var share := UiKit.button("Share…", func() -> void: pass, UiKit.GOOD)
			share_buttons.append(share)
			taps.append(WebTap.new(share, "share", message))
	for tap in taps:
		tap.replied.connect(func(reply: Dictionary) -> void:
			if reply.get("ok", false):
				feedback.text = "Copied to clipboard." if tap.payload == code else "Sent!"
				feedback.add_theme_color_override("font_color", UiKit.GOOD)
			elif reply.get("error") != "cancelled":
				feedback.text = "Couldn't do that here. Select the code and copy it."
				feedback.add_theme_color_override("font_color", UiKit.BAD))
		v.add_child(tap)
	share_buttons.append(feedback)
	v.add_child(UiKit.button_row(share_buttons))
	if saved_path != "" and not OS.has_feature("web"):
		v.add_child(UiKit.label("Also saved as a file: %s" % ProjectSettings.globalize_path(saved_path), 13, UiKit.MUTED))
	v.add_child(UiKit.button_row([
		UiKit.button("Search now (pass the device)", _share_args[2], UiKit.GOOD),
		UiKit.button("Hide again", _share_args[3]),
		UiKit.button("Menu", _share_args[4], UiKit.MUTED),
	]))
	_share = UiKit.modal(v)
	add_child(_share)
