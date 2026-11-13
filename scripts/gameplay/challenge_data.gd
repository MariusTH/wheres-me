class_name ChallengeData
extends RefCounted
## A hide-and-seek challenge. The map itself is NOT stored: it is rebuilt from
## map_id + map_version + generator_version + seed. Only the hider (name plus
## part-kit look), where they stand, and rule overrides travel with it.
## Local POC only: the answer is in the data, so this is not anti-cheat secure.

## v2: custom avatar look + free placement (v1 used preset avatars and hide points).
## v3: the hider could be a museum critter (museum removed; such codes are
## rejected, avatar v3 codes still load).
const SCHEMA_VERSION := 3
## Oldest version this build still reads.
const MIN_SCHEMA_VERSION := 2
const TARGET_OBJECT_ID := "target_player"

var schema_version: int = SCHEMA_VERSION
var map_id: String = ""
var map_version: int = 0
var generator_version: int = 0
var map_seed: int = 0
var challenge_id: String = ""
var hider_name: String = ""
var hider_look: Dictionary = {}
var target_object_id: String = TARGET_OBJECT_ID
## Feet (ground point) of the hider, world coordinates, integer-snapped.
var target_world_position: Vector2 = Vector2.ZERO
var wrong_tap_limit: int = 0
var show_target_on_finish: bool = true


static func create(layout: TownLayout, look: Dictionary, hider_name_text: String, feet: Vector2) -> ChallengeData:
	var c := ChallengeData.new()
	c.map_id = layout.map_id
	c.map_version = layout.map_version
	c.generator_version = layout.generator_version
	c.map_seed = layout.map_seed
	c.challenge_id = _new_id()
	c.hider_name = hider_name_text.strip_edges().left(AvatarKit.MAX_NAME_LENGTH)
	c.hider_look = AvatarKit.normalize(look)
	c.target_world_position = feet.round()
	return c


## What is hidden, as VisibilityChecker / TownController.place_subject take it.
func subject() -> WorldObjectData:
	return VisibilityChecker.subject_for_look(hider_look)


## "Find Alex!" or "Find your friend!".
func seeker_title() -> String:
	return "Find %s!" % hider_name if hider_name != "" else "Find your friend!"


func to_dict() -> Dictionary:
	return {
		"schema_version": schema_version,
		"map_id": map_id,
		"map_version": map_version,
		"generator_version": generator_version,
		"seed": map_seed,
		"challenge_id": challenge_id,
		"hider": {"name": hider_name, "look": hider_look},
		"target": {
			"object_id": target_object_id,
			"world_position": [target_world_position.x, target_world_position.y],
		},
		"rules": {
			"wrong_tap_limit": wrong_tap_limit,
			"show_target_on_finish": show_target_on_finish,
		},
	}


## Random id for naming files only; never feeds map generation.
static func _new_id() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return "c-%d-%06x" % [int(Time.get_unix_time_from_system()), rng.randi() & 0xFFFFFF]
