class_name MeshCanvas
extends RefCounted
## Records the CanvasItem drawing API subset that PlaceholderArt and
## GroundLayer use (like MaskCanvas does) into indexed triangle meshes, so a
## person or the whole ground ends up as one draw call instead of hundreds.
## Shapes keep their order (later ones paint over earlier ones, as on a canvas).
##
## Untextured shapes are vertex coloured; draw_texture_rect_region adds a quad
## with UVs for that texture. Consecutive shapes with the same texture (or
## none) share a mesh, so the result is a short list of
## {"mesh": ArrayMesh, "texture": Texture2D or null} to replay with draw_mesh.
##
## [member white_uv]: when set (a UV of an opaque white texel), untextured
## shapes get that UV instead of none, so they can share one mesh with
## textured shapes from the same atlas (see TownBake).
##
## Characters are cached per look (see character_mesh), so a crowd member and
## the hider's portrait never rebuild the same geometry twice.

## Circles get more segments as they grow, within these bounds.
const CIRCLE_MIN_SEGMENTS := 10
const CIRCLE_MAX_SEGMENTS := 40

var white_uv := Vector2(-1, -1)

## Object transform every draw is relative to (draw_set_transform composes).
var _base := Transform2D.IDENTITY
var _xf := Transform2D.IDENTITY
var _ops: Array = []
var _tex: Texture2D = null
var _verts := PackedVector2Array()
var _cols := PackedColorArray()
var _uvs := PackedVector2Array()
var _idx := PackedInt32Array()

static var _character_cache: Dictionary = {}
static var _character_arrays: Dictionary = {}


## One mesh for [param look] (flipped or not), cached. Drawn at the feet.
static func character_mesh(look: Dictionary, flip: bool) -> ArrayMesh:
	var key := _look_key(look, flip)
	var mesh: ArrayMesh = _character_cache.get(key)
	if mesh == null:
		var a := character_arrays(look, flip)
		mesh = ArrayMesh.new()
		if not (a[Mesh.ARRAY_VERTEX] as PackedVector2Array).is_empty():
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		_character_cache[key] = mesh
	return mesh


## Raw arrays of a character at the feet (vertex, colour, index), cached.
static func character_arrays(look: Dictionary, flip: bool) -> Array:
	var key := _look_key(look, flip)
	if _character_arrays.has(key):
		return _character_arrays[key]
	var mc := MeshCanvas.new()
	PlaceholderArt.draw_character(mc, look, flip)
	var a := mc._arrays()
	_character_arrays[key] = a
	return a


static func _look_key(look: Dictionary, flip: bool) -> String:
	return "%s|%s" % [JSON.stringify(look), flip]


static func clear_cache() -> void:
	_character_cache.clear()
	_character_arrays.clear()


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


## Current geometry as mesh arrays (vertex, colour, uv if any, index).
func _arrays() -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_COLOR] = _cols
	if _tex != null or white_uv.x >= 0.0:
		arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_INDEX] = _idx
	return arrays


func _flush() -> void:
	if _verts.is_empty():
		return
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays())
	_ops.append({"mesh": mesh, "texture": _tex})
	_verts = PackedVector2Array()
	_cols = PackedColorArray()
	_uvs = PackedVector2Array()
	_idx = PackedInt32Array()


func _use_texture(tex: Texture2D) -> void:
	if tex != _tex and not (tex == null and white_uv.x >= 0.0 and _tex != null):
		_flush()
		_tex = tex


## Adds [param pts] (local space) as vertices of [param color]; returns the
## index of the first one.
func _add(pts: PackedVector2Array, color: Color) -> int:
	var base := _verts.size()
	_verts.append_array(_xf * pts)
	for i in pts.size():
		_cols.append(color)
	if _tex != null or white_uv.x >= 0.0:
		for i in pts.size():
			_uvs.append(white_uv)
	return base


# --- CanvasItem drawing API subset ------------------------------------------

## Next draws are relative to an object at [param at].
func begin_object(at: Vector2) -> void:
	_base = Transform2D(0.0, at)
	_xf = _base


## Appends cached arrays (see character_arrays) drawn at [param at].
func append_local(a: Array, at: Vector2) -> void:
	var v: PackedVector2Array = a[Mesh.ARRAY_VERTEX]
	if v.is_empty():
		return
	var base := _verts.size()
	_verts.append_array(Transform2D(0.0, at) * v)
	_cols.append_array(a[Mesh.ARRAY_COLOR])
	if _tex != null or white_uv.x >= 0.0:
		var u := PackedVector2Array()
		u.resize(v.size())
		u.fill(white_uv)
		_uvs.append_array(u)
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var start := _idx.size()
	_idx.append_array(idx)
	for i in range(start, _idx.size()):
		_idx[i] += base


func draw_set_transform(pos: Vector2, rotation: float = 0.0, scale: Vector2 = Vector2.ONE) -> void:
	_xf = _base * Transform2D(rotation, scale, 0.0, pos)


func draw_set_transform_matrix(xf: Transform2D) -> void:
	_xf = _base * xf


func draw_colored_polygon(pts: PackedVector2Array, color: Color, _uvs_in: PackedVector2Array = PackedVector2Array(), _texture: Texture2D = null) -> void:
	if pts.size() < 3:
		return
	_use_texture(null)
	var idx := Geometry2D.triangulate_polygon(pts)
	var base := _add(pts, color)
	if idx.is_empty():
		# Self-intersecting outline: a fan is close enough for these shapes.
		for i in range(1, pts.size() - 1):
			_idx.append_array([base, base + i, base + i + 1])
		return
	for i in idx:
		_idx.append(base + i)


func draw_circle(center: Vector2, radius: float, color: Color, filled: bool = true, width: float = -1.0, _antialiased: bool = false) -> void:
	if not filled:
		draw_arc(center, radius, 0.0, TAU, _segments(radius) + 1, color, width)
		return
	_use_texture(null)
	var n := _segments(radius)
	var pts := PackedVector2Array([center])
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	var base := _add(pts, color)
	for i in n:
		_idx.append_array([base, base + 1 + i, base + 1 + (i + 1) % n])


func draw_rect(rect: Rect2, color: Color, filled: bool = true, width: float = -1.0, _antialiased: bool = false) -> void:
	if filled:
		_use_texture(null)
		var base := _add(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]), color)
		_idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
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
	var strip := PackedVector2Array()
	strip.resize(n * 2)
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
			off = m * hw / maxf(m.dot(n_out), 0.5)
		strip[i * 2] = pts[i] + off
		strip[i * 2 + 1] = pts[i] - off
	var base := _add(strip, color)
	for i in n - 1:
		var l0 := base + i * 2
		_idx.append_array([l0, l0 + 2, l0 + 3, l0, l0 + 3, l0 + 1])


func draw_texture(tex: Texture2D, pos: Vector2, modulate: Color = Color.WHITE) -> void:
	draw_texture_rect_region(tex, Rect2(pos, tex.get_size()), Rect2(Vector2.ZERO, tex.get_size()), modulate)


func draw_texture_rect_region(tex: Texture2D, rect: Rect2, src_rect: Rect2, modulate: Color = Color.WHITE, _transpose: bool = false, _clip_uv: bool = true) -> void:
	# An AtlasTexture samples its region of the shared atlas page.
	var page := tex
	var src := src_rect
	if tex is AtlasTexture:
		page = (tex as AtlasTexture).atlas
		src = Rect2(src_rect.position + (tex as AtlasTexture).region.position, src_rect.size)
	_use_texture(page)
	var ts := page.get_size()
	var base := _verts.size()
	_verts.append_array(_xf * PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]))
	var uv0 := src.position / ts
	var uv1 := src.end / ts
	_uvs.append_array([uv0, Vector2(uv1.x, uv0.y), uv1, Vector2(uv0.x, uv1.y)])
	for i in 4:
		_cols.append(modulate)
	_idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])


func _segment(a: Vector2, b: Vector2, color: Color, width: float) -> void:
	_use_texture(null)
	var d := b - a
	if d.length_squared() < 0.000001:
		return
	var nrm := Vector2(-d.y, d.x).normalized() * maxf(width, 1.0) * 0.5
	var base := _add(PackedVector2Array([a + nrm, b + nrm, b - nrm, a - nrm]), color)
	_idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])


static func _segments(radius: float) -> int:
	return clampi(int(radius * 2.0) + 6, CIRCLE_MIN_SEGMENTS, CIRCLE_MAX_SEGMENTS)
