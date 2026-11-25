extends GutTest
## Spectator support: rival roster identities, race history and position
## counts, camera director, spectator sessions and race-time accounting.


func _session(spectator: bool) -> RaceSession:
	var names := PackedStringArray(["YOU"])
	for i in range(1, 4):
		names.append(RivalRoster.short_name(i))
	var s := RaceSession.new(3, 1, names)
	s.set_spectator(spectator)
	return s


func _lap(s: RaceSession, id: int) -> void:
	for i in [1, 2, 0]:
		s.checkpoint_reached(i, id)


func test_roster_has_nine_fixed_identities() -> void:
	assert_eq(RivalRoster.count(), 9)
	var expected := ['Victor "The Professor"', 'Rocco "Mad Dog"', 'Ellie "Sparrow"', 'Hank "The Wall"',
		'Maya "Ghost"', 'Dante "Showboat"', 'Greta "Clockwork"', 'Finn "Wildcard"', 'Nina "The Hunter"']
	for id in range(1, 10):
		assert_eq(RivalRoster.full_name(id), expected[id - 1])
		assert_eq(AssetCatalog.ai_car(id), "cars/car_ai_%d" % id, "fixed car per rival")
	for id in range(1, 4):
		assert_true(RivalRoster.has_personality(id))
		assert_not_null(load(RivalRoster.params_path(id)))


func test_history_positions_and_counts() -> void:
	var h := RaceHistory.new([1, 2, 3] as Array[int])
	h.add_race([2, 1, 3] as Array[int])
	h.add_race([2, 3, 1] as Array[int])
	assert_eq(h.race_count(), 2)
	assert_eq(h.position_in(0, 1), 2)
	assert_eq(h.position_in(1, 1), 3)
	assert_eq(h.position_counts(2), [2, 0, 0] as Array[int])
	assert_eq(h.position_counts(1), [0, 1, 1] as Array[int])


func test_history_keeps_its_own_copy_of_results() -> void:
	var h := RaceHistory.new([1, 2] as Array[int])
	var order: Array[int] = [1, 2]
	h.add_race(order)
	order.reverse()
	assert_eq(h.position_in(0, 1), 1)


func test_director_follows_closest_battle_and_holds() -> void:
	var cars := [
		{"id": 1, "progress": 1000.0, "finished": false},
		{"id": 2, "progress": 700.0, "finished": false},
		{"id": 3, "progress": 680.0, "finished": false},
	]
	assert_eq(SpectatorDirector.choose(cars), 3, "chaser of the 20 px battle")
	var d := SpectatorDirector.new()
	assert_eq(d.update(cars, 0.1), 3)
	cars[0].progress = 690.0  # a closer battle appears
	cars[1].progress = 689.0
	assert_eq(d.update(cars, 1.0), 3, "holds the shot")
	assert_eq(d.update(cars, 4.0), 2, "cuts after the hold time")


func test_director_leaves_a_finished_car_immediately() -> void:
	var d := SpectatorDirector.new()
	var cars := [{"id": 1, "progress": 10.0, "finished": false}, {"id": 2, "progress": 5.0, "finished": false}]
	assert_eq(d.update(cars, 0.0), 2)
	cars[1].finished = true
	assert_eq(d.update(cars, 0.1), 1)


func test_spectator_session_excludes_player() -> void:
	var s := _session(true)
	assert_eq(s.racer_count(), 3)
	for r in s.standings():
		assert_false(r.is_player)
	s.start()
	assert_eq(s.checkpoint_reached(1, RaceSession.PLAYER_ID), LapTracker.Result.IGNORED)


func test_spectator_race_finishes_when_all_rivals_finish() -> void:
	var s := _session(true)
	s.start()
	_lap(s, 2)
	_lap(s, 1)
	assert_eq(s.state, RaceSession.State.RACING)
	_lap(s, 3)
	assert_eq(s.state, RaceSession.State.FINISHED)
	assert_eq(s.finish_order, [2, 1, 3] as Array[int])


func test_spectator_flag_only_changes_while_choosing() -> void:
	var s := _session(false)
	s.start()
	s.set_spectator(true)
	assert_false(s.spectator)


func test_rivals_finishing_after_player_get_their_own_times() -> void:
	var s := _session(false)
	s.start()
	s.tick(50.0)
	_lap(s, 1)
	s.tick(2.0)
	_lap(s, RaceSession.PLAYER_ID)
	assert_eq(s.state, RaceSession.State.FINISHED)
	s.tick(3.0)
	_lap(s, 2)
	s.tick(1.5)
	_lap(s, 3)
	assert_almost_eq(s.racers[1].finish_time, 50.0, 0.001)
	assert_almost_eq(s.racers[0].finish_time, 52.0, 0.001)
	assert_almost_eq(s.racers[2].finish_time, 55.0, 0.001, "clock kept running after the player finished")
	assert_almost_eq(s.racers[3].finish_time, 56.5, 0.001)
	s.tick(10.0)
	assert_almost_eq(s.elapsed, 56.5, 0.001, "clock stops when everyone has finished")


func test_classify_remaining_uses_running_order() -> void:
	var s := _session(true)
	s.start()
	_lap(s, 3)
	s.set_progress(1, 100.0)
	s.set_progress(2, 500.0)
	s.classify_remaining()
	assert_eq(s.state, RaceSession.State.FINISHED)
	assert_eq(s.finish_order, [3, 2, 1] as Array[int])
	assert_lt(s.racers[1].finish_time, 0.0, "no time for classified cars")


func test_history_panel_shows_stars_for_podium_and_numbers_below() -> void:
	var h := RaceHistory.new([1, 2, 3, 4] as Array[int])
	h.add_race([3, 1, 4, 2] as Array[int])
	var panel := HistoryPanel.new()
	panel.size = Vector2(500, 330)
	add_child_autofree(panel)
	var tex := {}
	var names := {}
	for id in [1, 2, 3, 4]:
		tex[id] = load("res://assets/graphics/cars/template_body_ai_%d.png" % id)
		names[id] = RivalRoster.full_name(id)
	panel.setup(AssetResolver.new(OS.get_user_data_dir().path_join("no_overrides")), h, tex, names)
	var grid: GridContainer = panel.find_children("*", "GridContainer", true, false)[0]
	var cells := grid.get_children()
	assert_eq(grid.columns, 1)
	assert_eq(cells.size(), 3 + 4, "race header + weapons row + laps row + one cell per driver")
	assert_eq(cells[1].text, "off", "race recorded without weapons")
	assert_eq(cells[2].text, "3", "race length")
	assert_true(cells[3] is TextureRect, "driver 1 was 2nd: silver star")
	assert_true(cells[4] is Label and cells[4].text == "4", "driver 2 was 4th")
	assert_true(cells[5] is TextureRect, "driver 3 won: gold star")
	panel.toggle_view()
	cells = grid.get_children()
	assert_eq(grid.columns, 4)
	assert_eq(cells[4 + 1].text, "1", "driver 1 (first row, after 4 headers): one 2nd place")


func test_history_marks_races_run_with_weapons() -> void:
	var h := RaceHistory.new([1, 2] as Array[int])
	h.add_race([1, 2] as Array[int], true)
	h.add_race([2, 1] as Array[int], false)
	h.add_race([1, 2] as Array[int])
	assert_eq(h.weapons, [true, false, false] as Array[bool])
	assert_eq(h.weapon_race_count(), 1)
