class_name TownBake
extends Node2D
## Draws the whole town (people, props, building slices, canopies) from a few
## dozen merged meshes instead of thousands of nodes. Godot pays per draw
## command, so a zoomed-out XL town went from ~2000 commands to ~100.
##
## How it stays exact: the town never moves, so the draw order Godot's Y-sort
## would produce is fixed. At bake time every drawable part ("piece") gets
## the same key Godot sorts by (z layer, ground y, tree order), pieces are
## sorted, and consecutive pieces are merged into "bands" of one mesh each,
## all sampling the shared TextureAtlas page (people use its white texel).
##
## How it stays live: the real nodes still exist (hidden) and keep all game
## logic. When one changes its looks (WorldActor.visual_changed: a marker, a
## flash, fading out, walking, a faded tree crown, a new hider) it goes "live":
## its pieces are cut out of their band and a stand-in node draws it with the
## node's own drawing code at the right place in the order. When it's back to
## how it was baked, it's merged back in. Actors that left (hidden) are cut
## out for good.

const MAX_BAND_PIECES := 48
const MAX_BAND_VERTS := 30000


class Piece:
	extends RefCounted
	var actor: WorldActor
	## What draws it: the actor, one of its BuildingSlices or its CanopyLayer.
	var part: Node2D
	var z := 0
	var y := 0.0
	var order := 0
	## Band holding its baked geometry (-1: not baked, e.g. a new hider).
	var home := -1
	var i0 := 0
	var i1 := 0

	func before(o: Piece) -> bool:
		return y < o.y or (y == o.y and order < o.order)


class Band:
	extends RefCounted
	var z := 0
	var pieces: Array[Piece] = []
	var arrays: Array = []
	var holder: Node2D


## Draws one live piece with the actor's own drawing code.
class Proxy:
	extends Node2D
	var piece: Piece

	func sync() -> void:
		var part := piece.part
		position = part.global_position
		var m := piece.actor.modulate
		if part != piece.actor:
			m *= part.modulate
		modulate = m
		visible = piece.actor.visible
		queue_redraw()

	func _draw() -> void:
		piece.part.draw_visual(self)


var _world: Node2D
var _bands: Array[Band] = []
## z -> Array[int] band indices in draw order.
var _layers: Dictionary = {}
## z -> container Node2D.
var _containers: Dictionary = {}
var _pieces_of: Dictionary = {}  # WorldActor -> Array[Piece]
## Live actors -> {"proxies": Array[Proxy], "keys": Array[float y]}.
var _live: Dictionary = {}
## Actors that left the town (hidden): cut out, no stand-in.
var _gone: Dictionary = {}
var _dirty: Dictionary = {}  # band index -> true
## CharacterActor -> look key it was baked with.
var _baked_look: Dictionary = {}
var _page: Texture2D
var _order := 0


## Bakes [param world]'s children. False when the town can't be merged (then
## nothing changes and the nodes draw themselves as before).
func bake(world: Node2D) -> bool:
	if not TextureAtlas.built() or TextureAtlas.page_count() != 1:
		return false
	_world = world
	_page = TextureAtlas.page(0)
	var by_z: Dictionary = {}
	for child in world.get_children():
		var actor := child as WorldActor
		if actor == null:
			continue
		for p in _make_pieces(actor):
			if not by_z.has(p.z):
				by_z[p.z] = []
			(by_z[p.z] as Array).append(p)
	var zs := by_z.keys()
	zs.sort()
	for z: int in zs:
		var list: Array = by_z[z]
		list.sort_custom(func(a: Piece, b: Piece) -> bool: return a.before(b))
		var container := Node2D.new()
		container.name = "Z%d" % z
		container.z_index = z
		add_child(container)
		_containers[z] = container
		_layers[z] = []
		var mc := _new_canvas()
		var band := _new_band(z, container)
		for p: Piece in list:
			if band.pieces.size() >= MAX_BAND_PIECES or mc._verts.size() >= MAX_BAND_VERTS:
				if not _close_band(band, mc):
					return _fail()
				mc = _new_canvas()
				band = _new_band(z, container)
			p.home = _bands.size() - 1
			p.i0 = mc._idx.size()
			_record(mc, p)
			p.i1 = mc._idx.size()
			band.pieces.append(p)
		if not _close_band(band, mc):
			return _fail()
	for actor: WorldActor in _pieces_of:
		actor.visual_changed.connect(_on_visual_changed)
		if actor is CharacterActor:
			_baked_look[actor] = AvatarKit.look_key((actor as CharacterActor).look)
	# Anything already marked, tinted, moving or hidden is drawn live / cut
	# out from the start (the baked geometry is always the plain look).
	for actor: WorldActor in _pieces_of.keys():
		if not _plain(actor):
			_on_visual_changed(actor)
	world.visible = false
	for i in _bands.size():
		_rebuild(i)
	return true


func _plain(actor: WorldActor) -> bool:
	if not actor.visible or actor.animating() or actor.marker != WorldActor.Marker.NONE or actor.modulate != Color.WHITE:
		return false
	for p: Piece in _pieces_of[actor]:
		if p.part != actor and p.part.modulate != Color.WHITE:
			return false
	return true


## A hider (or anything) spawned after the bake: drawn live from the start.
func adopt(actor: WorldActor) -> void:
	_pieces_of[actor] = _make_pieces(actor)
	actor.visual_changed.connect(_on_visual_changed)
	_on_visual_changed(actor)


func _fail() -> bool:
	for c in get_children():
		c.queue_free()
	_bands.clear()
	_world.visible = true
	return false


func _new_canvas() -> MeshCanvas:
	var mc := MeshCanvas.new()
	mc.white_uv = TextureAtlas.white_uv()
	mc._tex = _page
	return mc


func _new_band(z: int, container: Node2D) -> Band:
	var b := Band.new()
	b.z = z
	b.holder = Node2D.new()
	b.holder.set_meta("band", _bands.size())
	container.add_child(b.holder)
	_bands.append(b)
	(_layers[z] as Array).append(_bands.size() - 1)
	return b


## False when something in the band wasn't on the atlas page.
func _close_band(b: Band, mc: MeshCanvas) -> bool:
	if not mc._ops.is_empty() or mc._tex != _page:
		return false
	b.arrays = mc._arrays()
	return true


## The actor's pieces with their sort keys, in Godot's traversal order.
func _make_pieces(actor: WorldActor) -> Array[Piece]:
	var out: Array[Piece] = []
	out.append(_piece(actor, actor, actor.z_index, actor.global_position.y))
	for child in actor.get_children():
		var part := child as Node2D
		if part == null or not part.has_method("draw_visual"):
			continue
		var z := actor.z_index + part.z_index if part.z_as_relative else part.z_index
		# Y-sorted actors (sliced buildings) sort each child by its own y;
		# otherwise a child is drawn with its parent, at the parent's key.
		out.append(_piece(actor, part, z, part.global_position.y if actor.y_sort_enabled else actor.global_position.y))
	_pieces_of[actor] = out
	return out


func _piece(actor: WorldActor, part: Node2D, z: int, y: float) -> Piece:
	var p := Piece.new()
	p.actor = actor
	p.part = part
	p.z = z
	p.y = y
	_order += 1
	p.order = _order
	return p


func _record(mc: MeshCanvas, p: Piece) -> void:
	if p.part is CharacterActor:
		var c := p.part as CharacterActor
		mc.append_local(MeshCanvas.character_arrays(c.look, c.flip_h), c.global_position)
		return
	mc.begin_object(p.part.global_position)
	p.part.draw_visual(mc)


# --- Live actors ---------------------------------------------------------------

func _on_visual_changed(actor: WorldActor) -> void:
	if _live.has(actor):
		return
	_gone.erase(actor)
	var proxies: Array[Proxy] = []
	for p: Piece in _pieces_of[actor]:
		var px := Proxy.new()
		px.piece = p
		proxies.append(px)
		_mark(p)
	_live[actor] = {"proxies": proxies, "y": _part_ys(actor)}


func _part_ys(actor: WorldActor) -> PackedFloat32Array:
	var ys := PackedFloat32Array()
	for p: Piece in _pieces_of[actor]:
		ys.append(_live_y(p))
	return ys


## Where a live piece sorts now (it may have walked).
func _live_y(p: Piece) -> float:
	if p.part != p.actor and not p.actor.y_sort_enabled:
		return p.actor.global_position.y
	return p.part.global_position.y


## Marks the band a piece's geometry lives in and the band it sorts into now.
func _mark(p: Piece) -> void:
	if p.home >= 0:
		_dirty[p.home] = true
	_dirty[_slot_band(p.z, _live_y(p), p.order)] = true


## Band of layer [param z] whose key range takes (y, order).
func _slot_band(z: int, y: float, order: int) -> int:
	var list: Array = _layers.get(z, [])
	if list.is_empty():
		return _new_layer_band(z)
	var found: int = list[0]
	for bi: int in list:
		var first: Piece = _bands[bi].pieces[0] if not _bands[bi].pieces.is_empty() else null
		if first and (first.y < y or (first.y == y and first.order < order)):
			found = bi
		else:
			break
	return found


## A layer nothing was baked into (e.g. a marker-only z): an empty band.
func _new_layer_band(z: int) -> int:
	var container := Node2D.new()
	container.name = "Z%d" % z
	container.z_index = z
	add_child(container)
	_containers[z] = container
	_layers[z] = []
	var b := _new_band(z, container)
	b.arrays = []
	return _bands.size() - 1


func _process(_delta: float) -> void:
	if _bands.is_empty():
		return
	for actor: WorldActor in _live.keys():
		var entry: Dictionary = _live[actor]
		if not is_instance_valid(actor) or actor.is_queued_for_deletion():
			for px: Proxy in entry["proxies"]:
				if px.get_parent():
					_dirty[int(px.get_parent().get_meta("band"))] = true
				if px.piece.home >= 0:
					_dirty[px.piece.home] = true
			_drop(actor)
			continue
		var ys := _part_ys(actor)
		if ys != entry["y"]:
			for i in ys.size():
				var p: Piece = (_pieces_of[actor] as Array)[i]
				_dirty[_slot_band(p.z, entry["y"][i], p.order)] = true
				_dirty[_slot_band(p.z, ys[i], p.order)] = true
			entry["y"] = ys
		for px: Proxy in entry["proxies"]:
			px.sync()
		if _settled(actor):
			for p: Piece in _pieces_of[actor]:
				_mark(p)
			if actor.visible:
				_live.erase(actor)
			else:
				_live.erase(actor)
				_gone[actor] = true
			_free_proxies(entry)
	for bi: int in _dirty.keys():
		_rebuild(bi)
	_dirty.clear()


func _drop(actor: WorldActor) -> void:
	var entry: Dictionary = _live[actor]
	_live.erase(actor)
	_free_proxies(entry)
	_pieces_of.erase(actor)
	_gone.erase(actor)
	_baked_look.erase(actor)


func _free_proxies(entry: Dictionary) -> void:
	for px: Proxy in entry["proxies"]:
		if px.get_parent():
			px.get_parent().remove_child(px)
		px.queue_free()


## Back to exactly how it was baked (or gone for good): no stand-in needed.
func _settled(actor: WorldActor) -> bool:
	if actor.animating():
		return false
	if not actor.visible:
		return true
	if actor.marker != WorldActor.Marker.NONE or actor.modulate != Color.WHITE:
		return false
	var pieces: Array = _pieces_of[actor]
	for p: Piece in pieces:
		if p.home < 0:
			return false  # never baked (e.g. a hider placed later)
		if p.part != p.actor and p.part.modulate != Color.WHITE:
			return false
		if not is_equal_approx(_live_y(p), p.y):
			return false
	if actor is CharacterActor:
		return _baked_look.get(actor, "") == AvatarKit.look_key((actor as CharacterActor).look)
	return true


## Rebuilds band [param bi]: runs of baked geometry with live stand-ins
## slotted in where they sort, and cut-outs for live or departed actors.
func _rebuild(bi: int) -> void:
	var band := _bands[bi]
	for c in band.holder.get_children():
		band.holder.remove_child(c)
		if not c is Proxy:
			c.queue_free()
	# Stand-ins that sort into this band.
	var incoming: Array = []
	for actor: WorldActor in _live:
		var entry: Dictionary = _live[actor]
		var pieces: Array = _pieces_of[actor]
		for i in pieces.size():
			var p: Piece = pieces[i]
			if p.z == band.z and _slot_band(p.z, entry["y"][i], p.order) == bi:
				incoming.append([entry["y"][i], p.order, entry["proxies"][i]])
	incoming.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	# Baked geometry between two stand-ins is one mesh; cut-out pieces (live
	# elsewhere, or gone) are simply left out of its index list.
	var run := PackedInt32Array()
	var k := 0
	for p: Piece in band.pieces:
		while k < incoming.size() and (incoming[k][0] < p.y or (incoming[k][0] == p.y and incoming[k][1] < p.order)):
			_emit_run(band, run)
			run = PackedInt32Array()
			_put(band, incoming[k][2])
			k += 1
		if p.i1 == p.i0 or _live.has(p.actor) or _gone.has(p.actor):
			continue
		run.append_array(_slice_idx(band, p.i0, p.i1))
	_emit_run(band, run)
	while k < incoming.size():
		_put(band, incoming[k][2])
		k += 1


func _slice_idx(band: Band, i0: int, i1: int) -> PackedInt32Array:
	return (band.arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).slice(i0, i1)


func _put(band: Band, px: Proxy) -> void:
	if px.get_parent():
		px.get_parent().remove_child(px)
	band.holder.add_child(px)


func _emit_run(band: Band, idx: PackedInt32Array) -> void:
	if idx.is_empty():
		return
	var a := band.arrays.duplicate()
	a[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	var run := MeshRun.new()
	run.mesh = mesh
	run.texture = _page
	band.holder.add_child(run)


class MeshRun:
	extends Node2D
	var mesh: ArrayMesh
	var texture: Texture2D

	func _draw() -> void:
		draw_mesh(mesh, texture)
