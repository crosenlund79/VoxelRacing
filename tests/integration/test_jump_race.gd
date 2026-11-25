extends GutTest
## J3: the experimental jump on the figure-eight in real races: takeoff,
## flight over ground cars, landing back to normal driving, falls and recovery,
## combat in the air, progression and all nine rivals jumping and finishing;
## no jumps on flat circuits or in network races (until J5).

const MAIN_SCENE := preload("res://src/main/main.tscn")
const FIGURE8 := "res://src/track/layouts/exp_figure8_01.tres"
const P := RaceSession.PLAYER_ID

var _main: Node2D


class Drive extends DriverInput:
	## Scripted test driver: straight ahead, throttle held or released.
	var throttle := true
	func _init(p_throttle: bool) -> void:
		throttle = p_throttle
	func drive(_race: Node, _step: float) -> Dictionary:
		return {"steer": 0.0, "fire": throttle}


func after_each() -> void:
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0
	Engine.max_physics_steps_per_frame = 8


func _make(layout := FIGURE8) -> void:
	_main = MAIN_SCENE.instantiate()
	_main.presentation_enabled = false
	if layout != "":
		_main.layout_override = load(layout)
	add_child_autofree(_main)
	await wait_physics_frames(2)


func _lip() -> float:
	return _main.track.layout.jumps[0].x


func _gap() -> float:
	return _main.track.layout.jumps[0].z


## Puts racer id on the road at arc distance s, moving along it at speed. Its
## progress continues from the current lap, so the race carries on normally.
func _place(id: int, s: float, speed: float, throttle := true) -> void:
	var path: ClosedPath = _main.track.path
	var c: Car = _main.cars[id]
	var tan := path.tangent_at(s)
	c.place(Transform2D(tan.angle(), path.point_at(s)))
	c.model.velocity = tan * speed
	_main.progress[id].reset(c.global_position)
	_main.jumps.place(id, s)
	_main.inputs[id] = Drive.new(throttle)


## Racer id's arc distance along the lap.
func _s(id: int) -> float:
	return fposmod(_main.progress[id].distance, _main.track.path.length)


func _park_rivals_far_away() -> void:
	for id in range(1, 10):
		_main.cars[id].active = false
		_main.cars[id].place(Transform2D(0.0, Vector2(-5000 - id * 200, -5000)))
		_main.progress[id].reset(_main.cars[id].global_position)


func test_fast_car_flies_over_a_ground_car_and_lands_driving() -> void:
	await _make()
	_main.start_race()
	await wait_physics_frames(2)
	_park_rivals_far_away()
	var ground := 4
	var path: ClosedPath = _main.track.path
	var gs := _lip() + 110.0
	_main.cars[ground].place(Transform2D(path.tangent_at(gs).angle(), path.point_at(gs)))  # stopped under the flight path
	_main.progress[ground].reset(_main.cars[ground].global_position)
	_place(P, _lip() - 120.0, 420.0)
	var hits := []
	_main.cars[P].car_hit.connect(func(o: Car, _sp: float) -> void: hits.append(o.racer_id))
	var took_off_at := -1.0
	var landed_at := -1.0
	var air_layers := []
	for f in 90:
		await wait_physics_frames(1)
		var c: Car = _main.cars[P]
		if c.airborne:
			if took_off_at < 0.0:
				took_off_at = _s(P)
			air_layers.append(Vector2i(c.collision_layer, c.collision_mask))
		elif took_off_at >= 0.0 and landed_at < 0.0:
			landed_at = _s(P)
			break
	assert_gt(took_off_at, 0.0, "took off")
	assert_almost_eq(took_off_at, _lip(), 15.0, "at the lip")
	assert_gt(landed_at, _lip() + _gap(), "landed past the gap")
	assert_false(_main.jumps.is_down(P))
	for l in air_layers:
		assert_eq(l, Vector2i(Track.CAR_AIR_LAYER, Track.WALL_LAYER | Track.CAR_AIR_LAYER), "flying: barriers only")
	assert_false(hits.has(ground), "flew over the ground car without touching it")
	var c: Car = _main.cars[P]
	assert_eq(Vector2i(c.collision_layer, c.collision_mask), Track.car_collision(0), "ground collisions restored")
	assert_true(c.active)
	# normal driving again: steering turns the car
	var heading := c.global_rotation
	_main.inputs[P] = Steer.new()
	await wait_physics_frames(20)
	assert_gt(absf(angle_difference(heading, c.global_rotation)), 0.05, "steers on the ground again")


class Steer extends DriverInput:
	func drive(_race: Node, _step: float) -> Dictionary:
		return {"steer": 1.0, "fire": true}


func test_steering_in_the_air_changes_nothing() -> void:
	var ends := []
	for steer in [0.0, 1.0]:
		await _make()
		_main.start_race()
		await wait_physics_frames(2)
		_park_rivals_far_away()
		_place(P, _lip() - 5.0, 400.0)
		while not _main.cars[P].airborne:
			await wait_physics_frames(1)
		_main.inputs[P] = Steer.new() if steer > 0.0 else Drive.new(false)
		var c: Car = _main.cars[P]
		var v := c.model.velocity
		var rot := c.global_rotation
		while c.airborne:
			await wait_physics_frames(1)
			if c.airborne:
				assert_almost_eq(c.model.velocity.distance_to(v), 0.0, 0.01, "momentum kept in the air")
				assert_almost_eq(c.global_rotation, rot, 0.0001, "no steering in the air")
		ends.append(c.global_position)
		_main.queue_free()
		await wait_physics_frames(2)
	assert_almost_eq(ends[0].distance_to(ends[1]), 0.0, 1.0, "same landing with or without steering")


func test_speed_decides_the_distance_flown() -> void:
	var flown := []
	var rules: JumpRules = load("res://src/race/default_jump_rules.tres")
	for speed in [360.0, 420.0]:
		await _make()
		_main.start_race()
		await wait_physics_frames(2)
		_park_rivals_far_away()
		_place(P, _lip() - 4.0, speed, false)
		var from := -1.0
		while true:
			await wait_physics_frames(1)
			if _main.cars[P].airborne and from < 0.0:
				from = _s(P)
			elif not _main.cars[P].airborne and from >= 0.0:
				break
		flown.append(_s(P) - from)
		_main.queue_free()
		await wait_physics_frames(2)
	assert_almost_eq(flown[0], rules.flight_distance(360.0), 12.0)
	assert_almost_eq(flown[1], rules.flight_distance(420.0), 12.0)
	assert_gt(flown[1], flown[0] + 40.0, "faster flies further")


func test_slow_car_falls_into_the_gap_then_carries_on() -> void:
	await _make()
	_main.start_race()
	await wait_physics_frames(2)
	_park_rivals_far_away()
	var laps_before: int = _main.session.racers[P].tracker.laps_completed
	_place(P, _lip() - 30.0, 240.0, false)  # off the throttle: slows down
	var dist_before: float = _main.progress[P].distance
	var fell := false
	for f in 60:
		await wait_physics_frames(1)
		if _main.jumps.is_down(P):
			fell = true
			break
	assert_true(fell, "too slow: down in the gap")
	var c: Car = _main.cars[P]
	assert_false(c.active, "cannot drive out of the gap")
	assert_lt(_s(P), _lip() + _gap() + 5.0)
	var pos := c.global_position
	await wait_seconds(1.0)
	assert_eq(c.global_position, pos, "stays down")
	await wait_until(func() -> bool: return not _main.jumps.is_down(P), 3.0)
	await wait_physics_frames(2)
	assert_true(c.active, "drives again")
	assert_almost_eq(_s(P), _lip() + _gap() + _main.jump_rules.recovery_offset, 10.0, "set back past the gap")
	assert_eq(Vector2i(c.collision_layer, c.collision_mask), Track.car_collision(0))
	assert_gt(_main.progress[P].distance, dist_before, "progress carries on (not reset)")
	assert_eq(_main.session.racers[P].tracker.laps_completed, laps_before)


func test_flying_car_is_out_of_reach_of_a_ground_mine() -> void:
	await _make()
	_main.set_weapons_enabled(true)
	_main.start_race()
	await wait_physics_frames(2)
	_park_rivals_far_away()
	_place(P, _lip() - 5.0, 420.0)
	while not _main.cars[P].airborne:
		await wait_physics_frames(1)
	await wait_physics_frames(6)
	var under: Vector2 = _main.cars[P].global_position
	_main.combat.mines.append({"owner": 3, "pos": under, "age": _main.combat.rules.mine_fuse - 0.01, "level": 0, "band": false})
	await wait_physics_frames(3)
	assert_true(_main.cars[P].airborne)
	assert_false(_main.combat.is_wrecked(P), "a mine blast under a flying car does not reach it")


func test_rivals_jump_every_lap_and_finish() -> void:
	await _make()
	_main.set_weapons_enabled(false)
	_main.set_menu_choice(2)
	_main.set_sim_speed(8)
	_main.start_race()
	var takeoffs := {}
	var was_air := PackedByteArray()
	was_air.resize(_main.cars.size())
	var t := 0
	while _main.session.state != RaceSession.State.FINISHED and t < 60 * 60 * 6:
		await wait_physics_frames(1)
		t += 1
		for i in _main.cars.size():
			var a := 1 if _main.jumps.is_airborne(i) else 0
			if a == 1 and was_air[i] == 0:
				takeoffs[i] = takeoffs.get(i, 0) + 1
			was_air[i] = a
	assert_eq(_main.session.state, RaceSession.State.FINISHED)
	for r in _main.session.participants():
		assert_eq(r.tracker.laps_completed, _main.session.lap_count(), "%s finished every lap" % r.display_name)
		assert_gte(r.finish_time, 0.0, "%s finished on track" % r.display_name)
		assert_eq(takeoffs.get(r.id, 0), _main.session.lap_count(), "%s jumped every lap" % r.display_name)


func test_flat_circuit_has_no_jumps() -> void:
	await _make("")
	assert_null(_main.jumps)
	assert_false(_main.track.has_node("Jump0"))
	assert_false(_main.track.layout.has_jumps())


func test_network_races_have_the_figure_eight_jump() -> void:
	var link := NetLink.new()
	add_child_autofree(link)
	link.host(24733)
	_main = MAIN_SCENE.instantiate()
	_main.presentation_enabled = false
	_main.human_count = 2
	_main.layout_override = load(FIGURE8)
	_main.net = NetRace.new(link, NetRace.Role.HOST)
	add_child_autofree(_main)
	await wait_physics_frames(2)
	assert_not_null(_main.jumps, "J5: the host simulates the jump")
	assert_true(_main.track.has_node("Jump0"), "ramp and gap drawn")
	assert_false(_main.hud_track_name.contains("ONLINE"))
	link.close()
