class_name SearchHelp
extends RefCounted
## "Help me if I'm stuck": after a while searching, the hunt gets easier.
## At each stage the hider steps a little out of hiding (to the nearest spot
## where at least `visible` of them shows) and a share of the crowd leaves
## the town. Purely local to this search: the share code and the hide rule
## are untouched. On by default; the player can switch it off (Play page).

const SETTING_KEY := "search_help"
const PROFILE_FILE := "profile.json"

## Each stage once, in order. after: seconds on the clock; visible: share of
## the hider that shows afterwards; thin: share of the crowd that has left.
const STAGES: Array[Dictionary] = [
	{"after": 300.0, "visible": 0.70, "thin": 0.30},
	{"after": 480.0, "visible": 0.90, "thin": 0.55},
]
## How far (world px) the hider may step to find a more visible spot.
const MAX_STEP := 140.0
const RING_STEP := 10.0
const RING_POINTS := 14
const PERSONAL_SPACE := 16.0


static func enabled() -> bool:
	return bool(JsonStore.load_dict(PROFILE_FILE).get(SETTING_KEY, true))


static func set_enabled(on: bool) -> void:
	var p := JsonStore.load_dict(PROFILE_FILE)
	p[SETTING_KEY] = on
	JsonStore.save_dict(PROFILE_FILE, p)


## Ids of the crowd members who leave by [param thin] (a share 0..1).
## Deterministic, and each stage keeps the people the earlier one removed.
static func leavers(layout: TownLayout, thin: float, map_seed: int) -> Dictionary:
	var crowd: Array[WorldObjectData] = []
	for obj in layout.objects:
		if obj.is_interactive and obj.id != ChallengeData.TARGET_OBJECT_ID and obj.id != TownController.TARGET_ID:
			crowd.append(obj)
	var order: Array = []
	for obj in crowd:
		order.append([DetHash.fnv1a_32("%d:help:%s" % [map_seed, obj.id]), obj.id])
	order.sort()
	var out := {}
	for i in roundi(order.size() * clampf(thin, 0.0, 1.0)):
		out[order[i][1]] = true
	return out


## The nearest spot to [param feet] where at least [param want] of the hider
## shows (with [param gone] removed from the crowd). The most visible spot
## found when none is good enough; [param feet] itself when it already is.
static func step_out(map_def: MapDefinition, layout: TownLayout, look: Dictionary, feet: Vector2, want: float, gone: Dictionary) -> Vector2:
	var objects: Array[WorldObjectData] = []
	var people: Array[Vector2] = []
	for obj in layout.objects:
		if gone.has(obj.id) or obj.id == TownController.TARGET_ID:
			continue
		objects.append(obj)
		if obj.is_interactive:
			people.append(obj.world_position)
	var checker := VisibilityChecker.new(map_def, objects, 0.0, 0.0)
	var subject := VisibilityChecker.subject_for_look(look)
	var here: Dictionary = checker.measure(subject, feet)
	if float(here["fraction"]) >= want and float(here["head"]) >= want:
		return feet
	var bounds := map_def.world_bounds.grow(-40.0)
	var best := feet
	var best_f := float(here["fraction"])
	var r := RING_STEP
	while r <= MAX_STEP:
		for i in RING_POINTS:
			var a := TAU * (float(i) + (r / RING_STEP) * 0.5) / float(RING_POINTS)
			# Mostly sideways and down the screen (stepping forward out of cover).
			var p := (feet + Vector2(cos(a), sin(a) * 0.6) * r).round()
			if not bounds.has_point(p) or map_def.blocked_label_at(p) != "" or _crowded(p, people):
				continue
			var m: Dictionary = checker.measure(subject, p)
			var f := float(m["fraction"])
			if f >= want and float(m["head"]) >= want:
				return p
			if f > best_f:
				best_f = f
				best = p
		r += RING_STEP
	return best


static func _crowded(p: Vector2, people: Array[Vector2]) -> bool:
	for q in people:
		if absf(q.x - p.x) < PERSONAL_SPACE and absf(q.y - p.y) < PERSONAL_SPACE:
			return true
	return false
