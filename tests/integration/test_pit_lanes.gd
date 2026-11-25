extends GutTest
## Pit lanes and split sections in the race scene: every legal route counts
## laps; a rival really drives into a bay, stops and gets +30; a human's
## double tap overrides the limiter for free; ramming a car in its bay
## tickets the rammer (feed, no K / D), never the victim; harmless touches and
## racing-road contacts are free; three bays serve three cars and a fourth
## never squeezes in or jams the lane; Knockout has no service.

const MAIN_SCENE := preload("res://src/main/main.tscn")
const P := RaceSession.PLAYER_ID

var _main: Node2D


func after_each() -> void:
	Input.action_release(PlayerControls.FIRE)
	Engine.time_scale = 1.0


func _make(layout := "kestrel_ridge", mode := "race", presentation := false) -> void:
	_main = MAIN_SCENE.instantiate()
	_main.presentation_enabled = presentation
	_main.use_command_line_layout = false
	_main.layout_override = load(DevLayouts.LAYOUTS[layout])
	_main.race_mode = mode
	add_child_autofree(_main)
	await wait_physics_frames(2)


## Place the player at arc distance s, in the middle of `lane` there.
func _place_in_lane(s: float, lane: int) -> void:
	var t: Track = _main.track
	var bd := t.layout.route_bounds(s, t.path.length, lane)
	var tan := t.path.tangent_at(s)
	var pos := t.path.point_at(s) + Vector2(-tan.y, tan.x) * (bd.x + bd.y) * 0.5
	_main.car.place(Transform2D(tan.angle(), pos))
	_main.progress[P].reset(pos)  # (a teleport: anchor progress at once, not across the circuit's crossings)


func test_every_route_completes_laps() -> void:
	for lane in 2:  # 0: the racing road and left split lanes; 1: the pit lane and right split lanes
		await _make()
		_main.set_lap_count(1)
		_main.start_race()
		await wait_physics_frames(3)
		var t: Track = _main.track
		for i in range(1, t.checkpoint_count()) + [0]:
			var s: float = t.path.cumulative[t.checkpoint_samples[i]]
			var in_branch := t.layout.branch_at(s, t.path.length) >= 0
			_place_in_lane(s, lane if in_branch else 0)
			await wait_physics_frames(6)
		assert_eq(_main.session.racers[P].tracker.laps_completed, 1, "lane %d: the lap counts (next %d, state %d)" % [lane,
			_main.session.racers[P].tracker.next_checkpoint, _main.session.state])
		_main.queue_free()
		await wait_physics_frames(2)


func test_rival_pit_stop_repairs_thirty_points() -> void:
	await _make()
	_main.set_weapons_enabled(false)
	_main.set_lap_count(4)
	_main.set_menu_choice(2)
	_main.start_race()
	await wait_physics_frames(5)
	_main.damage.condition[1] = 20.0
	await wait_until(func() -> bool: return _main.pits.stops[1] >= 1, 120.0)
	assert_eq(_main.pits.stops[1], 1, "the rival made a pit stop")
	assert_almost_eq(_main.damage.condition[1], 50.0, 0.5, "+30 condition points")
	assert_eq(_main.drivers[1].missed_pits, 0, "it found the pit lane")
	var events: Array = _main.combat.events
	assert_true(events.any(func(e: Dictionary) -> bool: return e.kind == "pit_service" and e.car == 1))


func test_double_tap_override_is_free() -> void:
	await _make("kestrel_ridge", "race", true)
	_main.set_weapons_enabled(false)
	_main.start_race()
	await wait_physics_frames(3)
	var b: Dictionary = _main.track.layout.branches[_main.track.layout.pit_branch()]
	_place_in_lane(float(b.from) + float(b.ramp) + 120.0, 1)
	await wait_physics_frames(10)  # (progress follows a teleport over a few ticks)
	await wait_process_frames(2)
	assert_true(_main.pits.limiter_on(P), "the limiter engaged in the pit lane")
	assert_string_contains(_main.hud.pit_text(), "PIT LIMITER")
	assert_string_contains(_main.hud.pit_text(), PlayerControls.key_text(PlayerControls.FIRE), "the configured accelerator")
	assert_lt(_main.car.model.speed_cap, INF)
	for k in 2:
		Input.action_press(PlayerControls.FIRE)
		await wait_physics_frames(3)
		Input.action_release(PlayerControls.FIRE)
		await wait_physics_frames(3)
	assert_false(_main.pits.limiter_on(P), "limiter overridden")
	assert_eq(_main.car.model.speed_cap, INF, "full speed rules again")
	await wait_process_frames(2)
	assert_string_contains(_main.hud.pit_text(), "LIMITER OFF")
	assert_eq(_main.pits.tickets[P], 0, "no ticket for speeding")
	assert_eq(_main.combat.events.filter(func(e: Dictionary) -> bool: return e.kind == "ticket").size(), 0)
	assert_eq(_main.kill_feed.lines().size(), 0, "nothing in the feed")


## A rival parked in a service bay; returns its id.
func _park_in_bay(id: int, bay: int) -> void:
	var t: Track = _main.track
	var b: Dictionary = t.layout.branches[t.layout.pit_branch()]
	var strip := t.layout.bay_strip(b, t.path.length)
	var s := TrackLayout.bay_centre(b, bay)
	var tan := t.path.tangent_at(s)
	var pos := t.path.point_at(s) + Vector2(-tan.y, tan.x) * (strip.x + strip.y) * 0.5
	var c: Car = _main.cars[id]
	c.place(Transform2D(tan.angle(), pos))
	c.model.velocity = Vector2.ZERO
	_main.progress[id].reset(pos)
	_main.inputs[id] = Hold.new()


class Hold extends DriverInput:
	func drive(_race: Node, _step: float) -> Dictionary:
		return {"steer": 0.0, "fire": false}


class Ram extends DriverInput:
	var steer := 0.0
	func drive(_race: Node, _step: float) -> Dictionary:
		return {"steer": steer, "fire": true}


func _park_others(except: Array) -> void:
	for id in range(1, 10):
		if except.has(id):
			continue
		_main.cars[id].active = false
		_main.cars[id].place(Transform2D(0.0, Vector2(-9000 - id * 300, -9000)))
		_main.progress[id].reset(_main.cars[id].global_position)


func test_ramming_a_car_in_its_bay_tickets_the_rammer_not_the_victim() -> void:
	await _make("kestrel_ridge", "race", true)
	_main.set_weapons_enabled(false)
	_main.start_race()
	await wait_physics_frames(3)
	_park_others([4])
	_park_in_bay(4, 1)
	await wait_physics_frames(4)
	# the player drives straight into the parked car along the bays at speed
	var t: Track = _main.track
	var b: Dictionary = t.layout.branches[t.layout.pit_branch()]
	var strip := t.layout.bay_strip(b, t.path.length)
	var s := TrackLayout.bay_centre(b, 1) - 170.0  # (hard enough to shove the parked car into the wall)
	var tan := t.path.tangent_at(s)
	var pos := t.path.point_at(s) + Vector2(-tan.y, tan.x) * (strip.x + strip.y) * 0.5
	_main.car.place(Transform2D(tan.angle(), pos))
	_main.progress[P].reset(pos)
	_main.pits.in_lane[P] = 1
	_main.pits.overridden[P] = 1  # (speeding is allowed)
	_main.car.model.speed_cap = INF
	_main.car.model.velocity = tan * 300.0
	_main.inputs[P] = Ram.new()
	await wait_physics_frames(120)
	assert_eq(_main.pits.tickets[P], 1, "the rammer: one ticket for one incident")
	assert_eq(_main.pits.tickets[4], 0, "never the stationary victim, not even for being shoved into a wall")
	await wait_process_frames(3)
	assert_true(_main.kill_feed.lines().has("YOU [ticket] PIT COLLISION"), str(_main.kill_feed.lines()))
	assert_eq(_main.stats.line(P), [0, 0, 0], "no kills, deaths or tombstones")


func test_harmless_touches_and_racing_road_contacts_are_free() -> void:
	await _make()
	_main.set_weapons_enabled(false)
	_main.start_race()
	await wait_physics_frames(3)
	_park_others([4])
	_park_in_bay(4, 1)
	await wait_physics_frames(4)
	# a gentle nudge into the parked car (well below the damage threshold)
	var t: Track = _main.track
	var b: Dictionary = t.layout.branches[t.layout.pit_branch()]
	var strip := t.layout.bay_strip(b, t.path.length)
	var s := TrackLayout.bay_centre(b, 1) - 70.0
	var tan := t.path.tangent_at(s)
	var pos := t.path.point_at(s) + Vector2(-tan.y, tan.x) * (strip.x + strip.y) * 0.5
	_main.car.place(Transform2D(tan.angle(), pos))
	_main.progress[P].reset(pos)
	_main.car.model.velocity = tan * 60.0
	_main.inputs[P] = Hold.new()
	await wait_physics_frames(40)
	assert_eq(_main.pits.tickets[P], 0, "a harmless touch is free")
	# a hard hit on the racing road beside the pit lane: not a pit violation
	var on_road := t.path.point_at(s) + Vector2(-tan.y, tan.x) * -30.0
	_main.cars[4].place(Transform2D(tan.angle(), on_road + tan * 120.0))
	_main.progress[4].reset(on_road + tan * 120.0)
	_main.car.place(Transform2D(tan.angle(), on_road))
	_main.progress[P].reset(on_road)
	_main.car.model.velocity = tan * 320.0
	_main.inputs[P] = Ram.new()
	await wait_physics_frames(40)
	assert_eq(_main.pits.tickets[P], 0, "contacts on the racing road never count")
	assert_eq(_main.pits.tickets[4], 0)


func test_three_rivals_service_together_and_a_fourth_finds_the_pit_full() -> void:
	await _make()
	_main.set_weapons_enabled(false)
	_main.set_lap_count(4)
	_main.set_menu_choice(2)
	_main.start_race()
	await wait_physics_frames(3)
	# three rivals hold the bays (low condition: still to be serviced)
	_park_others([1, 2, 3, 4])
	for k in 3:
		_park_in_bay(k + 1, k)
		_main.damage.condition[k + 1] = 30.0
	await wait_physics_frames(20)
	assert_eq(_main.pits.bay_owner, PackedInt32Array([1, 2, 3]), "one car per bay, all three at once")
	await wait_physics_frames(60)
	for id in [1, 2, 3]:
		assert_gt(_main.pits.service[id], 0.0, "rival %d is being serviced" % id)
	# a fourth damaged rival arrives: no free bay, it never gets serviced while they are all held
	_main.damage.condition[4] = 15.0
	var t: Track = _main.track
	var b: Dictionary = t.layout.branches[t.layout.pit_branch()]
	_main.cars[4].active = true
	_main.cars[4].place(Transform2D(t.path.tangent_at(float(b.from) - 400.0).angle(), t.path.point_at(float(b.from) - 400.0)))
	_main.progress[4].reset(_main.cars[4].global_position)
	_main.inputs[4] = AiDriverInput.new(4, _main.drivers[4])
	_main.drivers[4].pitting = true
	_main.drivers[4].pit_entries += 1
	await wait_physics_frames(30)
	assert_eq(_main.pits.free_bays(4), 0, "full")
	assert_eq(_main.pits.bay_of(4), -1)
	await wait_until(func() -> bool: return _main.pits.in_lane[4] == 1, 10.0)
	await wait_physics_frames(60)
	assert_eq(_main.pits.bay_of(4), -1, "never a fourth car in the bays")
	assert_eq(_main.pits.stops[4], 0)
	# the three are done and drive out; the fourth either took a freed bay or gave up and drove on: never stuck
	await wait_until(func() -> bool: return _main.pits.in_lane[4] == 0, 40.0)
	assert_eq(_main.pits.in_lane[4], 0, "the fourth car left the pit lane (no jam)")
	for id in [1, 2, 3]:
		assert_eq(_main.pits.stops[id], 1, "rival %d was serviced" % id)
	assert_gt(_main.drivers[4].pit_abandons + _main.pits.stops[4], 0, "it gave up the stop (or got a bay)")
	# the serviced rivals race on again: out of their bays, along the through-lane, back on the track
	for id in [1, 2, 3]:
		_main.inputs[id] = AiDriverInput.new(id, _main.drivers[id])
	await wait_until(func() -> bool: return [1, 2, 3].all(func(id: int) -> bool: return _main.pits.in_lane[id] == 0), 30.0)
	for id in [1, 2, 3]:
		assert_eq(_main.pits.in_lane[id], 0, "rival %d merged back onto the track" % id)
	assert_eq(_main.pits.bay_owner, PackedInt32Array([-1, -1, -1]), "every bay free again")


func test_held_accelerator_through_the_entry_never_overrides() -> void:
	await _make()
	_main.set_weapons_enabled(false)
	_main.start_race()
	await wait_physics_frames(3)
	var b: Dictionary = _main.track.layout.branches[_main.track.layout.pit_branch()]
	var lane_start: float = float(b.from) + float(b.ramp) - 40.0  # the pit lane is formed; the limiter starts at the divider
	Input.action_press(PlayerControls.FIRE)  # floored from before the lane begins
	_place_in_lane(lane_start, 1)
	_main.car.model.velocity = Vector2.from_angle(_main.car.model.heading) * _main.driving_params.max_speed
	await wait_until(func() -> bool: return _main.pits.in_lane[P] == 1, 10.0)
	await wait_physics_frames(50)
	assert_eq(_main.pits.in_lane[P], 1, "still in the pit lane")
	assert_eq(_main.pits.tickets[P], 0, "holding Fire into the lane is not a double tap")
	assert_lt(_main.car.model.velocity.length(), _main.driving_params.max_speed * 0.5 + 1.0, "held at the limiter")


func test_knockout_has_no_pit_service() -> void:
	await _make("kestrel_ridge", "knockout")
	_main.set_lap_count(9)
	_main.start_race()
	await wait_physics_frames(3)
	assert_false(_main.pits.service_enabled)


func test_a_patient_rival_waits_for_a_bay_and_takes_it_when_freed() -> void:
	await _make()
	_main.set_weapons_enabled(false)
	_main.set_lap_count(4)
	_main.set_menu_choice(2)
	_main.start_race()
	await wait_physics_frames(3)
	_park_others([1, 2, 3, 4])  # rival 1 is Victor (pit_patience 5 s)
	for k in 3:
		_park_in_bay(k + 2, k)
		_main.damage.condition[k + 2] = 100.0  # parked, not being serviced: they never leave on their own
		_main.pits.bay_owner[k] = k + 2  # (held, as if each had stopped there for service)
	_main.damage.condition[1] = 20.0
	var t: Track = _main.track
	var b: Dictionary = t.layout.branches[t.layout.pit_branch()]
	_main.cars[1].active = true
	_main.cars[1].place(Transform2D(t.path.tangent_at(float(b.from) - 400.0).angle(), t.path.point_at(float(b.from) - 400.0)))
	_main.progress[1].reset(_main.cars[1].global_position)
	_main.drivers[1].pitting = true
	_main.drivers[1].pit_entries += 1
	await wait_until(func() -> bool: return _main.drivers[1].pit_waits > 0, 15.0)
	assert_eq(_main.drivers[1].pit_waits, 1, "Victor waits short of the bays")
	assert_lt(_main.cars[1].model.velocity.length(), 20.0, "stopped, waiting")
	# PIT 2 comes free: its occupant drives off the bays
	_main.cars[3].place(Transform2D(0.0, Vector2(-9000, -12000)))
	_main.progress[3].reset(_main.cars[3].global_position)
	_main.cars[3].active = false
	await wait_until(func() -> bool: return _main.pits.stops[1] >= 1, 20.0)
	assert_eq(_main.pits.stops[1], 1, "it took the freed bay and was serviced")
	assert_eq(_main.drivers[1].pit_abandons, 0)
	assert_almost_eq(_main.damage.condition[1], 50.0, 0.5)


## A human-style driver: digital keys only (steer left / right / none, Fire to
## accelerate), aiming a little ahead at a lateral target like a player would:
## the through-lane, then the bay from turn_at (px before the bay centre), a
## stop in the bay, and out again once serviced.
class HumanStyle extends DriverInput:
	var main: Node
	var bay_s := 0.0
	var bay_lat := 0.0
	var lane_lat := 0.0
	var approach := 200.0
	var turn_at := 160.0
	var leaving := false
	func drive(race: Node, _step: float) -> Dictionary:
		var p: RaceProgress = race.progress[0]
		var car: Car = race.car
		var len: float = race.track.path.length
		var w := fposmod(p.distance, len)
		var to_bay := bay_s - w
		var target := lane_lat
		var speed := approach
		if race.pits.served[0] == 1:
			leaving = true
		if leaving:
			speed = 150.0
		elif to_bay < turn_at:
			target = lerpf(lane_lat, bay_lat, clampf(1.0 - (to_bay - 25.0) / (turn_at - 25.0), 0.0, 1.0))
			speed = 0.0 if race.pits.bay_of(0) >= 0 and absf(to_bay) < 30.0 else (45.0 if to_bay < turn_at * 0.6 else 90.0)
		var tan: Vector2 = race.track.path.tangent_at(p.distance + 60.0)
		var want := tan.angle() + atan2(target - p.lateral, 60.0)
		var diff := wrapf(want - car.model.heading, -PI, PI)
		var steer := 0.0 if absf(diff) < deg_to_rad(4.0) else signf(diff)
		return {"steer": steer, "fire": car.model.forward_speed() < speed}


func _middle_bay_with_neighbours(approach: float, turn_at: float) -> Dictionary:
	await _make()
	_main.set_weapons_enabled(false)
	_main.start_race()
	await wait_physics_frames(3)
	_park_others([3, 4])
	_park_in_bay(3, 0)
	_park_in_bay(4, 2)
	_main.damage.condition[3] = 100.0  # parked, not wanting service: still occupying their bays
	_main.damage.condition[4] = 100.0
	var t: Track = _main.track
	var b: Dictionary = t.layout.branches[t.layout.pit_branch()]
	var strip := t.layout.bay_strip(b, t.path.length)
	var input := HumanStyle.new()
	input.bay_s = TrackLayout.bay_centre(b, 1)
	input.bay_lat = (strip.x + strip.y) * 0.5
	input.lane_lat = strip.x - float(b.lane) * 0.5
	input.approach = approach
	input.turn_at = turn_at
	_main.damage.condition[P] = 40.0
	var s := float(b.from) + float(b.ramp) + 40.0
	_place_in_lane(s, 1)
	_main.car.model.velocity = _main.track.path.tangent_at(s) * approach
	_main.inputs[P] = input
	var hits := {"car": 0, "wall": 0, "car_gap": INF, "wall_gap": INF}
	_main.car.car_hit.connect(func(_o: Car, _sp: float) -> void: hits.car += 1)
	_main.car.wall_hit.connect(func(_n: Vector2, _sp: float) -> void: hits.wall += 1)
	var watch := func() -> void: _clearance(hits, [3, 4])
	get_tree().physics_frame.connect(watch)
	await wait_physics_frames(10)
	assert_eq(_main.pits.bay_owner[0], 3, "PIT 1 occupied by a parked car")
	assert_eq(_main.pits.bay_owner[2], 4, "PIT 3 occupied by a parked car")
	await wait_until(func() -> bool: return _main.pits.stops[P] >= 1, 30.0)
	var entry := hits.duplicate()
	await wait_until(func() -> bool: return _main.pits.in_lane[P] == 0, 20.0)
	get_tree().physics_frame.disconnect(watch)
	gut.p("clearance: closest to a parked car %.1f px, to the pit barrier %.1f px" % [hits.car_gap, hits.wall_gap])
	return {"entry": entry, "total": hits, "out": _main.pits.in_lane[P] == 0}


## Car capsule (60 x 32: radius 16, axis 28) clearances while the player is in
## the pit lane: to the parked cars and to the pit's outer barrier.
func _clearance(hits: Dictionary, parked: Array) -> void:
	if _main == null or _main.pits == null or _main.pits.in_lane[P] == 0:
		return
	var me: Car = _main.car
	var ax := Vector2.from_angle(me.model.heading) * 14.0
	for id in parked:
		var o: Car = _main.cars[id]
		var oax := Vector2.from_angle(o.model.heading) * 14.0
		var pts := Geometry2D.get_closest_points_between_segments(me.global_position - ax, me.global_position + ax,
			o.global_position - oax, o.global_position + oax)
		hits.car_gap = minf(hits.car_gap, pts[0].distance_to(pts[1]) - 32.0)
	var t: Track = _main.track
	var p: RaceProgress = _main.progress[P]
	var tan := t.path.tangent_at(p.distance)
	var reach := 16.0 + absf(sin(me.model.heading - tan.angle())) * 14.0
	hits.wall_gap = minf(hits.wall_gap, t.layout.side_widths_at(p.distance, t.path.length).y - (p.lateral + reach))


func test_middle_bay_comfortable_from_the_limiter_with_both_neighbours_parked() -> void:
	var r: Dictionary = await _middle_bay_with_neighbours(205.0, 170.0)
	assert_eq(_main.pits.stops[P], 1, "serviced in PIT 2")
	assert_almost_eq(_main.damage.condition[P], 70.0, 0.5)
	assert_eq(r.entry.car, 0, "in without touching the neighbours")
	assert_eq(r.entry.wall, 0, "in without touching a barrier")
	assert_true(r.out, "out again and on its way")
	assert_eq(r.total.car, 0, "out without touching the car ahead")
	assert_eq(r.total.wall, 0)
	assert_eq(_main.pits.tickets[P], 0)
	assert_gt(r.total.car_gap, 40.0, "comfortable room to the parked cars (px; the old 90 px bays left 25-29)")
	assert_gt(r.total.wall_gap, 12.0, "comfortable room to the barrier (px)")


func test_middle_bay_comfortable_with_a_slow_late_turn_in() -> void:
	var r: Dictionary = await _middle_bay_with_neighbours(90.0, 110.0)
	assert_eq(_main.pits.stops[P], 1, "serviced in PIT 2")
	assert_eq(r.entry.car + r.entry.wall, 0, "in without any contact")
	assert_true(r.out)
	assert_eq(r.total.car + r.total.wall, 0, "out without any contact")
	assert_gt(r.total.car_gap, 40.0, "comfortable room to the parked cars (px; the old 90 px bays left 25-29)")
	assert_gt(r.total.wall_gap, 12.0, "comfortable room to the barrier (px)")


func test_rival_uses_the_middle_bay_with_both_neighbours_parked() -> void:
	await _make()
	_main.set_weapons_enabled(false)
	_main.set_lap_count(4)
	_main.set_menu_choice(2)
	_main.start_race()
	await wait_physics_frames(3)
	_park_others([1, 3, 4])
	_park_in_bay(3, 0)
	_park_in_bay(4, 2)
	_main.damage.condition[3] = 100.0
	_main.damage.condition[4] = 100.0
	var t: Track = _main.track
	var b: Dictionary = t.layout.branches[t.layout.pit_branch()]
	_main.damage.condition[1] = 20.0
	_main.cars[1].place(Transform2D(t.path.tangent_at(float(b.from) - 400.0).angle(), t.path.point_at(float(b.from) - 400.0)))
	_main.progress[1].reset(_main.cars[1].global_position)
	_main.drivers[1].pitting = true
	_main.drivers[1].pit_entries += 1
	var hits := {"car": 0, "wall": 0}
	_main.cars[1].car_hit.connect(func(_o: Car, _sp: float) -> void: hits.car += 1)
	_main.cars[1].wall_hit.connect(func(_n: Vector2, _sp: float) -> void: hits.wall += 1)
	await wait_until(func() -> bool: return _main.pits.stops[1] >= 1, 40.0)
	assert_eq(_main.pits.stops[1], 1, "serviced")
	assert_eq(_main.pits.bay_of(1), 1, "in PIT 2, the only free bay")
	await wait_until(func() -> bool: return _main.pits.in_lane[1] == 0, 20.0)
	assert_eq(_main.pits.in_lane[1], 0, "out and back on the track")
	assert_eq(hits.car, 0, "never touched the parked cars")
	assert_eq(hits.wall, 0, "never touched a barrier")
