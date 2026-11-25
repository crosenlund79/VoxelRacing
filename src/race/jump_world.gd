class_name JumpWorld
extends RefCounted
## J3 (experimental): the jumps of a layout, per car, one fixed tick at a time.
## Deterministic and pure (no scene): a car crossing a ramp lip forwards takes
## off with an upward speed proportional to its speed along the road; it flies
## with the velocity it had (no steering, throttle or grip in the air) until its
## height comes back to zero. Touching down past the gap is a landing; touching
## down in the gap - or rolling into it on the ground - is a fall: the car stops
## and after recovery_time is set back on the road just past the gap.

var layout: TrackLayout
var rules: JumpRules
var path: ClosedPath

## Per car: flying, seconds in the air, upward speed at takeoff, the jump it
## is on, seconds left down in the gap, last arc distance.
var airborne := PackedByteArray()
var air_time := PackedFloat32Array()
var lift := PackedFloat32Array()
var jump_of := PackedInt32Array()
var down_left := PackedFloat32Array()
var _last_s := PackedFloat32Array()


func _init(p_layout: TrackLayout, p_rules: JumpRules, p_path: ClosedPath, car_count: int) -> void:
	layout = p_layout
	rules = p_rules
	path = p_path
	for arr in [airborne, air_time, lift, jump_of, down_left, _last_s]:
		arr.resize(car_count)
	reset()


func reset() -> void:
	airborne.fill(0)
	air_time.fill(0.0)
	lift.fill(0.0)
	jump_of.fill(-1)
	down_left.fill(0.0)
	_last_s.fill(-1.0)


func is_airborne(id: int) -> bool:
	return airborne[id] == 1


func is_down(id: int) -> bool:
	return down_left[id] > 0.0


## Current height above the road (0 on the ground).
func height(id: int) -> float:
	if airborne[id] == 0:
		return 0.0
	var t := air_time[id]
	return maxf(0.0, lift[id] * t - 0.5 * rules.gravity * t * t)


## Seconds the current flight lasts in total.
func flight_time(id: int) -> float:
	return 2.0 * lift[id] / rules.gravity


## Starts tracking a car from where it is (grid placement, after recovery).
func place(id: int, s: float) -> void:
	_last_s[id] = s


## One tick for one car. s: its arc distance along the road (unwrapped is
## fine), speed_along: its speed along the road's direction, active: it can
## drive (not wrecked). Returns "" or one of "takeoff", "landed", "fell",
## "recovered".
func step(id: int, dt: float, s: float, speed_along: float, active: bool) -> String:
	var w := fposmod(s, path.length)
	var prev := _last_s[id]
	_last_s[id] = w
	if airborne[id] == 1:
		air_time[id] += dt
		if air_time[id] < flight_time(id):
			return ""
		airborne[id] = 0
		var j := layout.jumps[jump_of[id]]
		if w < j.x + j.z:  # came down before the end of the gap
			down_left[id] = rules.recovery_time
			return "fell"
		jump_of[id] = -1
		return "landed"
	if down_left[id] > 0.0:
		down_left[id] = maxf(0.0, down_left[id] - dt)
		return "recovered" if down_left[id] <= 0.0 else ""
	if not active or prev < 0.0:
		return ""
	for k in layout.jumps.size():
		var j := layout.jumps[k]
		if prev < j.x and w >= j.x and w - prev < 100.0 and speed_along > 0.0:
			airborne[id] = 1
			air_time[id] = 0.0
			lift[id] = rules.ramp_slope * speed_along
			jump_of[id] = k
			return "takeoff"
		if w > j.x and w < j.x + j.z:  # on the ground in the gap (rolled in): falls
			jump_of[id] = k
			down_left[id] = rules.recovery_time
			return "fell"
	return ""


## The car is down in the ravine of a flyover jump (under it runs the road
## below: no collisions there, drawn on the ground level).
func is_down_in_flyover(id: int) -> bool:
	return is_down(id) and jump_of[id] >= 0 and layout.is_flyover(jump_of[id], path.length)


## Where a car that fell into jump k is set back on the road.
func recovery_distance(k: int) -> float:
	var j := layout.jumps[k]
	return j.x + j.z + rules.recovery_offset
