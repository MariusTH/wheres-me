class_name PhotoToLook
extends RefCounted
## Turns selfie measurements (from web/selfie.js, see SelfieBridge) into part
## kit values. Pure and deterministic so it can be tested headless.
##
## Features dictionary (colours are [r, g, b] 0-255, or null when not seen):
##   skin, hair, shirt, hat     median colour of each segmented region
##   hair_ratio       hair pixels / face-skin pixels (≈0 when bald)
##   hair_below_chin  share of hair pixels lower than the chin (long hair)
##   hair_above_top   share of hair pixels well above the forehead (bun)
##   glasses          share of the eye band covered by accessories
##   hat_cover        share of the area above the forehead covered by accessories

## Photos are greyer than the painted kit colours, and hair photographs
## darker than it reads, so those are nudged before matching. Skin is matched
## as measured (lightening it made skin tones too light on test photos).
const HAIR_LIGHTEN := 8.0
const CLOTHES_SATURATE := 1.25
const BALD_BELOW := 0.08
const LONG_ABOVE := 0.12
const BUN_ABOVE := 0.22
const GLASSES_ABOVE := 0.12
const HAT_ABOVE := 0.35
## Lightness matters most for skin; hue and saturation matter more for clothes.
const SKIN_L_WEIGHT := 2.0


## [param look] with the parts a selfie can tell us replaced; everything a
## selfie can't see (build, trousers, accessory, ...) is kept.
static func apply(look: Dictionary, f: Dictionary) -> Dictionary:
	var out := AvatarKit.normalize(look)
	if f.get("skin") != null:
		out["skin"] = nearest(_color(f["skin"]), AvatarKit.values("skin"), SKIN_L_WEIGHT)
	out["hair_style"] = hair_style(f)
	if f.get("hair") != null and out["hair_style"] != "bald":
		out["hair"] = nearest(_lighten(_color(f["hair"])), AvatarKit.values("hair"))
	if f.get("shirt") != null:
		out["shirt"] = nearest(_saturate(_color(f["shirt"])), AvatarKit.values("shirt"))
		# A median colour can't see stripes or dots.
		out["pattern"] = "plain"
	out["glasses"] = float(f.get("glasses", 0.0)) > GLASSES_ABOVE
	if float(f.get("hat_cover", 0.0)) > HAT_ABOVE and f.get("hat") != null:
		if out["hat"] == "none":
			out["hat"] = "beanie"
		out["hat_color"] = nearest(_saturate(_color(f["hat"])), AvatarKit.values("hat_color"))
	else:
		out["hat"] = "none"
	return out


static func hair_style(f: Dictionary) -> String:
	if float(f.get("hair_ratio", 0.0)) < BALD_BELOW or f.get("hair") == null:
		return "bald"
	if float(f.get("hair_below_chin", 0.0)) > LONG_ABOVE:
		return "long"
	if float(f.get("hair_above_top", 0.0)) > BUN_ABOVE:
		return "bun"
	return "short"


## Palette entry ("#rrggbb") closest to [param c] in CIE Lab.
static func nearest(c: Color, palette: Array, l_weight: float = 1.0) -> String:
	var lab := to_lab(c)
	var best := String(palette[0])
	var best_d := INF
	for hex: String in palette:
		var p := to_lab(Color.html(hex))
		var d := pow((lab.x - p.x) * l_weight, 2) + pow(lab.y - p.y, 2) + pow(lab.z - p.z, 2)
		if d < best_d:
			best_d = d
			best = hex
	return best


## sRGB -> CIE Lab (D65). x = L, y = a, z = b.
static func to_lab(c: Color) -> Vector3:
	var lin := func(v: float) -> float:
		return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
	var r: float = lin.call(c.r)
	var g: float = lin.call(c.g)
	var b: float = lin.call(c.b)
	var x := (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
	var y := 0.2126 * r + 0.7152 * g + 0.0722 * b
	var z := (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
	var fn := func(t: float) -> float:
		return pow(t, 1.0 / 3.0) if t > 0.008856 else 7.787 * t + 16.0 / 116.0
	var fx: float = fn.call(x)
	var fy: float = fn.call(y)
	var fz: float = fn.call(z)
	return Vector3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))


static func _color(rgb: Variant) -> Color:
	var a: Array = rgb
	return Color8(int(a[0]), int(a[1]), int(a[2]))


static func _lighten(c: Color) -> Color:
	return Color.from_ok_hsl(c.ok_hsl_h, c.ok_hsl_s, clampf(c.ok_hsl_l + HAIR_LIGHTEN / 100.0, 0.0, 1.0))


static func _saturate(c: Color) -> Color:
	return Color.from_ok_hsl(c.ok_hsl_h, clampf(c.ok_hsl_s * CLOTHES_SATURATE, 0.0, 1.0), c.ok_hsl_l)
