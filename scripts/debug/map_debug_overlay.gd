class_name MapDebugOverlay
extends Node2D
## Developer overlay. F1 cycles: off -> zones/paths/blocked areas ->
## + object IDs and depth order -> off.

enum Level { OFF, SHAPES, LABELS }

const ZONE_COLOR := Color(0.2, 0.5, 1.0, 0.12)
const BLOCKED_COLOR := Color(1.0, 0.2, 0.2, 0.18)
const PATH_COLOR := Color(0.1, 0.8, 0.9, 0.9)
const LABEL_SIZE := 11

var level: Level = Level.OFF:
	set(value):
		level = value
		visible = level != Level.OFF
		queue_redraw()

var _map: MapDefinition
var _layout: TownLayout
var _town: TownController


func setup(map_def: MapDefinition, layout: TownLayout, town: TownController) -> void:
	_map = map_def
	_layout = layout
	_town = town
	z_index = 100
	level = level


func cycle() -> void:
	level = ((int(level) + 1) % 3) as Level


func _draw() -> void:
	if _map == null or level == Level.OFF:
		return
	var font := ThemeDB.fallback_font
	for z in _map.zones:
		draw_colored_polygon(z.polygon, ZONE_COLOR)
		var outline := z.polygon.duplicate()
		outline.append(z.polygon[0])
		draw_polyline(outline, Color(0.2, 0.4, 1.0, 0.8), 2.0)
		_label(font, z.bounds.position + Vector2(6, 16), "%s (%s) people=%d" % [z.id, z.kind, z.people], Color(0.1, 0.2, 0.7))
	for b in _map.blocked:
		if b.has("rect"):
			draw_rect(b["rect"], BLOCKED_COLOR)
			draw_rect(b["rect"], Color(0.9, 0.1, 0.1, 0.7), false, 2.0)
		else:
			draw_colored_polygon(PlaceholderArt.ellipse_points(b["center"], b["radii"].x, b["radii"].y, 32), BLOCKED_COLOR)
	for p in _map.paths:
		draw_polyline(p.points, PATH_COLOR, 3.0)
		for pt in p.points:
			draw_circle(pt, 5.0, PATH_COLOR)
		_label(font, p.points[0] + Vector2(8, -8), p.id, Color(0, 0.4, 0.5))
	if level == Level.LABELS:
		var nodes: Array[Node2D] = []
		for n in _town.world.get_children():
			nodes.append(n as Node2D)
		nodes.sort_custom(func(a: Node2D, b: Node2D) -> bool: return a.position.y < b.position.y)
		for i in nodes.size():
			var n := nodes[i]
			draw_circle(n.position, 2.5, Color.RED)
			_label(font, n.position + Vector2(5, 12), "#%d %s" % [i, n.name], Color(0.3, 0.05, 0.05))


func _label(font: Font, at: Vector2, text: String, color: Color) -> void:
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, 3, Color(1, 1, 1, 0.85))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, color)
