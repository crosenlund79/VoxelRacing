# HyperCars artwork master list

Everything in the game that can be drawn, in one place: what each picture is, where
it goes, how big, and which way up. Generated from the game's own artwork catalogue
(`src/assets/asset_catalog.gd`) by `docs/artwork/make_reference.py`, so it is always
the complete list. Technical contract: `assets/README.md`, `docs/ASSET_SPECS.md`.

**81 images to draw** (primary, each with a packaged `template_` picture), plus **12 legacy flattened-car names** you do not need (your older drawings only, no packaged picture): 93 catalogued names in total. Your own drawings already in use: 6.

## How to replace a picture

The game looks for each picture in this order (graphics):

1. `custom/graphics/<name>.png`: your override;
2. `assets/graphics/<name>.png`: your drawing added to the project under the
   plain name;
3. `assets/graphics/<folder>/template_<name>.png`: Claude's template, only the
   fallback.

`template_` files are never your files and are only used where you have not drawn
something. Files without the prefix (in `custom/` or `assets/`) are yours.
**Settings > ORIGINAL TEMPLATE ARTWORK** (the Artwork Mode, applied at the next
start) shows only the templates, to compare; switch it off to see your drawings
again. Music and voices are not affected.

Pick one of two places; restart the game to see it.

1. **`custom/graphics/<name>.png`**: in the project's `custom/` folder while
   developing, or next to the exported Windows / Linux game. This always wins and
   needs no rebuild.
2. **`assets/graphics/<name>.png`**: your drawing added to the project under the
   plain name (no `template_` prefix). It replaces Claude's `template_` picture in
   the packaged game.

**Rules:**
- Any resolution works if it keeps the template's **shape** (aspect ratio) and
  orientation. Drawing at 2x or 4x the template size is recommended; the game
  scales it to the display size.
- A missing or broken file falls back to the template.
- Claude never edits your files.

## Cars: draw each car once

- **What to draw:** one **wheel-free body** per car (`cars/body_*`) and one shared
  **wheel** (`cars/wheel`). The game adds four wheels to every car: they steer up to
  ±30° in races, the tread rolls as the car drives (the game scrolls your one wheel
  drawing inside its outline: a tread that repeats along X rolls best), and the same
  four are composed into every picture of the car (title
  backdrop, standings, results, championship rewards, Nemesis Welcome, arena scrap
  piles). A car drawn once looks the same everywhere.
- **The body:**
  - nose pointing right (+X), centred (the image centre is the car's pivot);
  - no wheels painted in;
  - leave the wheel areas transparent, or let the body edge cover their inner half
    as the templates do.
- **Night lights need nothing painted:** the game places two headlights and two
  red lights a little in from the corners of the car outline (front at +X). Painted
  lamps are decoration only. The one thing that matters is the nose direction: a
  drawing with its nose to the left looks as if it drives backwards, with the
  headlights at its painted tail ([night_lights_before_after.jpg](artwork/night_lights_before_after.jpg),
  last row).
- **Wheel positions** (display px from the car centre): front axle +16.5, rear
  axle −16.5, wheels ±10.5 sideways (mostly under the body, about 2 px of tyre showing).
  For a differently shaped body, set its own
  points in `src/presentation/default_wheel_layout.tres` (`per_car`).
- **Which artwork wins** (the same on every screen):
  1. your body drawing (with wheels);
  2. your older flattened `car_*` drawing (used as it is, never with extra wheels);
  3. Claude's body template (with wheels).
- **Legacy names:** `cars/car_*` exist only so older flattened drawings keep
  working. There is no packaged picture for them: every packaged car is a
  wheel-free body plus the shared wheel.

Proof that one drawing shows everywhere: [acceptance_car_art.png](artwork/acceptance_car_art.png)
(the real game with test drawings in a scratch override folder):

- a green 77 player body in the race, the title, the standings and the
  championship / results pictures;
- a legacy flattened car with no extra wheels;
- both files present (the body wins);
- a custom body for Hank;
- a won car and the junker;
- the packaged default restored when the override is removed.

## Vehicles

Cars: one wheel-free body per car plus the shared wheel. Draw these. Reference sheet: [sheet_vehicles.png](artwork/sheet_vehicles.png)

| Name | What it is / where it appears | Template (px) | Shown at (world px) | Frames | Orientation | Background | Status | Packaged template | Your replacement |
|---|---|---|---|---|---|---|---|---|---|
| `cars/wheel` | Shared wheel (P2), top-down, rolling direction along X (car nose right), centred pivot, transparent background. One image for all ten cars; four instances per car at the positions in src/presentation/default_wheel_layout.tres. While driving, its colours scroll along X inside its own outline (rolling tread): a tread that repeats seamlessly along X rolls best; one drawing, no extra frames. | 48 x 28 | 12 x 7 | 1 | top-down, nose pointing right (+X), car centred | transparent background | primary | `assets/graphics/cars/template_wheel.png` | `custom/graphics/cars/wheel.png` |
| `cars/body_ai_1` | Wheel-free body (P2): same size, orientation and pivot as the car image, transparent where the wheels go; the game adds four shared wheels (also in every static picture of the car). Takes precedence over the flattened car image. | 128 x 72 | 64 x 36 | 1 | top-down, nose pointing right (+X), car centred | transparent background | primary | `assets/graphics/cars/template_body_ai_1.png` | `custom/graphics/cars/body_ai_1.png` |
| `cars/body_ai_2` | Wheel-free body (P2): same size, orientation and pivot as the car image, transparent where the wheels go; the game adds four shared wheels (also in every static picture of the car). Takes precedence over the flattened car image. | 128 x 72 | 64 x 36 | 1 | top-down, nose pointing right (+X), car centred | transparent background | primary | `assets/graphics/cars/template_body_ai_2.png` | `custom/graphics/cars/body_ai_2.png` |
| `cars/body_ai_3` | Wheel-free body (P2): same size, orientation and pivot as the car image, transparent where the wheels go; the game adds four shared wheels (also in every static picture of the car). Takes precedence over the flattened car image. | 128 x 72 | 64 x 36 | 1 | top-down, nose pointing right (+X), car centred | transparent background | primary | `assets/graphics/cars/template_body_ai_3.png` | `custom/graphics/cars/body_ai_3.png` |
| `cars/body_ai_4` | Wheel-free body (P2): same size, orientation and pivot as the car image, transparent where the wheels go; the game adds four shared wheels (also in every static picture of the car). Takes precedence over the flattened car image. | 128 x 72 | 64 x 36 | 1 | top-down, nose pointing right (+X), car centred | transparent background | primary | `assets/graphics/cars/template_body_ai_4.png` | `custom/graphics/cars/body_ai_4.png` |
| `cars/body_ai_5` | Wheel-free body (P2): same size, orientation and pivot as the car image, transparent where the wheels go; the game adds four shared wheels (also in every static picture of the car). Takes precedence over the flattened car image. | 128 x 72 | 64 x 36 | 1 | top-down, nose pointing right (+X), car centred | transparent background | primary | `assets/graphics/cars/template_body_ai_5.png` | `custom/graphics/cars/body_ai_5.png` |
| `cars/body_ai_6` | Wheel-free body (P2): same size, orientation and pivot as the car image, transparent where the wheels go; the game adds four shared wheels (also in every static picture of the car). Takes precedence over the flattened car image. | 128 x 72 | 64 x 36 | 1 | top-down, nose pointing right (+X), car centred | transparent background | primary | `assets/graphics/cars/template_body_ai_6.png` | `custom/graphics/cars/body_ai_6.png` |
| `cars/body_ai_7` | Wheel-free body (P2): same size, orientation and pivot as the car image, transparent where the wheels go; the game adds four shared wheels (also in every static picture of the car). Takes precedence over the flattened car image. | 128 x 72 | 64 x 36 | 1 | top-down, nose pointing right (+X), car centred | transparent background | primary | `assets/graphics/cars/template_body_ai_7.png` | `custom/graphics/cars/body_ai_7.png` |
| `cars/body_ai_8` | Wheel-free body (P2): same size, orientation and pivot as the car image, transparent where the wheels go; the game adds four shared wheels (also in every static picture of the car). Takes precedence over the flattened car image. | 128 x 72 | 64 x 36 | 1 | top-down, nose pointing right (+X), car centred | transparent background | primary | `assets/graphics/cars/template_body_ai_8.png` | `custom/graphics/cars/body_ai_8.png` |
| `cars/body_ai_9` | Wheel-free body (P2): same size, orientation and pivot as the car image, transparent where the wheels go; the game adds four shared wheels (also in every static picture of the car). Takes precedence over the flattened car image. | 128 x 72 | 64 x 36 | 1 | top-down, nose pointing right (+X), car centred | transparent background | primary | `assets/graphics/cars/template_body_ai_9.png` | `custom/graphics/cars/body_ai_9.png` |
| `cars/body_junker` | Wheel-free junker body (championship rewards); same contract as the other bodies. One image for every displaced rival (each gets a slight tint). | 128 x 72 | 64 x 36 | 1 | top-down, nose pointing right (+X), car centred | transparent background | primary | `assets/graphics/cars/template_body_junker.png` | `custom/graphics/cars/body_junker.png` |
| `cars/body_player` | Wheel-free body (P2): same size, orientation and pivot as the car image, transparent where the wheels go; the game adds four shared wheels (also in every static picture of the car). Takes precedence over the flattened car image. | 128 x 72 | 64 x 36 | 1 | top-down, nose pointing right (+X), car centred | transparent background | primary | `assets/graphics/cars/template_body_player.png` | `custom/graphics/cars/body_player.png` |
| `cars/body_player_2` | Wheel-free body (P2): same size, orientation and pivot as the car image, transparent where the wheels go; the game adds four shared wheels (also in every static picture of the car). Takes precedence over the flattened car image. | 128 x 72 | 64 x 36 | 1 | top-down, nose pointing right (+X), car centred | transparent background | primary | `assets/graphics/cars/template_body_player_2.png` | `custom/graphics/cars/body_player_2.png` |

## Vehicles - legacy flattened cars

Older format with wheels painted in, kept only so your older drawings keep working (used when no body drawing exists). There is no packaged picture for these names. Do not draw them for new art.

| Name | What it is / where it appears | Template (px) | Shown at (world px) | Frames | Orientation | Background | Status | Packaged template | Your replacement |
|---|---|---|---|---|---|---|---|---|---|
| `cars/car_ai_1` | Opponent car 1; same contract as the player car. LEGACY flattened car (wheels painted in): your own older drawing only, used when no body drawing exists; there is no packaged template. Prefer body_*. | 128 x 72 | 64 x 36 | 1 | top-down, nose pointing right (+X), car centred | transparent background | legacy | `(none)` | `custom/graphics/cars/car_ai_1.png` |
| `cars/car_ai_2` | Opponent car 2; same contract as the player car. LEGACY flattened car (wheels painted in): your own older drawing only, used when no body drawing exists; there is no packaged template. Prefer body_*. | 128 x 72 | 64 x 36 | 1 | top-down, nose pointing right (+X), car centred | transparent background | legacy | `(none)` | `custom/graphics/cars/car_ai_2.png` |
| `cars/car_ai_3` | Opponent car 3; same contract as the player car. LEGACY flattened car (wheels painted in): your own older drawing only, used when no body drawing exists; there is no packaged template. Prefer body_*. | 128 x 72 | 64 x 36 | 1 | top-down, nose pointing right (+X), car centred | transparent background | legacy | `(none)` | `custom/graphics/cars/car_ai_3.png` |
| `cars/car_ai_4` | Opponent car 4; same contract as the player car. LEGACY flattened car (wheels painted in): your own older drawing only, used when no body drawing exists; there is no packaged template. Prefer body_*. | 128 x 72 | 64 x 36 | 1 | top-down, nose pointing right (+X), car centred | transparent background | legacy | `(none)` | `custom/graphics/cars/car_ai_4.png` |
| `cars/car_ai_5` | Opponent car 5; same contract as the player car. LEGACY flattened car (wheels painted in): your own older drawing only, used when no body drawing exists; there is no packaged template. Prefer body_*. | 128 x 72 | 64 x 36 | 1 | top-down, nose pointing right (+X), car centred | transparent background | legacy | `(none)` | `custom/graphics/cars/car_ai_5.png` |
| `cars/car_ai_6` | Opponent car 6; same contract as the player car. LEGACY flattened car (wheels painted in): your own older drawing only, used when no body drawing exists; there is no packaged template. Prefer body_*. | 128 x 72 | 64 x 36 | 1 | top-down, nose pointing right (+X), car centred | transparent background | legacy | `(none)` | `custom/graphics/cars/car_ai_6.png` |
| `cars/car_ai_7` | Opponent car 7; same contract as the player car. LEGACY flattened car (wheels painted in): your own older drawing only, used when no body drawing exists; there is no packaged template. Prefer body_*. | 128 x 72 | 64 x 36 | 1 | top-down, nose pointing right (+X), car centred | transparent background | legacy | `(none)` | `custom/graphics/cars/car_ai_7.png` |
| `cars/car_ai_8` | Opponent car 8; same contract as the player car. LEGACY flattened car (wheels painted in): your own older drawing only, used when no body drawing exists; there is no packaged template. Prefer body_*. | 128 x 72 | 64 x 36 | 1 | top-down, nose pointing right (+X), car centred | transparent background | legacy | `(none)` | `custom/graphics/cars/car_ai_8.png` |
| `cars/car_ai_9` | Opponent car 9; same contract as the player car. LEGACY flattened car (wheels painted in): your own older drawing only, used when no body drawing exists; there is no packaged template. Prefer body_*. | 128 x 72 | 64 x 36 | 1 | top-down, nose pointing right (+X), car centred | transparent background | legacy | `(none)` | `custom/graphics/cars/car_ai_9.png` |
| `cars/car_junker` | Championship: the battered junker a rival drives after the player has won their car; same contract as the player car. LEGACY flattened car (wheels painted in): your own older drawing only, used when no body drawing exists; there is no packaged template. Prefer body_*. | 128 x 72 | 64 x 36 | 1 | top-down, nose pointing right (+X), car centred | transparent background | legacy | `(none)` | `custom/graphics/cars/car_junker.png` |
| `cars/car_player` | Top-down, nose pointing right (+X), centred pivot, transparent background. LEGACY flattened car (wheels painted in): your own older drawing only, used when no body drawing exists; there is no packaged template. Prefer body_*. | 128 x 72 | 64 x 36 | 1 | top-down, nose pointing right (+X), car centred | transparent background | legacy | `(none)` | `custom/graphics/cars/car_player.png` |
| `cars/car_player_2` | Player 2 car (two-player races); same contract as the player car. LEGACY flattened car (wheels painted in): your own older drawing only, used when no body drawing exists; there is no packaged template. Prefer body_*. | 128 x 72 | 64 x 36 | 1 | top-down, nose pointing right (+X), car centred | transparent background | legacy | `(none)` | `custom/graphics/cars/car_player_2.png` |

## Weapons and effects

Projectiles, mines, explosions, smoke, dust, sparks, confetti, tyre marks. Reference sheet: [sheet_weapons.png](artwork/sheet_weapons.png)

| Name | What it is / where it appears | Template (px) | Shown at (world px) | Frames | Orientation | Background | Status | Packaged template | Your replacement |
|---|---|---|---|---|---|---|---|---|---|
| `decals/tire_mark` | Pair of rear-tyre marks along +X (stamped repeatedly while sliding); seamless left-right. | 32 x 12 | 10 x 26 | 1 | mark runs top to bottom (along the car) | transparent background | primary | `assets/graphics/decals/template_tire_mark.png` | `custom/graphics/decals/tire_mark.png` |
| `fx/blast` | Explosion burst, centred, transparent; scaled up and faded out. | 96 x 96 | 110 x 110 | 1 | top-down / as seen on screen | transparent background | primary | `assets/graphics/fx/template_blast.png` | `custom/graphics/fx/blast.png` |
| `fx/car_wear` | Damage wear (2026-11-23): scratches, dents and soot on a transparent background, top-down, nose right (+X), the same frame as a car body. One image for every car: the game blends it into each car's body (only where the body is painted) more strongly as the car's condition drops. No per-car damage drawings. | 128 x 72 | 64 x 36 | 1 | top-down / as seen on screen | transparent background | primary | `assets/graphics/fx/template_car_wear.png` | `custom/graphics/fx/car_wear.png` |
| `fx/confetti` | White confetti piece; tinted at runtime, so keep it white/light. | 12 x 12 | 12 x 12 | 1 | top-down / as seen on screen | transparent background | primary | `assets/graphics/fx/template_confetti.png` | `custom/graphics/fx/confetti.png` |
| `fx/dust` | Dust particle, soft, transparent. | 32 x 32 | 32 x 32 | 1 | top-down / as seen on screen | transparent background | primary | `assets/graphics/fx/template_dust.png` | `custom/graphics/fx/dust.png` |
| `fx/smoke` | Tyre-smoke particle, soft, transparent. | 32 x 32 | 32 x 32 | 1 | top-down / as seen on screen | transparent background | primary | `assets/graphics/fx/template_smoke.png` | `custom/graphics/fx/smoke.png` |
| `fx/spark` | Impact spark particle. | 24 x 24 | 24 x 24 | 1 | top-down / as seen on screen | transparent background | primary | `assets/graphics/fx/template_spark.png` | `custom/graphics/fx/spark.png` |
| `weapons/homing_missile` | Homing missile, nose pointing right (+X), centred; also the HUD / garage icon. | 40 x 16 | 30 x 12 | 1 | top-down, nose pointing right (+X) | transparent background | primary | `assets/graphics/weapons/template_homing_missile.png` | `custom/graphics/weapons/homing_missile.png` |
| `weapons/mine` | Mine: horizontal strip of 2 frames (32x32 each: lamp off / lamp on), blinks while armed; also the HUD mine icon. | 64 x 32 | 26 x 26 | 2 | top-down / as seen on screen | transparent background | primary | `assets/graphics/weapons/template_mine.png` | `custom/graphics/weapons/mine.png` |
| `weapons/missile` | Missile, nose pointing right (+X), centred; also the HUD missile icon. Homing/super missiles are tinted. | 40 x 16 | 30 x 12 | 1 | top-down, nose pointing right (+X) | transparent background | primary | `assets/graphics/weapons/template_missile.png` | `custom/graphics/weapons/missile.png` |
| `weapons/super_missile` | Super missile (orbits its car), nose pointing right (+X), centred; also the HUD / garage icon. | 40 x 20 | 34 x 17 | 1 | top-down, nose pointing right (+X) | transparent background | primary | `assets/graphics/weapons/template_super_missile.png` | `custom/graphics/weapons/super_missile.png` |

## Track and shared scenery (Green Valley and every circuit)

Road, grass, barriers, start line, pit sign, decals, trees, lamps, grandstands. Reference sheet: [sheet_track.png](artwork/sheet_track.png)

| Name | What it is / where it appears | Template (px) | Shown at (world px) | Frames | Orientation | Background | Status | Packaged template | Your replacement |
|---|---|---|---|---|---|---|---|---|---|
| `decals/grid_box` | Painted grid-slot bracket; open side faces the driving direction (+X). | 72 x 48 | 72 x 48 | 1 | top-down / as seen on screen | transparent background | primary; your drawing in use (`assets/graphics/decals/grid_box.png`) | `assets/graphics/decals/template_grid_box.png` | `custom/graphics/decals/grid_box.png` |
| `decals/road_wear` | Semi-transparent road wear decal, long axis along the driving direction. | 160 x 64 | 240 x 96 | 1 | top-down / as seen on screen | transparent background | primary | `assets/graphics/decals/template_road_wear.png` | `custom/graphics/decals/road_wear.png` |
| `scenery/bush` | Top-down bush, centred, transparent. | 72 x 72 | 72 x 72 | 1 | top-down / as seen on screen | transparent background | primary | `assets/graphics/scenery/template_bush.png` | `custom/graphics/scenery/bush.png` |
| `scenery/flag` | Marshal flag: horizontal strip of 2 frames (48x64 each), pole foot at bottom-left third. | 96 x 64 | 48 x 64 | 2 | top-down / as seen on screen | transparent background | primary | `assets/graphics/scenery/template_flag.png` | `custom/graphics/scenery/flag.png` |
| `scenery/flowers` | Flower patch, centred, transparent. | 64 x 64 | 64 x 64 | 1 | top-down / as seen on screen | transparent background | primary | `assets/graphics/scenery/template_flowers.png` | `custom/graphics/scenery/flowers.png` |
| `scenery/grandstand` | Top-down grandstand; the crowd side (bottom edge) faces the track. | 192 x 80 | 288 x 120 | 1 | top-down / as seen on screen | transparent background | primary | `assets/graphics/scenery/template_grandstand.png` | `custom/graphics/scenery/grandstand.png` |
| `scenery/lamp_post` | Lighting pilot: top-down lamp post, lamp head towards the top (-Y), rotated to face the track. | 48 x 48 | 56 x 56 | 1 | top-down / as seen on screen | transparent background | primary | `assets/graphics/scenery/template_lamp_post.png` | `custom/graphics/scenery/lamp_post.png` |
| `scenery/rock` | Rock, centred, transparent. | 56 x 56 | 56 x 56 | 1 | top-down / as seen on screen | transparent background | primary | `assets/graphics/scenery/template_rock.png` | `custom/graphics/scenery/rock.png` |
| `scenery/tree_bloom` | Top-down blossom tree, centred, transparent; sways gently. | 112 x 112 | 112 x 112 | 1 | top-down / as seen on screen | transparent background | primary | `assets/graphics/scenery/template_tree_bloom.png` | `custom/graphics/scenery/tree_bloom.png` |
| `scenery/tree_round` | Top-down tree canopy, centred, transparent; sways gently. | 128 x 128 | 128 x 128 | 1 | top-down / as seen on screen | transparent background | primary | `assets/graphics/scenery/template_tree_round.png` | `custom/graphics/scenery/tree_round.png` |
| `scenery/tyre_stack` | Tyre stack, centred, transparent. | 56 x 56 | 56 x 56 | 1 | top-down / as seen on screen | transparent background | primary | `assets/graphics/scenery/template_tyre_stack.png` | `custom/graphics/scenery/tyre_stack.png` |
| `track/grass` | Seamless repeating off-track ground, opaque. | 256 x 256 | - | 1 | any (repeating tile) | opaque, seamless tile (edges must repeat) | primary | `assets/graphics/track/template_grass.png` | `custom/graphics/track/grass.png` |
| `track/pit_sign` | Pit lane entrance sign (PIT + arrow), placed beside the entrance behind the barrier; the arrow points along the driving direction (+X). | 128 x 64 | 96 x 48 | 1 | top-down / as seen on screen | transparent background | primary | `assets/graphics/track/template_pit_sign.png` | `custom/graphics/track/pit_sign.png` |
| `track/start_line` | Start/finish strip, long axis across the road; stretched to road width. | 32 x 128 | 24 x 150 | 1 | long side = across the road | transparent background | primary | `assets/graphics/track/template_start_line.png` | `custom/graphics/track/start_line.png` |
| `track/tarmac` | Seamless repeating road surface, opaque. | 256 x 256 | - | 1 | any (repeating tile) | opaque, seamless tile (edges must repeat) | primary | `assets/graphics/track/template_tarmac.png` | `custom/graphics/track/tarmac.png` |
| `track/wall` | Barrier strip, seamless left-right, repeated along the track edge; transparent background. | 128 x 32 | 80 x 20 | 1 | horizontal strip that repeats left-right | transparent background | primary | `assets/graphics/track/template_wall.png` | `custom/graphics/track/wall.png` |

## Environments

Per-environment replacements (Green Valley uses the shared set above). Reference sheet: [sheet_environments.png](artwork/sheet_environments.png)

| Name | What it is / where it appears | Template (px) | Shown at (world px) | Frames | Orientation | Background | Status | Packaged template | Your replacement |
|---|---|---|---|---|---|---|---|---|---|
| `variant_2/scenery/prop_1` | **Wasteland:** Variant 2 tall prop (sways), top-down, centred, transparent; any rotation. | 128 x 128 | 128 x 128 | 1 | top-down / as seen on screen | transparent background | primary | `assets/graphics/variant_2/scenery/template_prop_1.png` | `custom/graphics/variant_2/scenery/prop_1.png` |
| `variant_2/scenery/prop_2` | **Wasteland:** Variant 2 medium prop, top-down, centred, transparent; any rotation. | 72 x 72 | 72 x 72 | 1 | top-down / as seen on screen | transparent background | primary | `assets/graphics/variant_2/scenery/template_prop_2.png` | `custom/graphics/variant_2/scenery/prop_2.png` |
| `variant_2/scenery/prop_3` | **Wasteland:** Variant 2 small prop, top-down, centred, transparent; any rotation. | 56 x 56 | 56 x 56 | 1 | top-down / as seen on screen | transparent background | primary | `assets/graphics/variant_2/scenery/template_prop_3.png` | `custom/graphics/variant_2/scenery/prop_3.png` |
| `variant_2/track/grass` | **Wasteland:** Variant 2 ground; same contract as track/grass (seamless, opaque). | 256 x 256 | - | 1 | any (repeating tile) | opaque, seamless tile (edges must repeat) | primary | `assets/graphics/variant_2/track/template_grass.png` | `custom/graphics/variant_2/track/grass.png` |
| `variant_2/track/tarmac` | **Wasteland:** Variant 2 road surface; same contract as track/tarmac. | 256 x 256 | - | 1 | any (repeating tile) | opaque, seamless tile (edges must repeat) | primary | `assets/graphics/variant_2/track/template_tarmac.png` | `custom/graphics/variant_2/track/tarmac.png` |
| `variant_2/track/wall` | **Wasteland:** Variant 2 barrier strip; same contract as track/wall. | 128 x 32 | 80 x 20 | 1 | horizontal strip that repeats left-right | transparent background | primary | `assets/graphics/variant_2/track/template_wall.png` | `custom/graphics/variant_2/track/wall.png` |
| `variant_3/scenery/prop_1` | **Winter:** Variant 3 tall prop (sways), top-down, centred, transparent; any rotation. | 128 x 128 | 128 x 128 | 1 | top-down / as seen on screen | transparent background | primary | `assets/graphics/variant_3/scenery/template_prop_1.png` | `custom/graphics/variant_3/scenery/prop_1.png` |
| `variant_3/scenery/prop_2` | **Winter:** Variant 3 medium prop, top-down, centred, transparent; any rotation. | 72 x 72 | 72 x 72 | 1 | top-down / as seen on screen | transparent background | primary | `assets/graphics/variant_3/scenery/template_prop_2.png` | `custom/graphics/variant_3/scenery/prop_2.png` |
| `variant_3/scenery/prop_3` | **Winter:** Variant 3 small prop, top-down, centred, transparent; any rotation. | 56 x 56 | 56 x 56 | 1 | top-down / as seen on screen | transparent background | primary | `assets/graphics/variant_3/scenery/template_prop_3.png` | `custom/graphics/variant_3/scenery/prop_3.png` |
| `variant_3/track/grass` | **Winter:** Variant 3 ground; same contract as track/grass (seamless, opaque). | 256 x 256 | - | 1 | any (repeating tile) | opaque, seamless tile (edges must repeat) | primary | `assets/graphics/variant_3/track/template_grass.png` | `custom/graphics/variant_3/track/grass.png` |
| `variant_3/track/tarmac` | **Winter:** Variant 3 road surface; same contract as track/tarmac. | 256 x 256 | - | 1 | any (repeating tile) | opaque, seamless tile (edges must repeat) | primary | `assets/graphics/variant_3/track/template_tarmac.png` | `custom/graphics/variant_3/track/tarmac.png` |
| `variant_3/track/wall` | **Winter:** Variant 3 barrier strip; same contract as track/wall. | 128 x 32 | 80 x 20 | 1 | horizontal strip that repeats left-right | transparent background | primary | `assets/graphics/variant_3/track/template_wall.png` | `custom/graphics/variant_3/track/wall.png` |
| `variant_4/decals/kerb` | **The Raceway:** The Raceway kerb: red / white blocks along +X, seamless left-right; laid along the road edge on corners (visual only). | 64 x 16 | 64 x 14 | 1 | horizontal strip that repeats left-right | transparent background | primary | `assets/graphics/variant_4/decals/template_kerb.png` | `custom/graphics/variant_4/decals/kerb.png` |
| `variant_4/scenery/pit_building` | **The Raceway:** The Raceway pit building beside the main straight; garage doors along the bottom edge face the track. | 384 x 128 | 480 x 160 | 1 | top-down / as seen on screen | transparent background | primary | `assets/graphics/variant_4/scenery/template_pit_building.png` | `custom/graphics/variant_4/scenery/pit_building.png` |
| `variant_4/scenery/prop_1` | **The Raceway:** The Raceway floodlight mast, top-down (lamp bank at the top), centred, transparent; any rotation. | 128 x 128 | 128 x 128 | 1 | top-down / as seen on screen | transparent background | primary | `assets/graphics/variant_4/scenery/template_prop_1.png` | `custom/graphics/variant_4/scenery/prop_1.png` |
| `variant_4/scenery/prop_2` | **The Raceway:** The Raceway advertising board (original generic brand), text readable when the long edge faces the track; placed facing the road. | 160 x 48 | 200 x 60 | 1 | top-down / as seen on screen | transparent background | primary | `assets/graphics/variant_4/scenery/template_prop_2.png` | `custom/graphics/variant_4/scenery/prop_2.png` |
| `variant_4/scenery/prop_3` | **The Raceway:** The Raceway marshal post, top-down, centred, transparent; any rotation. | 56 x 56 | 56 x 56 | 1 | top-down / as seen on screen | transparent background | primary | `assets/graphics/variant_4/scenery/template_prop_3.png` | `custom/graphics/variant_4/scenery/prop_3.png` |
| `variant_4/track/grass` | **The Raceway:** The Raceway ground: manicured striped grass; same contract as track/grass (seamless, opaque). | 256 x 256 | - | 1 | any (repeating tile) | opaque, seamless tile (edges must repeat) | primary | `assets/graphics/variant_4/track/template_grass.png` | `custom/graphics/variant_4/track/grass.png` |
| `variant_4/track/tarmac` | **The Raceway:** The Raceway asphalt: clean dark grain; same contract as track/tarmac. | 256 x 256 | - | 1 | any (repeating tile) | opaque, seamless tile (edges must repeat) | primary | `assets/graphics/variant_4/track/template_tarmac.png` | `custom/graphics/variant_4/track/tarmac.png` |
| `variant_4/track/wall` | **The Raceway:** The Raceway barrier: red / white strip; same contract as track/wall. | 128 x 32 | 80 x 20 | 1 | horizontal strip that repeats left-right | transparent background | primary | `assets/graphics/variant_4/track/template_wall.png` | `custom/graphics/variant_4/track/wall.png` |
| `variant_5/scenery/card` | **Tabletop Mayhem:** Tabletop Mayhem giant playing card (original design), centred, transparent; any rotation. | 220 x 300 | 220 x 300 | 1 | top-down / as seen on screen | transparent background | primary | `assets/graphics/variant_5/scenery/template_card.png` | `custom/graphics/variant_5/scenery/card.png` |
| `variant_5/scenery/paperclip` | **Tabletop Mayhem:** Tabletop Mayhem giant paperclip, centred, transparent; any rotation. | 280 x 140 | 280 x 140 | 1 | top-down / as seen on screen | transparent background | primary | `assets/graphics/variant_5/scenery/template_paperclip.png` | `custom/graphics/variant_5/scenery/paperclip.png` |
| `variant_5/scenery/pencil` | **Tabletop Mayhem:** Tabletop Mayhem giant pencil, point to the left, centred, transparent; any rotation. | 560 x 88 | 560 x 88 | 1 | top-down / as seen on screen | transparent background | primary | `assets/graphics/variant_5/scenery/template_pencil.png` | `custom/graphics/variant_5/scenery/pencil.png` |
| `variant_5/scenery/prop_1` | **Tabletop Mayhem:** Tabletop Mayhem giant coffee mug, top-down, centred, transparent; any rotation. | 256 x 256 | 220 x 220 | 1 | top-down / as seen on screen | transparent background | primary | `assets/graphics/variant_5/scenery/template_prop_1.png` | `custom/graphics/variant_5/scenery/prop_1.png` |
| `variant_5/scenery/prop_2` | **Tabletop Mayhem:** Tabletop Mayhem giant die, top-down, centred, transparent; any rotation. | 128 x 128 | 110 x 110 | 1 | top-down / as seen on screen | transparent background | primary | `assets/graphics/variant_5/scenery/template_prop_2.png` | `custom/graphics/variant_5/scenery/prop_2.png` |
| `variant_5/scenery/prop_3` | **Tabletop Mayhem:** Tabletop Mayhem toy block, top-down, centred, transparent; any rotation. | 112 x 112 | 96 x 96 | 1 | top-down / as seen on screen | transparent background | primary | `assets/graphics/variant_5/scenery/template_prop_3.png` | `custom/graphics/variant_5/scenery/prop_3.png` |
| `variant_5/track/grass` | **Tabletop Mayhem:** Tabletop Mayhem ground: wooden desk; same contract as track/grass (seamless, opaque). | 256 x 256 | - | 1 | any (repeating tile) | opaque, seamless tile (edges must repeat) | primary | `assets/graphics/variant_5/track/template_grass.png` | `custom/graphics/variant_5/track/grass.png` |
| `variant_5/track/tarmac` | **Tabletop Mayhem:** Tabletop Mayhem road: toy race-track plastic; same contract as track/tarmac. | 256 x 256 | - | 1 | any (repeating tile) | opaque, seamless tile (edges must repeat) | primary | `assets/graphics/variant_5/track/template_tarmac.png` | `custom/graphics/variant_5/track/tarmac.png` |
| `variant_5/track/wall` | **Tabletop Mayhem:** Tabletop Mayhem barrier: wooden ruler strip; same contract as track/wall. | 128 x 32 | 80 x 20 | 1 | horizontal strip that repeats left-right | transparent background | primary | `assets/graphics/variant_5/track/template_wall.png` | `custom/graphics/variant_5/track/wall.png` |

## Interface

Logo, menus, HUD, garage, kill-feed and ranking icons, achievements. Reference sheet: [sheet_ui.png](artwork/sheet_ui.png)

| Name | What it is / where it appears | Template (px) | Shown at (world px) | Frames | Orientation | Background | Status | Packaged template | Your replacement |
|---|---|---|---|---|---|---|---|---|---|
| `ui/achievement_badge` | Unlocked achievement medal (toast and list); square, centred, transparent. | 64 x 64 | 48 x 48 | 1 | top-down / as seen on screen | transparent background | primary | `assets/graphics/ui/template_achievement_badge.png` | `custom/graphics/ui/achievement_badge.png` |
| `ui/achievement_locked` | Locked achievement medal; same contract as the unlocked one. | 64 x 64 | 48 x 48 | 1 | top-down / as seen on screen | transparent background | primary | `assets/graphics/ui/template_achievement_locked.png` | `custom/graphics/ui/achievement_locked.png` |
| `ui/button` | Menu button nine-patch (16 px corners); hover/pressed/focus states are tints of it. | 96 x 48 | - | 1 | top-down / as seen on screen | nine-patch: corners kept, middle stretched (24 px margins) | primary | `assets/graphics/ui/template_button.png` | `custom/graphics/ui/button.png` |
| `ui/crash` | Kill feed: a car put out of the race by collisions (no weapon); square, centred, transparent. | 48 x 48 | 20 x 20 | 1 | top-down / as seen on screen | transparent background | primary; your drawing in use (`assets/graphics/ui/crash.png`) | `assets/graphics/ui/template_crash.png` | `custom/graphics/ui/crash.png` |
| `ui/garage_backdrop` | Garage screen background, full screen (16:9), opaque; the centre is covered by the weapon cards. | 640 x 360 | 1280 x 720 | 1 | top-down / as seen on screen | opaque (full background) | primary | `assets/graphics/ui/template_garage_backdrop.png` | `custom/graphics/ui/garage_backdrop.png` |
| `ui/hud_panel` | Nine-patch panel; 24 px corners are not stretched (scaled with the texture). | 96 x 96 | - | 1 | top-down / as seen on screen | nine-patch: corners kept, middle stretched (24 px margins) | primary | `assets/graphics/ui/template_hud_panel.png` | `custom/graphics/ui/hud_panel.png` |
| `ui/logo` | Title logo; transparent background, centred. | 880 x 240 | 660 x 180 | 1 | top-down / as seen on screen | transparent background | primary | `assets/graphics/ui/template_logo.png` | `custom/graphics/ui/logo.png` |
| `ui/star_bronze` | 3rd place marker; same contract as the gold star. | 48 x 48 | 22 x 22 | 1 | top-down / as seen on screen | transparent background | primary; your drawing in use (`assets/graphics/ui/star_bronze.png`) | `assets/graphics/ui/template_star_bronze.png` | `custom/graphics/ui/star_bronze.png` |
| `ui/star_gold` | 1st place marker in the race history; square, centred, transparent background. | 48 x 48 | 22 x 22 | 1 | top-down / as seen on screen | transparent background | primary; your drawing in use (`assets/graphics/ui/star_gold.png`) | `assets/graphics/ui/template_star_gold.png` | `custom/graphics/ui/star_gold.png` |
| `ui/star_silver` | 2nd place marker; same contract as the gold star. | 48 x 48 | 22 x 22 | 1 | top-down / as seen on screen | transparent background | primary; your drawing in use (`assets/graphics/ui/star_silver.png`) | `assets/graphics/ui/template_star_silver.png` | `custom/graphics/ui/star_silver.png` |
| `ui/ticket` | Kill feed: a pit-lane collision ticket (a meaningful crash in the pit lane); square, centred, transparent. | 48 x 48 | 20 x 20 | 1 | top-down / as seen on screen | transparent background | primary | `assets/graphics/ui/template_ticket.png` | `custom/graphics/ui/ticket.png` |
| `ui/tombstone` | Kill feed and rankings: a permanent elimination (DNF) caused by a driver; square, centred, transparent. | 48 x 48 | 20 x 20 | 1 | top-down / as seen on screen | transparent background | primary; your drawing in use (`assets/graphics/ui/tombstone.png`) | `assets/graphics/ui/template_tombstone.png` | `custom/graphics/ui/tombstone.png` |

## Drawn by the game itself (no picture to replace yet)

These are deliberately drawn in code: shading, light, paint lines and effects that
follow the track geometry. Larger optional artwork opportunities are listed in
`docs/BACKLOG.md`.

| Visual | Where | Why code |
|---|---|---|
| Pit lane paint: bay frames (gold / red when occupied), PIT 1-3 numbers, limiter lines, "PIT" lettering | every pit lane | follow the lane geometry; colours show bay occupancy |
| Divider island fill (its edges use the barrier picture) | pit lanes, split sections | follows the divider shape |
| Bridge shadow and deck shading; jump ramp / ravine shading | elevated crossings, jumps | shading over the tarmac and grass pictures |
| Battle Royale yard floor tint, concrete blocks, hazard stripes, scrap-pile base | the Scrapyard arena | flat shapes; the scrap cars on the piles are the junker picture, the yard uses the environment's grass / tarmac / wall |
| Danger-zone ring | Battle Royale | animated effect |
| Night lighting: ambient tint, lamp and headlight beams, brake lights, high beams, explosion flashes | night races | light, not pictures (the lamp post itself is a picture) |
| Rain and snow | Wasteland, Winter | particles |
| Missile trails, mine pulse, damage smoke / wreck tint | races | effects (smoke puffs use the smoke picture; the damage wear itself is the replaceable `fx/car_wear` picture) |
| Player marker chevron (P1 gold, P2 blue) | above your car | UI marker |
| Rotating circuit preview diorama | GO RACING! setup screen | drawn from the real circuit geometry |
| Rotating Scrapyard diorama (walls, scrap pile, blocks, barriers, tyre posts, stands, lamps) | Battle Royale setup screen | drawn from the real arena geometry (ArenaLayout) |
| Victory trophy and podium steps | the career's ending | drawn shapes (optional future pictures: see the backlog) |
| Garage spotlight under the car, shop pulses and money pop-ups | the garage | light and motion, not pictures (the car is its CarArt picture) |
| Milestone cards, race introduction card, pause menu shade, accent rules | career and races | panels from the HUD panel / button pictures plus text |
| Panels, text, bars (standings, results, garage, Nemesis Welcome) | menus and HUD | theme with the `ui/hud_panel` / `ui/button` pictures and the Fredoka font |
