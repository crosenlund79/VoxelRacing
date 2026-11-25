# Track layouts

The title screen's **LAYOUT** button chooses the circuit: **Classic Circuit** (default)
or **Figure Eight (Experimental)**. It is independent of the **TRACK** button, which
chooses the visual theme (Green Valley / Heather Moor / Snow Pass), and applies to quick,
garage and spectator races and to couch two-player races. The choice is **not saved**:
every launch starts on the Classic Circuit. The grid panel names the theme and layout
("GET READY - GREEN VALLEY - FIGURE EIGHT (EXPERIMENTAL)").

LAN / online: the host's layout (and theme) is sent to the client when it joins, so both
always race the same circuit.

Developer shortcut: `godot --path . -- --layout=exp_figure8_01` preselects a layout on
the title screen (and is used by race scenes started without the title: tests, probes,
the editor).

| Id | File | What it tests |
|---|---|---|
| `exp_figure8_01` | `src/track/layouts/exp_figure8_01.tres` | Figure-eight with one elevated crossing (bridge on the first diagonal, s = 1440–2240 px). |

Layouts are `TrackLayout` resources; `elevation_zones` (arc-length intervals along the
centreline) mark elevated road. `TrackLayout.validate()` checks crossings, zone ends,
the grid and checkpoint placement. Layout ids are neutral and independent of the
visual theme variants.

## Road levels (J1)

On an elevated layout each car has a road level (0 ground, 1 bridge) from its
progress along its own branch; it changes only at the ends of an elevation zone,
which validation keeps clear of the other road. Ground cars use collision layer 2
and the ground barriers (layer 1); bridge cars use layer 8 and the bridge barriers
(layer 4) — so the two levels never touch, while cars on the same level collide as
everywhere else. Checkpoint gates are never on the bridge. A network client's own
(predicted) car uses the barriers of the level shown by the host's snapshots.

Weapons (J4) respect the road levels: a missile, mine blast or super missile only
touches cars on its own level (anything within 80 px of a bridge end belongs to both
levels, like the cars there). Front / rear / homing missiles start on the shooter's branch
and level and follow the road they fly along (projected near their previous point, never
onto the other road at the crossing), so a missile leaving the bridge comes down where the
bridge ends; a super missile orbits on its owner's level; a mine keeps the level where it
was dropped; homing missiles only lock onto cars on their level. Nothing changes on flat
circuits (the rules only run when the layout has elevation zones). AI weapon decisions are
unchanged, so a rival may still fire at a car on the other level — the shot passes over /
under it.

Bridge ends (fix after J2): within 80 px (along the road) of either end of the bridge a car
belongs to **both** levels — it collides with cars and barriers of either — so two cars on
the same road can never pass through each other while one has switched level and the other
has not (they used to, unseen, with the rear car drawn under the deck). The band is
validated to stay clear of the other road and of every checkpoint gate. Cars in the band are
also drawn on the bridge level, so a car straddling the deck's edge is drawn whole.

Prototype fingerprints (fresh processes, `tests/support/sim_probe.gd`, layout
`exp_figure8_01`; changed by the bridge-end fix, since cars there now collide):
`mode=spectate ticks=4800 weapons=0` → `3f773ed8d02565f09e008bdbf4b33746`,
`mode=race ticks=3600 weapons=0` → `53352071e3c5478b43b4cd03d62d793d`
(J1/J2 values: `7fb45fa0…`, `a1d5d5c9…`).

## Bridge visuals (J2)

The elevated stretch is its own road surface ("BridgeDeck", the theme's tarmac) with
railings from the theme's barrier strip, above a soft procedural shadow that tapers
to nothing where the bridge meets the ground (`Track.bridge_height`). No new artwork;
custom tarmac / barrier overrides apply to the bridge too. Draw order (z):

| | ground level | bridge level |
|---|---|---|
| cars + wheels | 0 | 6 |
| mines + halos | 1 | 7 |
| missile trails | 2 | 8 |
| missiles | 3 | 9 |
| bridge shadow | 4 | |
| deck, railings, deck tyre marks | 5 | |
| your car marker | 10 (always on top) | |

Smoke, dust and sparks follow their car's level; tyre marks made on the bridge go on a
deck-level layer; a mine or missile keeps the level of the car that launched it. With
lighting on, each car's lights only light its own level. Scenery and lamp posts stay
off both roads.

Known limitations: the bridge's height is suggested by the shadow only (no ramp art,
no scaling of cars); a network client takes levels from the host's snapshots, so a car
reaching a bridge end can draw on the wrong side of the deck for a moment; weapons are
drawn by level and, since J4, only hit their own level.

Armed prototype fingerprints (J4; fresh processes, layout `exp_figure8_01`; No Guns
values above are unchanged by J4):

| probe | before J4 | after J4 |
|---|---|---|
| `mode=race ticks=3600 weapons=1` | `7afec9e8…` | `7afec9e8568d374b277acccaf5ca0ef2` (same) |
| `mode=race ticks=3600 weapons=1 style=1` | `1f2c4b11…` | `7d32d98bcddceb9b5d5dda2a7ab5a651` |
| `mode=spectate ticks=4800 weapons=1` | `0dc4bff4…` | `312d8159b1ddfc4b91ca2b97f6fb62a6` |
| `mode=spectate ticks=4800 weapons=1 style=1` | `47f19227…` | `47f1922765508a44dfd40932f3928a4d` (same) |

Changed where a weapon met a car on the other level (no hit any more) or a missile at the
crossing is now checked against its own road for leaving it.

## Jump (J3, experimental)

The figure-eight has one jump on the lower diagonal straight, after the crossing:
`TrackLayout.jumps = [Vector3(lip, ramp, gap)] = (6050, 90, 130)` px of arc distance
(ramp 5960–6050, gap 6050–6180). Optional data: layouts without `jumps` (the Classic
Circuit) are unchanged. `validate_jumps()` keeps a jump on one straight with 200 px of
runway either side, on the ground, clear of bridge ends, crossings, the grid and every
checkpoint gate (gates move off the jump).

**Flight model** (`src/race/jump_world.gd`, numbers in `src/race/default_jump_rules.tres`,
all provisional): a car whose centre crosses the lip forwards takes off with an upward
speed `vz = ramp_slope × v` (v = its speed along the road; slope 0.5). In the air it keeps
the velocity it had — steering, throttle, braking and grip do nothing (the ground driving
model is not stepped) — and its height follows `h = vz·t − ½·g·t²` (g = 900). It touches
down after `2·vz / g` seconds, so the distance flown is `2 · slope · v² / g`:

| speed at the lip (px/s) | flown (px) | result over the 130 px gap |
|---|---|---|
| 420 (top speed) | 196 | lands |
| 360 | 144 | lands |
| 342 | 130 | the clearing speed |
| 300 | 100 | falls into the gap |

Touching down before the far edge of the gap — or rolling into it on the ground — is a
**failed jump**: the car stops in the gap for `recovery_time` (2 s), then is set back on
the road 40 px past the gap, facing along it, and drives on. Its race progress carries on
(not reset), checkpoints and laps are unaffected (no gate near the jump). Nothing else
decides success: no hidden speed threshold besides the flight itself.

**Collisions and combat:** a flying car uses its own collision layer (16) and meets only
the barriers and other flying cars, so it passes over cars on the road; the ground layers
are restored at the landing tick. Ground missiles and mine blasts never touch a flying car
(and a flying car's mine or missile is a ground weapon); a super missile fired in the air
orbits in the air with its owner. Bridge-level combat (J4) is unchanged.

**AI:** unchanged (no personality or racing-line changes). All nine rivals reach the lip
near top speed and clear the gap every lap; a rival that arrives too slow (after a hit, a
spin, a wreck) falls like anyone else.

**Presentation** (`src/presentation/jump_view.gd`, procedural, existing textures and
sounds): approach chevrons, a lighter ramp with a bright lip, an earthy gap with a dark
core, landing stripes; a flying car grows with its height (up to ~1.3×) and casts a
separate shadow that moves away from it, and draws above ground cars; landing kicks up
dust with a thud; a failed jump sinks and darkens the car in the gap with smoke, sparks
and a crash. Wheels and custom car overrides scale with the body.

**Network races:** since J5 the jump works in LAN / online races too (host-authoritative;
see `docs/NETWORK_PLAY.md`).

Fingerprints: the eight original probes (Classic Circuit) are identical. Figure-eight
probes change, since every car now flies over the gap (fresh processes, same twice):

| probe (`layout=exp_figure8_01`) | before J3 | after J3 |
|---|---|---|
| `mode=spectate ticks=4800 weapons=0` | `3f773ed8…` | `dfd0738aa449fcf7b541d36d50cfae48` |
| `mode=race ticks=3600 weapons=0` | `53352071…` | `a6814824582681214c0693924c72fbc5` |
| `mode=race ticks=3600 weapons=1` | `7afec9e8…` | `9157630680ed00e4c452ba6c88db8f6d` |
| `mode=race ticks=3600 weapons=1 style=1` | `7d32d98b…` | `a8b7aec2d4331b253c171255beafe2ac` |
| `mode=spectate ticks=4800 weapons=1` | `312d8159…` | `c908c564c9eb85dafff706d078f820ab` |
| `mode=spectate ticks=4800 weapons=1 style=1` | `47f19227…` | `294c78fbdcfde848a0707b0f190ae854` |

Tests: `tests/unit/test_jumps.gd`, `tests/integration/test_jump_race.gd`.
