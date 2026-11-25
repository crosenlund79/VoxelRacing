extends GutTest
## Personality-driven weapon decisions: same rules for all, recognisable choices.

const DT := 1.0 / 60.0

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
	var d := AiDriver.new(_line, load(RivalRoster.params_path(id)))
	d.begin_race(seed_value)
	return d


func _me(x: float, speed := 300.0) -> Dictionary:
	return {"position": Vector2(x, 0), "heading": 0.0, "speed": speed, "distance": x, "lateral": 0.0}


func _target(x: float, y := 0.0, speed := 300.0) -> Dictionary:
	return {"position": Vector2(x, y), "velocity": Vector2(speed, 0), "distance": x, "lateral": y, "speed": speed, "wrecked": false}


func _ctx(front_ammo := 5, laps_left := 3, pressure := false) -> Dictionary:
	return {"front_ready": true, "rear_ready": true, "front_ammo": front_ammo, "front_start": 5, "laps_left": laps_left,
		"lap_count": 3, "missile_speed": 820.0, "hit_radius": 24.0, "mine_fuse": 3.0, "pressure": pressure}


## Shots fired over `seconds` with a fixed situation.
func _shots(d: AiDriver, me: Dictionary, targets: Array, ctx: Dictionary, seconds := 5.0) -> int:
	var n := 0
	for i in int(seconds / DT):
		if d.decide_weapons(me, targets, ctx, DT).front:
			n += 1
	return n


func test_shot_quality_rewards_aligned_targets() -> void:
	var d := _driver(1)
	assert_gt(d.front_shot_quality(_me(0), [_target(300)], _ctx()), 0.7)
	assert_eq(d.front_shot_quality(_me(0), [_target(300, 80)], _ctx()), 0.0, "far off the line")
	assert_eq(d.front_shot_quality(_me(0), [_target(-300)], _ctx()), 0.0, "behind")
	var wrecked := _target(300)
	wrecked.wrecked = true
	assert_eq(d.front_shot_quality(_me(0), [wrecked], _ctx()), 0.0)


func test_every_rival_fires_at_a_point_blank_shot() -> void:
	for id in range(1, 10):
		if id == 5:
			continue  # Maya only attacks vulnerable targets (own test)
		var d := _driver(id)
		assert_gt(_shots(d, _me(0), [_target(120)], _ctx(5, 1), 3.0), 0, RivalRoster.short_name(id))


## Victor saves his last rounds for clearly better chances, but never by an
## absolute rule (2026-11-23): a near-perfect shot late in the race is taken,
## and in the closing stage nothing is saved any more.
func test_victor_keeps_a_soft_reserve() -> void:
	var v := _driver(1)
	assert_eq(_shots(v, _me(0), [_target(250)], _ctx(2, 2)), 0, "an ordinary shot early on: kept")
	assert_gt(v.held_for_reserve, 0, "turned down by the ammunition plan")
	assert_gt(v.reserve_penalty(2, _ctx(2, 2)), 0.0)
	var late := _ctx(2, 2)
	late.progress = 0.7  # on schedule late in the race
	assert_gt(_shots(v, _me(0), [_target(60)], late), 0, "a near-perfect shot is not refused")
	assert_gt(_shots(v, _me(0), [_target(250)], _ctx(2, 1)), 0, "spends it on the last lap")


func test_rocco_wastes_rounds_without_a_target() -> void:
	var rocco := _driver(2)
	assert_gt(_shots(rocco, _me(0), [], _ctx(), 30.0), 0)
	assert_eq(rocco.wasted_shots, rocco.front_shots)
	var victor := _driver(1)
	assert_eq(_shots(victor, _me(0), [], _ctx(), 30.0), 0)


func test_ellie_takes_hastier_shots_under_pressure() -> void:
	var half_shot := [_target(300, 22)]  # marginal alignment
	var calm := _shots(_driver(3, 4), _me(0), half_shot, _ctx(5, 3, false), 10.0)
	var pressed := _shots(_driver(3, 4), _me(0), half_shot, _ctx(5, 3, true), 10.0)
	assert_eq(calm, 0)
	assert_gt(pressed, 0)


func test_hank_retaliates_with_more_mines_after_being_destroyed() -> void:
	var follower := [_target(-900, 0, 300)]  # arrives at the drop point as the fuse ends
	var base := _driver(4, 9)
	var calm := 0
	var angry := 0
	for i in int(10.0 / DT):
		if base.decide_weapons(_me(0), follower, _ctx(), DT).rear:
			calm += 1
	var hank := _driver(4, 9)
	hank.on_destroyed()
	for i in int(10.0 / DT):
		if hank.decide_weapons(_me(0), follower, _ctx(), DT).rear:
			angry += 1
	assert_gt(angry, calm)


func test_maya_only_attacks_vulnerable_targets() -> void:
	var maya := _driver(5)
	assert_eq(_shots(maya, _me(0, 300), [_target(400, 0, 300)], _ctx()), 0, "healthy target at speed")
	assert_gt(_shots(maya, _me(0, 300), [_target(400, 0, 100)], _ctx()), 0, "slow / recovering target")


func test_dante_takes_long_shots_nina_does_not() -> void:
	var far := [_target(700)]
	assert_gt(_shots(_driver(6), _me(0), far, _ctx(5, 1)), 0)
	assert_eq(_shots(_driver(9), _me(0), far, _ctx(5, 1)), 0)


func test_greta_paces_her_ammunition_over_the_laps() -> void:
	var g := _driver(7)
	assert_eq(_shots(g, _me(0), [_target(250)], _ctx(3, 3)), 0, "3 rounds left with 3 laps to go: hold")
	assert_gt(_shots(g, _me(0), [_target(250)], _ctx(5, 3)), 0, "above budget: fire")


func test_finn_sometimes_takes_poor_shots() -> void:
	var poor := [_target(300, 22)]
	var finn_shots := 0
	for s in 10:
		finn_shots += _shots(_driver(8, s), _me(0), poor, _ctx(), 3.0)
	assert_gt(finn_shots, 0)
	assert_eq(_shots(_driver(1), _me(0), poor, _ctx(5, 1), 30.0), 0, "Victor never does")


func test_mine_timing_matches_the_fuse() -> void:
	var d := _driver(4)
	assert_gt(d.mine_quality(_me(0), [_target(-900, 0, 300)], _ctx()), 0.8, "arrives as the fuse ends")
	assert_eq(d.mine_quality(_me(0), [_target(-100, 0, 300)], _ctx()), 0.0, "would pass before it explodes")


func test_weapon_decisions_do_not_change_driving_decisions() -> void:
	var a := _driver(2, 3)
	var b := _driver(2, 3)
	for i in 300:
		var me := _me(500.0 + i * 3.0)
		var others := [{"distance": 600.0 + i * 3.0, "lateral": 0.0, "speed": 250.0}]
		b.decide_weapons(me, [_target(600.0 + i * 3.0)], _ctx(), DT)
		assert_eq(a.decide(me, others, DT), b.decide(me, others, DT))
