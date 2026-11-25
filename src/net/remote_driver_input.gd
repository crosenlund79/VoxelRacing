class_name RemoteDriverInput
extends DriverInput
## A human driving from another computer (M5.1). The host feeds it the
## client's tick-stamped commands; it then behaves exactly like a local human
## (same braking after the flag, same weapon conditions). Weapon presses arrive
## as running totals, so a lost, repeated or late packet can never fire a
## weapon twice or lose a press: only the increase since the last applied
## total becomes shots.

var _tick := -1
var _steer := 0.0
var _fire := false
var _front_total := 0
var _rear_total := 0
var _front_used := 0
var _rear_used := 0
## Pit-limiter override gestures, as a running total (exactly once each).
var _pit_total := 0
var _pit_used := 0


func _init(p_racer_id: int) -> void:
	racer_id = p_racer_id


func is_human() -> bool:
	return true


## One received command. Older ticks than the newest seen are ignored.
func receive(tick: int, steer: float, fire: bool, front_total: int, rear_total: int, pit_total: int = 0) -> void:
	if tick <= _tick:
		return
	_pit_total = maxi(_pit_total, pit_total)
	_tick = tick
	_steer = clampf(steer, -1.0, 1.0)  # shaped / proportional on the client (SteerShaper)
	_fire = fire
	_front_total = maxi(_front_total, front_total)
	_rear_total = maxi(_rear_total, rear_total)


func last_tick() -> int:
	return _tick


## New race: presses made before the start are not carried into it.
func begin_race(_seed: int) -> void:
	_front_used = _front_total
	_rear_used = _rear_total
	_pit_used = _pit_total


func drive(race: Node, _step: float) -> Dictionary:
	var car: Car = race.cars[racer_id]
	if race.session.racers[racer_id].is_finished():
		return {"steer": 0.0, "fire": car.model.control_mode == CarModel.ControlMode.FIRE_TO_BRAKE}
	var over := _pit_total > _pit_used  # the host still decides whether it counts (PitWorld)
	_pit_used = _pit_total
	return {"steer": _steer, "fire": _fire, "pit_override": over}


func discard_pending_shots() -> void:
	_front_used = _front_total
	_rear_used = _rear_total


## One shot per new press (at most one per slot per tick, like a local player).
func weapons(race: Node, _step: float, _states: Array) -> Dictionary:
	var out := {"front": false, "rear": false}
	var can: bool = race.session.state == RaceSession.State.RACING and not race.combat.is_wrecked(racer_id) \
		and not race.session.racers[racer_id].is_finished()
	if _front_used < _front_total:
		_front_used += 1
		out.front = can
	if _rear_used < _rear_total:
		_rear_used += 1
		out.rear = can
	return out
