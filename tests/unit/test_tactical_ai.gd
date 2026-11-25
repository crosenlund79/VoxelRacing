extends GutTest
## M3.5 Stage 3: Tactical weapon decisions — weapon-aware shot quality from real
## positions, directions and speeds, and the nine personalities' tactical traits.
## Same rules for everyone: these only decide whether a driver asks to fire.

const DT := 1.0 / 60.0
const W := WeaponRules.Weapon

var _line: RacingLine


func before_all() -> void:
	var pts := PackedVector2Array()
	for i in 200:
		pts.append(Vector2(i * 20.0, 0.0))
	for i in 200:
		pts.append(Vector2(4000.0 - i * 20.0, 3000.0))
	var flat := AiParams.new()
	flat.line_iterations = 0
	_line = RacingLine.new(ClosedPath.new(pts), 150.0, DrivingParams.new(), flat)


func _driver(id: int, seed_value := 1) -> AiDriver:
	var params: AiParams = load(RivalRoster.params_path(id)) if id > 0 else AiParams.new()
	var d := AiDriver.new(_line, params)
	d.begin_race(seed_value)
	return d


func _me(x: float, speed := 300.0) -> Dictionary:
	return {"position": Vector2(x, 0), "heading": 0.0, "speed": speed, "distance": x, "lateral": 0.0}


func _target(x: float, y := 0.0, speed := 300.0) -> Dictionary:
	return {"position": Vector2(x, y), "velocity": Vector2(speed, 0), "distance": x, "lateral": y, "speed": speed, "wrecked": false}


func _ctx(front: int, rear: int, laps_left := 3, pressure := false) -> Dictionary:
	return {"front_ready": true, "rear_ready": true, "front_ammo": 8, "front_start": 8, "rear_ammo": 8, "rear_start": 8,
		"laps_left": laps_left, "lap_count": 3, "missile_speed": 820.0, "hit_radius": 24.0, "mine_fuse": 3.0,
		"pressure": pressure, "front_weapon": front, "rear_weapon": rear, "homing_range": 900.0, "super_orbit_radius": 56.0}


## Requests per slot over `seconds` with a fixed situation (slots never cool down here).
func _count(d: AiDriver, me: Dictionary, targets: Array, ctx: Dictionary, seconds := 5.0) -> Array[int]:
	var n: Array[int] = [0, 0]
	for i in int(seconds / DT):
		var out := d.decide_weapons_tactical(me, targets, ctx, DT)
		n[0] += int(out.front)
		n[1] += int(out.rear)
	return n


## Ticks until the first front request (-1 if none within `seconds`).
func _first_front(d: AiDriver, me: Dictionary, targets: Array, ctx: Dictionary, seconds := 3.0) -> int:
	for i in int(seconds / DT):
		if d.decide_weapons_tactical(me, targets, ctx, DT).front:
			return i
	return -1


func test_rear_missile_quality_looks_backwards() -> void:
	var d := _driver(0)
	var ctx := _ctx(W.FRONT_MISSILE, W.REAR_MISSILE)
	assert_gt(d.rear_shot_quality(_me(0), [_target(-250)], ctx), 0.7, "follower right behind")
	assert_eq(d.rear_shot_quality(_me(0), [_target(250)], ctx), 0.0, "car ahead")
	assert_eq(d.rear_shot_quality(_me(0), [_target(-250, 90)], ctx), 0.0, "off the line")


func test_homing_quality_needs_the_nearest_car_ahead() -> void:
	var d := _driver(0)
	var ctx := _ctx(W.HOMING_MISSILE, W.MINE)
	assert_gt(d.homing_quality(_me(0), [_target(300, 100)], ctx), 0.8, "off-axis but ahead: it will turn onto it")
	assert_eq(d.homing_quality(_me(0), [_target(-200), _target(400)], ctx), 0.0, "the nearest car is behind: it would lock on that one")
	assert_eq(d.homing_quality(_me(0), [_target(2000)], ctx), 0.0, "out of range")


func test_super_quality_counts_cars_around_the_orbit() -> void:
	var d := _driver(0)
	var ctx := _ctx(W.SUPER_MISSILE, W.MINE)
	assert_eq(d.super_quality(_me(0), [_target(900)], ctx), 0.0, "nobody near")
	var one := d.super_quality(_me(0), [_target(70, 20)], ctx)
	var two := d.super_quality(_me(0), [_target(70, 20), _target(-60, -30)], ctx)
	assert_gt(one, 0.4)
	assert_gt(two, one)


func test_quality_follows_the_mounted_weapon() -> void:
	var d := _driver(0)
	var ahead := [_target(300)]
	var ctx := _ctx(W.FRONT_MISSILE, W.REAR_MISSILE)
	assert_gt(d.tactical_quality(W.FRONT_MISSILE, _me(0), ahead, ctx), 0.5)
	assert_eq(d.tactical_quality(W.REAR_MISSILE, _me(0), ahead, ctx), 0.0)
	assert_eq(d.tactical_quality(W.NONE, _me(0), ahead, ctx), 0.0)


func test_relative_speed_changes_the_solution() -> void:
	var d := _driver(0)
	var ctx := _ctx(W.FRONT_MISSILE, W.MINE)
	var crossing := _target(500, 150)
	crossing.velocity = Vector2(0, -260)  # drives into the missile's path
	var parked := _target(500, 150, 0.0)
	assert_gt(d.front_shot_quality(_me(0), [crossing], ctx), d.front_shot_quality(_me(0), [parked], ctx))


func test_patience_victor_and_nina_aim_before_shooting_rocco_does_not() -> void:
	var me := _me(0)
	var ahead := [_target(120)]
	var ctx := _ctx(W.FRONT_MISSILE, W.MINE)
	var rocco := _first_front(_driver(2), me, ahead, ctx)
	var victor := _first_front(_driver(1), me, ahead, ctx)
	var nina := _first_front(_driver(9), me, ahead, ctx)
	assert_between(rocco, 0, 17, "Rocco fires almost at once")
	assert_gt(victor, int(0.3 / DT) - 1, "Victor waits for his aim")
	assert_gt(nina, int(0.45 / DT) - 1, "Nina waits longest")


func test_rocco_wastes_rounds_with_nobody_in_sight_victor_never() -> void:
	var ctx := _ctx(W.FRONT_MISSILE, W.MINE)
	assert_gt(_count(_driver(2), _me(0), [_target(2000, 300)], ctx, 20.0)[0], 0)
	assert_eq(_count(_driver(1), _me(0), [_target(2000, 300)], ctx, 20.0)[0], 0)


func test_hank_watches_his_mirrors() -> void:
	var behind := [_target(-260)]
	var ctx := _ctx(W.FRONT_MISSILE, W.REAR_MISSILE)
	var hank := _count(_driver(4), _me(0), behind, ctx, 3.0)[1]
	var maya := _count(_driver(5), _me(0), behind, ctx, 3.0)[1]
	assert_gt(hank, maya, "Hank fires backwards more readily")


func test_super_missile_needs_company_for_the_patient_drivers() -> void:
	var near := [_target(80, 30, 320.0)]
	var ctx := _ctx(W.SUPER_MISSILE, W.MINE)
	assert_eq(_count(_driver(9), _me(0), near, ctx, 3.0)[0], 0, "Nina waits for two cars")
	assert_gt(_count(_driver(6), _me(0), near, ctx, 3.0)[0], 0, "Dante shows off with one")


func test_ellie_rushes_under_pressure() -> void:
	var ahead := [_target(300, 18)]
	var calm := _first_front(_driver(3), _me(0), ahead, _ctx(W.FRONT_MISSILE, W.MINE, 3, false))
	var hurried := _first_front(_driver(3), _me(0), ahead, _ctx(W.FRONT_MISSILE, W.MINE, 3, true))
	assert_true(hurried >= 0 and (calm < 0 or hurried < calm), "calm %d, pressured %d" % [calm, hurried])


func test_finn_takes_brilliant_shots() -> void:
	var d := _driver(8)
	_count(d, _me(0), [_target(200)], _ctx(W.FRONT_MISSILE, W.MINE), 10.0)
	assert_gt(d.brilliant_shots, 0)
	assert_eq(_driver(1).brilliant_shots, 0)


func test_maya_only_takes_opportunities_with_homing() -> void:
	var d := _driver(5)
	var ctx := _ctx(W.HOMING_MISSILE, W.MINE)
	assert_eq(d.homing_quality(_me(0, 300.0), [_target(400, 60, 320.0)], ctx), 0.0, "fast, far target ignored")
	assert_gt(d.homing_quality(_me(0, 300.0), [_target(400, 60, 60.0)], ctx), 0.5, "slow target taken")


func test_victor_keeps_a_reserve_until_the_last_lap() -> void:
	var ctx := _ctx(W.FRONT_MISSILE, W.MINE)
	ctx.front_ammo = 2
	assert_eq(_count(_driver(1), _me(0), [_target(250)], ctx, 5.0)[0], 0)
	ctx.laps_left = 1
	assert_gt(_count(_driver(1), _me(0), [_target(250)], ctx, 5.0)[0], 0)


func test_not_ready_slots_never_fire() -> void:
	var ctx := _ctx(W.FRONT_MISSILE, W.REAR_MISSILE)
	ctx.front_ready = false
	ctx.rear_ready = false
	assert_eq(_count(_driver(2), _me(0), [_target(200), _target(-200)], ctx, 5.0), [0, 0] as Array[int])


func test_tactical_decisions_do_not_touch_the_driving_generator() -> void:
	var a := _driver(2, 77)
	var b := _driver(2, 77)
	_count(a, _me(0), [_target(200), _target(-200)], _ctx(W.FRONT_MISSILE, W.MINE), 3.0)
	assert_eq(a.rng.state, b.rng.state)


func test_classic_traits_unchanged_by_tactical_ones() -> void:
	for id in range(1, 10):
		var p: AiParams = load(RivalRoster.params_path(id))
		assert_between(p.tactical_aim_time, 0.0, 1.0)
		assert_between(p.rear_eagerness, 1.0, 3.0)
	var neutral := AiParams.new()
	assert_eq(neutral.tactical_aim_time, 0.0)
	assert_eq(neutral.rear_eagerness, 1.0)
	assert_eq(neutral.super_min_targets, 1)
	assert_eq(neutral.brilliance_rate, 0.0)
