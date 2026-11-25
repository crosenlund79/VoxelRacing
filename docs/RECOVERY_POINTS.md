# Recovery points

Known states of HyperCars you can go back to. This session's git access refuses tag
pushes, so each recovery point is a **backup branch** on GitHub. Recovery branches are
never moved or overwritten; development continues on `claude/festive-hypatia-15k6fj`.

## How to look at or recover a state

Inspect a state without changing anything (a throw-away folder beside your project):

```bash
git fetch origin
git worktree add ../HyperCars-rp0 origin/backup-20261123-presentation-rp0
```

Open `../HyperCars-rp0` in Godot 4.7.2 to play or test that state. Remove it when done:

```bash
git worktree remove ../HyperCars-rp0
```

Start new work from a recovery point (a new branch; nothing existing is touched):

```bash
git switch -c my-restart origin/backup-20261123-presentation-rp0
```

Compare a recovery point with the current work:

```bash
git diff origin/backup-20261123-presentation-rp0 origin/claude/festive-hypatia-15k6fj --stat
```

Never force-push, reset or delete a recovery branch to "restore" it: create a new
branch from it instead.

## Recovery points

| Name | Git reference | Commit | State | Validation | Known limitations |
|---|---|---|---|---|---|
| Pre-stabilization | `backup-20261122-pre-stabilization` | `630f25a` | Before the Stabilization & Pre-Completion Pass (2026-11-22) | Full suite 738 / 738 (2026-11-20) | Night high beam, network results and UI overlaps not yet fixed (fixed later) |
| RP0 — Pre-Presentation | `backup-20261123-presentation-rp0` | `3eb6afa` | "The Road to 1.0" complete: career, ending, wheels, defects | Full suite 771 / 771 on the same code (the last commits only changed docs) | See `docs/COMPLETION_READINESS.md` at that commit |
| RP1 — UI & Career | `backup-20261123-presentation-rp1` | `7371981` | Pause menu, results outcome line, race introduction, career milestones, rival reactions, stage identity | Focused: presentation_pass 3/3, rival_reactions 7/7, career_flow 9/9, championship_flow 13/13, race_menu 8/8, results_board 8/8, split_screen 9/9, career 11/11 | Garage, Scrapyard preview and damage visuals not yet done |
| RP2 — Arena & Garage | `backup-20261123-presentation-rp2` | `03db0ab` | + Scrapyard diorama, garage car centrepiece and shop feedback | Focused: presentation_pass 4/4, garage_flow 11/11, battle_royale 9/9, layout_selection 6/6, track_themes 9/9, career_flow 9/9, racing_modes 8/8 | Damage visuals not yet done |
| RP3 — Race Presentation | `backup-20261123-presentation-rp3` | `b5ad16e` | + visible damage (wear overlay, smoke by condition) | Focused: presentation_pass 5/5, multiplayer_regression (fingerprints) 3/3, vehicle_lights 6/6, lighting_pilot 5/5, net_damage 3/3, split_screen 9/9, battle_royale 9/9, jump_race 8/8, damage_race 15/15 | Final docs, artwork inventory and the full suite not yet run |
| RP4 — Validated Final | `backup-20261123-presentation-rp4` | the commit that added this row (docs only on top of `e0cb14f`, the code the full suite ran on) | The whole Presentation & Personality pass | Full suite 786 / 787 on `e0cb14f`. The one failure is the known intermittent LAN test (`test_net_lan_race`, 170 ms jump race: the client counted one take-off fewer for its own car under load); it passed 2 / 2 re-run alone, and no network, race or driving code changed since RP0. | Human visual acceptance outstanding (`docs/PRESENTATION.md`) |

### Garage, Combat & Career Refinements (2026-11-23)

| Name | Git reference | Commit | State | Validation | Known limitations |
|---|---|---|---|---|---|
| RP0 — Pre-Refinements | `backup-20261123-refinements-rp0` | `c47decf` | The Presentation & Personality pass, as delivered (same commit as RP4 above plus its readiness notes) | Full suite 786 / 787 on `e0cb14f` (docs-only commits since); the one failure is the known intermittent LAN test (A3) | Before the six refinements |
| RP1 — Weapons, AI & Rewards | `backup-20261123-refinements-rp1` | `130786d` | + career-garage Escape fix, weapon cycling (remappable, HUD), lowest-ranked-rival championship reward, AI ammunition pacing (fingerprints re-recorded for armed probes) | Focused: career_flow 10/10, garage_flow 14/14, weapon_cycling 10/10, control_bindings 13/13, championship 10/10, championship_flow 13/13, racecraft 10/10, ai_combat 12/12, tactical_ai 16/16, multiplayer_regression 3/3, tactical_race 7/7, achievement_tracking 6/6, race_variety 5/5, split_screen 9/9 | Upgrades and headlight colours not yet done |
| RP2 — Upgrades & Lights | `backup-20261123-refinements-rp2` | `3a8f5fd` | + Engine / Brakes / Chassis / Steering upgrades, headlight colour setting | Focused: upgrades 6/6, garage_flow 16/16, player_garage 19/19, career_flow 10/10, vehicle_lights 9/9, lighting_pilot 5/5, battle_royale 9/9, title_backdrop 1/1 | Docs, screenshots and the full suite not yet run |
| RP3 — Validated Final | `backup-20261123-refinements-rp3` | the commit that added this row (docs only on top of `9c7c0db`, the code the full suite ran on) | All six refinements, docs, screenshots, the two full-suite fixes | Full suite 818 / 818 on `9c7c0db` (the known LAN flake A3 did not occur) | Human playtest outstanding (`tests/manual/garage_combat_career_checklist.md`) |
