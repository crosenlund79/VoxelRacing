extends GutTest
## ClosedPath: arc length, lookup and projection on a closed polyline.

var _square: ClosedPath


func before_each() -> void:
	_square = ClosedPath.new(PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)]))


func test_length_and_cumulative_distances() -> void:
	assert_almost_eq(_square.length, 400.0, 0.001)
	assert_almost_eq(_square.cumulative[2], 200.0, 0.001)


func test_point_and_tangent_at_distance_wrap_around() -> void:
	assert_almost_eq(_square.point_at(150.0), Vector2(100, 50), Vector2(0.001, 0.001))
	assert_almost_eq(_square.point_at(450.0), Vector2(50, 0), Vector2(0.001, 0.001), "wraps past the end")
	assert_almost_eq(_square.point_at(-50.0), Vector2(0, 50), Vector2(0.001, 0.001), "negative wraps backwards")
	assert_eq(_square.tangent_at(150.0), Vector2.DOWN)


func test_project_gives_distance_and_signed_lateral() -> void:
	var p := _square.project(Vector2(40, 10))
	assert_eq(p.index, 0)
	assert_almost_eq(p.distance, 40.0, 0.001)
	assert_almost_eq(p.lateral, 10.0, 0.001, "inside the clockwise loop is right of travel")
	var outside := _square.project(Vector2(40, -10))
	assert_almost_eq(outside.lateral, -10.0, 0.001)


func test_project_with_hint_searches_locally() -> void:
	var long := PackedVector2Array()
	for i in 100:
		long.append(Vector2(i * 10.0, 0.0))
	for i in 100:
		long.append(Vector2(990.0 - i * 10.0, 50.0))
	var loop := ClosedPath.new(long)
	var p := loop.project(Vector2(500, 5), 50, 5)
	assert_almost_eq(p.distance, 500.0, 0.001)
	assert_almost_eq(p.lateral, 5.0, 0.001)
