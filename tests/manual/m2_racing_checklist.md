# M1.1 + M2 — manual racing checklist

Run the project (F5 in Godot 4.7). The M1 handling checklist (`m1_driving_checklist.md`) still applies; this list covers the redesigned circuit and AI racing. AI and grid values are **provisional**; record differences from Super Cars II rather than fixing them here.

To test with fewer opponents: select `Main` in `src/main/main.tscn` and set **Opponent Count** (0–9) in the Inspector.

## M1.1 circuit
- [ ] The circuit has clear straights, long sweeping corners and distinctly tighter bends.
- [ ] Barriers never let a car through; no corner traps a car.
- [ ] Laps still count only through every checkpoint in order.

## Grid and start
- [ ] All 10 cars wait on a two-column staggered grid behind the start/finish line; you (red car) start at the back.
- [ ] Every car starts when Fire is pressed on the mode panel; nobody moves before.
- [ ] Crossing the line at the start does not count as a lap.

## AI driving
- [ ] Opponents use the full road width through corners (racing line) and brake before tight bends.
- [ ] Opponents complete laps without getting stuck on barriers.
- [ ] Opponents follow a car ahead that is as fast as them, and move out to pass a slower one.
- [ ] Opponents can be overtaken and can overtake you; they do not get faster when behind (no catch-up).
- [ ] Opponent handling looks like yours (same rotation, acceleration and sliding).

## Contact
- [ ] Cars bump each other: a rear hit pushes the car ahead, side contact nudges both; no car passes through another.
- [ ] Contact is the same for you and the opponents.

## Positions and results
- [ ] HUD POS updates live as cars pass each other.
- [ ] When you finish, RESULTS lists finished cars with times, then the rest by running order ("running").
- [ ] Enter on RESULTS returns to the grid (Fire does nothing) with the order reversed: the winner starts last.
