extends GutTest
## M4 Stage 0: the shared driver-input foundation. Humans and AI supply the
## same commands; the session supports several human racer ids; single-player
## races are unchanged (fingerprints in test_multiplayer_regression).

const MAIN_SCENE := preload("res://src/main/main.tscn")

var _main: Node2D


func before_each() -> void:
	_main = MAIN_SCENE.instantiate()
	_main.presentation_enabled = false
	add_child_autofree(_main)
	await wait_physics_frames(2)


func after_each() -> void:
	for a in ["t1_steer_left", "t1_steer_right", "t1_fire", "t1_fire_front", "t1_fire_rear"]:
		if InputMap.has_action(a):
			Input.action_release(a)
			InputMap.erase_action(a)


func test_every_car_has_an_input_human_for_the_player_ai_for_rivals() -> void:
	assert_eq(_main.inputs.size(), _main.cars.size())
	assert_true(_main.inputs[0] is HumanDriverInput)
	assert_true(_main.inputs[0].is_human())
	for id in range(1, 10):
		assert_true(_main.inputs[id] is AiDriverInput, "rival %d" % id)
		assert_false(_main.inputs[id].is_human())
		assert_eq(_main.inputs[id].driver, _main.drivers[id], "wraps the same AiDriver")
		assert_eq(_main.inputs[id].racer_id, id)


func test_ai_input_gives_the_same_decisions_as_the_ai_driver() -> void:
	_main.start_race()
	await wait_physics_frames(120)
	var id := 4
	var ref := AiDriver.new(_main.racing_line, _main.drivers[id].params)
	ref.begin_race(77)
	_main.inputs[id].begin_race(77)
	var others: Array = []
	for other in _main.grid_order:
		if other != id:
			others.append({"distance": _main.progress[other].distance, "lateral": _main.progress[other].lateral,
				"speed": _main.cars[other].model.forward_speed()})
	var me := {"position": _main.cars[id].global_position, "heading": _main.cars[id].model.heading,
		"speed": _main.cars[id].model.forward_speed(), "distance": _main.progress[id].distance,
		"lateral": _main.progress[id].lateral}
	for k in 30:
		assert_eq(_main.inputs[id].drive(_main, 1.0 / 60.0), ref.decide(me, others, 1.0 / 60.0))


func test_human_input_reads_its_own_prefixed_actions() -> void:
	for a in ["steer_left", "steer_right", "fire", "fire_front", "fire_rear"]:
		InputMap.add_action("t1_" + a)
	var h := HumanDriverInput.new(0, "t1_")
	_main.start_race()
	Input.action_press("t1_steer_right")
	Input.action_press("t1_fire")
	var cmd := h.drive(_main, 1.0 / 60.0)
	assert_gt(cmd.steer, 0.0, "steering right (key steering ramps in: test_steering.gd)")
	for k in 10:
		cmd = h.drive(_main, 1.0 / 60.0)
	assert_eq(cmd, {"steer": 1.0, "fire": true, "pit_override": false})
	Input.action_press(PlayerControls.STEER_LEFT)
	assert_eq(h.drive(_main, 1.0 / 60.0).steer, 1.0, "default actions do not leak into a prefixed player")
	Input.action_release(PlayerControls.STEER_LEFT)


func test_finished_human_brakes_without_control() -> void:
	_main.start_race()
	var cps: int = _main.track.checkpoint_count()
	for lap in _main.session.lap_count():
		for i in range(1, cps):
			_main.session.checkpoint_reached(i, 0)
		_main.session.checkpoint_reached(0, 0)
	assert_eq(_main.inputs[0].drive(_main, 1.0 / 60.0), {"steer": 0.0, "fire": false, "pit_override": false})
	assert_eq(_main.inputs[0].weapons(_main, 1.0 / 60.0, []), {"front": false, "rear": false})


func test_session_with_two_humans_and_a_rival_sitting_out() -> void:
	var names := PackedStringArray()
	for i in 11:
		names.append("R%d" % i)
	var s := RaceSession.new(4, 1, names)
	s.set_humans([0, 10] as Array[int])
	s.set_sitting_out([9] as Array[int])
	assert_true(s.racers[0].is_player)
	assert_true(s.racers[10].is_player)
	assert_false(s.racers[3].is_player)
	assert_false(s.is_participating(9))
	assert_eq(s.racer_count(), 10)
	s.start()
	for i in [1, 2, 3, 0]:
		s.checkpoint_reached(i, 0)
	assert_eq(s.state, RaceSession.State.RACING, "one human finished: race goes on")
	assert_false(s.humans_finished())
	for i in [1, 2, 3, 0]:
		s.checkpoint_reached(i, 10)
	assert_eq(s.state, RaceSession.State.FINISHED, "both humans in")
	assert_eq(s.checkpoint_reached(1, 9), LapTracker.Result.IGNORED, "sitting-out rival takes no part")


func test_single_player_session_defaults_unchanged() -> void:
	var s := RaceSession.new(4, 1, PackedStringArray(["YOU", "A", "B"]))
	assert_eq(s.human_ids, [0] as Array[int])
	assert_true(s.racers[0].is_player)
	s.set_spectator(true)
	assert_false(s.is_participating(0))
	assert_true(s.is_participating(1))
