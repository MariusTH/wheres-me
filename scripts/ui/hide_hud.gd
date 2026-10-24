class_name HideHud
extends Control
## Hide-mode UI: who is hiding, live visibility readout, Confirm, and the
## share dialog. Emits intents only; HideController owns the rules.

signal confirm_pressed
signal back_pressed
signal edit_pressed

var _visible_label: Label
var _status: Label
var _confirm: Button


func _ready() -> void:
	theme = UiKit.theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func setup(subject: WorldObjectData, hider_name: String, map_title: String, map_seed: int) -> void:
	var critter := VisibilityChecker.is_critter(subject)
	var v := UiKit.vbox(8)
	v.custom_minimum_size = Vector2(290, 0)
	v.add_child(UiKit.stripes(8))
	var who := UiKit.hbox(10)
	var portrait := AvatarPortrait.new()
	portrait.show_subject(subject)
	portrait.disabled = true
	portrait.custom_minimum_size = Vector2(76, 90)
	who.add_child(portrait)
	var who_text := UiKit.vbox(6)
	if critter:
		who_text.add_child(UiKit.label("Hide the %s!" % AssetCatalog.label(subject.asset_key), 22, UiKit.INK, false))
		who_text.add_child(UiKit.label("New seed = new critter", 14, UiKit.MUTED, false))
	else:
		who_text.add_child(UiKit.label(hider_name if hider_name != "" else "You", 24, UiKit.INK, false))
		var edit := UiKit.button("Edit avatar", func() -> void: edit_pressed.emit(), UiKit.MUTED)
		edit.custom_minimum_size = Vector2(0, 44)
		who_text.add_child(edit)
	who.add_child(who_text)
	v.add_child(who)
	var what := "it" if critter else "you"
	v.add_child(UiKit.label("Tap the map to hide %s there. Drag to fine-tune. At least %d%% of %s must stay visible." % [what, roundi(VisibilityChecker.MIN_VISIBLE * 100.0), what], 16, UiKit.MUTED))
	_visible_label = UiKit.label("Visible: –", 26, UiKit.INK, false)
	v.add_child(_visible_label)
	_status = UiKit.label("", 16)
	_status.custom_minimum_size = Vector2(290, 44)
	v.add_child(_status)
	_confirm = UiKit.button("Confirm hiding spot", func() -> void: confirm_pressed.emit(), UiKit.GOOD)
	_confirm.disabled = true
	v.add_child(_confirm)
	v.add_child(UiKit.button("Back", func() -> void: back_pressed.emit(), UiKit.MUTED))
	v.add_child(UiKit.label("%s seed %d  ·  Pinch or scroll to zoom" % [map_title, map_seed], 13, UiKit.MUTED))
	var side := UiKit.panel(v)
	side.position = Vector2(12, 12)
	add_child(side)


## Shows a VisibilityChecker result.
func show_check(result: Dictionary) -> void:
	var ok: bool = result["ok"]
	_visible_label.text = "Visible: %d%%" % floori(float(result["fraction"]) * 100.0)
	_visible_label.add_theme_color_override("font_color", UiKit.GOOD if ok else UiKit.BAD)
	_status.text = "Nice spot! Confirm when you're happy." if ok else String(result["reason"])
	_status.add_theme_color_override("font_color", UiKit.INK if ok else UiKit.BAD)
	_confirm.disabled = not ok


func show_share(code: String, saved_path: String, on_search_now: Callable, on_hide_again: Callable, on_menu: Callable) -> void:
	var v := UiKit.vbox(12)
	v.custom_minimum_size = Vector2(620, 0)
	var banner := UiKit.banner("Challenge ready!", 420, 28)
	banner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(banner)
	v.add_child(UiKit.label("Send this code to a friend. They paste it on the main menu and try to find it.", 17, UiKit.MUTED))
	var code_box := TextEdit.new()
	code_box.text = code
	code_box.editable = false
	code_box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	code_box.custom_minimum_size = Vector2(600, 120)
	v.add_child(code_box)
	var copied := UiKit.label("", 15, UiKit.GOOD, false)
	var row := UiKit.hbox()
	row.add_child(UiKit.button("Copy code", func() -> void:
		DisplayServer.clipboard_set(code)
		copied.text = "Copied to clipboard."))
	row.add_child(copied)
	v.add_child(row)
	if saved_path != "":
		v.add_child(UiKit.label("Also saved as a file: %s" % ProjectSettings.globalize_path(saved_path), 13, UiKit.MUTED))
	else:
		v.add_child(UiKit.label("Could not save a file copy (see the console). The code above still works.", 13, UiKit.BAD))
	var actions := UiKit.hbox()
	actions.add_child(UiKit.button("Search now (pass the device)", on_search_now, UiKit.GOOD))
	actions.add_child(UiKit.button("Hide again", on_hide_again))
	actions.add_child(UiKit.button("Menu", on_menu, UiKit.MUTED))
	v.add_child(actions)
	add_child(UiKit.modal(v))
