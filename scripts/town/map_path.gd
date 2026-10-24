class_name MapPath
extends RefCounted
## Authored pedestrian path (polyline). Used for seeded crowd placement now
## and for moving pedestrians later (see POC_NOTES.md roadmap).

var id: String = ""
var points: PackedVector2Array = PackedVector2Array()
var width: float = 40.0
## Ground surface to paint under the path ("" = nothing, e.g. sidewalks).
var surface: String = ""
var people: int = 0
var tags: PackedStringArray = PackedStringArray()
var _length: float = 0.0


static func from_dict(d: Dictionary) -> MapPath:
	var p := MapPath.new()
	p.id = String(d["id"])
	for pt: Variant in d["points"]:
		p.points.append(MapDefinition.vec2(pt))
	p.width = float(d.get("width", 40.0))
	p.surface = String(d.get("surface", ""))
	p.people = int(d.get("people", 0))
	p.tags = PackedStringArray(d.get("tags", []))
	for i in range(1, p.points.size()):
		p._length += p.points[i - 1].distance_to(p.points[i])
	return p


func length() -> float:
	return _length


## Point at [param fraction] (0..1) of the total length.
func point_at(fraction: float) -> Vector2:
	return _sample(fraction)[0]


## Unit tangent at [param fraction].
func tangent_at(fraction: float) -> Vector2:
	return _sample(fraction)[1]


func _sample(fraction: float) -> Array:
	var target := clampf(fraction, 0.0, 1.0) * _length
	for i in range(1, points.size()):
		var a := points[i - 1]
		var b := points[i]
		var seg := a.distance_to(b)
		if target <= seg or i == points.size() - 1:
			var t := 0.0 if seg == 0.0 else clampf(target / seg, 0.0, 1.0)
			return [a.lerp(b, t), (b - a).normalized()]
		target -= seg
	return [points[0], Vector2.RIGHT]
