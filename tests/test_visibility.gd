extends TestSuite
## The hide rule (half the head and 70% overall must show), measured with the
## real drawing code.

const AVATAR_PRESET := 0


func _look() -> Dictionary:
	return AvatarKit.normalize(AvatarKit.presets()[AVATAR_PRESET]["look"])


## Small synthetic town: open ground plus a few hand-placed objects.
func _checker(objects: Array) -> VisibilityChecker:
	var m := MapDefinition.from_dict({"map_id": "fixture", "map_version": 1, "world_bounds": [0, 0, 1600, 1000]})
	var objs: Array[WorldObjectData] = []
	for spec: Array in objects:
		var o := TownGenerator.make_object(spec[0], spec[1], spec[2], "fixed")
		if o.is_interactive:
			o.look = _look()
		objs.append(o)
	return VisibilityChecker.new(m, objs)


func test_open_ground_fully_visible() -> void:
	var v := _checker([])
	check(is_equal_approx(v.visible_fraction(_look(), Vector2(400, 500)), 1.0), "nothing around: 100%")
	var r := v.check(_look(), Vector2(400, 500))
	check(r["ok"] and r["reason"] == "", "open spot is allowed (no 'too exposed' rule)")


func test_avatar_mask_has_sensible_size() -> void:
	var grid := PackedVector2Array()
	for y in range(-120, 6, 2):
		for x in range(-40, 40, 2):
			grid.append(Vector2(400 + x + 1, 500 + y + 1))
	var canvas := MaskCanvas.new(grid)
	canvas.begin_object(Vector2(400, 500))
	PlaceholderArt.draw_character(canvas, _look(), false)
	# Body ~22x58 px plus head and hat at 2px sampling => a few hundred samples.
	var n := canvas.covered_count()
	check(n > 200 and n < 700, "avatar covers %d samples" % n)


func test_tree_canopy_hides_avatar() -> void:
	var v := _checker([["tree", "tree_round", Vector2(500, 500)]])
	var f := v.visible_fraction(_look(), Vector2(500, 480))
	check(f < 0.5, "standing under the crown, behind the trunk: %.2f" % f)
	check(not v.check(_look(), Vector2(500, 480))["ok"], "rejected")


func test_people_in_front_and_behind() -> void:
	var v := _checker([["p_front", "person", Vector2(700, 530)], ["p_behind", "person", Vector2(1000, 470)]])
	var front := v.visible_fraction(_look(), Vector2(700, 500))
	check(front < VisibilityChecker.MIN_VISIBLE, "person 30px in front covers too much: %.2f" % front)
	var r := v.check(_look(), Vector2(700, 500))
	check(not r["ok"] and String(r["reason"]).contains("%"), "reason quotes the percentage: '%s'" % r["reason"])
	check(is_equal_approx(v.visible_fraction(_look(), Vector2(1000, 500)), 1.0), "person behind doesn't cover")


func test_partial_cover_by_bench_is_allowed() -> void:
	var v := _checker([["bench", "iso_bench", Vector2(900, 512)]])
	var f := v.visible_fraction(_look(), Vector2(900, 500))
	check(f > VisibilityChecker.MIN_VISIBLE and f < 1.0, "bench in front hides only the legs: %.2f" % f)
	check(v.check(_look(), Vector2(900, 500))["ok"], "allowed")


func test_head_must_show_even_when_body_is_visible() -> void:
	# Somewhere at the edge of a tree crown the head is under the leaves while
	# most of the body stands in the open. Feet and legs look alike on
	# everyone, so that spot must be rejected for the head, not accepted for 70%.
	var v := _checker([["tree", "tree_round", Vector2(800, 500)]])
	var found := 0
	for y in range(400, 640, 4):
		for x in range(640, 960, 4):
			var feet := Vector2(x, y)
			var m := v.measure(VisibilityChecker.subject_for_look(_look()), feet)
			if float(m["fraction"]) >= VisibilityChecker.MIN_VISIBLE and float(m["head"]) < VisibilityChecker.MIN_HEAD:
				found += 1
				var r := v.check(_look(), feet)
				if r["ok"] or not String(r["reason"]).contains("head"):
					check(false, "head %.2f / body %.2f at %s should fail on the head: %s" % [m["head"], m["fraction"], feet, r])
					return
	check(found > 0, "found %d spots with the body showing but the head hidden, all rejected" % found)


func test_old_codes_keep_their_rule() -> void:
	check(is_equal_approx(ChallengeData.new().min_head, VisibilityChecker.MIN_HEAD), "new challenges carry the head rule")
	var c := ChallengeData.create(TownGenerator.generate(load_map(), 7), _look(), "Ann", Vector2(400, 500))
	var d := c.to_dict()
	(d["rules"] as Dictionary).erase("min_head")
	var parsed := ChallengeCodec.from_dict(d)
	check(parsed["challenge"] != null, "old-style dict parses: %s" % parsed.get("error", ""))
	if parsed["challenge"] != null:
		check(is_equal_approx((parsed["challenge"] as ChallengeData).min_head, 0.0), "a code without the head rule keeps playing without it")


func test_building_and_decals() -> void:
	var v := _checker([["shop", "iso_shop_bakery", Vector2(300, 700)], ["flowers", "iso_flower_bed", Vector2(1200, 520)]])
	check(v.visible_fraction(_look(), Vector2(300, 640)) < 0.05, "behind a house: hidden")
	check(is_equal_approx(v.visible_fraction(_look(), Vector2(1200, 500)), 1.0), "flat flower bed in front never covers")
	check(v.check(_look(), Vector2(300, 760))["ok"], "in front of the shop: visible")


func test_outside_map_rejected() -> void:
	var v := _checker([])
	check(String(v.check(_look(), Vector2(-10, 500))["reason"]).contains("outside"), "left of the map")
	check(String(v.check(_look(), Vector2(400, 30))["reason"]).contains("outside"), "head above the map")


func test_check_is_fast_enough_for_dragging() -> void:
	var m := load_map()
	var layout := TownGenerator.generate(m, 481516)
	var v := VisibilityChecker.new(m, layout.objects)
	var t0 := Time.get_ticks_usec()
	var n := 0
	for x in range(200, 1400, 60):
		v.check(_look(), Vector2(x, 700))
		n += 1
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / n
	print("        visibility check: %.1f ms average over %d crowded spots" % [ms, n])
	check(ms < 50.0, "average check %.1f ms should stay under 50 ms" % ms)
