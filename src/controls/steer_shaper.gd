class_name SteerShaper
extends RefCounted
## Human steering input shaping (keyboard and controller alike; the car's
## driving model is unchanged and shared with the AI).
##
## Diagnosis (2026-11-17): steering is a turn rate (210 deg/s at full input)
## and a key is -1 / 0 / +1, so even a short 80-100 ms tap turned the car
## 17-21 deg and grip then pulled the car sideways: on long straights small
## corrections felt like yanking the wheel. Now the command builds up to the
## input over a short time that grows with speed (RAMP_SLOW at a standstill,
## RAMP_FAST at top speed), so a tap is a small correction while a held key
## still reaches full lock almost at once; releasing (or reversing) takes
## effect immediately, so the car settles and corners are not delayed.

## Seconds from 0 to full steering at a standstill and at top speed.
const RAMP_SLOW := 0.03
const RAMP_FAST := 0.14

var value := 0.0


## One tick: raw input (-1 .. 1, a stick may be partial), the car's speed as a
## share of its top speed (0 .. 1) and the tick length. Returns the command.
func step(raw: float, speed_share: float, delta: float) -> float:
	raw = clampf(raw, -1.0, 1.0)
	if raw == 0.0 or signf(raw) != signf(value):
		value = 0.0  # released or reversed: at once
	elif absf(raw) < absf(value):
		value = raw  # less steering: at once
	var ramp := lerpf(RAMP_SLOW, RAMP_FAST, clampf(speed_share, 0.0, 1.0))
	value = move_toward(value, raw, delta / ramp)
	return value


func reset() -> void:
	value = 0.0
