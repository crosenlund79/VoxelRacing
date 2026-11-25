extends GutTest
## Full Milestone 1 scene: input -> race start, car <-> checkpoint gates -> laps
## -> finish, camera follow, control-mode selection, restart.

const MAIN_SCENE := preload("res://src/main/main.tscn")

var _main: Node2D


func before_each() -> void:
	_main = MAIN_SCENE.instantiate()
	add_child_autofree(_main)
	await wait_physics_frames(2)


func after_each() -> void:
	for action in [PlayerControls.FIRE, PlayerControls.STEER_LEFT, PlayerControls.STEER_RIGHT]:
		Input.action_release(action)


func _tap(action: String) -> void:
	Input.action_press(action)
	await wait_physics_frames(2)
	Input.action_release(action)
	await wait_physics_frames(2)


func _visit_checkpoint(index: int) -> void:
	var t: Transform2D = _main.track.checkpoint_transform(index)
	_main.car.place(t)
	await wait_physics_frames(3)


func test_scene_builds_track_and_starts_in_mode_select() -> void:
	assert_eq(_main.session.state, RaceSession.State.MODE_SELECT)
	assert_eq(_main.track.checkpoint_count(), _main.track.layout.checkpoint_count)
	assert_not_null(_main.track.get_node("Walls"))
	assert_false(_main.car.active, "car frozen until the race starts")


func test_steer_input_toggles_control_mode_before_start() -> void:
	await _tap(PlayerControls.STEER_RIGHT)
	assert_eq(_main.session.control_mode, CarModel.ControlMode.FIRE_TO_BRAKE)
	await _tap(PlayerControls.FIRE)
	assert_eq(_main.car.model.control_mode, CarModel.ControlMode.FIRE_TO_BRAKE)


func test_fire_starts_race_and_car_accelerates() -> void:
	Input.action_press(PlayerControls.FIRE)
	await wait_physics_frames(30)
	assert_eq(_main.session.state, RaceSession.State.RACING)
	assert_gt(_main.car.model.forward_speed(), 0.0)


func test_camera_follows_car() -> void:
	Input.action_press(PlayerControls.FIRE)
	await wait_physics_frames(30)
	assert_almost_eq(_main.camera.global_position, _main.car.global_position, Vector2(0.01, 0.01))


func test_driving_all_checkpoints_completes_race() -> void:
	await _tap(PlayerControls.FIRE)
	var laps: int = _main.track.layout.lap_count
	for lap in laps:
		for i in range(1, _main.track.checkpoint_count()):
			await _visit_checkpoint(i)
		await _visit_checkpoint(0)
	assert_eq(_main.session.state, RaceSession.State.FINISHED)
	assert_eq(_main.session.lap_times.size(), laps)


func test_skipping_a_checkpoint_does_not_count_a_lap() -> void:
	await _tap(PlayerControls.FIRE)
	await _visit_checkpoint(1)
	await _visit_checkpoint(3)
	await _visit_checkpoint(0)
	assert_eq(_main.session.tracker.laps_completed, 0)


func test_fire_after_finish_resets_to_start() -> void:
	await _tap(PlayerControls.FIRE)
	for lap in _main.track.layout.lap_count:
		for i in range(1, _main.track.checkpoint_count()):
			await _visit_checkpoint(i)
		await _visit_checkpoint(0)
	await _tap(PlayerControls.FIRE)
	assert_eq(_main.session.state, RaceSession.State.FINISHED, "Fire (shooting) never leaves the results")
	await _tap(PlayerControls.CONFIRM)
	assert_eq(_main.session.state, RaceSession.State.MODE_SELECT)
	var slot: int = _main.grid_order.find(RaceSession.PLAYER_ID)
	assert_almost_eq(_main.car.global_position, _main.track.grid_transform(slot).origin, Vector2(0.01, 0.01))
