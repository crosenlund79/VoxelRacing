extends GutTest
## J3: the pure jump model (JumpRules, JumpWorld) and jump track data.

const FIGURE8 := "res://src/track/layouts/exp_figure8_01.tres"
const DT := 1.0 / 60.0

var _layout: TrackLayout
var _path: ClosedPath
var _rules: JumpRules


func before_each() -> void:
	_layout = load(FIGURE8)
	_path = ClosedPath.new(_layout.sample_centerline())
	_rules = load("res://src/race/default_jump_rules.tres")


## Drives one car straight along the road at a constant speed from `start`
## (arc distance) for up to `seconds`; returns the events with their distance.
func _fly(world: JumpWorld, start: float, speed: float, seconds := 3.0) -> Array:
	var out := []
	var s := start
	world.place(0, s)
	for i in int(seconds / DT):
		var down := world.is_down(0)
		if not down:
			s += speed * DT
		var ev := world.step(0, DT, s, speed, true)
		if ev != "":
			out.append([ev, s])
		if ev == "landed" or ev == "recovered":
			break
	return out


func test_flight_distance_grows_with_the_square_of_speed() -> void:
	assert_almost_eq(_rules.flight_distance(420.0), 196.0, 0.5)
	assert_almost_eq(_rules.flight_distance(210.0), 49.0, 0.5)
	assert_eq(_rules.flight_distance(-50.0), 0.0)
	var gap := _layout.jumps[0].z
	assert_almost_eq(_rules.flight_distance(_rules.clearing_speed(gap)), gap, 0.01)


func test_faster_cars_fly_further_and_clear_the_gap() -> void:
	var lip := _layout.jumps[0].x
	var gap := _layout.jumps[0].z
	var distances := []
	for speed in [360.0, 390.0, 420.0]:
		var w := JumpWorld.new(_layout, _rules, _path, 1)
		var ev := _fly(w, lip - 40.0, speed)
		assert_eq(ev[0][0], "takeoff", "took off at %d" % speed)
		assert_eq(ev[1][0], "landed", "cleared the gap at %d" % speed)
		var flown: float = ev[1][1] - ev[0][1]
		assert_almost_eq(flown, _rules.flight_distance(speed), speed * DT * 2.0, "flew as far as the model says")
		assert_gt(ev[1][1], lip + gap, "landed past the gap")
		distances.append(flown)
	assert_lt(distances[0], distances[1])
	assert_lt(distances[1], distances[2])


func test_too_slow_falls_into_the_gap_and_recovers_past_it() -> void:
	var lip := _layout.jumps[0].x
	var w := JumpWorld.new(_layout, _rules, _path, 1)
	var ev := _fly(w, lip - 40.0, 250.0, 5.0)
	assert_eq(ev.map(func(e: Array) -> String: return e[0]), ["takeoff", "fell", "recovered"])
	assert_lt(ev[1][1], lip + _layout.jumps[0].z, "came down inside the gap")
	assert_false(w.is_down(0))
	assert_almost_eq(w.recovery_distance(0), lip + _layout.jumps[0].z + _rules.recovery_offset, 0.001)


func test_fall_lasts_the_recovery_time() -> void:
	var w := JumpWorld.new(_layout, _rules, _path, 1)
	var lip := _layout.jumps[0].x
	w.place(0, lip + 10.0)
	assert_eq(w.step(0, DT, lip + 12.0, 5.0, true), "fell", "rolling into the gap on the ground falls")
	var ticks := 0
	while w.is_down(0):
		ticks += 1
		w.step(0, DT, lip + 12.0, 0.0, false)
	assert_almost_eq(ticks * DT, _rules.recovery_time, DT * 1.5)


func test_no_takeoff_backwards_wrecked_or_on_other_roads() -> void:
	var lip := _layout.jumps[0].x
	var w := JumpWorld.new(_layout, _rules, _path, 1)
	w.place(0, lip + 300.0)
	assert_eq(w.step(0, DT, lip + 290.0, -300.0, true), "", "driving backwards past the landing")
	w.place(0, lip - 5.0)
	assert_eq(w.step(0, DT, lip + 1.0, 300.0, false), "", "a wrecked car does not take off")
	w.place(0, 1000.0)
	assert_eq(w.step(0, DT, 1010.0, 400.0, true), "", "nothing elsewhere")
	assert_false(w.is_airborne(0))


func test_height_is_a_parabola_and_zero_on_the_ground() -> void:
	var w := JumpWorld.new(_layout, _rules, _path, 1)
	assert_eq(w.height(0), 0.0)
	var lip := _layout.jumps[0].x
	w.place(0, lip - 1.0)
	w.step(0, DT, lip + 1.0, 420.0, true)
	var peak := 0.0
	while w.is_airborne(0):
		peak = maxf(peak, w.height(0))
		w.step(0, DT, lip + 2.0, 420.0, true)
	var vz := _rules.ramp_slope * 420.0
	assert_almost_eq(peak, vz * vz / (2.0 * _rules.gravity), 0.5)
	assert_eq(w.height(0), 0.0)


func test_reset_clears_every_car() -> void:
	var w := JumpWorld.new(_layout, _rules, _path, 2)
	var lip := _layout.jumps[0].x
	w.place(1, lip - 1.0)
	w.step(1, DT, lip + 1.0, 400.0, true)
	assert_true(w.is_airborne(1))
	w.reset()
	assert_false(w.is_airborne(1))
	assert_eq(w.jump_of[1], -1)


func test_layout_jump_data_is_valid_and_flat_layouts_have_none() -> void:
	assert_true(_layout.has_jumps())
	assert_eq(_layout.validate(), PackedStringArray())
	var flat: TrackLayout = load("res://src/track/circuit_01.tres")
	assert_false(flat.has_jumps())
	assert_eq(flat.validate(), PackedStringArray())


func test_validation_rejects_a_jump_at_the_crossing_or_on_a_corner() -> void:
	var bad: TrackLayout = _layout.duplicate()
	var x := TrackLayout.find_crossings(bad.sample_centerline())[0]
	bad.jumps = PackedVector3Array([Vector3(x.s_b, 90, 130)])
	assert_gt(bad.validate_jumps().size(), 0, "on the crossing")
	bad.jumps = PackedVector3Array([Vector3(4400, 90, 130)])
	assert_gt(bad.validate_jumps().size(), 0, "too close to a corner")
	bad.jumps = PackedVector3Array([Vector3(6050, 0, 130)])
	assert_gt(bad.validate_jumps().size(), 0, "no ramp")


func test_gates_stay_clear_of_the_jump() -> void:
	var c := _layout.sample_centerline()
	var j := _layout.jumps[0]
	for g in _layout.checkpoint_sample_indices(c.size(), c):
		var s: float = _path.cumulative[g]
		assert_false(s > j.x - j.y - TrackLayout.JUMP_RUNWAY and s < j.x + j.z + TrackLayout.JUMP_RUNWAY, "gate at %.0f" % s)


func _combat() -> CombatWorld:
	var w := CombatWorld.new(WeaponRules.new(), 3, _path, _layout.road_width * 0.5)
	w.enabled = true
	w.layout = _layout
	return w


## A car state x px along the road from the jump lip (on the ground level).
func _car(x: float, air: bool) -> Dictionary:
	var s := _layout.jumps[0].x + x
	return {"position": _path.point_at(s), "heading": _path.tangent_at(s).angle(), "present": true,
		"level": 0, "band": false, "index": _path.index_at(s), "air": air}


func test_ground_mine_and_missile_miss_a_flying_car_but_hit_ground_cars() -> void:
	var w := _combat()
	var cars := [_car(0, false), _car(-34, true), _car(-30, false)]
	assert_true(w.request(0, CombatWorld.REAR, cars))
	for i in int((w.rules.mine_fuse + 0.1) / DT):
		w.step(DT, cars)
	assert_false(w.is_wrecked(1), "flying over the blast")
	assert_true(w.is_wrecked(2), "the car on the ground is caught")
	var m := _combat()
	var cars2 := [_car(0, false), _car(150, true)]
	assert_true(m.request(0, CombatWorld.FRONT, cars2))
	for i in 30:
		m.step(DT, cars2)
	assert_false(m.is_wrecked(1), "a ground missile passes under a flying car")


func test_flying_cars_meet_each_other_and_their_own_super_missile() -> void:
	var w := _combat()
	w.set_loadout(0, WeaponRules.Weapon.SUPER_MISSILE, 1, WeaponRules.Weapon.MINE, 0)
	var cars := [_car(0, true), _car(0, true), _car(0, false)]
	var side := _path.tangent_at(_layout.jumps[0].x).orthogonal()
	cars[1].position = cars[0].position + side * w.rules.super_orbit_radius
	cars[2].position = cars[0].position - side * w.rules.super_orbit_radius
	assert_true(w.request(0, CombatWorld.FRONT, cars))
	for i in 60:
		w.step(DT, cars)
	assert_true(w.is_wrecked(1), "a super missile fired in the air reaches another flying car")
	assert_false(w.is_wrecked(2), "not the car on the ground below")
	assert_true(CombatWorld.levels_meet(0, false, 0, false), "same-level rule unchanged")
