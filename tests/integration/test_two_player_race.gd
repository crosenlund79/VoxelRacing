extends GutTest
## M4 Stage 1: two human drivers. 10 cars (2 humans + 8 rivals), one rival
## rotating out per race, device-specific inputs, same physics and combat
## rules, both humans must finish (with a stuck-player safety net), results
## naming both, reversed grids with the rotation, garage / achievements off.

const MAIN_SCENE := preload("res://src/main/main.tscn")
const P1 := RaceSession.PLAYER_ID
const P2 := RaceSession.PLAYER_2_ID
const PAD1 := 3
const PAD2 := 4

var _main: Node2D


func before_each() -> void:
	_main = MAIN_SCENE.instantiate()
	_main.weapons_lock_enabled = false  # fires at once (the start lock: test_weapons_hot.gd)
	_main.presentation_enabled = false
	_main.human_count = 2
	_main.player_devices = [PAD1, PAD2] as Array[int]
	_main.garage = PlayerGarage.new(load("res://src/garage/default_garage_rules.tres"))
	_main.achievements = AchievementStore.new("user://test_two_player_should_not_exist.cfg")
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
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_two_player_should_not_exist.cfg"))


func _pad_button(device: int, button: JoyButton, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = device
	e.button_index = button
	e.pressed = pressed
	Input.parse_input_event(e)


func _finish(id: int) -> void:
	var cps: int = _main.track.checkpoint_count()
	for lap in _main.session.lap_count():
		for i in range(1, cps):
			_main.session.checkpoint_reached(i, id)
		_main.session.checkpoint_reached(0, id)


## Enter on the results (Fire never leaves them).
func _tap_fire() -> void:
	Input.action_press(PlayerControls.CONFIRM)
	await wait_physics_frames(2)
	Input.action_release(PlayerControls.CONFIRM)
	await wait_physics_frames(1)


func test_field_is_two_humans_and_eight_rivals() -> void:
	assert_eq(_main.cars.size(), 11)
	assert_eq(_main.grid_order.size(), 10)
	assert_eq(_main.grid_order, [2, 3, 4, 5, 6, 7, 8, 9, P2, P1] as Array[int], "P1 last, P2 ahead of P1")
	assert_eq(_main.session.human_ids, [P1, P2] as Array[int])
	assert_false(_main.session.is_participating(1), "Victor sits out the first race")
	assert_false(_main.cars[1].visible)
	assert_eq(_main.cars[1].collision_layer, 0, "no collision for the rival sitting out")
	for id in _main.grid_order:
		assert_eq(_main.cars[id].collision_layer, 2)
		assert_eq(_main.cars[id].collision_mask, 3)
	assert_eq(_main.session.racer_count(), 10)
	assert_true(_main.inputs[P1].is_human() and _main.inputs[P2].is_human())
	for id in range(1, 10):
		assert_eq(_main.drivers[id].params.resource_path, RivalRoster.params_path(id), "rival %d keeps their personality" % id)


func test_each_controller_drives_only_its_own_car() -> void:
	_main.start_race()
	_pad_button(PAD2, JOY_BUTTON_A, true)
	_pad_button(PAD2, JOY_BUTTON_DPAD_RIGHT, true)
	await wait_physics_frames(1)
	assert_eq(_main.inputs[P2].drive(_main, 1.0 / 60.0), {"steer": 1.0, "fire": true, "pit_override": false})
	assert_eq(_main.inputs[P1].drive(_main, 1.0 / 60.0), {"steer": 0.0, "fire": false, "pit_override": false}, "P1 untouched by pad 2")
	_pad_button(PAD2, JOY_BUTTON_A, false)
	_pad_button(PAD2, JOY_BUTTON_DPAD_RIGHT, false)
	_pad_button(PAD1, JOY_BUTTON_DPAD_LEFT, true)
	await wait_physics_frames(1)
	assert_eq(_main.inputs[P1].drive(_main, 1.0 / 60.0).steer, -1.0)
	assert_eq(_main.inputs[P2].drive(_main, 1.0 / 60.0).steer, 0.0)
	_pad_button(PAD1, JOY_BUTTON_DPAD_LEFT, false)
	Input.action_press(PlayerControls.FIRE)
	assert_false(_main.inputs[P1].drive(_main, 1.0 / 60.0).fire, "single-player actions do not drive two-player cars")
	Input.action_release(PlayerControls.FIRE)


func test_both_humans_drive_with_the_same_physics() -> void:
	_main.start_race()
	Input.action_press("p1_fire")
	Input.action_press("p2_fire")
	await wait_physics_frames(90)
	var v1: float = _main.cars[P1].model.forward_speed()
	var v2: float = _main.cars[P2].model.forward_speed()
	assert_gt(v1, 100.0)
	assert_gt(v2, 100.0)
	assert_eq(_main.cars[P1].model.params, _main.cars[P2].model.params)
	assert_ne(_main.session.position_of(P1), 0)
	assert_ne(_main.session.position_of(P2), 0)


func test_each_human_fires_their_own_weapons() -> void:
	_main.set_weapons_enabled(true)
	_main.start_race()
	await wait_physics_frames(2)
	var before1: int = _main.combat.ammo[P1][0]
	var before2: int = _main.combat.ammo[P2][0]
	_pad_button(PAD2, JOY_BUTTON_DPAD_UP, true)
	await wait_physics_frames(2)
	_pad_button(PAD2, JOY_BUTTON_DPAD_UP, false)
	assert_eq(_main.combat.ammo[P2][0], before2 - 1, "P2 fired")
	assert_eq(_main.combat.ammo[P1][0], before1, "P1 did not")
	_pad_button(PAD1, JOY_BUTTON_DPAD_DOWN, true)
	await wait_physics_frames(2)
	_pad_button(PAD1, JOY_BUTTON_DPAD_DOWN, false)
	assert_eq(_main.combat.mines.size(), 1, "P1 dropped a mine")


func test_race_waits_for_both_humans_and_names_them() -> void:
	_main.start_race()
	_finish(P1)
	await wait_physics_frames(2)
	assert_eq(_main.session.state, RaceSession.State.RACING, "P2 still racing")
	_finish(P2)
	await wait_physics_frames(3)
	assert_eq(_main.session.state, RaceSession.State.FINISHED)
	var labels: Array = _main.hud._message_box.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	assert_has(labels, "PLAYER 1")
	assert_has(labels, "PLAYER 2")
	var tower: Array = _main.hud._tower_rows.map(func(p: Array) -> String: return p[3].text)
	assert_has(tower, "P1")
	assert_has(tower, "P2")


func test_stuck_player_does_not_hold_up_the_results_forever() -> void:
	_main.human_stuck_timeout = 2.0
	_main.set_sim_speed(4)
	_main.start_race()
	_finish(P1)
	Input.action_press("p2_fire")  # P2 keeps driving: never cut short
	await wait_physics_frames(4 * 60 * 3)
	assert_eq(_main.session.state, RaceSession.State.RACING, "a moving player is not ended")
	Input.action_release("p2_fire")
	await wait_until(func() -> bool: return _main.session.state == RaceSession.State.FINISHED, 30.0)
	assert_eq(_main.session.state, RaceSession.State.FINISHED, "a player stuck for the timeout releases the results")
	assert_false(_main.session.racers[P2].is_finished(), "P2 shown as still running")


func test_no_safety_net_before_anyone_finishes() -> void:
	_main.human_stuck_timeout = 1.0
	_main.start_race()
	await wait_physics_frames(150)  # nobody pressed anything; nobody has finished
	assert_eq(_main.session.state, RaceSession.State.RACING)


func test_rotation_and_reversed_grid_across_races() -> void:
	for round in 10:
		var sitting: int = _main.sitting_out_rival(round)
		assert_eq(sitting, round % 9 + 1)
	_main.start_race()
	await wait_physics_frames(30)
	_finish(P2)
	_finish(P1)
	await wait_physics_frames(2)
	var reversed: Array[int] = _main.session.reversed_grid()
	await _tap_fire()
	assert_eq(_main.multiplayer_round, 1)
	assert_false(_main.session.is_participating(2), "Rocco sits out race 2")
	assert_true(_main.session.is_participating(1), "Victor is back")
	var expected := reversed.duplicate()
	expected[expected.find(2)] = 1
	assert_eq(_main.grid_order, expected, "reversed grid, Victor takes Rocco's slot")
	assert_eq(_main.grid_order[-1], reversed[-1], "the winner still starts last")
	assert_true(_main.cars[1].visible)
	assert_eq(_main.cars[1].collision_layer, 2)
	assert_false(_main.cars[2].visible)


func test_garage_and_achievements_are_off() -> void:
	assert_null(_main.garage)
	assert_null(_main.achievements)
	assert_null(_main.achievement_tracker)
	_main.start_race()
	_finish(P1)
	_finish(P2)
	await _tap_fire()
	assert_false(FileAccess.file_exists("user://test_two_player_should_not_exist.cfg"))


func test_menu_ignores_spectate_in_two_player() -> void:
	_main.set_menu_choice(2)
	assert_false(_main.session.spectator)
	Input.action_press("p2_fire")  # P2's own Fire starts the race from the grid panel
	await wait_physics_frames(2)
	Input.action_release("p2_fire")
	assert_eq(_main.session.state, RaceSession.State.RACING)
