class_name WebTap
extends Node
## Web-only: runs a browser action (web/web_tap.js) when [member button] is
## tapped, inside the browser's own tap handler, because iOS Safari refuses
## clipboard, share-sheet and photo-picker calls made a frame later from
## Godot. Actions: "paste", "copy", "share", and "photo" (web/selfie.js).
## The button's own pressed signal still fires; on the web it shouldn't do
## the same work again.

## Parsed JSON reply from the action, e.g. {"ok": true, "text": "..."}.
signal replied(data: Dictionary)

const SCRIPT_PATH := "res://web/web_tap.js"

## Text for "copy" and "share".
var payload: String = "":
	set(value):
		payload = value
		_last_rect = Rect2()

var _button: Control
var _action: String
var _id: String
var _callback: JavaScriptObject
var _last_rect := Rect2()
static var _loaded := false


static func available() -> bool:
	return OS.has_feature("web")


## Whether the browser has a native share sheet (phones, Safari).
static func can_share() -> bool:
	if not available():
		return false
	load_script()
	return bool(JavaScriptBridge.eval("window.wmTap.canShare()", true))


static func load_script() -> void:
	if not _loaded:
		_loaded = true
		JavaScriptBridge.eval(FileAccess.get_file_as_string(SCRIPT_PATH), true)


func _init(button: Control, action: String, p_payload: String = "") -> void:
	_button = button
	_action = action
	payload = p_payload


func _ready() -> void:
	if not available():
		set_process(false)
		return
	load_script()
	_id = "%s_%d" % [_action, get_instance_id()]
	# Keep a reference: the JS side only holds a weak one.
	_callback = JavaScriptBridge.create_callback(_on_reply)


func _exit_tree() -> void:
	if available() and _id != "":
		JavaScriptBridge.eval("window.wmTap && window.wmTap.clear(%s)" % JSON.stringify(_id), true)


func _process(_delta: float) -> void:
	var rect := Rect2()
	if _button.is_visible_in_tree() and not (_button is BaseButton and (_button as BaseButton).disabled):
		# Viewport coordinates, normalised: with aspect "expand" the visible
		# rect spans the whole canvas element.
		var xf := _button.get_global_transform_with_canvas()
		var visible := get_viewport().get_visible_rect()
		rect = Rect2((xf.origin - visible.position) / visible.size, xf.basis_xform(_button.size) / visible.size)
	if rect == _last_rect:
		return
	_last_rect = rect
	var api: JavaScriptObject = JavaScriptBridge.get_interface("wmTap")
	if rect.has_area():
		api.put(_id, rect.position.x, rect.position.y, rect.size.x, rect.size.y, _action, payload, _callback)
	else:
		api.clear(_id)


func _on_reply(args: Array) -> void:
	var data: Variant = JSON.parse_string(String(args[0]))
	replied.emit(data if data is Dictionary else {"ok": false, "error": "bad reply"})
