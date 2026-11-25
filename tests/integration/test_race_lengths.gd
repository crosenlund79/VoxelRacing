extends GutTest
## Selectable race lengths (3 / 7 / 20 / 50 laps): session rules, grid panel,
## HUD and history, spectator sessions and auto-restarts, and the stuck-race
## safety net never cutting a progressing race short.

const MAIN_SCENE := preload("res://src/main/main.tscn")
const OPTIONS := [3, 7, 20, 50]

var _main: Node2D


func before_each() -> void:
	_main = MAIN_SCENE.instantiate()
	_main.presentation_enabled = false
	add_child_autofree(_main)
	await wait_physics_frames(2)


func after_each() -> void:
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0
	Engine.max_physics_steps_per_frame = 8
	for a in [PlayerControls.FIRE, PlayerControls.HISTORY_VIEW]:
		Input.action_release(a)


func _laps(s: RaceSession, id: int, n: int) -> void:
	for lap in n:
		for i in range(1, s.racers[id].tracker.checkpoint_count):
			s.checkpoint_reached(i, id)
		s.checkpoint_reached(0, id)


func test_default_is_three_laps_and_options_are_offered() -> void:
	assert_eq(_main.lap_count(), 3)
	assert_eq(_main.LAP_OPTIONS, [3, 7, 20, 50] as Array[int])


func test_session_finishes_after_exactly_the_selected_laps() -> void:
	for n in OPTIONS:
		var s := RaceSession.new(4, 3, PackedStringArray(["YOU", "A"]))
		s.set_lap_count(n)
		assert_eq(s.lap_count(), n)
		s.start()
		_laps(s, 0, n - 1)
		assert_eq(s.state, RaceSession.State.RACING, "%d laps: not finished after %d" % [n, n - 1])
		_laps(s, 0, 1)
		assert_eq(s.state, RaceSession.State.FINISHED, "%d laps: finished" % n)
		assert_eq(s.racers[0].lap_times.size(), n)


func test_lap_count_only_changes_before_the_start() -> void:
	var s := RaceSession.new(4, 3)
	s.start()
	s.set_lap_count(20)
	assert_eq(s.lap_count(), 3)


func test_each_length_applies_to_every_car_and_the_hud() -> void:
	for n in OPTIONS:
		_main.set_lap_count(n)
		for r in _main.session.racers:
			assert_eq(r.tracker.lap_count, n)
		_main._refresh_hud()
		assert_eq(_main.hud._lap_label.text, "LAP 1 / %d" % n)


func test_player_race_of_each_length_finishes_on_the_last_lap() -> void:
	for n in OPTIONS:
		_main.session.state = RaceSession.State.MODE_SELECT
		_main.set_lap_count(n)
		_main.start_race()
		_laps(_main.session, 0, n)
		assert_eq(_main.session.state, RaceSession.State.FINISHED, "%d laps" % n)
		_main.hud.show_results(_main.session.standings())
		var title: Label = _main.hud._message_box.get_child(0)
		assert_eq(title.text, "RESULTS  -  %d LAPS" % n)
		_main.grid_order = _main.session.reversed_grid()
		_main.reset_race()
		assert_eq(_main.lap_count(), n, "kept for the next race")


func test_tab_on_the_grid_cycles_the_lengths() -> void:
	for expected in [7, 20, 50, 3]:
		Input.action_press(PlayerControls.HISTORY_VIEW)
		await wait_physics_frames(2)
		Input.action_release(PlayerControls.HISTORY_VIEW)
		await wait_physics_frames(1)
		assert_eq(_main.lap_count(), expected)


func test_history_records_each_race_length() -> void:
	var h := RaceHistory.new([1, 2] as Array[int])
	h.add_race([1, 2] as Array[int], false, 3)
	h.add_race([2, 1] as Array[int], true, 50)
	assert_eq(h.laps, [3, 50] as Array[int])


func test_spectator_session_keeps_its_length_across_restarts() -> void:
	_main.set_menu_choice(2)
	_main.set_lap_count(7)
	_main.set_sim_speed(8)
	_main.start_race()
	await wait_until(func() -> bool: return _main.history.race_count() >= 1, 300.0)
	assert_eq(_main.history.laps, [7] as Array[int])
	for r in _main.session.participants():
		assert_eq(r.tracker.laps_completed, 7)
		assert_gt(r.finish_time, 0.0, "every rival finished with a real time (no cut-off)")
	var order: Array = _main.history.results[0].duplicate()
	await wait_until(func() -> bool: return _main.session.state == RaceSession.State.RACING, 20.0)
	assert_eq(_main.lap_count(), 7, "auto-restart keeps the length")
	order.reverse()
	assert_eq(_main.grid_order, order, "reversed grid preserved")


func test_safety_net_only_triggers_on_a_genuinely_stuck_race() -> void:
	_main.set_menu_choice(2)
	_main.set_sim_speed(8)
	_main.start_race()
	await wait_physics_frames(60)
	for c in _main.cars:
		c.active = false  # nobody can make progress any more
	await wait_until(func() -> bool: return _main._stuck_time > 30.0, 200.0)
	assert_eq(_main.session.state, RaceSession.State.RACING, "30 s without progress is not enough")
	await wait_until(func() -> bool: return _main.history.race_count() >= 1, 200.0)
	assert_eq(_main.history.race_count(), 1, "classified and recorded after 60 s with no progress at all")
	for r in _main.session.participants():
		if _main.history.race_count() == 1 and _main.session.state != RaceSession.State.RACING:
			assert_lt(r.finish_time, 0.0, "stalled cars are classified without a time")
