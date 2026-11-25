class_name JumpRules
extends Resource
## J3 (experimental): how a car flies off a ramp. PROVISIONAL numbers; the
## original's jump behaviour is not verified. default_jump_rules.tres.

## Upward speed at the lip per unit of speed along the road (the ramp's
## steepness): vz = ramp_slope * speed.
@export var ramp_slope := 0.5
## Pull back down (px/s^2 of "height"). Flight time = 2 * vz / gravity, so the
## distance flown = 2 * ramp_slope * speed^2 / gravity (about 196 px at the
## default top speed of 420 px/s).
@export var gravity := 900.0
## Seconds a car that drops into the gap stays down before it is set back on
## the road just past the gap.
@export var recovery_time := 2.0
## Where a recovered car is set down, past the end of the gap (px).
@export var recovery_offset := 40.0


## Distance (px) flown from the lip at this speed along the road.
func flight_distance(speed: float) -> float:
	return 2.0 * ramp_slope * maxf(speed, 0.0) * maxf(speed, 0.0) / gravity


## Lowest speed along the road that clears a gap of this length.
func clearing_speed(gap: float) -> float:
	return sqrt(gap * gravity / (2.0 * ramp_slope))
