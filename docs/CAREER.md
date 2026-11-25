# Career

Approved 2026-11-22, "HyperCars — The Road to 1.0" (Option B: a complete arcade racer
with a finite career, an ending, and endless play afterwards).

The player starts as an unknown racer among the nine established rivals and wins
three championships, one after the other, to become the **HyperCars Champion**. The
career reuses the game's own systems:
- the championship rules: points, countback, reversed grids, DNFs;
- the races, the AI and its personalities;
- the garage economy and its prizes;
- the car rewards and Racing for Keeps.

The arcade modes (GO RACING!) stay as they are.

Code: `src/career/career.gd` (progress and records), `src/career/*.tres` (the stages),
`src/ui/career_screen.gd` (the hub and Hall of Fame), `src/ui/victory_screen.gd` (the
ending), `src/ui/credits_screen.gd`, and the flow in `src/main/game.gd` (Career section).

## The stages

| Stage | Rounds | Circuits / environments / time | Combat | Title bonus |
|---|---|---|---|---|
| 1. Rookie Cup | 3 × 3 laps | Kestrel Ridge (Green Valley), Larkspur Ring (The Raceway), Ravenhook (Green Valley); all by day | Classic | $500 |
| 2. Pro Series | 6 rounds: four of 3 laps, then two of 7 | all three circuits; Wasteland, Tabletop Mayhem, Winter, Green Valley, The Raceway; three night rounds | Tactical | $1000 |
| 3. HyperCars Grand Championship | 6 rounds: three of 3 laps, three of 7, ending with the 7-lap **Grand Final** (Kestrel Ridge, Winter, night) | every circuit and environment, day and night | Tactical | $2000 |

- **Unlocking:** winning a stage unlocks the next. Winning the Grand Championship
  completes the career.
- **Weapons:** career races are always armed, in the stage's combat style.
- **Difficulty:** the challenge comes only from the schedules (longer races, weather,
  night), Tactical weapon management, keeping the car repaired and equipped, and the
  rivals as they are.
  - The rivals obey the same driving and combat rules as the player.
  - There is no hidden speed or grip, no rubber-banding and no scripted results.
- **Points:** the existing points (25-18-15-12-10-8-6-4-2-1), countback, a DNF scoring
  nothing, and reversed grids, as in `docs/CHAMPIONSHIP.md`.
- **Schedules:** `ChampionshipSchedule` resources gain `has_final` (the last round is
  billed as the GRAND FINAL), `career_style`, `career_bonus` and `blurb`.

## The garage in the career

The career has its own garage, saved in `user://career_garage.cfg`. It follows the
same rules and prices as `docs/ECONOMY.md`. The standalone Garage Race career
(`user://garage.cfg`) is never touched by the career, and the reverse.

- **Between rounds:** the garage opens before every career race. Buy, sell, equip,
  repair, add armour or upgrade the car (Engine, Brakes, Chassis, Steering), then RACE.
  Every owned weapon type is carried and can be switched in the race
  (`docs/RACE_RULES.md`, Weapon cycling).
- **From the career screen:** GARAGE opens it without racing. Back (Escape / pad B)
  returns to the career screen, and Back there to the title menu (2026-11-23 fix:
  after a round the title scene behind the career screens was left hidden).
- **Prize money** is paid per round by finishing position and race length, as in
  garage races.
- **Title bonus:** paid once, when a stage is won, together with a rival's car (the
  normal championship reward: the lowest-ranked rival in the final standings whose car
  is not owned yet, `docs/CHAMPIONSHIP.md`).
- **No dead end:** a broke player still races.
  - A car below 50 % is patched up to 50 % for free before every race.
  - A player with no rounds left races unarmed.
  - Losing a stage costs nothing but the stage: try it again.

## Saving, quitting and abandoning

`user://career.cfg` is written atomically: to a temporary file, then renamed. It is
saved when a stage starts, when a career race starts, when a round ends and when a
stage is decided.

| Situation | Result |
|---|---|
| SAVE & EXIT on the standings between rounds, or quitting the game there | Everything is kept: standings, round, money, garage, car. CONTINUE resumes with the right grid and opponents. |
| Leaving a career race (race menu) **before the player finishes** | That championship attempt is forfeited. Rounds already raced stay in the records; enter the stage again from round 1. |
| Leaving **after the player finished** (while watching the others) | The round counts (unfinished rivals in running order), as for any race. |
| Closing the game (or a crash) **during** a career race | Forfeited at the next start, with a notice on the title. There is no quit-and-retry of a bad race. |
| Back on the grid panel or in the garage, before GO | Nothing happens; progress is saved. |
| Losing a stage | No bonus and no car; the stage stays open for another attempt. |

**Racing for Keeps:** entering a stage with a won rival car puts it at stake, exactly as
in a championship. The stake is held in `user://car_collection.cfg` (`career_stake`)
and survives quitting between rounds.
- **Lost:** losing, forfeiting or leaving mid-race gives the car back to its rival.
- **Kept:** winning keeps it.
- **NEW CAREER** during a stake also forfeits it, so there is no way around the rule.

**Rewards are decided exactly once.** A round is recorded when its race concludes. A
decided championship records nothing more, and the bonus and the car are applied in
that same step.

## The ending and after

- **The ending:** winning the Grand Championship shows the final standings. CONTINUE
  then opens a short victory ceremony, which Enter or Esc skip after 0.8 s:
  - "HYPERCARS CHAMPION";
  - the podium with the real top three cars (the player's chosen car; rivals in their
    own colours or the junker; user artwork applies);
  - a drawn trophy and confetti;
  - the final standings.

  The **Hall of Fame** follows, and the menu music plays throughout.
- **Hall of Fame** (CAREER > HALL OF FAME) shows recorded data only:
  - champion status and the completion date;
  - the final podium;
  - careers completed;
  - titles per stage;
  - career races, wins, podiums, DNFs and money won;
  - the rival with the most career race wins;
  - rivals who won a title instead of the player;
  - achievements unlocked;
  - the owned rival cars.
- **After completion:**
  - The career stays completed until NEW CAREER.
  - Any stage can be raced again; replays pay their bonus and car reward like any
    championship win.
  - Every arcade mode stays available.
- **NEW CAREER** asks twice and says what is reset: career progress, records and the
  career garage. It keeps achievements, won cars, the Garage Race career and the
  lifetime title count.
- **CREDITS** (main menu): accurate attribution from the project's records.

## Tests

- **`tests/unit/test_career.gd`:**
  - stage order;
  - coverage of circuits, environments and night;
  - a lost stage and its retry;
  - save and restore;
  - quit mid-race;
  - rewards once;
  - records;
  - NEW CAREER;
  - replays;
  - broken saves;
  - atomic-save recovery.
- **`tests/integration/test_career_flow.gd`** (the real game):
  - a real first race with its prize;
  - the garage between rounds;
  - save & exit and resume in a new session;
  - the whole career with a lost stage, the ending and the Hall of Fame;
  - completion surviving a restart;
  - racing after the ending;
  - leaving mid-race, and leaving after finishing;
  - closing the game mid-race;
  - a DNF while broke;
  - NEW CAREER;
  - old saves.
