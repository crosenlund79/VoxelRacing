# Circuits

## Kestrel Ridge (the first original HyperCars circuit; default)

`src/track/layouts/kestrel_ridge.tres` — lap 13,577 px (about 34 s for the rivals), ten
cars, raced on any theme (Green Valley, Heather Moor, Snow Pass). Anticlockwise, from the
start/finish line on the main straight:

1. **The main straight**: 3,500 px flat out, the main overtaking place. It runs under
   the Kestrel Leap and then under the Watchtower Bridge.
2. **Turn 1**: a long, fast left sweeper (R 330) onto the east straight.
3. **East straight and top bend**: fast, then the **Watchtower** (R 120), the first
   real braking point, a tight left that drops into the infield.
4. **Watchtower Bridge**: the road dives south and crosses **over** the main straight
   (an elevated deck with railings and a shadow; cars below and above never touch).
5. **The Horseshoe**: the hairpin (two R 95 right-handers) below the main straight,
   the slowest point of the lap (about 300 px/s for the rivals).
6. **The Kestrel Leap**: out of the Horseshoe, the road climbs a ramp and **jumps
   across the main straight**: a 260 px gap over the traffic racing below. The car
   lands on the elevated road beyond and comes down to the infield.
7. **The Ridge esses**: a tighter left after the landing (R 130), then the **narrow
   section**: 112 px instead of 150 between the barriers, 1,150 px of flowing esses
   where two cars just fit side by side. Passing there is risky, so it rewards a good
   exit from the landing and lining up for the straights that follow.
8. **The west loop**: two quick lefts and a long west straight back onto the main
   straight.

### The jump (Kestrel Leap)

A *flyover jump*: ramp, gap and landing are on an elevated stretch
(`elevation_zones`), and the gap spans the main straight with its barriers plus a
margin. Kestrel's own jump rules (`kestrel_jump_rules.tres`): ramp slope 0.55,
gravity 600 → distance flown = v² / 545; the 260 px gap is cleared from about
376 px/s; at top speed (420) a car flies 323 px and lands 63 px past the gap. A
clean exit from the Horseshoe reaches the lip near top speed; a botched exit, a hit, a
respawn or traffic just before the lip can leave a car short: it drops into the
ravine (no collisions with the road below, drawn at ground level, 10 % damage) and
after 2 s is set back past the gap. A flying car meets nothing on the main straight
(cars, mines, missiles), only its own road's barriers and other flying cars.

### Racing observations (automated, all nine rivals)

- Every rival completes every lap in No Guns, Classic and Tactical races, taking the
  Leap every lap; no safety-net classifications, no checkpoints from the upper level,
  no progress jumps between the branches at either crossing.
- More racing than on the Classic Circuit: 26 position changes over 20 No Guns laps
  (Classic Circuit: 8).
- Varied winners: 10-race spectator sessions had 5 different winners in No Guns,
  7 with Classic weapons and 6 with Tactical weapons (Rocco wins most often armed).
- Jump failures happen legitimately (e.g. a Tactical 3-lap race: one fall after
  combat); a clean car never falls.
- The narrow esses saw no passes in the measured races: cars hold position there
  and race again on the straights; it never blocked (no stoppages or pile-ups).

### Network races (J5)

LAN and online races have the real Leap (and Raven's Leap): takeoff, flight, landing,
falls into the gap with their damage, and the set-back past the gap, all decided by
the host. See `docs/NETWORK_PLAY.md` for how the client predicts its own jumps.

### Fingerprints (fresh processes, `layout=kestrel_ridge`, damage on; x1 = x8)

| probe | fingerprint |
|---|---|
| `mode=race ticks=3600 weapons=0` | `fffaa01697656baccece2b9756cad59a` |
| `mode=race ticks=3600 weapons=1` | `b54050cb6ee23fdacb0891fb91db1bc1` |
| `mode=race ticks=3600 weapons=1 style=1` | `9c972463db3a8aef314027562ed73431` |
| `mode=spectate ticks=4800 weapons=0` | `a8d4046a31b2a44ddaf914052316ae68` |
| `mode=spectate ticks=4800 weapons=1` | `fc95a9e552c5f93c2dcf008d008589f2` |
| `mode=spectate ticks=4800 weapons=1 style=1` | `8166dda05ca676113b16c0ac77c660bb` |

## Larkspur Ring (fast and flowing)

`src/track/layouts/larkspur_ring.tres` — lap 13,225 px (about 33 s for the rivals, the
fastest circuit: ~405 px/s average). One flowing loop, no crossings, no jump.

1. **Main straight**: 3,000 px flat out from the start line.
2. **The Lighthouse** (T1, R 120): the big stop of the lap at the end of the straight,
   the main place to dive down the inside.
3. **East run**: a fast right kink (R 700) and a long left sweeper (R 420) onto the top.
4. **The Hook**: the top straight dives into the infield through two R 105 corners and
   climbs out again: the second braking point, a place to defend or switch back.
5. **West sweepers**: two wide lefts (R 420-600) and a long run back onto the straight.

Racing (10-race spectator sessions): 6 different winners in No Guns; with weapons Rocco
wins about half; 13-28 position changes in 3 laps, ~28 over 20 laps.

## Ravenhook (technical and aggressive)

`src/track/layouts/ravenhook.tres` — lap 13,469 px (about 36 s, ~377 px/s: the most
technical). Corners of 100-160 px radius, two narrowings and a flyover jump.

1. **Start straight** into **T1** (R 100, tight left) and **the climb** north.
2. **The east block**: right onto the loop top (R 130), down the **narrowed east side**
   (116 px wide) and a hard right (R 110) onto...
3. **The Leap straight**, 3,000 px west: halfway along it **jumps over the climb**
   (Raven's Leap: a flyover jump, 270 px gap over the road below, the same jump rules as
   Kestrel; cleared from ~384 px/s, top speed flies 323 px). The approach is long enough
   to reach top speed from the hard right; traffic or damage can still leave a car short.
4. **The hairpin finger**: right (R 100) up the west side, the two-corner hairpin at the
   top (R 115), then **the Needle**: 112 px wide straight back down, side by side only
   with care.
5. **The west loop**: two lefts (R 130, R 160) back onto the start straight.

Racing (10-race sessions): 7 different winners in No Guns, 6 with Tactical weapons,
Rocco most often with Classic weapons (6 / 10); every rival takes the Leap every lap;
14-24 position changes in 3 laps, 44 over 20 laps without weapons.

## Legacy layouts (tests and developers only)

The Classic Circuit (`circuit_01.tres`, the race scene's own layout) and the
experimental Figure Eight (`exp_figure8_01.tres`) are no longer offered on the title
screen. They stay unchanged for regression tests and can be preselected with
`--layout=classic_01` or `--layout=exp_figure8_01`. All their fingerprints are
unchanged by Kestrel Ridge.

## Pit lanes and split sections (2026-11-17)

Every circuit has a pit lane on the main straight and one split section with a solid
divider (table, rules and AI behaviour: `docs/PIT_LANES.md`). Kestrel Ridge's split is
on the west loop straight (equal lanes); Larkspur Ring's runs through a bend (tight
84 px inside or wide 112 px outside); Ravenhook's has a wide left and a narrow right
lane. Laps, positions and timing are unchanged by the lane taken (centreline
progress); checkpoint gates span every lane. The Kestrel fingerprints above predate the
branches: races on these circuits now differ (pit stops, route choice), so that table
is historical. The pinned regression probes (`test_multiplayer_regression.gd`,
`test_combat_race.gd`, `test_tactical_race.gd`) run on the legacy test circuit,
which has no branches: their spectator hashes are unchanged, and only the
race-mode hashes (a scripted human player) were re-recorded, because of the
approved steering change (verified: identical to the steering-only commit).

## Layout features (for future circuits)

`TrackLayout`: control points + corner radii; `elevation_zones` (bridges);
`jumps` (ground jumps, or flyover jumps on an elevated stretch spanning a crossing);
`jump_rules` (per-layout jump physics); `narrow_sections` (start, end, width; tapered
over 120 px, at least 96 px wide, on the ground, away from crossings and jumps);
`branches` (pit lanes and split sections: from, to, ramp, side, lane widths, divider,
service box); `display_name`. `TrackLayout.validate()` checks all of them.
