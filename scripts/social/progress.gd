class_name Progress
extends RefCounted
## Solo progress on this device (user://progress.json): Daily challenge
## results and streaks, and per-difficulty Play records. Scores also go to the
## Leaderboard seam, so an online board can pick them up later.
##
## {"daily": {"2026-11-13": {"score", "found", "time", "taps", "wrong"}},
##  "streak": int, "best_streak": int, "last_daily": "2026-11-13",
##  "play": {"easy": {"played", "found", "best_score", "best_time"}}}

const FILE := "progress.json"
## Day 1 of the Daily challenge.
const DAILY_EPOCH := "2026-11-13"
## Monday easy, building up through the week, Saturday the hardest (like
## newspaper crosswords). Index = Time weekday (0 Sunday … 6 Saturday).
const DAILY_DIFFICULTY: Array[String] = ["hard", "easy", "normal", "normal", "hard", "hard", "expert"]


# --- Daily challenge -------------------------------------------------------

## Today's date on this device, "YYYY-MM-DD".
static func today() -> String:
	return Time.get_date_string_from_system()


## The town seed for [param date]: the same for every player that day.
static func daily_seed(date: String) -> int:
	return DetHash.fnv1a_32("wheres-me-daily:" + date) & ChallengeCodec.MAX_SEED


static func daily_difficulty(date: String) -> String:
	var unix := Time.get_unix_time_from_datetime_string(date + "T12:00:00")
	return DAILY_DIFFICULTY[Time.get_datetime_dict_from_unix_time(unix)["weekday"]]


## "Daily #1" is DAILY_EPOCH.
static func daily_number(date: String) -> int:
	var d := Time.get_unix_time_from_datetime_string(date + "T12:00:00")
	var e := Time.get_unix_time_from_datetime_string(DAILY_EPOCH + "T12:00:00")
	return int(roundf(float(d - e) / 86400.0)) + 1


## Your result for [param date], or {} if not played yet.
static func daily_result(date: String) -> Dictionary:
	return (_load().get("daily", {}) as Dictionary).get(date, {})


## Counts only the first attempt each day. Returns {"score", "counted",
## "new_best", "streak", "best"}.
static func record_daily(date: String, found: bool, seconds: float, taps: int, wrong: int) -> Dictionary:
	var p := _load()
	var daily: Dictionary = p.get("daily", {})
	var diff := daily_difficulty(date)
	var score := Difficulty.score(diff, found, seconds, wrong)
	var prev_best := best_daily_score()
	if daily.has(date):
		return {"score": score, "counted": false, "new_best": false, "streak": int(p.get("streak", 0)), "best": prev_best}
	daily[date] = {"score": score, "found": found, "time": snappedf(seconds, 0.1), "taps": taps, "wrong": wrong, "difficulty": diff}
	p["daily"] = daily
	# A streak counts days in a row with a find.
	var yesterday := Time.get_date_string_from_unix_time(Time.get_unix_time_from_datetime_string(date + "T12:00:00") - 86400)
	var streak := int(p.get("streak", 0))
	if found:
		streak = streak + 1 if String(p.get("last_daily", "")) == yesterday else 1
	else:
		streak = 0
	p["streak"] = streak
	p["best_streak"] = maxi(int(p.get("best_streak", 0)), streak)
	p["last_daily"] = date
	_save(p)
	if found:
		var meta := {"time": snappedf(seconds, 0.1), "wrong": wrong, "date": date}
		Leaderboard.submit("daily:" + date, score, meta)
		Leaderboard.submit("daily:all", score, meta)
	return {"score": score, "counted": true, "new_best": found and score > prev_best, "streak": streak, "best": maxi(prev_best, score)}


static func best_daily_score() -> int:
	return int(Leaderboard.best("daily:all").get("score", 0))


## Current streak, or 0 when the last find was before yesterday.
static func daily_streak() -> int:
	var p := _load()
	var last := String(p.get("last_daily", ""))
	var yesterday := Time.get_date_string_from_unix_time(Time.get_unix_time_from_datetime_string(today() + "T12:00:00") - 86400)
	return int(p.get("streak", 0)) if last == today() or last == yesterday else 0


static func best_streak() -> int:
	return int(_load().get("best_streak", 0))


# --- Play ------------------------------------------------------------------

## {"played", "found", "best_score", "best_time"} for a difficulty.
static func play_stats(difficulty: String) -> Dictionary:
	var s: Dictionary = (_load().get("play", {}) as Dictionary).get(difficulty, {})
	return {"played": int(s.get("played", 0)), "found": int(s.get("found", 0)),
		"best_score": int(s.get("best_score", 0)), "best_time": float(s.get("best_time", 0.0))}


## Returns {"score", "new_best", "best"}.
static func record_play(difficulty: String, found: bool, seconds: float, wrong: int) -> Dictionary:
	var p := _load()
	var play: Dictionary = p.get("play", {})
	var s := play_stats(difficulty)
	var score := Difficulty.score(difficulty, found, seconds, wrong)
	var new_best := found and score > int(s["best_score"])
	s["played"] = int(s["played"]) + 1
	if found:
		s["found"] = int(s["found"]) + 1
		s["best_score"] = maxi(int(s["best_score"]), score)
		if float(s["best_time"]) <= 0.0 or seconds < float(s["best_time"]):
			s["best_time"] = snappedf(seconds, 0.1)
		Leaderboard.submit("play:" + difficulty, score, {"time": snappedf(seconds, 0.1), "wrong": wrong})
	play[difficulty] = s
	p["play"] = play
	_save(p)
	return {"score": score, "new_best": new_best, "best": int(s["best_score"])}


static func _load() -> Dictionary:
	return JsonStore.load_dict(FILE)


static func _save(p: Dictionary) -> void:
	JsonStore.save_dict(FILE, p)
