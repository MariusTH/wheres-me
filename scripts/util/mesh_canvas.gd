class_name MeshCanvas
extends RefCounted
## Records the CanvasItem drawing API subset that PlaceholderArt and
## GroundLayer use (like MaskCanvas does) into triangle meshes, so a person or
## the whole ground ends up as one draw call instead of hundreds. Shapes keep
## their order (later ones paint over earlier ones, same as on a canvas).
##
## Untextured shapes go into vertex-coloured meshes; draw_texture_rect_region
## goes into a mesh with UVs for that texture. Consecutive shapes with the same
## texture (or none) share a mesh, so the result is a short list of
## {"mesh": ArrayMesh, "texture": Texture2D or null} to replay with draw_mesh.
##
## Characters are cached per look (see character_mesh), so a crowd member and
## the hider's portrait never rebuild the same geometry twice.

## Circles get more segments as they grow, within these bounds.
const CIRCLE_MIN_SEGMENTS := 10
const CIRCLE_MAX_SEGMENTS := 40

var _xf := Transform2D.IDENTITY
var _ops: Array = []
var _tex: Texture2D = null
var _verts := PackedVector2Array()
var _cols := PackedColorArray()
var _uvs := PackedVector2Array()

static var _character_cache: Dictionary = {}


## One mesh for [param look] (flipped or not), cached. Drawn at the feet.
static func character_mesh(look: Dictionary, flip: bool) -> ArrayMesh:
	var key := "%s|%s" % [JSON.stringify(look), flip]
	var mesh: ArrayMesh = _character_cache.get(key)
	if mesh == null:
		var mc := MeshCanvas.new()
		PlaceholderArt.draw_character(mc, look, flip)
		var ops := mc.finish()
		mesh = ops[0]["mesh"] if not ops.is_empty() else ArrayMesh.new()
		_character_cache[key] = mesh
	return mesh


static func clear_cache() -> void:
	_character_cache.clear()


## Ends recording. Returns [{"mesh": ArrayMesh, "texture": Texture2D|null}].
func finish() -> Array:
	_flush()
	var out := _ops
	_ops = []
	return out


## Replays [param ops] (from finish) on [param ci].
static func replay(ci: CanvasItem, ops: Array) -> void:
	for op: Dictionary in ops:
		ci.draw_mesh(op["mesh"], op["texture"])


func _flush() -> void:
	if _verts.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_COLOR] = _cols
	if _tex != null:
		arrays[Mesh.ARRAY_TEX_UV] = _uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_ops.append({"mesh": mesh, "texture": _tex})
	_verts = PackedVector2Array()
	_cols = PackedColorArray()
	_uvs = PackedVector2Array()


func _use_texture(tex: Texture2D) -> void:
	if tex != _tex:
		_flush()
		_tex = tex


## Adds triangle (a, b, c) in local space.
func _tri(a: Vector2, b: Vector2, c: Vector2, color: Color) -> void:
	_verts.append(_xf * a)
	_verts.append(_xf * b)
	_verts.append(_xf * c)
	_cols.append(color)
	_cols.append(color)
	_cols.append(color)


# --- CanvasItem drawing API subset ------------------------------------------

func draw_set_transform(pos: Vector2, rotation: float = 0.0, scale: Vector2 = Vector2.ONE) -> void:
	_xf = Transform2D(rotation, scale, 0.0, pos)


func draw_set_transform_matrix(xf: Transform2D) -> void:
	_xf = xf


func draw_colored_polygon(pts: PackedVector2Array, color: Color, _uvs_in: PackedVector2Array = PackedVector2Array(), _texture: Texture2D = null) -> void:
	if pts.size() < 3:
		return
	_use_texture(null)
	var idx := Geometry2D.triangulate_polygon(pts)
	if idx.is_empty():
		# Self-intersecting outline: a fan is close enough for these shapes.
		for i in range(1, pts.size() - 1):
			_tri(pts[0], pts[i], pts[i + 1], color)
		return
	for i in range(0, idx.size(), 3):
		_tri(pts[idx[i]], pts[idx[i + 1]], pts[idx[i + 2]], color)


func draw_circle(center: Vector2, radius: float, color: Color, filled: bool = true, width: float = -1.0, _antialiased: bool = false) -> void:
	if not filled:
		draw_arc(center, radius, 0.0, TAU, _segments(radius) + 1, color, width)
		return
	_use_texture(null)
	var n := _segments(radius)
	var prev := center + Vector2(radius, 0)
	for i in range(1, n + 1):
		var a := TAU * float(i) / float(n)
		var p := center + Vector2(cos(a), sin(a)) * radius
		_tri(center, prev, p, color)
		prev = p


func draw_rect(rect: Rect2, color: Color, filled: bool = true, width: float = -1.0, _antialiased: bool = false) -> void:
	if filled:
		_use_texture(null)
		var a := rect.position
		var b := Vector2(rect.end.x, rect.position.y)
		var c := rect.end
		var d := Vector2(rect.position.x, rect.end.y)
		_tri(a, b, c, color)
		_tri(a, c, d, color)
		return
	var p := rect.position
	draw_polyline(PackedVector2Array([p, Vector2(rect.end.x, p.y), rect.end, Vector2(p.x, rect.end.y), p]), color, width)


func draw_line(a: Vector2, b: Vector2, color: Color, width: float = -1.0, _antialiased: bool = false) -> void:
	_segment(a, b, color, width)


func draw_arc(center: Vector2, radius: float, start: float, end: float, point_count: int, color: Color, width: float = -1.0, _antialiased: bool = false) -> void:
	var pts := PackedVector2Array()
	var n := maxi(point_count, 2)
	for i in n:
		var a := lerpf(start, end, float(i) / float(n - 1))
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	draw_polyline(pts, color, width)


## A strip with mitred joints (miters capped so sharp corners don't spike).
func draw_polyline(pts: PackedVector2Array, color: Color, width: float = -1.0, _antialiased: bool = false) -> void:
	var n := pts.size()
	if n < 2:
		return
	if n == 2:
		_segment(pts[0], pts[1], color, width)
		return
	_use_texture(null)
	var hw := maxf(width, 1.0) * 0.5
	var closed := pts[0].is_equal_approx(pts[n - 1])
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	left.resize(n)
	right.resize(n)
	for i in n:
		var d_in := Vector2.ZERO
		var d_out := Vector2.ZERO
		if i > 0:
			d_in = (pts[i] - pts[i - 1]).normalized()
		elif closed:
			d_in = (pts[0] - pts[n - 2]).normalized()
		if i < n - 1:
			d_out = (pts[i + 1] - pts[i]).normalized()
		elif closed:
			d_out = (pts[1] - pts[0]).normalized()
		if d_in == Vector2.ZERO:
			d_in = d_out
		if d_out == Vector2.ZERO:
			d_out = d_in
		var n_in := Vector2(-d_in.y, d_in.x)
		var n_out := Vector2(-d_out.y, d_out.x)
		var m := n_in + n_out
		var off := n_out * hw
		if m.length_squared() > 0.0001:
			m = m.normalized()
			var k := m.dot(n_out)
			off = m * hw / maxf(k, 0.5)
		left[i] = pts[i] + off
		right[i] = pts[i] - off
	for i in n - 1:
		_tri(left[i], left[i + 1], right[i + 1], color)
		_tri(left[i], right[i + 1], right[i], color)


func draw_texture(tex: Texture2D, pos: Vector2, modulate: Color = Color.WHITE) -> void:
	draw_texture_rect_region(tex, Rect2(pos, tex.get_size()), Rect2(Vector2.ZERO, tex.get_size()), modulate)


func draw_texture_rect_region(tex: Texture2D, rect: Rect2, src_rect: Rect2, modulate: Color = Color.WHITE, _transpose: bool = false, _clip_uv: bool = true) -> void:
	_use_texture(tex)
	var ts := tex.get_size()
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	var uv0 := src_rect.position / ts
	var uv1 := src_rect.end / ts
	var uvs := [uv0, Vector2(uv1.x, uv0.y), uv1, Vector2(uv0.x, uv1.y)]
	for i: int in [0, 1, 2, 0, 2, 3]:
		_verts.append(_xf * (corners[i] as Vector2))
		_cols.append(modulate)
		_uvs.append(uvs[i])


func _segment(a: Vector2, b: Vector2, color: Color, width: float) -> void:
	_use_texture(null)
	var d := b - a
	if d.length_squared() < 0.000001:
		return
	var nrm := Vector2(-d.y, d.x).normalized() * maxf(width, 1.0) * 0.5
	_tri(a + nrm, b + nrm, b - nrm, color)
	_tri(a + nrm, b - nrm, a - nrm, color)


static func _segments(radius: float) -> int:
	return clampi(int(radius * 2.0) + 6, CIRCLE_MIN_SEGMENTS, CIRCLE_MAX_SEGMENTS)
