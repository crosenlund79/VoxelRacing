extends GutTest
## M4 Stage 2: couch split-screen. One view per human (own camera on the shared
## race world), each with its own HUD; press-a-button join; launch path from the
## title; lighting off by default; single-player has no split views.

const MAIN_SCENE := preload("res://src/main/main.tscn")
const GAME_SCENE := preload("res://src/main/game.tscn")
const P1 := RaceSession.PLAYER_ID
const P2 := RaceSession.PLAYER_2_ID

var _main: Node2D


func _make(presentation := false) -> void:
	_main = MAIN_SCENE.instantiate()
	_main.weapons_lock_enabled = false  # fires at once (the start lock: test_weapons_hot.gd)
	_main.presentation_enabled = presentation
	_main.human_count = 2
	_main.player_devices = [3, 4] as Array[int]
	add_child_autofree(_main)
	await wait_physics_frames(2)


func after_each() -> void:
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0
	Engine.max_physics_steps_per_frame = 8
	for n in [1, 2]:
		for a in PlayerControls.PLAYER_ACTIONS:
			Input.action_release(PlayerControls.player_prefix(n) + a)
	Input.action_release(PlayerControls.FIRE)


func _finish(id: int) -> void:
	var cps: int = _main.track.checkpoint_count()
	for lap in _main.session.lap_count():
		for i in range(1, cps):
			_main.session.checkpoint_reached(i, id)
		_main.session.checkpoint_reached(0, id)


func test_two_views_each_with_its_own_camera_on_the_shared_world() -> void:
	await _make()
	var views: Array = _main.player_views.views
	assert_eq(views.size(), 2)
	assert_eq(views[0].racer_id, P1)
	assert_eq(views[1].racer_id, P2)
	for v in views:
		assert_eq(v.viewport.world_2d, _main.get_viewport().world_2d, "same race world")
		assert_eq(v.viewport.get_camera_2d(), v.camera, "own current camera")
		assert_eq(v.camera.target, _main.cars[v.racer_id])
	assert_lt(views[0].container.position.x, views[1].container.position.x, "side by side")
	assert_eq(_main.camera.target, _main._park, "the main camera shows nothing")


func test_cameras_stay_independent_when_players_are_far_apart() -> void:
	await _make()
	_main.set_sim_speed(4)
	_main.start_race()
	Input.action_press("p1_fire")  # only P1 drives away
	await wait_physics_frames(4 * 60 * 6)
	var views: Array = _main.player_views.views
	var c1: Vector2 = views[0].camera.global_position
	var c2: Vector2 = views[1].camera.global_position
	assert_gt(c1.distance_to(c2), 600.0, "players far apart")
	assert_almost_eq(c1.distance_to(_main.cars[P1].global_position), 0.0, 1.0)
	assert_almost_eq(c2.distance_to(_main.cars[P2].global_position), 0.0, 1.0)


func test_each_hud_shows_its_own_player() -> void:
	await _make()
	_main.set_weapons_enabled(true)
	_main.start_race()
	Input.action_press("p2_fire_front")
	await wait_physics_frames(2)
	Input.action_release("p2_fire_front")
	await wait_physics_frames(2)
	var h1: Hud = _main.player_views.views[0].hud
	var h2: Hud = _main.player_views.views[1].hud
	assert_eq(h1._pos_label.text, "P%d" % _main.session.position_of(P1))
	assert_eq(h2._pos_label.text, "P%d" % _main.session.position_of(P2))
	assert_eq(h1._mode_label.text, "PLAYER 1")
	assert_eq(h2._mode_label.text, "PLAYER 2")
	assert_eq(h1._front_label.text, "x%d" % _main.combat.ammo[P1][0])
	assert_eq(h2._front_label.text, "x%d" % _main.combat.ammo[P2][0])
	assert_ne(h1._front_label.text, h2._front_label.text, "P2 fired, P1 did not")
	assert_gt(_main._cooldown_fraction(CombatWorld.FRONT, P2), 0.0)
	assert_false(_main.hud._info.visible, "shared HUD has no single-player panel")
	assert_false(_main.hud._tower_box.visible, "no shared tower over the divider (P1)")
	assert_true(h1._tower_box.visible and h2._tower_box.visible, "each view shows the standings")


func test_split_screen_race_completes_and_shows_results() -> void:
	await _make()
	_main.start_race()
	_finish(P2)
	_finish(P1)
	await wait_physics_frames(3)
	assert_eq(_main.session.state, RaceSession.State.FINISHED)
	assert_true(_main.hud._message.visible, "results on the shared HUD")


func test_lighting_off_by_default_in_split_screen() -> void:
	await _make(true)
	assert_not_null(_main.lighting)
	assert_false(_main.lighting.enabled)


func test_single_player_has_no_split_views() -> void:
	var m: Node2D = MAIN_SCENE.instantiate()
	m.weapons_lock_enabled = false
	m.presentation_enabled = false
	add_child_autofree(m)
	await wait_physics_frames(2)
	assert_null(m.player_views)
	assert_eq(m.camera.target, m.car)
	assert_true(m.hud._info.visible)


func test_join_panel_assigns_two_distinct_devices() -> void:
	var j := JoinPanel.new()
	add_child_autofree(j)
	j.setup()
	j.open()
	watch_signals(j)
	j.press(2)
	j.press(2)
	assert_eq(j.devices, [2] as Array[int], "one device cannot take both slots")
	j.press(PlayerControls.KEYBOARD)
	assert_eq(j.devices, [2, PlayerControls.KEYBOARD] as Array[int])
	j.press(5)
	assert_eq(j.devices.size(), 2, "only two players")
	j.press(2, true)
	assert_eq(j.devices, [PlayerControls.KEYBOARD] as Array[int], "Circle / B leaves")
	j.press(0)
	j.press(0)
	assert_signal_emitted_with_parameters(j, "confirmed", [[PlayerControls.KEYBOARD, 0]])
	j.open()
	j.press(1, true)
	assert_signal_emitted(j, "closed", "B with nobody joined goes back")


func test_join_panel_reacts_to_real_controller_events() -> void:
	var j := JoinPanel.new()
	add_child_autofree(j)
	j.setup()
	j.open()
	for dev in [7, 8]:
		var e := InputEventJoypadButton.new()
		e.device = dev
		e.button_index = JOY_BUTTON_A
		e.pressed = true
		get_viewport().push_input(e)
	assert_eq(j.devices, [7, 8] as Array[int])


func test_title_launches_two_player_split_screen() -> void:
	var game := GAME_SCENE.instantiate()
	game.achievements_path = "user://test_split_achievements.cfg"
	add_child_autofree(game)
	await wait_physics_frames(3)
	game.title._open_join()
	assert_true(game.title._join_panel.visible)
	await game.start_race(0, false, [3, 4] as Array[int])
	assert_eq(game.race.human_count, 2)
	assert_null(game.race.garage)
	assert_null(game.race.achievements)
	assert_not_null(game.race.player_views)
	assert_eq(game.race.session.state, RaceSession.State.MODE_SELECT, "grid panel first")
	await game.back_to_title()
	await game.start_race(0)
	assert_eq(game.race.human_count, 1, "single player unaffected")
	assert_null(game.race.player_views)
	game.title.stop_audio()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_split_achievements.cfg"))
