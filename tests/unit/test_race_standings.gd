extends GutTest
## RaceSession with a field: live positions, finishing order, results after the
## player finishes, and the reversed grid for the next race.


func _session(field: int) -> RaceSession:
	var names := PackedStringArray(["YOU"])
	for i in range(1, field):
		names.append("CPU %d" % i)
	return RaceSession.new(3, 2, names)


func _lap(s: RaceSession, id: int) -> void:
	s.checkpoint_reached(1, id)
	s.checkpoint_reached(2, id)
	s.checkpoint_reached(0, id)


func test_live_positions_follow_progress() -> void:
	var s := _session(4)
	s.start()
	s.set_progress(0, 100.0)
	s.set_progress(1, 300.0)
	s.set_progress(2, 200.0)
	s.set_progress(3, -50.0)
	assert_eq(s.position_of(1), 1)
	assert_eq(s.position_of(2), 2)
	assert_eq(s.position_of(0), 3)
	assert_eq(s.position_of(3), 4)


func test_completed_laps_rank_ahead_of_progress() -> void:
	var s := _session(2)
	s.start()
	_lap(s, 1)
	s.set_progress(0, 5000.0)
	s.set_progress(1, 10.0)
	assert_eq(s.position_of(1), 1)


func test_finishing_order_and_race_ends_when_player_finishes() -> void:
	var s := _session(3)
	s.start()
	s.tick(10.0)
	_lap(s, 2)
	_lap(s, 2)
	assert_eq(s.state, RaceSession.State.RACING, "an opponent finishing does not end the race")
	s.tick(2.0)
	_lap(s, 0)
	_lap(s, 0)
	assert_eq(s.state, RaceSession.State.FINISHED)
	assert_eq(s.racers[2].finish_position, 1)
	assert_eq(s.racers[0].finish_position, 2)
	assert_almost_eq(s.racers[0].finish_time, 12.0, 0.001)
	assert_eq(s.standings()[0].id, 2)


func test_opponent_laps_still_count_after_player_finishes() -> void:
	var s := _session(2)
	s.start()
	_lap(s, 0)
	_lap(s, 0)
	_lap(s, 1)
	_lap(s, 1)
	assert_eq(s.racers[1].finish_position, 2)


func test_reversed_grid_puts_winner_last() -> void:
	var s := _session(3)
	s.start()
	_lap(s, 1)
	_lap(s, 1)
	_lap(s, 0)
	_lap(s, 0)
	s.set_progress(2, 10.0)
	assert_eq(s.reversed_grid(), [2, 0, 1] as Array[int])


func test_reset_clears_results_for_every_racer() -> void:
	var s := _session(3)
	s.start()
	_lap(s, 1)
	s.reset()
	for r in s.racers:
		assert_eq(r.tracker.laps_completed, 0)
		assert_false(r.is_finished())
	assert_eq(s.finish_order.size(), 0)
