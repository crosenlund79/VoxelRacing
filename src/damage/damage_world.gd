class_name DamageWorld
extends RefCounted
## M6: every car's condition during one race. Pure and deterministic (no scene,
## no randomness): the race feeds it weapon destructions, barrier impacts and
## car contacts in tick order, and it reports when a car reaches zero (DNF).
## The same rules for every car; armour (a garage upgrade) scales damage down.

var rules: DamageRules
## Per car: condition (0 .. rules.max_condition), armour damage reduction
## (0 .. <1), retired (reached zero), seconds since retiring, seconds since the
## last damage (presentation; large when never hit).
var condition := PackedFloat32Array()
var armour := PackedFloat32Array()
var retired := PackedByteArray()
var retired_age := PackedFloat32Array()
var since_hit := PackedFloat32Array()
## Total damage taken this race per car (statistics / tests).
var taken := PackedFloat32Array()
var _pairs_this_tick := {}


func _init(p_rules: DamageRules, car_count: int) -> void:
	rules = p_rules
	for a in [condition, armour, retired, retired_age, since_hit, taken]:
		a.resize(car_count)
	reset()


## New race: every car at full condition, no armour.
func reset() -> void:
	condition.fill(rules.max_condition)
	armour.fill(0.0)
	retired.fill(0)
	retired_age.fill(0.0)
	since_hit.fill(999.0)
	taken.fill(0.0)
	_pairs_this_tick.clear()


func car_count() -> int:
	return condition.size()


## A car's condition and armour for this race (garage cars carry their damage).
func set_start(id: int, start_condition: float, armour_reduction: float) -> void:
	condition[id] = clampf(start_condition, 0.0, rules.max_condition)
	armour[id] = clampf(armour_reduction, 0.0, 0.95)


func fraction(id: int) -> float:
	return condition[id] / rules.max_condition


func is_retired(id: int) -> bool:
	return retired[id] == 1


func is_critical(id: int) -> bool:
	return not is_retired(id) and condition[id] <= rules.critical_condition


## Takes `amount` (before armour) off a car. Returns true when this damage
## retires it (condition reached zero now).
func damage(id: int, amount: float) -> bool:
	if amount <= 0.0 or is_retired(id):
		return false
	var dealt := amount * (1.0 - armour[id])
	condition[id] = maxf(0.0, condition[id] - dealt)
	taken[id] += dealt
	since_hit[id] = 0.0
	if condition[id] <= 0.0:
		retired[id] = 1
		retired_age[id] = 0.0
		return true
	return false


func weapon_hit(id: int, weapon: int) -> bool:
	return damage(id, rules.weapon_damage(weapon))


func wall_impact(id: int, speed: float) -> bool:
	return damage(id, rules.wall_damage(speed))


## A contact between cars a and b: both take the same damage (before their own
## armour), counted once per pair per tick. a_hurt / b_hurt: whether each car
## can take damage (a car that already finished cannot). Returns the cars it retires.
func car_impact(a: int, b: int, speed: float, a_hurt := true, b_hurt := true) -> Array[int]:
	var out: Array[int] = []
	var key := Vector2i(mini(a, b), maxi(a, b))
	if _pairs_this_tick.has(key):
		return out
	_pairs_this_tick[key] = true
	var amount := rules.car_damage(speed)
	if amount <= 0.0:
		return out
	if a_hurt and damage(a, amount):
		out.append(a)
	if b_hurt and damage(b, amount):
		out.append(b)
	return out


## End of a tick: timers advance, contact pairs may count again.
func step(dt: float) -> void:
	_pairs_this_tick.clear()
	for i in condition.size():
		since_hit[i] = minf(since_hit[i] + dt, 999.0)
		if retired[i] == 1:
			retired_age[i] += dt


## Exact state for determinism checks.
func state_snapshot() -> Array:
	return [condition, armour, retired]
