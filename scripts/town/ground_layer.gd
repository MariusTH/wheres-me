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
	# Nature museum.
	"wall": Color("6b5a52"),
	"marble": Color("efe6d6"),
	"parquet": Color("c99a64"),
	"carpet": Color("b84a4a"),
	"stone": Color("cfc7ba"),
}

var _map: MapDefinition


func setup(map_def: MapDefinition) -> void:
	_map = map_def
	z_index = -10
	queue_redraw()


func _draw() -> void:
	if _map == null:
		return
	draw_rect(_map.world_bounds, COLORS.get(_map.base_ground, COLORS["grass"]))
	if _map.base_ground == "grass":
		_draw_grass_tufts()
	for g in _map.ground:
		var type := String(g["type"])
		if g.has("ellipse"):
			var e: Array = g["ellipse"]
			_draw_water(Vector2(e[0], e[1]), float(e[2]), float(e[3]))
			continue
		var r := MapDefinition.rect2(g["rect"])
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
			"marble":
				_draw_checker(r, COLORS["marble"], COLORS["marble"].darkened(0.1), 48.0)
			"parquet":
				_draw_tiles(r, COLORS["parquet"], 18.0, true)
			"stone":
				_draw_tiles(r, COLORS["stone"], 60.0, true)
			"carpet":
				_draw_carpet(r)
			"wall":
				_draw_wall(r)
			_:
				draw_rect(r, COLORS.get(type, Color.MAGENTA))
				draw_rect(r, Color(0, 0, 0, 0.12), false, 2.0)
	for path in _map.paths:
		if path.surface != "":
			_draw_path(path)


## Decorative only: seeded from the map id, never affects gameplay data.
func _draw_grass_tufts() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = DetHash.fnv1a_32(_map.map_id + ":grass")
	var tuft := COLORS["grass"].darkened(0.14) as Color
	for i in 900:
		var p := Vector2(rng.randf_range(0, _map.world_bounds.size.x), rng.randf_range(0, _map.world_bounds.size.y))
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


func _draw_checker(r: Rect2, a: Color, b: Color, step: float) -> void:
	draw_rect(r, a)
	var row := 0
	var y := r.position.y
	while y < r.end.y:
		var x := r.position.x + (step if row % 2 == 1 else 0.0)
		while x < r.end.x:
			draw_rect(Rect2(x, y, minf(step, r.end.x - x), minf(step, r.end.y - y)), b)
			x += step * 2.0
		y += step
		row += 1
	draw_rect(r, a.darkened(0.25), false, 2.0)


## Gift-shop rug: plain field with a gold border.
func _draw_carpet(r: Rect2) -> void:
	draw_rect(r, COLORS["carpet"])
	draw_rect(r.grow(-10.0), Color("e2b84a"), false, 4.0)
	draw_rect(r.grow(-18.0), Color("e2b84a"), false, 1.5)


## Walls seen from above: dark top with a lighter front edge along the bottom.
func _draw_wall(r: Rect2) -> void:
	draw_rect(r, COLORS["wall"])
	if r.size.x >= r.size.y:
		draw_rect(Rect2(r.position.x, r.end.y - 8.0, r.size.x, 8.0), COLORS["wall"].lightened(0.25))
	draw_rect(r, PlaceholderArt.OUTLINE, false, 2.0)


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
