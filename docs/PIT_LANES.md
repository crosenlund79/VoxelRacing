# Pit lanes, split sections, pit violations and vehicle lights

Approved 2026-11-17 ("HyperCars — Endurance Racing, Track Branches, Pit Violations,
Lighting & Steering"), refined the same day ("HyperCars — Pit Lane Refinement: Three
Bays, Collision Fines & Speed Override"). Numbers are provisional (`src/race/default_pit_rules.tres`,
personality traits in `src/ai/personalities/`).

## Track branches (`TrackLayout.branches`)

A branch is a stretch where the road widens around a solid **divider** and later
merges back again. The divider is a barrier island with a rounded nose at each end.
Lap progress stays a projection onto the centreline, so every lane counts laps,
positions, gaps and timing in the same way. Checkpoint gates span every lane.
`TrackLayout.validate_branches()` keeps branches:
- on the ground;
- clear of jumps, narrow sections and the starting grid;
- at least 80 px from any other stretch of road.

| Circuit | Pit lane (arc px) | Service bays (centres) | Split section | Split lanes (left / right) |
|---|---|---|---|---|
| Kestrel Ridge | 250–1520, main straight, right | 705 / 885 / 1065 | 5430–6070 (west loop straight) | 96 / 96: equal |
| Larkspur Ring | 300–1750, main straight, right | 845 / 1025 / 1205 | 4150–4950 (through a bend) | 84 / 112: tight inside or fast-but-wide outside |
| Ravenhook | 250–1600, main straight, right | 745 / 925 / 1105 | 7650–8320 | 112 / 84: wide left or narrow right |

All three pit lanes use the same layout (Pit Lane Refinement; roomier bays in
Personality & Polish, 2026-11-17):
- 280 px entry and exit ramps and a 24 px divider;
- an 80 px **through-lane** beside the divider, clear all the way;
- three numbered **service bays**, PIT 1–3: 110 px long, 84 px deep, 70 px apart
  (180 px centre to centre);
- the bays sit on an apron that bulges out of the outer wall around them (110 px
  tapers), so cars turn out of the through-lane into a bay and back;
- no barrier stubs between the bays (they caught cars rolling along the apron): the
  bays are marked by thick frames and large PIT 1–3 numbers.

**Room to manoeuvre:** the car is unchanged (a 60 × 32 px capsule turning at 210°/s;
at the 50 % limiter its turning circle is about 57 px). It was driven with digital
keys into the middle bay with both neighbours parked, from the limiter and with a slow
late turn-in. The closest it came to a parked car was 50 px (25–29 px with the earlier
90 px bays), and 22 px to the barrier. It made no contact going in or out.

Each pit lane has a PIT sign before the entry (`track/pit_sign` template), "PIT"
lettering, white limiter lines and the bay frames: gold when free, red while a car
holds the bay. On The Raceway, the pit building stands beside the bays. The setup
screen's circuit preview draws the lanes from the real geometry.

## Pit service and bays (`PitWorld`, host-authoritative)

- **Service:** stopping in a free bay (below 12 px/s) for **6 s** restores **+30
  condition points**, never above 100 %. The service is free.
- **One car per bay:** a car in a bay occupies it, whether it wants service or not,
  and holds it until it has physically left (also after its service). A held bay is
  never shown as free and never services another car. Three cars can be serviced at
  the same time, one per bay. A retired car occupies nothing.
- **Pit full:** with all three bays held, nobody else can begin a service: wait for
  a bay or drive on along the through-lane. The HUD shows "PIT FULL - NO FREE PIT
  BAY"; the bay frames are red. Cars are never queued, moved or teleported into a bay.
- Moving off or leaving the bay interrupts the service and restores nothing.
- Each pit-lane traversal allows one service. Nudging out of a bay and back in
  does not repeat it; the next service needs another lap.
- No ammunition is restored. A retired (DNF) car is never repaired and holds no bay.
- **Knockout:** no service (pit lanes still exist; driving through gains nothing).
- **Battle Royale:** no pits; the Scrapyard arena has none.
- **HUD:** while servicing, "PIT n SERVICE - REPAIRING" and "CONDITION: 42% -> 72%",
  with a progress bar.

## Pit limiter and override

- **Engages** when a car enters the pit lane proper, beside the divider.
- **Caps the car at 50 %** of its top speed (`CarModel.speed_cap`). The slow-down is
  smooth, at 0.6 × brake deceleration, never a teleport.
- **Releases** when the car leaves the lane. The car then accelerates normally; there
  is no boost.
- **Never on the racing road:** a test samples every 20 px of all three circuits.
- **Override:** double-tap the configured **Fire / accelerate** binding (keyboard or
  controller) inside the pit lane, with both presses within 0.35 s.
  - A press held through the entry never counts; it must be released first.
  - The override lasts until the end of that traversal. The next entry engages the
    limiter again.
  - **Speeding is allowed:** no ticket, fine or penalty. The risk is the narrow, busy
    pit lane.
- **HUD:** "PIT LIMITER - 50%" with the bound key; once overridden "LIMITER OFF -
  COLLISIONS IN THE PITS ARE FINED".

## Collision tickets

- **What counts:** a meaningful impact by a car in the pit lane (its side of the
  divider, bays included):
  - into a barrier, the divider, a bay stub: impact ≥ `DamageRules.wall_threshold`
    (110 px/s, the damage model's own "this hurts" line);
  - into another car: closing speed ≥ `DamageRules.car_threshold` (120 px/s).
- **Who is to blame:** the car that drove into the other (its velocity towards the
  other just before the contact is the larger, and at least 40 px/s). A stopped car
  (in its bay, waiting) is never to blame.
- **One ticket per incident:** contact that goes on (scraping along a wall, two cars
  pressed together) counts once; a new ticket needs 1 s without pit impacts
  (`incident_gap`). A separate later impact is a new ticket.
- **Not tickets:** harmless touches below the thresholds, and every contact on the
  racing road (including the divider's racing-road side).
- **Fine:** $100 (`collision_fine`). The human in a garage race pays it at settlement
  (shown on the results and the garage, never below $0). Everyone else, rivals
  included, gets the ticket and its statistics only; there is no time penalty.
- **Banner** (the human): "PIT LANE VIOLATION! / PIT COLLISION - FINE $100" (or
  "- TICKET" without money).
- **Kill feed:** `NAME [ticket icon] PIT COLLISION` (`ui/ticket`). No victim; K, D and
  the tombstone count are unchanged.
- **Announcer:** the user's recording, which says "Pit lane violation" (checked with a
  speech-recognition pass; it names no offence, so it suits collisions), through the
  Voice Director: one speaker at a time, cooldowns, music ducking, once per ticket.
  It can be overridden at `custom/audio/voice/announcer_pit_violation.*`; the game
  works without it.

## AI

- **Same rules:** rivals obey the limiter and get the same collision tickets; no
  invisible service and no immunity.
- **Overrides** (`pit_speeding`): Rocco 0.35, Dante 0.15, Finn 0.1, Maya 0.05, Nina
  0.03, Victor 0.002, Greta never (three times as likely in a late podium fight).
  Speeding alone is never punished, but an overriding rival brakes late for its bay
  and can arrive too fast: Rocco is the one most likely to earn a collision ticket.
- **Pit strategy:** before the entry a rival weighs condition against its
  `pit_threshold` (raised for long races), laps to go (no stop on the last lap) and
  its `pit_stay_out_chance`.
- **Bays:** on reaching the pit branch a stopping rival reserves a free bay it can
  still turn into (host-authoritative; a human who stops in that bay first gets it
  and the rival picks again). It drives the through-lane at the limiter, turns into
  its bay, stops, waits out the service, then steers back into the through-lane and
  merges. Beside the bays a rival may use an empty bay's apron to pass a car stopped
  in the through-lane.
- **Pit full:** the rival waits short of the bays for up to `pit_patience` seconds
  for one to come free: Victor and Greta 5, Hank 4, Nina 3, Ellie and Maya 2, Dante
  and Finn 1, Rocco 0 (never waits). Then it gives up the stop and drives on.
- **Split sections:** before each fork, a rival picks a lane from route time, traffic
  (`route_traffic_weight`) and temperament (`route_whim`); Rocco takes the lane of a
  rival he is chasing.

## Weapons and the divider

Missiles explode on dividers (`CombatWorld.branch_layout`), as on barriers. Mines
stay where they were dropped.

## Network (protocol 6)

- **Pit state:** every snapshot carries each car's packed pit state: limiter,
  overridden, serviced, service progress and the bay it holds. Bay frames and "PIT
  FULL" on the client come from it.
- **Client's own car:** follows the host's limiter.
- **Bays:** only the host assigns them (the first car stopped in a free bay), so two
  players can never hold or be serviced in the same bay.
- **Override:** a client's double tap travels as a running total in INPUT, so it is
  delivered exactly once. The host grants it, judges collisions, issues tickets and
  does all repairs.
- **Ticket events:** they reach the client's kill feed and announcer through the
  reliable EVENTS channel.

## Vehicle lights at night (`LightingPilot`)

- **Headlights and taillights:** every car has two headlight beams and two red
  taillights. This includes junkers and won cars in their original colours.
- **Lamp anchors** (`LightingPilot.lamp_anchors()`): front-left, front-right,
  rear-left and rear-right, placed a little in from the corners of the shared
  64 × 36 car outline (nose +X), never read from the drawing. Any body drawing gets
  the same lamps; only its nose direction matters (the art contract: nose right).
- **Fixed 2026-11-22:** the high beam started about 58 px behind its proper place
  (behind the car's centre), so on fast clear straights the light seemed to come
  from the back of the car. Godot scales a light's texture but not its offset; the
  offset now grows with the beam (`beam_offset`). Evidence:
  `docs/artwork/night_lights_before_after.jpg`; tests `test_vehicle_lights.gd`
  (eight headings, both light modes, high beam, a custom body of another size,
  brake lights).
- **Brake lights:** brighter while the car slows hard (more than 110 px/s²). This is
  measured from the car's movement, so it also works for a network client's cars.
- **Automatic high beams:**
  - **On:** above 55 % of top speed, with no car within 560 px in the beam and the road
    straight for 520 px ahead.
  - **Dip:** for traffic or a bend. Blending takes about 0.3 s, and the state is checked
    ten times a second per car.
- **Settings → DYNAMIC VEHICLE LIGHTS:**
  - Saved in `user://settings.cfg` as `[video] dynamic_vehicle_lights`.
  - **On:** real 2D lights, one twin-beam headlight light and one twin-lamp tail light
    per car.
  - **Off:** a cheap fallback with additive glow sprites and no light passes.
  - In both modes, the lamp lenses are small additive sprites.
- **Environments:** Wasteland Night is darker so the headlights carry through the
  rain; Winter Night is blue moonlight with warm lamps and snow crossing the beams.
- **No effect on the race:** lighting is presentation only. A race is bit-identical
  with lighting on or off (`test_lighting_pilot.gd`).

## Measurements (2026-11-17, before = fc5e1f7, after = this update)

### AI simulations

Ten-rival spectator races, Green Valley, seed 811, one race per cell. Columns:
- race time (s);
- DNFs;
- mean condition of the finishers;
- barrier contacts;
- car contacts;
- after only: pit stops / planned stops, tickets, and split-lane use (left : right
  lane passes).

| Circuit | Laps | Armed | Before | After | Stops, tickets, splits |
|---|---|---|---|---|---|
| Kestrel Ridge | 3 | no | 108 s, 0, 98 %, 33, 271 | 109 s, 0, 97 %, 36, 265 | 0, 0, 9 : 18 |
| Kestrel Ridge | 3 | yes | 129 s, 1, 53 %, 91, 251 | 129 s, 1, 44 %, 60, 161 | 0 / 1, 0, 15 : 17 |
| Kestrel Ridge | 7 | no | 244 s, 0, 98 %, 76, 293 | 245 s, 0, 97 %, 81, 290 | 0, 0, 33 : 30 |
| Kestrel Ridge | 7 | yes | 263 s, 4, 39 %, 98, 224 | 288 s, 1, 53 %, 117, 175 | 7 / 8, 0, 35 : 29 |
| Kestrel Ridge | 20 | no | 687 s, 0, 98 %, 189, 344 | 688 s, 0, 97 %, 220, 340 | 0, 0, 96 : 87 |
| Kestrel Ridge | 20 | yes | 699 s, 4, 61 %, 220, 274 | 745 s, 4, 57 %, 202, 441 | 6 / 11, 2, 51 : 64 |
| Kestrel Ridge | 50 | no | 1708 s, 0, 94 %, 486, 398 | 1714 s, 0, 96 %, 531, 378 | 0, 0, 242 : 211 |
| Kestrel Ridge | 50 | yes | 1724 s, 5, 46 %, 569, 206 | 1770 s, 4, 59 %, 574, 469 | 26 / 29, 5, 131 : 135 |
| Larkspur Ring | 3 | no | 103 s, 0, 100 %, 25, 93 | 103 s, 0, 100 %, 24, 86 | 0, 0, 11 : 16 |
| Larkspur Ring | 3 | yes | 119 s, 0, 56 %, 58, 119 | 135 s, 0, 50 %, 54, 144 | 2 / 3, 2, 16 : 17 |
| Larkspur Ring | 7 | no | 234 s, 0, 100 %, 50, 101 | 234 s, 0, 100 %, 53, 95 | 0, 0, 33 : 30 |
| Larkspur Ring | 7 | yes | 255 s, 4, 55 %, 100, 304 | 286 s, 2, 56 %, 112, 215 | 5 / 6, 2, 32 : 32 |
| Larkspur Ring | 20 | no | 658 s, 0, 99 %, 137, 154 | 658 s, 0, 98 %, 144, 118 | 0, 0, 94 : 87 |
| Larkspur Ring | 20 | yes | 683 s, 4, 37 %, 162, 336 | 734 s, 4, 55 %, 108, 275 | 13 / 20, 2, 55 : 68 |
| Larkspur Ring | 50 | no | 1635 s, 0, 99 %, 341, 183 | 1637 s, 0, 96 %, 350, 161 | 0, 0, 230 : 223 |
| Larkspur Ring | 50 | yes | 1645 s, 5, 63 %, 290, 213 | 1749 s, 6, 53 %, 254, 252 | 19 / 29, 4, 105 : 103 |
| Ravenhook | 3 | no | 115 s, 0, 99 %, 27, 134 | 115 s, 0, 98 %, 39, 100 | 0, 0, 15 : 12 |
| Ravenhook | 3 | yes | 143 s, 3, 33 %, 104, 211 | 142 s, 0, 48 %, 66, 226 | 2 / 2, 0, 19 : 12 |
| Ravenhook | 7 | no | 262 s, 0, 99 %, 68, 143 | 263 s, 0, 97 %, 92, 109 | 0, 0, 34 : 29 |
| Ravenhook | 7 | yes | 282 s, 3, 38 %, 104, 208 | 285 s, 5, 59 %, 59, 110 | 2 / 5, 1, 24 : 13 |
| Ravenhook | 20 | no | 742 s, 0, 99 %, 201, 243 | 740 s, 0, 96 %, 246, 168 | 0, 0, 118 : 64 |
| Ravenhook | 20 | yes | 759 s, 5, 33 %, 203, 157 | 806 s, 6, 54 %, 190, 197 | 5 / 10, 1, 40 : 30 |
| Ravenhook | 50 | no | 1850 s, 0, 93 %, 506, 1195 | 1845 s, 0, 90 %, 558, 828 | 0, 0, 288 : 165 |
| Ravenhook | 50 | yes | 1851 s, 7, 33 %, 225, 358 | 1881 s, 7, 48 %, 201, 305 | 8 / 20, 2, 79 : 56 |

**Reading the table:**
- **Unarmed races** are essentially unchanged: race time within 0.5 %.
- **Armed races** run 0–7 % longer because of pit stops. Finishers end with more
  condition (e.g. Larkspur 20 laps, 37 → 55 %). DNFs vary race to race and show no
  systematic change (one seed per cell).
- **Pit stops:** rivals pit only when damaged. Planned stops that were not made are
  mostly aborted entries (a car shoved wide before the divider) or cars that retired
  first.
- **Tickets:** 0–5 per race, mostly Rocco.
- **Lanes:** both split lanes are used on every circuit. Ravenhook's wide left lane is
  preferred, about 1.5–2 : 1.
- **Stuck rivals found and fixed:** the first run of this table found rivals pinned on
  the pit divider (6,920 barrier contacts in one armed 50-lap Kestrel race; fixed:
  rivals follow the lane they are in). After the fix, barrier contacts are back to the
  "before" level.

### Performance

Night, spectating, software OpenGL (llvmpipe, no GPU), measured while other jobs
were running, so the figures are relative only:

| Version | Day | Night |
|---|---|---|
| Before (single glow per car) | 39.0 fps | 24.5 fps |
| After, DYNAMIC VEHICLE LIGHTS on | 35.8 fps | 19.6–21.2 fps |
| After, DYNAMIC VEHICLE LIGHTS off | — | 26.1 fps |

The fallback is cheaper than the old single glow.

## Measurements: Pit Lane Refinement (2026-11-17)

Ten-rival spectator races, Green Valley, seed 811 (crowd: 812 unarmed). In the crowd
runs, every rival's condition is set to 22 % after 40 s, so the whole field wants the
pits at about the same time.

Columns:
- race time;
- DNFs;
- stops made / planned;
- collision tickets;
- barrier contacts;
- most bays held at once;
- time with all three bays held;
- waits / stops given up;
- longest single stay in the pit lane.

| Circuit | Laps | Armed | Time | DNF | Stops | Tickets | Barriers | Bays | Full | Waits / gave up | Longest |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Kestrel Ridge | 7 crowd | no | 258 s | 0 | 8 / 10 | 2 | 131 | 3 | 8.1 s | 2 / 2 | 12.9 s |
| Kestrel Ridge | 7 crowd | yes | 297 s | 3 | 8 / 13 | 5 | 123 | 3 | 0.1 s | 0 / 2 | 15.3 s |
| Larkspur Ring | 7 crowd | no | 258 s | 0 | 8 / 15 | 3 | 104 | 3 | 8.9 s | 7 / 7 | 16.0 s |
| Larkspur Ring | 7 crowd | yes | 300 s | 2 | 11 / 16 | 4 | 218 | 3 | 4.6 s | 0 / 2 | 13.3 s |
| Ravenhook | 7 crowd | no | 276 s | 0 | 8 / 10 | 3 | 101 | 3 | 8.8 s | 2 / 2 | 12.1 s |
| Ravenhook | 7 crowd | yes | 322 s | 3 | 11 / 18 | 5 | 127 | 3 | 0.6 s | 2 / 2 | 17.1 s |
| Kestrel Ridge | 7 | yes | 302 s | 3 | 7 / 12 | 3 | 113 | 2 | 0 | 0 / 1 | 13.5 s |
| Larkspur Ring | 7 | yes | 299 s | 2 | 6 / 7 | 1 | 168 | 2 | 0 | 0 / 0 | 15.6 s |
| Ravenhook | 7 | yes | 312 s | 3 | 6 / 9 | 2 | 117 | 3 | 0.1 s | 0 / 2 | 18.6 s |
| Kestrel Ridge | 20 | yes | 718 s | 5 | 5 / 5 | 0 | 56 | 1 | 0 | 0 / 0 | 9.9 s |
| Larkspur Ring | 20 | yes | 701 s | 6 | 6 / 11 | 2 | 112 | 2 | 0 | 0 / 1 | 13.7 s |
| Ravenhook | 20 | yes | 804 s | 3 | 9 / 10 | 1 | 295 | 2 | 0 | 0 / 0 | 15.3 s |
| Kestrel Ridge | 50 | yes | 1791 s | 5 | 17 / 21 | 4 | 454 | 2 | 0 | 0 / 0 | 15.2 s |
| Larkspur Ring | 50 | yes | 1690 s | 4 | 9 / 15 | 4 | 392 | 2 | 0 | 0 / 0 | 16.4 s |
| Ravenhook | 50 | yes | 1907 s | 5 | 12 / 17 | 4 | 574 | 3 | 0.5 s | 0 / 0 | 12.4 s |
| Kestrel Ridge | 50 | no | 1709 s | 0 | 0 | 0 | 504 | 0 | 0 | 0 / 0 | – |
| Larkspur Ring | 50 | no | 1637 s | 0 | 0 | 0 | 350 | 0 | 0 | 0 / 0 | – |
| Ravenhook | 50 | no | 1845 s | 0 | 0 | 0 | 558 | 0 | 0 | 0 / 0 | – |

**Reading the table:**
- **No jams:** the longest stay in any pit lane was 18.6 s (entry, turn-in, 6 s
  service, exit). Every crowd run used all three bays at once, and the pit stayed full
  for up to 9 s. Rivals waited, took a freed bay or gave up and drove on.
- **Unarmed 50-lap races:** unchanged by the refinement (no stops; barrier and car
  contacts as before).
- **Planned stops not made:** mostly a rival shoved wide before the divider (the stop
  is abandoned), a rival retiring first, or a rival giving up when the pit is full.
- **Collision tickets:** 0–5 per race. Speeding alone never gives one.
- **Barrier contacts around the bays:** at normal levels after three AI fixes found in
  these runs. The Ravenhook 50-lap armed count is spread round the circuit; only 33
  are near the bays.

**AI faults found by these simulations and fixed:**
- Turning in before the bay apron had opened: about 1,000 contacts per race.
- Giving up on the first pit tick: Rocco never stopped.
- Stopping short of the bay, then rolling into the stub.
- Waiting behind a car being serviced after its own service.
- Stubs too deep: 737 contacts.
- A shoved victim ticketed.

## Measurements: roomier bays (Personality & Polish, 2026-11-17)

Ten-rival spectator races on the enlarged pits, seed 811 (crowd unarmed: 812). Every
run finished without a jam.

| Run | Stops / planned | Most bays at once | Pit full | Longest stay in the pit lane |
|---|---|---|---|---|
| Crowd, 7 laps, armed (each circuit) | 8 / 12 – 9 / 14 | 2–3 | up to 1.3 s | 15.6–17.3 s |
| Crowd, 7 laps, unarmed (each circuit) | 8 / 10 – 8 / 19 | 2–3 | up to 3.0 s | 12.6–18.0 s |
| 20 laps, armed (each circuit) | 8 / 11 – 15 / 22 | 1–2 | – | 14.1–16.1 s |
| 50 laps, armed: Kestrel / Larkspur / Ravenhook | 20 / 25, 11 / 14, 18 / 21 | 3 / 1 / 2 | 1.1 s | 13.2–17.1 s |

**What changed against the earlier, smaller bays:**
- **Barrier contacts around the bays:** about 10–30 per race.
- **Stops made:** more of the planned stops are completed in long races (Kestrel 50
  laps: 20 of 25, up from 17 of 21 in proportion).
- **Collision tickets:** 1–5 per race.
- **Unchanged:** stops not made still come mostly from rivals giving up when the pit
  is full, or being shoved wide at the entry.
