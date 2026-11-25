class_name PitWorld
extends RefCounted
## Pit lanes for one race (pure per-car state, host-authoritative): the pit
## limiter and its override, collision tickets in the pit area, and free
## service in the numbered service bays. The race scene feeds it each tick
## where every car is (in the pit lane / in which bay), its speed and
## condition; it answers with speed caps, repairs and tickets.
##
## One pit-lane traversal = from entering the pit lane proper (beside the
## divider) to leaving it. Per traversal: at most one override and one
## service. Leaving the lane and coming back in a later lap starts a new
## traversal; nudging out of a bay and back in does not.
##
## Pit Lane Refinement (2026-11-17): overriding the limiter is allowed and
## never punished; meaningful collisions in the pit area earn a ticket
## instead. Service bays hold one car each: a car occupies a free bay by
## being in it (whether it wants service or not) and keeps it until it has
## physically left it (Personality & Polish, 2026-11-17).

var rules: PitRules
## Per car.
var in_lane := PackedByteArray()
var overridden := PackedByteArray()
var served := PackedByteArray()
## Seconds of service done (0 = none in progress).
var service := PackedFloat32Array()
## Fines ($) per car this race: the garage human pays them at settlement;
## for everyone else they are statistics only.
var fines := PackedInt32Array()
## Per car: 1 = pays fines with money (the human in a garage race).
var pays_fines := PackedByteArray()
## Service in the pits is allowed in this race (off in Knockout).
var service_enabled := true
## Pit stops and collision tickets per car (statistics, tests).
var stops := PackedInt32Array()
var tickets := PackedInt32Array()
## Seconds until a new pit-area impact counts as a new incident (per car).
var _incident_left := PackedFloat32Array()
## Service bays: the car holding each bay (-1 = free), and a rival's
## reservation while it drives there (soft: a car that stops in a free bay
## first gets it, and the rival chooses again).
var bay_owner := PackedInt32Array()
var bay_reserved := PackedInt32Array()


func _init(p_rules: PitRules, car_count: int, bays: int = 3) -> void:
	rules = p_rules
	for arr in [in_lane, overridden, served, pays_fines]:
		arr.resize(car_count)
	for arr in [service, _incident_left]:
		arr.resize(car_count)
	for arr in [fines, stops, tickets]:
		arr.resize(car_count)
	bay_owner.resize(bays)
	bay_reserved.resize(bays)
	reset()


func reset() -> void:
	for arr in [in_lane, overridden, served]:
		arr.fill(0)
	service.fill(0.0)
	_incident_left.fill(0.0)
	fines.fill(0)
	stops.fill(0)
	tickets.fill(0)
	bay_owner.fill(-1)
	bay_reserved.fill(-1)


func car_count() -> int:
	return in_lane.size()


func bay_count() -> int:
	return bay_owner.size()


## The limiter holds this car now (in the lane and not overridden).
func limiter_on(id: int) -> bool:
	return in_lane[id] == 1 and overridden[id] == 0


## Service progress 0 .. 1 (0 = none).
func service_progress(id: int) -> float:
	return clampf(service[id] / maxf(rules.service_time, 0.01), 0.0, 1.0)


## A deliberate override (a human's double tap, a rival's choice): only in the
## pit lane, once per traversal. No ticket: speeding is allowed, crashing is not.
func request_override(id: int) -> bool:
	if in_lane[id] == 0 or overridden[id] == 1:
		return false
	overridden[id] = 1
	return true


## The bay this car holds (-1 = none).
func bay_of(id: int) -> int:
	return bay_owner.find(id)


## A bay this car may use: free, and not reserved by someone else.
func bay_available(k: int, id: int) -> bool:
	return bay_owner[k] == -1 and (bay_reserved[k] == -1 or bay_reserved[k] == id)


## Number of bays this car could still use now.
func free_bays(id: int) -> int:
	var n := 0
	for k in bay_count():
		n += int(bay_available(k, id))
	return n


## A rival picks the first bay it may use (keeps its reservation while that
## bay stays available); usable (optional, per bay) leaves out bays it can no
## longer turn into. Returns the bay, -1 when every bay is taken.
func reserve_bay(id: int, usable: Array[bool] = []) -> int:
	var mine := bay_reserved.find(id)
	if mine >= 0 and bay_available(mine, id):
		return mine
	release_reservation(id)
	for k in bay_count():
		if bay_available(k, id) and (usable.is_empty() or usable[k]):
			bay_reserved[k] = id
			return k
	return -1


func release_reservation(id: int) -> void:
	for k in bay_count():
		if bay_reserved[k] == id:
			bay_reserved[k] = -1


## A meaningful impact by this car in the pit area. Contact that goes on (a
## car scraping along a wall, two cars pressed together) is one incident:
## a new ticket needs a gap of rules.incident_gap without impacts first.
## Returns the fine charged (> 0) for a new incident, 0 otherwise.
func collision(id: int) -> int:
	var fresh := _incident_left[id] <= 0.0
	_incident_left[id] = rules.incident_gap
	if not fresh:
		return 0
	tickets[id] += 1
	fines[id] += rules.collision_fine
	return rules.collision_fine


## One tick for one car. lane: in the pit lane; bay: the service bay it is in
## (-1 none); speed (px/s); condition and max_condition (points); out:
## retired (DNF) or not racing (no service, holds no bay).
## Returns the condition points to add (> 0 when a service just completed).
func step(id: int, lane: bool, bay: int, speed: float, condition: float, max_condition: float,
		out: bool, delta: float) -> float:
	_incident_left[id] = maxf(0.0, _incident_left[id] - delta)
	if lane and in_lane[id] == 0:  # a new traversal of the pit lane
		in_lane[id] = 1
		overridden[id] = 0
		served[id] = 0
		service[id] = 0.0
	elif not lane and in_lane[id] == 1:  # out of the pit lane
		in_lane[id] = 0
		service[id] = 0.0
		release_reservation(id)
	var held := bay_of(id)
	if held >= 0 and (held != bay or out):  # it has physically left its bay (or is out): free again
		bay_owner[held] = -1
		held = -1
		service[id] = 0.0
	if out:
		release_reservation(id)
	if not lane or bay < 0:
		return 0.0
	var stopped := speed <= rules.stopped_speed
	var can_serve := service_enabled and not out and served[id] == 0 and condition < max_condition
	if held < 0 and bay_owner[bay] == -1 and not out:  # (a retired car collides with nothing: no occupant)
		bay_owner[bay] = id  # occupied by being in it (serviced or not: a bay holds one car)
		held = bay
		release_reservation(id)
		for k in bay_count():  # a rival that had reserved it chooses again
			if k == bay and bay_reserved[k] != -1:
				bay_reserved[k] = -1
	if held == bay and stopped and can_serve:
		service[id] += delta
		if service[id] >= rules.service_time:
			service[id] = 0.0
			served[id] = 1
			stops[id] += 1
			return minf(rules.repair_points * max_condition / 100.0, max_condition - condition)
	else:
		service[id] = 0.0  # moving, or not its bay: the service is interrupted
	return 0.0


## Compact per-car state for network snapshots: bit 0 limiter on, bit 1
## overridden (in the lane), bit 2 serviced on this traversal, bits 3-7
## service progress (0 .. 31), bits 8-9 the bay it holds + 1 (0 = none).
func pack(id: int) -> int:
	var v := (1 if limiter_on(id) else 0) | ((in_lane[id] & overridden[id]) << 1) | ((in_lane[id] & served[id]) << 2)
	v |= int(round(service_progress(id) * 31.0)) << 3
	return v | ((bay_of(id) + 1) << 8)


## The bay held according to a packed state (-1 = none).
static func packed_bay(st: int) -> int:
	return ((st >> 8) & 3) - 1
