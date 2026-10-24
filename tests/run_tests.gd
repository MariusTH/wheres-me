extends SceneTree
## Headless test runner. Usage (from the project folder):
##   godot --headless --path . -s res://tests/run_tests.gd
## Exits with code 0 when every test passes, 1 otherwise.

const SUITES := [
	"res://tests/test_map_determinism.gd",
	"res://tests/test_challenge_codec.gd",
	"res://tests/test_visibility.gd",
	"res://tests/test_scene_runtime.gd",
	"res://tests/test_photo_to_look.gd",
]

var _passed := 0
var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for path: String in SUITES:
		print("\n== %s" % path.get_file())
		var suite: TestSuite = load(path).new()
		suite.tree = self
		for m in suite.get_method_list():
			var test_name := String(m["name"])
			if not test_name.begins_with("test_"):
				continue
			suite.errors.clear()
			await suite.call(test_name)
			if suite.errors.is_empty():
				_passed += 1
				print("  PASS  %s" % test_name)
			else:
				_failed += 1
				print("  FAIL  %s" % test_name)
				for e in suite.errors:
					print("        - %s" % e)
	print("\n%d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
