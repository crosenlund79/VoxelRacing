extends GutTest
## LapTracker: in-order checkpoints, laps, finish, and ignoring invalid crossings.


func _drive_lap(t: LapTracker) -> LapTracker.Result:
	var last := LapTracker.Result.IGNORED
	for i in range(1, t.checkpoint_count):
		last = t.reach(i)
	return t.reach(0) if last != LapTracker.Result.IGNORED else last


func test_full_lap_in_order_counts() -> void:
	var t := LapTracker.new(4, 3)
	assert_eq(t.reach(1), LapTracker.Result.CHECKPOINT)
	assert_eq(t.reach(2), LapTracker.Result.CHECKPOINT)
	assert_eq(t.reach(3), LapTracker.Result.CHECKPOINT)
	assert_eq(t.reach(0), LapTracker.Result.LAP)
	assert_eq(t.laps_completed, 1)
	assert_eq(t.current_lap(), 2)


func test_start_line_at_race_start_is_ignored() -> void:
	var t := LapTracker.new(4, 3)
	assert_eq(t.reach(0), LapTracker.Result.IGNORED)
	assert_eq(t.laps_completed, 0)


func test_skipped_checkpoint_blocks_lap() -> void:
	var t := LapTracker.new(4, 3)
	t.reach(1)
	assert_eq(t.reach(3), LapTracker.Result.IGNORED, "shortcut past checkpoint 2")
	assert_eq(t.reach(0), LapTracker.Result.IGNORED)
	assert_eq(t.laps_completed, 0)


func test_driving_backwards_does_not_count() -> void:
	var t := LapTracker.new(4, 3)
	t.reach(1)
	t.reach(2)
	assert_eq(t.reach(1), LapTracker.Result.IGNORED)
	assert_eq(t.next_checkpoint, 3)


func test_repeated_checkpoint_is_ignored() -> void:
	var t := LapTracker.new(4, 3)
	t.reach(1)
	assert_eq(t.reach(1), LapTracker.Result.IGNORED)


func test_race_finishes_after_lap_count() -> void:
	var t := LapTracker.new(3, 2)
	assert_eq(_drive_lap(t), LapTracker.Result.LAP)
	assert_eq(_drive_lap(t), LapTracker.Result.FINISHED)
	assert_true(t.is_finished())
	assert_eq(t.current_lap(), 2, "lap display clamps to race length")


func test_no_progress_after_finish() -> void:
	var t := LapTracker.new(3, 1)
	_drive_lap(t)
	assert_eq(t.reach(1), LapTracker.Result.IGNORED)
	assert_eq(t.laps_completed, 1)
