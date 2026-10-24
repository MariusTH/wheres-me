class_name PlaceholderArt
extends RefCounted
## Code-drawn stand-in art in the target style: flat warm colours with a dark,
## slightly heavy outline. Used for any catalog asset without a "texture".
## All routines draw relative to the ground point (0, 0) with up = negative y.
## [code]ci[/code] is a CanvasItem when rendering, or a MaskCanvas when
## VisibilityChecker measures coverage with the very same drawing code.

const OUTLINE := Color("2b2230")
const OUTLINE_W := 1.6
const SHADOW := Color(0.12, 0.08, 0.16, 0.22)
const GLASS := Color("bfe3f0")
const WOOD := Color("9b6b43")
const STONE := Color("c9c2b8")
const METAL := Color("4a4f5c")


static func col(v: Variant, fallback: Color = Color.MAGENTA) -> Color:
	if v is String and v != "":
		return Color.html(v)
	return fallback


static func box(ci: Variant, r: Rect2, fill: Color, outline: bool = true) -> void:
	ci.draw_rect(r, fill)
	if outline:
		ci.draw_rect(r, OUTLINE, false, OUTLINE_W)


static func disc(ci: Variant, c: Vector2, radius: float, fill: Color, outline: bool = true) -> void:
	ci.draw_circle(c, radius, fill)
	if outline:
		ci.draw_arc(c, radius, 0.0, TAU, 20, OUTLINE, OUTLINE_W)


static func ellipse_points(c: Vector2, rx: float, ry: float, segments: int = 24) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * float(i) / float(segments)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


static func poly(ci: Variant, pts: PackedVector2Array, fill: Color, outline: bool = true) -> void:
	ci.draw_colored_polygon(pts, fill)
	if outline:
		var closed := pts.duplicate()
		closed.append(pts[0])
		ci.draw_polyline(closed, OUTLINE, OUTLINE_W)


static func blob(ci: Variant, c: Vector2, rx: float, ry: float, fill: Color, outline: bool = true) -> void:
	poly(ci, ellipse_points(c, rx, ry), fill, outline)


static func shadow(ci: Variant, c: Vector2, rx: float, ry: float) -> void:
	ci.draw_colored_polygon(ellipse_points(c, rx, ry, 18), SHADOW)


## Upper half-disc (a dome), used for hair and hats.
static func dome(ci: Variant, c: Vector2, r: float, fill: Color, outline: bool = true) -> void:
	var pts := PackedVector2Array()
	for i in 13:
		var a := PI + PI * float(i) / 12.0
		pts.append(c + Vector2(cos(a) * r, sin(a) * r))
	poly(ci, pts, fill, outline)


## Draws a catalog texture so that its "ground_point" pixel lands on (0, 0).
static func draw_grounded_texture(ci: Variant, tex: Texture2D, e: Dictionary, flip: bool, gp_field: String = "ground_point", height_field: String = "height_px") -> void:
	var size := tex.get_size()
	var gp := MapDefinition.vec2(e.get(gp_field, [size.x * 0.5, size.y]))
	var s := float(e.get(height_field, size.y)) / size.y
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(-s if flip else s, s))
	ci.draw_texture(tex, -gp)
	ci.draw_set_transform(Vector2.ZERO)


# --- Characters -------------------------------------------------------------

static func build_scale(look: Dictionary) -> Vector2:
	match String(look.get("build", "normal")):
		"tall":
			return Vector2(1.0, 1.12)
		"short":
			return Vector2(0.84, 0.82)
		"wide":
			return Vector2(1.18, 1.0)
	return Vector2.ONE


static func draw_character(ci: Variant, look: Dictionary, flip: bool, origin: Vector2 = Vector2.ZERO, scale: float = 1.0) -> void:
	var s := build_scale(look) * scale
	ci.draw_set_transform(origin, 0.0, Vector2(-s.x if flip else s.x, s.y))
	var skin := col(look.get("skin"), Color("f1c27d"))
	var shirt := col(look.get("shirt"), Color("4a7bd1"))
	var pants := col(look.get("pants"), Color("3a3f58"))
	var acc := String(look.get("accessory", "none"))
	var acc_col := col(look.get("acc_color"), Color("d63c3c"))

	shadow(ci, Vector2(0, -1), 13, 4)
	if acc == "backpack":
		box(ci, Rect2(-16, -42, 10, 20), acc_col)
	# Legs and shoes.
	box(ci, Rect2(-8, -21, 7, 20), pants)
	box(ci, Rect2(1, -21, 7, 20), pants)
	box(ci, Rect2(-9, -4, 8, 4), OUTLINE, false)
	box(ci, Rect2(1, -4, 8, 4), OUTLINE, false)
	# Torso (a coat runs down over the thighs).
	var torso := Rect2(-11, -42, 22, 30) if look.get("coat", false) else Rect2(-10, -42, 20, 23)
	box(ci, torso, shirt)
	_draw_pattern(ci, torso, look, pants)
	# Arms and hands.
	box(ci, Rect2(-14.5, -41, 5, 18), shirt)
	box(ci, Rect2(9.5, -41, 5, 18), shirt)
	disc(ci, Vector2(-12, -22), 2.8, skin)
	disc(ci, Vector2(12, -22), 2.8, skin)
	match acc:
		"scarf":
			box(ci, Rect2(-10, -44, 20, 5), acc_col)
			box(ci, Rect2(2, -41, 5, 13), acc_col)
		"bag":
			ci.draw_line(Vector2(-8, -42), Vector2(9, -24), OUTLINE, 1.5)
			box(ci, Rect2(6, -27, 9, 9), acc_col)
		"balloon":
			ci.draw_line(Vector2(12, -22), Vector2(16, -80), OUTLINE, 1.0)
			blob(ci, Vector2(16, -90), 9, 11, acc_col)
			ci.draw_circle(Vector2(13, -94), 2.5, Color(1, 1, 1, 0.6))
	# Head.
	disc(ci, Vector2(0, -50), 8.5, skin)
	_draw_hair(ci, look)
	ci.draw_circle(Vector2(3.2, -51), 1.1, OUTLINE)
	ci.draw_circle(Vector2(-2.2, -51), 1.1, OUTLINE)
	if look.get("glasses", false):
		ci.draw_arc(Vector2(-2.2, -51), 2.8, 0.0, TAU, 12, OUTLINE, 1.2)
		ci.draw_arc(Vector2(3.6, -51), 2.8, 0.0, TAU, 12, OUTLINE, 1.2)
	_draw_hat(ci, look)
	ci.draw_set_transform(Vector2.ZERO)


static func _draw_pattern(ci: Variant, torso: Rect2, look: Dictionary, pants: Color) -> void:
	var pc := col(look.get("pattern_color"), Color.WHITE)
	match String(look.get("pattern", "plain")):
		"stripes":
			var y := torso.position.y + 3.0
			while y < torso.end.y - 1.0:
				ci.draw_line(Vector2(torso.position.x + 1, y), Vector2(torso.end.x - 1, y), pc, 2.6)
				y += 6.0
			ci.draw_rect(torso, OUTLINE, false, OUTLINE_W)
		"dots":
			for p in [Vector2(-5, -37), Vector2(4, -34), Vector2(-3, -27), Vector2(5, -25)]:
				ci.draw_circle(p, 1.8, pc)
		"overalls":
			box(ci, Rect2(-7, -34, 14, 15), pants)
			ci.draw_line(Vector2(-6, -42), Vector2(-6, -34), pants, 2.5)
			ci.draw_line(Vector2(6, -42), Vector2(6, -34), pants, 2.5)


static func _draw_hair(ci: Variant, look: Dictionary) -> void:
	var hair := col(look.get("hair"), Color("3b2a1a"))
	match String(look.get("hair_style", "short")):
		"short":
			dome(ci, Vector2(0, -51), 9.0, hair)
		"long":
			box(ci, Rect2(-10, -52, 5, 16), hair)
			box(ci, Rect2(5, -52, 5, 16), hair)
			dome(ci, Vector2(0, -51), 9.5, hair)
		"bun":
			dome(ci, Vector2(0, -51), 9.0, hair)
			disc(ci, Vector2(0, -61), 4.5, hair)
		"ponytail":
			blob(ci, Vector2(-10, -46), 3.5, 7, hair)
			dome(ci, Vector2(0, -51), 9.0, hair)
		"curly":
			for p in [Vector2(-7, -53), Vector2(-3, -58), Vector2(3, -58), Vector2(7, -53), Vector2(0, -56)]:
				disc(ci, p, 4.0, hair)
		"spiky":
			poly(ci, PackedVector2Array([Vector2(-9, -50), Vector2(-8, -60), Vector2(-4, -56), Vector2(0, -63), Vector2(4, -56), Vector2(8, -60), Vector2(9, -50)]), hair)


static func _draw_hat(ci: Variant, look: Dictionary) -> void:
	var hc := col(look.get("hat_color"), Color("d63c3c"))
	match String(look.get("hat", "none")):
		"cap":
			dome(ci, Vector2(0, -52), 9.5, hc)
			box(ci, Rect2(2, -54, 11, 3), hc)
		"beanie":
			dome(ci, Vector2(0, -52), 9.8, hc)
			box(ci, Rect2(-10, -54, 20, 4), hc.lightened(0.25))
			disc(ci, Vector2(0, -63), 3.6, Color.WHITE)
		"top":
			box(ci, Rect2(-7, -74, 14, 19), hc)
			box(ci, Rect2(-7, -60, 14, 3), Color("d63c3c"), false)
			box(ci, Rect2(-12, -57, 24, 3), hc)
		"sun":
			blob(ci, Vector2(0, -56), 15, 3.8, hc)
			dome(ci, Vector2(0, -57), 8.0, hc)
		"rain":
			blob(ci, Vector2(0, -55), 13, 4.2, hc)
			dome(ci, Vector2(0, -56), 9.5, hc)
		"chef":
			for p in [Vector2(-5, -66), Vector2(0, -70), Vector2(5, -66)]:
				disc(ci, p, 6.0, hc)
			box(ci, Rect2(-8, -62, 16, 7), hc)
		"party":
			poly(ci, PackedVector2Array([Vector2(-6, -57), Vector2(6, -57), Vector2(0, -76)]), hc)
			disc(ci, Vector2(0, -77), 2.5, Color("f2c230"))
		"beret":
			blob(ci, Vector2(-2, -58), 10, 4.5, hc)


# --- Props ------------------------------------------------------------------

static func draw_prop(ci: Variant, key: String, e: Dictionary, flip: bool) -> void:
	var p: Dictionary = e.get("params", {})
	if flip:
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1, 1))
	match String(e.get("draw", key)):
		"bench":
			shadow(ci, Vector2(0, -2), 28, 6)
			box(ci, Rect2(-24, -10, 3, 10), METAL)
			box(ci, Rect2(21, -10, 3, 10), METAL)
			box(ci, Rect2(-26, -16, 52, 6), WOOD)
			box(ci, Rect2(-26, -28, 52, 6), WOOD)
		"bin":
			shadow(ci, Vector2(0, -1), 10, 3)
			box(ci, Rect2(-8, -22, 16, 22), Color("3f7f52"))
			box(ci, Rect2(-9.5, -25, 19, 4), Color("2f5f3e"))
		"planter":
			shadow(ci, Vector2(0, -1), 16, 4)
			for b in [Vector2(-8, -18), Vector2(6, -19), Vector2(0, -24)]:
				disc(ci, b, 8.0, Color("5e9e4a"))
			for f in [Vector2(-9, -21), Vector2(4, -26), Vector2(8, -17)]:
				ci.draw_circle(f, 2.0, Color("e85d8a"))
			box(ci, Rect2(-14, -12, 28, 12), Color("b5653a"))
		"lamp_post":
			shadow(ci, Vector2(0, -1), 7, 2.5)
			box(ci, Rect2(-2, -72, 4, 72), METAL)
			box(ci, Rect2(-5, -4, 10, 4), METAL)
			disc(ci, Vector2(0, -76), 6.0, Color("ffe08a"))
		"bike":
			shadow(ci, Vector2(0, -1), 18, 3)
			ci.draw_arc(Vector2(-12, -8), 7.5, 0.0, TAU, 16, OUTLINE, 2.0)
			ci.draw_arc(Vector2(12, -8), 7.5, 0.0, TAU, 16, OUTLINE, 2.0)
			ci.draw_polyline(PackedVector2Array([Vector2(-12, -8), Vector2(-3, -20), Vector2(8, -20), Vector2(12, -8)]), Color("d63c3c"), 2.5)
			ci.draw_line(Vector2(-3, -20), Vector2(0, -8), Color("d63c3c"), 2.5)
			ci.draw_line(Vector2(8, -20), Vector2(10, -25), OUTLINE, 2.0)
			box(ci, Rect2(-7, -24, 7, 3), OUTLINE, false)
		"sign_board":
			shadow(ci, Vector2(0, -1), 11, 3)
			poly(ci, PackedVector2Array([Vector2(-9, 0), Vector2(-6, -26), Vector2(6, -26), Vector2(9, 0)]), Color("3b3340"))
			poly(ci, PackedVector2Array([Vector2(-4, -19), Vector2(4, -19), Vector2(3, -12), Vector2(-3, -12)]), Color("f4efe6"), false)
			ci.draw_arc(Vector2(4.5, -16), 2.5, -PI / 2, PI / 2, 8, Color("f4efe6"), 1.2)
		"kiosk":
			shadow(ci, Vector2(0, -2), 36, 7)
			box(ci, Rect2(-30, -60, 60, 60), Color("e9d8b4"))
			box(ci, Rect2(-22, -48, 44, 22), GLASS)
			box(ci, Rect2(-30, -26, 60, 6), Color("b5653a"))
			_stripes(ci, Rect2(-34, -72, 68, 14), Color("2f6b4f"), Color("f4efe6"), 8.5)
		"food_cart":
			shadow(ci, Vector2(0, -1), 30, 5)
			ci.draw_line(Vector2(0, -36), Vector2(0, -64), OUTLINE, 2.0)
			box(ci, Rect2(-28, -34, 56, 26), Color("f4efe6"))
			box(ci, Rect2(-28, -34, 56, 6), Color("d63c3c"))
			disc(ci, Vector2(-16, -6), 6.5, METAL)
			disc(ci, Vector2(16, -6), 6.5, METAL)
			ci.draw_line(Vector2(28, -22), Vector2(38, -28), OUTLINE, 2.0)
			_umbrella(ci, Vector2(0, -66), 26, 10, Color("f2c230"), Color("d63c3c"))
		"dog":
			shadow(ci, Vector2(0, -1), 11, 3)
			ci.draw_line(Vector2(-8, -6), Vector2(-8, 0), OUTLINE, 2.0)
			ci.draw_line(Vector2(6, -6), Vector2(6, 0), OUTLINE, 2.0)
			ci.draw_line(Vector2(-11, -10), Vector2(-16, -16), Color("a0663a"), 2.5)
			blob(ci, Vector2(-1, -9), 11, 5, Color("a0663a"))
			disc(ci, Vector2(10, -14), 5.0, Color("a0663a"))
			blob(ci, Vector2(8, -17), 2, 4, Color("6b4226"), false)
			ci.draw_circle(Vector2(14.5, -13), 1.4, OUTLINE)
		"cafe_table":
			shadow(ci, Vector2(0, -1), 24, 5)
			box(ci, Rect2(-22, -18, 9, 18), Color("d63c3c"))
			box(ci, Rect2(13, -18, 9, 18), Color("d63c3c"))
			box(ci, Rect2(-1.5, -16, 3, 16), METAL)
			blob(ci, Vector2(0, -17), 12, 4, Color("f4efe6"))
			ci.draw_circle(Vector2(-3, -19), 2.0, Color("8b5a2b"))
		"parasol_table":
			shadow(ci, Vector2(0, -1), 26, 6)
			box(ci, Rect2(-22, -18, 9, 18), Color("3d6fd1"))
			box(ci, Rect2(13, -18, 9, 18), Color("3d6fd1"))
			box(ci, Rect2(-1.5, -60, 3, 60), METAL)
			blob(ci, Vector2(0, -17), 12, 4, Color("f4efe6"))
		"hydrant":
			shadow(ci, Vector2(0, -1), 7, 2)
			box(ci, Rect2(-5, -16, 10, 16), Color("d63c3c"))
			dome(ci, Vector2(0, -16), 5.0, Color("d63c3c"))
			box(ci, Rect2(-8, -11, 16, 3), Color("b02a2a"))
		"mailbox":
			shadow(ci, Vector2(0, -1), 8, 2)
			box(ci, Rect2(-1.5, -14, 3, 14), METAL)
			box(ci, Rect2(-8, -30, 16, 16), Color("d63c3c"))
			dome(ci, Vector2(0, -30), 8.0, Color("d63c3c"))
			box(ci, Rect2(-5, -25, 10, 2), OUTLINE, false)
		"flower_bed":
			blob(ci, Vector2(0, -6), 30, 12, Color("8b6a45"))
			var flower_cols := [Color("e85d8a"), Color("f2c230"), Color("ffffff"), Color("9b59b6")]
			for i in 14:
				var a := float(i) * 2.39996
				var rr := 4.0 + float(i % 5) * 4.6
				ci.draw_circle(Vector2(cos(a) * rr * 1.1, -6 + sin(a) * rr * 0.4), 3.0, flower_cols[i % 4])
		"bush":
			shadow(ci, Vector2(0, -1), 18, 4)
			for b in [Vector2(-9, -10), Vector2(9, -10), Vector2(0, -17)]:
				disc(ci, b, 10.0, Color("4f8a3f"))
			ci.draw_circle(Vector2(-3, -20), 3.0, Color("6fae55"))
		"crates":
			shadow(ci, Vector2(0, -1), 16, 4)
			box(ci, Rect2(-15, -14, 15, 14), WOOD)
			box(ci, Rect2(0, -14, 15, 14), WOOD)
			box(ci, Rect2(-8, -28, 15, 14), WOOD)
			for f in [Vector2(-11, -16), Vector2(-6, -16), Vector2(4, -16), Vector2(9, -16)]:
				ci.draw_circle(f, 3.0, Color("f08a24"))
		"car":
			var cc := col(p.get("color"), Color("d63c3c"))
			shadow(ci, Vector2(0, -1), 38, 5)
			poly(ci, PackedVector2Array([Vector2(-22, -22), Vector2(-14, -36), Vector2(16, -36), Vector2(26, -22)]), cc)
			poly(ci, PackedVector2Array([Vector2(-17, -23), Vector2(-12, -33), Vector2(0, -33), Vector2(0, -23)]), GLASS)
			poly(ci, PackedVector2Array([Vector2(3, -23), Vector2(3, -33), Vector2(14, -33), Vector2(21, -23)]), GLASS)
			box(ci, Rect2(-36, -24, 72, 16), cc)
			box(ci, Rect2(30, -20, 6, 4), Color("ffe08a"), false)
			disc(ci, Vector2(-22, -7), 6.5, OUTLINE)
			disc(ci, Vector2(22, -7), 6.5, OUTLINE)
			ci.draw_circle(Vector2(-22, -7), 2.5, METAL)
			ci.draw_circle(Vector2(22, -7), 2.5, METAL)
		"fountain":
			shadow(ci, Vector2(0, 0), 86, 30)
			blob(ci, Vector2(0, -6), 82, 34, STONE)
			blob(ci, Vector2(0, -10), 70, 26, Color("6fb6d6"))
			for r in [Vector2(-30, -12), Vector2(26, -6), Vector2(0, -20)]:
				ci.draw_arc(r, 10.0, PI * 1.1, PI * 1.9, 8, Color(1, 1, 1, 0.6), 1.5)
			box(ci, Rect2(-8, -64, 16, 54), STONE)
			blob(ci, Vector2(0, -64), 22, 7, STONE)
			for dx in [-14.0, 14.0]:
				ci.draw_polyline(PackedVector2Array([Vector2(0, -78), Vector2(dx * 0.6, -82), Vector2(dx, -70), Vector2(dx * 1.3, -50)]), Color("bfe3f0"), 2.0)
			ci.draw_line(Vector2(0, -66), Vector2(0, -84), Color("bfe3f0"), 3.0)
		"statue":
			shadow(ci, Vector2(0, -1), 24, 6)
			box(ci, Rect2(-20, -32, 40, 32), STONE)
			box(ci, Rect2(-23, -36, 46, 6), STONE.darkened(0.1))
			ci.draw_set_transform(Vector2.ZERO)
			draw_character(ci, {"skin": "#a7b0a0", "hair": "#8c9688", "shirt": "#a7b0a0", "pants": "#8c9688", "hat": "top", "hat_color": "#8c9688", "coat": true}, flip, Vector2(0, -36), 1.15)
		"easel":
			ci.draw_line(Vector2(-10, 0), Vector2(0, -50), WOOD, 2.5)
			ci.draw_line(Vector2(10, 0), Vector2(0, -50), WOOD, 2.5)
			ci.draw_line(Vector2(0, -40), Vector2(3, 0), WOOD, 2.0)
			box(ci, Rect2(-13, -50, 26, 20), Color("fffaf0"))
			ci.draw_circle(Vector2(-5, -42), 4.0, Color("6fb6d6"))
			ci.draw_circle(Vector2(4, -38), 3.5, Color("5e9e4a"))
			ci.draw_circle(Vector2(5, -45), 2.5, Color("f2c230"))
		"duck":
			blob(ci, Vector2(0, -3), 7, 4, Color("fffaf0"))
			disc(ci, Vector2(5, -8), 3.2, Color("2f6b4f"))
			poly(ci, PackedVector2Array([Vector2(8, -8), Vector2(12, -7), Vector2(8, -6)]), Color("f08a24"), false)
		"pigeon":
			blob(ci, Vector2(0, -4), 5.5, 3.5, Color("8a8f99"))
			disc(ci, Vector2(4.5, -7), 2.4, Color("6b6f7a"))
			ci.draw_line(Vector2(6.5, -7), Vector2(8.5, -6.5), Color("f08a24"), 1.2)
		"cat_in_tree":
			blob(ci, Vector2(0, -104), 8, 5, Color("2b2230"), false)
			disc(ci, Vector2(7, -110), 4.5, Color("2b2230"), false)
			poly(ci, PackedVector2Array([Vector2(4, -113), Vector2(5, -118), Vector2(7, -114)]), Color("2b2230"), false)
			poly(ci, PackedVector2Array([Vector2(8, -114), Vector2(10, -118), Vector2(11, -113)]), Color("2b2230"), false)
			ci.draw_circle(Vector2(6, -111), 1.0, Color("f2c230"))
			ci.draw_circle(Vector2(9, -111), 1.0, Color("f2c230"))
			ci.draw_line(Vector2(-7, -104), Vector2(-12, -94), Color("2b2230"), 2.0)
		"tree_round", "tree_pine":
			shadow(ci, Vector2(0, -1), 34, 10)
			box(ci, Rect2(-5, -48, 10, 48), Color("7a5232"))
		"stall":
			var sc := col(p.get("color"), Color("d63c3c"))
			shadow(ci, Vector2(0, -1), 66, 10)
			box(ci, Rect2(-58, -96, 4, 70), WOOD)
			box(ci, Rect2(54, -96, 4, 70), WOOD)
			box(ci, Rect2(-60, -30, 120, 30), WOOD.lightened(0.15))
			box(ci, Rect2(-60, -30, 120, 6), sc)
			var goods: Array = p.get("goods", ["#f08a24"])
			for i in 9:
				disc(ci, Vector2(-48 + i * 12, -34), 5.0, col(goods[i % goods.size()]))
		"building":
			_draw_building(ci, p)
		_:
			box(ci, Rect2(-10, -20, 20, 20), Color.MAGENTA)
	ci.draw_set_transform(Vector2.ZERO)


## Parts drawn on the canopy layer, above every y-sorted character.
static func draw_canopy(ci: Variant, key: String, e: Dictionary, flip: bool) -> void:
	var p: Dictionary = e.get("params", {})
	if flip:
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1, 1))
	match String(e.get("draw", key)):
		"tree_round":
			var leaf := col(p.get("leaf"), Color("5e9e4a"))
			for b in [Vector2(-22, -74), Vector2(22, -76), Vector2(0, -88), Vector2(-14, -104), Vector2(14, -104)]:
				disc(ci, b, 26.0, leaf)
			ci.draw_circle(Vector2(-10, -100), 10.0, leaf.lightened(0.25))
			ci.draw_circle(Vector2(12, -82), 6.0, leaf.lightened(0.18))
			if p.has("dots"):
				var dc := col(p["dots"])
				for d in [Vector2(-20, -80), Vector2(6, -96), Vector2(20, -72), Vector2(-4, -76), Vector2(16, -106), Vector2(-24, -100)]:
					ci.draw_circle(d, 2.4, dc)
		"tree_pine":
			var leaf := col(p.get("leaf"), Color("3f7f52"))
			for tier in [[-50.0, 30.0, 36.0], [-74.0, 25.0, 34.0], [-96.0, 19.0, 30.0]]:
				poly(ci, PackedVector2Array([Vector2(-tier[1], tier[0]), Vector2(tier[1], tier[0]), Vector2(0, tier[0] - tier[2])]), leaf)
		"parasol_table":
			_umbrella(ci, Vector2(0, -62), 32, 12, Color("f4efe6"), Color("3d6fd1"))
		"stall":
			var sc := col(p.get("color"), Color("d63c3c"))
			_stripes(ci, Rect2(-66, -100, 132, 26), sc, Color("f4efe6"), 12.0)
			for i in 11:
				var cx := -60.0 + float(i) * 12.0
				ci.draw_circle(Vector2(cx, -74), 6.0, sc if i % 2 == 0 else Color("f4efe6"))
				ci.draw_arc(Vector2(cx, -74), 6.0, 0.0, PI, 8, OUTLINE, OUTLINE_W)
	ci.draw_set_transform(Vector2.ZERO)


static func _stripes(ci: Variant, r: Rect2, a: Color, b: Color, stripe_w: float) -> void:
	var x := r.position.x
	var i := 0
	while x < r.end.x:
		var w := minf(stripe_w, r.end.x - x)
		ci.draw_rect(Rect2(x, r.position.y, w, r.size.y), a if i % 2 == 0 else b)
		x += stripe_w
		i += 1
	ci.draw_rect(r, OUTLINE, false, OUTLINE_W)


static func _umbrella(ci: Variant, c: Vector2, rx: float, ry: float, a: Color, b: Color) -> void:
	var segs := 8
	for i in segs:
		var a0 := PI + PI * float(i) / float(segs)
		var a1 := PI + PI * float(i + 1) / float(segs)
		var tri := PackedVector2Array([c + Vector2(0, -ry), c + Vector2(cos(a0) * rx, sin(a0) * ry * 0.3 + ry * 0.3), c + Vector2(cos(a1) * rx, sin(a1) * ry * 0.3 + ry * 0.3)])
		ci.draw_colored_polygon(tri, a if i % 2 == 0 else b)
	ci.draw_polyline(PackedVector2Array([c + Vector2(-rx, ry * 0.3), c + Vector2(0, -ry), c + Vector2(rx, ry * 0.3), c + Vector2(-rx, ry * 0.3)]), OUTLINE, OUTLINE_W)


static func _draw_building(ci: Variant, p: Dictionary) -> void:
	var w := float(p.get("width", 200))
	var h := float(p.get("height", 240))
	var wall := col(p.get("wall"), Color("ecc89f"))
	var roof := col(p.get("roof"), Color("a0522d"))
	var x0 := -w / 2.0
	shadow(ci, Vector2(0, 0), w * 0.52, 8)
	box(ci, Rect2(x0, -h, w, h), wall)
	# Slight hand-drawn brick hints.
	for i in 6:
		var by := -h + 40.0 + float(i) * 31.0
		var bx := x0 + 12.0 + fmod(float(i) * 47.0, w - 40.0)
		ci.draw_line(Vector2(bx, by), Vector2(bx + 14, by), wall.darkened(0.12), 1.5)
	box(ci, Rect2(x0 - 6, -h - 16, w + 12, 22), roof)
	box(ci, Rect2(x0 - 2, -h + 6, w + 4, 5), roof.darkened(0.15), false)
	# Upper floor windows.
	var cols := int(w / 60.0)
	var floors := int((h - 120.0) / 62.0)
	for row in floors:
		for c in cols:
			var wx := x0 + (w - float(cols) * 60.0) / 2.0 + float(c) * 60.0 + 14.0
			var wy := -h + 26.0 + float(row) * 62.0
			box(ci, Rect2(wx, wy, 32, 38), GLASS)
			ci.draw_line(Vector2(wx + 16, wy), Vector2(wx + 16, wy + 38), OUTLINE, 1.2)
			box(ci, Rect2(wx - 3, wy + 38, 38, 4), wall.darkened(0.2))
	var door_c := roof.darkened(0.2)
	if String(p.get("front", "shop")) == "shop":
		box(ci, Rect2(x0 + 12, -84, w / 2.0 - 34, 62), GLASS)
		box(ci, Rect2(22, -84, w / 2.0 - 34, 62), GLASS)
		box(ci, Rect2(x0 + 8, -22, w - 16, 6), wall.darkened(0.25))
		box(ci, Rect2(-15, -82, 30, 82), door_c)
		ci.draw_circle(Vector2(9, -40), 2.0, Color("f2c230"))
		var aw := Rect2(x0 + 6, -110, w - 12, 20)
		_stripes(ci, aw, col(p.get("awning")), col(p.get("awning2"), Color.WHITE), 14.0)
		var sx := aw.position.x
		var i := 0
		while sx < aw.end.x - 4:
			ci.draw_circle(Vector2(sx + 7, aw.end.y), 7.0, col(p.get("awning")) if i % 2 == 0 else col(p.get("awning2"), Color.WHITE))
			ci.draw_arc(Vector2(sx + 7, aw.end.y), 7.0, 0.0, PI, 8, OUTLINE, OUTLINE_W)
			sx += 14.0
			i += 1
		box(ci, Rect2(-34, -146, 68, 28), Color("fffaf0"))
		_draw_icon(ci, String(p.get("icon", "none")), Vector2(0, -132))
	else:
		box(ci, Rect2(-15, -70, 30, 70), door_c)
		ci.draw_circle(Vector2(9, -34), 2.0, Color("f2c230"))
		box(ci, Rect2(-20, -6, 40, 6), STONE)
		for wx in [x0 + 18.0, w / 2.0 - 58.0]:
			box(ci, Rect2(wx, -80, 40, 40), GLASS)
			ci.draw_line(Vector2(wx + 20, -80), Vector2(wx + 20, -40), OUTLINE, 1.2)
			box(ci, Rect2(wx - 3, -40, 46, 8), WOOD)
			for f in 4:
				ci.draw_circle(Vector2(wx + 5 + f * 10, -42), 3.2, [Color("e85d8a"), Color("f2c230")][f % 2])


## Simple pictogram for shop signs. Deliberately no text.
static func _draw_icon(ci: Variant, icon: String, c: Vector2) -> void:
	match icon:
		"bread":
			blob(ci, c, 14, 7, Color("d9a05b"))
			for dx in [-6.0, 0.0, 6.0]:
				ci.draw_line(c + Vector2(dx - 2, -4), c + Vector2(dx + 2, 4), OUTLINE, 1.2)
		"cup":
			box(ci, Rect2(c.x - 8, c.y - 7, 14, 14), Color("8b5a2b"))
			ci.draw_arc(c + Vector2(7, 0), 4.0, -PI / 2, PI / 2, 8, OUTLINE, 1.6)
		"flower":
			for i in 5:
				var a := TAU * float(i) / 5.0
				disc(ci, c + Vector2(cos(a), sin(a)) * 6.0, 4.0, Color("e85d8a"))
			disc(ci, c, 3.5, Color("f2c230"))
		"book":
			box(ci, Rect2(c.x - 12, c.y - 8, 12, 16), Color("4a3a6b"))
			box(ci, Rect2(c.x, c.y - 8, 12, 16), Color("7b4fa0"))
		"ball":
			disc(ci, c, 9.0, Color("d63c3c"))
			ci.draw_line(c + Vector2(-9, 0), c + Vector2(9, 0), Color.WHITE, 2.0)
		"apple":
			disc(ci, c + Vector2(0, 1), 8.0, Color("d63c3c"))
			blob(ci, c + Vector2(4, -9), 4, 2, Color("4f9a4a"))
		"note":
			disc(ci, c + Vector2(-4, 5), 4.0, OUTLINE)
			ci.draw_line(c + Vector2(-0.5, 5), c + Vector2(-0.5, -10), OUTLINE, 2.0)
			ci.draw_line(c + Vector2(-0.5, -10), c + Vector2(7, -6), OUTLINE, 2.0)
