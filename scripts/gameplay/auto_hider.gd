class_name AutoHider
extends RefCounted
## The computer as hider, for Play, the Daily challenge and practice partners.
## Picks a look and a name from the seed, then a spot whose visibility falls
## in the difficulty's band. Placement follows wherewally.md:
##  * near cover (props and buildings), so the person is partly behind something;
##  * not at the very edges, and not dead centre, where eyes go first;
##  * not standing on top of someone else;
##  * some of the head always shows (Difficulty min_head).
## Deterministic: the same map, seed and difficulty give the same challenge.

const NAMES: Array[String] = [
	"Pip", "Juno", "Otto", "Mabel", "Rufus", "Ida", "Nico", "Wren", "Bea", "Felix",
	"Tilda", "Arlo", "Nell", "Hugo", "Clem", "Iris", "Bram", "Lulu", "Ezra", "Mira",
	"Dot", "Kit", "Remy", "Sunny", "Olive", "Basil", "Pearl", "Milo", "Hazel", "Teo",
]
const ATTEMPTS := 500
## Share of the map on each side where the hider never goes (Handford rarely
## hides Wally at the page edges).
const EDGE_FRACTION := 0.08
## Radius around the map centre, as a share of the short side, that is avoided.
const CENTRE_FRACTION := 0.12
## No standing inside another person.
const PERSONAL_SPACE := 16.0


## A look and name for [param salt] (a seed, a bot id…).
static func hider_for(map_seed: int, salt: String = "auto_hider") -> Dictionary:
	var rng := DetHash.make_rng(map_seed, salt + ":who")
	return {"name": NAMES[rng.randi_range(0, NAMES.size() - 1)], "look": AvatarKit.normalize(AvatarKit.random_look(rng))}


## Builds a challenge on an already generated town. [param who] is
## {"name", "look"}; empty = hider_for(map_seed). Applies the difficulty's
## decoys and the twin rule to [param layout] (the same changes the search
## scene makes, so the chosen spot's visibility holds there too).
static func make(map_def: MapDefinition, layout: TownLayout, difficulty_id: String, who: Dictionary = {}) -> ChallengeData:
	var level := Difficulty.get_level(difficulty_id)
	if who.is_empty():
		who = hider_for(layout.map_seed)
	var look := AvatarKit.normalize(who["look"])
	prepare_crowd(layout, look, int(level["decoys"]), layout.map_seed)
	var feet := find_spot(map_def, layout, look, level, layout.map_seed)
	var c := ChallengeData.create(layout, look, String(who["name"]), feet)
	c.apply_difficulty(difficulty_id)
	return c


## Twin rule + decoys on layout data (TownController does the same on nodes).
static func prepare_crowd(layout: TownLayout, look: Dictionary, decoys: int, map_seed: int) -> void:
	Decoys.apply(layout, look, decoys, map_seed)
	var key := AvatarKit.look_key(look)
	for obj in layout.objects:
		if obj.is_interactive and AvatarKit.look_key(obj.look) == key:
			obj.look = AvatarKit.make_distinct(obj.look, look)


## A spot inside the band, or the closest one found if none fits.
static func find_spot(map_def: MapDefinition, layout: TownLayout, look: Dictionary, level: Dictionary, map_seed: int) -> Vector2:
	var rng := DetHash.make_rng(map_seed, "auto_hider:spot:" + String(level["id"]))
	var lo := float(level["min_visible"])
	var hi := float(level["max_visible"])
	var head := float(level["min_head"])
	var checker := VisibilityChecker.new(map_def, layout.objects, lo, head)
	var subject := VisibilityChecker.subject_for_look(look)
	var b := map_def.world_bounds
	var inner := b.grow_individual(-b.size.x * EDGE_FRACTION, -b.size.y * EDGE_FRACTION - 60.0, -b.size.x * EDGE_FRACTION, -b.size.y * EDGE_FRACTION)
	var centre_r := minf(b.size.x, b.size.y) * CENTRE_FRACTION
	var cover: Array[WorldObjectData] = []
	var people: Array[Vector2] = []
	for obj in layout.objects:
		if obj.is_interactive:
			people.append(obj.world_position)
		elif obj.depth_mode != "ground" and inner.has_point(obj.world_position):
			cover.append(obj)
	var best := Vector2.INF
	var best_miss := INF
	for i in ATTEMPTS:
		var p: Vector2
		if not cover.is_empty() and rng.randf() < 0.75:
			# Just behind or beside something that can cover the legs or body.
			var c := cover[rng.randi_range(0, cover.size() - 1)]
			p = c.world_position + Vector2(rng.randf_range(-50.0, 50.0), rng.randf_range(-36.0, 6.0))
		else:
			p = Vector2(rng.randf_range(inner.position.x, inner.end.x), rng.randf_range(inner.position.y, inner.end.y))
		p = p.round()
		if not inner.has_point(p) or p.distance_to(b.get_center()) < centre_r:
			continue
		if map_def.blocked_label_at(p) != "" or _crowded(p, people):
			continue
		var r := checker.check_subject(subject, p)
		var f := float(r["fraction"])
		if r["ok"] and f <= hi + 0.0005:
			return p
		# Fallback: the least visible spot that still passes the rule (too
		# easy beats unplayable: the search re-checks the rule).
		if r["ok"] and f < best_miss:
			best_miss = f
			best = p
	if best.is_finite():
		return best
	return _any_valid(checker, subject, inner)


## Scans for any spot that passes the rule (only when sampling found none).
static func _any_valid(checker: VisibilityChecker, subject: WorldObjectData, area: Rect2) -> Vector2:
	var y := area.position.y
	while y < area.end.y:
		var x := area.position.x
		while x < area.end.x:
			var p := Vector2(x, y).round()
			if checker.check_subject(subject, p)["ok"]:
				return p
			x += 97.0
		y += 83.0
	return area.get_center().round()


static func _crowded(p: Vector2, people: Array[Vector2]) -> bool:
	for q in people:
		if absf(q.x - p.x) < PERSONAL_SPACE and absf(q.y - p.y) < PERSONAL_SPACE:
			return true
	return false
