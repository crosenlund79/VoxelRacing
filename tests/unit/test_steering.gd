extends GutTest
## Straight-line steering precision (SteerShaper): short taps make small
## corrections at speed, held steering keeps its authority, low-speed steering
## stays immediate, a stick is proportional. The driving model is unchanged.

const DT := 1.0 / 60.0


## Heading change (deg) and sideways drift (px) one second after a tap of
## `ticks` ticks, at speed_share of top speed, with or without shaping.
func _tap(ticks: int, speed_share: float, shaped: bool, hold := 0) -> Dictionary:
	var params: DrivingParams = load("res://src/driving/default_driving_params.tres")
	var m := CarModel.new(params)
	m.velocity = Vector2(params.max_speed * speed_share, 0)
	var sh := SteerShaper.new()
	var total := ticks + hold
	for t in 60:
		var raw := 1.0 if t < total else 0.0
		var steer := sh.step(raw, m.velocity.length() / params.max_speed, DT) if shaped else raw
		m.update(DT, steer, true)
		m.integrate(DT)
	return {"heading": rad_to_deg(m.heading), "drift": m.position.y}


func test_short_taps_are_small_corrections_at_speed() -> void:
	for ticks in [2, 5]:
		var before := _tap(ticks, 1.0, false)
		var after := _tap(ticks, 1.0, true)
		gut.p("top speed, %d-tick tap: heading %.1f -> %.1f deg, drift %.1f -> %.1f px" % [
			ticks, before.heading, after.heading, before.drift, after.drift])
		assert_lt(after.heading, before.heading * 0.5, "a tap turns much less")
		assert_gt(after.heading, 0.0, "but still turns")


func test_held_steering_keeps_its_authority() -> void:
	var before := _tap(60, 1.0, false)
	var after := _tap(60, 1.0, true)
	gut.p("top speed, held 1 s: %.0f -> %.0f deg" % [before.heading, after.heading])
	assert_gt(after.heading, before.heading - 15.0, "a held turn loses at most ~15 deg in its first second")
	var low_b := _tap(30, 0.25, false)
	var low_a := _tap(30, 0.25, true)
	gut.p("quarter speed, held 0.5 s: %.0f -> %.0f deg" % [low_b.heading, low_a.heading])
	assert_gt(low_a.heading, low_b.heading - 6.0, "low speed: nearly immediate")


func test_release_and_reverse_are_immediate() -> void:
	var sh := SteerShaper.new()
	for i in 20:
		sh.step(1.0, 1.0, DT)
	assert_eq(sh.value, 1.0, "full lock when held")
	assert_eq(sh.step(0.0, 1.0, DT), 0.0, "release: straight at once")
	sh.step(1.0, 1.0, DT)
	assert_lt(sh.step(-1.0, 1.0, DT), 0.0, "reversing starts from zero, not from the old side")
	assert_eq(sh.step(-0.3, 1.0, DT), -0.3 if absf(sh.value) > 0.3 else sh.value, "less steering: at once")


func test_stick_is_proportional_keys_are_full() -> void:
	PlayerControls.ensure_actions()
	var e := InputEventJoypadMotion.new()
	e.axis = JOY_AXIS_LEFT_X
	for v in [0.1, 0.4, 0.7, 1.0]:
		e.axis_value = v
		Input.parse_input_event(e)
		await wait_process_frames(1)
		var s := PlayerControls.steer()
		gut.p("stick %.1f -> steer %.2f" % [v, s])
		if v <= PlayerControls.STEER_DEADZONE:
			assert_eq(s, 0.0, "inside the deadzone")
		else:
			assert_between(s, 0.0, 1.0)
	e.axis_value = 0.4
	Input.parse_input_event(e)
	await wait_process_frames(1)
	var half := PlayerControls.steer()
	assert_lt(half, 0.5, "a small tilt is a small correction")
	e.axis_value = 1.0
	Input.parse_input_event(e)
	await wait_process_frames(1)
	assert_eq(PlayerControls.steer(), 1.0, "full tilt is full lock")
	e.axis_value = 0.0
	Input.parse_input_event(e)
	await wait_process_frames(2)
	Input.action_press(PlayerControls.STEER_LEFT)
	assert_eq(PlayerControls.steer(), -1.0, "a key is full lock")
	Input.action_release(PlayerControls.STEER_LEFT)
