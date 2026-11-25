# Racing modes, combat statistics and Racing for Keeps

## Finishing early: watch the rest live

When the local player finishes (or is out) in a single-player race - quick, garage,
championship or Knockout - while rivals are still racing:

1. The position and time are fixed at once (the race simulation is unchanged: the
   rivals simply keep racing, as they always did).
2. A caption for 5 s: "1ST PLACE - YOU FINISHED!" (or "OUT - DNF!", or in Knockout
   "ELIMINATED AFTER LAP n!") over "RACE CONTINUES - WATCH YOUR RIVALS!".
   Enter: watch at once. Tab: skip to the results.
3. Live spectating (the spectator camera and director): the closest battle is
   followed; Left / Right switch to the previous / next car still racing; the standings
   tower can be clicked; it shows who is in, who is out and K / D / tombstones.
4. In a championship a compact panel shows the championship "IF IT ENDED NOW": the
   points before the round plus the round's points for each car's current position
   (FINAL for cars that are in, "now" for cars still racing).
5. Tab at any time: the real race is fast-forwarded (x8) until every car is in -
   nothing is invented. A field with no progress for 60 s is classified in running
   order, as in spectator races.
6. When everyone is in: the results (with TOMBSTONE | K | D) and, in a championship,
   the standings after the round; Enter continues (garage, standings, next race). Fire
   never dismisses a screen (2026-11-17).

Couch and network races keep their previous behaviour (results with the cars still
running). Once every car is in, contacts no longer change any car's condition.

## Kill feed and K / D / tombstones

A compact feed in the top-right corner (`src/ui/kill_feed.gd`), five recent lines that
fade after 6 s: `ROCCO [missile] VICTOR`, `NINA [mine] [tombstone] ELLIE`,
`HANK [crash] [tombstone] FINN`, `[tombstone] MAYA` (out, nobody responsible),
`OUT GRETA` (Knockout). AI against AI is shown too. It reads the same statistics as
the rankings (`src/combat/combat_stats.gd`):

- **K** - opponents destroyed by the driver's weapons (also when they respawn), and a
  retirement by collision damage the driver caused (below).
- **D** - every destruction of the car (own mine included) and a retirement not
  caused by a weapon destruction.
- **Tombstone** - permanent eliminations caused: a destruction that retires the car
  (one kill plus the tombstone, never two kills), or a retirement by collision damage
  where this driver's car contact damaged it within the last 4 s. Walls, own weapons,
  unattributed wear and Knockout eliminations by position give nobody a tombstone; a
  nearby driver who did not touch the car is never credited.

The results board and the standings tower show TOMBSTONE | K | D after the existing
columns (the compact split-screen tower leaves them out). Statistics are per race. Network
clients rebuild them from the host's combat events; the host's collision attribution
is not sent, so collision retirements show unattributed on the client.

## Knockout (GO RACING! > KNOCKOUT)

Last place out, on any circuit, environment and time of day, with the normal weapons, damage
and personalities. Ten cars, nine laps: every time the leader completes a lap, the
last-placed car still in (live standings) is eliminated - it leaves the race like a
retired car (no collisions, off the road, never back). A combat DNF just leaves earlier,
so fewer eliminations are needed; when one car is left it wins at once. The HUD line
shows the cars left and the next elimination. The last car still in, the one that would
go out now, gets a red "!" before its position in the standings. When that car is the
player, the HUD line turns red: "YOU ARE IN THE DROP ZONE!". The results show "OUT Ln". An eliminated
player watches the rest live. Knockout races do not count for achievements.

## Battle Royale (GO RACING! > BATTLE ROYALE)

**The Scrapyard** (`src/arena/`): an eight-sided walled yard with a scrap pile of junked
cars in the middle, four concrete blocks with hazard stripes, two crash barriers that
split the long sides into lanes, four tyre posts, grandstands and lamps; the environment's
ground, weather and day / night. Wide rings for ramming runs, tight gaps for close
fights, no dead ends.

- Ten cars, everyone against everyone; no laps, checkpoints or race positions; no respawns.
- Weapons never run out: front missiles (2.4 s cooldown) and mines (3.5 s) on their own
  cooldowns (`arena_weapon_rules.tres`); no homing or super missiles. The HUD shows
  "x INF" and the cooldown bars. Weapons go hot 3 s after FIGHT!.
- A missile hit costs 20 % condition, a mine 34 %, and stuns the car for 0.8 s;
  collisions and walls wear cars down as on a circuit. 0 % = eliminated for good,
  credited to the driver who caused it (weapon icon + tombstone; collisions as above).
- After 70 s the safe zone closes (90 s to its smallest) and outside it cars lose 8 % a
  second, so no match stalls.
- Arena AI (`arena_ai.gd`): picks an opponent (near, ahead, damaged, revenge - never
  preferring the human), hunts it, keeps the distance its personality likes, shoots only
  with a clear, aimed line, drops mines on pursuers, evades when chased, looks ahead to
  steer round the scrap and walls. From the rivals' existing traits: Rocco charges and
  rams; Victor, Greta and Nina keep their distance and wait for clean shots; Finn
  wanders. A stalled car pressed against a wall is turned a little (no reverse gear), the
  same for every driver.
- An eliminated player watches the survivors (Left / Right, Tab skips); the winner
  banner and the results with TOMBSTONE | K | D follow. Enter: menu, Tab: fight again.
- A hit only wears a car down here, so the rival defeat popup appears only for the hit
  that eliminates the player (2026-11-17).
- Measured AI matches: about 50-60 s, winners vary (Maya, Hank, Ellie, Greta, Dante,
  Rocco, Victor in different seeds), most eliminations by missiles, some by ramming.
  Local single-player only.

## Won cars and Racing for Keeps

A won rival car keeps the rival's own colours and artwork (and user overrides); the
red repaint is gone. The displaced rival still races the junker.

**Racing for Keeps**: enter a championship with a won rival car and that car is at stake.

- The setup screen says so in red ("RACING FOR KEEPS! WIN THE CHAMPIONSHIP - OR LOSE
  ROCCO'S CAR."), the round line says "FOR KEEPS: ROCCO'S CAR".
- **Win**: keep the car, plus the normal reward (a random car not yet owned).
- **Lose**: the car goes back to its rival ("CHAMPIONSHIP LOST - ROCCO RECLAIMS THE
  CAR!"), who drops the junker; it can be won again later. Other won cars stay.
- **The own car** can never be lost.
- **Forfeit**: abandoning (race menu or standings screen) asks twice when a car is at
  stake ("CONFIRM: FORFEIT") and then counts as a loss. The stake is saved when the
  championship starts, so closing the game mid-championship also forfeits it (applied,
  with a notice, at the next start).
