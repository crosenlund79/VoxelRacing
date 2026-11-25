# Milestone 1 — manual driving checklist

Run the project (F5 in the Godot 4.7 editor, main scene `src/main/main.tscn`). Mark each item **pass / fail / note**. Driving values are **provisional**; record how they differ from Super Cars II rather than fixing them here.

Controls: **Left/Right** (arrows, A/D, d-pad or left stick) steer; **Fire** (Space, Ctrl or pad A) is the single fire button. Up/down are unbound (weapons in the original).

## Start and mode selection
- [ ] Game opens on the circuit with the control-mode panel; the car is stationary just past the start/finish line, facing along the track.
- [ ] Left/Right switches between FIRE TO ACCELERATE and FIRE TO BRAKE; HUD shows the chosen mode.
- [ ] Fire starts the race and hides the panel; the timer starts.

## Fire to Accelerate
- [ ] Holding Fire accelerates from rest to a top speed.
- [ ] Releasing Fire slows the car automatically (brake), to a full stop; it never reverses.

## Fire to Brake
- [ ] The car accelerates automatically without Fire.
- [ ] Holding Fire brakes noticeably harder than releasing Fire does in the other mode.

## Steering and momentum
- [ ] Left/Right rotate the car relative to its own heading (car-relative, not screen directions).
- [ ] Turning at speed makes the car slide briefly before it follows its new heading.
- [ ] Note the turn speed and whether the car can turn while stationary (current default: yes) — compare with the original.

## Walls
- [ ] The car never passes through a barrier, at any angle or speed.
- [ ] A head-on hit bounces the car back slightly; a glancing hit scrapes along the wall losing some speed.
- [ ] The car never gets stuck in a barrier or corner.

## Laps and finish
- [ ] Crossing the start/finish line after a full lap increases the lap counter.
- [ ] Turning round and re-crossing the line, or cutting across the infield is not possible / does not count.
- [ ] After the last lap the FINISHED panel shows total and lap times; the car brakes to a stop without control.
- [ ] Fire on the FINISHED panel returns to mode selection at the start line.

## Camera and presentation
- [ ] The overhead camera keeps the car centred and scrolls with it; the view never rotates.
- [ ] Track, barriers, start line, car and HUD panels share the hand-painted style of `docs/art_refrence/`.
- [ ] No visible seams in road or grass tiling.

## Asset overrides (user files in `custom/`)
- [ ] Put a PNG at `custom/graphics/cars/car_player.png` (nose pointing right), restart: the car uses it, scaled to the same size.
- [ ] Replace it with a non-image file renamed `.png`, restart: the template car returns, and a warning appears in the Output panel.
- [ ] Delete it, restart: the template car is used.
- [ ] Exported Windows/Linux build: **pending** — no export was approved.
