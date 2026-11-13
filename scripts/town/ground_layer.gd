class_name GroundLayer
extends Node2D
## Paints the flat ground (grass, pavements, roads, water, paths) from the map
## definition. Always drawn below every object.

const COLORS := {
	"grass": Color("9cc56f"),
	"pavement": Color("ddd3c4"),
	"plaza": Color("ead9bd"),
	"market": Color("d9c19b"),
	"road": Color("74707a"),
	"road_plain": Color("74707a"),
	"sand": Color("ecd7a0"),
	"soil": Color("9b7653"),
	"water": Color("6fb6d6"),
}

## World px covered by one repeat of a ground texture.
const TEXTURE_WORLD_SIZE := 128.0
## Storybook edges are found on a grid this fine (world px).
const EDGE_CELL := 8
const INK := Color(0.24, 0.16, 0.12, 0.7)
const KERB_STONE := Color("e9dfcc")
const KERB_WIDTH := 7.0
const KERB_FACE := Color("cbbfa9")
## Pigment that pools along the inside of each painted region, per type.
const POOL := {
	"grass": Color(0.24, 0.42, 0.16, 0.22),
	"pavement": Color(0.45, 0.36, 0.26, 0.16),
	"plaza": Color(0.55, 0.28, 0.18, 0.18),
	"market": Color(0.5, 0.3, 0.12, 0.18),
	"road": Color(0.12, 0.09, 0.12, 0.3),
}

var _map: MapDefinition
var _textures: Dictionary = {}
var _shadows: Array = []
## Isometric only: kerb lines (plan space) whose raised face shows on screen.
var _kerb_faces: Array = []
## Screen px a pavement stands above the road on isometric maps.
const KERB_HEIGHT := 6.0


func setup(map_def: MapDefinition) -> void:
	_map = map_def
	z_index = -10
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_textures.clear()
	if _map.ground_style != "":
		for type in ["grass", "road", "pavement", "plaza", "market"]:
			var path := "res://art/ground/ground_%s.png" % type
			if ResourceLoader.exists(path):
				_textures[type] = load(path)
	queue_redraw()


## Soft watercolour shadows under buildings, trees and props (storybook maps
## only). Purely cosmetic: the ground layer is never part of visibility.
func set_shadows(layout: TownLayout) -> void:
	_shadows.clear()
	if _map == null or _map.ground_style == "" or layout == null:
		return
	for o in layout.objects:
		var key := o.asset_key
		var kind := AssetCatalog.kind(key)
		if kind == "character" or AssetCatalog.texture(key) == null:
			continue
		var r := AssetCatalog.sprite_rect(key)
		var w := r.size.x * 0.5
		var p := o.world_position
		if AssetCatalog.entry(key).has("footprint"):
			var fp := MapDefinition.vec2(AssetCatalog.entry(key)["footprint"])
			_shadows.append({"p": p, "fp": fp})
			continue
		if kind == "tree":
			w = minf(r.size.x * 0.42, 60.0)
		else:
			w = minf(w * 0.9, 70.0)
		_shadows.append({"p": p, "w": w})
	queue_redraw()


## Tiles [param tex] over [param r] in world-aligned UVs, so neighbouring rects
## of the same type join without visible seams.
func _draw_textured(r: Rect2, tex: Texture2D) -> void:
	var scale := float(tex.get_width()) / TEXTURE_WORLD_SIZE
	draw_texture_rect_region(tex, r, Rect2(r.position * scale, r.size * scale))


func _draw() -> void:
	if _map == null:
		return
	# Isometric maps paint the ground on the plan, through the projection.
	draw_set_transform_matrix(_map.ground_transform)
	if _textures.has(_map.base_ground):
		_draw_textured(_map.plan_bounds, _textures[_map.base_ground])
	else:
		draw_rect(_map.plan_bounds, COLORS.get(_map.base_ground, COLORS["grass"]))
		if _map.base_ground == "grass":
			_draw_grass_tufts()
	for g in _map.ground:
		var type := String(g["type"])
		if g.has("ellipse"):
			var e: Array = g["ellipse"]
			_draw_water(Vector2(e[0], e[1]), float(e[2]), float(e[3]))
			continue
		var r := MapDefinition.rect2(g["rect"])
		var tex_type := "road" if type == "road_plain" else type
		if _textures.has(tex_type):
			_draw_textured(r, _textures[tex_type])
			continue
		match type:
			"road":
				_draw_road(r, true)
			"road_plain":
				_draw_road(r, false)
			"crosswalk":
				_draw_crosswalk(r)
			"plaza":
				_draw_tiles(r, COLORS["plaza"], 40.0, false)
			"market":
				_draw_tiles(r, COLORS["market"], 26.0, true)
			"pavement":
				_draw_tiles(r, COLORS["pavement"], 35.0, false)
			_:
				draw_rect(r, COLORS.get(type, Color.MAGENTA))
				draw_rect(r, Color(0, 0, 0, 0.12), false, 2.0)
	for path in _map.paths:
		if path.surface != "":
			_draw_path(path)
	if _map.ground_style != "":
		_draw_storybook_edges()
		draw_set_transform_matrix(Transform2D.IDENTITY)
		if _kerb_faces.size() > 0:
			_draw_kerb_faces()
		_draw_shadows()
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_shadows() -> void:
	for sh: Dictionary in _shadows:
		var p: Vector2 = sh["p"]
		if sh.has("fp"):
			# House plot: the footprint and its cast towards the lower right.
			var fp: Vector2 = sh["fp"]
			var l := p + Vector2(-fp.y, -fp.y * 0.5)
			var rr := p + Vector2(fp.x, -fp.x * 0.5)
			var tt := p + Vector2(fp.x - fp.y, -(fp.x + fp.y) * 0.5)
			var o := Vector2(34, 8)
			draw_colored_polygon(PackedVector2Array([l, p, p + o, rr + o, tt + o, tt]), Color(0.2, 0.14, 0.24, 0.16))
			continue
		var w: float = sh["w"]
		for i in 3:
			var k := 1.0 - i * 0.22
			draw_colored_polygon(PlaceholderArt.ellipse_points(p + Vector2(4, 1), w * k, w * 0.3 * k + 2.0, 20), Color(0.2, 0.14, 0.24, 0.1))


## Hand-inked outlines where two ground types meet, a kerb along every road,
## and pigment pooled along the inside of each region (like a watercolour wash
## drying darker at its edge). Found on a grid so merged rects need no care.
func _draw_storybook_edges() -> void:
	_kerb_faces.clear()
	var cols := ceili(_map.plan_bounds.size.x / EDGE_CELL)
	var rows := ceili(_map.plan_bounds.size.y / EDGE_CELL)
	var origin := _map.plan_bounds.position
	var names: Array[String] = [_surface(_map.base_ground)]
	var grid := PackedByteArray()
	grid.resize(cols * rows)
	grid.fill(0)
	for g in _map.ground:
		var t := _surface(String(g["type"]))
		if names.find(t) < 0:
			names.append(t)
		var id := names.find(t)
		if g.has("ellipse"):
			var e: Array = g["ellipse"]
			var c := Vector2(e[0], e[1])
			for y in rows:
				for x in cols:
					var q := (origin + Vector2(x + 0.5, y + 0.5) * EDGE_CELL - c) / Vector2(e[2], e[3])
					if q.length_squared() <= 1.0:
						grid[y * cols + x] = id
			continue
		var r := MapDefinition.rect2(g["rect"])
		var x0 := clampi(roundi((r.position.x - origin.x) / EDGE_CELL), 0, cols)
		var x1 := clampi(roundi((r.end.x - origin.x) / EDGE_CELL), 0, cols)
		var y0 := clampi(roundi((r.position.y - origin.y) / EDGE_CELL), 0, rows)
		var y1 := clampi(roundi((r.end.y - origin.y) / EDGE_CELL), 0, rows)
		for y in range(y0, y1):
			for x in range(x0, x1):
				grid[y * cols + x] = id
	# Runs of edge between cell rows (horizontal) and columns (vertical).
	for horizontal in [true, false]:
		var lines := rows if horizontal else cols
		var span := cols if horizontal else rows
		for l in range(1, lines):
			var start := -1
			var pair := Vector2i(-1, -1)
			for i in span + 1:
				var cur := Vector2i(-1, -1)
				if i < span:
					var a := grid[(l - 1) * cols + i] if horizontal else grid[i * cols + l - 1]
					var b := grid[l * cols + i] if horizontal else grid[i * cols + l]
					if a != b:
						cur = Vector2i(a, b)
				if cur != pair:
					if pair.x >= 0:
						_draw_edge(names[pair.x], names[pair.y], horizontal, l, start, i, origin)
					pair = cur
					start = i


## Same surface family for edges: plain road joins striped road seamlessly.
static func _surface(t: String) -> String:
	return "road" if t == "road_plain" else t


## Edge between surface [param a] (above / left) and [param b] (below /
## right) along grid line [param l], cells [param from]..[param to].
func _draw_edge(a: String, b: String, horizontal: bool, l: int, from: int, to: int, origin: Vector2) -> void:
	if a == "water" or b == "water":
		return
	var along := Vector2(1, 0) if horizontal else Vector2(0, 1)
	var normal := Vector2(0, 1) if horizontal else Vector2(1, 0)
	var p0 := origin + (along * from + normal * l) * EDGE_CELL
	var length := float(to - from) * EDGE_CELL
	var line := _wobbly(p0, along, normal, length)
	# Pooled pigment just inside each side.
	if POOL.has(a):
		_band(line, -normal, 7.0, POOL[a])
	if POOL.has(b):
		_band(line, normal, 7.0, POOL[b])
	if a == "road" or b == "road":
		var out := normal if a == "road" else -normal  # from road towards the kerb side
		var inner := _offset(line, out * KERB_WIDTH)
		var kerb := line.duplicate()
		var rev := inner.duplicate()
		rev.reverse()
		kerb.append_array(rev)
		draw_colored_polygon(kerb, KERB_STONE)
		_band(line, -out, 10.0, Color(0.1, 0.07, 0.12, 0.22))
		draw_polyline(inner, INK, 1.5)
		# Isometric: a kerb faces the viewer when the road lies towards plan
		# +x or +y (down the screen) from it.
		if _map.ground_transform != Transform2D.IDENTITY and (out.x < 0.0 or out.y < 0.0):
			_kerb_faces.append(line)
	draw_polyline(line, INK, 2.0)


## Points along a straight edge nudged by smooth deterministic noise of the
## world position, so the line looks drawn by hand. Ends stay put so runs meet.
func _wobbly(p0: Vector2, along: Vector2, normal: Vector2, length: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := maxi(1, ceili(length / 14.0))
	for i in n + 1:
		var p := p0 + along * (length * i / n)
		var t := p.dot(along)
		var k := 0.0 if (i == 0 or i == n) else 1.0
		var off := (sin(t * 0.045 + p.dot(normal) * 0.031) * 1.4 + sin(t * 0.13 + 1.7) * 0.7) * k
		pts.append(p + normal * off)
	return pts


static func _offset(line: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in line:
		out.append(p + by)
	return out


func _band(line: PackedVector2Array, towards: Vector2, width: float, color: Color) -> void:
	var poly := line.duplicate()
	var rev := _offset(line, towards * width)
	rev.reverse()
	poly.append_array(rev)
	draw_colored_polygon(poly, color)


## Decorative only: seeded from the map id, never affects gameplay data.
func _draw_grass_tufts() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = DetHash.fnv1a_32(_map.map_id + ":grass")
	var tuft := COLORS["grass"].darkened(0.14) as Color
	for i in 900:
		var p := _map.plan_bounds.position + Vector2(rng.randf_range(0, _map.plan_bounds.size.x), rng.randf_range(0, _map.plan_bounds.size.y))
		draw_line(p, p + Vector2(-3, -6), tuft, 1.5)
		draw_line(p, p + Vector2(3, -6), tuft, 1.5)


func _draw_tiles(r: Rect2, base: Color, step: float, offset_rows: bool) -> void:
	draw_rect(r, base)
	var line := base.darkened(0.08)
	var y := r.position.y + step
	var row := 0
	while y < r.end.y:
		draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), line, 1.0)
		y += step
	var x := r.position.x + step
	while x < r.end.x:
		if offset_rows:
			var yy := r.position.y
			row = 0
			while yy < r.end.y:
				var sx := x + (step * 0.5 if row % 2 == 1 else 0.0)
				if sx < r.end.x:
					draw_line(Vector2(sx, yy), Vector2(sx, minf(yy + step, r.end.y)), line, 1.0)
				yy += step
				row += 1
		else:
			draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), line, 1.0)
		x += step
	draw_rect(r, base.darkened(0.15), false, 2.0)


func _draw_road(r: Rect2, dashes: bool) -> void:
	draw_rect(r, COLORS["road"])
	if not dashes:
		return
	var dash := Color("f4efe6")
	if r.size.x >= r.size.y:
		var cy := r.get_center().y
		var x := r.position.x + 10.0
		while x < r.end.x:
			draw_line(Vector2(x, cy), Vector2(minf(x + 34.0, r.end.x), cy), dash, 4.0)
			x += 70.0
	else:
		var cx := r.get_center().x
		var y := r.position.y + 10.0
		while y < r.end.y:
			draw_line(Vector2(cx, y), Vector2(cx, minf(y + 34.0, r.end.y)), dash, 4.0)
			y += 70.0


## Zebra bars run parallel to the traffic, i.e. across the crossing's long axis.
func _draw_crosswalk(r: Rect2) -> void:
	var bar := Color("f4efe6")
	if r.size.y > r.size.x:
		var y := r.position.y + 6.0
		while y + 10.0 < r.end.y:
			draw_rect(Rect2(r.position.x, y, r.size.x, 11.0), bar)
			y += 22.0
	else:
		var x := r.position.x + 6.0
		while x + 10.0 < r.end.x:
			draw_rect(Rect2(x, r.position.y, 11.0, r.size.y), bar)
			x += 22.0


func _draw_water(c: Vector2, rx: float, ry: float) -> void:
	draw_colored_polygon(PlaceholderArt.ellipse_points(c, rx + 10.0, ry + 8.0, 40), Color("c9c2b8"))
	draw_colored_polygon(PlaceholderArt.ellipse_points(c, rx, ry, 40), COLORS["water"])
	draw_colored_polygon(PlaceholderArt.ellipse_points(c + Vector2(-20, -10), rx * 0.7, ry * 0.6, 32), COLORS["water"].lightened(0.12))
	var outline := PlaceholderArt.ellipse_points(c, rx, ry, 40)
	outline.append(outline[0])
	draw_polyline(outline, PlaceholderArt.OUTLINE, 2.0)
	for o in [Vector2(-120, 20), Vector2(60, -40), Vector2(150, 40), Vector2(-40, 60)]:
		draw_arc(c + o, 14.0, PI * 1.15, PI * 1.85, 8, Color(1, 1, 1, 0.55), 2.0)


func _draw_path(path: MapPath) -> void:
	var base: Color = COLORS.get(path.surface, COLORS["sand"])
	var edge := base.darkened(0.18)
	draw_polyline(path.points, edge, path.width + 6.0)
	for p in path.points:
		draw_circle(p, (path.width + 6.0) / 2.0, edge)
	draw_polyline(path.points, base, path.width)
	for p in path.points:
		draw_circle(p, path.width / 2.0, base)


## Isometric: the side of the kerb stone shows below every kerb line that
## faces the viewer, so pavements read as raised above the road.
func _draw_kerb_faces() -> void:
	var xf := _map.ground_transform
	var down := Vector2(0, KERB_HEIGHT)
	for line: PackedVector2Array in _kerb_faces:
		var top := PackedVector2Array()
		for p in line:
			top.append(xf * p)
		var bottom := _offset(top, down)
		var poly := top.duplicate()
		var rev := bottom.duplicate()
		rev.reverse()
		poly.append_array(rev)
		draw_colored_polygon(poly, KERB_FACE)
		draw_polyline(bottom, INK, 1.5)
