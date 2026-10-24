class_name SelfieBridge
extends Node
## Web-only link to web/selfie.js: keeps the selfie button's screen rect
## registered with the page (the picker must open inside the browser's own tap
## handler, see selfie.js) and turns its JSON replies into signals.

signal analyzing
## [param features] is the dictionary PhotoToLook.apply() expects.
signal finished(features: Dictionary)
signal failed(message: String)

const SCRIPT_PATH := "res://web/selfie.js"

var _button: Control
var _callback: JavaScriptObject
var _last_rect := Rect2()


static func available() -> bool:
	return OS.has_feature("web")


func _init(button: Control) -> void:
	_button = button


func _ready() -> void:
	if not available():
		set_process(false)
		return
	JavaScriptBridge.eval(FileAccess.get_file_as_string(SCRIPT_PATH), true)
	# Keep a reference: the JS side only holds a weak one.
	_callback = JavaScriptBridge.create_callback(_on_message)


func _exit_tree() -> void:
	if available():
		JavaScriptBridge.eval("window.hfSelfie && window.hfSelfie.clearTarget()", true)


func _process(_delta: float) -> void:
	var rect := Rect2()
	if _button.is_visible_in_tree():
		# Viewport coordinates, normalised: with aspect "expand" the visible
		# rect spans the whole canvas element.
		var xf := _button.get_global_transform_with_canvas()
		var visible := get_viewport().get_visible_rect()
		rect = Rect2((xf.origin - visible.position) / visible.size, xf.basis_xform(_button.size) / visible.size)
	if rect == _last_rect:
		return
	_last_rect = rect
	var api: JavaScriptObject = JavaScriptBridge.get_interface("hfSelfie")
	if rect.has_area():
		api.setTarget(rect.position.x, rect.position.y, rect.size.x, rect.size.y, _callback)
	else:
		api.clearTarget()


func _on_message(args: Array) -> void:
	var data: Variant = JSON.parse_string(String(args[0]))
	if not data is Dictionary:
		failed.emit("Something went wrong reading the photo.")
		return
	var d: Dictionary = data
	if d.get("stage") == "analyzing":
		analyzing.emit()
	elif d.get("ok", false):
		finished.emit(d)
	else:
		failed.emit(message_for(String(d.get("error", ""))))


static func message_for(error: String) -> String:
	match error:
		"cancelled":
			return ""
		"no_face":
			return "Couldn't find a face. Try a front-facing photo in good light."
	return "Couldn't read that photo (%s)." % error
