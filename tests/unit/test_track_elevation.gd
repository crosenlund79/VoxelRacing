extends GutTest
## J0: optional elevation zones on TrackLayout, crossing detection, validation,
## checkpoint placement, and the developer-only experimental figure-8.

const CIRCUIT := "res://src/track/circuit_01.tres"
const FIGURE8 := "res://src/track/layouts/exp_figure8_01.tres"


func _fig8(zones := PackedVector2Array([Vector2(1440, 2240)])) -> TrackLayout:
	var l: TrackLayout = (load(FIGURE8) as TrackLayout).duplicate()
	l.elevation_zones = zones
	return l


func test_existing_circuit_is_flat_and_unchanged() -> void:
	var l: TrackLayout = load(CIRCUIT)
	assert_false(l.has_elevation())
	var c := l.sample_centerline()
	assert_eq(TrackLayout.find_crossings(c).size(), 0)
	assert_eq(l.validate().size(), 0)
	assert_eq(l.checkpoint_sample_indices(c.size(), c), l.checkpoint_sample_indices(c.size()), "same gates as before")
	for s in [0.0, 1000.0, 4000.0, 7000.0]:
		assert_eq(l.level_at(s, 7374.0), 0)


func test_figure8_has_one_crossing_with_one_elevated_branch() -> void:
	var l: TrackLayout = load(FIGURE8)
	assert_eq(l.validate().size(), 0, str(l.validate()))
	var c := l.sample_centerline()
	var path := ClosedPath.new(c)
	var xs := TrackLayout.find_crossings(c)
	assert_eq(xs.size(), 1)
	var x: Dictionary = xs[0]
	assert_almost_eq(x.point, Vector2(1200, 750), Vector2(2, 2))
	assert_eq(l.level_at(x.s_a, path.length), 1, "first branch on the bridge")
	assert_eq(l.level_at(x.s_b, path.length), 0, "second branch underneath")
	var reach := l.crossing_reach(x.angle)
	assert_eq(l.level_at(x.s_a - reach, path.length), 1)
	assert_eq(l.level_at(x.s_a + reach, path.length), 1)
	assert_eq(l.level_at(0.0, path.length), 0, "start line on the ground")
	assert_eq(l.level_at(path.length - l.grid_extent(), path.length), 0, "grid on the ground")


func test_figure8_gates_avoid_bridge_crossing_and_zone_ends() -> void:
	var l: TrackLayout = load(FIGURE8)
	var c := l.sample_centerline()
	var path := ClosedPath.new(c)
	var x: Dictionary = TrackLayout.find_crossings(c)[0]
	var gates := l.checkpoint_sample_indices(c.size(), c)
	assert_eq(gates.size(), l.checkpoint_count)
	assert_eq(gates[0], 0, "start/finish line stays")
	for g in gates.size():
		var s := path.cumulative[gates[g]]
		if g > 0:
			assert_gt(gates[g], gates[g - 1], "gates stay in driving order")
		assert_eq(l.level_at(s, path.length), 0, "gate %d not on the bridge" % g)
		assert_gt(c[gates[g]].distance_to(x.point), l.road_width + TrackLayout.CROSSING_CLEARANCE - 0.01, "gate %d clear of the crossing" % g)
		for z in l.elevation_zones:
			assert_gt(absf(s - z.x), TrackLayout.GATE_ZONE_MARGIN - 0.01)
			assert_gt(absf(s - z.y), TrackLayout.GATE_ZONE_MARGIN - 0.01)


func test_validation_rejects_unsafe_elevation() -> void:
	assert_gt(_fig8(PackedVector2Array()).validate().size(), 0, "a crossing needs an elevated branch")
	assert_gt(_fig8(PackedVector2Array([Vector2(1700, 1980)])).validate().size(), 0, "zone too short for the crossing")
	assert_gt(_fig8(PackedVector2Array([Vector2(1650, 2240)])).validate().size(), 0, "zone end too close to the other road")
	assert_gt(_fig8(PackedVector2Array([Vector2(1440, 2240), Vector2(5300, 5700)])).validate().size(), 0, "both branches elevated")
	assert_gt(_fig8(PackedVector2Array([Vector2(1440, 2240), Vector2(2000, 2600)])).validate().size(), 0, "overlapping zones")
	assert_gt(_fig8(PackedVector2Array([Vector2(1440, 2240), Vector2(7100, 7300)])).validate().size(), 0, "zone in the grid")
	assert_gt(_fig8(PackedVector2Array([Vector2(1440, 9000)])).validate().size(), 0, "zone beyond the lap")
	var flat: TrackLayout = (load(CIRCUIT) as TrackLayout).duplicate()
	flat.elevation_zones = PackedVector2Array([Vector2(1000, 1400)])
	assert_gt(flat.validate().size(), 0, "zones without a crossing")


func test_dev_layout_selection_is_command_line_only() -> void:
	assert_eq(DevLayouts.selected_id(PackedStringArray()), "")
	assert_null(DevLayouts.load_selected(PackedStringArray()))
	assert_eq(DevLayouts.selected_id(PackedStringArray(["--layout=exp_figure8_01"])), "exp_figure8_01")
	assert_true(DevLayouts.load_selected(PackedStringArray(["x=1", "--layout=exp_figure8_01"])) is TrackLayout)
	assert_eq(DevLayouts.selected_id(PackedStringArray(["--layout=nope"])), "", "unknown ids ignored")
	assert_eq(NetRace.build_id(), NetRace.GAME_BUILD, "no layout selected in tests: normal build string")
