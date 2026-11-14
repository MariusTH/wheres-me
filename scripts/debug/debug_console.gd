extends CanvasLayer
## Debug console for prototyping on phones (autoload "DebugConsole").
## Open it: shake the phone, tap with three fingers, or press F12 / ` on desktop
## (or start with -- --console).
## Shows device and app info, the last log lines (print, warnings, script
## errors) and the native iOS log (native/ios/WMNative.m), with Copy and Share
## so a tester can paste it into a chat.

const NATIVE_LOG := "user://wmnative.log"
## Acceleration (m/s², gravity removed) that counts as one shake jolt.
const SHAKE_JOLT := 14.0
## Jolts within SHAKE_WINDOW seconds that open the console.
const SHAKE_JOLTS := 3
const SHAKE_WINDOW := 1.0

var _panel: Control
var _text: TextEdit
var _feedback: Label
var _jolts: Array[float] = []
var _touches := {}


func _init() -> void:
	DebugLog.install()


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("[DebugConsole] ready: shake, three-finger tap or F12 to open")
	if OS.get_cmdline_user_args().has("--console"):
		toggle.call_deferred()


func _process(_delta: float) -> void:
	if not OS.has_feature("mobile"):
		return
	var a := Input.get_accelerometer() - Input.get_gravity()
	if Input.get_gravity() == Vector3.ZERO:
		# No gravity sensor: treat anything far from 1 g as a jolt.
		a = Vector3(0, 0, Input.get_accelerometer().length() - 9.81)
	if a.length() < SHAKE_JOLT:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if not _jolts.is_empty() and now - _jolts[-1] < 0.12:
		return  # same jolt
	_jolts.append(now)
	_jolts = _jolts.filter(func(t: float) -> bool: return now - t <= SHAKE_WINDOW)
	if _jolts.size() >= SHAKE_JOLTS:
		_jolts.clear()
		toggle()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_F12 or event.keycode == KEY_QUOTELEFT):
		toggle()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = true
			if _touches.size() >= 3:
				_touches.clear()
				toggle()
				get_viewport().set_input_as_handled()
		else:
			_touches.erase(event.index)


func toggle() -> void:
	if _panel:
		_panel.queue_free()
		_panel = null
	else:
		_open()


func _open() -> void:
	var v := UiKit.vbox(8)
	v.custom_minimum_size = Vector2(UiKit.fit_width(900.0), 0)
	v.add_child(UiKit.label("Debug console", 22, UiKit.ACCENT, false))
	_text = TextEdit.new()
	_text.editable = false
	_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_text.custom_minimum_size = Vector2(0, maxf(200.0, UiKit.viewport_size().y - 190.0))
	_text.add_theme_font_size_override("font_size", 13)
	_text.text = report()
	v.add_child(_text)
	_feedback = UiKit.label("", 14, UiKit.GOOD, false)
	var buttons: Array = [
		UiKit.button("Copy", func() -> void:
			DisplayServer.clipboard_set(_text.text)
			_feedback.text = "Copied.", UiKit.GOOD),
	]
	if NativeShare.available():
		buttons.append(UiKit.button("Share…", func() -> void: NativeShare.share(_text.text), UiKit.GOOD))
	buttons.append(UiKit.button("Refresh", func() -> void: _text.text = report(), UiKit.MUTED))
	buttons.append(UiKit.button("Clear", func() -> void:
		DebugLog.clear()
		if FileAccess.file_exists(NATIVE_LOG):
			DirAccess.remove_absolute(NATIVE_LOG)
		_text.text = report(), UiKit.MUTED))
	buttons.append(UiKit.button("Close", toggle, UiKit.MUTED))
	buttons.append(_feedback)
	v.add_child(UiKit.button_row(buttons))
	var root := Control.new()
	root.theme = UiKit.theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(UiKit.modal(v))
	_panel = root
	add_child(root)


## Everything a tester should paste: device, app state, logs.
func report() -> String:
	var out := PackedStringArray()
	out.append("== Where's Me debug report %s ==" % Time.get_datetime_string_from_system())
	out.append("OS: %s %s, model %s, locale %s" % [OS.get_name(), OS.get_version(), OS.get_model_name(), OS.get_locale()])
	out.append("Godot %s, renderer %s, video %s" % [Engine.get_version_info()["string"],
		RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name()])
	out.append("Screen %s @%.2fx, window %s, viewport %s" % [DisplayServer.screen_get_size(),
		DisplayServer.screen_get_scale(), DisplayServer.window_get_size(), UiKit.viewport_size()])
	out.append("FPS %d, static mem %.1f MB, user dir %s" % [Engine.get_frames_per_second(),
		OS.get_static_memory_usage() / 1048576.0, OS.get_user_data_dir()])
	var app := get_node_or_null("/root/AppState")
	if app:
		out.append("AppState: mode=%s seed=%d map=%s size=%s session=%s avatar=%s player=%s" % [
			app.mode, app.map_seed, app.map_id, app.map_size, app.session, app.has_avatar(), app.player_id])
		out.append("Deep link: pending=%s inbox_file=%s" % [app.pending_code.left(24), FileAccess.file_exists(DeepLink.INBOX)])
	out.append("Scene: %s" % (get_tree().current_scene.scene_file_path if get_tree().current_scene else "-"))
	if FileAccess.file_exists(NATIVE_LOG):
		out.append("\n== native (iOS) ==")
		out.append(FileAccess.get_file_as_string(NATIVE_LOG).strip_edges())
	elif OS.get_name() == "iOS":
		out.append("\n== native (iOS) ==\n(no wmnative.log: native glue not linked?)")
	out.append("\n== log (newest last) ==")
	out.append(DebugLog.text())
	return "\n".join(out)
