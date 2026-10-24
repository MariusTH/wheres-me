class_name TestSuite
extends RefCounted
## Minimal assertion base for tests/run_tests.gd. Each method named test_*
## is run in order; it may await (e.g. on tree.process_frame).

var tree: SceneTree
var errors: PackedStringArray = PackedStringArray()


func check(cond: bool, msg: String) -> bool:
	if not cond:
		errors.append(msg)
	return cond


func check_eq(actual: Variant, expected: Variant, msg: String) -> bool:
	return check(actual == expected, "%s: expected <%s>, got <%s>" % [msg, str(expected), str(actual)])


func load_map() -> MapDefinition:
	return MapDefinition.load_map("town_demo_01")


## First spot (scanning a grid from [param from]) where [param look] passes the
## visibility rule, so tests don't depend on hand-picked coordinates.
func find_visible_spot(m: MapDefinition, layout: TownLayout, look: Dictionary, from: Vector2 = Vector2(300, 700), min_fraction: float = 0.95) -> Vector2:
	var v := VisibilityChecker.new(m, layout.objects)
	for dy in range(0, 400, 20):
		for dx in range(0, 1200, 20):
			var p := from + Vector2(dx, dy)
			var r := v.check(look, p)
			if r["ok"] and float(r["fraction"]) >= min_fraction:
				return p
	return Vector2.INF
