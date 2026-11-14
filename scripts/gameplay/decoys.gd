class_name Decoys
extends RefCounted
## Red herrings, Where's Wally style: a few crowd members get the hider's look
## with exactly one part changed (a different hat, other glasses, another
## trouser colour…), so a quick glance isn't enough. Deterministic from the
## seed and the hider's look, so hider and seeker see the same crowd.
## Who becomes a decoy depends only on the crowd's ids, never on their current
## looks, so applying it twice gives the same result.

## Parts a decoy may differ in. The shirt is the hider's most visible colour
## and the strongest cue; changing it is the "almost" that fools you.
const FIELDS: Array[String] = ["shirt", "hat", "hair_style", "hair", "pants", "glasses", "pattern", "coat"]


## Turns [param count] crowd members of [param layout] into decoys of
## [param look]. Returns the changed object ids.
static func apply(layout: TownLayout, look: Dictionary, count: int, map_seed: int) -> PackedStringArray:
	var changed := PackedStringArray()
	if count <= 0:
		return changed
	var crowd: Array[WorldObjectData] = []
	for obj in layout.objects:
		if obj.is_interactive and obj.id != ChallengeData.TARGET_OBJECT_ID:
			crowd.append(obj)
	if crowd.is_empty():
		return changed
	var target := AvatarKit.normalize(look)
	var rng := DetHash.make_rng(map_seed, "decoys:" + AvatarKit.look_key(target))
	var fields: Array[String] = []
	# Only parts that show on this look (a pattern under a coat changes nothing).
	for f in FIELDS:
		if AvatarKit.field_order().has(f) and AvatarKit.values(f).size() > 1 and AvatarKit.is_relevant(f, target):
			fields.append(f)
	var picked := {}
	for i in mini(count, crowd.size()):
		var idx := rng.randi_range(0, crowd.size() - 1)
		var tries := 0
		while picked.has(idx) and tries < crowd.size():
			idx = (idx + 1) % crowd.size()
			tries += 1
		picked[idx] = true
		var field := fields[rng.randi_range(0, fields.size() - 1)] if not fields.is_empty() else ""
		var obj := crowd[idx]
		obj.look = variant(target, field, rng)
		changed.append(obj.id)
	return changed


## [param look] with [param field] set to a different value. Keeps the change
## visible: a hat only matters when the decoy wears one, so "no hat" becomes a hat.
static func variant(look: Dictionary, field: String, rng: RandomNumberGenerator) -> Dictionary:
	var out := look.duplicate()
	if field == "":
		return AvatarKit.make_distinct(out, look)
	var vals := AvatarKit.values(field)
	var i := vals.find(out.get(field))
	var step := rng.randi_range(1, vals.size() - 1)
	out[field] = vals[(maxi(i, 0) + step) % vals.size()]
	out = AvatarKit.normalize(out)
	if AvatarKit.look_key(out) == AvatarKit.look_key(look):
		out = AvatarKit.make_distinct(out, look)
	return out
