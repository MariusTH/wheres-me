class_name MaskCanvas
extends RefCounted
## CPU stand-in for a CanvasItem. PlaceholderArt (and textured sprites) can
## draw into it exactly as they draw on screen; instead of pixels it records
## which of a fixed set of world-space sample points are covered by opaque
## paint (alpha >= MIN_ALPHA, so soft shadows don't count).
## Used by VisibilityChecker to measure how much of the hider shows.

const MIN_ALPHA := 0.5
const CELL := 8.0

var points: PackedVector2Array
var hit: PackedByteArray

var _cells: Dictionary = {}
var _base := Transform2D.IDENTITY
var _xf := Transform2D.IDENTITY

static var _images: Dictionary = {}


func _init(p_points: PackedVector2Array) -> void:
	points = p_points
	hit.resize(points.size())
	hit.fill(0)
	for i in points.size():
		var k := Vector2i(floori(points[i].x / CELL), floori(points[i].y / CELL))
		if not _cells.has(k):
			_cells[k] = PackedInt32Array()
		_cells[k].append(i)


## Next draw calls are relative to an object whose origin is [param world_pos].
func begin_object(world_pos: Vector2) -> void:
	_base = Transform2D(0.0, world_pos)
	_xf = Transform2D.IDENTITY


func covered_count() -> int:
	return hit.count(1)


func covered_points() -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in points.size():
		if hit[i] == 1:
			out.append(points[i])
	return out


# --- CanvasItem drawing API subset used by PlaceholderArt ------------------

func draw_set_transform(pos: Vector2, rotation: float = 0.0, scale: Vector2 = Vector2.ONE) -> void:
	_xf = Transform2D(rotation, scale, 0.0, pos)


func draw_rect(rect: Rect2, color: Color, filled: bool = true, width: float = -1.0, _antialiased: bool = false) -> void:
	if color.a < MIN_ALPHA:
		return
	if filled:
		_mark(rect, func(l: Vector2) -> bool: return rect.has_point(l))
	else:
		var c := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
		for i in 4:
			draw_line(c[i], c[(i + 1) % 4], color, width)


func draw_circle(center: Vector2, radius: float, color: Color, _filled: bool = true, _width: float = -1.0, _antialiased: bool = false) -> void:
	if color.a < MIN_ALPHA:
		return
	var r2 := radius * radius
	_mark(Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0), func(l: Vector2) -> bool: return l.distance_squared_to(center) <= r2)


func draw_colored_polygon(pts: PackedVector2Array, color: Color, _uvs: PackedVector2Array = PackedVector2Array(), _texture: Texture2D = null) -> void:
	if color.a < MIN_ALPHA or pts.size() < 3:
		return
	var box := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		box = box.expand(p)
	_mark(box, func(l: Vector2) -> bool: return Geometry2D.is_point_in_polygon(l, pts))


func draw_line(a: Vector2, b: Vector2, color: Color, width: float = -1.0, _antialiased: bool = false) -> void:
	if color.a < MIN_ALPHA:
		return
	var half := maxf(width, 1.0) / 2.0
	var box := Rect2(a, Vector2.ZERO).expand(b).grow(half)
	_mark(box, func(l: Vector2) -> bool: return Geometry2D.get_closest_point_to_segment(l, a, b).distance_to(l) <= half)


func draw_polyline(pts: PackedVector2Array, color: Color, width: float = -1.0, _antialiased: bool = false) -> void:
	for i in range(1, pts.size()):
		draw_line(pts[i - 1], pts[i], color, width)


func draw_arc(center: Vector2, radius: float, start: float, end: float, point_count: int, color: Color, width: float = -1.0, _antialiased: bool = false) -> void:
	var pts := PackedVector2Array()
	for i in point_count + 1:
		var a := lerpf(start, end, float(i) / float(point_count))
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	draw_polyline(pts, color, width)


func draw_texture(tex: Texture2D, pos: Vector2, modulate: Color = Color.WHITE) -> void:
	if modulate.a < MIN_ALPHA:
		return
	var img := _image_of(tex)
	if img == null:
		return
	var size := Vector2(img.get_width(), img.get_height())
	_mark(Rect2(pos, size), func(l: Vector2) -> bool:
		var px := Vector2i(l - pos)
		if px.x < 0 or px.y < 0 or px.x >= img.get_width() or px.y >= img.get_height():
			return false
		return img.get_pixelv(px).a >= MIN_ALPHA)


# --- internals ---------------------------------------------------------------

## Marks sample points inside [param local_box] (in current draw space) for
## which [param test] (given the point in draw space) returns true.
func _mark(local_box: Rect2, test: Callable) -> void:
	var full := _base * _xf
	var world_box := full * local_box
	var inv := full.affine_inverse()
	var c0 := Vector2i(floori(world_box.position.x / CELL), floori(world_box.position.y / CELL))
	var c1 := Vector2i(floori(world_box.end.x / CELL), floori(world_box.end.y / CELL))
	for cx in range(c0.x, c1.x + 1):
		for cy in range(c0.y, c1.y + 1):
			var bucket: Variant = _cells.get(Vector2i(cx, cy))
			if bucket == null:
				continue
			for i: int in bucket:
				if hit[i] == 0 and test.call(inv * points[i]):
					hit[i] = 1


static func _image_of(tex: Texture2D) -> Image:
	var key := tex.get_rid()
	if _images.has(key):
		return _images[key]
	var img := tex.get_image()
	if img and img.is_compressed():
		img.decompress()
	_images[key] = img
	return img
