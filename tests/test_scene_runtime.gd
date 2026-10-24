extends TestSuite
## Instantiates the real town scene: tap mapping, depth setup, restart hygiene,
## free placement in hide mode.

const TOWN_SCENE := "res://scenes/town/town_demo.tscn"
const SEED := 481516


func _look() -> Dictionary:
	return AvatarKit.normalize(AvatarKit.presets()[2]["look"])


func _challenge() -> ChallengeData:
	var m := load_map()
	var layout := TownGenerator.generate(m, SEED)
	return ChallengeData.create(layout, _look(), "Tester", find_visible_spot(m, layout, _look(), Vector2(900, 650)))


func _spawn(mode: int, c: ChallengeData = null) -> Node:
	var app_state: Node = tree.root.get_node("AppState")
	app_state.mode = mode
	app_state.challenge = c
	app_state.map_seed = SEED
	app_state.my_avatar = {"name": "Tester", "look": _look()}
	var scene: Node = load(TOWN_SCENE).instantiate()
	tree.root.add_child(scene)
	await tree.process_frame
	await tree.process_frame
	return scene


func test_tap_selection_after_pan_and_zoom() -> void:
	var app_state: Node = tree.root.get_node("AppState")
	var scene: Node = await _spawn(app_state.Mode.SEARCH, _challenge())
	var town: TownController = scene.town
	var cam: MapCamera = scene.camera
	var sc: SearchController = scene.controller
	var target := town.target
	if not check(target != null, "target placed"):
		scene.free()
		return
	var views := [[target.position, 1.0], [target.position + Vector2(200, -120), 0.6], [target.position + Vector2(-90, 60), 2.2], [target.position, cam.min_zoom]]
	for view: Array in views:
		cam.set_view(view[0], view[1])
		await tree.process_frame
		var screen: Vector2 = tree.root.get_canvas_transform() * (target.position + Vector2(0, -40))
		var world := cam.screen_to_world(screen)
		check(world.distance_to(target.position + Vector2(0, -40)) < 0.5, "screen->world round trip at zoom %.2f" % view[1])
		check(town.character_at(world, MapCamera.TAP_MAX_MOVE / cam.zoom.x) == target, "tap hits target at view %s zoom %.2f" % [view[0], view[1]])
	var other: CharacterActor = null
	for ch in town.characters():
		if ch != target and ch.position.distance_to(target.position) > 300:
			other = ch
			break
	check(sc.handle_tap(other.position + Vector2(0, -30)) == null, "taps are ignored before Start")
	sc.begin()
	var hit := sc.handle_tap(other.position + Vector2(0, -30))
	check(hit == other, "wrong tap returns the tapped person")
	check(not sc.found, "wrong tap does not win")
	hit = sc.handle_tap(target.position + Vector2(0, -30))
	check(hit == target and sc.found, "correct tap wins")
	scene.free()


func test_depth_setup() -> void:
	var app_state: Node = tree.root.get_node("AppState")
	var scene: Node = await _spawn(app_state.Mode.SEARCH, _challenge())
	var town: TownController = scene.town
	check(town.world.y_sort_enabled, "world node is Y-sorted")
	var layout := TownGenerator.generate(load_map(), SEED)
	for o in layout.objects:
		var n := town.world.get_node_or_null(NodePath(o.id)) as Node2D
		if not check(n != null, "node for %s" % o.id):
			continue
		check(n.position == o.world_position, "%s origin is its ground point" % o.id)
		if o.depth_mode == "ground":
			check(n.z_index < 0, "%s ground decal below people" % o.id)
	var canopies := 0
	for p in town.props():
		if p.canopy:
			canopies += 1
			check(p.canopy.z_index > 0 and p.canopy.get_parent() == p, "%s canopy is a raised child" % p.object_id)
	check(canopies > 20, "trees/stalls have canopy layers (%d)" % canopies)
	scene.free()


func test_restart_has_no_duplicates() -> void:
	var app_state: Node = tree.root.get_node("AppState")
	var c := _challenge()
	var expected := TownGenerator.generate(load_map(), SEED).objects.size() + 1
	for run in 3:
		var scene: Node = await _spawn(app_state.Mode.SEARCH, c)
		var town: TownController = scene.town
		check_eq(town.world.get_child_count(), expected, "world children on run %d" % run)
		var targets := 0
		for n in town.world.get_children():
			if n.name == TownController.TARGET_ID:
				targets += 1
		check_eq(targets, 1, "exactly one target on run %d" % run)
		check_eq(town.target.position, c.target_world_position, "target position on run %d" % run)
		check(town.target.marker == WorldActor.Marker.NONE, "target not pre-revealed on run %d" % run)
		scene.free()
		await tree.process_frame


func test_twins_of_the_hider_are_changed() -> void:
	var m := load_map()
	var layout := TownGenerator.generate(m, SEED)
	var twin: WorldObjectData = null
	for o in layout.objects:
		if o.is_interactive and o.source == "generated":
			twin = o
			break
	var town := TownController.new()
	tree.root.add_child(town)
	town.build(m, layout)
	var original := twin.look.duplicate()
	var changed := town.ensure_unique(original)
	check(changed.has(twin.id), "the twin was changed")
	check(AvatarKit.look_key(twin.look) != AvatarKit.look_key(original), "twin's look differs from the hider now")
	var node := town.world.get_node(NodePath(twin.id)) as CharacterActor
	check_eq(AvatarKit.look_key(node.look), AvatarKit.look_key(layout.get_object(twin.id).look), "node redrawn with the new look")
	check(AvatarKit.validate(node.look) == "", "changed look is still a valid kit look")
	town.free()


func test_hide_mode_free_placement() -> void:
	var app_state: Node = tree.root.get_node("AppState")
	var scene: Node = await _spawn(app_state.Mode.HIDE)
	var hc: HideController = scene.controller
	var town: TownController = scene.town
	check(town.target == null, "no avatar before the first tap")
	check(hc.confirm() == null, "can't confirm before placing")
	# Behind the shop facades: hidden, so confirm stays disabled.
	var r := hc.place_at(Vector2(610, 590))
	check(not r["ok"] and town.target.marker == WorldActor.Marker.PREVIEW_BAD, "buried spot shows as invalid")
	check(hc.confirm() == null, "confirm refused while invalid")
	# Anywhere visible is fine, including the pond (no walkable-area rule).
	var pond := Vector2(2560, 420)
	r = hc.place_at(pond)
	check(r["ok"], "standing in the pond is allowed when visible (%.2f)" % r["fraction"])
	var good := find_visible_spot(town.map_def, town.layout, _look(), Vector2(900, 650))
	r = hc.place_at(good + Vector2(0.4, -0.3))
	check(r["ok"] and town.target.position == good, "placement snaps to whole pixels and passes")
	var c := hc.confirm()
	check(c != null and c.target_world_position == good and c.hider_name == "Tester", "confirm builds the challenge")
	if c:
		check_eq(SearchController.verify(c, town.map_def, town.layout), "", "the new challenge verifies for the seeker")
		DirAccess.remove_absolute("%s/%s.json" % [ChallengeCodec.SAVE_DIR, c.challenge_id])
	scene.free()


func test_museum_search_taps_critters() -> void:
	var m := MapDefinition.load_map(AppState.MUSEUM_MAP_ID)
	var layout := TownGenerator.generate(m, SEED)
	var key := TownGenerator.critter_for_seed(SEED)
	var checker := VisibilityChecker.new(m, layout.objects)
	var spot := Vector2.INF
	for y in range(300, 1500, 40):
		for x in range(900, 1600, 40):
			if m.blocked_label_at(Vector2(x, y)) == "" and checker.check_subject(VisibilityChecker.subject_for_critter(key), Vector2(x, y))["fraction"] >= 0.95:
				spot = Vector2(x, y)
				break
		if spot.is_finite():
			break
	var c := ChallengeData.create_critter(layout, key, "Tester", spot)
	var app_state: Node = tree.root.get_node("AppState")
	app_state.map_id = AppState.MUSEUM_MAP_ID
	var scene: Node = await _spawn(app_state.Mode.SEARCH, c)
	var town: TownController = scene.town
	var sc: SearchController = scene.controller
	check(town.target is PropActor and town.target.asset_key == key, "hidden critter placed as %s" % key)
	check((town.target as PropActor).material == null, "hidden critter keeps its original colours")
	var decoy: PropActor = null
	for p in town.props():
		if p != town.target and p.is_critter() and p.position.distance_to(spot) > 200:
			decoy = p
			break
	check(decoy != null and decoy.material != null, "decoys are hue-shifted")
	sc.begin()
	for person in town.characters():
		var at := person.position + Vector2(0, -30)
		if town.critter_at(at, 8.0) == null:
			check(sc.handle_tap(at) == null and not sc.found, "visitors aren't guesses in the museum")
			break
	var centre := decoy.hit_rect(0).get_center()
	check(sc.handle_tap(centre) == decoy and not sc.found, "tapping a decoy is a wrong guess")
	check(sc.handle_tap(town.target.hit_rect(0).get_center()) == town.target and sc.found, "tapping the hidden critter wins")
	app_state.map_id = AppState.TOWN_MAP_ID
	scene.free()
