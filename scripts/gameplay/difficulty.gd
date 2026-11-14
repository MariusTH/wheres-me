class_name Difficulty
extends RefCounted
## Difficulty levels, shared by Play, the Daily challenge and friend games.
## A level picks the town size, how hidden the person may be, and how many
## look-alike decoys stand in the crowd. The numbers follow the notes in
## wherewally.md: harder means a bigger crowd and more of the body hidden, but
## some of the head always shows, because the face and hat are what you look for.
##
##   size         town size (MapDefinition sizes: S, M, L, XL)
##   min_visible  hide rule: at least this share of the person must show
##   max_visible  the computer hider picks spots showing at most this share
##   min_head     at least this share of the head (face, hair, hat) must show
##   decoys       crowd members who share all but one part of the hider's look
##   points       score multiplier

const DEFAULT_ID := "normal"

const LEVELS: Array[Dictionary] = [
	{"id": "easy", "name": "Easy", "size": "S", "min_visible": 0.80, "max_visible": 1.00, "min_head": 0.90, "decoys": 0, "points": 1.0,
		"blurb": "Small town. They stand out in the open."},
	{"id": "normal", "name": "Normal", "size": "M", "min_visible": 0.60, "max_visible": 0.85, "min_head": 0.75, "decoys": 2, "points": 1.5,
		"blurb": "Bigger crowd. Partly behind things, with a couple of look-alikes."},
	{"id": "hard", "name": "Hard", "size": "L", "min_visible": 0.45, "max_visible": 0.70, "min_head": 0.60, "decoys": 4, "points": 2.0,
		"blurb": "The full town. Half hidden, and several look-alikes."},
	{"id": "expert", "name": "Expert", "size": "XL", "min_visible": 0.30, "max_visible": 0.55, "min_head": 0.50, "decoys": 8, "points": 3.0,
		"blurb": "Huge town. Mostly hidden, only the head peeks out. Lots of look-alikes."},
]

## Town size words for the UI.
const SIZE_NAMES := {"S": "small", "M": "medium", "L": "large", "XL": "huge"}


static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for l in LEVELS:
		out.append(String(l["id"]))
	return out


## The level with [param id] (the default level when unknown).
static func get_level(id: String) -> Dictionary:
	for l in LEVELS:
		if l["id"] == id:
			return l
	return get_level(DEFAULT_ID)


static func exists(id: String) -> bool:
	return ids().has(id)


## One line for intro cards: "Hard · large town · up to 55% hidden, head always shows".
static func describe(id: String) -> String:
	var l := get_level(id)
	var hidden := roundi((1.0 - float(l["min_visible"])) * 100.0)
	return "%s · %s town · up to %d%% hidden, but some of the head always shows" % [l["name"], SIZE_NAMES.get(l["size"], "large"), hidden]


## Score for one search: faster is better, wrong taps cost, harder pays more.
## 0 when not found. A 30-second find on Normal scores 1000.
static func score(id: String, found: bool, seconds: float, wrong: int) -> int:
	if not found:
		return 0
	var l := get_level(id)
	var speed := 60.0 / (60.0 + maxf(seconds, 0.0))
	return maxi(0, roundi(float(l["points"]) * 1000.0 * speed - 40.0 * wrong))
