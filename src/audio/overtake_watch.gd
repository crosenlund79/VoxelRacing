class_name OvertakeWatch
extends RefCounted
## Confirmed overtakes of a human by a rival, from race distance (laps
## included, so lap changes and lapping never look like passes). A pass counts
## only when the rival, having trailed the human by at least `margin` for
## `confirm` seconds, then leads by at least `margin` for `confirm` seconds:
## position jitter, side-by-side running and brief swaps are ignored. A car
## whose race distance jumps (a jump recovery, a network correction) restarts
## its comparisons without an event. Pure logic, no scene.

const TELEPORT := 150.0

var margin := 24.0
var confirm := 0.6
var _pairs := {}
var _last := {}


func reset() -> void:
	_pairs.clear()
	_last.clear()


## distances: racer id -> race distance now, for every eligible car (cars
## that finished, retired or are not racing are left out: their pairs are
## forgotten). quiet: track positions but report nothing (race start).
## Returns [{"human": id, "rival": id}] for overtakes confirmed now.
func update(now: float, humans: Array, rivals: Array, distances: Dictionary, quiet: bool = false) -> Array:
	var out: Array = []
	var jumped := {}
	for id in distances:
		if _last.has(id) and absf(distances[id] - _last[id]) > TELEPORT:
			jumped[id] = true
		_last[id] = distances[id]
	for h in humans:
		for r in rivals:
			var key := Vector2i(h, r)
			if not distances.has(h) or not distances.has(r):
				_pairs.erase(key)
				continue
			var d: float = distances[r] - distances[h]
			var side := 1 if d > margin else (-1 if d < -margin else 0)
			if not _pairs.has(key) or jumped.has(h) or jumped.has(r):
				_pairs[key] = {"confirmed": side, "pending": side, "since": now}
				continue
			var st: Dictionary = _pairs[key]
			if side == 0:
				continue
			if side != st.pending:
				st.pending = side
				st.since = now
			if now - st.since >= confirm and side != st.confirmed:
				if st.confirmed == -1 and side == 1 and not quiet:
					out.append({"human": h, "rival": r})
				st.confirmed = side
	return out
