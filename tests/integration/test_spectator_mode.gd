extends GutTest
## Spectator mode in the full scene: nine rivals race without the player car,
## the next race starts automatically, history accumulates, and fast simulation
## reproduces normal simulation exactly for identical starting conditions.

const MAIN_SCENE := preload("res://src/main/main.tscn")

var _main: Node2D


func _new_main() -> Node2D:
	var m := MAIN_SCENE.instantiate()
	add_child_autofree(m)
	await wait_physics_frames(2)
	return m


func after_each() -> void:
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0
	Engine.max_physics_steps_per_frame = 8


## Exact bytes of every rival's car and driver state.
func _state_bytes(m: Node2D) -> PackedByteArray:
	var state := []
	for id in range(1, 10):
		state.append_array([m.cars[id].global_position, m.cars[id].model.velocity, m.cars[id].model.heading,
			m.drivers[id].lane_bias, m.drivers[id].commitment, m.drivers[id].fluster_time])
	return var_to_bytes(state)


func test_spectate_choice_removes_player_and_grids_nine_rivals() -> void:
	_main = await _new_main()
	_main.set_menu_choice(2)
	assert_true(_main.session.spectator)
	assert_false(_main.car.visible)
	assert_eq(_main.car.collision_layer, 0, "player car takes no part in collisions")
	assert_eq(_main.grid_order.size(), 9)
	assert_false(_main.grid_order.has(RaceSession.PLAYER_ID))
	assert_eq(_main.session.racer_count(), 9)
	_main.set_menu_choice(0)
	assert_false(_main.session.spectator)
	assert_true(_main.car.visible)
	assert_eq(_main.grid_order.size(), 10)


func test_full_spectator_race_records_history_and_restarts() -> void:
	_main = await _new_main()
	_main.set_menu_choice(2)
	_main.set_sim_speed(8)
	_main.start_race()
	await wait_until(func() -> bool: return _main.history.race_count() >= 1, 120.0)
	assert_eq(_main.history.race_count(), 1)
	var order: Array = _main.history.results[0]
	var sorted := order.duplicate()
	sorted.sort()
	assert_eq(sorted, [1, 2, 3, 4, 5, 6, 7, 8, 9], "all nine classified once")
	for r in _main.session.participants():
		assert_gt(r.finish_time, 0.0, "every rival has a real finish time")
	await wait_until(func() -> bool: return _main.session.state == RaceSession.State.RACING, 20.0)
	assert_eq(_main.races_started, 2, "next race started automatically")
	var expected_grid: Array = order.duplicate()
	expected_grid.reverse()
	assert_eq(_main.grid_order, expected_grid, "reversed grid: winner starts last")


func test_fast_simulation_matches_normal_simulation_exactly() -> void:
	# Each run in a fresh process (same initial conditions, including engine state).
	var normal := ProbeRunner.run(["mode=spectate", "speed=1", "ticks=900"])
	var fast := ProbeRunner.run(["mode=spectate", "speed=4", "ticks=900"])
	assert_eq(normal.length(), 32, normal)
	assert_eq(fast, normal, "bit-identical cars and drivers after 900 ticks at x1 and x4")


func test_back_opens_the_race_menu_and_leave_resets_speed() -> void:
	_main = await _new_main()
	_main.set_menu_choice(2)
	_main.start_race()
	Input.action_press(PlayerControls.SIM_SPEED)
	await wait_physics_frames(2)
	Input.action_release(PlayerControls.SIM_SPEED)
	assert_eq(_main.sim_speed, _main.fast_multiplier)
	Input.action_press(PlayerControls.BACK)
	await wait_process_frames(2)
	Input.action_release(PlayerControls.BACK)
	assert_true(_main.menu_open, "Esc opens the race menu while spectating")
	assert_true(_main.get_tree().paused, "spectating pauses")
	watch_signals(_main)
	_main.leave_race()
	assert_signal_emitted(_main, "exit_requested")
	assert_false(_main.get_tree().paused)
	assert_eq(_main.sim_speed, 1, "normal speed again")
