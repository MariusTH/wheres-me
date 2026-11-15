class_name TextureAtlas
extends RefCounted
## Packs every catalog texture (buildings, props, canopies) into a few big
## pages once per session, and hands out AtlasTextures for them. Drawing many
## different props from one page lets Godot batch them, and lets TownBake
## merge a whole strip of town (people included, via a white texel) into a
## single mesh.
##
## Each sprite is copied 1:1 with its edge pixels repeated into a small gutter,
## so linear filtering at the borders samples exactly what the original
## texture (clamped at its edge) would. The original Image stays attached to
## each AtlasTexture (meta "src_image") for MaskCanvas.

const PAGE_WIDTH := 4096
const MAX_PAGE_HEIGHT := 4096
## Edge pixels repeated around each sprite.
const GUTTER := 2
## Opaque white block at the top left of page 0 (see white_uv).
const WHITE_SIZE := 4

static var _by_path: Dictionary = {}
static var _pages: Array[ImageTexture] = []
static var _white_uv := Vector2(-1, -1)


static func built() -> bool:
	return not _pages.is_empty()


## The AtlasTexture for [param path] (null when it wasn't packed).
static func get_texture(path: String) -> AtlasTexture:
	return _by_path.get(path)


## UV of an opaque white texel on page 0 (for untextured shapes in a page mesh).
static func white_uv() -> Vector2:
	return _white_uv


static func page(i: int) -> Texture2D:
	return _pages[i]


static func page_count() -> int:
	return _pages.size()


## Packs [param paths] (res:// textures). Missing ones are skipped.
static func build(paths: Array) -> void:
	if built():
		return
	var images: Array = []
	for p: String in paths:
		if not ResourceLoader.exists(p):
			continue
		var tex := load(p) as Texture2D
		if tex == null:
			continue
		var img := tex.get_image()
		if img == null:
			continue
		if img.is_compressed():
			img.decompress()
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		images.append([p, img])
	# Tallest first: shelf packing wastes least that way.
	images.sort_custom(func(a: Array, b: Array) -> bool:
		return (a[1] as Image).get_height() > (b[1] as Image).get_height())
	var placements: Array = []  # [path, img, page, Vector2i]
	var page_heights: Array[int] = []
	var page_i := 0
	var x := GUTTER * 2 + WHITE_SIZE
	var y := 0
	var shelf_h := WHITE_SIZE + GUTTER * 2
	for item: Array in images:
		var img: Image = item[1]
		var w := img.get_width() + GUTTER * 2
		var h := img.get_height() + GUTTER * 2
		if x + w > PAGE_WIDTH:
			y += shelf_h
			x = 0
			shelf_h = 0
		if y + h > MAX_PAGE_HEIGHT:
			page_heights.append(y + shelf_h)
			page_i += 1
			x = 0
			y = 0
			shelf_h = 0
		placements.append([item[0], img, page_i, Vector2i(x + GUTTER, y + GUTTER)])
		x += w
		shelf_h = maxi(shelf_h, h)
	page_heights.append(y + shelf_h)
	var page_images: Array[Image] = []
	for h in page_heights:
		page_images.append(Image.create_empty(PAGE_WIDTH, maxi(4, (h + 3) / 4 * 4), false, Image.FORMAT_RGBA8))
	page_images[0].fill_rect(Rect2i(GUTTER, GUTTER, WHITE_SIZE, WHITE_SIZE), Color.WHITE)
	for pl: Array in placements:
		_blit_with_gutter(page_images[pl[2]], pl[1], pl[3])
	for pi in page_images:
		_pages.append(ImageTexture.create_from_image(pi))
	_white_uv = (Vector2(GUTTER, GUTTER) + Vector2.ONE * WHITE_SIZE * 0.5) / Vector2(page_images[0].get_size())
	for pl: Array in placements:
		var img: Image = pl[1]
		var at := AtlasTexture.new()
		at.atlas = _pages[pl[2]]
		at.region = Rect2(Vector2(pl[3]), Vector2(img.get_size()))
		at.set_meta("src_image", img)
		_by_path[pl[0]] = at


## Copies [param img] to [param at] and repeats its border pixels outwards.
static func _blit_with_gutter(dst: Image, img: Image, at: Vector2i) -> void:
	var w := img.get_width()
	var h := img.get_height()
	dst.blit_rect(img, Rect2i(0, 0, w, h), at)
	for g in range(1, GUTTER + 1):
		dst.blit_rect(img, Rect2i(0, 0, w, 1), at + Vector2i(0, -g))
		dst.blit_rect(img, Rect2i(0, h - 1, w, 1), at + Vector2i(0, h - 1 + g))
	for g in range(1, GUTTER + 1):
		dst.blit_rect(dst, Rect2i(at.x, at.y - GUTTER, 1, h + GUTTER * 2), Vector2i(at.x - g, at.y - GUTTER))
		dst.blit_rect(dst, Rect2i(at.x + w - 1, at.y - GUTTER, 1, h + GUTTER * 2), Vector2i(at.x + w - 1 + g, at.y - GUTTER))
