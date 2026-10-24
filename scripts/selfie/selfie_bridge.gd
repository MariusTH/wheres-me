class_name SelfieBridge
extends Node
## Web-only link to web/selfie.js: the selfie button is a WebTap with action
## "photo" (the picker must open inside the browser's own tap handler), and
## the JSON replies become signals.

signal analyzing
## [param features] is the dictionary PhotoToLook.apply() expects.
signal finished(features: Dictionary)
signal failed(message: String)

const SCRIPT_PATH := "res://web/selfie.js"

static var _loaded := false

var _tap: WebTap


static func available() -> bool:
	return WebTap.available()


func _init(button: Control) -> void:
	_tap = WebTap.new(button, "photo")


func _ready() -> void:
	if not available():
		return
	WebTap.load_script()
	if not _loaded:
		_loaded = true
		JavaScriptBridge.eval(FileAccess.get_file_as_string(SCRIPT_PATH), true)
	add_child(_tap)
	_tap.replied.connect(_on_reply)


func _on_reply(d: Dictionary) -> void:
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
