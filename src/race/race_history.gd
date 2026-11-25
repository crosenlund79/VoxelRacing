class_name RaceHistory
extends RefCounted
## Finishing orders of completed spectator races for the current session only
## (nothing is saved). Fixed driver rows; one result per completed race.
## No points, rankings or progression.

## Driver ids in fixed row order.
var driver_ids: Array[int] = []
## results[r] = driver ids in finishing order for race r.
var results: Array = []
## weapons[r] = true when race r was run with weapons enabled.
var weapons: Array[bool] = []
## laps[r] = race length of race r.
var laps: Array[int] = []


func _init(p_driver_ids: Array[int]) -> void:
	driver_ids = p_driver_ids


func race_count() -> int:
	return results.size()


func add_race(finishing_order: Array[int], with_weapons: bool = false, lap_count: int = 3) -> void:
	results.append(finishing_order.duplicate())
	weapons.append(with_weapons)
	laps.append(lap_count)


func weapon_race_count() -> int:
	return weapons.count(true)


## 1-based finishing position of a driver in race r (0 if absent).
func position_in(race_index: int, driver_id: int) -> int:
	return results[race_index].find(driver_id) + 1


## counts[p - 1] = how many times the driver finished in position p.
func position_counts(driver_id: int) -> Array[int]:
	var counts: Array[int] = []
	counts.resize(driver_ids.size())
	counts.fill(0)
	for order in results:
		var p: int = order.find(driver_id)
		if p >= 0 and p < counts.size():
			counts[p] += 1
	return counts
