# Sound effects inventory

The working reference for audio production: what every sound effect is, whether it
is the user's ElevenLabs recording or a Claude placeholder, and how to replace it.
Current as of Audio Integration 001 (inbox `assets/audio/_inbox/20261128/`).

## How sounds are resolved

Every effect has a logical name (e.g. `vehicles/engine_loop`).
`AssetResolver.get_audio_variants()` collects its recordings from the first level
below that has any:

1. **Custom override (no rebuild).** `custom/audio/<logical>.<ext>` and/or numbered
   variations `custom/audio/<logical>_1.<ext>`, `_2`, …, up to `_12`.
   - `<ext>` is `ogg`, `wav` or `mp3`.
   - Location: the project's `custom/` folder during development; `custom/` next to
     `VoxelRacing.exe` in the exported game.
   - Read once per game start.
2. **Packaged recordings.** `res://assets/audio/<logical>_<n>.wav`. These are the
   runtime copies of the user's ElevenLabs recordings and are exported with the game.
3. **Placeholder.** The inherited HyperCars template
   (`assets/audio/<dir>/template_<name>.*`). If there is none, SoundKit's synthesised
   sound (`src/audio/sound_kit.gd`) is used instead.

**Variations:**
- One-shots pick a random variation on every play and never repeat the previous one.
  This uses the resolver's own random generator, so gameplay randomness is never
  touched.
- Loops pick one variation per player and keep it.
- Each car keeps a fixed matched engine pair, Engine Loop *n* with Engine Load *n*
  (`RaceAudio.engine_variant(racer_id)`). The same pair is used in that car's
  action-replay engine.

**Adding a new delivery:** put the WAVs in a new `assets/audio/_inbox/<date>/`
folder, then run:

```bash
python3 tools/import_inbox_audio.py assets/audio/_inbox/<date>
```

- It writes the runtime copies `assets/audio/<logical>_<n>.wav`, with a per-file
  gain toward the category's loudness target and peaks limited to −1 dBFS. The
  inbox originals are never changed.
- The `MAP` table in the script maps inbox names to logical names. It already has
  rows for Crowd Applause, Race Finish, Achievement, Fastest Lap Stinger, Shop Buy
  and Shop Sell, ready for those recordings.
- After running it, open the project once (or run `--import`) and rebuild. The code
  picks up new files automatically.

## ElevenLabs recordings in use (99 recordings, 25 sounds)

Inbox names are `<Inbox name> <n>.wav`, with n = 1–4 (1–3 for Crowd loop). Runtime
copies are `assets/audio/<logical>_<n>.wav`. Gain is the level applied to each runtime
copy.

| Category | Logical name | Inbox name | Var. | Loop | Gain (dB) | Plays |
|---|---|---|---:|---|---|---|
| Engines | `vehicles/engine_loop` | Engine Loop | 4 | yes | −1.2…+0.8 | Each car's engine, one fixed recording per car (RaceAudio, replays) |
| Engines | `vehicles/engine_load` | Engine Load | 4 | yes | −2.1…+0.2 | Load layer, paired with the car's engine loop |
| Tires | `vehicles/tire_squeal` | Tire Squeal | 4 | yes | −3.0…+0.9 | Sliding (one variation per car) |
| Collisions | `vehicles/impact_car` | Car impact | 4 | — | −0.8…0 | Car-to-car hits (race and replays) |
| Collisions | `vehicles/impact_wall` | Wall impact | 4 | — | −0.7…+0.2 | Barrier hits, jump landings (race and replays) |
| Exhausts | `vehicles/backfire` | Backfire | 4 | — | −6.9…0 | Exhaust backfire on a lift-off at speed (voxel_race_fx) |
| Exhausts | `vehicles/turbo_spit` | Turbo Spit | 4 | — | −0.3…−0.1 | **New:** anti-lag bangs, see below |
| Debris | `vehicles/debris_rattle` | Debris rattle | 4 | — | −0.1…+3.6 | Cars kicking voxel debris |
| Weapons | `weapons/missile_launch` | Missile launch | 4 | — | −0.4…+0.4 | Missile fired |
| Weapons | `weapons/homing_launch` | Homing launch | 4 | — | −0.4…+0.4 | Homing missile fired, played at ×1.12 pitch ¹ |
| Weapons | `weapons/super_launch` | Super launch | 4 | — | −0.1…+8.0 | Super missile fired |
| Weapons | `weapons/mine_drop` | Mine Drop | 4 | — | −0.6…+0.1 | Mine dropped |
| Weapons | `weapons/empty` | Empty weapon | 4 | — | −0.5…+0.6 | Fire with no ammunition |
| Explosions | `weapons/explosion` | Explosion | 4 | — | −0.3…+0.1 | Missile/mine blasts, car destroyed, jump crash, replays |
| Spectators | `crowd/crowd_loop` | Crowd loop | 3 | yes | +18.2…+20.8 | Crowd bed; volume follows excitement and distance (voxel_life) |
| Spectators | `crowd/cheer` | Crowd cheer | 4 | — | +0.8…+11.2 | Race start, overtakes, jumps, after a wreck |
| Spectators | `crowd/gasp` | Crowd Gasp | 4 | — | −3.5…+1.5 | Big crashes, wrecks, pile-ups |
| Ambience | `ambience/ambience` | Racetrack Ambiance | 4 | yes | +18.1…+19.6 | Trackside bed for the race (one variation per race) |
| Interface | `ui/ui_move` | UI Move | 4 | — | −0.4…+11.9 | Menu focus; also the weapon switch and garage repair ticks |
| Interface | `ui/ui_select` | UI select | 4 | — | +0.6…+2.8 | Menu confirm; garage; workshop "ding" |
| Interface | `ui/ui_back` | UI Back | 4 | — | −1.3…+3.2 | Menu back; garage close/refuse |
| Interface | `ui/pop` | Notification Pop | 4 | — | −0.1…+0.1 | Player overtakes, achievement badge (no longer the backfire) |
| Interface | `ui/tick` | Lap completion tick | 4 | — | −0.4…+0.4 | Player completes a lap (not a fastest lap) |
| Interface | `ui/whoosh` | Replay whosh | 4 | — | −2.5…−0.3 | Between action-replay clips |
| Race | `race/start_go` | Race start | 4 | — | −0.4…+0.4 | Race start (races, network, Battle Royale) |

¹ The four Homing launch WAVs are byte-identical copies of the four Missile launch
WAVs. They are used as delivered, with a slightly higher pitch so the two weapons
stay distinguishable (`RaceAudio.PITCH`). Separate homing recordings can replace
them at any time.

The 4 `Empty weapon * – genvej.lnk` files in the inbox are Windows shortcuts and
were ignored.

**Turbo Spit behaviour** (`src/voxel/voxel_race_fx.gd`, `TURBO_SPIT`):
- **When:** a lift-off at speed after at least 1.1 s of hard acceleration.
- **Burst:** 1–3 irregular bangs, 0.07–0.19 s apart, each with a spit of sparks.
- **Cooldown:** 3.5–5.5 s per car afterwards.
- **Chance per lift-off, by driver:** Finn 60%, Maya 45%, Nina 45%, Dante 40%,
  Greta 30%, the player 18%.
- **Everyone else** (Victor, Rocco, Ellie, Hank) only backfires. A car that spits
  does not also backfire on that lift-off.
- Uses the race FX's own random generator. Engine and driving are unchanged.

## Claude placeholders still in use (no recording yet)

| Sound | Logical name | Placeholder | Loop | Plays | Replace with |
|---|---|---|---|---|---|
| Crowd Applause | `crowd/applause` | SoundKit `applause` (synth) | — | A car finishes | `custom/audio/crowd/applause[_n].wav` or inbox "Crowd applause n" |
| Fastest Lap Stinger | `ui/stinger` | SoundKit `stinger` (synth) | — | Player's fastest lap; replay opening | `custom/audio/ui/stinger[_n].wav` or inbox "Fastest lap stinger n" |
| Race Finish | `race/finish` | HyperCars template `assets/audio/race/template_finish.ogg` | — | Player/spectator finish; replays | `custom/audio/race/finish[_n].wav` or inbox "Race finish n" |
| Achievement | `ui/achievement` | HyperCars template `assets/audio/ui/template_achievement.ogg` | — | Achievement toast; podium winner | `custom/audio/ui/achievement[_n].wav` or inbox "Achievement n" |
| Shop Buy | `ui/shop_buy` | HyperCars template `assets/audio/ui/template_shop_buy.ogg` | — | Garage purchase | `custom/audio/ui/shop_buy[_n].wav` or inbox "Shop buy n" |
| Shop Sell | `ui/shop_sell` | HyperCars template `assets/audio/ui/template_shop_sell.ogg` | — | Garage sale | `custom/audio/ui/shop_sell[_n].wav` or inbox "Shop sell n" |

**Defined but never played** (SoundKit synth; no game code plays them):
- Tool Clink (`garage/tool_clink`)
- Ratchet (`garage/ratchet`)
- Air Wrench (`garage/air_wrench`)

**How the placeholders were made:**
- **SoundKit placeholders:** synthesised at runtime by Claude during VoxelRacing (P004,
  commit `2c8093c`).
- **`template_` sounds:** inherited from HyperCars (commit `461e5c6`). They were
  synthesised there, most likely by Claude.
- **Replaced templates:** the templates of the sounds replaced above stay in
  `assets/audio/` as the third lookup level, but are no longer played.

## Mixing notes (first pass, to be tuned by ear)

- **How levels are set:**
  - Each runtime copy is set to a loudness target for its category, so all
    variations of a sound play at a similar level.
  - The existing in-game volumes, buses, distance attenuation, engine pitch, fast-
    forward silence and spectator behaviour are unchanged.
- **Targets (RMS dBFS):**
  - −14: explosion, race start
  - −15: engines, impacts, missiles
  - −19: tyre squeal, backfire, turbo spit, mine drop, crowd one-shots
  - −20 to −23: interface
  - −22: crowd bed
  - −26: ambience
  - Recordings with high peaks (explosions) are peak-limited, so they end up a few
    dB under target.
- **Compared with the old sounds:** interface sounds are about 7 dB quieter, and the
  ambience about 4 dB quieter. That is deliberate.
- To re-balance a whole sound, change its target in `tools/import_inbox_audio.py`
  and re-run the script, or adjust the playing call site's `volume_db`.

## Music and voices (not sound effects, unchanged)

All of these were supplied by the user and are listed here so the inventory is
complete:

- **Music:** 3 tracks, `assets/audio/music/template_music_{menu,race,battle}.mp3`.
  The `template_` prefix here does not mean Claude-made.
- **Voices:** 7 lines in `assets/audio/voice/*.mp3`.

Both are replaceable via `custom/audio/music/` and `custom/audio/voice/`.
