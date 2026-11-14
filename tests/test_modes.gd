extends TestSuite
## Game modes: town sizes, difficulty rules, decoys, the computer hider,
## v4 codes, the Daily challenge, Play records and the friend-game loop.
## Saves go to a scratch folder (JsonStore.root), never the player's own.

const SEED := 4242
const TOWN_SCENE := "res://scenes/town/town.tscn"


func _scratch() -> void:
	JsonStore.root = "user://test_saves_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(JsonStore.root)


func _look(i: int = 3) -> Dictionary:
	return AvatarKit.normalize(AvatarKit.presets()[i]["look"])


func test_town_sizes_grow_and_classic_is_unchanged() -> void:
	var classic := MapDefinition.load_map(AppState.TOWN_MAP_ID, SEED)
	var l := MapDefinition.load_map(AppState.TOWN_MAP_ID, SEED, "L")
	check_eq(l.world_bounds, classic.world_bounds, "size L is the classic town")
	check_eq(TownGenerator.generate(l, SEED).signature(), TownGenerator.generate(classic, SEED).signature(), "size L builds the same layout")
	check_eq(Array(MapDefinition.sizes(AppState.TOWN_MAP_ID)), ["S", "M", "L", "XL"], "sizes in order")
	var prev_area := 0.0
	var prev_people := 0
	for size in ["S", "M", "L", "XL"]:
		var m := MapDefinition.load_map(AppState.TOWN_MAP_ID, SEED, size)
		var layout := TownGenerator.generate(m, SEED)
		var people := 0
		for o in layout.objects:
			people += 1 if o.is_interactive else 0
		check(m.world_bounds.get_area() > prev_area, "%s is bigger than the size before" % size)
		check(people > prev_people, "%s has a bigger crowd (%d)" % [size, people])
		prev_area = m.world_bounds.get_area()
		prev_people = people
	var a := TownGenerator.generate(MapDefinition.load_map(AppState.TOWN_MAP_ID, SEED, "S"), SEED).signature()
	var b := TownGenerator.generate(MapDefinition.load_map(AppState.TOWN_MAP_ID, SEED, "S"), SEED).signature()
	check_eq(a, b, "small towns are deterministic too")


func test_difficulty_levels_get_harder() -> void:
	var prev: Dictionary = {}
	for l: Dictionary in Difficulty.LEVELS:
		check(float(l["min_visible"]) < float(l["max_visible"]), "%s band is not empty" % l["id"])
		check(float(l["min_head"]) >= 0.5, "%s keeps at least half the head showing" % l["id"])
		if not prev.is_empty():
			check(float(l["min_visible"]) < float(prev["min_visible"]), "%s hides more than %s" % [l["id"], prev["id"]])
			check(int(l["decoys"]) >= int(prev["decoys"]), "%s has at least as many decoys" % l["id"])
		prev = l
	check(Difficulty.score("normal", true, 30.0, 0) == 1000, "30 s on Normal is 1000 points")
	check(Difficulty.score("expert", true, 30.0, 0) > Difficulty.score("easy", true, 30.0, 0), "harder pays more")
	check(Difficulty.score("normal", true, 20.0, 0) > Difficulty.score("normal", true, 40.0, 0), "faster pays more")
	check(Difficulty.score("normal", true, 30.0, 3) < Difficulty.score("normal", true, 30.0, 0), "wrong taps cost")
	check_eq(Difficulty.score("hard", false, 10.0, 0), 0, "not found scores 0")


func test_head_rule() -> void:
	var m := load_map()
	var layout := TownGenerator.generate(m, AppState.DEFAULT_SEED)
	var v := VisibilityChecker.new(m, layout.objects, 0.1, 0.9)
	var open := find_visible_spot(m, layout, _look(), Vector2(300, 700), 0.99)
	var r := v.check(_look(), open)
	check(r["ok"] and float(r["head"]) > 0.95, "in the open the head shows: %s" % r)
	var buried := v.check(_look(), buried_spot(m))
	check(not buried["ok"], "behind a house the head rule fails")


func test_decoys_are_near_twins_and_stable() -> void:
	var m := MapDefinition.load_map(AppState.TOWN_MAP_ID, SEED, "M")
	var look := _look(5)
	var a := TownGenerator.generate(m, SEED)
	var ids := Decoys.apply(a, look, 6, SEED)
	check_eq(ids.size(), 6, "six decoys")
	var key := AvatarKit.look_key(look)
	for obj in a.objects:
		if ids.has(obj.id):
			var diffs := 0
			for f: String in AvatarKit.field_order():
				if obj.look[f] != look[f]:
					diffs += 1
			check(AvatarKit.look_key(obj.look) != key, "decoy %s is not an exact twin" % obj.id)
			check(diffs >= 1 and diffs <= 2, "decoy %s differs in one part (%d)" % [obj.id, diffs])
	var snapshot := a.signature()
	Decoys.apply(a, look, 6, SEED)
	check_eq(a.signature(), snapshot, "applying decoys twice changes nothing")
	var b := TownGenerator.generate(m, SEED)
	Decoys.apply(b, look, 6, SEED)
	check_eq(b.signature(), snapshot, "same seed and look give the same decoys")


func test_auto_hider_hits_each_band_and_is_deterministic() -> void:
	for id in Difficulty.ids():
		var l := Difficulty.get_level(id)
		var s := 900 + Difficulty.ids().find(id)
		var m := MapDefinition.load_map(AppState.TOWN_MAP_ID, s, String(l["size"]))
		var layout := TownGenerator.generate(m, s)
		var t0 := Time.get_ticks_msec()
		var c := AutoHider.make(m, layout, id)
		var ms := Time.get_ticks_msec() - t0
		check(ms < 6000, "%s: hiding took %d ms" % [id, ms])
		check_eq(c.difficulty, id, "difficulty stored")
		check_eq(c.town_size, String(l["size"]), "size stored")
		# Same check the search screen does, on a freshly built town.
		var fresh := TownGenerator.generate(MapDefinition.load_map(AppState.TOWN_MAP_ID, s, c.town_size), s)
		AutoHider.prepare_crowd(fresh, c.hider_look, c.decoys, s)
		var r := c.checker(m, fresh).check_subject(c.subject(), c.target_world_position)
		check(r["ok"], "%s: spot passes its own rule (%s)" % [id, r])
		check(float(r["fraction"]) <= float(l["max_visible"]) + 0.15, "%s: about as hidden as the level asks (%.2f)" % [id, r["fraction"]])
		var again := AutoHider.make(m, TownGenerator.generate(m, s), id)
		check_eq(again.target_world_position, c.target_world_position, "%s: same seed, same spot" % id)
		check_eq(again.hider_name, c.hider_name, "%s: same seed, same name" % id)


func test_v4_code_round_trip() -> void:
	var m := MapDefinition.load_map(AppState.TOWN_MAP_ID, SEED, "S")
	var layout := TownGenerator.generate(m, SEED)
	var c := AutoHider.make(m, layout, "easy")
	c.from_id = "0123abcd4567"
	c.round = 3
	c.reply = {"to": "c-1-abc", "found": true, "time": 41.5, "taps": 3, "wrong": 1}
	var r := ChallengeCodec.decode("Can you find me? " + ChallengeCodec.encode(c))
	check_eq(r["error"], "", "decodes")
	var b: ChallengeData = r["challenge"]
	if b == null:
		return
	check_eq(b.town_size, "S", "size")
	check_eq(b.difficulty, "easy", "difficulty")
	check(is_equal_approx(b.min_visible, c.min_visible) and is_equal_approx(b.min_head, c.min_head), "hide rule")
	check_eq(b.decoys, c.decoys, "decoys")
	check_eq(b.from_id, c.from_id, "sender")
	check_eq(b.round, 3, "round")
	check_eq(b.reply, c.reply, "reply")
	var d := c.to_dict()
	d["size"] = "XXL"
	check(ChallengeCodec.from_dict(d)["challenge"] == null, "unknown size is rejected")


func test_daily_challenge_records_first_try_and_streak() -> void:
	_scratch()
	var date := "2026-11-16"  # a Monday
	check_eq(Progress.daily_seed(date), Progress.daily_seed(date), "same seed all day")
	check(Progress.daily_seed(date) != Progress.daily_seed("2026-11-17"), "new town every day")
	check_eq(Progress.daily_difficulty(date), "easy", "Monday is easy")
	check_eq(Progress.daily_difficulty("2026-11-21"), "expert", "Saturday is expert")
	check_eq(Progress.daily_number(Progress.DAILY_EPOCH), 1, "first daily is #1")
	var r := Progress.record_daily(date, true, 30.0, 2, 1)
	check(r["counted"] and r["score"] > 0 and r["new_best"], "first try counts: %s" % r)
	check_eq(int(r["streak"]), 1, "streak starts")
	var again := Progress.record_daily(date, true, 5.0, 1, 0)
	check(not again["counted"], "a replay doesn't count")
	check_eq(Progress.best_daily_score(), int(r["score"]), "best score is the counted one")
	var next := Progress.record_daily("2026-11-17", true, 50.0, 1, 0)
	check_eq(int(next["streak"]), 2, "streak grows day by day")
	check_eq(Leaderboard.best("daily:2026-11-17").get("score"), next["score"], "score goes to the day's board")
	var miss := Progress.record_daily("2026-11-19", false, 90.0, 4, 4)
	check_eq(int(miss["streak"]), 0, "a miss ends the streak")
	check_eq(Progress.best_streak(), 2, "best streak kept")


func test_play_records_bests_per_difficulty() -> void:
	_scratch()
	Progress.record_play("hard", true, 60.0, 0)
	var r := Progress.record_play("hard", true, 20.0, 0)
	check(r["new_best"], "faster find is a new best")
	Progress.record_play("hard", false, 99.0, 3)
	var st := Progress.play_stats("hard")
	check_eq(st["played"], 3, "played")
	check_eq(st["found"], 2, "found")
	check(is_equal_approx(float(st["best_time"]), 20.0), "fastest time")
	check_eq(Progress.play_stats("easy")["played"], 0, "other levels untouched")


## Two players on one machine: swap the player id and save folder between turns.
func test_friend_game_loop() -> void:
	var m := MapDefinition.load_map(AppState.TOWN_MAP_ID, SEED, "M")
	var layout := TownGenerator.generate(m, SEED)
	var alice_dir := "user://test_alice_%d" % Time.get_ticks_usec()
	var bob_dir := "user://test_bob_%d" % Time.get_ticks_usec()
	var real_id := AppState.player_id
	# Alice invites (no friend yet).
	JsonStore.root = alice_dir
	AppState.player_id = "a11ce0000001"
	var c1 := AutoHider.make(m, layout, "normal", {"name": "Alice", "look": _look(1)})
	c1.from_id = AppState.player_id
	c1.round = FriendsStore.next_round("")
	FriendsStore.record_sent("", c1, ChallengeCodec.encode(c1))
	check_eq(FriendsStore.open_invites().size(), 1, "invite waits for an answer")
	# Bob opens it.
	JsonStore.root = bob_dir
	AppState.player_id = "b0b000000002"
	var got := ChallengeCodec.decode(ChallengeCodec.encode(c1))["challenge"] as ChallengeData
	var r := FriendsStore.receive(got, ChallengeCodec.encode(got))
	check(r["is_new"] and r["friend_id"] == "a11ce0000001", "Bob gets a new game with Alice")
	var f := FriendsStore.get_friend("a11ce0000001")
	check_eq(f["turn"], FriendsStore.TURN_FIND, "Bob's turn to find")
	check_eq(FriendsStore.your_turn_count(), 1, "one game waiting on Bob")
	check(FriendsStore.receive(got, ChallengeCodec.encode(got))["is_new"] == false, "opening twice doesn't duplicate")
	FriendsStore.record_my_find("a11ce0000001", got, true, 42.0, 3, 1)
	check_eq(FriendsStore.get_friend("a11ce0000001")["turn"], FriendsStore.TURN_HIDE, "then Bob hides")
	var c2 := AutoHider.make(m, TownGenerator.generate(m, SEED), "normal", {"name": "Bob", "look": _look(2)})
	c2.from_id = AppState.player_id
	c2.round = FriendsStore.next_round("a11ce0000001")
	c2.reply = FriendsStore.pending_reply("a11ce0000001")
	FriendsStore.record_sent("a11ce0000001", c2, ChallengeCodec.encode(c2))
	check_eq(FriendsStore.get_friend("a11ce0000001")["turn"], FriendsStore.TURN_WAIT, "Bob waits")
	check_eq(c2.round, 2, "round 2")
	# Alice gets Bob's code with his result.
	JsonStore.root = alice_dir
	AppState.player_id = "a11ce0000001"
	var got2 := ChallengeCodec.decode(ChallengeCodec.encode(c2))["challenge"] as ChallengeData
	var r2 := FriendsStore.receive(got2, ChallengeCodec.encode(got2))
	check(r2["is_new"], "Alice's game with Bob starts from his reply")
	check_eq(FriendsStore.open_invites().size(), 0, "the invite is answered")
	check(bool(r2["their_result"].get("found", false)) and is_equal_approx(float(r2["their_result"]["time"]), 42.0), "Bob's time arrives")
	FriendsStore.record_my_find("b0b000000002", got2, true, 30.0, 2, 0)
	var st := FriendsStore.stats(FriendsStore.get_friend("b0b000000002"))
	check_eq(st["rounds"], 2, "two searches played")
	check(is_equal_approx(float(st["my_best"]), 30.0) and is_equal_approx(float(st["their_best"]), 42.0), "fastest finds: %s" % st)
	check_eq([st["my_wins"], st["their_wins"]], [1, 0], "Alice won round 1")
	# Her own code isn't a friend.
	check(FriendsStore.receive(c1, "")["own"], "own code is recognised")
	AppState.player_id = real_id


func test_practice_partner_round() -> void:
	_scratch()
	var id := Matchmaker.find_random("easy")
	var f := FriendsStore.get_friend(id)
	check(f.get("bot", false) and f["turn"] == FriendsStore.TURN_FIND, "partner hides first")
	var m := MapDefinition.load_map(AppState.TOWN_MAP_ID, SEED, "S")
	var c := AutoHider.make(m, TownGenerator.generate(m, SEED), "easy", {"name": f["name"], "look": f["look"]})
	FriendsStore.record_my_find(id, c, true, 12.0, 1, 0)
	var mine := ChallengeData.create(TownGenerator.generate(m, SEED), _look(), "Me", Vector2(900, 700))
	mine.apply_difficulty("easy")
	FriendsStore.record_sent(id, mine)
	var r := FriendsStore.bot_searches(id, mine, 0.9)
	check(float(r["time"]) > 0.0, "partner took some time")
	check_eq(FriendsStore.get_friend(id)["turn"], FriendsStore.TURN_FIND, "partner's turn to hide again")
	check_eq(FriendsStore.stats(FriendsStore.get_friend(id))["rounds"], 2, "both searches recorded")


func test_play_mode_scene_builds_auto_challenge() -> void:
	_scratch()
	var app_state: Node = tree.root.get_node("AppState")
	app_state.mode = app_state.Mode.SEARCH
	app_state.challenge = null
	app_state.session = {"kind": AppState.KIND_PLAY, "difficulty": "easy"}
	app_state.auto_hide = {"difficulty": "easy", "who": {}}
	app_state.map_seed = SEED
	app_state.map_id = AppState.TOWN_MAP_ID
	app_state.map_size = "S"
	var scene: Node = load(TOWN_SCENE).instantiate()
	tree.root.add_child(scene)
	await tree.process_frame
	await tree.process_frame
	var sc := scene.controller as SearchController
	check(sc != null, "search controller running")
	check(app_state.challenge != null and app_state.challenge.difficulty == "easy", "challenge made by the computer")
	if sc and scene.town.target:
		sc.begin()
		sc.handle_tap(scene.town.target.position + Vector2(0, -30))
		check(sc.found, "tapping the hider wins")
		check_eq(Progress.play_stats("easy")["found"], 1, "result saved to Play records")
	scene.free()
	app_state.session = {"kind": AppState.KIND_QUICK}
	app_state.auto_hide = {}
	app_state.map_size = ""


func test_friends_screen_renders_games() -> void:
	_scratch()
	var bot := Matchmaker.find_random("hard")
	var m := MapDefinition.load_map(AppState.TOWN_MAP_ID, SEED, "S")
	var c := AutoHider.make(m, TownGenerator.generate(m, SEED), "easy")
	FriendsStore.record_my_find(bot, c, true, 33.0, 2, 1)
	c.from_id = "f00dcafe1234"
	FriendsStore.receive(c, ChallengeCodec.encode(c))
	FriendsStore.record_sent("", c, "WM1-test")
	var screen: Control = load("res://scenes/ui/friends_screen.tscn").instantiate()
	tree.root.add_child(screen)
	await tree.process_frame
	check(FriendsStore.list().size() == 2, "two games listed")
	for page: Array in [["friend", bot], ["friend", "f00dcafe1234"], ["new", ""], ["list", ""]]:
		screen._go(page[0], page[1])
		await tree.process_frame
		check(screen._content != null, "page %s builds" % page[0])
	screen.free()
	var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
	tree.root.add_child(menu)
	await tree.process_frame
	menu._go_page("play")
	await tree.process_frame
	check(menu._content != null, "play page builds")
	menu.free()
