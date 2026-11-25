extends GutTest
## RacingLine: stays inside the road, cuts corners, and its speed profile is
## derived from the shared driving parameters and is brake-feasible.

const CIRCUIT := "res://src/track/circuit_01.tres"

var _layout: TrackLayout
var _driving: DrivingParams
var _ai: AiParams
var _line: RacingLine


func before_all() -> void:
	_layout = load(CIRCUIT)
	_driving = load("res://src/driving/default_driving_params.tres")
	_ai = AiParams.new()
	_line = RacingLine.new(ClosedPath.new(_layout.sample_centerline()), _layout.road_width, _driving, _ai)


func test_line_stays_inside_road_margin() -> void:
	var limit := _layout.road_width * 0.5 - _ai.line_margin
	for o in _line.offsets:
		assert_lte(absf(o), limit + 0.001)


func test_line_uses_the_road_width_to_cut_corners() -> void:
	var widest := 0.0
	for o in _line.offsets:
		widest = maxf(widest, absf(o))
	assert_gt(widest, (_layout.road_width * 0.5 - _ai.line_margin) * 0.9)


func test_speeds_never_exceed_car_top_speed() -> void:
	for v in _line.speeds:
		assert_lte(v, _driving.max_speed + 0.001)
		assert_gt(v, 0.0)


func test_tight_corners_are_slower_than_straights() -> void:
	var slowest := INF
	var fastest := 0.0
	for v in _line.speeds:
		slowest = minf(slowest, v)
		fastest = maxf(fastest, v)
	assert_almost_eq(fastest, _driving.max_speed, 0.001, "full speed on straights")
	assert_lt(slowest, _driving.max_speed * 0.8, "slows for the tight bends")


func test_speed_profile_is_brake_feasible() -> void:
	var decel := _driving.release_deceleration * _ai.brake_planning_factor
	var n := _line.speeds.size()
	for i in n:
		var j := (i + 1) % n
		var ds := _line.position(i).distance_to(_line.position(j))
		assert_lte(_line.speeds[i] * _line.speeds[i], _line.speeds[j] * _line.speeds[j] + 2.0 * decel * ds + 0.5)
