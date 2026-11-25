extends GutTest
## Full scene with computer opponents under real physics: grid, AI navigation,
## live positions, lap counting for every car, results and the reversed grid.
## Validated with one opponent first, then the full 10-car field.
## Each race test simulates ~25-40 s; run GUT with --fixed-fps 60 to make it fast.

const MAIN_SCENE := preload("res://src/main/main.tscn")

var _main: Node2D
var _wall_hits := {}


func _start(opponents: int) -> void:
	_main = MAIN_SCENE.instantiate()
	_main.opponent_count = opponents
	add_child_autofree(_main)
	await wait_physics_frames(2)
	for c in _main.cars:
		_wall_hits[c.racer_id] = 0
		c.wall_hit.connect(func(_n: Vector2, speed: float) -> void:
			if speed > 60.0:
				_wall_hits[c.racer_id] += 1)
	Input.action_press(PlayerControls.FIRE)
	await wait_physics_frames(2)
	Input.action_release(PlayerControls.FIRE)  # player stays parked on the grid


func after_each() -> void:
	Input.action_release(PlayerControls.FIRE)


func _all_opponents_lapped() -> bool:
	for r in _main.session.racers:
		if not r.is_player and r.tracker.laps_completed < 1:
			return false
	return true


func test_grid_places_whole_field_behind_line_without_overlap() -> void:
	_main = MAIN_SCENE.instantiate()
	add_child_autofree(_main)
	await wait_physics_frames(2)
	assert_eq(_main.cars.size(), 10, "player + 9 opponents")
	assert_eq(_main.grid_order[_main.grid_order.size() - 1], RaceSession.PLAYER_ID, "player starts at the back")
	for i in _main.cars.size():
		assert_lt(_main.progress[i].distance, 0.0, "behind the start/finish line")
		for j in range(i + 1, _main.cars.size()):
			assert_gt(_main.cars[i].global_position.distance_to(_main.cars[j].global_position), 60.0)


func test_first_grid_helper() -> void:
	var main_script: GDScript = load("res://src/main/main.gd")
	assert_eq(main_script.first_grid(4, -1), [1, 2, 3, 0] as Array[int])
	assert_eq(main_script.first_grid(4, 0), [0, 1, 2, 3] as Array[int])
	assert_eq(main_script.first_grid(3, 9), [1, 2, 0] as Array[int], "slot clamped to the field")


func test_single_opponent_completes_a_lap_cleanly() -> void:
	await _start(1)
	await wait_until(_all_opponents_lapped, 40.0)
	var ai: RacerState = _main.session.racers[1]
	assert_eq(ai.tracker.laps_completed, 1)
	assert_eq(ai.lap_times.size(), 1)
	assert_lte(_wall_hits[1], 1, "drives the line without hitting barriers")
	assert_eq(_main.session.position_of(1), 1)
	assert_eq(_main.session.position_of(RaceSession.PLAYER_ID), 2, "parked player is last")


func test_full_field_navigates_and_every_opponent_completes_a_lap() -> void:
	await _start(9)
	await wait_until(_all_opponents_lapped, 60.0)
	assert_true(_all_opponents_lapped(), "all 9 opponents lapped")
	var positions := []
	for r in _main.session.racers:
		positions.append(_main.session.position_of(r.id))
	positions.sort()
	assert_eq(positions, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10], "positions are a full ranking")
	assert_eq(_main.session.position_of(RaceSession.PLAYER_ID), 10)
	var total_wall_hits := 0
	for id in _wall_hits:
		total_wall_hits += _wall_hits[id]
	assert_lt(total_wall_hits, 30, "no car is stuck bouncing off barriers")


func test_results_and_reversed_grid_after_player_finishes() -> void:
	await _start(3)
	# Teleport the player through the gates (as in the M1 flow test).
	for lap in _main.track.layout.lap_count:
		for i in range(1, _main.track.checkpoint_count()) + [0]:
			_main.car.place(_main.track.checkpoint_transform(i))
			await wait_physics_frames(3)
	assert_eq(_main.session.state, RaceSession.State.FINISHED)
	assert_eq(_main.session.racers[0].finish_position, 1)
	assert_eq(_main.session.standings()[0].id, RaceSession.PLAYER_ID)
	var expected_grid: Array[int] = _main.session.reversed_grid()
	Input.action_press(PlayerControls.CONFIRM)
	await wait_physics_frames(2)
	Input.action_release(PlayerControls.CONFIRM)
	await wait_physics_frames(2)
	assert_eq(_main.session.state, RaceSession.State.MODE_SELECT)
	assert_eq(_main.grid_order, expected_grid)
	assert_eq(_main.grid_order[_main.grid_order.size() - 1], RaceSession.PLAYER_ID, "winner starts last")
