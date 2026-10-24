class_name TownGenerator
extends RefCounted
## Deterministic town dressing: authored base layout + seeded placements.
## Same map_version + GENERATOR_VERSION + seed => identical object IDs, asset
## keys, positions and crowd looks. Bump GENERATOR_VERSION whenever a change
## here would move anything, so old challenges are rejected instead of
## silently pointing at the wrong spot.

## v2: crowd looks from the part kit, no candidate hide points.
const GENERATOR_VERSION := 2
const PERSON_RADIUS := 12.0
const PLACEMENT_ATTEMPTS := 40
const PATH_PLACEMENT_ATTEMPTS := 12
const GRID_CELL := 64.0
const EDGE_MARGIN := 20.0
## Catalog entry used for every generated crowd member (look comes from the kit).
const CROWD_ASSET := "person"
## Decoy critters are hue-shifted by at least this much (turns), so the
## original-coloured hidden critter is always unique.
const DECOY_MIN_HUE := 0.12


static func generate(map_def: MapDefinition, map_seed: int) -> TownLayout:
	var layout := TownLayout.new()
	layout.map_id = map_def.map_id
	layout.map_version = map_def.map_version
	layout.generator_version = GENERATOR_VERSION
	layout.map_seed = map_seed
	var grid := SpatialGrid.new(GRID_CELL)

	for fixed: Dictionary in map_def.fixed_objects:
		var obj := make_object(String(fixed["id"]), String(fixed["asset"]), MapDefinition.vec2(fixed["pos"]), "fixed")
		obj.flip_h = bool(fixed.get("flip_h", false))
		_add(layout, grid, obj)

	for zone in map_def.zones:
		_dress_zone(zone, map_def, map_seed, grid, layout)
	for path in map_def.paths:
		_populate_path(path, map_def, map_seed, grid, layout)
	return layout


## The critter a museum challenge hides. Derived from the seed, so the share
## code doesn't need to choose it (it is still stored, for verification).
static func critter_for_seed(map_seed: int) -> String:
	var all := AssetCatalog.critters()
	return all[DetHash.sub_seed(map_seed, "hidden_critter") % all.size()]


## Builds a WorldObjectData with catalog-derived depth/occlusion fields.
static func make_object(id: String, asset_key: String, pos: Vector2, source: String) -> WorldObjectData:
	var e := AssetCatalog.entry(asset_key)
	var obj := WorldObjectData.new()
	obj.id = id
	obj.asset_key = asset_key
	obj.world_position = pos
	obj.source = source
	obj.depth_mode = String(e.get("depth", "y_sort"))
	obj.tags = PackedStringArray(e.get("tags", []))
	if e.has("ground_point"):
		obj.ground_point_offset = MapDefinition.vec2(e["ground_point"])
	obj.is_interactive = String(e.get("kind", "")) == "character"
	if obj.is_interactive:
		obj.look = AvatarKit.normalize(e.get("look", {}))
	if e.get("canopy", false):
		obj.occlusion_role = "foreground_occluder"
	elif not (e.get("occluders", []) as Array).is_empty():
		obj.occlusion_role = "opaque"
	return obj


static func _add(layout: TownLayout, grid: SpatialGrid, obj: WorldObjectData) -> void:
	layout.objects.append(obj)
	var r := AssetCatalog.radius(obj.asset_key)
	if obj.is_interactive:
		r = PERSON_RADIUS
	if r > 0.0:
		grid.insert(obj.world_position, r)


static func _dress_zone(zone: PlacementZone, map_def: MapDefinition, map_seed: int, grid: SpatialGrid, layout: TownLayout) -> void:
	var rng := DetHash.make_rng(map_seed, zone.id)
	var prop_index := 0
	for rule in zone.prop_rules:
		var pool: Array = rule["pool"]
		for i in int(rule["count"]):
			var key := String(pool[rng.randi_range(0, pool.size() - 1)])
			var pos := _find_spot(rng, zone, map_def, grid, AssetCatalog.radius(key))
			if not pos.is_finite():
				layout.shortfalls.append("%s: no room for prop %s" % [zone.id, key])
				continue
			var obj := make_object("%s_p%02d" % [zone.id, prop_index], key, pos, "generated")
			obj.flip_h = rng.randf() < 0.5
			# Only critters draw a hue, so maps without them keep their streams.
			if AssetCatalog.is_critter(key):
				obj.hue = rng.randf_range(DECOY_MIN_HUE, 1.0 - DECOY_MIN_HUE)
			_add(layout, grid, obj)
			prop_index += 1
	var person_index := 0
	for i in zone.people:
		var look := AvatarKit.random_look(rng)
		var pos := _find_spot(rng, zone, map_def, grid, PERSON_RADIUS)
		if not pos.is_finite():
			layout.shortfalls.append("%s: no room for person %d" % [zone.id, i])
			continue
		var obj := make_object("%s_c%03d" % [zone.id, person_index], CROWD_ASSET, pos, "generated")
		obj.look = look
		obj.flip_h = rng.randf() < 0.5
		_add(layout, grid, obj)
		person_index += 1


static func _find_spot(rng: RandomNumberGenerator, zone: PlacementZone, map_def: MapDefinition, grid: SpatialGrid, r: float) -> Vector2:
	var inner := map_def.world_bounds.grow(-EDGE_MARGIN)
	for attempt in PLACEMENT_ATTEMPTS:
		var p := zone.random_point(rng)
		if not zone.contains(p) or not inner.has_point(p):
			continue
		if not zone.allow_on_blocked and map_def.blocked_label_at(p) != "":
			continue
		if grid.overlaps(p, r):
			continue
		return p
	return Vector2.INF


## People spread along a path, one per equal segment with seeded jitter.
static func _populate_path(path: MapPath, map_def: MapDefinition, map_seed: int, grid: SpatialGrid, layout: TownLayout) -> void:
	if path.people <= 0:
		return
	var rng := DetHash.make_rng(map_seed, path.id)
	var inner := map_def.world_bounds.grow(-EDGE_MARGIN)
	var person_index := 0
	for i in path.people:
		var look := AvatarKit.random_look(rng)
		var flip := rng.randf() < 0.5
		for attempt in PATH_PLACEMENT_ATTEMPTS:
			var t := (float(i) + rng.randf()) / float(path.people)
			var normal := path.tangent_at(t).orthogonal()
			var p := path.point_at(t) + normal * rng.randf_range(-path.width * 0.4, path.width * 0.4)
			p = p.round()
			if not inner.has_point(p) or map_def.blocked_label_at(p) != "" or grid.overlaps(p, PERSON_RADIUS):
				continue
			var obj := make_object("%s_c%03d" % [path.id, person_index], CROWD_ASSET, p, "generated")
			obj.look = look
			obj.flip_h = flip
			obj.tags.append("on_path")
			_add(layout, grid, obj)
			person_index += 1
			break


## Uniform grid of occupied circles for fast minimum-spacing checks.
class SpatialGrid:
	var cell: float
	var cells: Dictionary = {}
	var max_radius: float = 0.0

	func _init(cell_size: float) -> void:
		cell = cell_size

	func _key(p: Vector2) -> Vector2i:
		return Vector2i(floori(p.x / cell), floori(p.y / cell))

	func insert(p: Vector2, r: float) -> void:
		var k := _key(p)
		if not cells.has(k):
			cells[k] = []
		(cells[k] as Array).append(Vector3(p.x, p.y, r))
		max_radius = maxf(max_radius, r)

	func overlaps(p: Vector2, r: float) -> bool:
		var reach := ceili((r + max_radius) / cell)
		var k := _key(p)
		for dx in range(-reach, reach + 1):
			for dy in range(-reach, reach + 1):
				for e: Vector3 in cells.get(k + Vector2i(dx, dy), []):
					if Vector2(e.x, e.y).distance_to(p) < e.z + r:
						return true
		return false
