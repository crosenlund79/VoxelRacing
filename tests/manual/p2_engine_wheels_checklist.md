# P2 manual checklist — engine sound and animated wheels

Claude cannot listen to audio; the engine was verified technically (pitch range,
smoothing, layer levels, voice limit, offline spectral comparison). These
listening and viewing checks need a person. Tunables: `src/audio/default_engine_sound.tres`
(`EngineSoundParams`).

## Engine sound (headphones and speakers; Engine volume at the default 70 %)

- [ ] Long race: 20 laps (ideally 50) on one track, Weapons ON. The engine never becomes a high, buzzing drone; it stays comfortable to listen to.
- [ ] Your engine is clearly audible over music and ambience, but missiles, explosions and impacts still cut through. If too quiet / loud: `volume_top_db` / `volume_idle_db`.
- [ ] Launch from the grid: a deeper engine rising with speed, the load layer (a rougher "working" sound) clearly present while accelerating.
- [ ] Holding top speed down a straight: steady and calm, not lifeless (load layer quiet: `cruise_load`).
- [ ] Braking into a corner: the pitch dips and the effort sound drops; accelerating out it comes back smoothly (no clicks, jumps or warbles).
- [ ] Fire to Brake mode behaves the same way.
- [ ] Rivals: you hear a few nearby cars passing; a full pack does not turn into a chorus of beating tones (`max_rival_voices`).
- [ ] Split-screen: both players' engines audible; spectating: rivals near the camera audible.
- [ ] LAN / online client: your engine responds the same as on the host.
- [ ] Settings: Engine volume slider and mute still work; Master mute silences it.
- [ ] Custom audio: a `custom/audio/vehicles/engine_loop.ogg` (or `.wav`) replaces the foundation, `engine_load` the load layer, after a restart.
- [ ] Laptop speakers: the engine is still recognisable (its body is around 100-400 Hz, not only sub-bass).

Offline renders for a first impression (an approximation, not the game's output):
`engine_mix_old_40s.wav` and `engine_mix_new_40s.wav` (same scale) from the P2 report.

## Animated wheels (normal game scale, also on a TV / large monitor)

- [ ] All ten cars show four wheels that look attached to the body at every angle, including while spinning after a hit; no doubled or floating wheels.
- [ ] Hold left / right: both front wheels turn visibly but restrained (about 10°) and ease back when you release.
- [ ] Fast corners: the rear wheels shift a hair to the outside, barely noticeable; nothing wobbles on straights or at standstill.
- [ ] Rivals' front wheels move with their steering; wrecked cars' wheels darken with the body; respawning cars blink as before.
- [ ] Split-screen and a LAN / online client: wheels animate on every car (the client's own car included).
- [ ] Your own art: a `custom/graphics/cars/body_player.png` (no wheels) gets the shared wheels; an older `custom/graphics/cars/car_player.png` with painted wheels alone is shown as before, without extra wheels; `custom/graphics/cars/wheel.png` replaces the wheel on every car (restart after changes).
