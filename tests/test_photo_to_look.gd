extends TestSuite
## Selfie measurements -> part kit values (PhotoToLook). The browser side
## (web/selfie.js) is checked by hand; this covers the mapping.


func _features(overrides: Dictionary = {}) -> Dictionary:
	var f := {
		"ok": true, "skin": [228, 180, 150], "hair": [40, 28, 20], "shirt": [200, 40, 40], "hat": null,
		"hair_ratio": 0.5, "hair_below_chin": 0.02, "hair_above_top": 0.05, "glasses": 0.0, "hat_cover": 0.0,
	}
	f.merge(overrides, true)
	return f


func test_result_is_a_valid_look() -> void:
	var look := PhotoToLook.apply(AvatarKit.default_look(), _features())
	check_eq(AvatarKit.validate(look), "", "selfie look passes kit validation")


func test_keeps_parts_a_selfie_cannot_see() -> void:
	var base := AvatarKit.normalize(AvatarKit.presets()[3]["look"])
	var look := PhotoToLook.apply(base, _features())
	for field: String in ["build", "pants", "accessory", "coat"]:
		check_eq(look[field], base[field], "%s kept" % field)


func test_colours_match_nearest_palette_entries() -> void:
	check_eq(PhotoToLook.nearest(Color("#d63c3c"), AvatarKit.values("shirt")), "#d63c3c", "exact colour maps to itself")
	var red := PhotoToLook.apply(AvatarKit.default_look(), _features({"shirt": [190, 35, 40]}))
	check(["#d63c3c", "#e85d5d"].has(red["shirt"]), "photo red shirt -> a red, got %s" % red["shirt"])
	var blue := PhotoToLook.apply(AvatarKit.default_look(), _features({"shirt": [45, 85, 170]}))
	check(["#3d6fd1", "#3d5a99"].has(blue["shirt"]), "photo blue shirt -> a blue, got %s" % blue["shirt"])
	var blond := PhotoToLook.apply(AvatarKit.default_look(), _features({"hair": [200, 165, 90]}))
	check_eq(blond["hair"], "#e6c35c", "blond hair")


func test_skin_tone_order_is_preserved() -> void:
	var skins := AvatarKit.values("skin")
	var light := skins.find(PhotoToLook.apply(AvatarKit.default_look(), _features({"skin": [235, 200, 175]}))["skin"])
	var mid := skins.find(PhotoToLook.apply(AvatarKit.default_look(), _features({"skin": [185, 130, 90]}))["skin"])
	var dark := skins.find(PhotoToLook.apply(AvatarKit.default_look(), _features({"skin": [80, 50, 35]}))["skin"])
	check(light < mid and mid < dark, "light %d < mid %d < dark %d (palette runs light to dark)" % [light, mid, dark])


func test_hair_style_rules() -> void:
	check_eq(PhotoToLook.hair_style(_features()), "short", "default short")
	check_eq(PhotoToLook.hair_style(_features({"hair_ratio": 0.02})), "bald", "little hair -> bald")
	check_eq(PhotoToLook.hair_style(_features({"hair": null})), "bald", "no hair colour -> bald")
	check_eq(PhotoToLook.hair_style(_features({"hair_below_chin": 0.3})), "long", "hair below chin -> long")
	check_eq(PhotoToLook.hair_style(_features({"hair_above_top": 0.3})), "bun", "hair high above forehead -> bun")


func test_glasses_and_hat() -> void:
	var base := AvatarKit.default_look()
	base["glasses"] = true
	base["hat"] = "top"
	var plain := PhotoToLook.apply(base, _features())
	check(not plain["glasses"] and plain["hat"] == "none", "no accessories seen -> glasses and hat removed")
	var dressed := PhotoToLook.apply(AvatarKit.default_look(), _features({"glasses": 0.3, "hat_cover": 0.6, "hat": [40, 60, 150]}))
	check(dressed["glasses"], "glasses detected")
	check_eq(dressed["hat"], "beanie", "hat detected")
	check_eq(AvatarKit.validate(dressed), "", "dressed look valid")
