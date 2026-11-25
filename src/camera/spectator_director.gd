class_name SpectatorDirector
extends RefCounted
## Chooses which car the spectator camera follows: the chasing car of the
## closest battle still racing, held for a minimum time to avoid jumpy cuts.
## Presentation only; it never affects the race.
## The spectator can pick a driver (follow): the camera then stays on that
## driver until another is picked or a new race resets the choice.

## Minimum time on one car before cutting to another (s).
var min_hold := 4.0
var target_id := -1
var _held := 0.0
## True while a chosen driver is followed (automatic battle choice off).
var locked := false


## Follow this driver until told otherwise.
func follow(id: int) -> void:
	target_id = id
	locked = true
	_held = 0.0


## Neighbour of `current` in the fixed starting-grid order (dir -1 / +1, wrapping).
## If `current` is not on the grid: the first slot for +1, the last for -1.
static func grid_neighbour(grid: Array, current: int, dir: int) -> int:
	if grid.is_empty():
		return -1
	var i := grid.find(current)
	if i < 0:
		return grid[0] if dir > 0 else grid[-1]
	return grid[posmod(i + dir, grid.size())]


## cars: Array of {id, progress, finished}. Returns the id to follow.
func update(cars: Array, delta: float) -> int:
	_held += delta
	if locked and target_id >= 0:
		return target_id
	var current_running := false
	for c in cars:
		if c.id == target_id and not c.finished:
			current_running = true
	if target_id >= 0 and current_running and _held < min_hold:
		return target_id
	var best := choose(cars)
	if best >= 0 and best != target_id:
		target_id = best
		_held = 0.0
	return target_id


## The car behind in the closest gap between two running cars; the leader if
## only one is running; -1 if none.
static func choose(cars: Array) -> int:
	var running := cars.filter(func(c: Dictionary) -> bool: return not c.finished)
	if running.is_empty():
		return -1
	running.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.progress > b.progress)
	if running.size() == 1:
		return running[0].id
	var best_gap := INF
	var best_id: int = running[0].id
	for i in range(1, running.size()):
		var gap: float = running[i - 1].progress - running[i].progress
		if gap < best_gap:
			best_gap = gap
			best_id = running[i].id
	return best_id
