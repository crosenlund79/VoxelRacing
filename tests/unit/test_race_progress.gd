extends GutTest
## RaceProgress: continuous distance for live positions, including the grid
## behind the line and crossing the start/finish line.

var _path: ClosedPath


func before_each() -> void:
	var pts := PackedVector2Array()
	for i in 40:
		pts.append(Vector2(i * 25.0, 0.0))
	for i in 40:
		pts.append(Vector2(1000.0 - i * 25.0, 200.0))
	_path = ClosedPath.new(pts)  # ~2400 px loop, line at (0,0) heading +X


func test_grid_position_behind_line_is_negative() -> void:
	var p := RaceProgress.new(_path)
	p.reset(Vector2(-10, 100))  # on the return leg, just before the line
	assert_lt(p.distance, 0.0)


func test_crossing_the_line_is_continuous() -> void:
	var p := RaceProgress.new(_path)
	p.reset(Vector2(5, 190))
	var before := p.distance
	p.update(Vector2(0, 150))
	p.update(Vector2(0, 50))
	p.update(Vector2(20, 0))
	assert_between(p.distance, before, before + 300.0, "no lap-length jump at the line")
	assert_gt(p.distance, 0.0)


func test_driving_forward_increases_and_backward_decreases() -> void:
	var p := RaceProgress.new(_path)
	p.reset(Vector2(100, 0))
	p.update(Vector2(200, 0))
	assert_almost_eq(p.distance, 200.0, 0.01)
	p.update(Vector2(150, 0))
	assert_almost_eq(p.distance, 150.0, 0.01)


func test_full_lap_adds_path_length() -> void:
	var p := RaceProgress.new(_path)
	p.reset(Vector2(100, 0))
	for i in 60:
		p.update(_path.point_at(100.0 + _path.length * (i + 1) / 60.0))
	assert_almost_eq(p.distance, 100.0 + _path.length, 0.5)
