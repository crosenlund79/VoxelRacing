# M5.2 — online acceptance checklist (two Windows PCs on different internet connections)

Real cross-network play has **not** been verified by the developer tools — only simulated latency / jitter / loss on one machine. This checklist is the acceptance test. Setup help: `docs/NETWORK_PLAY.md`.

## Preparation
- [ ] Both PCs run the **same build**.
- [ ] Host PC: UDP **24680** forwarded on the router to the host's local address; Windows Firewall allows HyperCars (or the `netsh` rule); not behind CGNAT (router WAN IP = "what is my IP" address).
- [ ] Note both connections (cable / Wi-Fi / mobile) and the approximate distance between the players.

## Connect
- [ ] Host: RACE → TWO PLAYERS: LAN / ONLINE → HOST GAME (status shows UDP port 24680, waiting).
- [ ] Joiner: types the host's **public** address → JOIN GAME → progress "Connecting… n s" → both reach the grid within a few seconds.
- [ ] Wrong address or port not forwarded: "Could not connect…" within ~10 s; CANCEL works; nothing hangs.
- [ ] Different builds: a clear "different version" message on both sides.
- [ ] Both grids show the host's track name, laps, weapons and combat style.

## Lobby and readiness
- [ ] Joiner presses Fire (or Cross) several times: shows "YOU ARE READY" once and stays ready; host shows "PLAYER 2 READY".
- [ ] Joiner changes Fire to Accelerate / Brake: becomes not-ready until Fire again.
- [ ] Host Fire starts the race exactly once; repeated presses never restart anything.

## Racing (repeat for Fire to Accelerate and Fire to Brake, keyboard and controller)
- [ ] The joiner's own car answers steering and throttle immediately (no noticeable delay).
- [ ] Occasional small position corrections are acceptable; note any visible jumps (when, how large).
- [ ] Bumps with other cars: note how they feel for the joiner (they arrive slightly later; that is expected).
- [ ] PING line bottom-right shows plausible values (note them); it turns red only on real trouble.
- [ ] Classic, Tactical and No Guns: shots fire once per press; ammunition, explosions, wrecks and recovery look the same on both PCs.
- [ ] Every track (Green Valley, Heather Moor, Snow Pass) and at least 3 and 7 laps; one 20-lap race if time allows.
- [ ] Both PCs show the same results; host Enter (Confirm) → next race (Fire does nothing on the results) with the reversed grid and the next rival sitting out; repeat 3 races.

## Disconnects and cleanup
- [ ] Joiner quits mid-race → host shows CONNECTION LOST within ~10 s → Enter / Esc → menu. Swap roles and repeat.
- [ ] Pull the network cable / disable Wi-Fi for 15 s on one PC: both end cleanly, no freeze.
- [ ] After any ending, host and join again: a fresh session works (no ghost cars, no old results).
- [ ] Afterwards: single-player, spectating, garage races and couch split-screen still work.

Record: ping range, packet loss if shown, visible correction frequency, and anything that felt unfair for the joiner.
