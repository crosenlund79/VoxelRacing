# HyperCars — completion readiness

**As of:** 2026-11-22, after "The Road to 1.0" (career, ending, wheel refinement,
remaining defects).
**Branch:** `claude/festive-hypatia-15k6fj`.
**Backups:** branch `backup-20261122-pre-stabilization` at `630f25a`. A branch rather
than a tag: this session's git access refuses tag pushes, and the user chose a backup
branch.

This document records what stands between the current build and a finished game. It
is not a plan and approves nothing (`docs/GODOT_CLAUDE_GUIDELINES.md`, rule 7).

## Verdict: feature complete, pending human playtesting and artwork

HyperCars can be played from the start of a career to its ending, and on indefinitely
afterwards. Every approved system is implemented and covered by automated tests.

What remains needs a person:
- a playtest on real hardware (B);
- balance decisions made from that playtest (D3);
- the user's own artwork (E);
- a first Windows export once approved (C).

## What the game is now

- **CAREER** (`docs/CAREER.md`): Rookie Cup → Pro Series → HyperCars Grand
  Championship, with:
  - a seven-lap Grand Final;
  - its own saved garage, with prizes, title bonuses and a rival's car per title;
  - Racing for Keeps;
  - atomic saving between rounds, and no quit-and-retry of a bad race;
  - a victory ceremony, the Hall of Fame and replays after completion;
  - NEW CAREER with confirmation.
- **GO RACING!:** Quick Race, Garage Race, Championship, Knockout, Battle Royale,
  Spectate, Multiplayer (couch split-screen, LAN / online).
- **The racing:**
  - three circuits, five environments, day / night;
  - combat, damage, pit lanes;
  - nine personality rivals;
  - achievements, Nemesis Welcome;
  - the official music and voice recordings;
  - remappable controls;
  - the artwork override pipeline with Artwork Mode;
  - CREDITS.

**A complete, enjoyable game without new modes or circuits?** Structurally, yes. The
career gives a beginning, a climb, a climax and an ending; the car collection and the
arcade modes give reasons to keep playing. Whether it holds the player's interest for
the whole career is the playtest's question (B), not something tests can answer.

## Presentation & Personality pass (2026-11-23)

The UI, career atmosphere, Scrapyard preview, garage, race introduction / results and
visible damage are polished (`docs/PRESENTATION.md`; recovery points in
`docs/RECOVERY_POINTS.md`).

**Full suite:** 786 of 787 passed in 94 scripts. The one failure is the known
intermittent LAN jump test (A3), which passed 2 / 2 re-run alone.

**Performance** (software OpenGL, no GPU, 10 armed cars, 1280×720):
- with every car worn and smoking: 34.5 fps by day and 17.9 at night;
- all healthy: 33.9 and 17.0;
- the wear shader and smoke cost nothing measurable.

## Garage, Combat & Career Refinements (2026-11-23)

Six playtest observations, all delivered:
- the career-garage Escape bug (root cause fixed, regression test);
- weapon cycling between owned types;
- AI ammunition pacing by personality schedule (measured: `docs/RACE_RULES.md`);
- the lowest-ranked unowned rival's car as the championship reward;
- Engine / Brakes / Chassis / Steering upgrades;
- headlight colours.

Recovery points: `docs/RECOVERY_POINTS.md`.

**Full suite:** 818 of 818 passed in 96 scripts on `9c7c0db`. An earlier run on
`3a8f5fd` had two failures, both fixed:
- a test expecting the old weapon-command shape;
- a network test that retired a fresh weapon wreck by fiat
  (`docs/BACKLOG.md`).

The known intermittent LAN test (A3) passed in both runs.

The armed determinism fingerprints were re-recorded: the AI fires at other moments.
Every unarmed fingerprint is unchanged.

**Needs a person:** `tests/manual/garage_combat_career_checklist.md`.
- Upgrade feel and prices.
- Cycling on a real pad.
- Headlight tints on a real GPU.
- Whether Victor / Greta / Nina should spend more: they are limited by their own
  quality bars.
- Long armed races ending with most of the field retired (D1).

## A. Confirmed bugs (still open)

None of these blocks a normal session or the career.

| # | Defect | Effect | Notes |
|---|---|---|---|
| A1 | At an elevation-zone end (bridge circuits), two cars on the same branch can pass through each other for a few frames (J1 design limit). | A rare visual pass-through. | Not fixed: a fix changes collision layering and therefore the deterministic simulation fingerprints. Better as its own small, approved task with fingerprint review. |
| A2 | A client's car bumps arrive as host corrections: slightly late or snappy, with a few hard snaps per race at 80–120 ms. | Feel only, online. | The prediction design (M5.2). Needs real two-PC play to judge. |
| A3 | Test only: `test_net_lan_race` "armed jump race at 170 ms" fails now and then under full-suite load. On 2026-11-23 the client counted one take-off fewer for its own predicted car than the host. | None found in the game: classification, DNFs, condition and ammunition come from reliable messages. | Passes re-run alone (2 / 2). Its jump tolerance assumes the client never counts fewer take-offs than the host; whether that assumption or the prediction should change is for the network cleanup. |

**Fixed in this assignment:**
- Network clients now see the culprit of a collision retirement in the kill feed and
  in TOMBSTONE | K | D (a host `retired` event), whichever arrives first, the event or
  the DNF.
- Two intermittent `test_net_lan_race` failures under load turned out to be test-only:
  - "armed jump race at 170 ms" hit its own 140 s wall-clock limit while the field was
    still racing; the limit is now 220 s;
  - "experimental crossing armed race" compared per-computer take-off observations
    exactly; it now uses the jump races' tolerance, and every other field must still
    match exactly.

## B. Human playtesting (only real play can verify these)

Automated tests prove none of the following:

- **The career end to end by a person:**
  - pacing over three stages;
  - whether the Rookie Cup is approachable and the Grand Championship hard but fair;
  - whether the title bonuses ($500 / $1000 / $2000) and the career garage economy feel
    right;
  - whether forfeiting on a mid-race exit feels fair.
- **Real controllers:**
  - DualSense and Xbox pads on Windows;
  - hot-plugging;
  - couch with two pads;
  - the career and garage menus with a pad only.
- **Two computers:** LAN and the internet, port forwarding, real latency and loss,
  disconnects.
- **A real GPU:** night with dynamic lights, split-screen, 50-lap armed races, the
  victory confetti.
- **Audio by ear:** music loops, the Battle Royale loop, engine layers, the voice
  speed-up, ducking.
- **Balance and feel:**
  - combat deadliness;
  - DNFs in long armed races;
  - Rocco's win rate;
  - prices and prizes;
  - pit rules;
  - Battle Royale timing;
  - Nemesis Welcome frequency.
- **Readability at 1080p and on a TV:** HUD, standings, career screens, couch views,
  night lighting.
- **The new visuals:** the tucked-in wheels, 30° steering and the rolling tread at
  speed (check for strobing); the career screens, ceremony and Hall of Fame.
- **The user's own artwork:** drawings in `custom/` and `assets/graphics/` (nose to the
  right; a tread that repeats along X rolls best), and an exported build reading
  `custom/` next to the executable.

Checklists: `tests/manual/playtest_checklist.md` (whole game) and
`tests/manual/career_checklist.md` (the career).

## C. Essential missing functionality

- **C1. A Windows release candidate.** This needs explicit approval for an export.
  What it would take:
  1. The Godot 4.7.2 export templates, and an `export_presets.cfg` with one
     "Windows Desktop" preset.
     - Exclude `tests/*`, `addons/gut/*`, `docs/*` and `assets/audio/_inbox/*`.
     - Embed the PCK or ship it beside the executable.
  2. A portable folder or zip: `HyperCars.exe` (+ `.pck`), an empty `custom/graphics`
     and `custom/audio` with a short README (the override contract, `assets/README.md`),
     and the licences (Fredoka OFL; Godot's MIT notice).
  3. Saves go to `%APPDATA%\Godot\app_userdata\HyperCars\`. Optionally,
     `application/config/use_custom_user_dir` could give a cleaner `%APPDATA%\HyperCars`;
     that is a user decision before the first release, since it moves saves.
  4. Windows Firewall asks the first time the game hosts on UDP 24680 (LAN / online).
  5. Unsigned builds show a SmartScreen warning; code signing is a later release
     decision.
  6. Smoke-test the exported build: start, career save / resume, a `custom/` override
     picked up without rebuilding, a pad, and quitting cleanly.
- **Linux:** the same preset approach works where the existing support permits.
  Untested.

Nothing else was found missing from an approved system.

## D. Design decisions (for the user and ChatGPT; not approved)

- **D1. Balance after the playtest:**
  - weapon damage by race length;
  - Rocco ("Mad Dog") winning about 31 % of armed races;
  - consolation money for P6+;
  - the 20 / 50-lap prize multipliers;
  - career title bonuses;
  - stage schedules (laps, night share).
- **D2. Career options:**
  - whether a mid-race exit should forfeit the whole attempt (today) or only score the
    round as a DNF;
  - whether replays after completion should pay the title bonus again (today: yes, like
    any championship win).
- **D3. Super Cars II items not implemented:** upgrades (turbo / jump, ram, engines),
  track hazards, the interview characters. Add only by explicit decision.
- **D4. Network scope:** reconnect, NAT traversal / relay, more players, online
  Knockout / Battle Royale.
- **D5. AI scope:** rivals caring about their own condition, rival armour, awareness of
  mines.
- **D6. Release:** the Windows save-folder name, code signing, the store (none planned).

## E. Optional improvements (not needed to finish)

- **Artwork:** the user's drawings replacing the templates one at a time, the next
  phase. Optional new pictures for visuals still drawn in code:
  - the trophy and podium (career ending);
  - the arena floor and blocks;
  - divider tops, jump ramps, pit lettering.
- **Audio:**
  - voice recordings for more rivals and events, including career moments (title won,
    Grand Final);
  - per-file loop points for MP3 overrides.
- **Presentation:**
  - per-board ad and crowd variety;
  - a pit line for the followed rival in spectator mode;
  - Artwork Mode applying without a restart;
  - a career-specific announcer line at the Grand Final (needs a recording).
- **Robustness:** the standalone garage, car collection and career now save
  atomically. Settings, controls, achievements and the rival memory still write in
  place (a crash mid-write could lose those small files).

## Remaining placeholder art and audio

- **Graphics:** every picture except the user's six drawings (stars, crash, tombstone,
  grid box) and the edited confetti is a replaceable template
  (`docs/ARTWORK_MASTER_LIST.md`). The trophy and podium in the ending are drawn in
  code.
- **Audio:**
  - **The user's own:** the three music tracks and seven voice recordings: four
    announcer lines (including "Pit lane violation") and Rocco, Victor and Nina.
  - **Templates:** every sound effect and the engine layers are synthesised.

## Verification of this assignment (automated, 2026-11-22)

**Full suite (headless, GUT):** 771 of 771 passed in 91 scripts, with 1 GUT warning
(a float / int comparison in a test).
- It includes the determinism fingerprint tests: ordinary races are unchanged by the
  career and the wheel work.
- It includes the LAN tests: two processes, simulated latency, jitter, loss and
  repeated races.

**Armed AI races** (spectator, 3 laps, ten rivals, 8× speed; one per circuit and combat
style):
- all six finished, with 13–26 destructions each and no DNFs;
- the winners were Rocco ×5 and Hank ×1. Scene-level runs keep a fixed first grid, so
  this is no measure of Rocco's 31 % (shuffled grids, D1).

Career-specific tests:
- **`tests/unit/test_career.gd` (11):** the career's rules;
- **`tests/integration/test_career_flow.gd` (9):** the real game, from a fresh career
  through the ending, a restart and post-career racing, plus the losing, forfeiting,
  closing, broke, NEW CAREER and old-save routes.

**Rendered checks** (software OpenGL, real game scenes):
- the career screens, the ending and the Hall of Fame (`docs/artwork/career_screens.jpg`);
- the wheels before and after (`docs/artwork/wheels_before_after.jpg`).

## Fixed in the Stabilization pass (earlier on 2026-11-22)

| Fix | Root cause | Test |
|---|---|---|
| Night high beam lit the road behind the car | Godot scales a `PointLight2D` texture without scaling its offset; the offset now grows with the beam. | `test_vehicle_lights.gd`; `docs/artwork/night_lights_before_after.jpg` |
| Client could miss a DNF / final condition / ammunition at the flag | RESULTS now carry them (protocol 7). | `test_net_authority.gd`, `test_net_lan_race.gd` |
| Title backdrop showed the own car when a won car was chosen | Now the chosen car (CarArt). | `test_title_backdrop.gd` |
| Couch pit-ticket banner on the shared screen | Now in the offender's own view. | `test_stabilization_ui.gd` |
| Achievement toasts over the championship standings | Toasts wait while the standings are up. | `test_stabilization_ui.gd` |
