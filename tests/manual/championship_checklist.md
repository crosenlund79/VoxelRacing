# Manual checklist — Race Experience, Rival AI & Championship

Run the game (`godot --path .`). Tick each item.

## Menus and setup
- [ ] Title: GO RACING! / ACHIEVEMENTS / SETTINGS / CONTROLS / QUIT; Esc / BACK return correctly.
- [ ] GO RACING!: Quick Race, Garage Race, Championship, Spectate, Multiplayer.
- [ ] Setup rows change with Enter and Left / Right; values persist after a restart.
- [ ] The preview rotates and updates for every circuit, environment and DAY / NIGHT; Ravenhook shows its bridge and the open jump gap.
- [ ] Spectate hides CONTROL and CAR; Championship hides circuit / environment / time / laps and lists the schedule.
- [ ] Multiplayer → split screen join and LAN host / join still work; audio settings still apply.

## Environments and night
- [ ] Wasteland: rain, slightly looser handling; Winter: snowfall, noticeably lower grip and longer braking; Green Valley unchanged.
- [ ] Night on every circuit and environment: cars, road edges and HUD stay readable; Winter night has blue moonlight, warm lamps, snow in the headlights.
- [ ] L still toggles lights; split-screen and spectating work at night.

## Rivals
- [ ] 20-lap armed race: rivals still fire in the last laps.
- [ ] Rocco is wild and blocks, Victor / Greta / Nina are tidy, Finn wanders.
- [ ] A car stuck behind a wreck gets through it after about half a second; active cars never pass through each other.

## Championship
- [ ] Six rounds (or three with ROUNDS 3) with the announced circuit / environment / time; standings after each round with points, DNF, wins.
- [ ] The grid reverses between rounds (winner last).
- [ ] Esc in a round: RESUME RACE / ABANDON CHAMPIONSHIP; abandoning returns to the menu.
- [ ] Winning: "CHAMPIONSHIP WON - YOU UNLOCKED <NICKNAME>!" with the red car; the CAR row offers it; that rival races the junker in later races, even with your own car chosen; ownership survives a restart.
- [ ] Losing: no reward. The next championship uses the other schedule.

## Defeat popup
- [ ] Destroyed by a rival: a card with that rival's car, name and a line; no extra sound; announcer line still plays at most once.
- [ ] Your own mine or a rival-on-rival hit: no card.
