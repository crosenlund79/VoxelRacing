extends GutTest
## The in-race Esc menu: RESUME RACE / LEAVE RACE. Single-player, spectator and
## couch races pause (a resumed race is bit-identical to one never paused); the
## menu never restarts the race; gameplay controls do nothing while it is open;
## leaving returns to the title without stale races, unpaused, and an unfinished
## garage race pays nothing and uses no rounds. (Network: test_net_session_flow.)

const MAIN_SCENE := preload("res://src/main/main.tscn")
const GAME_SCENE := preload("res://src/main/game.tscn")

var _main: Node2D


func after_each() -> void:
	if is_inside_tree():
		get_tree().paused = false
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0
	Engine.max_physics_steps_per_frame = 8
	for a in [PlayerControls.BACK, PlayerControls.FIRE, PlayerControls.STEER_LEFT, PlayerControls.FIRE_FRONT, "p2_" + PlayerControls.BACK]:
		if InputMap.has_action(a):
			Input.action_release(a)


func _make(humans := 1) -> void:
	_main = MAIN_SCENE.instantiate()
	_main.presentation_enabled = false
	if humans == 2:
		_main.human_count = 2
		_main.player_devices = [3, 4] as Array[int]
	add_child_autofree(_main)
	await wait_physics_frames(2)


func _tap(action: String) -> void:
	Input.action_press(action)
	await wait_process_frames(2)
	Input.action_release(action)
	await wait_process_frames(1)


func test_esc_pauses_and_resume_continues_the_same_race() -> void:
	await _make()
	_main.start_race()
	Input.action_press(PlayerControls.FIRE)
	await wait_physics_frames(90)
	await _tap(PlayerControls.BACK)
	assert_true(_main.menu_open)
	assert_true(_main.race_menu.is_open())
	assert_true(get_tree().paused, "single-player pauses")
	var t0: float = _main.session.elapsed
	var p0: Vector2 = _main.car.global_position
	await wait_process_frames(20)
	assert_eq(_main.session.elapsed, t0, "the clock stops")
	assert_eq(_main.car.global_position, p0, "cars stop")
	await _tap(PlayerControls.BACK)  # Esc again: resume
	assert_false(_main.menu_open)
	assert_false(get_tree().paused)
	await wait_physics_frames(30)
	assert_eq(_main.session.state, RaceSession.State.RACING, "same race, not restarted")
	assert_gt(_main.session.elapsed, t0, "carries on from where it was")
	assert_gt(_main.car.global_position.distance_to(p0), 10.0)


func test_menu_only_during_a_race() -> void:
	await _make()
	await _tap(PlayerControls.BACK)
	assert_false(_main.menu_open, "not on the grid panel (Esc there still leaves)")


func test_gameplay_controls_do_nothing_while_the_menu_is_open() -> void:
	await _make()
	_main.start_race()
	await wait_physics_frames(5)
	_main.open_race_menu()
	Input.action_press(PlayerControls.STEER_LEFT)
	Input.action_press(PlayerControls.FIRE)
	Input.action_press(PlayerControls.FIRE_FRONT)
	var cmd: Dictionary = _main.inputs[0].drive(_main, Car.FIXED_STEP)
	var shots: Dictionary = _main.inputs[0].weapons(_main, Car.FIXED_STEP, [])
	assert_eq(cmd.steer, 0.0, "no steering from menu navigation")
	assert_false(cmd.fire, "brakes (Fire to Accelerate: no throttle)")
	assert_false(shots.front, "Up never fires a missile")
	_main.resume_race()


func test_a_paused_and_resumed_race_is_identical_to_one_never_paused() -> void:
	# the same fingerprint as an unpaused race (fresh processes), with a 90-frame pause mid-race
	for c in [[["mode=race", "ticks=3600", "weapons=1", "style=1"], "pause=1200", "racing"],
			[["mode=spectate", "ticks=4800", "weapons=1"], "pause=1500", "spectating"]]:
		var plain := ProbeRunner.run(PackedStringArray(c[0]))
		assert_ne(plain, "")
		assert_eq(ProbeRunner.run(PackedStringArray(c[0] + [c[1]])), plain, c[2])


func test_couch_race_pauses_for_either_player() -> void:
	await _make(2)
	_main.start_race()
	await wait_physics_frames(10)
	await _tap("p2_" + PlayerControls.BACK)
	assert_true(_main.menu_open, "Player 2's Back opens it")
	assert_true(get_tree().paused, "the shared race pauses")
	_main.resume_race()
	assert_false(get_tree().paused)


## A couch player's controller unplugged mid-race pauses the race with a
## message; another device (not in the race) does not.
func test_couch_controller_disconnect_pauses() -> void:
	await _make(2)
	_main.start_race()
	await wait_physics_frames(5)
	_main._on_joy_connection(7, false)
	assert_false(_main.menu_open, "a pad that is not racing")
	_main._on_joy_connection(4, false)
	assert_true(_main.menu_open, "player 2's pad: paused")
	assert_true(get_tree().paused)
	assert_string_contains(_main.race_menu._note.text, "PLAYER 2: CONTROLLER DISCONNECTED")
	_main.resume_race()
	assert_false(get_tree().paused)


func test_leave_returns_to_the_title_cleanly_and_a_new_race_works() -> void:
	var game: Node = GAME_SCENE.instantiate()
	game.achievements_path = "user://test_race_menu_ach.cfg"
	add_child_autofree(game)
	await wait_physics_frames(3)
	game.start_race(0)
	await wait_physics_frames(30)
	var race: Node2D = game.race
	race.start_race()
	await wait_physics_frames(30)
	race.open_race_menu()
	assert_true(get_tree().paused)
	race.leave_race()
	assert_false(get_tree().paused, "never left paused")
	await wait_physics_frames(40)
	assert_null(game.race, "race gone")
	assert_false(is_instance_valid(race), "freed, no stale race scene")
	assert_true(game.title._ui.visible, "back at the title")
	assert_eq(game.find_children("*", "Node2D", false, false).filter(func(n: Node) -> bool: return n.has_method("open_race_menu")).size(), 0)
	game.start_race(0)
	await wait_physics_frames(30)
	assert_not_null(game.race, "a new race starts normally")
	assert_eq(game.race.session.state, RaceSession.State.MODE_SELECT)
	game.title.stop_audio()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_race_menu_ach.cfg"))


func test_leaving_a_garage_race_pays_nothing_and_keeps_every_round() -> void:
	var garage := PlayerGarage.new(load("res://src/garage/default_garage_rules.tres"))
	_main = MAIN_SCENE.instantiate()
	_main.presentation_enabled = false
	_main.garage = garage
	add_child_autofree(_main)
	await wait_physics_frames(2)
	var money := garage.money
	var stock := garage.stock.duplicate()
	_main.set_weapons_enabled(true)
	_main.start_race()
	await wait_physics_frames(5)
	assert_true(garage.race_pending())
	_main.combat.request(0, CombatWorld.FRONT, _main._combat_states())  # fire a round
	_main.open_race_menu()
	_main.leave_race()
	_main.free()  # the game frees the race scene on leaving
	assert_false(garage.race_pending(), "the race is abandoned")
	assert_eq(garage.money, money, "no prize for an unfinished race")
	assert_eq(garage.stock, stock, "no rounds used up")
	assert_false(get_tree().paused)
