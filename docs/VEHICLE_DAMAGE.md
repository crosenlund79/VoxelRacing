# Vehicle damage, repairs and armour (M6)

Every car has a **condition** from 100 % to 0 %. It wears down during a race and never
changes how the car drives (the approved M1 handling is untouched). At 0 % the car is
**out of the race (DNF)**.

## What causes damage (`src/damage/default_damage_rules.tres`, all provisional)

| Source | Damage | Notes |
|---|---|---|
| Front / rear / homing missile destroys the car | 12 | on top of the unchanged explosion, wreck (3 s) and respawn |
| Super missile | 16 | |
| Mine | 14 | |
| Barrier impact | (speed into the barrier − 110) × 0.05, max 12 per impact | scrapes below 110 px/s are free |
| Car contact (both cars) | (closing speed − 120) × 0.02, max 8 each | once per pair per tick; nudges are free |
| Falling into a jump gap (J3, figure-eight) | 10 | |

One weapon hit never retires a healthy car (7–9 hits do). Measured AI spectator races:
without weapons the worst car loses about 10 % over 20 laps; armed Classic 3-lap races
leave cars between 12 % and 66 % with no DNF; Tactical 3-lap races (the rivals carry
homing / super missiles) about 2 DNFs; 20-lap armed races 2–3 DNFs of nine. Critical (≤ 25 %): the HUD bar pulses red, the car
trails smoke.

**DNF:** the car stops and smokes as a darkened wreck that no longer collides or takes
part in combat, and leaves the road after 3 s. It ranks behind every running car and is
classified after the finishers once the race is over (results say DNF, no time). A
human out of the race sees "OUT - DNF!" and the race ends for them exactly as when they
finish; the others race on. The next race's reversed grid treats DNFs like any other
result (the last classified starts in front).

**Everyone, the same rules:** rivals take the same damage and can retire. AI driving,
personalities and weapon decisions are unchanged (the AI does not consider damage).

## Garage races

In garage races the car's condition carries from race to race and is saved with the
garage career. Repairs, the free emergency patch-up and armour are bought in the
garage; prices and rules are in [`ECONOMY.md`](ECONOMY.md), the single authoritative
description. Armour reduces every kind of damage, but never makes a car invulnerable.

A DNF pays no prize, though unused rounds are kept. Leaving a garage race before the
flag changes nothing: no rounds used, no damage, no patch-up.

Quick races, spectating, couch and network races always start with fully repaired,
unarmoured cars.

## Multiplayer

The host decides all damage, condition, wrecks and DNFs; snapshots carry each car's
condition and each racer's DNF (network protocol 3), and the final result (with DNFs
classified last) is sent reliably as before. A client never counts damage itself, not
even for its own predicted car. Couch races: each view shows its own car's condition;
one player out does not end the race while the other still races.

## Fingerprints

With damage switched off (`sim_probe.gd damage=0`), all eight pre-M6 fingerprints are
identical: driving, AI and combat are untouched. With damage on, the probe also hashes
every car's condition and DNF, so the recorded values are new (see
`tests/integration/test_multiplayer_regression.gd`).

| probe (Classic Circuit) | pre-M6 = M6 with `damage=0` | M6 (damage on) | what changed |
|---|---|---|---|
| `mode=race ticks=3600 weapons=0` | `17d204f8…` | `8663575678f05c185b0e7572cf5fce1e` | the scripted probe driver hits the barrier 17 times and retires |
| `mode=race ticks=3600 weapons=1` | `ebc88be5…` | `dd1529fd620a12f80c05d73833e9c0ce` | DNFs change the race |
| `mode=race ticks=3600 weapons=1 style=1` | `9bdc6a5d…` | `4f16242a5a774e12857f22320c4becbe` | DNFs change the race |
| `mode=spectate ticks=4800 weapons=0` | `6e440848…` | `bc46e870ecc22a04a1ed6eefd555311d` | car positions identical; only condition added |
| `mode=spectate ticks=4800 weapons=1` | `cf11fd3d…` | `b2054bce9ce15b9d2cee135243950e90` | DNFs change the race |
| `mode=spectate ticks=4800 weapons=1 style=1` (x1 = x8) | `7cc525dd…` | `48f2373d383d7a1844afccf6ffd580ef` | DNFs change the result, so the next reversed grid |
| `mode=race ticks=3600 weapons=1 style=1 theme=3` | `9bdc6a5d…` | `4f16242a…` (= theme 1) | |

Figure-eight (`layout=exp_figure8_01`) with `damage=0` matches the J3 values
(`dfd0738a…`, `91576306…`, `294c78fb…`).
