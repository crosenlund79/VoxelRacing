extends GutTest
## M2.2 presentation: never changes the race (bit-identical with it on or off,
## in a normal race and when spectating), scenery is decorative only, effects
## and HUD react to race state, and the title screen starts and leaves races.

const MAIN_SCENE := preload("res://src/main/main.tscn")
const GAME_SCENE := preload("res://src/main/game.tscn")


func after_each() -> void:
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0
	Engine.max_physics_steps_per_frame = 8
	for a in [PlayerControls.FIRE, PlayerControls.STEER_LEFT, PlayerControls.STEER_RIGHT]:
		Input.action_release(a)


func _main(presentation: bool) -> Node2D:
	var m := MAIN_SCENE.instantiate()
	m.presentation_enabled = presentation
	add_child_autofree(m)
	await wait_physics_frames(2)
	return m


func _state(m: Node2D) -> PackedByteArray:
	var s := []
	for c in m.cars:
		s.append_array([c.global_position, c.model.velocity, c.model.heading])
	for d in m.drivers:
		if d != null:
			s.append_array([d.lane_bias, d.commitment, d.fluster_time])
	for r in m.session.racers:
		s.append_array([r.progress, r.tracker.laps_completed, r.tracker.next_checkpoint])
	return var_to_bytes(s)


## Scripted player input so both runs see exactly the same commands.
func _drive_player(ticks: int) -> void:
	for i in ticks:
		if i % 90 == 30:
			Input.action_press(PlayerControls.STEER_RIGHT)
		elif i % 90 == 45:
			Input.action_release(PlayerControls.STEER_RIGHT)
		await wait_physics_frames(1)


func test_normal_race_is_identical_with_and_without_presentation() -> void:
	# Fresh process per run: same initial conditions, including physics-engine state.
	var off := ProbeRunner.run(["mode=race", "presentation=0", "ticks=600"])
	var on := ProbeRunner.run(["mode=race", "presentation=1", "ticks=600"])
	assert_eq(off.length(), 32, off)
	assert_eq(on, off, "presentation must not change a normal race")


func test_spectating_is_identical_with_and_without_presentation() -> void:
	var off := ProbeRunner.run(["mode=spectate", "presentation=0", "ticks=900"])
	var on := ProbeRunner.run(["mode=spectate", "presentation=1", "ticks=900"])
	assert_eq(off.length(), 32, off)
	assert_eq(on, off, "presentation must not change spectating")


func test_driving_physics_and_personalities_are_unchanged() -> void:
	var p: DrivingParams = load("res://src/driving/default_driving_params.tres")
	assert_eq([p.max_speed, p.acceleration, p.release_deceleration, p.brake_deceleration, p.turn_rate_degrees,
		p.full_steer_speed, p.grip, p.wall_restitution, p.wall_tangent_retention, p.car_restitution],
		[420.0, 260.0, 200.0, 520.0, 210.0, 0.0, 4.5, 0.3, 0.75, 0.4])
	var rocco: AiParams = load(RivalRoster.params_path(2))
	assert_eq([rocco.brake_anticipation, rocco.corner_commitment, rocco.overcommit_chance], [0.04, 1.02, 0.12])
	var victor: AiParams = load(RivalRoster.params_path(1))
	assert_eq([victor.brake_anticipation, victor.corner_commitment, victor.pass_on_straights_only], [0.2, 0.97, true])
	var ellie: AiParams = load(RivalRoster.params_path(3))
	assert_eq([ellie.pressure_distance, ellie.fluster_chance_per_second], [110.0, 0.6])
	assert_eq([victor.pass_lookahead, victor.pass_speed_margin, victor.follow_gap, victor.lane_change_rate],
		[120.0, 6.0, 95.0, 105.0], "Victor's latest adjustment (8d58ccd)")


func test_scenery_is_decorative_and_clear_of_the_track() -> void:
	var m := await _main(true)
	var scenery: TrackScenery = m.scenery
	assert_gt(scenery.get_child_count(), 60, "plenty of props")
	assert_gt(scenery.sway_count(), 5, "trees sway")
	assert_gt(scenery.flag_count(), 0, "flags wave")
	assert_eq(scenery.find_children("*", "CollisionObject2D", true, false).size(), 0, "no collision")
	assert_eq(m.get_node("Decals").find_children("*", "CollisionObject2D", true, false).size(), 0)
	var half: float = m.track.layout.road_width * 0.5
	for spr in scenery.get_children():
		if spr is Sprite2D and spr.z_index >= 0:
			var p: Dictionary = m.track.path.project(spr.global_position)
			assert_gt(absf(p.lateral), half + 40.0, "prop %s clear of the barrier" % spr.texture.resource_path.get_file())


func test_scenery_layout_is_the_same_every_time() -> void:
	var a := await _main(true)
	var pa: Array = a.scenery.get_children().map(func(n: Node) -> Vector2: return n.position)
	a.queue_free()
	await wait_physics_frames(2)
	var b := await _main(true)
	var pb: Array = b.scenery.get_children().map(func(n: Node) -> Vector2: return n.position)
	assert_eq(pa, pb)


func test_tyre_marks_appear_when_sliding_and_not_in_fast_mode() -> void:
	var m := await _main(true)
	Input.action_press(PlayerControls.FIRE)
	await wait_physics_frames(2)
	m.car.model.velocity = Vector2(0, 300).rotated(m.car.global_rotation)  # pure sideways slide
	await wait_physics_frames(4)
	assert_gt(m.effects.mark_count(), 0, "marks while sliding")
	m.set_sim_speed(4)
	assert_false(m.effects.visible, "effects reduced in fast mode")
	m.set_sim_speed(1)
	assert_true(m.effects.visible)


func test_hud_shows_tower_and_podium_stars_in_results() -> void:
	var m := await _main(true)
	await wait_physics_frames(2)
	assert_eq(m.hud._tower_rows.size(), 10, "one row per car")
	var rows: Array = m.hud._tower_rows
	assert_eq(rows[9][3].text, "YOU", "player starts last")
	m.session.start()
	for lap in m.track.layout.lap_count:
		for i in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 0]:
			m.session.checkpoint_reached(i, 1)
	m.hud.show_results(m.session.standings())
	var stars: Array = m.hud._message_box.find_children("*", "TextureRect", true, false).filter(
		func(t: TextureRect) -> bool: return t.texture == m.hud._stars[0])
	assert_eq(stars.size(), 1, "gold star for the winner")


func test_history_panel_hides_without_stopping_the_race() -> void:
	var m := await _main(true)
	m.set_menu_choice(2)
	m.start_race()
	await wait_physics_frames(10)
	var elapsed: float = m.session.elapsed
	Input.action_press(PlayerControls.TOGGLE_PANEL)
	await wait_physics_frames(2)
	Input.action_release(PlayerControls.TOGGLE_PANEL)
	assert_false(m.hud.history_panel.visible)
	assert_eq(m.session.state, RaceSession.State.RACING)
	await wait_physics_frames(10)
	assert_gt(m.session.elapsed, elapsed, "race keeps running")


func test_title_starts_a_race_and_returns() -> void:
	var game := GAME_SCENE.instantiate()
	game.achievements_path = "user://test_game_achievements.cfg"
	add_child_autofree(game)
	await wait_physics_frames(3)
	assert_true(game.title._ui.visible)
	await game.start_race(1)
	assert_not_null(game.race)
	assert_eq(game.race.session.control_mode, CarModel.ControlMode.FIRE_TO_BRAKE)
	assert_false(game.title._ui.visible)
	assert_true(game.race.camera.is_current())
	await game.back_to_title()
	assert_null(game.race)
	assert_true(game.title._ui.visible)
	await game.start_race(2)
	assert_true(game.race.session.spectator)
	assert_eq(game.race.session.state, RaceSession.State.RACING, "spectating starts straight away")
	game.title.stop_audio()
