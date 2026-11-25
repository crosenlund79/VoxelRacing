# M2.1 — manual spectator and personality checklist

Run the project (F5 in Godot 4.7). On the MODE panel press Left/Right until **SPECTATE RIVALS**, then Fire. The earlier checklists (`m1_driving_checklist.md`, `m2_racing_checklist.md`) still apply to normal races, which now use the rivals' names. All personality values are **provisional**.

Spectator keys: **Tab** switch Race History / Position Counts · **Left/Right** scroll the history · **F** normal / fast simulation · **Esc** back to the MODE panel.

## Spectator mode
- [ ] The red player car is not on the grid; the nine rivals start from a staggered grid.
- [ ] The camera follows a close battle, holds each shot for a few seconds, and leaves a car once it has finished.
- [ ] When all nine finish, RESULTS shows every rival with a real time, then the next race starts by itself from the reversed grid (winner last).
- [ ] Race History: fixed rows (Victor … Nina, each with their car), one new column per race; gold / silver / bronze stars for 1st–3rd, numbers for 4th–9th.
- [ ] After about 10 races the columns scroll; Left/Right scroll them; a new race scrolls to the newest column.
- [ ] Position Counts shows, per rival, how many times they finished 1st … 9th; the totals match the history.
- [ ] Esc returns to the MODE panel; spectating again keeps this session's history. Restarting the game starts a fresh history.
- [ ] No points, rankings or championship appear anywhere.

## Simulation speed
- [ ] F switches the info panel between x1 and x4; in x4 the race runs about four times faster but cars look and behave the same.
- [ ] Leaving spectator mode (Esc) always returns to x1.

## Identities
- [ ] Every race and every new game: Victor = sage car, Rocco = ochre, Ellie = slate blue, Hank = teal, Maya = cream, Dante = plum, Greta = olive, Finn = charcoal, Nina = burnt orange.

## Personality pilot (watch several races; behaviour varies race to race)
- [ ] **Victor "The Professor":** brakes early and smoothly, rarely touches barriers or cars, waits behind slower cars until a straight before passing; can get stuck mid-pack when starting at the back.
- [ ] **Rocco "Mad Dog":** brakes late, tailgates and dives for gaps (including in corners), now and then overshoots a corner and hits the barrier; lots of contact.
- [ ] **Ellie "Sparrow":** quick and tidy through corners in clean air; with a car right behind her she sometimes hesitates (lifts) or weaves (over-corrects) and loses time.
- [ ] Hank, Maya, Dante, Greta, Finn and Nina drive like the M2 opponents (no personality yet).
- [ ] No rival is visibly faster on straights or gets faster when behind (no catch-up).

## Camera selection (follow-up, 2026-11-15)
- [ ] Each spectator race starts with the camera on the car in the last grid slot (its row is outlined in gold).
- [ ] Clicking a car icon or name in the standings follows that driver with a smooth camera move; it stays on them.
- [ ] The < and > buttons under the standings step through the starting grid order (not the live positions), wrapping around.
- [ ] Works at x1 and in fast mode (F); a new race resets to its last-grid starter; the history panel is unchanged.
