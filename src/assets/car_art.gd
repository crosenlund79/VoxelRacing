class_name CarArt
extends RefCounted
## Which images a car is drawn with: ONE rule for every screen (racing, title,
## standings, results, championship, garage, Nemesis Welcome, Battle Royale).
##
## Every car is a wheel-free body ("cars/body_*") completed with four
## instances of the shared wheel ("cars/wheel") at the wheel-layout positions:
## moving wheels on the racing car, and the same body and wheels composed into
## one picture for the small static pictures (icons). So a car drawn once looks
## the same everywhere.
##
## Which artwork is the car (artwork precedence, the same everywhere):
##   1. the user's body drawing  body_<car>.png  (+ wheels)
##   2. the user's older flattened drawing  car_<car>.png (wheels painted in):
##      drawn as it is, never with extra wheels
##   3. the packaged body template  assets/graphics/cars/template_body_<car>.png  (+ wheels)
## "The user's drawing" = a custom/graphics/cars/ override, or the user's own
## file added to assets/graphics/cars/ under the plain name (AssetResolver).
## Legacy flattened names (car_*) have no packaged template at all: the
## packaged cars are only wheel-free bodies plus the shared wheel.

## Slight per-rival tints for the junker (index = racer id).
const JUNKER_TINTS: Array[Color] = [Color(1, 1, 1), Color(1, 0.92, 0.9), Color(0.92, 0.95, 1),
	Color(0.96, 1, 0.9), Color(1, 0.97, 0.86), Color(0.94, 0.9, 1), Color(1, 0.9, 0.96),
	Color(0.9, 1, 0.98), Color(1, 0.95, 0.92), Color(0.9, 0.94, 0.94)]

const WHEEL_LAYOUT := preload("res://src/presentation/default_wheel_layout.tres")

## Composed icons, per resolver and car (built once).
static var _icons: Dictionary = {}


## {body: Texture2D, wheels: bool, body_logical: String} for a car image name
## ("cars/car_player", "cars/car_ai_3", "cars/car_junker"...): the artwork
## precedence above.
static func look(resolver: AssetResolver, car_logical: String) -> Dictionary:
	var body := AssetCatalog.body_of(car_logical)
	if resolver.has_user_art(body) or not resolver.has_user_art(car_logical):
		return {"body": resolver.get_texture(body), "wheels": true, "body_logical": body}
	return {"body": resolver.get_texture(car_logical), "wheels": false, "body_logical": car_logical}


## Picture of the complete car for icons and static displays: exactly the
## car the race draws (look()), with its four wheels in their neutral place.
static func icon(resolver: AssetResolver, car_logical: String) -> Texture2D:
	var key := "%d:%s" % [resolver.get_instance_id(), car_logical]
	if _icons.has(key):
		return _icons[key]
	var l := look(resolver, car_logical)
	var tex: Texture2D = l.body
	if l.wheels:
		tex = compose(l.body, resolver.get_texture(AssetCatalog.WHEEL), WHEEL_LAYOUT.positions(l.body_logical))
	_icons[key] = tex
	return tex


## A body with four wheels under it, at the body image's own resolution
## (wheel positions in display pixels: front x, rear x, half track; the body
## shows at AssetCatalog car display size, the wheel at its display size).
static func compose(body: Texture2D, wheel: Texture2D, at: Vector3) -> Texture2D:
	var body_img := _rgba(body)
	if body_img == null:
		return body
	var size := body_img.get_size()
	var display: Vector2 = AssetCatalog.SPECS[AssetCatalog.CAR_PLAYER].display_size
	var px := Vector2(size) / display  # image pixels per display pixel
	var out := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var wheel_img := _rgba(wheel)
	if wheel_img != null:
		var wheel_size: Vector2 = AssetCatalog.SPECS[AssetCatalog.WHEEL].display_size * px
		var w := Vector2i(roundi(wheel_size.x), roundi(wheel_size.y))
		if wheel_img.get_size() != w:
			wheel_img.resize(maxi(w.x, 1), maxi(w.y, 1), Image.INTERPOLATE_BILINEAR)
		var centre := Vector2(size) * 0.5
		for x in [at.x, at.y]:
			for y in [-at.z, at.z]:
				var p := centre + Vector2(x, y) * px - Vector2(wheel_img.get_size()) * 0.5
				out.blend_rect(wheel_img, Rect2i(Vector2i.ZERO, wheel_img.get_size()), Vector2i(roundi(p.x), roundi(p.y)))
	out.blend_rect(body_img, Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)  # the body over the wheels, as in the race
	return ImageTexture.create_from_image(out)


static func _rgba(tex: Texture2D) -> Image:
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


## Forget composed icons (tests that change overrides at runtime).
static func clear_cache() -> void:
	_icons.clear()
