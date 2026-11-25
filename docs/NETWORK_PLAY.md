# Playing HyperCars over the network (two players)

HyperCars connects two computers directly over **UDP port 24680** (Godot ENet). One player **hosts**, the other **joins** with the host's IPv4 address. There are no servers, accounts, relays or automatic router setup: for internet play the **host** must make port 24680 reachable.

## Quick start
1. Both players run the same HyperCars build (the game refuses a different version).
2. Host: Title → RACE → TWO PLAYERS: LAN / ONLINE → **HOST GAME**. The panel shows the local network address and waits.
3. Joiner: same menu, type the host's address → **JOIN GAME**.
   - Same house / local network: the host's local address, e.g. `192.168.1.20`.
   - Over the internet: the host's **public** IPv4 address, e.g. `203.0.113.7` (the host finds it by searching "what is my IP" in a browser).
   - A different port: `203.0.113.7:30000` (the host must then also use that port — the default 24680 is recommended).
4. Both land on the grid panel. The joiner presses **Fire** to be ready, the host presses **Fire** to start. After the results the host presses **Confirm** (Enter / pad Start) for the next race; Fire never dismisses a screen. (Keys shown are the defaults; the game shows your own bindings.)

## What the host must set up for internet play
### 1. Windows Firewall (host, and usually the joiner too)
The first time HyperCars hosts, Windows asks whether to allow it on networks: tick **Private** (and **Public** only if needed) and choose **Allow**. If you missed the prompt, add a rule (Administrator command prompt):

```
netsh advfirewall firewall add rule name="HyperCars UDP 24680" dir=in action=allow protocol=UDP localport=24680
```

To remove it later: `netsh advfirewall firewall delete rule name="HyperCars UDP 24680"`. Third-party antivirus firewalls need an equivalent UDP rule.

### 2. Port forwarding on the host's router
In the router's web page (often `192.168.1.1` or `192.168.0.1`; look for *Port forwarding*, *Virtual server* or *NAT*):
- Protocol **UDP**, external port **24680**, internal port **24680**,
- internal IP = the host computer's local address (shown on the HOST panel, e.g. `192.168.1.20`).
- Give the host computer a fixed local address (DHCP reservation) so the rule keeps working.

The joiner does **not** need port forwarding.

### 3. Check for CGNAT (carrier-grade NAT)
Port forwarding cannot work if the internet provider shares one public address between customers (common on mobile / 4G / 5G, some fibre and cable providers):
- Compare the **WAN / Internet IP** shown in the router with the address from "what is my IP". If they differ, or the router's WAN IP starts with `100.64.`–`100.127.`, `10.`, `172.16.`–`172.31.` or `192.168.`, you are behind CGNAT.
- Options: ask the provider for a public IPv4 address (sometimes free, sometimes paid), let the other player host instead, or use a VPN-style virtual LAN tool that both players install (outside HyperCars; then join with the virtual-LAN address).

## Common connection failures
| Message / symptom | Likely cause | What to try |
|---|---|---|
| "Could not connect to … " after ~10 s | Wrong address, host not hosting, port not forwarded, firewall, CGNAT | Check the address and port; host waits on the HOST panel; check the firewall rule, port forwarding and CGNAT above; try on the same LAN first. |
| "Please type the host's IPv4 address…" | Not an IPv4 address (names and IPv6 are not supported) | Type digits like `203.0.113.7` or `203.0.113.7:24680`. |
| "Could not host on port 24680" | Another program (or another HyperCars) already uses the port | Close it, or restart the computer. |
| "The host runs a different version of HyperCars" | Different builds | Both players install the same build. |
| "The host is already racing" | A race is in progress on the host | Wait until the host returns to the menu and hosts again. |
| "CONNECTION LOST" during a race | One computer closed the game or the connection dropped for ~10 s | Both return to the menu (Enter / Esc, or pad Start / B) and start a new session. There is no reconnect. |
| High ping / "connection problems" indicator | Busy or Wi-Fi network, long distance | Prefer cable, close downloads / streams. Above ~150 ms ping the game remains playable but bumps and hits react later. |

## Testing at home
- **One computer, two copies:** host in one window, join `127.0.0.1` in the other (in the editor: Debug → Customize Run Instances → 2).
- **Two computers, same network:** join the host's local address (no forwarding needed).
- **Over the internet:** only after port forwarding; if it fails, test the forwarding with a friend first on LAN, then from outside.

## Final results (protocol 7, 2026-11-22)

The host's RESULTS message is reliable and authoritative. It carries:
- the finishing order and times;
- every racer's DNF flag;
- every car's final condition and ammunition.

The client takes these in place of the last snapshot it received, so a car retiring
just before the flag is classified the same on both computers even when the final
snapshots are lost. Protocol 6 builds cannot join protocol 7 games.

## Pit lanes in network races (protocol 6)

The host decides everything in the pit lanes: limiter, overrides, collision tickets,
service bays and repairs (`docs/PIT_LANES.md`). Each snapshot carries every car's pit
state (limiter, overridden, serviced, service progress, the bay it holds); the
client's own car follows the host's limiter at once, and only the host assigns bays,
so two players can never hold the same bay. A client's double tap travels as a running total in its
INPUT messages (delivered exactly once, like weapon presses); tickets reach the
client's kill feed and announcer through the reliable EVENTS channel. Steering is
sent as a fraction (proportional sticks, smoothed keys). Protocol 6 builds cannot
join older builds (the version check says so). Tested with 80 ms latency, jitter
and loss: a host-decided rival pit stop, the client seeing the service, identical
condition and results (`test_net_lan_race.gd`).

## Jumps in network races (J5)

Kestrel Ridge, Ravenhook and the experimental figure-eight are raced with their real
jumps on both computers (protocol 5; older builds cannot join). The host decides every
takeoff, landing and fall, the fall's damage and the set-back past the gap.

- **What travels:** each snapshot carries the jump state (seconds in the air, takeoff
  lift, which jump, seconds left down in the gap) only for cars that are flying or down
  in a gap; cars on the road add nothing.
- **Other cars** on the client fly at the moment the client shows them (interpolated
  like their positions, about 4 ticks behind the newest snapshot).
- **Your own car** jumps at once: the client runs the same jump model for it (takeoff
  from its own speed, flight, landing). If the host's outcome differs from the
  prediction (e.g. the host's car was slowed by a contact the client does not
  simulate), the host's state replaces it. A one- or two-tick timing difference does
  not count. A fall the client predicts waits in the gap until the host confirms it;
  after a fall or a wreck the client continues from the host's newest state.
- **Same race on both computers:** the client always races the host's circuit, environment
  (and so the same handling), time of day, laps, weapons and combat style.

Measured on one machine with simulated conditions (two processes over localhost):
40-170 ms latency, 10-40 ms jitter, 1-5 % loss, armed and unarmed, forced falls, both
control modes: identical finishing order, times, car condition, ammunition, DNFs,
destructions, takeoffs and falls on both computers; 0-1 jump corrections per race.
This is not a substitute for a real internet test between two computers.
