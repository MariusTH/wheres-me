class_name JsonStore
extends RefCounted
## Tiny helpers for the player's local save files (user://*.json).
## Tests point [member root] at a scratch folder so they never touch real saves.

static var root := "user://"


static func path(file: String) -> String:
	return root.path_join(file)


static func load_dict(file: String) -> Dictionary:
	var p := path(file)
	if not FileAccess.file_exists(p):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
	if not data is Dictionary:
		push_warning("Ignoring unreadable save file %s" % p)
		return {}
	return data


static func save_dict(file: String, data: Dictionary) -> bool:
	var p := path(file)
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		push_error("Could not save %s: %s" % [p, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(JSON.stringify(data, " "))
	return true


## The AppState autoload, looked up at run time. Static helper classes use
## this instead of the AppState identifier, which isn't known yet when they
## are compiled from a tool or test script.
static func app() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("AppState") if tree else null


## Your player id ("" when AppState isn't running).
static func player_id() -> String:
	var a := app()
	return String(a.get("player_id")) if a else ""
