# HyperCars replaceable assets

Generated from `src/assets/asset_catalog.gd` (the authoritative contract). Override rules: `assets/README.md`.

Lookup order for graphics: `custom/` override > your drawing added as `assets/graphics/<name>.png` (plain name) > Claude's `template_` fallback; the Artwork Mode (VoxelRacing: `artwork_mode = "original"` in `user://settings.cfg` [video], no longer in Settings) shows the templates only (after a restart). The artist's guide with pictures: `docs/ARTWORK_MASTER_LIST.md`.

Put your file at the **override path** inside `custom/` (project folder while developing; next to the executable in an exported Windows/Linux game). Restart the game to see it. A missing or invalid file falls back to the packaged `template_` asset. Never edit files in `custom/` from tools; they are yours.

## Graphics (PNG)

### Cars: body + shared wheel (P2)

Each car is drawn as **one body image** plus **four copies of one shared wheel image**; the front pair turns with the steering (up to ±30°), the rear pair shifts a pixel or two sideways when cornering, and the tread rolls as the car drives (the game scrolls the wheel image along X inside its own outline: one drawing, no extra frames).

- **Body** `custom/graphics/cars/body_<car>.png` (`body_player`, `body_player_2`, `body_ai_1` … `body_ai_9`): top-down, **nose pointing right (+X)**, the car centred in the image (the image centre is the car's pivot), transparent background, **no wheels painted in** (leave the wheel areas transparent or let the body edge cover the inner part of the wheels, as the templates do). Any resolution with the 16:9-ish 128 x 72 aspect; it is shown 64 x 36 world px.
- **Wheel** `custom/graphics/cars/wheel.png`: one tyre seen from above, rolling direction along X, centred, transparent background, 48 x 28 template (shown 12 x 7 world px; any resolution with that aspect). A tread that repeats seamlessly along X rolls best. Used for all ten cars; the body is drawn on top of it.
- **Attachment points** (display px from the car centre, car facing +X): front axle x = +16.5, rear axle x = −16.5, wheels y = ±10.5 (mostly under the body, about 2 px of tyre showing). These fit the template bodies. For a differently shaped body, set its own points in `src/presentation/default_wheel_layout.tres` (`per_car`: `"cars/body_ai_3": Vector3(front_x, rear_x, half_track)`); the motion amounts (`max_steer_degrees`, `rear_shift_px`, `roll_animation`, `roll_px`) are there too.
- **Older flattened car images** `custom/graphics/cars/car_<car>.png` (wheels painted in) still work: when such a file exists and no `body_<car>.png` does, it is drawn as it is, without extra wheels (no doubled wheels, no animation). A `body_` file takes precedence. Every picture of the car (title, standings, results, championship, Nemesis Welcome, arena) is made from the same artwork as the racing car: the body with its four wheels, or your flattened image when that is all there is. Complete list and drawing guide: `docs/ARTWORK_MASTER_LIST.md`.

Any resolution is accepted as long as the **aspect ratio and orientation** match the template; the game scales it to the display size. Cars face right (+X). Transparent backgrounds unless noted.

| Override path | Template size (px) | Display size (world px) | Notes |
|---|---|---|---|
| `custom/graphics/cars/body_ai_1.png` | 128 x 72 | 64 x 36 | Wheel-free body (P2): same size, orientation and pivot as the car image, transparent where the wheels go; the game adds four shared wheels (also in every static picture of the car). Takes precedence over the flattened car image. |
| `custom/graphics/cars/body_ai_2.png` | 128 x 72 | 64 x 36 | Wheel-free body (P2): same size, orientation and pivot as the car image, transparent where the wheels go; the game adds four shared wheels (also in every static picture of the car). Takes precedence over the flattened car image. |
| `custom/graphics/cars/body_ai_3.png` | 128 x 72 | 64 x 36 | Wheel-free body (P2): same size, orientation and pivot as the car image, transparent where the wheels go; the game adds four shared wheels (also in every static picture of the car). Takes precedence over the flattened car image. |
| `custom/graphics/cars/body_ai_4.png` | 128 x 72 | 64 x 36 | Wheel-free body (P2): same size, orientation and pivot as the car image, transparent where the wheels go; the game adds four shared wheels (also in every static picture of the car). Takes precedence over the flattened car image. |
| `custom/graphics/cars/body_ai_5.png` | 128 x 72 | 64 x 36 | Wheel-free body (P2): same size, orientation and pivot as the car image, transparent where the wheels go; the game adds four shared wheels (also in every static picture of the car). Takes precedence over the flattened car image. |
| `custom/graphics/cars/body_ai_6.png` | 128 x 72 | 64 x 36 | Wheel-free body (P2): same size, orientation and pivot as the car image, transparent where the wheels go; the game adds four shared wheels (also in every static picture of the car). Takes precedence over the flattened car image. |
| `custom/graphics/cars/body_ai_7.png` | 128 x 72 | 64 x 36 | Wheel-free body (P2): same size, orientation and pivot as the car image, transparent where the wheels go; the game adds four shared wheels (also in every static picture of the car). Takes precedence over the flattened car image. |
| `custom/graphics/cars/body_ai_8.png` | 128 x 72 | 64 x 36 | Wheel-free body (P2): same size, orientation and pivot as the car image, transparent where the wheels go; the game adds four shared wheels (also in every static picture of the car). Takes precedence over the flattened car image. |
| `custom/graphics/cars/body_ai_9.png` | 128 x 72 | 64 x 36 | Wheel-free body (P2): same size, orientation and pivot as the car image, transparent where the wheels go; the game adds four shared wheels (also in every static picture of the car). Takes precedence over the flattened car image. |
| `custom/graphics/cars/body_junker.png` | 128 x 72 | 64 x 36 | Wheel-free junker body (championship rewards); same contract as the other bodies. One image for every displaced rival (each gets a slight tint). |
| `custom/graphics/cars/body_player.png` | 128 x 72 | 64 x 36 | Wheel-free body (P2): same size, orientation and pivot as the car image, transparent where the wheels go; the game adds four shared wheels (also in every static picture of the car). Takes precedence over the flattened car image. |
| `custom/graphics/cars/body_player_2.png` | 128 x 72 | 64 x 36 | Wheel-free body (P2): same size, orientation and pivot as the car image, transparent where the wheels go; the game adds four shared wheels (also in every static picture of the car). Takes precedence over the flattened car image. |
| `custom/graphics/cars/car_ai_1.png` | 128 x 72 | 64 x 36 | Opponent car 1; same contract as the player car. LEGACY flattened car (wheels painted in): your own older drawing only, used when no body drawing exists; there is no packaged template. Prefer body_*. |
| `custom/graphics/cars/car_ai_2.png` | 128 x 72 | 64 x 36 | Opponent car 2; same contract as the player car. LEGACY flattened car (wheels painted in): your own older drawing only, used when no body drawing exists; there is no packaged template. Prefer body_*. |
| `custom/graphics/cars/car_ai_3.png` | 128 x 72 | 64 x 36 | Opponent car 3; same contract as the player car. LEGACY flattened car (wheels painted in): your own older drawing only, used when no body drawing exists; there is no packaged template. Prefer body_*. |
| `custom/graphics/cars/car_ai_4.png` | 128 x 72 | 64 x 36 | Opponent car 4; same contract as the player car. LEGACY flattened car (wheels painted in): your own older drawing only, used when no body drawing exists; there is no packaged template. Prefer body_*. |
| `custom/graphics/cars/car_ai_5.png` | 128 x 72 | 64 x 36 | Opponent car 5; same contract as the player car. LEGACY flattened car (wheels painted in): your own older drawing only, used when no body drawing exists; there is no packaged template. Prefer body_*. |
| `custom/graphics/cars/car_ai_6.png` | 128 x 72 | 64 x 36 | Opponent car 6; same contract as the player car. LEGACY flattened car (wheels painted in): your own older drawing only, used when no body drawing exists; there is no packaged template. Prefer body_*. |
| `custom/graphics/cars/car_ai_7.png` | 128 x 72 | 64 x 36 | Opponent car 7; same contract as the player car. LEGACY flattened car (wheels painted in): your own older drawing only, used when no body drawing exists; there is no packaged template. Prefer body_*. |
| `custom/graphics/cars/car_ai_8.png` | 128 x 72 | 64 x 36 | Opponent car 8; same contract as the player car. LEGACY flattened car (wheels painted in): your own older drawing only, used when no body drawing exists; there is no packaged template. Prefer body_*. |
| `custom/graphics/cars/car_ai_9.png` | 128 x 72 | 64 x 36 | Opponent car 9; same contract as the player car. LEGACY flattened car (wheels painted in): your own older drawing only, used when no body drawing exists; there is no packaged template. Prefer body_*. |
| `custom/graphics/cars/car_junker.png` | 128 x 72 | 64 x 36 | Championship: the battered junker a rival drives after the player has won their car; same contract as the player car. LEGACY flattened car (wheels painted in): your own older drawing only, used when no body drawing exists; there is no packaged template. Prefer body_*. |
| `custom/graphics/cars/car_player.png` | 128 x 72 | 64 x 36 | Top-down, nose pointing right (+X), centred pivot, transparent background. LEGACY flattened car (wheels painted in): your own older drawing only, used when no body drawing exists; there is no packaged template. Prefer body_*. |
| `custom/graphics/cars/car_player_2.png` | 128 x 72 | 64 x 36 | Player 2 car (two-player races); same contract as the player car. LEGACY flattened car (wheels painted in): your own older drawing only, used when no body drawing exists; there is no packaged template. Prefer body_*. |
| `custom/graphics/cars/wheel.png` | 48 x 28 | 12 x 7 | Shared wheel (P2), top-down, rolling direction along X (car nose right), centred pivot, transparent background. One image for all ten cars; four instances per car at the positions in src/presentation/default_wheel_layout.tres. While driving, its colours scroll along X inside its own outline (rolling tread): a tread that repeats seamlessly along X rolls best; one drawing, no extra frames. |
| `custom/graphics/decals/grid_box.png` | 72 x 48 | 72 x 48 | Painted grid-slot bracket; open side faces the driving direction (+X). |
| `custom/graphics/decals/road_wear.png` | 160 x 64 | 240 x 96 | Semi-transparent road wear decal, long axis along the driving direction. |
| `custom/graphics/decals/tire_mark.png` | 32 x 12 | 10 x 26 | Pair of rear-tyre marks along +X (stamped repeatedly while sliding); seamless left-right. |
| `custom/graphics/fx/blast.png` | 96 x 96 | 110 x 110 | Explosion burst, centred, transparent; scaled up and faded out. |
| `custom/graphics/fx/confetti.png` | 12 x 12 | 12 x 12 | White confetti piece; tinted at runtime, so keep it white/light. |
| `custom/graphics/fx/dust.png` | 32 x 32 | 32 x 32 | Dust particle, soft, transparent. |
| `custom/graphics/fx/smoke.png` | 32 x 32 | 32 x 32 | Tyre-smoke particle, soft, transparent. |
| `custom/graphics/fx/spark.png` | 24 x 24 | 24 x 24 | Impact spark particle. |
| `custom/graphics/fx/car_wear.png` | 128 x 72 | 64 x 36 | Damage wear (2026-11-23): scratches, dents and soot on a transparent background, top-down, nose right (+X), the same frame as a car body. One image for every car: the game blends it into each car's body (only where the body is painted) more strongly as the car's condition drops. No per-car damage drawings. |
| `custom/graphics/scenery/bush.png` | 72 x 72 | 72 x 72 | Top-down bush, centred, transparent. |
| `custom/graphics/scenery/flag.png` | 96 x 64 | 48 x 64 | Marshal flag: horizontal strip of 2 frames (48x64 each), pole foot at bottom-left third. |
| `custom/graphics/scenery/flowers.png` | 64 x 64 | 64 x 64 | Flower patch, centred, transparent. |
| `custom/graphics/scenery/grandstand.png` | 192 x 80 | 288 x 120 | Top-down grandstand; the crowd side (bottom edge) faces the track. |
| `custom/graphics/scenery/lamp_post.png` | 48 x 48 | 56 x 56 | Lighting pilot: top-down lamp post, lamp head towards the top (-Y), rotated to face the track. |
| `custom/graphics/scenery/rock.png` | 56 x 56 | 56 x 56 | Rock, centred, transparent. |
| `custom/graphics/scenery/tree_bloom.png` | 112 x 112 | 112 x 112 | Top-down blossom tree, centred, transparent; sways gently. |
| `custom/graphics/scenery/tree_round.png` | 128 x 128 | 128 x 128 | Top-down tree canopy, centred, transparent; sways gently. |
| `custom/graphics/scenery/tyre_stack.png` | 56 x 56 | 56 x 56 | Tyre stack, centred, transparent. |
| `custom/graphics/track/grass.png` | 256 x 256 | tile = 256 | Seamless repeating off-track ground, opaque. |
| `custom/graphics/track/pit_sign.png` | 128 x 64 | 96 x 48 | Pit lane entrance sign (PIT + arrow), placed beside the entrance behind the barrier; the arrow points along the driving direction (+X). |
| `custom/graphics/track/start_line.png` | 32 x 128 | 24 x 150 | Start/finish strip, long axis across the road; stretched to road width. |
| `custom/graphics/track/tarmac.png` | 256 x 256 | tile = 256 | Seamless repeating road surface, opaque. |
| `custom/graphics/track/wall.png` | 128 x 32 | 80 x 20 | Barrier strip, seamless left-right, repeated along the track edge; transparent background. |
| `custom/graphics/ui/achievement_badge.png` | 64 x 64 | 48 x 48 | Unlocked achievement medal (toast and list); square, centred, transparent. |
| `custom/graphics/ui/achievement_locked.png` | 64 x 64 | 48 x 48 | Locked achievement medal; same contract as the unlocked one. |
| `custom/graphics/ui/button.png` | 96 x 48 | nine-patch, 16 px margins | Menu button nine-patch (16 px corners); hover/pressed/focus states are tints of it. |
| `custom/graphics/ui/garage_backdrop.png` | 640 x 360 | 1280 x 720 | Garage screen background, full screen (16:9), opaque; the centre is covered by the weapon cards. |
| `custom/graphics/ui/hud_panel.png` | 96 x 96 | nine-patch, 24 px margins | Nine-patch panel; 24 px corners are not stretched (scaled with the texture). |
| `custom/graphics/ui/logo.png` | 880 x 240 | 660 x 180 | Title logo; transparent background, centred. |
| `custom/graphics/ui/star_bronze.png` | 48 x 48 | 22 x 22 | 3rd place marker; same contract as the gold star. |
| `custom/graphics/ui/ticket.png` | 48 x 48 | 20 x 20 | Kill feed: a pit-lane collision ticket (a meaningful crash in the pit lane); square, centred, transparent. |
| `custom/graphics/ui/tombstone.png` | 48 x 48 | 20 x 20 | Kill feed and rankings: a permanent elimination (DNF) caused by a driver; square, centred, transparent. |
| `custom/graphics/ui/crash.png` | 48 x 48 | 20 x 20 | Kill feed: a car put out of the race by collisions (no weapon); square, centred, transparent. |
| `custom/graphics/ui/star_gold.png` | 48 x 48 | 22 x 22 | 1st place marker in the race history; square, centred, transparent background. |
| `custom/graphics/ui/star_silver.png` | 48 x 48 | 22 x 22 | 2nd place marker; same contract as the gold star. |
| `custom/graphics/variant_2/scenery/prop_1.png` | 128 x 128 | 128 x 128 | Variant 2 tall prop (sways), top-down, centred, transparent; any rotation. |
| `custom/graphics/variant_2/scenery/prop_2.png` | 72 x 72 | 72 x 72 | Variant 2 medium prop, top-down, centred, transparent; any rotation. |
| `custom/graphics/variant_2/scenery/prop_3.png` | 56 x 56 | 56 x 56 | Variant 2 small prop, top-down, centred, transparent; any rotation. |
| `custom/graphics/variant_2/track/grass.png` | 256 x 256 | tile = 256 | Variant 2 ground; same contract as track/grass (seamless, opaque). |
| `custom/graphics/variant_2/track/tarmac.png` | 256 x 256 | tile = 256 | Variant 2 road surface; same contract as track/tarmac. |
| `custom/graphics/variant_2/track/wall.png` | 128 x 32 | 80 x 20 | Variant 2 barrier strip; same contract as track/wall. |
| `custom/graphics/variant_3/scenery/prop_1.png` | 128 x 128 | 128 x 128 | Variant 3 tall prop (sways), top-down, centred, transparent; any rotation. |
| `custom/graphics/variant_3/scenery/prop_2.png` | 72 x 72 | 72 x 72 | Variant 3 medium prop, top-down, centred, transparent; any rotation. |
| `custom/graphics/variant_3/scenery/prop_3.png` | 56 x 56 | 56 x 56 | Variant 3 small prop, top-down, centred, transparent; any rotation. |
| `custom/graphics/variant_3/track/grass.png` | 256 x 256 | tile = 256 | Variant 3 ground; same contract as track/grass (seamless, opaque). |
| `custom/graphics/variant_3/track/tarmac.png` | 256 x 256 | tile = 256 | Variant 3 road surface; same contract as track/tarmac. |
| `custom/graphics/variant_3/track/wall.png` | 128 x 32 | 80 x 20 | Variant 3 barrier strip; same contract as track/wall. |
| `custom/graphics/variant_4/decals/kerb.png` | 64 x 16 | 64 x 14 | The Raceway kerb: red / white blocks along +X, seamless left-right; laid along the road edge on corners (visual only). |
| `custom/graphics/variant_4/scenery/pit_building.png` | 384 x 128 | 480 x 160 | The Raceway pit building beside the main straight; garage doors along the bottom edge face the track. |
| `custom/graphics/variant_4/scenery/prop_1.png` | 128 x 128 | 128 x 128 | The Raceway floodlight mast, top-down (lamp bank at the top), centred, transparent; any rotation. |
| `custom/graphics/variant_4/scenery/prop_2.png` | 160 x 48 | 200 x 60 | The Raceway advertising board (original generic brand), text readable when the long edge faces the track; placed facing the road. |
| `custom/graphics/variant_4/scenery/prop_3.png` | 56 x 56 | 56 x 56 | The Raceway marshal post, top-down, centred, transparent; any rotation. |
| `custom/graphics/variant_4/track/grass.png` | 256 x 256 | tile = 256 | The Raceway ground: manicured striped grass; same contract as track/grass (seamless, opaque). |
| `custom/graphics/variant_4/track/tarmac.png` | 256 x 256 | tile = 256 | The Raceway asphalt: clean dark grain; same contract as track/tarmac. |
| `custom/graphics/variant_4/track/wall.png` | 128 x 32 | 80 x 20 | The Raceway barrier: red / white strip; same contract as track/wall. |
| `custom/graphics/variant_5/scenery/card.png` | 220 x 300 | 220 x 300 | Tabletop Mayhem giant playing card (original design), centred, transparent; any rotation. |
| `custom/graphics/variant_5/scenery/paperclip.png` | 280 x 140 | 280 x 140 | Tabletop Mayhem giant paperclip, centred, transparent; any rotation. |
| `custom/graphics/variant_5/scenery/pencil.png` | 560 x 88 | 560 x 88 | Tabletop Mayhem giant pencil, point to the left, centred, transparent; any rotation. |
| `custom/graphics/variant_5/scenery/prop_1.png` | 256 x 256 | 220 x 220 | Tabletop Mayhem giant coffee mug, top-down, centred, transparent; any rotation. |
| `custom/graphics/variant_5/scenery/prop_2.png` | 128 x 128 | 110 x 110 | Tabletop Mayhem giant die, top-down, centred, transparent; any rotation. |
| `custom/graphics/variant_5/scenery/prop_3.png` | 112 x 112 | 96 x 96 | Tabletop Mayhem toy block, top-down, centred, transparent; any rotation. |
| `custom/graphics/variant_5/track/grass.png` | 256 x 256 | tile = 256 | Tabletop Mayhem ground: wooden desk; same contract as track/grass (seamless, opaque). |
| `custom/graphics/variant_5/track/tarmac.png` | 256 x 256 | tile = 256 | Tabletop Mayhem road: toy race-track plastic; same contract as track/tarmac. |
| `custom/graphics/variant_5/track/wall.png` | 128 x 32 | 80 x 20 | Tabletop Mayhem barrier: wooden ruler strip; same contract as track/wall. |
| `custom/graphics/weapons/homing_missile.png` | 40 x 16 | 30 x 12 | Homing missile, nose pointing right (+X), centred; also the HUD / garage icon. |
| `custom/graphics/weapons/mine.png` | 64 x 32 | 26 x 26 | Mine: horizontal strip of 2 frames (32x32 each: lamp off / lamp on), blinks while armed; also the HUD mine icon. |
| `custom/graphics/weapons/missile.png` | 40 x 16 | 30 x 12 | Missile, nose pointing right (+X), centred; also the HUD missile icon. Homing/super missiles are tinted. |
| `custom/graphics/weapons/super_missile.png` | 40 x 20 | 34 x 17 | Super missile (orbits its car), nose pointing right (+X), centred; also the HUD / garage icon. |

## Audio (OGG Vorbis, WAV or MP3)

`.ogg` is looked up first, then `.wav`. Looping sounds loop over the whole file; use WAV when a loop must be sample-exact (OGG encoding can trim the end). Buses: Music, Engine, Effects (all under Master).

| Override path (.ogg or .wav) | Loops | Bus | Notes |
|---|---|---|---|
| `custom/audio/ambience/ambience` | yes | Effects | Trackside ambience loop (wind, birds), stereo. |
| `custom/audio/music/music_menu` | yes | Music | Menu music (title, GO RACING!, setup, garage, championship screens): the official HyperCars - Theme. OGG, WAV or MP3; played to its end and looped with a short crossfade. |
| `custom/audio/music/music_race` | yes | Music | Race music (every race, Knockout, spectating): the official HyperCars - Racing Theme. OGG, WAV or MP3; played to its end and looped with a short crossfade. |
| `custom/audio/music/music_battle` | yes | Music | Battle Royale music (the Scrapyard arena): the official HyperCars - Battle Royale theme. OGG, WAV or MP3; played to its end and looped with a short crossfade. |
| `custom/audio/race/finish` | no | Effects | Finish jingle (player finishes / spectator winner). |
| `custom/audio/race/start_go` | no | Effects | Played when the race starts. |
| `custom/audio/ui/achievement` | no | Effects | Achievement unlocked jingle. |
| `custom/audio/ui/shop_buy` | no | Effects | Garage: weapon bought (coins). |
| `custom/audio/ui/shop_sell` | no | Effects | Garage: weapon sold. |
| `custom/audio/ui/ui_back` | no | Effects | Menu back. |
| `custom/audio/ui/ui_move` | no | Effects | Menu focus change. |
| `custom/audio/ui/ui_select` | no | Effects | Menu confirm. |
| `custom/audio/vehicles/engine_loop` | yes | Engine | Engine foundation: seamless deep loop (template ~41 Hz firing, body around 100-200 Hz), heard all the time; pitched about 0.78x (standstill) to 1.3x (top speed). WAV recommended for exact looping. |
| `custom/audio/vehicles/engine_load` | yes | Engine | Engine load layer: seamless loop at the same pitch as the foundation (template: 2x firing order + soft intake roar, ~200-400 Hz), faded in while accelerating, silent when cruising. WAV recommended. |
| `custom/audio/vehicles/impact_car` | no | Effects | Car-to-car bump, < 1 s. |
| `custom/audio/vehicles/impact_wall` | no | Effects | Car hits barrier, < 1 s. |
| `custom/audio/vehicles/tire_squeal` | yes | Effects | Seamless tyre squeal loop; WAV recommended. |
| `custom/audio/weapons/empty` | no | Effects | Fire pressed with no ammunition left. |
| `custom/audio/weapons/explosion` | no | Effects | Missile/mine explosion and car destroyed. |
| `custom/audio/weapons/homing_launch` | no | Effects | Homing missile fired (launch + seeker chirp). |
| `custom/audio/weapons/mine_drop` | no | Effects | Mine dropped (clunk + arming beep). |
| `custom/audio/weapons/missile_launch` | no | Effects | Missile fired. |
| `custom/audio/weapons/super_launch` | no | Effects | Super missile fired (rising whirl). |

## Not replaceable through custom/

- Font: `assets/fonts/Fredoka.ttf` (Fredoka, SIL Open Font License 1.1; licence in `assets/fonts/Fredoka_OFL.txt`).
