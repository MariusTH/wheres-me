extends TestSuite
## Export -> import must preserve every field; bad input gives clear errors.

const SEED := 481516


func _make() -> Array:
	var m := load_map()
	var layout := TownGenerator.generate(m, SEED)
	var look := AvatarKit.normalize(AvatarKit.presets()[4]["look"])
	var c := ChallengeData.create(layout, look, "Alex", find_visible_spot(m, layout, look))
	c.wrong_tap_limit = 3
	c.show_target_on_finish = false
	return [c, m, layout]


func _check_same(a: ChallengeData, b: ChallengeData, how: String) -> void:
	if not check(b != null, "%s: decode returned null" % how):
		return
	check_eq(b.schema_version, a.schema_version, how + " schema_version")
	check_eq(b.map_id, a.map_id, how + " map_id")
	check_eq(b.map_version, a.map_version, how + " map_version")
	check_eq(b.generator_version, a.generator_version, how + " generator_version")
	check_eq(b.map_seed, a.map_seed, how + " seed")
	check_eq(b.challenge_id, a.challenge_id, how + " challenge_id")
	check_eq(b.hider_name, a.hider_name, how + " hider name")
	check_eq(AvatarKit.look_key(b.hider_look), AvatarKit.look_key(a.hider_look), how + " hider look")
	check_eq(b.target_object_id, a.target_object_id, how + " target object id")
	check_eq(b.target_world_position, a.target_world_position, how + " target position")
	check_eq(b.wrong_tap_limit, a.wrong_tap_limit, how + " wrong_tap_limit")
	check_eq(b.show_target_on_finish, a.show_target_on_finish, how + " show_target_on_finish")


func test_share_code_round_trip() -> void:
	var c: ChallengeData = _make()[0]
	var code := ChallengeCodec.encode(c)
	check(code.begins_with(ChallengeCodec.CODE_PREFIX), "code prefix")
	check(not code.contains("+") and not code.contains("/") and not code.contains("="), "code must be URL-safe")
	var r := ChallengeCodec.decode(code)
	check_eq(r["error"], "", "decode error")
	_check_same(c, r["challenge"], "code")
	# Codes pasted from chat apps often gain line breaks / spaces.
	var mangled := "  " + code.substr(0, 20) + "\n" + code.substr(20) + " \n"
	_check_same(c, ChallengeCodec.decode(mangled)["challenge"], "code with whitespace")


func test_json_and_file_round_trip() -> void:
	var c: ChallengeData = _make()[0]
	_check_same(c, ChallengeCodec.decode(ChallengeCodec.to_json(c))["challenge"], "json")
	var path := ChallengeCodec.save_to_file(c)
	check(path != "", "save_to_file returned a path")
	_check_same(c, ChallengeCodec.load_from_file(path)["challenge"], "file")
	DirAccess.remove_absolute(path)


func test_long_name_is_truncated() -> void:
	var c: ChallengeData = _make()[0]
	var d := c.to_dict()
	d["hider"]["name"] = "  " + "x".repeat(60) + "  "
	var r := ChallengeCodec.decode(JSON.stringify(d))
	check(r["challenge"] != null and (r["challenge"] as ChallengeData).hider_name.length() == AvatarKit.MAX_NAME_LENGTH, "name clamped to %d chars" % AvatarKit.MAX_NAME_LENGTH)


func test_rejects_malformed_input() -> void:
	var c: ChallengeData = _make()[0]
	var good: Dictionary = c.to_dict()
	var cases := {
		"empty": "",
		"plain text": "hello friend",
		"bad base64": "WM1-!!!***",
		"base64 of non-json": "HF1-" + Marshalls.utf8_to_base64("not json at all"),
		"json array": "[1, 2, 3]",
	}
	var variants := {
		"old schema": {"schema_version": 1},
		"future schema": {"schema_version": ChallengeData.SCHEMA_VERSION + 1},
		"unknown map": {"map_id": "atlantis"},
		"negative seed": {"seed": -5},
		"fractional seed": {"seed": 1.5},
		"missing generator version": {"generator_version": null},
		"missing hider": {"hider": null},
		"bad look value": {"hider": {"name": "A", "look": {"hat": "crown"}}},
		"unknown look part": {"hider": {"name": "A", "look": {"wings": true}}},
		"bad name type": {"hider": {"name": 5, "look": {}}},
		"missing target": {"target": null},
		"bad position": {"target": {"object_id": "target_player", "world_position": [1]}},
	}
	for k: String in variants:
		var d := good.duplicate(true)
		for field: String in variants[k]:
			d[field] = variants[k][field]
		cases[k] = JSON.stringify(d)
	for k: String in cases:
		var r := ChallengeCodec.decode(cases[k])
		check(r["challenge"] == null and String(r["error"]) != "", "case '%s' should be rejected with a message" % k)


func test_search_verifies_challenge_against_map() -> void:
	var made := _make()
	var c: ChallengeData = made[0]
	var m: MapDefinition = made[1]
	var layout: TownLayout = made[2]
	var copy := func() -> ChallengeData: return ChallengeCodec.decode(ChallengeCodec.to_json(c))["challenge"]
	check_eq(SearchController.verify(c, m, layout), "", "valid challenge")
	var bad_version: ChallengeData = copy.call()
	bad_version.map_version = 99
	check(SearchController.verify(bad_version, m, layout).contains("map version"), "map version mismatch detected")
	var bad_gen: ChallengeData = copy.call()
	bad_gen.generator_version = 99
	check(SearchController.verify(bad_gen, m, layout).contains("generator"), "generator mismatch detected")
	var buried: ChallengeData = copy.call()
	buried.target_world_position = Vector2(610, 590)  # just behind the shop facades
	check(SearchController.verify(buried, m, layout).contains("visible"), "hidden-behind-building spot rejected: '%s'" % SearchController.verify(buried, m, layout))
	var outside: ChallengeData = copy.call()
	outside.target_world_position = Vector2(-50, 300)
	check(SearchController.verify(outside, m, layout).contains("outside"), "off-map spot rejected")


func test_legacy_and_v2_codes_still_load() -> void:
	var c: ChallengeData = _make()[0]
	var legacy := "HF1-" + ChallengeCodec.encode(c).substr(ChallengeCodec.CODE_PREFIX.length())
	check_eq(ChallengeCodec.decode(legacy)["error"], "", "HF1- code from before the rename decodes")
	var d := c.to_dict()
	d["schema_version"] = 2
	var r := ChallengeCodec.from_dict(d)
	check_eq(r["error"], "", "schema v2 (avatar only) still loads")


func _museum() -> Array:
	var m := MapDefinition.load_map(AppState.MUSEUM_MAP_ID)
	var layout := TownGenerator.generate(m, SEED)
	var key := TownGenerator.critter_for_seed(SEED)
	var checker := VisibilityChecker.new(m, layout.objects)
	var subject := VisibilityChecker.subject_for_critter(key)
	var spot := Vector2.INF
	for y in range(200, 1500, 40):
		for x in range(100, 2300, 40):
			var p := Vector2(x, y)
			if m.blocked_label_at(p) == "" and checker.check_subject(subject, p)["fraction"] >= 0.95:
				spot = p
				break
		if spot.is_finite():
			break
	return [ChallengeData.create_critter(layout, key, "Alex", spot), m, layout]


func test_critter_challenge_round_trip_and_verify() -> void:
	var arr := _museum()
	var c: ChallengeData = arr[0]
	check(c.target_world_position.is_finite(), "found a visible museum spot")
	var r := ChallengeCodec.decode(ChallengeCodec.encode(c))
	check_eq(r["error"], "", "critter code decodes")
	var b: ChallengeData = r["challenge"]
	check_eq(b.hider_critter, c.hider_critter, "critter preserved")
	check(b.hider_look.is_empty(), "no avatar look for a critter")
	check_eq(b.seeker_title(), "Find the %s!" % AssetCatalog.label(c.hider_critter), "seeker title names the critter")
	check_eq(SearchController.verify(b, arr[1], arr[2]), "", "critter challenge verifies")
	var wrong := ChallengeCodec.decode(ChallengeCodec.encode(c))["challenge"] as ChallengeData
	for k in AssetCatalog.critters():
		if k != c.hider_critter:
			wrong.hider_critter = k
			break
	check(SearchController.verify(wrong, arr[1], arr[2]).contains("critter"), "critter that doesn't match the seed is rejected")
	var d := c.to_dict()
	d["hider"]["critter"] = "bench"
	check(ChallengeCodec.from_dict(d)["error"] != "", "a non-critter asset can't be the hidden critter")


func test_decoy_critters_never_match_the_hidden_one() -> void:
	var layout: TownLayout = _museum()[2]
	var critters := 0
	for o in layout.objects:
		if AssetCatalog.is_critter(o.asset_key):
			critters += 1
			check(o.hue >= TownGenerator.DECOY_MIN_HUE and o.hue <= 1.0 - TownGenerator.DECOY_MIN_HUE, "%s is visibly hue-shifted" % o.id)
	check(critters >= 40, "museum has plenty of decoy critters (%d)" % critters)
