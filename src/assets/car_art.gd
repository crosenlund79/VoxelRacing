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
	# VoxelRacing: the car's own voxel model, rendered at startup (VoxelIconStudio)
	var body_name := AssetCatalog.body_of(car_logical)
	if VoxelIconStudio.icons.has(body_name):
		return VoxelIconStudio.icons[body_name]
	return look(resolver, car_logical).body  # (before the voxel renders exist)


## Forget composed icons (tests that change overrides at runtime).
static func clear_cache() -> void:
	_icons.clear()
