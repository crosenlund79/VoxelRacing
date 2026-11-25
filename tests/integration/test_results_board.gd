extends GutTest
## Results & ranking board cleanup: the results never appear under the FINISH!
## banner, update in place (no fade-out/in) as more cars finish, replace the
## live tower and DESTROYED countdown while up, never get a banner on top, and
## always match the race's own standings, race after race.

const MAIN_SCENE := preload("res://src/main/main.tscn")
const P1 := RaceSession.PLAYER_ID
const P2 := RaceSession.PLAYER_2_ID

var _main: Node2D


func after_each() -> void:
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0
	Engine.max_physics_steps_per_frame = 8
	Input.action_release(PlayerControls.FIRE)
	Input.action_release(PlayerControls.CONFIRM)


func _make(humans := 1) -> void:
	_main = MAIN_SCENE.instantiate()
	_main.presentation_enabled = false
	if humans == 2:
		_main.human_count = 2
		_main.player_devices = [3, 4] as Array[int]
	add_child_autofree(_main)
	await wait_physics_frames(2)


func _finish(id: int) -> void:
	var cps: int = _main.track.checkpoint_count()
	for lap in _main.session.lap_count():
		for i in range(1, cps):
			_main.session.checkpoint_reached(i, id)
		_main.session.checkpoint_reached(0, id)


## Results row names, top to bottom.
func _result_names() -> Array:
	var out := []
	var rows: Array = _main.hud._message_box.find_children("*", "HBoxContainer", true, false)
	for row in rows:
		var labels: Array = row.find_children("*", "Label", false, false)
		if labels.size() < 2 or labels[-1].text == "D":
			continue  # (the TOMBSTONE | K | D column heads)
		# name, then the time, then (when shown) TOMBSTONE, K and D
		var stats_cols := 3 if _main.hud.stats != null else 0
		out.append(labels[labels.size() - 2 - stats_cols].text)
	return out


func _expected_names() -> Array:
	return _main.session.standings().map(func(r: RacerState) -> String:
		return _main.hud._full_names.get(r.id, r.display_name))


func test_results_in_the_finish_frame_wait_for_the_banner() -> void:
	await _make()
	_main.start_race()
	await wait_seconds(1.2)
	assert_false(_main.hud.banner_showing(), "GO! has gone")
	_finish(P1)  # the player finishes: banner and results in the same frame
	await wait_process_frames(1)
	var hud: Hud = _main.hud
	assert_eq(_main.session.state, RaceSession.State.FINISHED)
	assert_true(hud.banner_showing(), "FINISH! on screen")
	assert_true(hud._message.visible)
	assert_eq(hud._message.modulate.a, 0.0, "results not under the banner")
	await wait_seconds(0.5)
	assert_true(hud.banner_showing(), "banner still up")
	assert_eq(hud._message.modulate.a, 0.0, "still hidden while the banner is up")
	await wait_seconds(1.3)
	assert_false(hud.banner_showing())
	assert_gt(hud._message.modulate.a, 0.99, "results after the banner")


func test_results_update_in_place_without_flicker() -> void:
	await _make()
	_main.start_race()
	await wait_physics_frames(2)
	_finish(P1)
	await wait_seconds(1.9)
	var hud: Hud = _main.hud
	assert_gt(hud._message.modulate.a, 0.99)
	var lowest := 1.0
	for id in [3, 5, 7]:
		_finish(id)
		for f in 6:
			await wait_process_frames(1)
			lowest = minf(lowest, hud._message.modulate.a)
	assert_eq(lowest, 1.0, "never faded out while other cars finished")
	assert_eq(_result_names(), _expected_names(), "rows follow the race standings")


func test_tower_and_countdown_step_aside_while_results_are_up() -> void:
	await _make()
	_main.set_weapons_enabled(true)
	_main.start_race()
	await wait_physics_frames(2)
	var hud: Hud = _main.hud
	assert_true(hud._tower_box.visible, "live tower while racing")
	_finish(P1)
	_main.combat.wreck_left[P1] = 2.0  # hit after crossing the line
	await wait_physics_frames(1)
	await wait_process_frames(1)
	assert_true(hud.results_up())
	assert_false(hud._tower_box.visible, "no duplicate ranking beside the results")
	assert_false(hud._wreck_label.visible, "no countdown over the results")
	_main.combat.wreck_left[P1] = 0.0
	Input.action_press(PlayerControls.CONFIRM)
	await wait_physics_frames(2)
	Input.action_release(PlayerControls.CONFIRM)
	await wait_process_frames(2)
	assert_eq(_main.session.state, RaceSession.State.MODE_SELECT, "next race grid")
	assert_false(hud.results_up())
	assert_true(hud._tower_box.visible, "tower back for the next race")


func test_no_banner_over_the_results() -> void:
	await _make()
	_main.start_race()
	await wait_physics_frames(2)
	_finish(P1)
	await wait_seconds(1.9)
	var hud: Hud = _main.hud
	hud.flash_banner("P2 FINISHED!")
	await wait_process_frames(2)
	assert_eq(hud._banner.modulate.a, 0.0, "a late finisher does not cover the results")
	assert_gt(hud._message.modulate.a, 0.99)


func test_consecutive_races_show_fresh_results_and_reverse_the_grid() -> void:
	await _make()
	for race in 3:
		_main.start_race()
		await wait_physics_frames(2)
		var order: Array = [race + 1, P1, race + 4] if race % 2 == 0 else [P1, race + 2, 9]
		for id in order:
			_finish(id)
		await wait_seconds(1.9)
		assert_eq(_main.session.finish_order.slice(0, 3), order, "race %d order" % (race + 1))
		assert_eq(_result_names(), _expected_names(), "race %d results match the standings" % (race + 1))
		assert_eq(_result_names()[0], _main.hud._full_names.get(order[0], "YOU"), "winner on top, not last race's")
		var expected_grid: Array = _main.session.reversed_grid()
		Input.action_press(PlayerControls.CONFIRM)
		await wait_physics_frames(2)
		Input.action_release(PlayerControls.CONFIRM)
		await wait_process_frames(2)
		assert_eq(_main.grid_order, expected_grid, "reversed grid after race %d" % (race + 1))
		assert_false(_main.hud.results_up(), "results gone on the grid")
		await wait_physics_frames(15)  # grid input delay


func test_split_screen_views_hide_their_overlays_at_the_results() -> void:
	await _make(2)
	_main.start_race()
	await wait_physics_frames(2)
	var views: Array = _main.player_views.views
	_finish(P1)
	_finish(P2)
	await wait_physics_frames(1)
	await wait_process_frames(1)
	for v in views:
		assert_true(v.hud.results_up())
		assert_false(v.hud._tower_box.visible, "view tower hidden under the shared results")
	assert_true(_main.hud._message.visible)
	Input.action_press(PlayerControls.CONFIRM)
	await wait_physics_frames(2)
	Input.action_release(PlayerControls.CONFIRM)
	await wait_process_frames(2)
	for v in views:
		assert_true(v.hud._tower_box.visible, "back on the next grid")


func test_spectator_results_are_not_covered_by_the_history_panel() -> void:
	await _make()
	_main.set_menu_choice(2)
	_main.start_race()
	await wait_physics_frames(2)
	for id in range(1, 10):
		_finish(id)
	await wait_physics_frames(2)
	await wait_process_frames(2)
	var hud: Hud = _main.hud
	assert_true(hud._message.visible, "spectator results")
	assert_true(hud.history_panel.visible)
	var results := Rect2(hud._message.position, hud._message.size)
	var history := Rect2(hud.history_panel.position, hud.history_panel.size)
	var info := Rect2(hud._info.position, hud._info.size)
	assert_false(results.intersects(history), "results beside the history panel")
	assert_false(results.intersects(info), "and below the info panel")
	assert_true(Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(results), "on screen")
	assert_gt(hud._message.get_index(), hud.history_panel.get_index(), "centre panels draw above the history panel")
	assert_eq(_result_names(), _expected_names())


func test_split_screen_results_clear_both_info_panels() -> void:
	await _make(2)
	_main.start_race()
	await wait_physics_frames(2)
	_finish(P1)
	_finish(P2)
	await wait_physics_frames(1)
	await wait_process_frames(2)
	var hud: Hud = _main.hud
	var results := Rect2(hud._message.position, hud._message.size)
	for v in _main.player_views.views:
		var info := Rect2(v.hud.offset + v.hud._info.position, v.hud._info.size)
		assert_false(results.intersects(info), "results below the info panel of view %d" % v.racer_id)
	assert_true(Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(results), "on screen")
