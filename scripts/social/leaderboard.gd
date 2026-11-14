class_name Leaderboard
extends RefCounted
## Leaderboard seam. Every scored game goes through submit(); screens read
## through top() and best(). Today the only backend is LocalBackend (this
## device: your own scores, so "top" is your personal best list). An online
## backend (e.g. a Supabase table, see the go-online notes in wherewally.md)
## only has to implement the same three methods and be assigned to [member backend].
##
## Board ids: "daily:2026-11-13", "daily:all", "play:easy" … "play:expert".


static var backend: Backend = null


static func _b() -> Backend:
	if backend == null:
		backend = LocalBackend.new()
	return backend


## Records [param score] (higher is better) on [param board].
## [param meta]: anything worth showing later, e.g. {"time": 41.2, "wrong": 1}.
static func submit(board: String, score: int, meta: Dictionary = {}) -> void:
	_b().submit(board, score, meta)


## Best entries first: [{"name", "score", "meta", "at"}]. Local: only yours.
static func top(board: String, count: int = 10) -> Array:
	return _b().top(board, count)


## Your best entry on [param board], or {} if you have none.
static func best(board: String) -> Dictionary:
	var t := _b().top(board, 1)
	return t[0] if not t.is_empty() else {}


## Whether scores are shared with other players yet.
static func is_online() -> bool:
	return _b().is_online()


class Backend:
	extends RefCounted

	func submit(_board: String, _score: int, _meta: Dictionary) -> void:
		pass

	func top(_board: String, _count: int) -> Array:
		return []

	func is_online() -> bool:
		return false


## Scores on this device, user://scores.json: {board: [entries]} (best 20 kept).
class LocalBackend:
	extends Backend
	const FILE := "scores.json"
	const KEEP := 20

	func submit(board: String, score: int, meta: Dictionary) -> void:
		var all := JsonStore.load_dict(FILE)
		var list: Array = all.get(board, [])
		var app_node := JsonStore.app()
		var me := String((app_node.get("my_avatar") as Dictionary).get("name", "")) if app_node else ""
		list.append({"name": me if me != "" else "You", "score": score, "meta": meta, "at": int(Time.get_unix_time_from_system())})
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["score"]) > int(b["score"]))
		all[board] = list.slice(0, KEEP)
		JsonStore.save_dict(FILE, all)

	func top(board: String, count: int) -> Array:
		var list: Array = JsonStore.load_dict(FILE).get(board, [])
		return list.slice(0, count)
