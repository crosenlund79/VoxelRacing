class_name RacerState
extends RefCounted
## One car's race status: laps (from checkpoints), distance progress (for live
## positions), lap times and finish.

var id: int
var display_name: String
var is_player: bool
var tracker: LapTracker
var lap_times: Array[float] = []
## Distance driven along the centreline since the start/finish line, unwrapped
## across laps (negative while still behind the line on the grid).
var progress := 0.0
var finish_time := -1.0
## 1-based finishing position, 0 while still racing.
var finish_position := 0
var lap_start := 0.0
## M6: out of the race at zero condition (did not finish). Classified after
## every car still running, once the race is over.
var dnf := false
## Knockout: the lap after which this racer was eliminated by position (0: not).
var knockout_lap := 0
## Shown instead of the time / DNF in the results (Battle Royale: "OUT 1:23").
var result_note := ""
## Race clock when the car retired (-1 while running).
var retire_time := -1.0


func _init(p_id: int, p_name: String, p_is_player: bool, checkpoint_count: int, lap_count: int) -> void:
	id = p_id
	display_name = p_name
	is_player = p_is_player
	tracker = LapTracker.new(checkpoint_count, lap_count)


func is_finished() -> bool:
	return finish_position > 0


## The time this car's race ended: finish time, retirement time, or -1.
func end_time() -> float:
	return retire_time if dnf else finish_time


## Finished, or out of the race (DNF): this car's race is over.
func is_done() -> bool:
	return finish_position > 0 or dnf
