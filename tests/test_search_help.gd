extends TestSuite
## "Help when stuck" (SearchHelp) and the mesh recorder (MeshCanvas).

const SEED := 2024


func test_leavers_thin_the_crowd_and_grow_each_stage() -> void:
	var m := MapDefinition.load_map(AppState.TOWN_MAP_ID, SEED, "M")
	var layout := TownGenerator.generate(m, SEED)
	var crowd := 0
	for o in layout.objects:
		if o.is_interactive:
			crowd += 1
	var first := SearchHelp.leavers(layout, 0.3, SEED)
	var second := SearchHelp.leavers(layout, 0.55, SEED)
	check(absi(first.size() - roundi(crowd * 0.3)) <= 1, "about 30%% leave (%d of %d)" % [first.size(), crowd])
	for id: String in first:
		check(second.has(id), "%s stays gone at the next stage" % id)
	check_eq(SearchHelp.leavers(layout, 0.3, SEED), first, "deterministic")


func test_step_out_makes_the_hider_more_visible() -> void:
	var m := MapDefinition.load_map(AppState.TOWN_MAP_ID, SEED, "L")
	var layout := TownGenerator.generate(m, SEED)
	var c := AutoHider.make(m, layout, "expert")
	var subject := VisibilityChecker.subject_for_look(c.hider_look)
	var before := float(VisibilityChecker.new(m, layout.objects).measure(subject, c.target_world_position)["fraction"])
	var gone := SearchHelp.leavers(layout, 0.3, SEED)
	var to := SearchHelp.step_out(m, layout, c.hider_look, c.target_world_position, 0.7, gone)
	var rest: Array[WorldObjectData] = []
	for o in layout.objects:
		if not gone.has(o.id):
			rest.append(o)
	var after := float(VisibilityChecker.new(m, rest).measure(subject, to)["fraction"])
	check(after > before, "more of them shows after (%.2f -> %.2f)" % [before, after])
	check(after >= 0.7 or to.distance_to(c.target_world_position) > 0.0, "reaches 70%% or at least moves (%.2f)" % after)
	check(to.distance_to(c.target_world_position) <= SearchHelp.MAX_STEP + 1.0, "only a short step")


func test_character_mesh_is_cached_and_not_empty() -> void:
	var look := AvatarKit.normalize(AvatarKit.presets()[0]["look"])
	var a := MeshCanvas.character_mesh(look, false)
	check(a.get_surface_count() == 1, "one surface")
	check(a.surface_get_array_len(0) > 300, "has the whole drawing (%d verts)" % a.surface_get_array_len(0))
	check(MeshCanvas.character_mesh(look, false) == a, "same look reuses the mesh")
	check(MeshCanvas.character_mesh(look, true) != a, "mirrored look gets its own")
