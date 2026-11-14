class_name FriendsStore
extends RefCounted
## Your games with friends, on this device (user://friends.json). There is no
## server: challenges travel as share codes, and each code carries who sent
## it (their player id), the round, and the sender's result on the challenge
## it answers. Receiving a code updates the friend's game here.
##
## The loop with one friend:  they hide → you get the code (turn "find")
## → you find them (turn "hide") → you hide and send back, your code carries
## your result (turn "wait") → their code arrives with their result → …
##
## {"friends": {id: Friend}, "invites": {challenge_id: {"at", "difficulty"}}}
## Friend: {"id", "name", "look", "bot", "difficulty", "turn": "find"|"hide"|"wait",
##   "inbox": code waiting to be played, "inbox_id", "reply": result to send back,
##   "rounds": [{"who": "me"|"them", "challenge_id", "found", "time", "taps", "wrong", "at"}],
##   "sent": int, "received": int, "last_sent", "last_code": your latest code
##   to them (to send again), "created", "updated"}

const FILE := "friends.json"
const TURN_FIND := "find"
const TURN_HIDE := "hide"
const TURN_WAIT := "wait"
const BOT_PREFIX := "bot-"


static func _load() -> Dictionary:
	var d := JsonStore.load_dict(FILE)
	if not d.get("friends") is Dictionary:
		d["friends"] = {}
	if not d.get("invites") is Dictionary:
		d["invites"] = {}
	return d


static func _save(d: Dictionary) -> void:
	JsonStore.save_dict(FILE, d)


static func _now() -> int:
	return int(Time.get_unix_time_from_system())


static func get_friend(id: String) -> Dictionary:
	return (_load()["friends"] as Dictionary).get(id, {})


## Friends, the ones waiting on you first, then most recently active.
static func list() -> Array:
	var out: Array = (_load()["friends"] as Dictionary).values()
	var order := {TURN_FIND: 0, TURN_HIDE: 1, TURN_WAIT: 2}
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var oa := int(order.get(a.get("turn"), 3))
		var ob := int(order.get(b.get("turn"), 3))
		if oa != ob:
			return oa < ob
		return int(a.get("updated", 0)) > int(b.get("updated", 0)))
	return out


## How many games are waiting on you (for the menu badge).
static func your_turn_count() -> int:
	var n := 0
	for f: Dictionary in list():
		if f.get("turn") in [TURN_FIND, TURN_HIDE]:
			n += 1
	return n


static func _new_friend(id: String, name: String, look: Dictionary) -> Dictionary:
	return {"id": id, "name": name, "look": look, "bot": id.begins_with(BOT_PREFIX), "difficulty": Difficulty.DEFAULT_ID,
		"turn": TURN_WAIT, "inbox": "", "inbox_id": "", "reply": {}, "rounds": [], "sent": 0, "received": 0,
		"created": _now(), "updated": _now()}


## A code arrived (pasted on the Friends screen). Returns
## {"friend_id", "is_new", "own", "already_played", "their_result": {} or the reply}.
## Codes without a sender (older codes) return friend_id "".
static func receive(c: ChallengeData, code: String) -> Dictionary:
	var out := {"friend_id": "", "is_new": false, "own": false, "already_played": false, "their_result": {}}
	if c.from_id == "":
		return out
	if c.from_id == JsonStore.player_id():
		out["own"] = true
		return out
	var d := _load()
	var friends: Dictionary = d["friends"]
	var f: Dictionary = friends.get(c.from_id, {})
	if f.is_empty():
		f = _new_friend(c.from_id, c.hider_name if c.hider_name != "" else "Friend", c.hider_look)
		out["is_new"] = true
	f["name"] = c.hider_name if c.hider_name != "" else f["name"]
	f["look"] = c.hider_look
	if c.difficulty != "":
		f["difficulty"] = c.difficulty
	if not c.reply.is_empty():
		(d["invites"] as Dictionary).erase(c.reply["to"])
		if _add_round(f, "them", c.reply):
			out["their_result"] = c.reply
	if _has_round(f, "me", c.challenge_id):
		out["already_played"] = true
	elif String(f.get("inbox_id", "")) != c.challenge_id:
		f["inbox"] = code
		f["inbox_id"] = c.challenge_id
		f["received"] = int(f.get("received", 0)) + 1
		f["turn"] = TURN_FIND
	f["updated"] = _now()
	friends[c.from_id] = f
	_save(d)
	out["friend_id"] = c.from_id
	return out


## You finished searching [param c] from friend [param friend_id].
static func record_my_find(friend_id: String, c: ChallengeData, found: bool, seconds: float, taps: int, wrong: int) -> void:
	var d := _load()
	var f: Dictionary = (d["friends"] as Dictionary).get(friend_id, {})
	if f.is_empty():
		return
	var result := {"to": c.challenge_id, "found": found, "time": snappedf(seconds, 0.1), "taps": taps, "wrong": wrong}
	_add_round(f, "me", result)
	f["inbox"] = ""
	f["inbox_id"] = ""
	f["reply"] = result
	f["turn"] = TURN_HIDE
	f["updated"] = _now()
	d["friends"][friend_id] = f
	_save(d)


## The result to attach when hiding for [param friend_id] ({} if none).
static func pending_reply(friend_id: String) -> Dictionary:
	return get_friend(friend_id).get("reply", {})


## Round number for the next code you send to [param friend_id].
static func next_round(friend_id: String) -> int:
	var f := get_friend(friend_id)
	return int(f.get("sent", 0)) + int(f.get("received", 0)) + 1


## You hid and got a code for [param friend_id] ("" = an invite to whoever opens it).
static func record_sent(friend_id: String, c: ChallengeData, code: String = "") -> void:
	var d := _load()
	if friend_id == "":
		d["invites"][c.challenge_id] = {"at": _now(), "difficulty": c.difficulty, "code": code}
		_save(d)
		return
	var f: Dictionary = (d["friends"] as Dictionary).get(friend_id, {})
	if f.is_empty():
		return
	f["reply"] = {}
	f["sent"] = int(f.get("sent", 0)) + 1
	f["last_sent"] = c.challenge_id
	f["last_code"] = code
	if c.difficulty != "":
		f["difficulty"] = c.difficulty
	if String(f.get("inbox", "")) == "":
		f["turn"] = TURN_WAIT
	f["updated"] = _now()
	d["friends"][friend_id] = f
	_save(d)


## Invites you sent that nobody has answered yet, newest first:
## [{"challenge_id", "at", "difficulty", "code"}].
static func open_invites() -> Array:
	var out: Array = []
	var inv: Dictionary = _load()["invites"]
	for id: String in inv:
		var e: Dictionary = (inv[id] as Dictionary).duplicate()
		e["challenge_id"] = id
		out.append(e)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("at", 0)) > int(b.get("at", 0)))
	return out


static func cancel_invite(challenge_id: String) -> void:
	var d := _load()
	(d["invites"] as Dictionary).erase(challenge_id)
	_save(d)


static func remove(friend_id: String) -> void:
	var d := _load()
	(d["friends"] as Dictionary).erase(friend_id)
	_save(d)


## Head-to-head numbers for the friend card.
## {"rounds", "my_finds", "their_finds", "my_best", "their_best", "my_avg",
##  "their_avg", "my_wins", "their_wins", "last_played"}
static func stats(f: Dictionary) -> Dictionary:
	var mine: Array = []
	var theirs: Array = []
	for r: Dictionary in f.get("rounds", []):
		(mine if r["who"] == "me" else theirs).append(r)
	var s := {"rounds": mine.size() + theirs.size(), "my_finds": 0, "their_finds": 0, "my_best": 0.0, "their_best": 0.0,
		"my_avg": 0.0, "their_avg": 0.0, "my_wins": 0, "their_wins": 0, "last_played": int(f.get("updated", 0))}
	for side: Array in [[mine, "my"], [theirs, "their"]]:
		var total := 0.0
		var n := 0
		for r: Dictionary in side[0]:
			if r["found"]:
				n += 1
				total += float(r["time"])
				var key := "%s_best" % side[1]
				if float(s[key]) <= 0.0 or float(r["time"]) < float(s[key]):
					s[key] = float(r["time"])
		s["%s_finds" % side[1]] = n
		s["%s_avg" % side[1]] = total / n if n > 0 else 0.0
	# Round k: your k-th search against their k-th search; the faster find wins.
	for k in mini(mine.size(), theirs.size()):
		var a: Dictionary = mine[k]
		var b: Dictionary = theirs[k]
		var ta := float(a["time"]) if a["found"] else INF
		var tb := float(b["time"]) if b["found"] else INF
		if ta < tb:
			s["my_wins"] += 1
		elif tb < ta:
			s["their_wins"] += 1
	return s


## "Your turn: find Alex" / "Your turn: hide and send back" / "Waiting for Alex".
static func status_line(f: Dictionary) -> String:
	match String(f.get("turn", "")):
		TURN_FIND:
			return "Your turn: find %s" % f.get("name", "them")
		TURN_HIDE:
			return "Your turn: hide and send back"
		_:
			return "Waiting for %s to find you" % f.get("name", "them")


# --- Practice partners ("Play with random" until matchmaking is online) -----

## Makes a practice partner (a computer player) and returns its id.
static func create_bot(difficulty: String) -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var id := "%s%08x" % [BOT_PREFIX, rng.randi()]
	var who := AutoHider.hider_for(rng.randi() & ChallengeCodec.MAX_SEED, id)
	var d := _load()
	var f := _new_friend(id, String(who["name"]), who["look"])
	f["difficulty"] = difficulty
	f["turn"] = TURN_FIND
	d["friends"][id] = f
	_save(d)
	return id


## A practice partner searched your challenge [param c]. Their time grows with
## the town size and how hidden you were. Returns the result recorded.
static func bot_searches(friend_id: String, c: ChallengeData, visible_fraction: float) -> Dictionary:
	var base := {"S": 18.0, "M": 35.0, "L": 60.0, "XL": 90.0}
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var t := float(base.get(c.town_size if c.town_size != "" else "L", 60.0)) * lerpf(1.8, 0.7, clampf(visible_fraction, 0.0, 1.0)) * rng.randf_range(0.6, 1.5)
	var found := rng.randf() < 0.92
	var result := {"to": c.challenge_id, "found": found, "time": snappedf(t if found else t * 2.0, 0.1), "taps": rng.randi_range(1, 6), "wrong": rng.randi_range(0, 3)}
	var d := _load()
	var f: Dictionary = (d["friends"] as Dictionary).get(friend_id, {})
	if f.is_empty():
		return result
	_add_round(f, "them", result)
	f["turn"] = TURN_FIND
	f["updated"] = _now()
	d["friends"][friend_id] = f
	_save(d)
	return result


static func _has_round(f: Dictionary, who: String, challenge_id: String) -> bool:
	for r: Dictionary in f.get("rounds", []):
		if r["who"] == who and r["challenge_id"] == challenge_id:
			return true
	return false


## Adds a round from a result dict ({"to", "found", "time", …}); false if it was already there.
static func _add_round(f: Dictionary, who: String, result: Dictionary) -> bool:
	if _has_round(f, who, String(result["to"])):
		return false
	var rounds: Array = f.get("rounds", [])
	rounds.append({"who": who, "challenge_id": String(result["to"]), "found": bool(result.get("found", false)),
		"time": float(result.get("time", 0.0)), "taps": int(result.get("taps", 0)), "wrong": int(result.get("wrong", 0)), "at": _now()})
	f["rounds"] = rounds
	return true
