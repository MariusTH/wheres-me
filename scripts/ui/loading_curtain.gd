class_name LoadingCurtain
extends CanvasLayer
## Full-screen "building the town" card shown while the town scene builds
## (generating and drawing thousands of people takes a moment on phones).
## Better a calm loading card than a frozen or half-drawn screen. Lifted with
## a short fade once the first frames of the finished town have been drawn.

var _root: Control


static func cover(parent: Node, text: String = "Filling the town…") -> LoadingCurtain:
	var c := LoadingCurtain.new()
	c.layer = 50
	parent.add_child(c)
	c._build(text)
	return c


## True where a loading card makes sense (not in headless test runs).
static func wanted() -> bool:
	return DisplayServer.get_name() != "headless"


func _build(text: String) -> void:
	_root = Control.new()
	_root.theme = UiKit.theme()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_root.add_child(UiKit.backdrop())
	var v := UiKit.vbox(12)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var glass := UiKit.icon("ui_magnifier", 96)
	glass.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	glass.resized.connect(func() -> void: glass.pivot_offset = glass.size / 2.0)
	v.add_child(glass)
	var l := UiKit.title(text, 34, UiKit.INK)
	l.add_theme_constant_override("outline_size", 0)
	v.add_child(l)
	_root.add_child(UiKit.scroll_center(UiKit.panel(v)))
	var t := glass.create_tween().set_loops()
	t.tween_property(glass, "rotation", 0.12, 0.5).set_trans(Tween.TRANS_SINE)
	t.tween_property(glass, "rotation", -0.12, 0.5).set_trans(Tween.TRANS_SINE)


## Waits [param frames] rendered frames, so the card is really on screen.
func settle(frames: int = 2) -> void:
	for i in frames:
		await get_tree().process_frame


func lift() -> void:
	var t := create_tween()
	t.tween_property(_root, "modulate:a", 0.0, 0.25)
	t.tween_callback(queue_free)
