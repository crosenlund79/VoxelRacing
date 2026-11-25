# M3 — manual combat checklist

Run the project (F5). On the title, **WEAPONS: ON / NO GUNS** sets the option for racing and spectating (saved). On the GET READY panel, **Up / Down** toggles it as well. Numbers are provisional; note what feels different from Super Cars II.

Controls (original manual): joystick **Forward / Up** = front weapon, **Backwards / Down** = rear weapon, **Fire** = accelerate or brake depending on the mode. Keyboard: Up / W and Down / S.

## No Guns
- [ ] Nobody fires; driving, bumping and AI racing feel exactly as before (M2.3).
- [ ] The HUD shows no ammunition; spectator history shows "off" for these races.

## Weapons ON — your car
- [ ] HUD shows the missile and mine icons with ammunition (5 each by default).
- [ ] Up fires a missile straight ahead; it destroys the first car it hits, or explodes at the barrier / after a short flight; cars can dodge it.
- [ ] Down drops a mine behind you; it blinks faster before it explodes after about 3 s, destroying any car close to it (including yours if you stop on it).
- [ ] With no ammunition left, Up / Down only gives an empty click.
- [ ] When your car is destroyed it stops, darkens and smokes, "DESTROYED 2.9…" counts down, then you carry on from the same spot; you are briefly flashing and cannot be destroyed again straight away.
- [ ] Both Fire to Accelerate and Fire to Brake still drive as before.

## Weapons ON — rivals (same weapons and ammunition as you)
- [ ] Rivals fire missiles at cars ahead and drop mines for cars behind; they run out of ammunition like you.
- [ ] Victor saves rounds until the last lap; Rocco fires a lot, sometimes at nothing; Ellie gets trigger-happy under pressure; Hank drops lots of mines and hits back after being destroyed; Maya picks off slow or recovering cars; Dante tries long shots; Greta spreads her shots over the laps; Finn is unpredictable; Nina waits for point-blank shots.
- [ ] Every armed race still finishes with all cars classified.

## Spectating with weapons
- [ ] Armed spectator races auto-restart as before; F (fast) keeps working (effects/sounds reduced while fast).
- [ ] Race History shows an "ON"/"off" weapons row for every race; the title shows how many races had weapons; Position Counts unchanged.

## Presentation
- [ ] Missiles (cream with red band) fly with a flame; homing/super missiles would be tinted (not in the default loadout).
- [ ] Explosions show a painted blast and play a boom; launches whoosh; mines clunk and beep.
- [ ] Replace `custom/graphics/weapons/missile.png`, `custom/graphics/weapons/mine.png` (2-frame strip), `custom/graphics/fx/blast.png`, or `custom/audio/weapons/*.ogg|.wav` and restart: overrides are used (see docs/ASSET_SPECS.md).
