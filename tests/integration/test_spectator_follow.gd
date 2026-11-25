extends GutTest
## Spectator camera selection: each race starts on the last-grid starter;
## clicking a standings row follows that driver; the arrows step through the
## fixed starting grid (not live positions); the followed row is highlighted;
## works at x1 and fast speed; normal races are unaffected.

const MAIN_SCENE := preload("res://src/main/main.tscn")

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


func _spectate() -> void:
	_main.set_menu_choice(2)
	_main.start_race()
	await wait_physics_frames(2)


func _row_of(id: int) -> PanelContainer:
	for parts in _main.hud._tower_rows:
		if parts[0].visible and parts[0].has_meta("racer_id") and int(parts[0].get_meta("racer_id")) == id:
			return parts[0]
	return null


func _click(id: int) -> void:
	var row := _row_of(id)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = row.get_global_rect().get_center()
	e.global_position = e.position
	get_viewport().push_input(e, true)
	var up := e.duplicate()
	up.pressed = false
	get_viewport().push_input(up, true)
	await wait_physics_frames(2)


func test_grid_neighbour_wraps_in_grid_order() -> void:
	var grid := [4, 9, 1, 7]
	assert_eq(SpectatorDirector.grid_neighbour(grid, 9, 1), 1)
	assert_eq(SpectatorDirector.grid_neighbour(grid, 9, -1), 4)
	assert_eq(SpectatorDirector.grid_neighbour(grid, 7, 1), 4, "wraps forwards")
	assert_eq(SpectatorDirector.grid_neighbour(grid, 4, -1), 7, "wraps backwards")
	assert_eq(SpectatorDirector.grid_neighbour(grid, 99, 1), 4)
	assert_eq(SpectatorDirector.grid_neighbour([], 1, 1), -1)


func test_chosen_driver_overrides_the_automatic_battle_choice() -> void:
	var d := SpectatorDirector.new()
	d.follow(5)
	var cars := [{"id": 1, "progress": 500.0, "finished": false}, {"id": 2, "progress": 480.0, "finished": false},
		{"id": 5, "progress": 10.0, "finished": false}]
	for i in 600:
		assert_eq(d.update(cars, 1.0 / 60.0), 5)


func test_race_starts_on_the_last_grid_starter() -> void:
	await _spectate()
	var last: int = _main.grid_order[-1]
	assert_eq(_main.director.target_id, last)
	assert_eq(_main.camera.target, _main.cars[last])
	assert_true(_main.camera.position_smoothing_enabled, "smooth transitions kept")
	assert_true(_main.hud._follow_controls.visible)


func test_clicking_a_standings_row_follows_that_driver_and_highlights_it() -> void:
	await _spectate()
	var pick: int = _main.grid_order[2]
	await _click(pick)
	assert_eq(_main.director.target_id, pick)
	await wait_physics_frames(2)
	assert_eq(_main.camera.target, _main.cars[pick])
	await wait_physics_frames(1)
	for parts in _main.hud._tower_rows:
		var is_pick: bool = int(parts[0].get_meta("racer_id")) == pick
		assert_eq(parts[0].get_theme_stylebox("panel") == _main.hud._highlight, is_pick)
		if is_pick:
			assert_eq(parts[3].get_theme_color("font_color"), HyperTheme.GOLD)


func test_arrows_follow_the_starting_grid_not_live_positions() -> void:
	await _spectate()
	var grid: Array[int] = _main.grid_order.duplicate()
	_main.set_sim_speed(8)
	await wait_physics_frames(1200)  # positions have changed by now
	_main.hud._follow_prev.pressed.emit()
	assert_eq(_main.director.target_id, grid[-2], "previous grid slot")
	_main.hud._follow_prev.pressed.emit()
	assert_eq(_main.director.target_id, grid[-3])
	_main.hud._follow_next.pressed.emit()
	_main.hud._follow_next.pressed.emit()
	assert_eq(_main.director.target_id, grid[-1])
	_main.hud._follow_next.pressed.emit()
	assert_eq(_main.director.target_id, grid[0], "wraps to pole")
	await wait_physics_frames(1)
	await _click(grid[4])
	assert_eq(_main.director.target_id, grid[4], "clicking works at fast speed")


func test_new_race_resets_to_its_last_grid_starter() -> void:
	await _spectate()
	_main.set_sim_speed(8)
	_main.follow_driver(_main.grid_order[0])
	await wait_until(func() -> bool: return _main.history.race_count() >= 1 and _main.session.state == RaceSession.State.RACING, 150.0)
	var last: int = _main.grid_order[-1]
	assert_eq(last, _main.history.results[0][0], "reversed grid: last race's winner starts last")
	assert_eq(_main.director.target_id, last)


func test_normal_race_has_no_follow_controls() -> void:
	_main.start_race()
	await wait_physics_frames(2)
	assert_false(_main.hud._follow_controls.visible)
	for parts in _main.hud._tower_rows:
		assert_eq(parts[0].mouse_filter, Control.MOUSE_FILTER_IGNORE)
	_main.follow_driver(3)
	assert_eq(_main.camera.target, _main.car, "camera stays on the player")
