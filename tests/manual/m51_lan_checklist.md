# M5.1 — LAN race checklist (two computers, needs real hardware)

Both computers on the same local network, both running this HyperCars build. Allow UDP port **24680** through each computer's firewall (Windows may ask the first time you host).

## Host and join
- [ ] PC A: Title → RACE → TWO PLAYERS: LAN (TWO COMPUTERS) → HOST GAME. It shows "Hosting. Your address: 192.168.x.y (port 24680). Waiting for the other player…".
- [ ] PC B: same menu, type PC A's address, JOIN GAME → "Connecting…", then both computers switch to the grid panel.
- [ ] A wrong address / nobody hosting: PC B shows "Could not connect…" within a few seconds; CANCEL / Esc returns.
- [ ] Grid panel: PC A shows "Waiting for Player 2 to get ready…"; PC B shows "Fire: ready (the host starts the race)". After PC B presses Fire both show "READY"; PC A presses Fire to start. Each player can pick Fire to Accelerate / Fire to Brake for themselves with Left / Right before readying.

## Racing
- [ ] Each computer follows its own car (PC A red, PC B blue) and shows its own position, lap, time and weapons.
- [ ] Both computers show the same positions, crashes and finishing order; PC B's view lags very slightly behind and its own steering reacts a little late (no prediction yet) — note how it feels on your network.
- [ ] Weapons ON (Classic and Tactical): both see the same missiles, mines, explosions and wrecks; a press fires exactly once; ammunition matches on both screens.
- [ ] Holding / repeatedly pressing Space or Cross during a race only drives (never restarts anything).
- [ ] After both finish, both show the same results; PC A presses Enter (Confirm) for the next race; Fire on the results does nothing (reversed grid, a different rival sits out); PC B readies again.

## Disconnects
- [ ] Close the game (or pull the network cable) on PC B mid-race: PC A shows "CONNECTION LOST — The other player left the game."; Enter / Esc returns to the menu. Same the other way round ("The host left the game.").
- [ ] While PC A is still on its "connection lost" screen, a third computer that tries to join is refused ("The host is already racing").
- [ ] After returning, both can host / join again; single-player, couch split-screen, spectating and garage races still work.
