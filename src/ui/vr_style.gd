class_name VrStyle
extends RefCounted
## VoxelRacing's visual identity for 2D interface pieces: the palette, the
## Pixel Operator typography (CC0, assets/fonts/pixel_operator/) and "voxel
## block" panels and buttons: chunky rectangles with a dark ink outline, a lit
## top edge, a darker depth band underneath and a hard block shadow, as if
## each button were a little voxel brick. Everything is generated here (no
## image files), so colours stay consistent everywhere.

# ---- palette: "miniature motorsport at dusk"
const INK := Color("1a1d38")          ## outlines, deep backgrounds
const NIGHT := Color("252a4e")        ## panels
const NIGHT_LIGHT := Color("343b6e")  ## panel top edge
const PAPER := Color("fff4de")        ## text
const PAPER_DIM := Color("fff4de", 0.62)
const RED := Color("e8432e")          ## primary: race red
const RED_DARK := Color("a62a1f")
const YELLOW := Color("f7b731")       ## highlight / selection / gold
const TEAL := Color("2ec4b6")         ## secondary accent
const GREEN := Color("7bc950")
const SKY := Color("59c3f2")
const PINK := Color("f45b9b")
const SHADOW := Color(0.04, 0.03, 0.1, 0.55)

const FONT_DIR := "res://assets/fonts/pixel_operator/"

static var _fonts := {}
static var _boxes := {}


## Pixel Operator: "regular", "bold", "mono", "mono_bold", "small" (8 px grid),
## "small_bold", "hb" (high-contrast bold).
static func font(kind: String = "regular") -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var file := {
		"regular": "PixelOperator.ttf", "bold": "PixelOperator-Bold.ttf",
		"mono": "PixelOperatorMono.ttf", "mono_bold": "PixelOperatorMono-Bold.ttf",
		"small": "PixelOperator8.ttf", "small_bold": "PixelOperator8-Bold.ttf",
		"hb": "PixelOperatorHB.ttf",
	}.get(kind, "PixelOperator.ttf") as String
	var f: Font = load(FONT_DIR + file)
	_fonts[kind] = f
	return f


## Pixel Operator is drawn on a 16 px grid: sizes snap to multiples of 8 so
## its pixels stay square.
static func px(size: int) -> int:
	return maxi(16, int(round(size / 8.0)) * 8)


## A voxel block: face colour, ink outline, lit top edge, darker depth band
## (`depth` px) and a block shadow. Returned as a StyleBoxTexture (nine-patch).
static func block(face: Color, depth: int = 6, outline: Color = INK, shadow: bool = true) -> StyleBoxTexture:
	var key := "%s|%d|%s|%s" % [face.to_html(), depth, outline.to_html(), shadow]
	if _boxes.has(key):
		return (_boxes[key] as StyleBoxTexture).duplicate()
	var w := 32
	var h := 32 + depth
	var sh := 4 if shadow else 0
	var img := Image.create(w + sh, h + sh, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	if shadow:
		img.fill_rect(Rect2i(sh, sh, w, h), SHADOW)
	img.fill_rect(Rect2i(0, 0, w, h), outline)
	img.fill_rect(Rect2i(3, 3, w - 6, h - 6), face.darkened(0.32))  # the depth band shows at the bottom
	img.fill_rect(Rect2i(3, 3, w - 6, h - 6 - depth), face)
	img.fill_rect(Rect2i(3, 3, w - 6, 3), face.lightened(0.28))  # lit top edge
	img.fill_rect(Rect2i(3, 6, 3, h - 12 - depth), face.lightened(0.12))
	var sb := StyleBoxTexture.new()
	sb.texture = ImageTexture.create_from_image(img)
	sb.texture_margin_left = 8
	sb.texture_margin_top = 8
	sb.texture_margin_right = 8 + sh
	sb.texture_margin_bottom = 8 + depth + sh
	sb.content_margin_left = 22
	sb.content_margin_right = 22 + sh
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8 + depth + sh
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	_boxes[key] = sb
	return sb.duplicate()


## A pressed block: shifted down onto its depth band.
static func block_pressed(face: Color, depth: int = 6) -> StyleBoxTexture:
	var sb := block(face.darkened(0.1), 2, INK, false)
	sb.content_margin_top = 8 + depth - 2
	return sb


## A panel: deep night-blue voxel slab with a lit rim.
static func panel(alpha: float = 0.94) -> StyleBoxTexture:
	var sb := block(Color(NIGHT, 1.0), 8)
	sb.modulate_color = Color(1, 1, 1, alpha)
	sb.content_margin_left = 24
	sb.content_margin_right = 28
	sb.content_margin_top = 20
	sb.content_margin_bottom = 30
	return sb


## A flat chip (small tags, HUD cells).
static func chip(face: Color, outline: Color = INK) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = face
	s.border_color = outline
	s.set_border_width_all(2)
	s.border_width_bottom = 4
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 2
	s.content_margin_bottom = 4
	return s


## The checkered motif (a strip of black and white squares), as a texture.
static func checker(cells_x: int = 16, cells_y: int = 2, cell: int = 4) -> ImageTexture:
	var img := Image.create(cells_x * cell, cells_y * cell, false, Image.FORMAT_RGBA8)
	for y in cells_y:
		for x in cells_x:
			img.fill_rect(Rect2i(x * cell, y * cell, cell, cell), PAPER if (x + y) % 2 == 0 else INK)
	return ImageTexture.create_from_image(img)


static var _backdrop: Texture2D


## The screens' backdrop (garage, championship, career, credits): a dusk
## gradient over a chequered pit floor of big voxel tiles, drawn at a low
## resolution and shown with crisp pixels.
static func backdrop() -> Texture2D:
	if _backdrop != null:
		return _backdrop
	var w := 320
	var h := 180
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var t := float(y) / h
		var c := INK.lerp(Color("4a2f66"), smoothstep(0.0, 0.75, t))
		for x in w:
			img.set_pixel(x, y, c)
	# the pit floor: tiles in perspective from the horizon down
	var horizon := 112
	for y in range(horizon, h):
		var d := float(y - horizon + 6)
		var row := int(log(d) * 7.0)
		for x in w:
			var u := (x - w * 0.5) / d
			var col := int(floor(u * 2.2))
			var light := 0.04 if (row + col) % 2 == 0 else 0.0
			var c := Color("2e2952").lerp(Color("3d356a"), float(y - horizon) / (h - horizon)).lightened(light)
			img.set_pixel(x, y, c)
	# a chequered skirting band along the horizon, and a red stripe
	for x in w:
		for y in range(horizon - 6, horizon):
			img.set_pixel(x, y, PAPER.darkened(0.15) if ((x / 3) + (y / 3)) % 2 == 0 else INK)
		img.set_pixel(x, horizon - 7, RED)
		img.set_pixel(x, horizon - 8, RED)
	var tex := ImageTexture.create_from_image(img)
	_backdrop = tex
	return tex


## The panel image (nine-patch) and its margin, for NinePatchRect panels.
static func panel_texture() -> Texture2D:
	return panel().texture
