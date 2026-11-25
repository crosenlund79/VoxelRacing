# VoxelRacing — Prototype 001: The Voxel Experiment

HyperCars, rebuilt as a voxel miniature. The race you drive is HyperCars' own
2D simulation (handling, AI, weapons, rules, audio, menus are unchanged); what
you see is a 3D voxel diorama that mirrors it frame by frame.

**Download:** the GitHub Actions *Windows build* workflow uploads a portable
Windows x64 folder for every push (Actions tab → latest run → artifact). Extract
and run `VoxelRacing.exe`.

## Voxel keys

| Key | |
|---|---|
| **V** | Cycle the camera: MINIATURE (58°), HIGH (72°), LOW (44°), TOP-DOWN |
| **G** | Switch between the voxel world and the original 2D look (A / B) |
| **L** | Night lighting on / off (HyperCars' key; TIME: NIGHT on the setup screen) |

All other controls are HyperCars' (below).

## How it works

- **Simulation untouched.** `src/main/main.gd` gains six lines that add a
  `VoxelStage` (`src/voxel/`) to the race scene. The 2D world visuals are
  culled with canvas visibility layers; nothing in the race changes.
- **Camera.** Orthographic, pitched but never yawed: the ground plane then maps
  to the screen by an affine transform, so the 2D camera gets the matching
  zoom `(k, k·sin pitch)` and every remaining 2D effect (smoke, sparks,
  missiles, mines, explosions, markers, weather) stays aligned with the 3D world.
- **Track conversion** (`voxel_track.gd`). The circuit's own 2D nodes are
  rendered offscreen at voxel resolution (4 px cells) twice: once in their real
  artwork (colour) and once in flat colours (what each cell is). That gives a
  heightfield — barriers 3 voxels tall, kerbs 1, dividers 2, the flyover
  ravine sunk, terraced hills and flower voxels on the grass — which is
  greedy-meshed in chunks. Every biome and layout converts automatically.
  Bridges are real decks with railings, embankments and pillars; the flyover
  jump's gap is a real gap.
- **Cars** (`voxel_cars.gd`). Each car drawing becomes a 2 px voxel model:
  rounded body, glass cabin with the number roundel on the roof, wheel arches,
  lamp voxels at HyperCars' lamp anchors. Voxel wheels steer and roll; the body
  rolls and pitches with the car's acceleration.
- **Scenery** (`voxel_props.gd`). Trees, bushes, rocks, flowers, tyre stacks,
  flags, grandstands, boards, lamp posts and the Tabletop props are extruded
  from their artwork with a shape per kind, at HyperCars' own placements.
- **Tyre marks** render each frame into a small viewport that the terrain
  shader samples per voxel, so they lie on the road under the cars.
- **Light.** Forward+ (Vulkan → D3D12 → OpenGL fallback): sun shadows, SSAO,
  glow, a subtle tilt-shift; at night real headlights (high beam), tail and
  brake lights and lit lamp posts.
- The voxel mesher and model shader are adapted from SirensWentQuiet
  (`src/voxel/voxel_mesher.gd`, `voxel_grid.gd`).

Developer tools: `tools/capture_race.gd` (screenshots of a race, any layout,
biome, time, camera), `tools/car_showroom.gd` (all cars as voxel models),
`tools/smoke_flow.gd` (scripted end-to-end smoke test with simulated keys).

## Known limitations

- Battle Royale (its own arena scene) and the title / garage backdrops are
  still the original 2D.
- Building the voxel world takes a few seconds when a race loads; the original
  2D view shows meanwhile ("BUILDING THE VOXEL WORLD...").
- 2D effects on a bridge deck (smoke, missiles) are drawn at ground level;
  tyre marks on bridge decks are not shown.
- The inherited GUT suite was not re-run for this experiment.

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

**GO RACING!** opens a shared setup screen with a rotating circuit preview. The modes are:

| Mode | What it is |
|---|---|
| Quick Race | Standard weapons, any circuit / environment / time / length |
| Garage Race | Prize money, your own weapons, repairs and armour; the career is saved |
| Championship | Six rounds (or three) ending in a grand final; win a rival's car |
| Knockout | Nine laps, last place out every lap |
| Battle Royale | One arena, no respawns, last car standing |
| Spectate | The nine rivals race; follow any driver |
| Multiplayer | Couch split-screen, or LAN / online |

The game has:
- **3 circuits:** Kestrel Ridge, Larkspur Ring, Ravenhook. They include bridges, narrowings and speed-dependent jumps.
- **5 environments:** Green Valley, Wasteland, Winter, The Raceway and Tabletop Mayhem. Each has its own modest handling, identical for every car.
- **Day / night** on any combination.
- **Weapons:** Classic or Tactical combat style, or No Guns.
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

Fire never dismisses a results or standings screen. The game's hints always show your current bindings.

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
