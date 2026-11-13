extends TestSuite
## The procedural isometric town (data/maps/town_iso.json): the seed alone
## must rebuild the same map, every map must be playable, and sliced building
## depth must hold (people beside a wall sort by the wall in front of them).

const MAP_ID := "town_iso"
const SEED := 481516
const SEEDS := [481516, 1, 7, 2024]
const HOUSE := "iso_house_sage"
## SHA-256 of TownLayout.signature() for town_iso v3, generator v2, seed
## 481516. If this changes, existing challenges would point at wrong spots:
## bump map_version in data/maps/town_iso.json and update this value.
const GOLDEN_SHA256 := "45067f04bcfb4ac8edc7ec52d80d49fc589156dab529c4aa9df9a51947542ecb"


func _template() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(MapDefinition.map_path(MAP_ID)))


func test_same_seed_same_map_and_layout() -> void:
	var a := MapDefinition.load_map(MAP_ID, SEED)
	var b := MapDefinition.load_map(MAP_ID, SEED)
	check_eq(JSON.stringify(a.fixed_objects), JSON.stringify(b.fixed_objects), "fixed objects")
	check_eq(TownGenerator.generate(a, SEED).signature(), TownGenerator.generate(b, SEED).signature(), "dressing")
	check(a.ground_transform != Transform2D.IDENTITY, "iso map carries its ground projection")


func test_global_rng_does_not_leak_in() -> void:
	seed(1)
	var a := WfcTown.build(_template(), SEED)
	randomize()
	randi()
	var b := WfcTown.build(_template(), SEED)
	check_eq(JSON.stringify(a), JSON.stringify(b), "map built after reseeding the global RNG")


func test_different_seeds_give_different_towns() -> void:
	var layouts := {}
	for s: int in SEEDS:
		layouts[JSON.stringify(WfcTown.build(_template(), s)["fixed_objects"])] = true
	check_eq(layouts.size(), SEEDS.size(), "distinct building layouts across seeds")


func test_roads_connect_and_houses_face_a_kerb() -> void:
	for s: int in SEEDS:
		var w := WfcTown.new()
		w._setup(_template())
		w._solve(s)
		var roads := 0
		for y in w.rows:
			for x in w.cols:
				if w.role(x, y) == "road":
					roads += 1
				if w.role(x, y) == "house":
					check(w.role(x, y + 1) == "road" and w.sockets(x, y + 1)[WfcSolver.N] == "k", "seed %d: house at %d,%d must face a pavement" % [s, x, y])
		check(w._roads_connected(roads), "seed %d: road network must be connected" % s)


func test_challenge_round_trip_rebuilds_same_target() -> void:
	var m := MapDefinition.load_map(MAP_ID, SEED)
	var layout := TownGenerator.generate(m, SEED)
	var look := AvatarKit.default_look()
	var spot := find_visible_spot(m, layout, look, Vector2(600, 600), 0.7)
	if not check(spot.is_finite(), "no visible hiding spot found"):
		return
	var decoded: Dictionary = ChallengeCodec.decode(ChallengeCodec.encode(ChallengeData.create(layout, look, "Tester", spot)))
	if not check(decoded["challenge"] != null, "decode failed: %s" % decoded.get("error", "")):
		return
	var back: ChallengeData = decoded["challenge"]
	check_eq(back.map_id, MAP_ID, "map id")
	var rebuilt := TownGenerator.generate(MapDefinition.load_map(back.map_id, back.map_seed), back.map_seed)
	check_eq(rebuilt.signature(), layout.signature(), "town rebuilt from the code")


func test_every_seed_passes_quality_and_fills_the_view() -> void:
	for s: int in SEEDS:
		var w := WfcTown.new()
		w._setup(_template())
		w._solve(s)
		check(w.attempt >= 0, "seed %d: no attempt passed the quality checks" % s)
		var m := MapDefinition.load_map(MAP_ID, s)
		var houses := 0
		var spots := {}
		for f in m.fixed_objects:
			var p := MapDefinition.vec2(f["pos"])
			if String(f["asset"]).begins_with("iso_"):
				houses += 1
				check(not spots.has(p), "seed %d: two houses on one plot" % s)
				spots[p] = true
		check(houses >= 30, "seed %d: expected a real town, got %d houses" % [s, houses])


func test_crowd_is_dense_and_on_screen() -> void:
	var m := MapDefinition.load_map(MAP_ID, SEED)
	var layout := TownGenerator.generate(m, SEED)
	check(layout.count_people() > 600, "crowd too thin (%d)" % layout.count_people())
	for o in layout.objects:
		if o.is_interactive:
			check(m.world_bounds.has_point(o.world_position), "%s outside the view" % o.id)
			check(m.blocked_label_at(o.world_position) == "", "%s stands in %s" % [o.id, m.blocked_label_at(o.world_position)])


func test_dressing_fits_the_view() -> void:
	# Zones are clipped to the screen, so almost everything asked for fits.
	for s: int in [SEED, 7]:
		var m := MapDefinition.load_map(MAP_ID, s)
		var layout := TownGenerator.generate(m, s)
		check(layout.shortfalls.size() < 50, "seed %d: %d placement shortfalls" % [s, layout.shortfalls.size()])
		for o in layout.objects:
			check(AssetCatalog.has(o.asset_key), "seed %d: unknown asset %s" % [s, o.asset_key])


func test_each_town_uses_a_subset_of_buildings() -> void:
	var counts: Array = _template()["house_subset"]
	var looks := {}
	for s: int in SEEDS:
		var keys := {}
		for f in MapDefinition.load_map(MAP_ID, s).fixed_objects:
			var k := String(f["asset"])
			if k.begins_with("iso_house_") or k.begins_with("iso_shop_"):
				keys[k] = true
		check(keys.size() <= int(counts[0]) + int(counts[1]), "seed %d: %d building designs, subset is %s" % [s, keys.size(), counts])
		var sorted := keys.keys()
		sorted.sort()
		looks[str(sorted)] = true
	check(looks.size() > 1, "every seed picked the same buildings")


func test_sliced_house_depth() -> void:
	if not check(not AssetCatalog.strips(HOUSE).is_empty(), "test house has no slices (art missing?)"):
		return
	var m := MapDefinition.load_map(MAP_ID, SEED)
	var gp := m.world_bounds.get_center()
	var house := TownGenerator.make_object("h", HOUSE, gp, "fixed")
	var vc := VisibilityChecker.new(m, [house] as Array[WorldObjectData])
	var look := AvatarKit.default_look()
	# Beside the front-left wall: above the house's ground point on screen,
	# yet in front of the wall, so fully visible.
	check(vc.visible_fraction(look, gp + Vector2(-90, -24)) > 0.97, "person in front of the left wall is drawn behind it")
	check(vc.visible_fraction(look, gp + Vector2(70, -14)) > 0.97, "person in front of the right wall is drawn behind it")
	# Directly behind the house: hidden.
	check(vc.visible_fraction(look, gp + Vector2(0, -140)) < 0.3, "person behind the house shows through it")


func test_build_time_budget() -> void:
	var started := Time.get_ticks_msec()
	for s: int in SEEDS:
		WfcTown.build(_template(), s)
	var avg := (Time.get_ticks_msec() - started) / float(SEEDS.size())
	check(avg < 700.0, "average iso build took %.0f ms" % avg)


func test_golden_signature() -> void:
	var sha := TownGenerator.generate(MapDefinition.load_map(MAP_ID, SEED), SEED).signature().sha256_text()
	check_eq(sha, GOLDEN_SHA256, "golden layout hash (see comment on GOLDEN_SHA256)")
