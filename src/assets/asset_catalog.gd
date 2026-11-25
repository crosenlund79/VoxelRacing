class_name AssetCatalog
extends RefCounted
## Replacement contract for every graphic and sound used by the game.
## Overrides may use any resolution but must keep the template's aspect ratio and
## orientation; the game scales each texture to its display size in world pixels.

const CAR_PLAYER := "cars/car_player"
## Second human player's car (two-player races).
const CAR_PLAYER_2 := "cars/car_player_2"
## Opponent cars: "cars/car_ai_1" .. "cars/car_ai_9" (see ai_car()).
const AI_CAR_COUNT := 9
const TARMAC := "track/tarmac"
const GRASS := "track/grass"
const WALL := "track/wall"
const START_LINE := "track/start_line"
const STAR_GOLD := "ui/star_gold"
## Kill feed / rankings: a permanent elimination, and a collision kill.
const TOMBSTONE := "ui/tombstone"
const CRASH := "ui/crash"
const TICKET := "ui/ticket"
const PIT_SIGN := "track/pit_sign"
const STAR_SILVER := "ui/star_silver"
const STAR_BRONZE := "ui/star_bronze"
const TREE_ROUND := "scenery/tree_round"
const TREE_BLOOM := "scenery/tree_bloom"
const BUSH := "scenery/bush"
const FLOWERS := "scenery/flowers"
const ROCK := "scenery/rock"
const TYRE_STACK := "scenery/tyre_stack"
const FLAG := "scenery/flag"
const GRANDSTAND := "scenery/grandstand"
const ROAD_WEAR := "decals/road_wear"
const GRID_BOX := "decals/grid_box"
const TIRE_MARK := "decals/tire_mark"
## Visual damage (2026-11-23): one shared wear overlay blended into every car's
## body as its condition drops (scratches, dents, soot).
const LAMP_POST := "scenery/lamp_post"
const ACHIEVEMENT_BADGE := "ui/achievement_badge"
const ACHIEVEMENT_LOCKED := "ui/achievement_locked"
## P2: one shared wheel image for every car, drawn four times per car.
## Championship rewards: the one junker every displaced rival drives.
const CAR_JUNKER := "cars/car_junker"

## display_size: world/screen pixels the texture is scaled to (sprites, strips).
## tile_world_size: world pixels covered by one repeat of a seamless tile.
const SPECS := {
	CAR_PLAYER: {"template_size": Vector2i(128, 72), "display_size": Vector2(64, 36),
		"notes": "Top-down, nose pointing right (+X), centred pivot, transparent background. LEGACY flattened car (wheels painted in): your own older drawing only, used when no body drawing exists; there is no packaged template. Prefer body_*."},
	CAR_PLAYER_2: {"template_size": Vector2i(128, 72), "display_size": Vector2(64, 36),
		"notes": "Player 2 car (two-player races); same contract as the player car. LEGACY flattened car (wheels painted in): your own older drawing only, used when no body drawing exists; there is no packaged template. Prefer body_*."},
	"cars/car_ai_1": {"template_size": Vector2i(128, 72), "display_size": Vector2(64, 36),
		"notes": "Opponent car 1; same contract as the player car. LEGACY flattened car (wheels painted in): your own older drawing only, used when no body drawing exists; there is no packaged template. Prefer body_*."},
	"cars/car_ai_2": {"template_size": Vector2i(128, 72), "display_size": Vector2(64, 36),
		"notes": "Opponent car 2; same contract as the player car. LEGACY flattened car (wheels painted in): your own older drawing only, used when no body drawing exists; there is no packaged template. Prefer body_*."},
	"cars/car_ai_3": {"template_size": Vector2i(128, 72), "display_size": Vector2(64, 36),
		"notes": "Opponent car 3; same contract as the player car. LEGACY flattened car (wheels painted in): your own older drawing only, used when no body drawing exists; there is no packaged template. Prefer body_*."},
	"cars/car_ai_4": {"template_size": Vector2i(128, 72), "display_size": Vector2(64, 36),
		"notes": "Opponent car 4; same contract as the player car. LEGACY flattened car (wheels painted in): your own older drawing only, used when no body drawing exists; there is no packaged template. Prefer body_*."},
	"cars/car_ai_5": {"template_size": Vector2i(128, 72), "display_size": Vector2(64, 36),
		"notes": "Opponent car 5; same contract as the player car. LEGACY flattened car (wheels painted in): your own older drawing only, used when no body drawing exists; there is no packaged template. Prefer body_*."},
	"cars/car_ai_6": {"template_size": Vector2i(128, 72), "display_size": Vector2(64, 36),
		"notes": "Opponent car 6; same contract as the player car. LEGACY flattened car (wheels painted in): your own older drawing only, used when no body drawing exists; there is no packaged template. Prefer body_*."},
	"cars/car_ai_7": {"template_size": Vector2i(128, 72), "display_size": Vector2(64, 36),
		"notes": "Opponent car 7; same contract as the player car. LEGACY flattened car (wheels painted in): your own older drawing only, used when no body drawing exists; there is no packaged template. Prefer body_*."},
	"cars/car_ai_8": {"template_size": Vector2i(128, 72), "display_size": Vector2(64, 36),
		"notes": "Opponent car 8; same contract as the player car. LEGACY flattened car (wheels painted in): your own older drawing only, used when no body drawing exists; there is no packaged template. Prefer body_*."},
	"cars/car_ai_9": {"template_size": Vector2i(128, 72), "display_size": Vector2(64, 36),
		"notes": "Opponent car 9; same contract as the player car. LEGACY flattened car (wheels painted in): your own older drawing only, used when no body drawing exists; there is no packaged template. Prefer body_*."},
	"cars/body_player": {"template_size": Vector2i(128, 72), "display_size": Vector2(64, 36),
		"notes": "Wheel-free body (P2): same size, orientation and pivot as the car image, transparent where the wheels go; the game adds four shared wheels (also in every static picture of the car). Takes precedence over the flattened car image."},
	"cars/body_player_2": {"template_size": Vector2i(128, 72), "display_size": Vector2(64, 36),
		"notes": "Wheel-free body (P2): same size, orientation and pivot as the car image, transparent where the wheels go; the game adds four shared wheels (also in every static picture of the car). Takes precedence over the flattened car image."},
	"cars/body_ai_1": {"template_size": Vector2i(128, 72), "display_size": Vector2(64, 36),
		"notes": "Wheel-free body (P2): same size, orientation and pivot as the car image, transparent where the wheels go; the game adds four shared wheels (also in every static picture of the car). Takes precedence over the flattened car image."},
	"cars/body_ai_2": {"template_size": Vector2i(128, 72), "display_size": Vector2(64, 36),
		"notes": "Wheel-free body (P2): same size, orientation and pivot as the car image, transparent where the wheels go; the game adds four shared wheels (also in every static picture of the car). Takes precedence over the flattened car image."},
	"cars/body_ai_3": {"template_size": Vector2i(128, 72), "display_size": Vector2(64, 36),
		"notes": "Wheel-free body (P2): same size, orientation and pivot as the car image, transparent where the wheels go; the game adds four shared wheels (also in every static picture of the car). Takes precedence over the flattened car image."},
	"cars/body_ai_4": {"template_size": Vector2i(128, 72), "display_size": Vector2(64, 36),
		"notes": "Wheel-free body (P2): same size, orientation and pivot as the car image, transparent where the wheels go; the game adds four shared wheels (also in every static picture of the car). Takes precedence over the flattened car image."},
	"cars/body_ai_5": {"template_size": Vector2i(128, 72), "display_size": Vector2(64, 36),
		"notes": "Wheel-free body (P2): same size, orientation and pivot as the car image, transparent where the wheels go; the game adds four shared wheels (also in every static picture of the car). Takes precedence over the flattened car image."},
	"cars/body_ai_6": {"template_size": Vector2i(128, 72), "display_size": Vector2(64, 36),
		"notes": "Wheel-free body (P2): same size, orientation and pivot as the car image, transparent where the wheels go; the game adds four shared wheels (also in every static picture of the car). Takes precedence over the flattened car image."},
	"cars/body_ai_7": {"template_size": Vector2i(128, 72), "display_size": Vector2(64, 36),
		"notes": "Wheel-free body (P2): same size, orientation and pivot as the car image, transparent where the wheels go; the game adds four shared wheels (also in every static picture of the car). Takes precedence over the flattened car image."},
	"cars/body_ai_8": {"template_size": Vector2i(128, 72), "display_size": Vector2(64, 36),
		"notes": "Wheel-free body (P2): same size, orientation and pivot as the car image, transparent where the wheels go; the game adds four shared wheels (also in every static picture of the car). Takes precedence over the flattened car image."},
	"cars/body_ai_9": {"template_size": Vector2i(128, 72), "display_size": Vector2(64, 36),
		"notes": "Wheel-free body (P2): same size, orientation and pivot as the car image, transparent where the wheels go; the game adds four shared wheels (also in every static picture of the car). Takes precedence over the flattened car image."},
	CAR_JUNKER: {"template_size": Vector2i(128, 72), "display_size": Vector2(64, 36),
		"notes": "Championship: the battered junker a rival drives after the player has won their car; same contract as the player car. LEGACY flattened car (wheels painted in): your own older drawing only, used when no body drawing exists; there is no packaged template. Prefer body_*."},
	"cars/body_junker": {"template_size": Vector2i(128, 72), "display_size": Vector2(64, 36),
		"notes": "Wheel-free junker body (championship rewards); same contract as the other bodies. One image for every displaced rival (each gets a slight tint)."},
	TARMAC: {"template_size": Vector2i(256, 256), "tile_world_size": 256.0,
		"notes": "Seamless repeating road surface, opaque."},
	GRASS: {"template_size": Vector2i(256, 256), "tile_world_size": 256.0,
		"notes": "Seamless repeating off-track ground, opaque."},
	WALL: {"template_size": Vector2i(128, 32), "display_size": Vector2(80, 20),
		"notes": "Barrier strip, seamless left-right, repeated along the track edge; transparent background."},
	START_LINE: {"template_size": Vector2i(32, 128), "display_size": Vector2(24, 150),
		"notes": "Start/finish strip, long axis across the road; stretched to road width."},
	TOMBSTONE: {"template_size": Vector2i(48, 48), "display_size": Vector2(20, 20),
		"notes": "Kill feed and rankings: a permanent elimination (DNF) caused by a driver; square, centred, transparent."},
	PIT_SIGN: {"template_size": Vector2i(128, 64), "display_size": Vector2(96, 48),
		"notes": "Pit lane entrance sign (PIT + arrow), placed beside the entrance behind the barrier; the arrow points along the driving direction (+X)."},
	TICKET: {"template_size": Vector2i(48, 48), "display_size": Vector2(20, 20),
		"notes": "Kill feed: a pit-lane collision ticket (a meaningful crash in the pit lane); square, centred, transparent."},
	CRASH: {"template_size": Vector2i(48, 48), "display_size": Vector2(20, 20),
		"notes": "Kill feed: a car put out of the race by collisions (no weapon); square, centred, transparent."},
	STAR_GOLD: {"template_size": Vector2i(48, 48), "display_size": Vector2(22, 22),
		"notes": "1st place marker in the race history; square, centred, transparent background."},
	STAR_SILVER: {"template_size": Vector2i(48, 48), "display_size": Vector2(22, 22),
		"notes": "2nd place marker; same contract as the gold star."},
	STAR_BRONZE: {"template_size": Vector2i(48, 48), "display_size": Vector2(22, 22),
		"notes": "3rd place marker; same contract as the gold star."},
	TREE_ROUND: {"template_size": Vector2i(128, 128), "display_size": Vector2(128, 128),
		"notes": "Top-down tree canopy, centred, transparent; sways gently."},
	TREE_BLOOM: {"template_size": Vector2i(112, 112), "display_size": Vector2(112, 112),
		"notes": "Top-down blossom tree, centred, transparent; sways gently."},
	BUSH: {"template_size": Vector2i(72, 72), "display_size": Vector2(72, 72), "notes": "Top-down bush, centred, transparent."},
	FLOWERS: {"template_size": Vector2i(64, 64), "display_size": Vector2(64, 64), "notes": "Flower patch, centred, transparent."},
	ROCK: {"template_size": Vector2i(56, 56), "display_size": Vector2(56, 56), "notes": "Rock, centred, transparent."},
	TYRE_STACK: {"template_size": Vector2i(56, 56), "display_size": Vector2(56, 56), "notes": "Tyre stack, centred, transparent."},
	FLAG: {"template_size": Vector2i(96, 64), "display_size": Vector2(48, 64), "frames": 2,
		"notes": "Marshal flag: horizontal strip of 2 frames (48x64 each), pole foot at bottom-left third."},
	GRANDSTAND: {"template_size": Vector2i(192, 80), "display_size": Vector2(288, 120),
		"notes": "Top-down grandstand; the crowd side (bottom edge) faces the track."},
	ROAD_WEAR: {"template_size": Vector2i(160, 64), "display_size": Vector2(240, 96),
		"notes": "Semi-transparent road wear decal, long axis along the driving direction."},
	GRID_BOX: {"template_size": Vector2i(72, 48), "display_size": Vector2(72, 48),
		"notes": "Painted grid-slot bracket; open side faces the driving direction (+X)."},
	TIRE_MARK: {"template_size": Vector2i(32, 12), "display_size": Vector2(10, 26),
		"notes": "Pair of rear-tyre marks along +X (stamped repeatedly while sliding); seamless left-right."},
	ACHIEVEMENT_BADGE: {"template_size": Vector2i(64, 64), "display_size": Vector2(48, 48),
		"notes": "Unlocked achievement medal (toast and list); square, centred, transparent."},
	ACHIEVEMENT_LOCKED: {"template_size": Vector2i(64, 64), "display_size": Vector2(48, 48),
		"notes": "Locked achievement medal; same contract as the unlocked one."},
	"variant_2/track/grass": {"template_size": Vector2i(256, 256), "tile_world_size": 256.0,
		"notes": "Variant 2 ground; same contract as track/grass (seamless, opaque)."},
	"variant_2/track/tarmac": {"template_size": Vector2i(256, 256), "tile_world_size": 256.0,
		"notes": "Variant 2 road surface; same contract as track/tarmac."},
	"variant_2/track/wall": {"template_size": Vector2i(128, 32), "display_size": Vector2(80, 20),
		"notes": "Variant 2 barrier strip; same contract as track/wall."},
	"variant_2/scenery/prop_1": {"template_size": Vector2i(128, 128), "display_size": Vector2(128, 128),
		"notes": "Variant 2 tall prop (sways), top-down, centred, transparent; any rotation."},
	"variant_2/scenery/prop_2": {"template_size": Vector2i(72, 72), "display_size": Vector2(72, 72),
		"notes": "Variant 2 medium prop, top-down, centred, transparent; any rotation."},
	"variant_2/scenery/prop_3": {"template_size": Vector2i(56, 56), "display_size": Vector2(56, 56),
		"notes": "Variant 2 small prop, top-down, centred, transparent; any rotation."},
	"variant_3/track/grass": {"template_size": Vector2i(256, 256), "tile_world_size": 256.0,
		"notes": "Variant 3 ground; same contract as track/grass (seamless, opaque)."},
	"variant_3/track/tarmac": {"template_size": Vector2i(256, 256), "tile_world_size": 256.0,
		"notes": "Variant 3 road surface; same contract as track/tarmac."},
	"variant_3/track/wall": {"template_size": Vector2i(128, 32), "display_size": Vector2(80, 20),
		"notes": "Variant 3 barrier strip; same contract as track/wall."},
	"variant_3/scenery/prop_1": {"template_size": Vector2i(128, 128), "display_size": Vector2(128, 128),
		"notes": "Variant 3 tall prop (sways), top-down, centred, transparent; any rotation."},
	"variant_3/scenery/prop_2": {"template_size": Vector2i(72, 72), "display_size": Vector2(72, 72),
		"notes": "Variant 3 medium prop, top-down, centred, transparent; any rotation."},
	"variant_3/scenery/prop_3": {"template_size": Vector2i(56, 56), "display_size": Vector2(56, 56),
		"notes": "Variant 3 small prop, top-down, centred, transparent; any rotation."},
	"variant_4/track/grass": {"template_size": Vector2i(256, 256), "tile_world_size": 256.0,
		"notes": "The Raceway ground: manicured striped grass; same contract as track/grass (seamless, opaque)."},
	"variant_4/track/tarmac": {"template_size": Vector2i(256, 256), "tile_world_size": 256.0,
		"notes": "The Raceway asphalt: clean dark grain; same contract as track/tarmac."},
	"variant_4/track/wall": {"template_size": Vector2i(128, 32), "display_size": Vector2(80, 20),
		"notes": "The Raceway barrier: red / white strip; same contract as track/wall."},
	"variant_4/scenery/prop_1": {"template_size": Vector2i(128, 128), "display_size": Vector2(128, 128),
		"notes": "The Raceway floodlight mast, top-down (lamp bank at the top), centred, transparent; any rotation."},
	"variant_4/scenery/prop_2": {"template_size": Vector2i(160, 48), "display_size": Vector2(200, 60),
		"notes": "The Raceway advertising board (original generic brand), text readable when the long edge faces the track; placed facing the road."},
	"variant_4/scenery/prop_3": {"template_size": Vector2i(56, 56), "display_size": Vector2(56, 56),
		"notes": "The Raceway marshal post, top-down, centred, transparent; any rotation."},
	"variant_4/scenery/pit_building": {"template_size": Vector2i(384, 128), "display_size": Vector2(480, 160),
		"notes": "The Raceway pit building beside the main straight; garage doors along the bottom edge face the track."},
	"variant_4/decals/kerb": {"template_size": Vector2i(64, 16), "display_size": Vector2(64, 14),
		"notes": "The Raceway kerb: red / white blocks along +X, seamless left-right; laid along the road edge on corners (visual only)."},
	"variant_5/track/grass": {"template_size": Vector2i(256, 256), "tile_world_size": 256.0,
		"notes": "Tabletop Mayhem ground: wooden desk; same contract as track/grass (seamless, opaque)."},
	"variant_5/track/tarmac": {"template_size": Vector2i(256, 256), "tile_world_size": 256.0,
		"notes": "Tabletop Mayhem road: toy race-track plastic; same contract as track/tarmac."},
	"variant_5/track/wall": {"template_size": Vector2i(128, 32), "display_size": Vector2(80, 20),
		"notes": "Tabletop Mayhem barrier: wooden ruler strip; same contract as track/wall."},
	"variant_5/scenery/prop_1": {"template_size": Vector2i(256, 256), "display_size": Vector2(220, 220),
		"notes": "Tabletop Mayhem giant coffee mug, top-down, centred, transparent; any rotation."},
	"variant_5/scenery/prop_2": {"template_size": Vector2i(128, 128), "display_size": Vector2(110, 110),
		"notes": "Tabletop Mayhem giant die, top-down, centred, transparent; any rotation."},
	"variant_5/scenery/prop_3": {"template_size": Vector2i(112, 112), "display_size": Vector2(96, 96),
		"notes": "Tabletop Mayhem toy block, top-down, centred, transparent; any rotation."},
	"variant_5/scenery/pencil": {"template_size": Vector2i(560, 88), "display_size": Vector2(560, 88),
		"notes": "Tabletop Mayhem giant pencil, point to the left, centred, transparent; any rotation."},
	"variant_5/scenery/card": {"template_size": Vector2i(220, 300), "display_size": Vector2(220, 300),
		"notes": "Tabletop Mayhem giant playing card (original design), centred, transparent; any rotation."},
	"variant_5/scenery/paperclip": {"template_size": Vector2i(280, 140), "display_size": Vector2(280, 140),
		"notes": "Tabletop Mayhem giant paperclip, centred, transparent; any rotation."},
	LAMP_POST: {"template_size": Vector2i(48, 48), "display_size": Vector2(56, 56),
		"notes": "Lighting pilot: top-down lamp post, lamp head towards the top (-Y), rotated to face the track."},
}

## Replaceable audio: logical name -> spec. bus: Music / Engine / Effects.
const AUDIO := {
	"vehicles/engine_loop": {"loop": true, "bus": "Engine",
		"notes": "Engine foundation: seamless deep loop (template ~41 Hz firing, body around 100-200 Hz), heard all the time; pitched about 0.78x (standstill) to 1.3x (top speed). WAV recommended for exact looping."},
	"vehicles/engine_load": {"loop": true, "bus": "Engine",
		"notes": "Engine load layer: seamless loop at the same pitch as the foundation (template: 2x firing order + soft intake roar, ~200-400 Hz), faded in while accelerating, silent when cruising. WAV recommended."},
	"vehicles/tire_squeal": {"loop": true, "bus": "Effects", "notes": "Seamless tyre squeal loop; WAV recommended."},
	"vehicles/impact_car": {"loop": false, "bus": "Effects", "notes": "Car-to-car bump, < 1 s."},
	"vehicles/impact_wall": {"loop": false, "bus": "Effects", "notes": "Car hits barrier, < 1 s."},
	"race/start_go": {"loop": false, "bus": "Effects", "notes": "Played when the race starts."},
	"race/finish": {"loop": false, "bus": "Effects", "notes": "Finish jingle (player finishes / spectator winner)."},
	"ui/ui_move": {"loop": false, "bus": "Effects", "notes": "Menu focus change."},
	"ui/ui_select": {"loop": false, "bus": "Effects", "notes": "Menu confirm."},
	"ui/ui_back": {"loop": false, "bus": "Effects", "notes": "Menu back."},
	"ambience/ambience": {"loop": true, "bus": "Effects", "notes": "Trackside ambience loop (wind, birds), stereo."},
	"music/music_menu": {"loop": true, "bus": "Music", "notes": "Menu music (title, GO RACING!, setup, garage, championship screens): the official HyperCars - Theme. OGG, WAV or MP3; played to its end and looped with a short crossfade."},
	"music/music_race": {"loop": true, "bus": "Music", "notes": "Race music (every race, Knockout, spectating): the official HyperCars - Racing Theme. OGG, WAV or MP3; played to its end and looped with a short crossfade."},
	"music/music_battle": {"loop": true, "bus": "Music", "notes": "Battle Royale music (the Scrapyard arena): the official HyperCars - Battle Royale theme. OGG, WAV or MP3; played to its end and looped with a short crossfade."},
	"weapons/missile_launch": {"loop": false, "bus": "Effects", "notes": "Missile fired."},
	"weapons/explosion": {"loop": false, "bus": "Effects", "notes": "Missile/mine explosion and car destroyed."},
	"weapons/mine_drop": {"loop": false, "bus": "Effects", "notes": "Mine dropped (clunk + arming beep)."},
	"weapons/empty": {"loop": false, "bus": "Effects", "notes": "Fire pressed with no ammunition left."},
	"ui/achievement": {"loop": false, "bus": "Effects", "notes": "Achievement unlocked jingle."},
	"ui/shop_buy": {"loop": false, "bus": "Effects", "notes": "Garage: weapon bought (coins)."},
	"ui/shop_sell": {"loop": false, "bus": "Effects", "notes": "Garage: weapon sold."},
	"weapons/homing_launch": {"loop": false, "bus": "Effects", "notes": "Homing missile fired (launch + seeker chirp)."},
	"weapons/super_launch": {"loop": false, "bus": "Effects", "notes": "Super missile fired (rising whirl)."},
}


## Track theme variants: the asset variant n uses for a shared logical name —
## "variant_<n>/<logical>" when the catalogue defines it, otherwise the shared
## asset. Variant 1 (the baseline) always uses the shared assets.
static func themed(logical: String, variant: int) -> String:
	if variant > 1:
		var key := "variant_%d/%s" % [variant, logical]
		if SPECS.has(key):
			return key
	return logical


## Wheel-free body for a car image name ("cars/car_ai_3" -> "cars/body_ai_3").
## Legacy flattened car images ("cars/car_*", wheels painted in): supported as
## the user's own drawings only; there is no packaged template (the packaged
## cars are wheel-free bodies plus the shared wheel).
static func is_legacy(logical: String) -> bool:
	return logical.begins_with("cars/car_")


static func body_of(car_logical: String) -> String:
	return car_logical.replace("cars/car_", "cars/body_")


## Logical name of opponent car n (1-based), cycling if more cars than templates.
static func ai_car(n: int) -> String:
	return "cars/car_ai_%d" % ((n - 1) % AI_CAR_COUNT + 1)


## Converts a world-space tile size to the UV scale for a texture of any resolution.
static func uv_per_world_pixel(texture: Texture2D, tile_world_size: float) -> Vector2:
	return Vector2(texture.get_width(), texture.get_height()) / tile_world_size


## Scale that maps a texture of any resolution onto its display size.
static func scale_for(texture: Texture2D, display_size: Vector2) -> Vector2:
	return display_size / Vector2(texture.get_width(), texture.get_height())
