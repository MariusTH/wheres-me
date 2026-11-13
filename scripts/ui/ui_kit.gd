class_name UiKit
extends RefCounted
## Shared "Where's Me" storybook theme and widget helpers, matching the town:
## cream paper, warm brown ink, sage and terracotta washes, a chunky display
## font, hand-drawn signboards and wobbly ink dividers, plus the painted HUD
## art in art/ui (magnifier, stopwatch, menu backdrop).

const INK := Color("3a2b24")
const PAPER := Color("f8f1e2")
## Terracotta: headings and the "find them" action.
const ACCENT := Color("cf6a4a")
## Sage: the main action on every screen.
const GOOD := Color("4f9177")
const BAD := Color("b84f45")
## Dusty plum: secondary buttons.
const MUTED := Color("85727f")
const SAGE_WASH := Color("b9dcc5")
const FIELD_BORDER := Color("d8ccb6")
const DISPLAY_FONT_PATH := "res://art/fonts/LuckiestGuy-Regular.ttf"
const UI_ART := "res://art/ui/%s.png"
## Lens of ui_magnifier.png: centre and radius as fractions of the image width/height.
const LENS_CENTER := Vector2(0.475, 0.272)
const LENS_RADIUS := 0.40

static var _theme: Theme = null
static var _display_font: Font = null


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 19
	t.set_font("font", "Button", display_font())
	t.set_font_size("font_size", "Button", 21)
	t.set_color("font_color", "Label", INK)
	t.set_color("font_color", "CheckButton", INK)
	t.set_color("font_hover_color", "CheckButton", INK)
	t.set_color("font_pressed_color", "CheckButton", INK)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(state, "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.7))
	t.set_stylebox("normal", "Button", _button_box(ACCENT))
	t.set_stylebox("hover", "Button", _button_box(ACCENT.lightened(0.1)))
	t.set_stylebox("pressed", "Button", _button_box(ACCENT.darkened(0.12), true))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("disabled", "Button", _button_box(Color("c4b8a8")))
	t.set_color("font_outline_color", "Button", Color(0.16, 0.1, 0.08, 0.35))
	t.set_constant("outline_size", "Button", 3)
	var paper := _flat(PAPER, 20, INK, 2)
	paper.shadow_color = Color(0.2, 0.13, 0.08, 0.28)
	paper.shadow_size = 14
	paper.shadow_offset = Vector2(0, 6)
	paper.content_margin_left = 20
	paper.content_margin_right = 20
	paper.content_margin_top = 16
	paper.content_margin_bottom = 16
	t.set_stylebox("panel", "PanelContainer", paper)
	t.set_stylebox("normal", "TextEdit", _flat(Color("fffdf8"), 10, FIELD_BORDER, 2))
	t.set_stylebox("read_only", "TextEdit", _flat(Color("f3ecdd"), 10, FIELD_BORDER, 2))
	t.set_stylebox("focus", "TextEdit", _flat(Color("fffdf8"), 10, GOOD, 2))
	t.set_color("font_color", "TextEdit", INK)
	t.set_color("font_readonly_color", "TextEdit", INK)
	t.set_color("font_placeholder_color", "TextEdit", Color(INK, 0.4))
	t.set_font_size("font_size", "TextEdit", 15)
	t.set_stylebox("panel", "ItemList", _flat(Color("fffdf8"), 10, FIELD_BORDER, 2))
	t.set_color("font_color", "ItemList", INK)
	t.set_stylebox("normal", "LineEdit", _flat(Color("fffdf8"), 10, FIELD_BORDER, 2))
	t.set_stylebox("focus", "LineEdit", _flat(Color("fffdf8"), 10, GOOD, 2))
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", Color(INK, 0.4))
	t.set_stylebox("normal", "SpinBox", _flat(Color("fffdf8"), 10, FIELD_BORDER, 2))
	_theme = t
	return t


static func _flat(bg: Color, radius: int, border: Color, border_w: int = 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border_w)
	s.border_color = border
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


## Soft storybook button: ink outline and a thicker bottom edge that
## "presses in".
static func _button_box(bg: Color, pressed: bool = false) -> StyleBoxFlat:
	var s := _flat(bg, 16, INK, 2)
	s.border_width_bottom = 2 if pressed else 5
	s.content_margin_top = 10 if pressed else 7
	return s


static func display_font() -> Font:
	if _display_font == null:
		_display_font = load(DISPLAY_FONT_PATH) as Font
	return _display_font


static func ui_texture(key: String) -> Texture2D:
	for ext in ["png", "jpg"]:
		var path := "res://art/ui/%s.%s" % [key, ext]
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	return null


## Headline in the display font with a soft ink outline.
static func title(text: String, size: int = 40, color: Color = ACCENT) -> Label:
	var l := label(text, size, color, false)
	l.add_theme_font_override("font", display_font())
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", maxi(4, size / 8))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Luckiest Guy's capitals rise above the font's reported ascent; give the
	# label extra height and sit the text at the bottom so nothing pokes out
	# over the panel border above it.
	l.custom_minimum_size.y = size * 1.3
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return l


## Hand-drawn hanging signboard (cream board, sage frame, ink outline, two
## little hangers) with [param text] on it, [param width] wide.
static func banner(text: String, width: float, size: int = 34) -> Control:
	var room := width * 0.82
	while size > 14 and display_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > room:
		size -= 1
	var sign := _Sign.new()
	sign.custom_minimum_size = Vector2(width, size * 1.55 + 34)
	sign.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := title(text, size, ACCENT)
	l.add_theme_constant_override("outline_size", 0)
	l.custom_minimum_size = Vector2.ZERO
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.offset_top = 18
	l.offset_bottom = -2
	sign.add_child(l)
	return sign


class _Sign extends Control:
	func _draw() -> void:
		var board := Rect2(4, 16, size.x - 8, size.y - 20)
		# Hangers: two short iron lines up to the top edge.
		for x in [board.position.x + board.size.x * 0.18, board.end.x - board.size.x * 0.18]:
			draw_line(Vector2(x, board.position.y), Vector2(x + 6, 3), UiKit.INK, 2.0)
			draw_circle(Vector2(x + 6, 4), 3.0, UiKit.INK)
		var tilt := Transform2D(deg_to_rad(-0.8), board.get_center())
		draw_set_transform_matrix(tilt)
		var r := Rect2(-board.size / 2.0, board.size)
		draw_rect(r.grow(1), Color(0.2, 0.13, 0.08, 0.18))
		draw_rect(r, UiKit.SAGE_WASH)
		draw_rect(r.grow(-6), UiKit.PAPER)
		draw_rect(r, UiKit.INK, false, 2.0)
		draw_rect(r.grow(-6), Color(UiKit.INK, 0.55), false, 1.2)
		draw_set_transform_matrix(Transform2D.IDENTITY)


## Full-screen backdrop for menu screens: a painting of the town under a
## soft paper wash, so the busy scene stays in the background.
static func backdrop() -> Control:
	var root := ColorRect.new()
	root.color = Color("a9c98a")
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var town := icon("menu_town", 100)
	if town.texture:
		town.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		town.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(town)
	var wash := ColorRect.new()
	wash.color = Color(PAPER, 0.28)
	wash.set_anchors_preset(Control.PRESET_FULL_RECT)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(wash)
	return root


## Painted icon (magnifier, stopwatch) at [param height] px.
static func icon(key: String, height: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture = ui_texture(key)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var aspect := 1.0 if r.texture == null else float(r.texture.get_width()) / r.texture.get_height()
	r.custom_minimum_size = Vector2(height * aspect, height)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## [param content] shown inside the lens of the big magnifying glass (the
## "find this" card). The content is sized to fit the lens.
static func magnified(content: Control, height: float) -> Control:
	var glass := icon("ui_magnifier", height)
	if glass.texture == null:
		return content
	var w := glass.custom_minimum_size.x
	var r := LENS_RADIUS * w
	var lens := Panel.new()
	var round_box := StyleBoxFlat.new()
	round_box.bg_color = Color("f4eef6")
	round_box.set_corner_radius_all(int(r))
	lens.add_theme_stylebox_override("panel", round_box)
	lens.position = Vector2(LENS_CENTER.x * w - r, LENS_CENTER.y * height - r)
	lens.size = Vector2(r, r) * 2.0
	lens.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lens.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	content.position = Vector2(r * 0.15, r * 0.02)
	content.size = Vector2(r * 1.7, r * 1.96)
	content.custom_minimum_size = content.size
	lens.add_child(content)
	glass.add_child(lens)
	# The rim is drawn again on top so the content sits inside it.
	var rim := icon("ui_magnifier", height)
	rim.set_anchors_preset(Control.PRESET_FULL_RECT)
	rim.material = _rim_material()
	glass.add_child(rim)
	return glass


## Shows only the opaque rim/handle of the magnifier (not the glass) so the
## lens content stays visible under it.
static func _rim_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform vec2 center; uniform float radius;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 d = (UV - center) * vec2(1.0, TEXTURE_PIXEL_SIZE.x / TEXTURE_PIXEL_SIZE.y);
	COLOR = length(d) < radius * 0.97 ? vec4(c.rgb, c.a * 0.15) : c;
}"""
	m.shader = sh
	m.set_shader_parameter("center", LENS_CENTER)
	m.set_shader_parameter("radius", LENS_RADIUS)
	return m


## A hand-drawn wobbly ink line with a faint sage wash under it (section break).
static func divider(height: float = 10.0) -> Control:
	var c := _Divider.new()
	c.custom_minimum_size = Vector2(0, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


class _Divider extends Control:
	func _draw() -> void:
		var y := size.y * 0.5
		var pts := PackedVector2Array()
		var n := maxi(2, int(size.x / 12.0))
		for i in n + 1:
			var x := size.x * i / n
			pts.append(Vector2(x, y + sin(x * 0.07) * 1.2 + sin(x * 0.23 + 1.3) * 0.6))
		draw_line(Vector2(6, y + 2), Vector2(size.x - 6, y + 2), Color(UiKit.SAGE_WASH, 0.9), 4.0)
		draw_polyline(pts, Color(UiKit.INK, 0.75), 1.6, true)


static func button(text: String, on_pressed: Callable, color: Color = ACCENT) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 52)
	if color != ACCENT:
		b.add_theme_stylebox_override("normal", _button_box(color))
		b.add_theme_stylebox_override("hover", _button_box(color.lightened(0.12)))
		b.add_theme_stylebox_override("pressed", _button_box(color.darkened(0.15), true))
	b.pressed.connect(on_pressed)
	return b


## Wrapping labels need a width from their container; pass wrap=false for
## labels inside HBoxes or free-floating ones, or they collapse to one column.
static func label(text: String, size: int = 19, color: Color = INK, wrap: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func panel(content: Control) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.add_child(content)
	return p


static func vbox(separation: int = 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	return v


static func hbox(separation: int = 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", separation)
	return h


## Full-screen dimmer with a centred panel; blocks map input while open.
## Scrolls when the panel is taller than the screen (phone in landscape).
static func modal(content: Control) -> Control:
	var root := ColorRect.new()
	root.color = Color(0.2, 0.14, 0.1, 0.4)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(scroll_center(panel(content)))
	return root


## Full-rect container that centres [param content] and scrolls vertically
## when it doesn't fit.
static func scroll_center(content: Control) -> Control:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Finger jitter on a button shouldn't turn the tap into a scroll.
	scroll.scroll_deadzone = 12
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	scroll.add_child(margin)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(center)
	center.add_child(content)
	return scroll


static func viewport_size() -> Vector2:
	return AppState.viewport_size()


## Content width for a panel: [param desired], or less so the panel (its
## padding and border, ~34) plus the screen margins (2 x 10) and
## [param margin] still fit on screen.
static func fit_width(desired: float, margin: float = 8.0) -> float:
	return minf(desired, viewport_size().x - 54.0 - margin)


## Row of buttons that wraps onto more lines on narrow screens.
static func button_row(buttons: Array, separation: int = 8) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", separation)
	flow.add_theme_constant_override("v_separation", separation)
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	for b: Control in buttons:
		flow.add_child(b)
	return flow


static func format_time(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d" % [s / 60, s % 60]
