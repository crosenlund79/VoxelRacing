extends GutTest
## Regression: in couch split-screen, pressing the join / start button (Space,
## Cross) again while racing must only drive that player's car; it must never
## start a second race or replace the running one (M4 bug report, both
## reproduction sequences).

const GAME_SCENE := preload("res://src/main/game.tscn")
const PATH := "user://test_couch_input_regression.cfg"
const PAD := 0

var _game: Node


func before_each() -> void:
	_game = GAME_SCENE.instantiate()
	_game.achievements_path = PATH
	add_child_autofree(_game)
	await wait_physics_frames(3)


func after_each() -> void:
	_space(false)
	_cross(false)
	await wait_physics_frames(1)
	if _game != null and is_instance_valid(_game):
		_game.title.stop_audio()
	Engine.time_scale = 1.0
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func _space(pressed: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_SPACE
	e.physical_keycode = KEY_SPACE
	e.pressed = pressed
	Input.parse_input_event(e)


func _cross(pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = PAD
	e.button_index = JOY_BUTTON_A
	e.pressed = pressed
	Input.parse_input_event(e)


func _tap(fn: Callable) -> void:
	fn.call(true)
	await wait_physics_frames(3)
	fn.call(false)
	await wait_physics_frames(3)


## Waits for the game root's fade-in race start to complete.
func _await_race() -> void:
	await wait_until(func() -> bool: return _game.race != null and _game.race.is_inside_tree(), 3.0)
	await wait_physics_frames(20)


func _join_and_start(first: Callable, second: Callable, start: Callable) -> void:
	_game.title._open_join()
	await wait_physics_frames(2)
	await _tap(first)
	await _tap(second)
	await _tap(start)  # both joined: continue to the race
	await _await_race()
	await _tap(start)  # start the race from the grid panel
	await wait_physics_frames(5)


func _check_presses_only_drive(press: Callable, driver_id: int, other_id: int) -> void:
	var race: Node2D = _game.race
	assert_eq(race.session.state, RaceSession.State.RACING, "race started")
	for k in 4:
		press.call(true)
		await wait_physics_frames(25)
		var p: float = race.progress[driver_id].distance
		assert_true(race.cars[driver_id].fire, "the press drives its own car")
		assert_false(race.cars[other_id].fire, "the other car is not affected")
		press.call(false)
		await wait_physics_frames(25)
		assert_eq(_game.race, race, "the race was not replaced (press %d)" % k)
		assert_eq(race.session.state, RaceSession.State.RACING, "still racing")
		assert_gte(race.progress[driver_id].distance, p - 1.0, "progress not reset")
	assert_gt(race.session.elapsed, 1.0, "race clock kept running")


func test_sequence_a_keyboard_joins_first_then_cross_starts_and_drives() -> void:
	await _join_and_start(_space, _cross, _cross)
	var race: Node2D = _game.race
	assert_not_null(race)
	assert_eq(race.player_devices, [PlayerControls.KEYBOARD, PAD] as Array[int])
	var before_races: int = race.races_started
	await _check_presses_only_drive(_cross, RaceSession.PLAYER_2_ID, RaceSession.PLAYER_ID)
	assert_eq(race.races_started, before_races, "no second start")
	await _check_presses_only_drive(_space, RaceSession.PLAYER_ID, RaceSession.PLAYER_2_ID)
	assert_eq(_game.race.player_devices, [PlayerControls.KEYBOARD, PAD] as Array[int], "assignments kept")


func test_sequence_b_cross_joins_first_then_space_starts_and_drives() -> void:
	await _join_and_start(_cross, _space, _space)
	var race: Node2D = _game.race
	assert_not_null(race)
	assert_eq(race.player_devices, [PAD, PlayerControls.KEYBOARD] as Array[int])
	await _check_presses_only_drive(_space, RaceSession.PLAYER_2_ID, RaceSession.PLAYER_ID)
	await _check_presses_only_drive(_cross, RaceSession.PLAYER_ID, RaceSession.PLAYER_2_ID)


func test_join_panel_ignores_input_once_the_race_runs() -> void:
	await _join_and_start(_space, _cross, _cross)
	var panel: JoinPanel = _game.title._join_panel
	watch_signals(panel)
	await _tap(_cross)
	await _tap(_space)
	assert_signal_not_emitted(panel, "confirmed")


func test_a_second_start_request_while_starting_is_ignored() -> void:
	_game.start_race(0, false, [PAD, PlayerControls.KEYBOARD] as Array[int])
	_game.start_race(0, false, [PAD, PlayerControls.KEYBOARD] as Array[int])
	await _await_race()
	var races := _game.get_children().filter(func(n: Node) -> bool: return n.has_method("start_race") and n != _game)
	assert_eq(races.size(), 1, "exactly one race scene")
