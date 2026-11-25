class_name RaceSession
extends RefCounted
## Race flow: choose mode -> race -> finished. In a normal race FINISHED means
## the player has finished; in spectator mode (no player car) it means every
## rival has finished. The race clock keeps running until every participating
## car has finished, so later finishers get their real times.
## Holds every racer's laps, live positions and the finishing order.
## Racer 0 is the player; the single-racer API (tracker, lap_times,
## checkpoint_reached(index)) refers to the player.
## Elapsed time and lap times are calibration aids, not claimed original features.

enum State { MODE_SELECT, RACING, FINISHED }

const PLAYER_ID := 0
## Racer id of the second human in two-player races (after the nine rivals).
const PLAYER_2_ID := 10

var state: State = State.MODE_SELECT
var control_mode: CarModel.ControlMode = CarModel.ControlMode.FIRE_TO_ACCELERATE
var racers: Array[RacerState] = []
var elapsed := 0.0
var finish_order: Array[int] = []
## Spectator mode: the player (racer 0) does not take part.
var spectator := false
## Racer ids driven by humans (single-player: just the player, id 0).
var human_ids: Array[int] = [PLAYER_ID]
## Racer ids not taking part in the current race (e.g. a rival sitting out).
var sitting_out: Array[int] = []
var _checkpoint_count: int
var _lap_count: int
var _names: PackedStringArray

## The player's lap tracker.
var tracker: LapTracker:
	get:
		return racers[PLAYER_ID].tracker
## The player's lap times.
var lap_times: Array[float]:
	get:
		return racers[PLAYER_ID].lap_times


## names[0] is the player; one racer is created per name.
func _init(checkpoint_count: int, lap_count: int, names: PackedStringArray = PackedStringArray(["YOU"])) -> void:
	_checkpoint_count = checkpoint_count
	_lap_count = lap_count
	_names = names
	reset()


func reset() -> void:
	state = State.MODE_SELECT
	elapsed = 0.0
	finish_order.clear()
	racers.clear()
	for i in _names.size():
		racers.append(RacerState.new(i, _names[i], human_ids.has(i), _checkpoint_count, _lap_count))


## Only allowed while choosing the mode.
func set_spectator(on: bool) -> void:
	if state == State.MODE_SELECT:
		spectator = on


func is_participating(racer_id: int) -> bool:
	if sitting_out.has(racer_id):
		return false
	return not (spectator and human_ids.has(racer_id))


## Humans for this session (before the start); rebuilds the racers.
func set_humans(ids: Array[int]) -> void:
	if state != State.MODE_SELECT:
		return
	human_ids = ids.duplicate()
	reset()


## Racers sitting out the next race (before the start).
func set_sitting_out(ids: Array[int]) -> void:
	if state == State.MODE_SELECT:
		sitting_out = ids.duplicate()


## True when every participating human has finished (or is out: DNF).
func humans_finished() -> bool:
	for id in human_ids:
		if is_participating(id) and not racers[id].is_done():
			return false
	return true


## Ends the race for the humans (safety net for a stuck human): results are
## shown; cars still running keep racing and are placed in running order.
func end_for_humans() -> void:
	if state == State.RACING:
		state = State.FINISHED


func participants() -> Array[RacerState]:
	var out: Array[RacerState] = []
	for r in racers:
		if is_participating(r.id):
			out.append(r)
	return out


func racer_count() -> int:
	return participants().size()


## Every participating car has finished or is out (DNF).
func all_finished() -> bool:
	for r in participants():
		if not r.is_done():
			return false
	return true


## Race length (laps); only changeable while choosing the mode. Rebuilds the racers.
func set_lap_count(laps: int) -> void:
	if state != State.MODE_SELECT or laps < 1:
		return
	_lap_count = laps
	reset()


func lap_count() -> int:
	return _lap_count


func toggle_mode() -> void:
	if state != State.MODE_SELECT:
		return
	control_mode = CarModel.ControlMode.FIRE_TO_BRAKE if control_mode == CarModel.ControlMode.FIRE_TO_ACCELERATE else CarModel.ControlMode.FIRE_TO_ACCELERATE


func start() -> void:
	if state == State.MODE_SELECT:
		state = State.RACING


func tick(delta: float) -> void:
	if state != State.MODE_SELECT and not all_finished():
		elapsed += delta


## Laps keep counting for every car until it finishes, also after the player finished.
func checkpoint_reached(index: int, racer_id: int = PLAYER_ID) -> LapTracker.Result:
	if state == State.MODE_SELECT or not is_participating(racer_id):
		return LapTracker.Result.IGNORED
	var r := racers[racer_id]
	var result := r.tracker.reach(index)
	if result == LapTracker.Result.LAP or result == LapTracker.Result.FINISHED:
		r.lap_times.append(elapsed - r.lap_start)
		r.lap_start = elapsed
	if result == LapTracker.Result.FINISHED:
		finish_order.append(racer_id)
		r.finish_position = finish_order.size()
		r.finish_time = elapsed
		if (not spectator and human_ids.has(racer_id) and humans_finished()) or (spectator and all_finished()):
			state = State.FINISHED
		_classify_retired()
	return result


## M6: a car at zero condition is out of the race (DNF). When it was the last
## human still racing (or, spectating, the last car) the race is over for the
## humans, exactly as when they finish. Returns false when nothing changed.
func retire(racer_id: int) -> bool:
	if state == State.MODE_SELECT or not is_participating(racer_id):
		return false
	var r := racers[racer_id]
	if r.is_done():
		return false
	r.dnf = true
	r.retire_time = elapsed
	if state == State.RACING and ((not spectator and human_ids.has(racer_id) and humans_finished()) or (spectator and all_finished())):
		state = State.FINISHED
	_classify_retired()
	return true


## Once every car has finished or retired, the retired cars are classified
## after the finishers (in standings order: who got further ranks higher),
## without a finish time.
func _classify_retired() -> void:
	if not all_finished():
		return
	for r in standings():
		if r.dnf and r.finish_position == 0:
			finish_order.append(r.id)
			r.finish_position = finish_order.size()
	state = State.FINISHED


## Knockout: the last racer standing wins now (finishes at the current time);
## the eliminated and retired cars are then classified behind.
func finish_now(racer_id: int) -> void:
	var r := racers[racer_id]
	if state == State.MODE_SELECT or r.is_done():
		return
	finish_order.append(racer_id)
	r.finish_position = finish_order.size()
	r.finish_time = elapsed
	if (not spectator and human_ids.has(racer_id) and humans_finished()) or all_finished():
		state = State.FINISHED
	_classify_retired()


## Ends a race that cannot complete normally (spectator safety net): unfinished
## participants are classified in running order without a finish time.
func classify_remaining() -> void:
	for r in standings():
		if not r.is_finished():
			finish_order.append(r.id)
			r.finish_position = finish_order.size()
	state = State.FINISHED


func set_progress(racer_id: int, progress: float) -> void:
	racers[racer_id].progress = progress


## Live order: finished cars by finishing order, then the rest by distance covered.
func standings() -> Array[RacerState]:
	var order: Array[RacerState] = participants()
	order.sort_custom(func(a: RacerState, b: RacerState) -> bool:
		if a.is_finished() != b.is_finished():
			return a.is_finished()
		if a.is_finished():
			return a.finish_position < b.finish_position
		if a.dnf != b.dnf:  # cars still running ahead of retired ones
			return b.dnf
		if a.tracker.laps_completed != b.tracker.laps_completed:
			return a.tracker.laps_completed > b.tracker.laps_completed
		if a.progress != b.progress:
			return a.progress > b.progress
		return a.id < b.id)
	return order


## 1-based live position of a racer.
func position_of(racer_id: int) -> int:
	var order := standings()
	for i in order.size():
		if order[i].id == racer_id:
			return i + 1
	return 0


## Next race's grid (slot 0 = pole) from this race's result, reversed:
## the winner starts last (Super Cars II manual, as reported; see backlog).
func reversed_grid() -> Array[int]:
	var ids: Array[int] = []
	for r in standings():
		ids.append(r.id)
	ids.reverse()
	return ids
