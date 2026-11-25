# M4 — couch split-screen checklist (needs real hardware)

Two PS5 DualSense controllers connected to the PC (USB or Bluetooth), TV at 16:9. Godot reads them as standard gamepads: Cross = A, Circle = B, Triangle = Y, R1 = right shoulder.

## Joining
- [ ] Title → RACE → TWO PLAYERS: SPLIT SCREEN shows "PLAYER 1 / PLAYER 2: press Cross / A to join".
- [ ] Controller A's Cross makes it Player 1 (its name is shown); controller B's Cross makes it Player 2; pressing Cross twice on one controller does not take both slots.
- [ ] Circle removes a joined player; Circle with nobody joined goes back. With both joined, Cross starts.
- [ ] (Optional) One player on the keyboard: Space joins, keys as in single-player.

## Racing
- [ ] Left half = Player 1 (red car), right half = Player 2 (blue car); each camera stays on its own car even when far apart.
- [ ] Each controller steers / accelerates / fires only its own car; the other car never reacts.
- [ ] Each HUD shows its own position, lap, time, weapons, ammunition and cooldown bars; DESTROYED appears only on the wrecked player's half.
- [ ] The grid panel and results respond to either controller (Cross start / continue, d-pad left-right mode, up-down weapons, R1 combat style, Triangle laps, Circle back).
- [ ] The race shows results only after both players finish; if one player is genuinely stuck for 30 s after someone finished, the results appear anyway.
- [ ] One rival sits out each race (Victor first, then Rocco, …); the next grid is the reversed result.
- [ ] Engine and weapon sounds are heard sensibly from between the two cars.
- [ ] HUD text is readable from the sofa; the shared position list (bottom centre) does not hide anything important.
- [ ] Frame rate is smooth on the TV PC, lighting off; note the result with L (lighting on).
- [ ] Single-player, garage races and spectating still work as before afterwards.
