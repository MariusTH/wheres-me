class_name WebField
extends Node
## Web-only: lays a real browser textarea (web/web_tap.js) over [member edit],
## because Godot's own text input on the web is a hidden element that iOS
## can't long-press to paste into, and focusing it zooms the page. The
## TextEdit stays as the frame and keeps [code]text[/code] in sync both ways;
## its own text is hidden so it isn't drawn twice.

var _edit: TextEdit
var _id: String
var _callback: JavaScriptObject
var _last_rect := Rect2()
var _last_text := ""


func _init(edit: TextEdit) -> void:
	_edit = edit


func _ready() -> void:
	if not WebTap.available():
		set_process(false)
		return
	WebTap.load_script()
	_id = "field_%d" % get_instance_id()
	# Keep a reference: the JS side only holds a weak one.
	_callback = JavaScriptBridge.create_callback(_on_input)
	_edit.editable = false
	_edit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for color in ["font_color", "font_readonly_color", "font_placeholder_color"]:
		_edit.add_theme_color_override(color, Color.TRANSPARENT)
	_edit.add_theme_stylebox_override("read_only", _edit.get_theme_stylebox("normal"))


func _exit_tree() -> void:
	if WebTap.available() and _id != "":
		JavaScriptBridge.eval("window.wmTap && window.wmTap.clearField(%s)" % JSON.stringify(_id), true)


func _process(_delta: float) -> void:
	var rect := Rect2()
	if _edit.is_visible_in_tree():
		var xf := _edit.get_global_transform_with_canvas()
		var visible := get_viewport().get_visible_rect()
		rect = Rect2((xf.origin - visible.position) / visible.size, xf.basis_xform(_edit.size) / visible.size)
	# Godot changed the text (e.g. the Paste button): push it to the browser.
	if rect == _last_rect and _edit.text == _last_text:
		return
	_last_rect = rect
	_last_text = _edit.text
	var api: JavaScriptObject = JavaScriptBridge.get_interface("wmTap")
	if rect.has_area():
		api.putField(_id, rect.position.x, rect.position.y, rect.size.x, rect.size.y, _edit.text, _edit.placeholder_text, _callback)
	else:
		api.clearField(_id)


func _on_input(args: Array) -> void:
	_last_text = String(args[0])
	_edit.text = _last_text
