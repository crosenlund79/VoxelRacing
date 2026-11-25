extends GutTest
## TrackLayout geometry: closed centreline, edges, checkpoints; circuit_01 sanity.

const CIRCUIT := "res://src/track/circuit_01.tres"


func _square() -> TrackLayout:
	var l := TrackLayout.new()
	l.control_points = PackedVector2Array([Vector2(1000, 0), Vector2(1000, 1000), Vector2(0, 1000), Vector2(0, 0)])
	l.corner_radii = PackedFloat32Array([200, 200, 200, 200])
	l.road_width = 150.0
	l.sample_spacing = 20.0
	l.checkpoint_count = 4
	return l


func test_start_line_is_middle_of_straight_into_first_corner() -> void:
	var c := _square().sample_centerline()
	assert_almost_eq(c[0], Vector2(500, 0), Vector2(0.001, 0.001))


func test_straights_are_straight_between_corners() -> void:
	var c := _square().sample_centerline()
	# Straight from the start line (500,0) to the first corner entry (800,0).
	for i in 15:
		assert_almost_eq(c[i].y, 0.0, 0.001)
		assert_between(c[i].x, 500.0 - 0.001, 800.0 + 0.001)


func test_corner_has_declared_radius() -> void:
	var c := _square().sample_centerline()
	var centre := Vector2(800, 200)  # corner at (1000,0) with radius 200
	var on_arc := 0
	for p in c:
		if p.x > 800.0 + 0.001 and p.y < 200.0 - 0.001:
			assert_almost_eq(p.distance_to(centre), 200.0, 0.01)
			on_arc += 1
	assert_gt(on_arc, 5)


func test_samples_are_no_further_apart_than_spacing() -> void:
	var c := _square().sample_centerline()
	for i in c.size():
		assert_lte(c[i].distance_to(c[(i + 1) % c.size()]), 20.0 + 0.001)


func test_validate_accepts_square_and_rejects_bad_layouts() -> void:
	assert_eq(_square().validate().size(), 0)
	var tight := _square()
	tight.corner_radii[1] = 60.0
	assert_gt(tight.validate().size(), 0, "radius below half road width")
	var crowded := _square()
	crowded.corner_radii = PackedFloat32Array([600, 600, 200, 200])
	assert_gt(crowded.validate().size(), 0, "corners overlap on a 1000 px side")


func test_circuit_is_valid_and_mixes_straights_with_tight_and_sweeping_corners() -> void:
	var l: TrackLayout = load(CIRCUIT)
	assert_eq(l.validate().size(), 0, str(l.validate()))
	var radii := Array(l.corner_radii)
	assert_lte(radii.min(), 150.0, "has tight bends")
	assert_gte(radii.max(), 350.0, "has long sweeping corners")


func test_offset_line_is_perpendicular_at_given_distance() -> void:
	var c := PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(200, 0)])
	var right := TrackLayout.offset_line(c, 50.0)
	assert_almost_eq(right[1], Vector2(100, 50), Vector2(0.001, 0.001), "+distance is right of travel (screen +Y)")


func test_checkpoints_evenly_spaced_starting_at_zero() -> void:
	var l := _square()
	assert_eq(l.checkpoint_sample_indices(40), PackedInt32Array([0, 10, 20, 30]))


func test_circuit_edges_do_not_self_intersect() -> void:
	var l: TrackLayout = load(CIRCUIT)
	var c := l.sample_centerline()
	for edge in [TrackLayout.offset_line(c, -l.road_width * 0.5), TrackLayout.offset_line(c, l.road_width * 0.5)]:
		var n: int = edge.size()
		var crossings := 0
		for i in n:
			for j in range(i + 2, n):
				if i == 0 and j == n - 1:
					continue
				if Geometry2D.segment_intersects_segment(edge[i], edge[(i + 1) % n], edge[j], edge[(j + 1) % n]) != null:
					crossings += 1
		assert_eq(crossings, 0)


func test_circuit_has_valid_race_settings() -> void:
	var l: TrackLayout = load(CIRCUIT)
	assert_gte(l.checkpoint_count, 2)
	assert_gte(l.lap_count, 1)
	assert_gt(l.road_width, 0.0)
