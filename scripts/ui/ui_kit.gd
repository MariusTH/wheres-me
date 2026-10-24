class_name UiKit
extends RefCounted
## Shared "Where's Me" picture-book theme and widget helpers: red and white
## stripes, cream paper panels, ink outlines, a chunky display font, and the
## painted HUD art in art/ui (magnifier, stopwatch, banner).

const INK := Color("2b2230")
const PAPER := Color("fbf3df")
const ACCENT := Color("d7262e")
const STRIPE := Color("fffaf0")
const GOOD := Color("2f9e4a")
const BAD := Color("c73a3a")
const MUTED := Color("6b6474")
const DISPLAY_FONT_PATH := "res://art/fonts/LuckiestGuy-Regular.ttf"
const UI_ART := "res://art/ui/%s.png"
## Cream middle of ui_banner.png as fractions of the image (text goes here).
const BANNER_TEXT_AREA := Rect2(0.2, 0.18, 0.6, 0.42)
## Lens of ui_magnifier.png: centre and radius as fractions of the image width/height.
const LENS_CENTER := Vector2(0.5, 0.255)
const LENS_RADIUS := 0.44

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
	t.set_color("font_color", "Button", Color.WHITE)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.6))
	t.set_stylebox("normal", "Button", _button_box(ACCENT))
	t.set_stylebox("hover", "Button", _button_box(ACCENT.lightened(0.12)))
	t.set_stylebox("pressed", "Button", _button_box(ACCENT.darkened(0.15), true))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("disabled", "Button", _button_box(Color("b8b0a8")))
	t.set_color("font_outline_color", "Button", INK)
	t.set_constant("outline_size", "Button", 4)
	var paper := _flat(PAPER, 14, INK, 3)
	paper.border_width_top = 8
	paper.border_color = INK
	paper.shadow_color = Color(0.17, 0.13, 0.19, 0.35)
	paper.shadow_size = 0
	paper.shadow_offset = Vector2(4, 5)
	t.set_stylebox("panel", "PanelContainer", paper)
	t.set_stylebox("normal", "TextEdit", _flat(Color.WHITE, 8, Color("c9c2b8"), 2))
	t.set_stylebox("read_only", "TextEdit", _flat(Color("f4efe6"), 8, Color("c9c2b8"), 2))
	t.set_stylebox("focus", "TextEdit", _flat(Color.WHITE, 8, ACCENT, 2))
	t.set_color("font_color", "TextEdit", INK)
	t.set_color("font_readonly_color", "TextEdit", INK)
	t.set_font_size("font_size", "TextEdit", 15)
	t.set_stylebox("panel", "ItemList", _flat(Color.WHITE, 8, Color("c9c2b8"), 2))
	t.set_color("font_color", "ItemList", INK)
	t.set_stylebox("normal", "LineEdit", _flat(Color.WHITE, 8, Color("c9c2b8"), 2))
	t.set_color("font_color", "LineEdit", INK)
	t.set_stylebox("normal", "SpinBox", _flat(Color.WHITE, 8, Color("c9c2b8"), 2))
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


## Chunky picture-book button: ink outline and a thicker bottom edge that
## "presses in".
static func _button_box(bg: Color, pressed: bool = false) -> StyleBoxFlat:
	var s := _flat(bg, 12, INK, 3)
	s.border_width_bottom = 3 if pressed else 6
	s.content_margin_top = 10 if pressed else 7
	return s


static func display_font() -> Font:
	if _display_font == null:
		_display_font = load(DISPLAY_FONT_PATH) as Font
	return _display_font


static func ui_texture(key: String) -> Texture2D:
	var path := UI_ART % key
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## Big outlined headline in the display font.
static func title(text: String, size: int = 40, color: Color = Color.WHITE) -> Label:
	var l := label(text, size, color, false)
	l.add_theme_font_override("font", display_font())
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", maxi(6, size / 5))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Luckiest Guy's capitals rise above the font's reported ascent; give the
	# label extra height and sit the text at the bottom so nothing pokes out
	# over the panel border above it.
	l.custom_minimum_size.y = size * 1.3
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return l


## Striped ribbon banner with [param text] on its cream middle.
static func banner(text: String, width: float, size: int = 34) -> Control:
	var tex := ui_texture("ui_banner")
	if tex == null:
		return title(text, size, ACCENT)
	var root := TextureRect.new()
	root.texture = tex
	root.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	root.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	root.custom_minimum_size = Vector2(width, width * tex.get_height() / tex.get_width())
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Shrink long text ("Find the baby T-rex!") to fit the cream middle.
	var room := width * BANNER_TEXT_AREA.size.x * 0.9
	while size > 14 and display_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > room:
		size -= 1
	var l := title(text, size, ACCENT)
	l.add_theme_constant_override("outline_size", 0)
	l.custom_minimum_size = Vector2.ZERO
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.anchor_left = BANNER_TEXT_AREA.position.x
	l.anchor_top = BANNER_TEXT_AREA.position.y
	l.anchor_right = BANNER_TEXT_AREA.end.x
	l.anchor_bottom = BANNER_TEXT_AREA.end.y
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.clip_text = false
	root.add_child(l)
	return root


## Painted icon (magnifier, stopwatch, hat) at [param height] px.
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
	round_box.bg_color = Color("eaf4f6")
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
	COLOR = length(d) < radius * 0.93 ? vec4(c.rgb, c.a * 0.18) : c;
}"""
	m.shader = sh
	m.set_shader_parameter("center", LENS_CENTER)
	m.set_shader_parameter("radius", LENS_RADIUS)
	return m


## Red-and-white candy stripes (decorative band).
static func stripes(height: float) -> Control:
	var c := _Stripes.new()
	c.custom_minimum_size = Vector2(0, height)
	c.clip_contents = true
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


class _Stripes extends Control:
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), UiKit.STRIPE)
		var w := size.y
		var x := -size.y
		while x < size.x:
			draw_colored_polygon(PackedVector2Array([Vector2(x, size.y), Vector2(x + w * 0.5, size.y), Vector2(x + w * 0.5 + size.y, 0), Vector2(x + size.y, 0)]), UiKit.ACCENT)
			x += w
		draw_rect(Rect2(Vector2.ZERO, size), UiKit.INK, false, 2.0)


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
	root.color = Color(0.1, 0.08, 0.14, 0.45)
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
