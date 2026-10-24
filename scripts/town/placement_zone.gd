class_name PlacementZone
extends RefCounted
## An authored area of the map with density targets for seeded dressing.

var id: String = ""
## e.g. "shop_frontage", "plaza", "park", "market", "garden", "sidewalk".
var kind: String = ""
var polygon: PackedVector2Array = PackedVector2Array()
var bounds: Rect2 = Rect2()
## Number of generated people in this zone.
var people: int = 0
## Each rule: {"pool": Array[String] of asset keys, "count": int}.
var prop_rules: Array[Dictionary] = []
## Lets props (parked cars) sit on blocked areas such as the road.
var allow_on_blocked: bool = false


static func from_dict(d: Dictionary) -> PlacementZone:
	var z := PlacementZone.new()
	z.id = String(d["id"])
	z.kind = String(d.get("kind", ""))
	if d.has("rect"):
		var r := MapDefinition.rect2(d["rect"])
		z.polygon = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	else:
		for p: Variant in d["polygon"]:
			z.polygon.append(MapDefinition.vec2(p))
	z.bounds = Rect2(z.polygon[0], Vector2.ZERO)
	for p in z.polygon:
		z.bounds = z.bounds.expand(p)
	z.people = int(d.get("people", 0))
	for rule: Dictionary in d.get("props", []):
		z.prop_rules.append({"pool": Array(rule["pool"]), "count": int(rule["count"])})
	z.allow_on_blocked = bool(d.get("allow_on_blocked", false))
	return z


func contains(p: Vector2) -> bool:
	return bounds.has_point(p) and Geometry2D.is_point_in_polygon(p, polygon)


## Integer-snapped point inside the zone's bounding box (caller checks contains()).
func random_point(rng: RandomNumberGenerator) -> Vector2:
	var x := rng.randf_range(bounds.position.x, bounds.end.x)
	var y := rng.randf_range(bounds.position.y, bounds.end.y)
	return Vector2(roundf(x), roundf(y))
