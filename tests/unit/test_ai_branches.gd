extends GutTest
## Rivals at track branches: a rival beside a divider always follows the lane
## it is really in (a dropped pit plan, a shove or a respawn in the pit lane must
## never steer it into the divider - 2026-11-17 simulations found rivals pinned
## against the pit divider at walking pace).

var _layout: TrackLayout
var _path: ClosedPath
var _line: RacingLine


func before_all() -> void:
	_layout = DevLayouts.load_layout("kestrel_ridge")
	_path = ClosedPath.new(_layout.sample_centerline())
	var driving: DrivingParams = load("res://src/driving/default_driving_params.tres")
	_line = RacingLine.new(_path, _layout.road_width, driving, AiParams.new(), PackedFloat32Array(), _layout,
		driving.max_speed * 0.5)


func _me(s: float, lane: int) -> Dictionary:
	var bd := _layout.route_bounds(s, _path.length, lane)
	var lat := (bd.x + bd.y) * 0.5
	var tan := _path.tangent_at(s)
	return {"position": _path.point_at(s) + Vector2(-tan.y, tan.x) * lat, "heading": tan.angle(), "speed": 100.0,
		"distance": s, "lateral": lat, "pit": {"open": true, "condition": 1.0, "laps_left": 5, "position": 5,
		"in_lane": lane == 1, "in_box": false, "served": false}}


func test_a_rival_in_the_pit_lane_without_a_plan_stays_in_the_pit_lane() -> void:
	var b: Dictionary = _layout.branches[_layout.pit_branch()]
	var d := AiDriver.new(_line, AiParams.new())
	var s := float(b.box) + 20.0
	d.decide(_me(s, 1), [], 1.0 / 60.0)
	assert_false(d.pitting, "no stop planned (healthy car)")
	assert_eq(d.route_at(s), RacingLine.ROUTE_PIT, "beside the divider: the pit lane it is in")
	var room := _line.bounds_at(s, d.route_at(s))
	assert_gt(room.x, (_layout.divider_at(s, _path.length).x + _layout.divider_at(s, _path.length).y) * 0.5,
		"its room is the pit lane, beyond the divider")
	# the exit ramp: still the pit route until the branch ends
	d.decide(_me(float(b.to) - 60.0, 1), [], 1.0 / 60.0)
	assert_eq(d.route_at(float(b.to) - 60.0), RacingLine.ROUTE_PIT)
	# next lap on the racing road: the plan decides again
	var after := _path.length + float(b.box) + 20.0
	d.decide(_me(fposmod(float(b.to) + 400.0, _path.length), 0), [], 1.0 / 60.0)
	d.decide(_me(float(b.box) + 20.0, 0), [], 1.0 / 60.0)
	assert_eq(d.route_at(after), RacingLine.ROUTE_MAIN, "on the racing road beside the divider: the main route")


func test_a_rival_in_the_other_split_lane_follows_that_lane() -> void:
	for k in _layout.branches.size():
		var b: Dictionary = _layout.branches[k]
		if b.kind != "split":
			continue
		var s := (float(b.from) + float(b.to)) * 0.5
		var d := AiDriver.new(_line, AiParams.new())
		d.route_choice[k] = RacingLine.ROUTE_MAIN
		d.decide(_me(s, 1), [], 1.0 / 60.0)
		assert_eq(d.route_at(s), RacingLine.ROUTE_ALT, "the right lane it is in, whatever it planned")
		d.decide(_me(s, 0), [], 1.0 / 60.0)
		assert_eq(d.route_at(s), RacingLine.ROUTE_MAIN)
