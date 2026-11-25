extends GutTest
## Personality pilot: traits change decisions only (inputs stay steer -1/0/+1 and
## fire), neutral traits reproduce the shared driver, decisions are reproducible
## per seed, and Victor / Rocco / Ellie differ in recognisable ways.

const DT := 1.0 / 60.0

var _line: RacingLine
var _victor: AiParams
var _rocco: AiParams
var _ellie: AiParams
var _corner_s := 0.0


func before_all() -> void:
	var layout: TrackLayout = load("res://src/track/circuit_01.tres")
	var driving: DrivingParams = load("res://src/driving/default_driving_params.tres")
	_line = RacingLine.new(ClosedPath.new(layout.sample_centerline()), layout.road_width, driving,
		load("res://src/ai/default_ai_params.tres"))
	_victor = load(RivalRoster.params_path(1))
	_rocco = load(RivalRoster.params_path(2))
	_ellie = load(RivalRoster.params_path(3))
	# First point where the plan drops below top speed (the first braking zone).
	var s := 0.0
	while _line.speed_at(s) >= _line.top_speed - 1.0:
		s += 5.0
	_corner_s = s


## Car on the racing line at distance s, pointing along it.
func _me(s: float, speed: float, lateral := NAN) -> Dictionary:
	var lat := _line.offset_at(s) if is_nan(lateral) else lateral
	return {"position": _line.point_with_lateral(s, lat), "heading": _line.center.tangent_at(s).angle(),
		"speed": speed, "distance": s, "lateral": lat}


## Distance before the first braking zone at which a driver near top speed first lifts.
func _lift_point(params: AiParams, seed_value: int) -> float:
	var d := AiDriver.new(_line, params)
	d.begin_race(seed_value)
	var s := _corner_s - 600.0
	while s < _corner_s + 200.0:
		if not d.decide(_me(s, _line.top_speed - 5.0), [], DT).fire:
			return s
		s += 2.0
	return s


func test_rivals_without_personality_use_neutral_traits() -> void:
	var neutral: AiParams = load("res://src/ai/default_ai_params.tres")
	assert_eq(neutral.corner_commitment, 1.0)
	assert_eq(neutral.overcommit_chance, 0.0)
	assert_eq(neutral.pressure_distance, 0.0)
	assert_eq(neutral.brake_anticipation, 0.1, "same braking read-ahead as the M2 driver")
	assert_false(neutral.pass_check_clearance)


func test_neutral_driver_ignores_seed() -> void:
	var a := AiDriver.new(_line, AiParams.new())
	var b := AiDriver.new(_line, AiParams.new())
	a.begin_race(1)
	b.begin_race(99999)
	for i in 300:
		var s := _corner_s - 400.0 + i * 3.0
		assert_eq(a.decide(_me(s, 380.0), [], DT), b.decide(_me(s, 380.0), [], DT))


func test_same_seed_gives_same_decisions() -> void:
	var a := AiDriver.new(_line, _rocco)
	var b := AiDriver.new(_line, _rocco)
	a.begin_race(42)
	b.begin_race(42)
	for i in 600:
		var s := fmod(i * 13.0, _line.center.length)
		assert_eq(a.decide(_me(s, 350.0), [], DT), b.decide(_me(s, 350.0), [], DT))
	assert_eq(a.commitment, b.commitment)


func test_outputs_are_player_inputs_for_every_personality() -> void:
	for p in [_victor, _rocco, _ellie]:
		var d := AiDriver.new(_line, p)
		d.begin_race(7)
		for i in 200:
			var out := d.decide(_me(fmod(i * 37.0, _line.center.length), 300.0), [], DT)
			assert_has([-1.0, 0.0, 1.0], out.steer)
			assert_typeof(out.fire, TYPE_BOOL)


func test_rocco_brakes_later_than_victor() -> void:
	for seed_value in [1, 2, 3, 4, 5]:
		assert_gt(_lift_point(_rocco, seed_value), _lift_point(_victor, seed_value), "seed %d" % seed_value)


func test_victor_corner_commitment_is_consistent_and_rocco_varies() -> void:
	var victor_values := []
	var rocco_values := []
	for seed_value in 40:
		for pair in [[_victor, victor_values], [_rocco, rocco_values]]:
			var d := AiDriver.new(_line, pair[0])
			d.begin_race(seed_value)
			d.decide(_me(_corner_s + 10.0, 300.0), [], DT)
			pair[1].append(d.commitment)
	assert_lt(victor_values.max() - victor_values.min(), 0.021)
	assert_gt(rocco_values.max() - rocco_values.min(), 0.1, "includes occasional over-commitment")
	assert_lt(victor_values.max(), 1.0, "Victor never pushes beyond the plan")


func test_rocco_overcommits_occasionally_not_always() -> void:
	var d := AiDriver.new(_line, _rocco)
	var corners := 0
	for seed_value in 200:
		d.begin_race(seed_value)
		d.decide(_me(_corner_s + 10.0, 300.0), [], DT)
		corners += d.overcommits
	assert_between(corners, 5, 60, "about %d%% of corners" % int(_rocco.overcommit_chance * 100))


func test_victor_only_passes_on_straights_and_clearly_slower_cars() -> void:
	var victor := AiDriver.new(_line, _victor)
	var rocco := AiDriver.new(_line, _rocco)
	var s_zone := _corner_s - 30.0
	var slower := [{"distance": s_zone + 80.0, "lateral": _line.offset_at(s_zone), "speed": 250.0}]
	for i in 20:
		victor.decide(_me(s_zone, 300.0), slower, DT)
		rocco.decide(_me(s_zone, 300.0), slower, DT)
	assert_eq(victor.lane_bias, 0.0, "Victor waits for a straight")
	assert_ne(rocco.lane_bias, 0.0, "Rocco dives for the gap")
	var straight_s := _corner_s - 900.0
	var barely_slower := [{"distance": straight_s + 80.0, "lateral": _line.offset_at(straight_s), "speed": 295.0}]
	victor.begin_race(1)
	rocco.begin_race(1)
	for i in 20:
		victor.decide(_me(straight_s, 300.0), barely_slower, DT)
		rocco.decide(_me(straight_s, 300.0), barely_slower, DT)
	assert_eq(victor.lane_bias, 0.0, "not worth the risk for Victor")
	assert_ne(rocco.lane_bias, 0.0)


func test_ellie_only_gets_flustered_under_pressure() -> void:
	var d := AiDriver.new(_line, _ellie)
	d.begin_race(3)
	var s := 1000.0
	for i in 600:
		d.decide(_me(s, 300.0), [], DT)
	assert_eq(d.flusters, 0, "clean air")
	var chaser := [{"distance": s - 60.0, "lateral": _line.offset_at(s), "speed": 300.0}]
	assert_true(d.under_pressure(_me(s, 300.0), chaser))
	for i in 600:
		d.decide(_me(s, 300.0), chaser, DT)
	assert_gt(d.flusters, 0, "pressure from behind")


func test_flustered_ellie_hesitates_and_overcorrects() -> void:
	# Straight test line (line = centreline along +X) so heading errors are exact.
	var pts := PackedVector2Array()
	for i in 100:
		pts.append(Vector2(i * 20.0, 0.0))
	for i in 100:
		pts.append(Vector2(2000.0 - i * 20.0, 3000.0))
	var flat := AiParams.new()
	flat.line_iterations = 0
	var straight := RacingLine.new(ClosedPath.new(pts), 150.0, DrivingParams.new(), flat)
	var d := AiDriver.new(straight, _ellie)
	d.begin_race(5)
	# Slightly off heading: calm Ellie holds course inside her deadband, flustered Ellie steers.
	var off := {"position": Vector2(500, 0), "heading": deg_to_rad(_ellie.steer_deadband_degrees * 0.7),
		"speed": 200.0, "distance": 500.0, "lateral": 0.0}
	assert_eq(d.decide(off, [], DT).steer, 0.0)
	d.fluster_time = 1.0
	assert_eq(d.decide(off, [], DT).steer, -1.0, "over-corrects")
	var lifts := 0
	for i in 100:
		d.fluster_time = 1.0
		off.heading = 0.0
		if not d.decide(off, [], DT).fire:
			lifts += 1
	assert_between(lifts, 10, 70, "hesitates some of the time")


func test_victor_never_gets_flustered() -> void:
	var d := AiDriver.new(_line, _victor)
	var chaser := [{"distance": 940.0, "lateral": 0.0, "speed": 300.0}]
	for i in 600:
		d.decide(_me(1000.0, 300.0), chaser, DT)
	assert_eq(d.flusters, 0)
