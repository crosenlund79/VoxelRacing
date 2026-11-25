extends GutTest
## Pit lanes, pure rules: the limiter (50 % cap, smooth slow-down, normal speed
## after the lane), the double-tap override (free; held accelerator never
## counts), collision tickets (one per incident), service bays (one car per
## bay, three at once, a fourth waits, reservation and release), service
## (stationary in a bay, full duration, +30 capped at 100, interrupted, once
## per traversal, never after a DNF) and the branch geometry.

const DT := 1.0 / 60.0

var _rules: PitRules


func before_each() -> void:
	_rules = load("res://src/race/default_pit_rules.tres")


func _layout() -> TrackLayout:
	return load(DevLayouts.LAYOUTS["kestrel_ridge"])


func test_limiter_caps_at_half_with_controlled_slowdown() -> void:
	var params: DrivingParams = load("res://src/driving/default_driving_params.tres")
	var m := CarModel.new(params)
	m.velocity = Vector2(params.max_speed, 0)
	m.speed_cap = params.max_speed * _rules.limiter_share
	m.update(DT, 0.0, true)
	assert_gt(m.forward_speed(), params.max_speed * 0.9, "no instant drop: a smooth slow-down")
	for i in 120:
		m.update(DT, 0.0, true)
	assert_almost_eq(m.forward_speed(), params.max_speed * 0.5, 0.5, "held at 50 % of top speed")
	m.speed_cap = INF
	m.update(DT, 0.0, true)
	assert_almost_eq(m.forward_speed(), params.max_speed * 0.5 + params.acceleration * DT, 0.01,
		"after the lane: normal acceleration (no boost to top speed)")


func test_limiter_on_in_the_lane_off_outside() -> void:
	var p := PitWorld.new(_rules, 3)
	assert_false(p.limiter_on(0))
	p.step(0, true, -1, 200.0, 50.0, 100.0, false, DT)
	assert_true(p.limiter_on(0), "on entering the pit lane")
	p.step(0, false, -1, 200.0, 50.0, 100.0, false, DT)
	assert_false(p.limiter_on(0), "off when leaving it")


func test_override_is_free_and_lasts_one_traversal() -> void:
	var p := PitWorld.new(_rules, 2)
	assert_false(p.request_override(0), "outside the pit lane: nothing to override")
	p.step(0, true, -1, 200.0, 50.0, 100.0, false, DT)
	assert_true(p.request_override(0), "granted")
	assert_false(p.limiter_on(0), "limiter off for this traversal")
	assert_false(p.request_override(0), "a second request changes nothing")
	assert_eq(p.tickets[0], 0, "speeding is never ticketed")
	assert_eq(p.fines[0], 0, "and never fined")
	p.step(0, true, -1, 400.0, 50.0, 100.0, false, DT)
	assert_false(p.limiter_on(0), "stays off for the rest of the lane")
	p.step(0, false, -1, 400.0, 50.0, 100.0, false, DT)
	assert_false(p.limiter_on(0), "no penalty after the lane")
	p.step(0, true, -1, 200.0, 50.0, 100.0, false, DT)
	assert_true(p.limiter_on(0), "the next entry: the limiter engages again")


func test_one_ticket_per_collision_incident() -> void:
	var p := PitWorld.new(_rules, 2)
	assert_eq(p.collision(0), _rules.collision_fine, "a meaningful impact: one ticket")
	for i in 30:  # the same incident, still scraping along: nothing more
		assert_eq(p.collision(0), 0)
		p.step(0, true, -1, 100.0, 50.0, 100.0, false, DT)
	assert_eq(p.tickets[0], 1)
	for i in int(_rules.incident_gap / DT) + 2:  # clear of trouble for a while
		p.step(0, true, -1, 100.0, 50.0, 100.0, false, DT)
	assert_eq(p.collision(0), _rules.collision_fine, "a separate later impact: another ticket")
	assert_eq(p.tickets[0], 2)
	assert_eq(p.fines[0], 2 * _rules.collision_fine)
	assert_eq(p.tickets[1], 0, "per car")


func test_garage_human_pays_collision_fines_never_below_zero() -> void:
	var p := PitWorld.new(_rules, 2)
	p.pays_fines[0] = 1
	p.collision(0)
	var g := PlayerGarage.new(load("res://src/garage/default_garage_rules.tres"))
	g.money = 60
	g.begin_race()
	g.settle_race(8, 0, 0, -1.0, 3, p.fines[0])
	assert_eq(g.money, 0, "deducted from the balance, never below $0 (no debt)")
	assert_eq(g.last_fine, _rules.collision_fine)


## Service in bay 0 for one car, starting stationary in the bay.
func _serve(p: PitWorld, id: int, bay: int, cond: float) -> float:
	var got := 0.0
	for i in int(_rules.service_time / DT) + 5:
		got = maxf(got, p.step(id, true, bay, 0.0, cond, 100.0, false, DT))
	return got


func test_service_rules() -> void:
	var p := PitWorld.new(_rules, 2)
	p.step(0, true, -1, 100.0, 42.0, 100.0, false, DT)
	var got := 0.0
	var ticks := 0
	while got == 0.0 and ticks < 2000:
		got = p.step(0, true, 1, 0.0, 42.0, 100.0, false, DT)
		ticks += 1
	assert_almost_eq(ticks * DT, _rules.service_time, 2.0 * DT, "the full service time, stationary in the bay")
	assert_eq(got, 30.0, "+30 condition points")
	for i in 600:
		assert_eq(p.step(0, true, 1, 0.0, 72.0, 100.0, false, DT), 0.0, "once per traversal")
	# interrupted service: no repair
	var q := PitWorld.new(_rules, 1)
	for i in int(_rules.service_time / DT * 0.8):
		q.step(0, true, 0, 0.0, 50.0, 100.0, false, DT)
	q.step(0, true, 0, 60.0, 50.0, 100.0, false, DT)  # drove off early
	assert_eq(q.service[0], 0.0, "service interrupted")
	assert_eq(q.stops[0], 0)
	# capped at 100
	assert_eq(_serve(PitWorld.new(_rules, 1), 0, 0, 90.0), 10.0, "never above 100 %")
	# a DNF car is never repaired and holds no bay
	var x := PitWorld.new(_rules, 1)
	for i in int(_rules.service_time / DT) + 5:
		assert_eq(x.step(0, true, 0, 0.0, 0.0, 100.0, true, DT), 0.0)
	assert_eq(x.bay_owner[0], -1)
	# service disabled (Knockout)
	var k := PitWorld.new(_rules, 1)
	k.service_enabled = false
	assert_eq(_serve(k, 0, 0, 40.0), 0.0)
	# not in a bay (the through-lane): no service
	var t := PitWorld.new(_rules, 1)
	assert_eq(_serve(t, 0, -1, 40.0), 0.0, "only in a service bay")


func test_two_legitimate_stops_need_two_traversals() -> void:
	var p := PitWorld.new(_rules, 1)
	var cond := 20.0
	for lap in 2:
		p.step(0, true, -1, 100.0, cond, 100.0, false, DT)
		for i in int(_rules.service_time / DT) + 5:
			cond += p.step(0, true, 2, 0.0, cond, 100.0, false, DT)
		# nudge out of the bay and back in: no second service
		p.step(0, true, -1, 20.0, cond, 100.0, false, DT)
		for i in int(_rules.service_time / DT) + 5:
			cond += p.step(0, true, 2, 0.0, cond, 100.0, false, DT)
		p.step(0, false, -1, 200.0, cond, 100.0, false, DT)  # out of the lane, a lap later back
	assert_eq(cond, 80.0, "two stops, +30 each")
	assert_eq(p.stops[0], 2)


func test_three_bays_serve_three_cars_at_once_and_a_fourth_waits() -> void:
	var p := PitWorld.new(_rules, 4)
	for id in 3:
		p.step(id, true, -1, 100.0, 40.0, 100.0, false, DT)
	p.step(3, true, -1, 100.0, 40.0, 100.0, false, DT)
	var done := [0.0, 0.0, 0.0]
	for i in int(_rules.service_time / DT) + 3:
		for id in 3:
			done[id] = maxf(done[id], p.step(id, true, id, 0.0, 40.0, 100.0, false, DT))
		# the fourth car stops in bay 1, already held: no service there
		assert_eq(p.step(3, true, 1, 0.0, 40.0, 100.0, false, DT), 0.0, "an occupied bay never serves a second car")
	assert_eq(done, [30.0, 30.0, 30.0], "three bays, three cars serviced at the same time")
	assert_eq(p.bay_owner, PackedInt32Array([0, 1, 2]))
	assert_eq(p.free_bays(3), 0, "full")
	assert_eq(p.reserve_bay(3), -1, "nothing to reserve while full")
	# the occupant of bay 1 drives out: the bay is free, and the fourth car gets it
	p.step(1, true, -1, 80.0, 70.0, 100.0, false, DT)
	assert_eq(p.bay_owner[1], -1, "released once it has physically left")
	var got := 0.0
	for i in int(_rules.service_time / DT) + 3:
		got = maxf(got, p.step(3, true, 1, 0.0, 40.0, 100.0, false, DT))
	assert_eq(got, 30.0)
	assert_eq(p.bay_owner[1], 3)


func test_a_parked_car_occupies_its_bay_even_without_wanting_service() -> void:
	var p := PitWorld.new(_rules, 3)
	p.step(0, true, -1, 100.0, 100.0, 100.0, false, DT)
	p.step(0, true, 1, 0.0, 100.0, 100.0, false, DT)  # full condition: parked, no service wanted
	assert_eq(p.bay_owner[1], 0, "physically occupied: not free")
	assert_eq(p.free_bays(2), 2, "two bays left for others")
	assert_eq(PitWorld.packed_bay(p.pack(0)), 1, "shown as occupied (red frame) everywhere")
	p.step(2, true, -1, 100.0, 30.0, 100.0, false, DT)
	for i in int(_rules.service_time / DT) + 5:
		assert_eq(p.step(2, true, 1, 0.0, 30.0, 100.0, false, DT), 0.0, "nobody else is serviced in it")
	assert_eq(p.reserve_bay(2), 0, "a rival reserves a free bay instead")
	p.step(0, true, -1, 60.0, 100.0, 100.0, false, DT)  # it drives off
	assert_eq(p.bay_owner[1], -1, "free once it has physically left")


func test_bay_reservation_is_one_car_per_bay() -> void:
	var p := PitWorld.new(_rules, 3)
	assert_eq(p.reserve_bay(0), 0)
	assert_eq(p.reserve_bay(1), 1, "a reserved bay is not offered to another rival")
	assert_eq(p.reserve_bay(0), 0, "kept while available")
	var usable: Array[bool] = [false, false, true]
	assert_eq(p.reserve_bay(2, usable), 2, "only bays it can still turn into")
	assert_eq(p.reserve_bay(1, [] as Array[bool]), 1)
	# someone (a human) stops in bay 0 first: it is theirs; the rival chooses again
	p.step(2, true, -1, 100.0, 40.0, 100.0, false, DT)
	p.release_reservation(2)
	p.step(2, true, 0, 0.0, 40.0, 100.0, false, DT)
	assert_eq(p.bay_owner[0], 2)
	assert_eq(p.reserve_bay(0), 2, "the rival moves on to a bay it may use")
	# leaving the lane releases reservations
	p.step(1, true, -1, 100.0, 40.0, 100.0, false, DT)
	p.step(1, false, -1, 100.0, 40.0, 100.0, false, DT)
	assert_eq(p.bay_reserved.find(1), -1)


func test_packed_state_carries_the_bay() -> void:
	var p := PitWorld.new(_rules, 2)
	p.step(1, true, -1, 100.0, 40.0, 100.0, false, DT)
	p.step(1, true, 2, 0.0, 40.0, 100.0, false, DT)
	assert_eq(PitWorld.packed_bay(p.pack(1)), 2)
	assert_eq(PitWorld.packed_bay(p.pack(0)), -1)
	assert_eq(p.pack(1) & 1, 1, "limiter on")


func test_double_tap_detection() -> void:
	var d := PitTapDetector.new()
	var fired := false
	# held accelerator through the entry: never an override, however long
	for i in 120:
		fired = fired or d.step(true, i > 10, DT, _rules.double_tap_window)
	assert_false(fired, "holding the accelerator never overrides")
	# release, then two quick presses
	fired = d.step(false, true, DT, _rules.double_tap_window)
	var taps := [true, true, false, false, true]  # press (held 2 ticks), release, press
	for t in taps:
		fired = fired or d.step(t, true, DT, _rules.double_tap_window)
	assert_true(fired, "two separate presses within the window")
	# two slow presses do not count
	var e := PitTapDetector.new()
	var f := false
	e.step(false, true, DT, _rules.double_tap_window)
	f = e.step(true, true, DT, _rules.double_tap_window)
	for i in 40:
		f = f or e.step(false, true, DT, _rules.double_tap_window)
	f = f or e.step(true, true, DT, _rules.double_tap_window)
	assert_false(f, "too slow: not a double tap")
	# outside the pit lane nothing counts
	var o := PitTapDetector.new()
	var g := false
	for t in [false, true, false, true, false, true]:
		g = g or o.step(t, false, DT, _rules.double_tap_window)
	assert_false(g)


func test_limiter_never_applies_on_the_racing_road() -> void:
	for id in DevLayouts.PLAYER_LAYOUTS:
		var l: TrackLayout = DevLayouts.load_layout(id)
		var path := ClosedPath.new(l.sample_centerline())
		var s := 0.0
		while s < path.length:
			var main := l.route_bounds(s, path.length, 0)
			for lat in [main.x + 2.0, 0.0, main.y - 2.0]:
				assert_false(l.in_pit_lane(s, path.length, lat), "%s at %.0f / %.0f" % [id, s, lat])
			s += 20.0


func test_three_bays_beside_a_through_lane() -> void:
	for id in DevLayouts.PLAYER_LAYOUTS:
		var l: TrackLayout = DevLayouts.load_layout(id)
		var path := ClosedPath.new(l.sample_centerline())
		var b: Dictionary = l.branches[l.pit_branch()]
		assert_eq(TrackLayout.bay_count(b), 3, id)
		var strip := l.bay_strip(b, path.length)
		var through := l.route_bounds(float(b.box), path.length, 1)
		assert_almost_eq(through.y, strip.x, 0.01, "%s: the bays begin where the through-lane ends" % id)
		assert_gt(through.y - through.x, 60.0, "%s: the through-lane fits a car" % id)
		for k in 3:
			var c := TrackLayout.bay_centre(b, k)
			var mid := (strip.x + strip.y) * 0.5
			assert_eq(l.bay_at(c, path.length, mid), k, "%s: PIT %d" % [id, k + 1])
			assert_eq(l.bay_at(c, path.length, (through.x + through.y) * 0.5), -1, "%s: the through-lane is no bay" % id)
			assert_false(l.road_blocked(c, path.length, mid), "%s: the bay is open road" % id)
			assert_true(l.road_blocked(c, path.length, strip.y + 4.0), "%s: walled behind the bay" % id)


func test_divider_stops_missiles_and_lanes_are_drivable() -> void:
	var l := _layout()
	var path := ClosedPath.new(l.sample_centerline())
	for k in l.branches.size():
		var b: Dictionary = l.branches[k]
		var mid: float = (float(b.from) + float(b.to)) * 0.5
		var d := l.divider_at(mid, path.length)
		assert_ne(d, Vector2.INF, "branch %d has a divider mid-way" % k)
		assert_true(l.road_blocked(mid, path.length, (d.x + d.y) * 0.5), "the divider is solid")
		for lane in 2:
			var bd := l.route_bounds(mid, path.length, lane)
			assert_false(l.road_blocked(mid, path.length, (bd.x + bd.y) * 0.5), "lane %d is open road" % lane)
			assert_gt(bd.y - bd.x, 60.0, "lane %d fits a car" % lane)
