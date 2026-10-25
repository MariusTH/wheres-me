extends TestSuite
## Same map version + generator version + seed must give the same town.

const SEED := 481516
## SHA-256 of TownLayout.signature() for town_demo_01 v2, generator v2, seed
## 481516. If this changes, existing challenges would point at wrong spots:
## bump TownGenerator.GENERATOR_VERSION (or map_version) and update this value.
const GOLDEN_SHA256 := "6c4769f127032d9dfeb8cd0df274cf164335a765edc382d6c6af1062cf399614"


func test_same_seed_same_layout() -> void:
	var m := load_map()
	var a := TownGenerator.generate(m, SEED)
	var b := TownGenerator.generate(m, SEED)
	check(a.objects.size() > 300, "expected a dense town, got %d objects" % a.objects.size())
	check(a.count_people() > 300, "expected a big crowd, got %d people" % a.count_people())
	check_eq(a.signature(), b.signature(), "two runs with the same seed")


func test_global_rng_does_not_leak_in() -> void:
	var m := load_map()
	seed(1)
	var a := TownGenerator.generate(m, SEED)
	randomize()
	randi()
	var b := TownGenerator.generate(m, SEED)
	check_eq(a.signature(), b.signature(), "generation after reseeding global RNG")


func test_fresh_map_load_same_layout() -> void:
	var a := TownGenerator.generate(load_map(), SEED)
	var b := TownGenerator.generate(load_map(), SEED)
	check_eq(a.signature(), b.signature(), "independently loaded map definitions")


func test_different_seed_changes_dressing_only() -> void:
	var m := load_map()
	var a := TownGenerator.generate(m, SEED)
	var b := TownGenerator.generate(m, SEED + 1)
	check(a.signature() != b.signature(), "different seeds should give different dressing")
	for f in m.fixed_objects:
		var oa := a.get_object(String(f["id"]))
		var ob := b.get_object(String(f["id"]))
		check(oa != null and ob != null and oa.world_position == ob.world_position, "fixed object %s must not move between seeds" % f["id"])


func test_ids_unique_and_stable_format() -> void:
	var a := TownGenerator.generate(load_map(), SEED)
	var seen := {}
	for o in a.objects:
		check(not seen.has(o.id), "duplicate object id %s" % o.id)
		seen[o.id] = true
		check(o.world_position == o.world_position.round(), "position of %s must be integer-snapped" % o.id)


func test_crowd_looks_valid_and_varied() -> void:
	var a := TownGenerator.generate(load_map(), SEED)
	var distinct := {}
	for o in a.objects:
		if not o.is_interactive:
			continue
		check_eq(AvatarKit.validate(o.look), "", "look of %s" % o.id)
		distinct[AvatarKit.look_key(o.look)] = true
	check(distinct.size() > a.count_people() * 0.9, "crowd looks should be nearly all different (%d distinct of %d)" % [distinct.size(), a.count_people()])


func test_golden_signature() -> void:
	var sha := TownGenerator.generate(load_map(), SEED).signature().sha256_text()
	check_eq(sha, GOLDEN_SHA256, "golden layout hash (see comment on GOLDEN_SHA256)")
