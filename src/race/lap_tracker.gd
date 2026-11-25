class_name LapTracker
extends RefCounted
## Checkpoint-based lap counting. Checkpoint 0 is the start/finish line.
## The car starts just past the line, so the first expected checkpoint is 1.
## Only the next checkpoint in order counts; anything else is ignored, so
## shortcuts, driving backwards or re-crossing the line never score a lap.

enum Result { IGNORED, CHECKPOINT, LAP, FINISHED }

var checkpoint_count: int
var lap_count: int
var next_checkpoint := 1
var laps_completed := 0


func _init(p_checkpoint_count: int, p_lap_count: int) -> void:
	assert(p_checkpoint_count >= 2, "Need at least two checkpoints")
	assert(p_lap_count >= 1, "Need at least one lap")
	checkpoint_count = p_checkpoint_count
	lap_count = p_lap_count


func is_finished() -> bool:
	return laps_completed >= lap_count


func reach(index: int) -> Result:
	if is_finished() or index != next_checkpoint:
		return Result.IGNORED
	next_checkpoint = (index + 1) % checkpoint_count
	if index != 0:
		return Result.CHECKPOINT
	laps_completed += 1
	return Result.FINISHED if is_finished() else Result.LAP


## Lap currently being driven (1-based), clamped to the race length.
func current_lap() -> int:
	return mini(laps_completed + 1, lap_count)
