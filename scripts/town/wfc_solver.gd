class_name WfcSolver
extends RefCounted
## Simple-tiled Wave Function Collapse on a grid, deterministic for a given
## RNG. Each tile has one socket per side (N, E, S, W); two neighbours fit
## when their touching sockets are listed as compatible. Domains are bitmasks,
## so a tile set may hold at most 62 tiles.
##
## Determinism: only integer weights, a fixed cell scan order and the caller's
## seeded RandomNumberGenerator decide anything. No backtracking: on a
## contradiction solve() returns false and the caller retries with a new seed.

const N := 0
const E := 1
const S := 2
const W := 3
const OFFSETS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

var cols: int
var rows: int
var tile_ids: PackedStringArray = PackedStringArray()
var weights: PackedInt32Array = PackedInt32Array()
## allowed[dir][tile] = mask of tiles that may sit on that side of the tile.
var allowed: Array = [[], [], [], []]
## Domain bitmask per cell, row-major.
var domains: PackedInt64Array = PackedInt64Array()
var full_mask: int = 0


## [param tiles]: [{"id", "sockets": [n, e, s, w], "weight"}].
## [param compatible]: socket pairs that may touch (symmetric).
## [param boundary]: sockets allowed on a side facing out of the map.
func _init(p_cols: int, p_rows: int, tiles: Array, compatible: Array, boundary: Array) -> void:
	cols = p_cols
	rows = p_rows
	assert(tiles.size() <= 62, "WfcSolver supports at most 62 tiles")
	var fits := {}
	for pair: Array in compatible:
		fits["%s|%s" % [pair[0], pair[1]]] = true
		fits["%s|%s" % [pair[1], pair[0]]] = true
	for t: Dictionary in tiles:
		tile_ids.append(String(t["id"]))
		weights.append(maxi(1, int(t.get("weight", 1))))
	full_mask = (1 << tiles.size()) - 1
	for d in 4:
		var opposite := (d + 2) % 4
		var per_tile: Array[int] = []
		for a: Dictionary in tiles:
			var mask := 0
			for bi in tiles.size():
				var b: Dictionary = tiles[bi]
				if fits.has("%s|%s" % [a["sockets"][d], b["sockets"][opposite]]):
					mask |= 1 << bi
			per_tile.append(mask)
		allowed[d] = per_tile
	domains.resize(cols * rows)
	domains.fill(full_mask)
	# Sides facing out of the map only take boundary sockets.
	for y in rows:
		for x in cols:
			var mask := full_mask
			for d in 4:
				var n := Vector2i(x, y) + OFFSETS[d]
				if n.x < 0 or n.y < 0 or n.x >= cols or n.y >= rows:
					mask &= _tiles_with_socket(tiles, d, boundary)
			domains[y * cols + x] = mask


static func _tiles_with_socket(tiles: Array, d: int, sockets: Array) -> int:
	var mask := 0
	for i in tiles.size():
		if sockets.has(tiles[i]["sockets"][d]):
			mask |= 1 << i
	return mask


func tile_index(id: String) -> int:
	return tile_ids.find(id)


## Mask of tiles whose socket on side [param d] is [param socket].
func mask_with_socket(tiles: Array, d: int, socket: String) -> int:
	return _tiles_with_socket(tiles, d, [socket])


## Narrows a cell before solving (e.g. "this row must carry a road").
## Returns false if that empties the cell or a neighbour.
func restrict(cell: Vector2i, mask: int) -> bool:
	var i := cell.y * cols + cell.x
	domains[i] &= mask
	if domains[i] == 0:
		return false
	return _propagate([i])


func solve(rng: RandomNumberGenerator) -> bool:
	while true:
		var i := _pick_cell(rng)
		if i < 0:
			return true
		domains[i] = 1 << _pick_tile(domains[i], rng)
		if not _propagate([i]):
			return false
	return true


## Tile index at a solved cell (-1 if not collapsed).
func tile_at(x: int, y: int) -> int:
	var m := domains[y * cols + x]
	if m == 0 or (m & (m - 1)) != 0:
		return -1
	var t := 0
	while (m >> t) & 1 == 0:
		t += 1
	return t


## Lowest option count wins; ties broken by the RNG over the scan order.
func _pick_cell(rng: RandomNumberGenerator) -> int:
	var best := 1 << 30
	var ties: Array[int] = []
	for i in domains.size():
		var c := _popcount(domains[i])
		if c <= 1:
			continue
		if c < best:
			best = c
			ties = [i]
		elif c == best:
			ties.append(i)
	if ties.is_empty():
		return -1
	return ties[rng.randi_range(0, ties.size() - 1)]


func _pick_tile(mask: int, rng: RandomNumberGenerator) -> int:
	var total := 0
	for t in weights.size():
		if (mask >> t) & 1:
			total += weights[t]
	var roll := rng.randi_range(0, total - 1)
	for t in weights.size():
		if (mask >> t) & 1:
			roll -= weights[t]
			if roll < 0:
				return t
	return -1


func _propagate(queue: Array[int]) -> bool:
	while not queue.is_empty():
		var i: int = queue.pop_back()
		var x := i % cols
		var y := i / cols
		var mask := domains[i]
		for d in 4:
			var nx := x + OFFSETS[d].x
			var ny := y + OFFSETS[d].y
			if nx < 0 or ny < 0 or nx >= cols or ny >= rows:
				continue
			var support := 0
			var per_tile: Array = allowed[d]
			for t in per_tile.size():
				if (mask >> t) & 1:
					support |= per_tile[t]
			var ni := ny * cols + nx
			var narrowed := domains[ni] & support
			if narrowed != domains[ni]:
				if narrowed == 0:
					return false
				domains[ni] = narrowed
				queue.append(ni)
	return true


static func _popcount(m: int) -> int:
	var c := 0
	while m != 0:
		m &= m - 1
		c += 1
	return c
