class_name CombatStats
extends RefCounted
## Kills, deaths and tombstones per car, and the kill feed's entries. Pure and
## deterministic; fed by the race scene from the existing events (weapon
## destructions, car contacts that did damage, retirements).
##   K: opponent cars destroyed (weapon destructions, also when they respawn;
##      and a retirement by collision damage that is attributable).
##   D: times the car was destroyed (every weapon destruction, own mine
##      included, and a retirement not caused by a weapon destruction).
##   T (tombstones): permanent eliminations (DNFs) caused: a destruction that
##      retires the car (counted once as a kill, plus the tombstone), or a
##      retirement from collision damage dealt by an opponent within
##      ATTRIBUTION_TIME. Walls, own weapons, unattributed wear and Knockout
##      eliminations give nobody a tombstone.

## Feed "weapon" for kills without a weapon (collision damage), and for
## Knockout eliminations / unattributed retirements.
const COLLISION := -1
const ELIMINATED := -2
const RETIRED := -3
## Feed "weapon" for a pit-lane collision ticket (no victim, no statistics).
const TICKET := -4
## Seconds a car's last damaging contact counts as the cause of its retirement.
const ATTRIBUTION_TIME := 4.0

var kills := PackedInt32Array()
var deaths := PackedInt32Array()
var tombstones := PackedInt32Array()
## Newest last: {attacker (-1 none), victim, weapon, tombstone, time}.
var feed: Array = []
## Per car: who last damaged it by contact, and when ({} none).
var _last_contact: Array = []
## The newest feed entry per victim from a weapon destruction (for a tombstone
## on the same destruction).
var _last_destroy: Dictionary = {}


func _init(car_count: int) -> void:
	for arr in [kills, deaths, tombstones]:
		arr.resize(car_count)
	_last_contact.resize(car_count)
	reset()


func reset() -> void:
	kills.fill(0)
	deaths.fill(0)
	tombstones.fill(0)
	feed.clear()
	_last_destroy.clear()
	for i in _last_contact.size():
		_last_contact[i] = {}


## A weapon destroyed `victim` (attacker = the weapon's owner).
func on_destroyed(victim: int, attacker: int, weapon: int, time: float) -> void:
	deaths[victim] += 1
	var by := attacker if attacker >= 0 and attacker != victim else -1
	if by >= 0:
		kills[by] += 1
	var entry := {"attacker": by, "victim": victim, "weapon": weapon, "tombstone": false, "time": time}
	feed.append(entry)
	_last_destroy[victim] = entry


## A contact between two cars damaged `victim`; `other` is held responsible
## if the victim retires soon after.
func on_contact(victim: int, other: int, time: float) -> void:
	if other >= 0 and other != victim:
		_last_contact[victim] = {"by": other, "time": time}


## `victim` is out of the race for good. by_weapon: the retirement came with a
## weapon destruction this tick (already counted as kill and death).
func on_retired(victim: int, time: float, by_weapon: bool) -> void:
	if by_weapon and _last_destroy.has(victim) and time - float(_last_destroy[victim].time) <= 1.0:
		var e: Dictionary = _last_destroy[victim]
		e.tombstone = e.attacker >= 0
		if e.attacker >= 0:
			tombstones[e.attacker] += 1
		return
	deaths[victim] += 1
	var c: Dictionary = _last_contact[victim]
	var by: int = c.by if not c.is_empty() and time - float(c.time) <= ATTRIBUTION_TIME else -1
	if by >= 0:
		kills[by] += 1
		tombstones[by] += 1
	feed.append({"attacker": by, "victim": victim, "weapon": COLLISION if by >= 0 else RETIRED,
		"tombstone": true, "time": time})


## Network client: the host named `by` as the culprit of a retirement this
## computer already counted unattributed (the DNF arrived before the event).
func attribute_retirement(victim: int, by: int) -> void:
	if by < 0 or by == victim:
		return
	for k in range(feed.size() - 1, -1, -1):
		var e: Dictionary = feed[k]
		if e.victim == victim and e.tombstone and e.attacker < 0 and e.weapon == RETIRED:
			e.attacker = by
			e.weapon = COLLISION
			kills[by] += 1
			tombstones[by] += 1
			return


## A pit-lane collision ticket: in the feed (offender only), no statistics.
func on_ticket(offender: int, time: float) -> void:
	feed.append({"attacker": offender, "victim": -1, "weapon": TICKET, "tombstone": false, "time": time})


## A Knockout elimination by position: in the feed, no statistics.
func on_eliminated(victim: int, time: float) -> void:
	feed.append({"attacker": -1, "victim": victim, "weapon": ELIMINATED, "tombstone": false, "time": time})


## [tombstones, kills, deaths] of a car.
func line(id: int) -> Array:
	return [tombstones[id], kills[id], deaths[id]]
