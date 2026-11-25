extends GutTest
## RaceSession: mode selection, timing, lap times, finish and reset.


func test_starts_in_mode_select_with_fire_to_accelerate() -> void:
	var s := RaceSession.new(3, 2)
	assert_eq(s.state, RaceSession.State.MODE_SELECT)
	assert_eq(s.control_mode, CarModel.ControlMode.FIRE_TO_ACCELERATE)


func test_toggle_mode_only_in_mode_select() -> void:
	var s := RaceSession.new(3, 2)
	s.toggle_mode()
	assert_eq(s.control_mode, CarModel.ControlMode.FIRE_TO_BRAKE)
	s.start()
	s.toggle_mode()
	assert_eq(s.control_mode, CarModel.ControlMode.FIRE_TO_BRAKE)


func test_checkpoints_and_time_ignored_before_start() -> void:
	var s := RaceSession.new(3, 2)
	s.tick(1.0)
	assert_eq(s.checkpoint_reached(1), LapTracker.Result.IGNORED)
	assert_eq(s.elapsed, 0.0)


func test_full_race_records_lap_times_and_finishes() -> void:
	var s := RaceSession.new(3, 2)
	s.start()
	for lap in 2:
		s.tick(10.0 + lap)
		s.checkpoint_reached(1)
		s.checkpoint_reached(2)
		s.checkpoint_reached(0)
	assert_eq(s.state, RaceSession.State.FINISHED)
	assert_eq(s.lap_times.size(), 2)
	assert_almost_eq(s.lap_times[0], 10.0, 0.0001)
	assert_almost_eq(s.lap_times[1], 11.0, 0.0001)
	s.tick(5.0)
	assert_almost_eq(s.elapsed, 21.0, 0.0001, "clock stops at the finish")


func test_reset_returns_to_mode_select_and_keeps_mode() -> void:
	var s := RaceSession.new(3, 1)
	s.toggle_mode()
	s.start()
	s.checkpoint_reached(1)
	s.reset()
	assert_eq(s.state, RaceSession.State.MODE_SELECT)
	assert_eq(s.tracker.next_checkpoint, 1)
	assert_eq(s.control_mode, CarModel.ControlMode.FIRE_TO_BRAKE)
