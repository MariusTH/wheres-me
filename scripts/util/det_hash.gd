class_name DetHash
extends RefCounted
## Platform-stable hashing used to derive RNG seeds.
## Never use String.hash() or the global randi()/randf() for anything that
## affects a shared challenge: their output is not part of our data contract.

const FNV_OFFSET := 2166136261
const FNV_PRIME := 16777619
const MASK_32 := 0xFFFFFFFF


## 32-bit FNV-1a over the UTF-8 bytes of [param text]. Kept in 32 bits so the
## multiplication can never overflow a 64-bit int.
static func fnv1a_32(text: String) -> int:
	var h: int = FNV_OFFSET
	for b: int in text.to_utf8_buffer():
		h = ((h ^ b) * FNV_PRIME) & MASK_32
	return h


## Seed for an independent RNG stream (e.g. one per zone), so adding content
## to one zone never shifts the placements of another.
static func sub_seed(base_seed: int, salt: String) -> int:
	return fnv1a_32("%d|%s" % [base_seed, salt])


static func make_rng(base_seed: int, salt: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = sub_seed(base_seed, salt)
	return rng
