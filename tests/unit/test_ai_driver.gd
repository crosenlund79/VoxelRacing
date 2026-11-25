extends GutTest
## AiDriver decisions: player-equivalent inputs only, steering towards the line,
## throttle from the speed profile, following and passing traffic.

var _line: RacingLine
var _params: AiParams


func before_all() -> void:
	# Long straight loop: line at y = 0 heading +X for the first 2000 px.
	var pts := PackedVector2Array()
	for i in 100:
		pts.append(Vector2(i * 20.0, 0.0))
	for i in 100:
		pts.append(Vector2(2000.0 - i * 20.0, 3000.0))
	_params = AiParams.new()
	_params.line_iterations = 0  # line = centreline, so expected inputs are exact
	var driving := DrivingParams.new()
	_line = RacingLine.new(ClosedPath.new(pts), 150.0, driving, _params)


func _me(pos: Vector2, heading: float, speed: float) -> Dictionary:
	return {"position": pos, "heading": heading, "speed": speed, "distance": pos.x, "lateral": pos.y}


func _driver() -> AiDriver:
	return AiDriver.new(_line, _params)


func test_outputs_are_player_inputs_only() -> void:
	var out := _driver().decide(_me(Vector2(500, 0), 0.0, 100.0), [], 1.0 / 60.0)
	assert_has([-1.0, 0.0, 1.0], out.steer)
	assert_typeof(out.fire, TYPE_BOOL)


func test_steers_back_towards_the_line() -> void:
	var d := _driver()
	assert_eq(d.decide(_me(Vector2(500, -40), 0.0, 200.0), [], 1.0 / 60.0).steer, 1.0, "line is to the right (+Y)")
	assert_eq(d.decide(_me(Vector2(500, 40), 0.0, 200.0), [], 1.0 / 60.0).steer, -1.0)
	assert_eq(d.decide(_me(Vector2(500, 0), 0.0, 200.0), [], 1.0 / 60.0).steer, 0.0, "on line, pointing ahead")


func test_accelerates_below_target_speed_and_brakes_above() -> void:
	var d := _driver()
	assert_true(d.decide(_me(Vector2(500, 0), 0.0, 100.0), [], 1.0 / 60.0).fire)
	var fast := _line.speed_at(500.0) + 50.0
	assert_false(d.decide(_me(Vector2(500, 0), 0.0, fast), [], 1.0 / 60.0).fire)


func test_moves_out_to_pass_a_slower_car_ahead() -> void:
	var d := _driver()
	var slower := [{"distance": 600.0, "lateral": 0.0, "speed": 100.0}]
	for i in 30:
		d.decide(_me(Vector2(500, 0), 0.0, 300.0), slower, 1.0 / 60.0)
	assert_gt(absf(d.lane_bias), 20.0, "shifted sideways to pass")


func test_follows_instead_of_ramming_a_close_car_at_same_speed() -> void:
	var d := _driver()
	var close := [{"distance": 560.0, "lateral": 0.0, "speed": 300.0}]
	var out := d.decide(_me(Vector2(500, 0), 0.0, 300.0), close, 1.0 / 60.0)
	assert_false(out.fire, "eases off")
	assert_eq(d.lane_bias, 0.0, "no pass attempt on an equally fast car")


func test_ignores_cars_behind_far_ahead_or_beside() -> void:
	var d := _driver()
	var others := [
		{"distance": 400.0, "lateral": 0.0, "speed": 0.0},
		{"distance": 900.0, "lateral": 0.0, "speed": 0.0},
		{"distance": 560.0, "lateral": 60.0, "speed": 0.0},
	]
	assert_true(d.decide(_me(Vector2(500, 0), 0.0, 100.0), others, 1.0 / 60.0).fire)
	assert_eq(d.lane_bias, 0.0)


func test_pass_side_must_fit_inside_the_road() -> void:
	var d := _driver()
	var limit := 75.0 - _params.pass_margin
	var side := d.choose_pass_lateral(-10.0, 0.0)
	assert_almost_eq(side, -_params.pass_offset, 0.001, "nearest side")
	assert_lte(absf(side), limit)
	assert_true(is_nan(d.choose_pass_lateral(0.0, 0.0)) == (_params.pass_offset > limit))
