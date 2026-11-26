<p align="center"><img src="assets/branding/voxelracing_logo.png" width="560" alt="VoxelRacing"></p>

# VoxelRacing

**Miniature motorsport, block by block.** A combat racing game built from
voxels: little voxel race cars that break apart bit by bit, blow up into
chunks of their own colours and leave their debris and burn marks on the
track for the rest of the race. Underneath runs HyperCars' racing
simulation (handling, AI rivals, weapons, rules, career, music and voices).

**Download:** the GitHub Actions *Windows build* workflow uploads a portable
Windows x64 folder for every push (Actions tab, latest run, artifact).
Extract it and run `VoxelRacing.exe`.

## Prototype history

- **Prototype 001 - The Voxel Experiment** (branch `checkpoint/prototype-001`):
  HyperCars' world, cars and scenery converted to voxels.
- **Prototype 002 - A World of Voxels**: its own identity. New logo and
  Pixel Operator typography, voxel-block interface, a living voxel diorama
  as the main menu, "The Little Race" loading screen, voxel car icons,
  progressive voxel damage, voxel explosions, persistent debris that cars
  scatter, burn marks, voxel collision stars and sparks, voxel missiles and
  mines, Battle Royale in voxels, and the inherited 2D presentation removed.
  Screenshots of the running game: `docs/screenshots/p002/`.
- **Prototype 003 - Lights, Camera, Carnage** (previous state on branch
  `checkpoint/prototype-002`): automatic cinematic action replays of the
  race's best moments (missile, mine, chase, trackside, sweep, side and
  destruction cameras, slow motion), cars with weight (nose lift, dive,
  body roll, wheelspin and burnouts), heavier debris that costs grip,
  cheeky rivals lobbing soda cans at the car they just passed, darker nights
  with more lamp posts, meadow grass and flowers like the menu island,
  Championship with the garage between rounds (Garage Race retired), tabbed
  controls, voxel achievement icons and new credits.
  Screenshots: `docs/screenshots/p003/`.
- **Prototype 004 - A Living Motorsport World** (previous state on branch
  `checkpoint/prototype-003`): every circuit dressed for its theme (barns,
  windmills and cows; sheds and containers; cabins and snowmen; pit garages,
  TV towers and big screens; giant toys), animated voxel spectators who
  follow the cars and cheer their favourite drivers, marshals, butterflies
  and birds, cars with numbers, exhausts that puff and pop and a gadget per
  driver, a start-light gantry and a short cinematic over the grid, a podium
  after the race, a voxel workshop as the garage, a generated crowd and
  workshop soundscape, livelier menus, and a photography mode.
  Screenshots: `docs/screenshots/p004/`.
- **Prototype 005 - Less Is More** (previous state on branch
  `checkpoint/prototype-004`): a simpler, icon-first interface. Kenney
  Future typography, a set of voxel icons with short optional tooltips
  (on / off, delay and duration in Settings), a one-time input device
  choice so prompts show only your keyboard or gamepad keys, a compact race
  setup where the circuit and environment names are the selectors and a
  voxel miniature of the circuit is the centrepiece, an icon-only race
  preparation card, three clear racing choices (Quick Race, Championship,
  Career), one combat system (no more Classic / Tactical) with rivals who
  keep their cool for the first seconds instead of emptying their racks at
  the start line, two little display cars by the logo, and new grandstands
  in muted concrete, steel and slate. Screenshots: `docs/screenshots/p005/`.

<p align="center">
<img src="docs/screenshots/p004/05_intro_grid_dolly_drivers_and_crowd.jpg" width="49%" alt="Race intro over the grid">
<img src="docs/screenshots/p004/14_podium_celebration.jpg" width="49%" alt="Podium">
<img src="docs/screenshots/p004/18_garage_workshop_damaged_car.jpg" width="49%" alt="Garage workshop">
<img src="docs/screenshots/p004/12_replay_mine_cam.jpg" width="49%" alt="Replay mine cam">
</p>

<p align="center">
<img src="docs/screenshots/p003/11_replay_missile_cam.jpg" width="49%" alt="Replay: missile cam">
<img src="docs/screenshots/p003/16_replay_destruction_cam.jpg" width="49%" alt="Replay: destruction cam">
<img src="docs/screenshots/p003/06_night_lamp_posts.jpg" width="49%" alt="Night race with lamp posts">
<img src="docs/screenshots/p003/22_garage_between_rounds.jpg" width="49%" alt="Championship garage between rounds">
</p>

<p align="center">
<img src="docs/screenshots/p002/01_main_menu.jpg" width="49%" alt="Main menu">
<img src="docs/screenshots/p002/03_loading_race_50.jpg" width="49%" alt="The Little Race loading screen">
<img src="docs/screenshots/p002/06_night_race_lights_explosions.jpg" width="49%" alt="Night race">
<img src="docs/screenshots/p002/10_debris_and_burn_mark.jpg" width="49%" alt="Debris and burn mark">
</p>

## Keys

| Key | |
|---|---|
| **V** | Cycle the camera: MINIATURE (58 deg), HIGH (72), LOW (44), TOP-DOWN |
| **L** | Night lighting on / off (also TIME: NIGHT on the setup screen) |
| **R** / pad X | On the results: watch the race's highlights again |
| **Enter / Space** | During an action replay: next moment |
| **Esc** / pad B | During an action replay: skip the replay |
| **P** / pad L3 | Photography mode: freeze, free camera, Enter / F12 saves a picture |
| **Enter / Space** | During the race intro or the podium: skip |

All other controls are HyperCars' (CONTROLS in the menu; see below).

## How it works

- **Simulation untouched.** The race is HyperCars' 2D simulation; its 2D
  world is kept as data (physics, track geometry, placements) and culled from
  the screen. `VoxelStage` (`src/voxel/`) mirrors it in 3D every frame.
- **Camera.** Orthographic, pitched, never yawed: the ground maps to the
  screen affinely, so the remaining 2D ground decals (tyre marks, burn marks,
  the mine halo, the Battle Royale zone) are rendered into a small viewport
  and projected onto the voxel road under the cars.
- **World conversion** (`voxel_track.gd`): each circuit (and the Battle
  Royale arena) is rendered offscreen into colour and class maps, turned into
  a heightfield and greedy-meshed in time slices while the loading race runs.
  Bridges are real decks; the flyover gap is a real gap.
- **Cars** (`voxel_cars.gd`): every car drawing becomes a voxel model (body,
  glass cabin, roof roundel, wheel arches, rear wing where drawn, bumpers,
  head lamps on the nose, tail lamps on the tail). Damage, debris and
  explosions derive from each car's own voxel model (`voxel_car_damage.gd`),
  so custom cars get them for free.
- **Effects** (`voxel_fx.gd`, `voxel_race_fx.gd`): instanced voxel debris
  (bounces, settles, persists, kicked about by passing cars through a spatial
  hash), sparks, fire, smoke puffs, voxel stars; all driven by the existing
  damage, combat and collision events.
- **Interface** (`src/ui/vr_style.gd`, `hyper_theme.gd`, `vr_widgets.gd`):
  VoxelRacing palette, Kenney Future (CC0, `assets/fonts/kenney_future/`),
  compact chips and panels; voxel icons drawn in code (`vr_icons.gd`), short
  tooltips (`vr_tips.gd`), the input device choice (`device_picker.gd`).
- **Branding**: the logo is a live voxel model (`voxel_logo.gd`);
  `tools/make_branding.gd` bakes `assets/branding/` (window icon, splash).

- **Action replays** (`replay_recorder.gd`, `replay_theater.gd`): the
  recorder scores events as they happen (kills, wrecks, pile-ups, overtakes
  in corners or on the last lap, close finishes, taunts, jumps) and keeps a
  few seconds of 30 Hz voxel poses around each good one; after the race the
  theater replays the best (variety, about 50 s at most) with its own cars,
  debris and camera while the live race stays hidden and untouched.
- **Debris grip** (`src/race/debris_field.gd`): wrecks and lost bodywork
  leave debris on a coarse grid that lowers `CarModel.grip_scale` for any
  car on it and is swept along by traffic; constants at the top for tuning.

- **A living circuit** (`voxel_kit.gd`, `voxel_life.gd`, `voxel_flair.gd`):
  set dressing per theme placed only on open, level grass off the drivable
  surfaces; instanced spectators animated in a shader (`voxel_crowd.gdshader`)
  and driven by nearby cars and the recorder's events; car flair built from
  each car's own voxel grid. Presentation only.

Developer tools (run under Xvfb): `tools/smoke_flow.gd` (end-to-end smoke
test with simulated keys), `tools/capture_race.gd` (screenshots of any
circuit, biome, time, camera; `--hurt` damages a car to show damage and
explosions), `tools/fx_check.gd` (damage, explosion, debris, burn mark and
fresh-race reset counts), `tools/replay_check.gd` (a short spectated race
with a forced wreck and mine, then the highlights and the podium),
`tools/life_tour.gd` (a circuit's set dressing and crowd), `tools/intro_check.gd`
(the race intro and start lights), `tools/photo_check.gd` (photography mode), `tools/screens_tour.gd`, `tools/car_showroom.gd`,
`tools/logo_preview.gd`.

## Known limitations

- The Windows `.exe` file itself keeps Godot's icon (the window uses the
  VoxelRacing icon); stamping the exe needs rcedit on the build machine.
- 2D ground decals are not drawn on bridge decks; effects on a deck lie at
  deck height but missiles there are drawn slightly above it.
- Some inherited GUT tests still describe the HyperCars presentation and were
  not maintained for this prototype.
- Action replays: single-player races and spectating only (not couch or LAN
  races, not Battle Royale). Each moment re-creates its own debris and burn
  marks; tyre marks are the race's final ones. A point-blank missile hit has
  no flight to follow, so it is shown from the trackside. The replay camera
  can pass under a bridge deck. Only the focused car's engine is heard.
- Debris grip is a coarse grid that follows the same events as the voxel
  debris, not each visible piece (tuning constants: `debris_field.gd`).
- Camera view (V) and highlights (R / pad X) are fixed inputs, not rebindable.

---

# HyperCars (inherited README)

A top-down combat racing game in Godot 4.7, mechanically faithful to *Super Cars II* (Gremlin, 1991) with original, hand-painted HyperCars artwork. Ten cars race: you and nine recurring rivals with their own personalities, or two players with eight rivals.

## Run

- Open the folder in **Godot 4.7.x** (developed with 4.7.2-stable, GL Compatibility renderer) and press Play.
- Command line: `godot --path .`
  - `-- --seed=N` replays a whole session's rival decisions.
  - `-- --layout=<id>` preselects a circuit.

## What is in the game

**CAREER** is the heart of the game: start as an unknown racer and win the Rookie Cup,
the Pro Series and the HyperCars Grand Championship (with its seven-lap Grand Final) to
become the HyperCars Champion. You race with your own saved garage between rounds,
your progress is saved after every round, and the career ends with a victory ceremony
and the Hall of Fame. Afterwards you can replay any championship or play every other
mode. See `docs/CAREER.md`.

The main menu leads straight to the modes; each opens a compact setup with a
voxel miniature of the circuit (Left / Right cycle the circuit and the
environment; the icons cycle day / night, laps, weapons and the control mode).

| Mode | What it is |
|---|---|
| Quick Race | Choose a circuit and race at once |
| Championship | Six rounds (or three) ending in a grand final, with prize money and the garage between rounds; win a rival's car |
| Career | The long road from rookie to overall champion (championships, garage, rewards, ending) |
| Knockout | Nine laps, last place out every lap |
| Battle Royale | One arena, no respawns, last car standing |
| Spectate | The nine rivals race; follow any driver |
| Multiplayer | Couch split-screen, or LAN / online |

The game has:
- **3 circuits:** Kestrel Ridge, Larkspur Ring, Ravenhook. They include bridges, narrowings and speed-dependent jumps.
- **5 environments:** Green Valley, Wasteland, Winter, The Raceway and Tabletop Mayhem. Each has its own modest handling, identical for every car.
- **Day / night** on any combination.
- **Weapons:** on or off. One combat system: front and rear weapons each
  have their own cooldown, with a short lock after any shot.
- **Vehicle damage**, a kill feed and TOMBSTONE | K | D statistics.
- **Achievements** and rival careers.
- **The official music** and an announcer with rival taunts.

## Controls

The defaults below can be changed in **CONTROLS**: every action takes two keyboard keys and two controller inputs.

| Action | Keyboard | Controller |
|---|---|---|
| Steer left / right | arrow keys / A, D | d-pad / left stick |
| Fire (accelerate or brake, by control mode) | Space / Ctrl | A |
| Front / rear weapon | Up / Down, W / S | d-pad / stick up / down |
| Confirm (results, standings, garage) | Enter | Start |
| Back / race menu | Esc | B |

Fire never dismisses a results or standings screen. At the first launch you
choose your input device (keyboard or a gamepad; change it in Settings); the
game's prompts then show only that device's current bindings.

## Your own art and audio

Put replacement files in a `custom/` folder: in the project while developing, or next to the exported Windows / Linux game. Restart the game to apply them; no rebuild is needed. Missing or broken files fall back to the packaged `template_` assets.

- Per-asset contract: [`docs/ASSET_SPECS.md`](docs/ASSET_SPECS.md).
- Rules: [`assets/README.md`](assets/README.md).

## Saved data (`user://`)

| File | Contents |
|---|---|
| `settings.cfg` | Volumes and setup choices |
| `controls.cfg` | Your bindings |
| `garage.cfg` | Garage career |
| `car_collection.cfg` | Won cars and the Racing for Keeps stake |
| `achievements.cfg` | Achievements and rival careers |

## Tests

```bash
godot --headless --path . --import
```

```bash
godot --headless --path . --fixed-fps 60 -s addons/gut/gut_cmdln.gd
```

GUT 9.7.1 is vendored. Tests never touch your own saved files (a pre-run hook redirects them). Manual checklists are in `tests/manual/`.

## Documentation

| Topic | Where |
|---|---|
| Current rules, decisions, approvals | [`docs/PROJECT_BRIEF.md`](docs/PROJECT_BRIEF.md) |
| Development rules (Claude / Godot) | [`docs/GODOT_CLAUDE_GUIDELINES.md`](docs/GODOT_CLAUDE_GUIDELINES.md), [`docs/DESIGN_WORKFLOW.md`](docs/DESIGN_WORKFLOW.md), [`CLAUDE.md`](CLAUDE.md) |
| Race rules, environments, fingerprints | [`docs/RACE_RULES.md`](docs/RACE_RULES.md) |
| Circuits | [`docs/TRACKS.md`](docs/TRACKS.md) |
| Championship, setup screen, car rewards | [`docs/CHAMPIONSHIP.md`](docs/CHAMPIONSHIP.md) |
| Knockout, Battle Royale, statistics | [`docs/RACING_MODES.md`](docs/RACING_MODES.md) |
| Damage and repairs | [`docs/VEHICLE_DAMAGE.md`](docs/VEHICLE_DAMAGE.md) |
| Garage economy | [`docs/ECONOMY.md`](docs/ECONOMY.md) |
| Music, voice | [`docs/MUSIC.md`](docs/MUSIC.md), [`docs/VOICE.md`](docs/VOICE.md) |
| LAN / online play | [`docs/NETWORK_PLAY.md`](docs/NETWORK_PLAY.md) |
| Deferred observations | [`docs/BACKLOG.md`](docs/BACKLOG.md) |

## Status

Development happens on a working branch and is reviewed before promotion to `main`. Builds and exports are made only on explicit request.
