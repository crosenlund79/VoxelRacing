# Championship, car rewards and the race setup screen

## GO RACING! and the race setup screen

The title's main menu is GO RACING! / ACHIEVEMENTS / SETTINGS / CONTROLS / QUIT.
GO RACING! lists QUICK RACE, GARAGE RACE, CHAMPIONSHIP, SPECTATE and MULTIPLAYER.
Every entry opens the same setup screen (`src/ui/title_screen.gd`):

| Row | Values | Shown for |
|---|---|---|
| CIRCUIT | Kestrel Ridge / Larkspur Ring / Ravenhook | all but Championship |
| ENVIRONMENT | Green Valley / Wasteland / Winter / The Raceway / Tabletop Mayhem | all but Championship |
| TIME | DAY / NIGHT | all but Championship |
| LAPS | 3 / 7 / 20 / 50 | all but Championship |
| WEAPONS | ON / NO GUNS | all |
| COMBAT | Classic / Tactical | all |
| CONTROL | Fire to Accelerate / Fire to Brake | all but Spectate |
| CAR | your own car or a won rival car | Quick, Garage, Championship |
| ROUNDS | 6 (full season) / 3 (short) | Championship |

Enter (or Left / Right) changes a row; START begins; Esc goes back. Circuit, environment,
time, laps, weapons, style, control, car and championship rounds are saved in `user://settings.cfg`.
MULTIPLAYER continues to SPLIT SCREEN (press-a-button join) and LAN / ONLINE as before;
a LAN / online client races the host's circuit, environment and time of day (sent in WELCOME).

The right half shows a rotating low-poly diorama of the chosen circuit
(`src/ui/circuit_preview.gd`): a faceted plate in the environment's colours, the real
centreline, bridges lifted on pillars, the jump's gap left open (gold markers), the
start line, a few faceted trees and, at night, warm lamps. The Raceway shows red / white
kerbs and floodlight masts (cool lamps at night); Tabletop Mayhem shows a wooden plate
with pencils and dice. The preview is drawn procedurally (no 3D scene, no artwork) and
rebuilt whenever the circuit, environment or time changes.

## The championship

A six-round season (or the three-round short version: ROUNDS on the setup screen)
against all nine rivals (`src/championship/championship.gd`, `championship_schedule.gd`).
Each schedule covers all three original circuits, all five environments and both day
and night. It ends with a **seven-lap GRAND FINAL**, billed on the standings screen
("NEXT: THE GRAND FINAL", "START THE FINAL") and in the race HUD.

- **Schedules** are resources (2026-11-17):

  | Round | `hypercars_cup.tres` (HyperCars Cup) | `night_series.tres` (Ridge & Hook Series) |
  |---|---|---|
  | 1 | Kestrel Ridge, Green Valley, day | Larkspur Ring, The Raceway, night |
  | 2 | Larkspur Ring, Wasteland, day | Kestrel Ridge, Tabletop Mayhem, day |
  | 3 | Ravenhook, Tabletop Mayhem, day | Ravenhook, Winter, day |
  | 4 | Larkspur Ring, Winter, night | Kestrel Ridge, Wasteland, night |
  | 5 | Ravenhook, The Raceway, day | Larkspur Ring, Green Valley, night |
  | FINAL | Kestrel Ridge, The Raceway, night, 7 laps | Ravenhook, Tabletop Mayhem, night, 7 laps |
  | short version | rounds 2, 3, final | rounds 2, 5, final |

  Rounds 1–5 are 3 laps. The short version (`short_rounds`) picks three rounds, one on
  each circuit, ending with the same final. Championships take turns through
  `ChampionshipSchedule.SCHEDULES` (the count is saved), so consecutive runs race
  different combinations. Add a schedule by adding a `.tres` and listing it.
- **Points** 25 / 18 / 15 / 12 / 10 / 8 / 6 / 4 / 2 / 1 (per schedule); a DNF scores
  nothing and is classified behind the finishers.
- **Ties**: points, then countback (more wins, then more seconds, ...), then the last
  round's result, then racer id.
- **Grids**: round 1 = the rivals in a shuffled order (race variety, from the race seed), the player last; afterwards the previous
  round's order reversed (the winner starts last), as in normal races.
- **Between rounds** the standings screen (`src/ui/championship_screen.gd`) shows the
  table (position, car, driver, last result, wins, points) and the next round's circuit,
  environment, time of day and laps with the rotating preview; START ROUND n or ABANDON.
- **Racing**: the setup's weapons, combat style, control mode and car apply; the standard
  quick-race loadout (no garage money); ammunition scales with the round's laps; the HUD
  names the round. Esc pauses (RESUME RACE / ABANDON CHAMPIONSHIP); leaving abandons the
  championship (nothing won). Enter on the results continues to the standings (Fire never
  dismisses a screen).
- **Final**: the final standings and the champion. Rounds count for achievements and
  rival careers like normal races.

## Car rewards (`src/garage/car_collection.gd`)

Winning a championship (standalone or a career stage) claims the car of the
**lowest-ranked rival in the final standings whose car the player does not own yet**
(2026-11-23; it was random). It is saved in `user://car_collection.cfg`.

- **Deterministic, never a duplicate:** owned cars are skipped (the next one up the
  standings), and a rival missing from the standings counts as last.
- **Reward screen:** e.g. "CHAMPIONSHIP WON - YOU CLAIMED DANTE'S CAR!" with the
  rival's own artwork, in its original colours, and the milestone card "YOU CLAIMED
  DANTE'S CAR".
- **Collection complete:** after the ninth, "ALL NINE RIVAL CARS COLLECTED!"; later wins
  say the collection is complete.
- **Racing for Keeps:** stakes and forfeits are unchanged.

- **The player's car**: the setup's CAR row picks the own car or any won car. A won car
  keeps the rival's original colours and artwork (user overrides included); the earlier
  red repaint was removed. Racing for Keeps: see `docs/RACING_MODES.md`.
- **The displaced rival** races the one shared junker (`cars/body_junker`,
  `cars/car_junker`, slight per-rival tint) from then on, whatever car the player
  picks, with the same name, personality, voice lines and career statistics.
- **Identical performance**: looks only; every car keeps the same driving parameters.
- Applies to single-player races, garage races, championships and spectating; couch
  split-screen and network races keep the standard cars (the other computer has its own
  collection).

## Rival defeat popup (`src/ui/defeat_popup.gd`)

When a rival's weapon destroys a human's car on this computer, a short card shows
that rival's car, full name and one of three lines in their personality
(`src/ai/rival_taunts.gd`), credited to the actual attacker (the combat event's owner).
It is silent, so the Voice Director stays the only voice (announcer and rival lines
never overlap). One card at a time with a 6 s minimum gap, each rival's lines in turn,
nothing for your own weapon, another human's, rival-on-rival hits or spectating.
