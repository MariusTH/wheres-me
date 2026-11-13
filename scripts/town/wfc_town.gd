class_name WfcTown
extends RefCounted
## Builds the isometric town's map dictionary (the same shape as
## data/maps/*.json) from the template data/maps/town_iso.json and a seed:
##   1. A main east-west and north-south road are pinned, then WfcSolver fills
##      the coarse grid with roads, house rows (front + backyard) and open cells.
##      Only cells that show inside the "view" rectangle take part.
##   2. A solve is accepted only if it passes the template's quality checks
##      (roads connected, enough houses and open space); otherwise the next
##      attempt seed is tried, so a share code always maps to the same town.
##   3. Roads get seeded widths, offsets and jogs; house rows mix houses, small
##      buildings and garden gaps on jittered plots; open cells are split into
##      chunks that become parks, gardens, yards, plazas and markets (one park
##      gets a pond, one plaza the fountain).
##   4. The plan is laid out at 2:1 isometric (plan x runs down-right on screen,
##      plan y down-left): zones, blocked areas and objects are projected to
##      screen space, the ground stays on the plan (GroundLayer draws it through
##      the transform), and zones are clipped to the view.
## Changing anything here that moves the output needs a map_version bump in
## the template.

const ZONE_INSET := 6.0
## No-standing margin kept around each house plot (so nobody overlaps a wall).
const PLOT_MARGIN := 12.0
## Zones less visible than this are dropped; the rest keep their on-screen
## part with crowd and props scaled to it (no dressing aimed off screen).
const MIN_ZONE_ON_SCREEN := 0.2
## Nothing is placed closer to the screen edge than this.
const VIEW_MARGIN := TownGenerator.EDGE_MARGIN

var t: Dictionary
var cols: int
var rows: int
var cell: float
var road_w: float
var tiles: Array
var roles: PackedStringArray = PackedStringArray()
## Solved tile index per cell, row-major.
var grid: PackedInt32Array = PackedInt32Array()
var attempt: int = -1
var rng: RandomNumberGenerator
## Plan -> world transform, the visible screen rectangle and which cells show
## inside it (1) or are left out (0).
var xf := Transform2D.IDENTITY
var view := Vector2.ZERO
var active := PackedByteArray()
var plot := 0.0
var map_seed: int = 0
## Uneven roads ("roads" in the template): per road line a width and an
## offset from the cell centre, and per road cell the offset at each edge it
## crosses (straight stretches can jog).
var road_cfg: Dictionary = {}
var row_w := PackedFloat32Array()
var row_off := PackedFloat32Array()
var col_w := PackedFloat32Array()
var col_off := PackedFloat32Array()
## Vector2i cell -> Vector2(offset at W edge, offset at E edge) / (N edge, S edge).
var h_edges := {}
var v_edges := {}

var ground: Array = []
var blocked: Array = []
var zones: Array = []
var fixed: Array = []


static func build(template: Dictionary, map_seed: int) -> Dictionary:
	var w := WfcTown.new()
	w._setup(template)
	w._solve(map_seed)
	w.map_seed = map_seed
	w.rng = DetHash.make_rng(map_seed, "wfc_build")
	w._plan_roads()
	w._emit()
	return w._to_dict()


func _setup(template: Dictionary) -> void:
	t = template
	var g: Dictionary = t["grid"]
	cols = int(g["cols"])
	rows = int(g["rows"])
	cell = float(g["cell"])
	road_w = float(g["carriageway"])
	tiles = t["tiles"]
	for tile: Dictionary in tiles:
		roles.append(String(tile["role"]))
	view = MapDefinition.vec2(t["view"])
	plot = float(g["plot"])
	var side := Vector2(cols, rows) * cell
	var centre := Vector2((side.x - side.y) * 0.5, (side.x + side.y) * 0.25)
	xf = Transform2D(Vector2(1, 0.5), Vector2(-1, 0.5), view * 0.5 - centre)
	var screen := Rect2(Vector2.ZERO, view)
	active.resize(cols * rows)
	for y in rows:
		for x in cols:
			var box := Rect2(xf * (Vector2(x, y) * cell), Vector2.ZERO)
			for c in [Vector2(x + 1, y), Vector2(x, y + 1), Vector2(x + 1, y + 1)]:
				box = box.expand(xf * (c * cell))
			active[y * cols + x] = 1 if screen.intersects(box.grow(-cell * 0.25)) else 0


# --- 1 + 2: solve with retries -------------------------------------------

func _solve(map_seed: int) -> void:
	var q: Dictionary = t["quality"]
	var fallback := PackedInt32Array()
	for a in int(q["attempts"]):
		var solved := _try_solve(map_seed, a)
		if solved.is_empty():
			continue
		if fallback.is_empty():
			fallback = solved
		grid = solved
		if _quality_ok():
			attempt = a
			return
	# Nothing passed: use the first clean solve (still deterministic).
	grid = fallback
	attempt = -1
	assert(not grid.is_empty(), "WfcTown: no attempt solved at all")


func _try_solve(map_seed: int, a: int) -> PackedInt32Array:
	var sock: Dictionary = t["sockets"]
	var solver := WfcSolver.new(cols, rows, tiles, sock["compatible"], sock["boundary"])
	var r := DetHash.make_rng(map_seed, "wfc|%d" % a)
	# Pin a main road each way so every town has a spine to navigate by.
	var main_row := r.randi_range(rows / 3, rows - rows / 3)
	var main_col := r.randi_range(cols / 3, cols - cols / 3)
	var ew := solver.mask_with_socket(tiles, WfcSolver.E, "r") & solver.mask_with_socket(tiles, WfcSolver.W, "r")
	var ns := solver.mask_with_socket(tiles, WfcSolver.N, "r") & solver.mask_with_socket(tiles, WfcSolver.S, "r")
	# Cells off screen are left as open ground.
	var open_mask := 0
	for i in tiles.size():
		if roles[i] == "open":
			open_mask |= 1 << i
	for y in rows:
		for x in cols:
			if not is_active(x, y) and not solver.restrict(Vector2i(x, y), open_mask):
				return PackedInt32Array()
	for x in cols:
		if not (is_active(x - 1, main_row) and is_active(x, main_row) and is_active(x + 1, main_row)):
			continue
		if not solver.restrict(Vector2i(x, main_row), ew):
			return PackedInt32Array()
	for y in rows:
		if not (is_active(main_col, y - 1) and is_active(main_col, y) and is_active(main_col, y + 1)):
			continue
		if not solver.restrict(Vector2i(main_col, y), ns):
			return PackedInt32Array()
	if not solver.solve(r):
		return PackedInt32Array()
	var out := PackedInt32Array()
	out.resize(cols * rows)
	for y in rows:
		for x in cols:
			out[y * cols + x] = solver.tile_at(x, y)
	return out


func is_active(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < cols and y < rows and active[y * cols + x] == 1


## Role of the solved cell ("" off the grid or outside the view).
func role(x: int, y: int) -> String:
	if not is_active(x, y):
		return ""
	return roles[grid[y * cols + x]]


func sockets(x: int, y: int) -> Array:
	return tiles[grid[y * cols + x]]["sockets"]


func _quality_ok() -> bool:
	var q: Dictionary = t["quality"]
	var counts := {"road": 0, "house": 0, "open": 0, "backyard": 0}
	for i in grid.size():
		if active[i] == 1:
			counts[roles[grid[i]]] += 1
	var total := float(active.count(1))
	var rf: Array = q["road_fraction"]
	if counts["road"] / total < float(rf[0]) or counts["road"] / total > float(rf[1]):
		return false
	if counts["house"] < int(q["min_house_fronts"]):
		return false
	if counts["open"] / total < float(q["min_open_fraction"]):
		return false
	return _roads_connected(counts["road"])


func _roads_connected(road_count: int) -> bool:
	var start := -1
	for i in grid.size():
		if roles[grid[i]] == "road":
			start = i
			break
	if start < 0:
		return false
	var seen := {start: true}
	var stack: Array[int] = [start]
	while not stack.is_empty():
		var i: int = stack.pop_back()
		var x := i % cols
		var y := i / cols
		var s := sockets(x, y)
		for d in 4:
			if s[d] != "r":
				continue
			var n := Vector2i(x, y) + WfcSolver.OFFSETS[d]
			if n.x < 0 or n.y < 0 or n.x >= cols or n.y >= rows:
				continue
			var ni := n.y * cols + n.x
			if not seen.has(ni) and role(n.x, n.y) == "road":
				seen[ni] = true
				stack.append(ni)
	return seen.size() == road_count


# --- 3 + 4: emit map data ------------------------------------------------

func cell_rect(x: int, y: int) -> Rect2:
	return Rect2(x * cell, y * cell, cell, cell)


func _emit() -> void:
	for y in rows:
		for x in cols:
			match role(x, y):
				"road":
					_emit_road(x, y)
				"backyard":
					_emit_zone("by_%d_%d" % [x, y], "backyard", _band(cell_rect(x, y), WfcSolver.N, cell * 0.45), t["streets"]["backyard"])
	_emit_house_rows()
	_emit_districts()
	ground = _merge_ground(ground)


## Strip of [param depth] along side [param d] of [param r].
func _band(r: Rect2, d: int, depth: float) -> Rect2:
	match d:
		WfcSolver.N:
			return Rect2(r.position, Vector2(r.size.x, depth))
		WfcSolver.S:
			return Rect2(r.position.x, r.end.y - depth, r.size.x, depth)
		WfcSolver.E:
			return Rect2(r.end.x - depth, r.position.y, depth, r.size.y)
		_:
			return Rect2(r.position, Vector2(depth, r.size.y))


func _straight_h(x: int, y: int) -> bool:
	var s := sockets(x, y)
	return s[WfcSolver.E] == "r" and s[WfcSolver.W] == "r" and s[WfcSolver.N] != "r" and s[WfcSolver.S] != "r"


func _straight_v(x: int, y: int) -> bool:
	var s := sockets(x, y)
	return s[WfcSolver.N] == "r" and s[WfcSolver.S] == "r" and s[WfcSolver.E] != "r" and s[WfcSolver.W] != "r"


## Seeded road widths, offsets and jogs (own RNG stream).
func _plan_roads() -> void:
	road_cfg = t["roads"]
	row_w.resize(rows)
	row_off.resize(rows)
	col_w.resize(cols)
	col_off.resize(cols)
	var r := DetHash.make_rng(map_seed, "roads")
	var widths: Array = road_cfg["widths"]
	for i in rows:
		row_w[i] = float(widths[r.randi_range(0, widths.size() - 1)])
		row_off[i] = _road_offset(r, row_w[i])
	for i in cols:
		col_w[i] = float(widths[r.randi_range(0, widths.size() - 1)])
		col_off[i] = _road_offset(r, col_w[i])
	var jog := float(road_cfg["jog_chance"])
	for y in rows:
		var edge := row_off[y]
		for x in cols:
			if role(x, y) != "road" or not _straight_h(x, y):
				edge = row_off[y]
				continue
			var nxt := edge
			var next_straight := x + 1 < cols and role(x + 1, y) == "road" and _straight_h(x + 1, y)
			if not next_straight:
				nxt = row_off[y]
			elif r.randf() < jog:
				nxt = _road_offset(r, row_w[y])
			h_edges[Vector2i(x, y)] = Vector2(edge, nxt)
			edge = nxt
	for x in cols:
		var edge := col_off[x]
		for y in rows:
			if role(x, y) != "road" or not _straight_v(x, y):
				edge = col_off[x]
				continue
			var nxt := edge
			var next_straight := y + 1 < rows and role(x, y + 1) == "road" and _straight_v(x, y + 1)
			if not next_straight:
				nxt = col_off[x]
			elif r.randf() < jog:
				nxt = _road_offset(r, col_w[x])
			v_edges[Vector2i(x, y)] = Vector2(edge, nxt)
			edge = nxt


## Random offset from the cell centre that keeps a walkable pavement both sides.
func _road_offset(r: RandomNumberGenerator, w: float) -> float:
	var room := minf(float(road_cfg["offset"]), (cell - w) * 0.5 - float(road_cfg["min_walk"]))
	return roundf(r.randf_range(-room, room)) if room > 0.0 else 0.0


## Road rects for one cell: carriageway pieces (jogs split a straight one into
## two halves and a connector), first entry is the main piece.
func _lanes(x: int, y: int) -> Array[Rect2]:
	var r := cell_rect(x, y)
	var s := sockets(x, y)
	var c := r.get_center()
	var lanes: Array[Rect2] = []
	if _straight_h(x, y):
		var w := row_w[y]
		var e: Vector2 = h_edges.get(Vector2i(x, y), Vector2(row_off[y], row_off[y]))
		if e.x == e.y:
			lanes.append(Rect2(r.position.x, c.y + e.x - w * 0.5, cell, w))
		else:
			lanes.append(Rect2(r.position.x, c.y + e.x - w * 0.5, cell * 0.5, w))
			lanes.append(Rect2(c.x, c.y + e.y - w * 0.5, cell * 0.5, w))
			lanes.append(Rect2(c.x - w * 0.5, c.y + minf(e.x, e.y) - w * 0.5, w, absf(e.y - e.x) + w))
		return lanes
	if _straight_v(x, y):
		var w := col_w[x]
		var e: Vector2 = v_edges.get(Vector2i(x, y), Vector2(col_off[x], col_off[x]))
		if e.x == e.y:
			lanes.append(Rect2(c.x + e.x - w * 0.5, r.position.y, w, cell))
		else:
			lanes.append(Rect2(c.x + e.x - w * 0.5, r.position.y, w, cell * 0.5))
			lanes.append(Rect2(c.x + e.y - w * 0.5, c.y, w, cell * 0.5))
			lanes.append(Rect2(c.x + minf(e.x, e.y) - w * 0.5, c.y - w * 0.5, absf(e.y - e.x) + w, w))
		return lanes
	var box := Rect2(c.x + col_off[x] - col_w[x] * 0.5, c.y + row_off[y] - row_w[y] * 0.5, col_w[x], row_w[y])
	lanes.append(box)
	if s[WfcSolver.N] == "r":
		lanes.append(Rect2(box.position.x, r.position.y, box.size.x, box.position.y - r.position.y))
	if s[WfcSolver.S] == "r":
		lanes.append(Rect2(box.position.x, box.end.y, box.size.x, r.end.y - box.end.y))
	if s[WfcSolver.W] == "r":
		lanes.append(Rect2(r.position.x, box.position.y, box.position.x - r.position.x, box.size.y))
	if s[WfcSolver.E] == "r":
		lanes.append(Rect2(box.end.x, box.position.y, r.end.x - box.end.x, box.size.y))
	return lanes


func _emit_road(x: int, y: int) -> void:
	var r := cell_rect(x, y)
	var s := sockets(x, y)
	ground.append({"type": "pavement", "rect": _arr(r)})
	var straight_h := _straight_h(x, y)
	var straight_v := _straight_v(x, y)
	var lanes := _lanes(x, y)
	var road := lanes[0]
	for i in lanes.size():
		road = road.merge(lanes[i])
		ground.append({"type": "road" if (straight_h or straight_v or i > 0) else "road_plain", "rect": _arr(lanes[i])})
		blocked.append({"id": "blk_road_%d_%d_%d" % [x, y, i], "label": "that's in the road", "rect": _arr(lanes[i])})
	# Pavements on kerb sides: shop frontage under a house, sidewalk otherwise.
	var streets: Dictionary = t["streets"]
	for d in 4:
		if s[d] != "k":
			continue
		var depth := [road.position.y - r.position.y, r.end.x - road.end.x, r.end.y - road.end.y, road.position.x - r.position.x][d] as float
		var band := _band(r, d, depth)
		var under_house := d == WfcSolver.N and role(x, y - 1) == "house"
		var kind := "shop_frontage" if under_house else "sidewalk"
		_emit_zone("sw_%d_%d_%d" % [x, y, d], kind, band, streets["frontage" if under_house else "sidewalk"])
	# Junction corners between two road arms are left-over pavement: give
	# them a lamp, a bush or someone waiting.
	if not straight_h and not straight_v:
		var box := lanes[0]
		var corners := [[WfcSolver.N, WfcSolver.W, Rect2(r.position, box.position - r.position)],
			[WfcSolver.N, WfcSolver.E, Rect2(box.end.x, r.position.y, r.end.x - box.end.x, box.position.y - r.position.y)],
			[WfcSolver.S, WfcSolver.W, Rect2(r.position.x, box.end.y, box.position.x - r.position.x, r.end.y - box.end.y)],
			[WfcSolver.S, WfcSolver.E, Rect2(box.end, r.end - box.end)]]
		for q: Array in corners:
			var qr: Rect2 = q[2]
			if s[q[0]] == "r" and s[q[1]] == "r" and minf(qr.size.x, qr.size.y) >= 24.0:
				_emit_zone("isl_%d_%d_%d%d" % [x, y, q[0], q[1]], "sidewalk", qr, streets["island"])
	# Parked cars; the art drives down-left, so cars on lanes running
	# down-right (plan x) are mirrored.
	var car_ok := lanes.size() == 1 and lanes[0].size[1 if straight_h else 0] >= float(road_cfg["min_car_width"])
	if straight_h and rng.randf() < float(streets["car_chance"]) and car_ok:
		zones.append({"id": "car_%d_%d" % [x, y], "kind": "roadside", "rect": _arr(lanes[0].grow(-8.0)),
			"people": 0, "allow_on_blocked": true, "flip_h": true, "props": [{"pool": streets["cars"], "count": 1}]})
	elif straight_v and rng.randf() < float(streets["car_chance"]) and car_ok:
		zones.append({"id": "car_%d_%d" % [x, y], "kind": "roadside", "rect": _arr(lanes[0].grow(-8.0)),
			"people": 0, "allow_on_blocked": true, "flip_h": false, "props": [{"pool": streets["cars"], "count": 1}]})


func _emit_zone(id: String, kind: String, r: Rect2, spec: Dictionary) -> void:
	var inner := r.grow(-ZONE_INSET) if minf(r.size.x, r.size.y) > ZONE_INSET * 4.0 else r
	zones.append({"id": id, "kind": kind, "rect": _arr(inner), "people": int(spec.get("people", 0)), "props": spec.get("props", [])})


## Fills each run of house-front cells with plots, doors on the kerb.
func _emit_house_rows() -> void:
	# Keys without art yet are skipped (dev only: the pool is fixed per map_version).
	var has_art := func(k: String) -> bool: return AssetCatalog.has(k) and AssetCatalog.entry(k).has("texture")
	var pool := house_subset((t["buildings"] as Array).filter(has_art), t["house_subset"], map_seed)
	var spec: Dictionary = t["plots"]
	var small := house_subset((spec["small"] as Array).filter(has_art), [int(spec["small_subset"]), 0], map_seed + 1)
	for y in rows:
		var x := 0
		while x < cols:
			if role(x, y) != "house":
				x += 1
				continue
			var start := x
			while x < cols and role(x, y) == "house":
				x += 1
			_plot_buildings(Rect2(start * cell, y * cell, (x - start) * cell, cell), pool, small, "bld_%d_%d" % [start, y])


## The buildings one town uses: a seeded pick of [houses, shops] from the
## pool, so towns differ in look, not only in layout. Order follows the pool.
static func house_subset(pool: Array, counts: Array, seed_value: int) -> Array:
	var r := DetHash.make_rng(seed_value, "house_subset")
	var picked: Array = []
	for want_shop: bool in [false, true]:
		var group := pool.filter(func(k: String) -> bool: return k.contains("_shop_") == want_shop)
		var n := mini(int(counts[1 if want_shop else 0]), group.size())
		for i in n:
			picked.append(group.pop_at(r.randi_range(0, group.size() - 1)))
	return pool.filter(func(k: String) -> bool: return picked.has(k))


## One plot per cell, door facing the pavement (lower left on screen). Rows
## vary: some cells hold a small building on a smaller plot or are left as a
## garden, and every plot shifts sideways and back by a seeded amount, so rows
## don't read as a fence.
func _plot_buildings(run: Rect2, pool: Array, small: Array, id_prefix: String) -> void:
	var spec: Dictionary = t["plots"]
	var n := roundi(run.size.x / cell) if not pool.is_empty() else 0
	var setback: Array = spec["setback"]
	var garden := float(spec["garden_chance"])
	var prev := ""
	for i in n:
		var c := Rect2(run.position.x + i * cell, run.position.y, cell, cell)
		var roll := rng.randf()
		if roll < garden and n > 1:
			_emit_zone("%s_%d_garden" % [id_prefix, i], "garden", c, t["streets"]["plot_garden"])
			prev = ""
			continue
		ground.append({"type": "pavement", "rect": _arr(c)})
		var key: String
		var p := plot
		if roll < garden + float(spec["small_chance"]) and not small.is_empty():
			key = small[rng.randi_range(0, small.size() - 1)]
			p = float(spec["small_plot"])
		else:
			key = pool[rng.randi_range(0, pool.size() - 1)]
		if key == prev and pool.size() > 1 and pool.has(key):  # no identical twins side by side
			key = pool[(pool.find(key) + 1 + rng.randi_range(0, pool.size() - 2)) % pool.size()]
		prev = key
		var slack := cell - p
		var x0 := c.position.x + slack * 0.5 + roundf(rng.randf_range(-0.5, 0.5) * slack * float(spec["jitter"]))
		var y1 := run.end.y - roundf(rng.randf_range(float(setback[0]), minf(float(setback[1]), slack)))
		var r := Rect2(x0, y1 - p, p, p)
		blocked.append({"id": "blk_%s_%d" % [id_prefix, i], "label": "that's inside a house", "rect": _arr(r.grow(PLOT_MARGIN))})
		fixed.append({"id": "%s_%d" % [id_prefix, i], "asset": key, "pos": [r.end.x, r.end.y]})
		if p < plot:
			# Room round a small building: a little yard (placement avoids the plot).
			_emit_zone("%s_%d_yard" % [id_prefix, i], "garden", c, t["streets"]["small_yard"])
	# The strip of the cell behind the plots is a little yard.
	var back := Rect2(run.position, Vector2(run.size.x, run.size.y - plot - float(setback[1]) - PLOT_MARGIN))
	if back.size.y > ZONE_INSET * 4.0:
		_emit_zone(id_prefix + "_yard", "backyard", back, t["streets"]["backyard"])


func _emit_districts() -> void:
	var specs: Dictionary = t["districts"]
	var kinds: Array[String] = []
	var kind_weights: Array[int] = []
	for k: String in specs:
		if k.begins_with("_"):
			continue
		kinds.append(k)
		kind_weights.append(int(specs[k]["weight"]))
	var chunks := _open_chunks()
	if chunks.is_empty():
		return
	# Biggest chunk is the park (with a pond if it has a 2x2 block); the chunk
	# closest to the map centre becomes the fountain plaza.
	var biggest := 0
	var central := 0
	var centre := Vector2(cols, rows) * 0.5
	for i in chunks.size():
		if (chunks[i] as Array).size() > (chunks[biggest] as Array).size():
			biggest = i
		if _chunk_centre(chunks[i]).distance_squared_to(centre) < _chunk_centre(chunks[central]).distance_squared_to(centre):
			central = i
	if central == biggest and chunks.size() > 1:
		central = (biggest + 1) % chunks.size()
	for i in chunks.size():
		var kind: String
		if i == biggest:
			kind = "park"
		elif i == central:
			kind = "plaza"
		else:
			kind = kinds[_weighted(kind_weights)]
		var spec: Dictionary = specs[kind]
		for c: Vector2i in chunks[i]:
			var r := cell_rect(c.x, c.y)
			if String(spec["ground"]) != "":
				ground.append({"type": spec["ground"], "rect": _arr(r)})
			_emit_zone("d%02d_%s_%d_%d" % [i, kind, c.x, c.y], kind, r, spec)
		if i == biggest:
			_add_pond(chunks[i])
		elif i == central:
			var cc := _chunk_anchor(chunks[i])
			fixed.append({"id": "landmark_fountain", "asset": String(t["fountain"]), "pos": [cc.x, cc.y]})


## Open cells split into chunks of about 8 by round-robin flood fill from
## seeded starts, so big open areas become several districts.
func _open_chunks() -> Array:
	var owner_of := {}
	var chunks: Array = []
	for y in rows:
		for x in cols:
			var p := Vector2i(x, y)
			if role(x, y) != "open" or owner_of.has(p):
				continue
			var comp := _component(p)
			var starts: Array[Vector2i] = []
			var n := maxi(1, ceili(comp.size() / 8.0))
			var pool := comp.duplicate()
			for k in n:
				starts.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
			var fronts: Array = []
			for s in starts:
				owner_of[s] = chunks.size()
				chunks.append([s])
				fronts.append([s])
			var grew := true
			while grew:
				grew = false
				for f in fronts.size():
					var next: Array = []
					for c: Vector2i in fronts[f]:
						for o in WfcSolver.OFFSETS:
							var q := c + o
							if role(q.x, q.y) == "open" and not owner_of.has(q):
								owner_of[q] = chunks.size() - n + f
								(chunks[chunks.size() - n + f] as Array).append(q)
								next.append(q)
								grew = true
					fronts[f] = next
	return chunks


func _component(start: Vector2i) -> Array:
	var seen := {start: true}
	var out: Array = [start]
	var i := 0
	while i < out.size():
		var c: Vector2i = out[i]
		i += 1
		for o in WfcSolver.OFFSETS:
			var q := c + o
			if role(q.x, q.y) == "open" and not seen.has(q):
				seen[q] = true
				out.append(q)
	return out


func _chunk_centre(chunk: Array) -> Vector2:
	var sum := Vector2.ZERO
	for c: Vector2i in chunk:
		sum += Vector2(c) + Vector2(0.5, 0.5)
	return sum / float(chunk.size())


## World centre of the chunk cell nearest the chunk's centroid.
func _chunk_anchor(chunk: Array) -> Vector2:
	var centre := _chunk_centre(chunk)
	var best: Vector2i = chunk[0]
	for c: Vector2i in chunk:
		if (Vector2(c) + Vector2(0.5, 0.5)).distance_squared_to(centre) < (Vector2(best) + Vector2(0.5, 0.5)).distance_squared_to(centre):
			best = c
	return cell_rect(best.x, best.y).get_center()


func _add_pond(chunk: Array) -> void:
	var cells := {}
	for c: Vector2i in chunk:
		cells[c] = true
	for c: Vector2i in chunk:
		if cells.has(c + Vector2i(1, 0)) and cells.has(c + Vector2i(0, 1)) and cells.has(c + Vector2i(1, 1)):
			var centre := Vector2(c + Vector2i(1, 1)) * cell
			var radii := Vector2(cell * 0.8, cell * 0.55)
			ground.append({"type": "water", "ellipse": [centre.x, centre.y, radii.x, radii.y]})
			blocked.append({"id": "blk_pond", "label": "that's in the pond", "ellipse": [centre.x, centre.y, radii.x, radii.y]})
			zones.append({"id": "pond_ducks", "kind": "pond", "rect": _arr(Rect2(centre - radii * 0.5, radii)),
				"people": 0, "allow_on_blocked": true, "props": [{"pool": ["duck"], "count": 4}]})
			return


## Joins same-type ground rects that share a whole edge (so pavements and
## road lanes draw as long strips without per-cell seams), then orders them
## so roads paint over pavements.
static func _merge_ground(items: Array) -> Array:
	const ORDER := ["pavement", "plaza", "market", "road_plain", "road", "water"]
	var rects := {}
	var others: Array = []
	for g: Dictionary in items:
		if g.has("rect"):
			var type := String(g["type"])
			if not rects.has(type):
				rects[type] = []
			(rects[type] as Array).append(MapDefinition.rect2(g["rect"]))
		else:
			others.append(g)
	var out: Array = []
	for type: String in ORDER:
		if not rects.has(type):
			continue
		var list: Array = rects[type]
		var merged := true
		while merged:
			merged = false
			for i in list.size():
				for j in range(i + 1, list.size()):
					var a: Rect2 = list[i]
					var b: Rect2 = list[j]
					var row: bool = is_equal_approx(a.position.y, b.position.y) and is_equal_approx(a.size.y, b.size.y) \
						and (is_equal_approx(a.end.x, b.position.x) or is_equal_approx(b.end.x, a.position.x))
					var col: bool = is_equal_approx(a.position.x, b.position.x) and is_equal_approx(a.size.x, b.size.x) \
						and (is_equal_approx(a.end.y, b.position.y) or is_equal_approx(b.end.y, a.position.y))
					if row or col:
						list[i] = a.merge(b)
						list.remove_at(j)
						merged = true
						break
				if merged:
					break
		for r: Rect2 in list:
			out.append({"type": type, "rect": _arr(r)})
	return out + others


func _weighted(w: Array[int]) -> int:
	var total := 0
	for v in w:
		total += v
	var roll := rng.randi_range(0, total - 1)
	for i in w.size():
		roll -= w[i]
		if roll < 0:
			return i
	return 0


static func _arr(r: Rect2) -> Array:
	return [r.position.x, r.position.y, r.size.x, r.size.y]


## The map projected: zones and blocked areas become polygons, objects move
## to screen space, and the ground stays on the plan with its transform.
func _to_dict() -> Dictionary:
	var out_blocked: Array = []
	for b: Dictionary in blocked:
		var e := {"id": b["id"], "label": b["label"]}
		if b.has("rect"):
			e["polygon"] = _proj_rect(MapDefinition.rect2(b["rect"]))
		else:
			var el: Array = b["ellipse"]
			var pts: Array = []
			for p in PlaceholderArt.ellipse_points(Vector2(el[0], el[1]), float(el[2]), float(el[3]), 28):
				pts.append(_proj(p))
			e["polygon"] = pts
		out_blocked.append(e)
	var out_zones: Array = []
	var v := Rect2(Vector2.ZERO, view).grow(-VIEW_MARGIN)
	var screen := PackedVector2Array([v.position, Vector2(v.end.x, v.position.y), v.end, Vector2(v.position.x, v.end.y)])
	for z: Dictionary in zones:
		var poly := PackedVector2Array()
		for p: Array in _proj_rect(MapDefinition.rect2(z["rect"])):
			poly.append(Vector2(p[0], p[1]))
		var e := _clip_zone(z, poly, screen)
		if not e.is_empty():
			out_zones.append(e)
	var out_fixed: Array = []
	for f: Dictionary in fixed:
		var e := f.duplicate()
		e["pos"] = _proj(MapDefinition.vec2(f["pos"]))
		out_fixed.append(e)
	var inv := xf.affine_inverse()
	var plan := Rect2(inv * Vector2.ZERO, Vector2.ZERO)
	for c in [Vector2(view.x, 0), view, Vector2(0, view.y)]:
		plan = plan.expand(inv * c)
	return {
		"map_id": t["map_id"],
		"map_version": t["map_version"],
		"title": t.get("title", t["map_id"]),
		"ground_style": t.get("ground_style", ""),
		"default_seed": t.get("default_seed", 0),
		"world_bounds": [0, 0, view.x, view.y],
		"projection": {"x": [xf.x.x, xf.x.y], "y": [xf.y.x, xf.y.y], "origin": [xf.origin.x, xf.origin.y], "plan_bounds": _arr(plan.grow(cell))},
		"ground": ground,
		"blocked": out_blocked,
		"zones": out_zones,
		"paths": [],
		"fixed_objects": out_fixed,
	}


## The zone's on-screen part with counts scaled to it, or {} if too little shows.
func _clip_zone(z: Dictionary, poly: PackedVector2Array, screen: PackedVector2Array) -> Dictionary:
	var full := _area(poly)
	var best := PackedVector2Array()
	for piece in Geometry2D.intersect_polygons(poly, screen):
		if _area(piece) > _area(best):
			best = piece
	var frac := _area(best) / maxf(full, 1.0)
	if frac < MIN_ZONE_ON_SCREEN:
		return {}
	var e := z.duplicate(true)
	e.erase("rect")
	if frac < 0.999:
		e["people"] = roundi(int(z["people"]) * frac)
		var props: Array = []
		for rule: Dictionary in z["props"]:
			var n := roundi(int(rule["count"]) * frac)
			if n > 0:
				props.append({"pool": rule["pool"], "count": n})
		e["props"] = props
		if int(e["people"]) == 0 and props.is_empty():
			return {}
	var pts: Array = []
	for p in (best if frac < 0.999 else poly):
		pts.append([roundf(p.x), roundf(p.y)])
	e["polygon"] = pts
	return e


static func _area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		a += p[i].cross(p[(i + 1) % p.size()])
	return absf(a) * 0.5


func _proj(p: Vector2) -> Array:
	var q := xf * p
	return [roundf(q.x), roundf(q.y)]


func _proj_rect(r: Rect2) -> Array:
	return [_proj(r.position), _proj(Vector2(r.end.x, r.position.y)), _proj(r.end), _proj(Vector2(r.position.x, r.end.y))]
