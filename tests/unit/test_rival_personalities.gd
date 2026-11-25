extends GutTest
## M2.3: the six new personalities. Traits shape decisions only (player inputs),
## neutral defaults change nothing, and each new rival's trait is recognisable.

const DT := 1.0 / 60.0

var _line: RacingLine
var _corner_s := 0.0


func before_all() -> void:
	# Straight test line (+X) with a loop back, so lateral positions are exact.
	var pts := PackedVector2Array()
	for i in 100:
		pts.append(Vector2(i * 20.0, 0.0))
	for i in 100:
		pts.append(Vector2(2000.0 - i * 20.0, 3000.0))
	var flat := AiParams.new()
	flat.line_iterations = 0
	_line = RacingLine.new(ClosedPath.new(pts), 150.0, DrivingParams.new(), flat)


func _params(id: int) -> AiParams:
	return load(RivalRoster.params_path(id))


func _me(s: float, lateral: float, speed: float) -> Dictionary:
	return {"position": Vector2(s, lateral), "heading": 0.0, "speed": speed, "distance": s, "lateral": lateral}


func _run(d: AiDriver, me: Dictionary, others: Array, ticks: int) -> void:
	for i in ticks:
		d.decide(me, others, DT)


func test_all_nine_rivals_have_personalities() -> void:
	for id in range(1, 10):
		assert_true(RivalRoster.has_personality(id), RivalRoster.short_name(id))
		assert_not_null(load(RivalRoster.params_path(id)))


func test_new_traits_are_neutral_by_default() -> void:
	var p := AiParams.new()
	assert_eq([p.defend_distance, p.pass_check_clearance, p.pass_side, p.disrupted_threshold, p.pass_impulse_chance],
		[0.0, false, 0, 0.0, 0.0])
	for id in [1, 3]:
		var q := _params(id)
		assert_eq([q.defend_distance, q.pass_check_clearance, q.pass_side, q.disrupted_threshold, q.pass_impulse_chance],
			[0.0, false, 0, 0.0, 0.0], "pilot rival %d untouched" % id)
	# Rocco blocks since the racecraft update (2026-11-16): aggressive defending only
	var r := _params(2)
	assert_eq([r.pass_check_clearance, r.pass_side, r.disrupted_threshold, r.pass_impulse_chance], [false, 0, 0.0, 0.0])
	assert_gt(r.defend_distance, 0.0, "Rocco defends")


func test_victor_keeps_the_latest_adjustment() -> void:
	var v := _params(1)
	assert_eq([v.pass_lookahead, v.pass_speed_margin, v.follow_gap, v.lane_change_rate], [120.0, 6.0, 95.0, 105.0])


func test_hank_covers_the_line_of_a_closing_car() -> void:
	var hank := AiDriver.new(_line, _params(4))
	var neutral := AiDriver.new(_line, AiParams.new())
	var chaser := [{"distance": 440.0, "lateral": 30.0, "speed": 330.0}]
	_run(hank, _me(500.0, 0.0, 320.0), chaser, 40)
	_run(neutral, _me(500.0, 0.0, 320.0), chaser, 40)
	assert_gt(hank.lane_bias, 15.0, "moves across to defend")
	assert_eq(neutral.lane_bias, 0.0)
	assert_gt(hank.defends, 0)


func test_hank_ignores_slower_cars_behind() -> void:
	var hank := AiDriver.new(_line, _params(4))
	_run(hank, _me(500.0, 0.0, 320.0), [{"distance": 440.0, "lateral": 30.0, "speed": 200.0}], 40)
	assert_eq(hank.defends, 0)


func test_maya_does_not_force_a_pass_into_an_occupied_lane() -> void:
	var p := _params(5)
	var maya := AiDriver.new(_line, p)
	var slow_ahead := {"distance": 580.0, "lateral": 0.0, "speed": 200.0}
	_run(maya, _me(500.0, 0.0, 320.0), [slow_ahead], 30)
	assert_ne(maya.lane_bias, 0.0, "passes when the lane is clear")
	var maya2 := AiDriver.new(_line, p)
	var blockers := [slow_ahead, {"distance": 560.0, "lateral": -p.pass_offset, "speed": 300.0},
		{"distance": 560.0, "lateral": p.pass_offset, "speed": 300.0}]
	_run(maya2, _me(500.0, 0.0, 320.0), blockers, 30)
	assert_lt(absf(maya2.lane_bias), p.pass_offset * 0.25, "waits instead of forcing (only her own line drift)")


func test_dante_passes_on_the_outside_of_the_next_corner() -> void:
	# Real circuit: find a point before a right-hander; the outside is the left (-lateral).
	var layout: TrackLayout = load("res://src/track/circuit_01.tres")
	var line := RacingLine.new(ClosedPath.new(layout.sample_centerline()), layout.road_width, DrivingParams.new(),
		load("res://src/ai/default_ai_params.tres"))
	var dante := AiDriver.new(line, _params(6))
	var s := 0.0
	while dante._turn_direction(s) == 0.0:
		s += 25.0
	var turn := dante._turn_direction(s)
	var lat := line.offset_at(s)
	var me := {"position": line.point_with_lateral(s, lat), "heading": line.center.tangent_at(s).angle(),
		"speed": 380.0, "distance": s, "lateral": lat}
	_run(dante, me, [{"distance": s + 70.0, "lateral": lat, "speed": 250.0}], 20)
	assert_eq(signf(dante.pass_side_choice), -turn, "outside of the corner")


func test_greta_loses_composure_when_pushed_off_line() -> void:
	var greta := AiDriver.new(_line, _params(7))
	greta.lane_bias = 40.0
	greta.decide(_me(500.0, 40.0, 300.0), [], DT)
	assert_gt(greta.disrupted_time, 0.0)
	assert_eq(greta.disruptions, 1)
	var calm := AiDriver.new(_line, _params(7))
	calm.decide(_me(500.0, 0.0, 300.0), [], DT)
	assert_eq(calm.disruptions, 0)


func test_finn_sometimes_attempts_impulsive_passes() -> void:
	var finn := AiDriver.new(_line, _params(8))
	finn.begin_race(11)
	var neutral := AiDriver.new(_line, AiParams.new())
	var same_speed := [{"distance": 600.0, "lateral": 0.0, "speed": 320.0}]
	_run(finn, _me(500.0, 0.0, 320.0), same_speed, 300)
	_run(neutral, _me(500.0, 0.0, 320.0), same_speed, 300)
	assert_gt(finn.impulse_passes, 0)
	assert_eq(neutral.impulse_passes, 0)


func test_nina_follows_closer_and_only_attacks_on_straights() -> void:
	var nina := _params(9)
	assert_lt(nina.follow_gap, AiParams.new().follow_gap, "hunts close behind")
	assert_true(nina.pass_on_straights_only, "times her attacks")


func test_personality_decisions_are_reproducible_per_seed() -> void:
	for id in range(4, 10):
		var a := AiDriver.new(_line, _params(id))
		var b := AiDriver.new(_line, _params(id))
		a.begin_race(5)
		b.begin_race(5)
		var others := [{"distance": 560.0, "lateral": 5.0, "speed": 300.0}, {"distance": 450.0, "lateral": -20.0, "speed": 330.0}]
		for i in 200:
			var me := _me(500.0 + i, 0.0, 310.0)
			assert_eq(a.decide(me, others, DT), b.decide(me, others, DT), RivalRoster.short_name(id))
