class_name DebugLog
extends RefCounted
## Ring buffer of recent log lines (print, warnings, script errors), filled
## from any thread by a Logger that DebugConsole installs. See DebugConsole.

const MAX_LINES := 400

static var _lines: PackedStringArray = []
static var _mutex := Mutex.new()


## Captures everything Godot logs.
class CaptureLogger extends Logger:
	func _log_message(message: String, error: bool) -> void:
		DebugLog.add_line(("ERR " if error else "") + message.strip_edges(false, true))

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		var kind: String = ["ERROR", "WARNING", "SCRIPT ERROR", "SHADER ERROR"][clampi(error_type, 0, 3)]
		DebugLog.add_line("%s: %s (%s:%d %s)" % [kind, rationale if rationale != "" else code, file.get_file(), line, function])


static func install() -> void:
	OS.add_logger(CaptureLogger.new())


static func add_line(line: String) -> void:
	_mutex.lock()
	_lines.append("%s %s" % [Time.get_time_string_from_system(), line])
	if _lines.size() > MAX_LINES:
		_lines = _lines.slice(_lines.size() - MAX_LINES)
	_mutex.unlock()


static func text() -> String:
	_mutex.lock()
	var t := "\n".join(_lines)
	_mutex.unlock()
	return t


static func clear() -> void:
	_mutex.lock()
	_lines.clear()
	_mutex.unlock()
