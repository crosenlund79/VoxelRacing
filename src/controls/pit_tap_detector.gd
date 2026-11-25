class_name PitTapDetector
extends RefCounted
## The pit-limiter override gesture: two separate presses of the accelerator
## (the Fire binding, keyboard or controller) within a short window while in
## the pit lane. A press already held when the car enters the lane does not
## count until it has been released, so holding the accelerator through the
## entry never overrides the limiter by accident.

var _time := 0.0
var _in_lane := false
var _was_down := false
var _armed := false
var _first_press := -INF


## One tick: is the accelerator down, is the car in the pit lane, the tick
## length and the double-tap window. True on the tick the override is asked for.
func step(down: bool, in_lane: bool, delta: float, window: float) -> bool:
	_time += delta
	if not in_lane:
		_in_lane = false
		_was_down = down
		return false
	if not _in_lane:  # just entered: a held press waits for its release
		_in_lane = true
		_armed = not down
		_first_press = -INF
	var pressed := down and not _was_down
	_was_down = down
	if not down:
		_armed = true
	if not pressed or not _armed:
		return false
	if _time - _first_press <= window:
		_first_press = -INF
		return true
	_first_press = _time
	return false
