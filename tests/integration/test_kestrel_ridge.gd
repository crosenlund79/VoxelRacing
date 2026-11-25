extends GutTest
## Kestrel Ridge, the first original circuit: geometry (two crossings, the
## Watchtower Bridge and the Kestrel Leap flyover jump over the main straight,
## the narrow esses), building with every theme, jump success / failure over
## live traffic, level separation and combat at both crossings, progress and
## laps around the crossings, all-AI races in every combat mode, couch
## split-screen and the network restriction (the jump is a bridge online).

const MAIN_SCENE := preload("res://src/main/main.tscn")
const KESTREL := "res://src/track/layouts/kestrel_ridge.tres"
const P := RaceSession.PLAYER_ID

var _main: Node2D


class Drive extends DriverInput:
	var throttle := true
	func _init(p_throttle: bool) -> void:
		throttle = p_throttle
	func drive(_race: Node, _step: float) -> Dictionary:
		return {"steer": 0.0, "fire": throttle}


func after_each() -> void:
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0
	Engine.max_physics_steps_per_frame = 8


func _layout() -> TrackLayout:
	return load(KESTREL)


func _make(variant := 1, presentation := false) -> void:
	_main = MAIN_SCENE.instantiate()
	_main.presentation_enabled = presentation
	_main.layout_override = _layout()
	_main.track_variant = variant
	add_child_autofree(_main)
	await wait_physics_frames(2)


func _crossings() -> Array[Dictionary]:
	return TrackLayout.find_crossings(_layout().sample_centerline())


## The crossing under the jump (its upper branch carries the jump).
func _jump_crossing() -> Dictionary:
	var j := _layout().jumps[0]
	for x in _crossings():
		if x.s_b > j.x and x.s_b < j.x + j.z:
			return x
	return {}


func _park_rivals() -> void:
	for id in range(1, 10):
		_main.cars[id].active = false
		_main.cars[id].place(Transform2D(0.0, Vector2(-8000 - id * 300, -8000)))
		_main.progress[id].reset(_main.cars[id].global_position)


func _place(id: int, s: float, speed: float, throttle := true) -> void:
	var path: ClosedPath = _main.track.path
	var c: Car = _main.cars[id]
	var tan := path.tangent_at(s)
	c.place(Transform2D(tan.angle(), path.point_at(s)))
	c.model.velocity = tan * speed
	c.active = true
	_main.progress[id].reset(c.global_position)
	_main.session.set_progress(id, _main.progress[id].distance)
	if _main.jumps != null:
		_main.jumps.place(id, s)
	_main.inputs[id] = Drive.new(throttle)


func _s(id: int) -> float:
	return fposmod(_main.progress[id].distance, _main.track.path.length)


# --- geometry ---

func test_layout_is_valid_original_and_has_its_features() -> void:
	var l := _layout()
	assert_eq(l.validate(), PackedStringArray())
	assert_eq(l.display_name, "Kestrel Ridge")
	var xs := _crossings()
	assert_eq(xs.size(), 2, "two crossings: the bridge and the jump")
	for x in xs:
		assert_almost_eq(x.angle, PI / 2.0, 0.01, "square crossings")
	assert_eq(l.jumps.size(), 1)
	assert_true(l.is_flyover(0, ClosedPath.new(l.sample_centerline()).length), "the jump flies over a road")
	assert_eq(l.narrow_sections.size(), 1)
	assert_lt(l.narrow_sections[0].z, l.road_width)
	assert_gte(l.narrow_sections[0].z, TrackLayout.MIN_NARROW_WIDTH)
	for legacy in ["res://src/track/circuit_01.tres", "res://src/track/layouts/exp_figure8_01.tres"]:
		var o: TrackLayout = load(legacy)
		assert_ne(o.control_points, l.control_points, "not a reshaped legacy layout")
	var path := ClosedPath.new(l.sample_centerline())
	assert_gt(path.length, 12000.0)
	assert_lt(path.length, 15000.0)


func test_builds_with_every_theme_with_bridge_ravine_and_narrowing() -> void:
	for variant in [1, 2, 3]:
		await _make(variant, true)
		var track: Track = _main.track
		assert_true(track.has_node("BridgeDeck"), "theme %d: bridge deck" % variant)
		assert_true(track.has_node("Ravine0"), "theme %d: the jump's ravine" % variant)
		assert_true(track.has_node("Jump0"))
		var n := track.centerline.size()
		var narrowest := INF
		for h in track.half_widths:
			narrowest = minf(narrowest, h)
		assert_almost_eq(narrowest * 2.0, _layout().narrow_sections[0].z, 1.0, "the esses are narrower")
		var gap_samples := 0
		for i in n:
			if track.in_flyover_gap(i):
				gap_samples += 1
				assert_eq(track.level_of_sample(i), 1, "the gap is on the elevated road")
		assert_gt(gap_samples, 10)
		_main.queue_free()
		await wait_physics_frames(2)


# --- the Kestrel Leap ---

func test_fast_car_flies_over_main_straight_traffic_and_lands_on_its_road() -> void:
	await _make()
	_main.start_race()
	await wait_physics_frames(2)
	_park_rivals()
	var x := _jump_crossing()
	var below := 6
	_place(below, x.s_a - 40.0, 0.0, false)  # stopped on the main straight, under the jump
	var lip := _layout().jumps[0].x
	_place(P, lip - 260.0, 420.0)
	var hits := []
	_main.cars[P].car_hit.connect(func(o: Car, _sp: float) -> void: hits.append(o.racer_id))
	var flew := false
	var landed_at := -1.0
	var air_z := 0
	for f in 120:
		await wait_physics_frames(1)
		var c: Car = _main.cars[P]
		if c.airborne:
			flew = true
			air_z = maxi(air_z, c.z_index)
			assert_eq(c.collision_mask & Track.WALL_LAYER, 0, "only its own road's barriers in the air")
		elif flew:
			landed_at = _s(P)
			break
	assert_true(flew, "took off")
	assert_gt(landed_at, lip + _layout().jumps[0].z, "cleared the gap")
	assert_false(hits.has(below), "never touched the car below")
	assert_eq(_main.car_levels[P], 1, "landed on the elevated road")
	assert_eq(Vector2i(_main.cars[P].collision_layer, _main.cars[P].collision_mask), Track.car_collision(1), "normal collisions back")
	_main._present_levels()
	assert_gt(air_z, _main.cars[below].z_index, "drawn above the traffic below")
	assert_eq(_main.damage.condition[P], 100.0, "a clean jump costs nothing")


func test_slow_car_falls_into_the_ravine_without_hitting_the_road_below_and_recovers() -> void:
	await _make()
	_main.start_race()
	await wait_physics_frames(2)
	_park_rivals()
	var lip := _layout().jumps[0].x
	_place(P, lip - 40.0, 250.0, false)
	await wait_until(func() -> bool: return _main.jumps.is_down(P), 2.0)
	assert_true(_main.jumps.is_down_in_flyover(P), "fell short of the far side")
	await wait_physics_frames(1)
	var c: Car = _main.cars[P]
	assert_eq(Vector2i(c.collision_layer, c.collision_mask), Vector2i.ZERO, "in the ravine: no collisions with the road below")
	_main._present_levels()
	assert_eq(c.z_index, 0, "drawn down on the ground")
	assert_almost_eq(_main.damage.condition[P], 100.0 - _main.damage_rules.jump_fall_damage, 0.01)
	await wait_until(func() -> bool: return not _main.jumps.is_down(P), 3.0)
	await wait_physics_frames(2)
	assert_true(c.active)
	assert_gt(_s(P), lip + _layout().jumps[0].z, "set back past the gap")
	assert_eq(_main.car_levels[P], 1)
	assert_eq(Vector2i(c.collision_layer, c.collision_mask), Track.car_collision(1), "collisions restored")


func test_clearing_speed_matches_the_circuit_rules() -> void:
	var rules: JumpRules = _layout().jump_rules
	var gap := _layout().jumps[0].z
	assert_lt(rules.clearing_speed(gap), 400.0, "a clean exit from the Horseshoe clears it")
	assert_gt(rules.clearing_speed(gap), 340.0, "a slow exit does not")
	assert_gt(rules.flight_distance(420.0), gap, "top speed clears with room to spare")


func test_flying_car_is_out_of_reach_of_a_mine_on_the_main_straight() -> void:
	await _make()
	_main.set_weapons_enabled(true)
	_main.start_race()
	await wait_physics_frames(2)
	_park_rivals()
	var lip := _layout().jumps[0].x
	_place(P, lip - 10.0, 420.0)
	while not _main.cars[P].airborne:
		await wait_physics_frames(1)
	await wait_physics_frames(8)
	_main.combat.mines.append({"owner": 3, "pos": _main.cars[P].global_position, "age": _main.combat.rules.mine_fuse - 0.01,
		"level": 0, "band": false})
	await wait_physics_frames(3)
	assert_false(_main.combat.is_wrecked(P))


# --- the Watchtower Bridge ---

func test_bridge_traffic_and_main_straight_traffic_pass_without_touching() -> void:
	await _make()
	_main.start_race()
	await wait_physics_frames(2)
	_park_rivals()
	var bridge: Dictionary = {}
	for x in _crossings():
		if x != _jump_crossing():
			bridge = x
	var up := 2
	var down := 7
	_place(up, bridge.s_b - 150.0, 300.0)
	_place(down, bridge.s_a - 150.0, 300.0)
	var hits := []
	_main.cars[up].car_hit.connect(func(o: Car, _sp: float) -> void: hits.append(o.racer_id))

	_main.cars[down].car_hit.connect(func(o: Car, _sp: float) -> void: hits.append(o.racer_id))
	var closest := INF
	for f in 40:
		await wait_physics_frames(1)
		closest = minf(closest, _main.cars[up].global_position.distance_to(_main.cars[down].global_position))
	assert_lt(closest, 30.0, "they crossed")
	assert_eq(hits.size(), 0, "on different levels")
	assert_eq(_main.damage.condition[up] + _main.damage.condition[down], 200.0)


# --- racing ---

func _ai_race(weapons: bool, style := WeaponRules.Style.CLASSIC) -> Dictionary:
	await _make()
	_main.set_weapons_enabled(weapons)
	_main.set_combat_style(style)
	_main.set_menu_choice(2)
	_main.set_sim_speed(8)
	_main.start_race()
	var jumps := {}
	var gate_from_upper := 0
	var big_jumps := 0
	var was_air := {}
	var was_down := {}
	var last := {}
	_main.track.checkpoint_reached.connect(func(_i: int, body: Node2D) -> void:
		if body is Car and _main.car_levels[body.racer_id] != 0:
			gate_from_upper += 1)
	var t := 0
	while _main.session.state != RaceSession.State.FINISHED and t < 60 * 60 * 10:
		await wait_physics_frames(1)
		t += 1
		for id in range(1, 10):
			var a: bool = _main.jumps.is_airborne(id)
			if a and not was_air.get(id, false):
				jumps[id] = jumps.get(id, 0) + 1
			was_air[id] = a
			var d: float = _main.progress[id].distance
			var down: bool = _main.jumps.is_down(id)
			# (a car recovering from a fall is set back past the gap: not a branch jump)
			if last.has(id) and absf(d - last[id]) > 40.0 and not down and not was_down.get(id, false) \
					and not _main.combat.is_wrecked(id):
				big_jumps += 1
			was_down[id] = down
			last[id] = d
	return {"jumps": jumps, "gate_from_upper": gate_from_upper, "progress_jumps": big_jumps}


func _assert_complete(r: Dictionary, label: String) -> void:
	assert_eq(_main.session.state, RaceSession.State.FINISHED, label)
	assert_eq(_main.session.finish_order.size(), 9, label + ": everyone classified")
	for p in _main.session.participants():
		assert_true(p.dnf or p.finish_time >= 0.0, "%s %s finished on the road or retired (no safety net)" % [label, p.display_name])
		if not p.dnf:
			assert_eq(p.tracker.laps_completed, _main.session.lap_count(), label)
			assert_gte(r.jumps.get(p.id, 0), _main.session.lap_count(), "%s %s took the Kestrel Leap every lap" % [label, p.display_name])
	assert_eq(r.gate_from_upper, 0, label + ": no gate triggered from the bridge or the leap")
	assert_eq(r.progress_jumps, 0, label + ": progress never jumps between branches at the crossings")


func test_all_nine_rivals_complete_a_no_guns_race() -> void:
	_assert_complete(await _ai_race(false), "No Guns")


func test_all_nine_rivals_complete_a_classic_combat_race() -> void:
	_assert_complete(await _ai_race(true), "Classic")


func test_all_nine_rivals_complete_a_tactical_combat_race() -> void:
	_assert_complete(await _ai_race(true, WeaponRules.Style.TACTICAL), "Tactical")


func test_narrow_esses_limit_passing_room() -> void:
	await _make()
	var line: RacingLine = _main.racing_line
	var n := _layout().narrow_sections[0]
	var mid := (n.x + n.y) * 0.5
	assert_almost_eq(line.half_width_at(mid), n.z * 0.5, 0.5)
	assert_eq(line.half_width_at(1000.0), _layout().road_width * 0.5)
	var lim: float = line.half_width_at(mid) - _main.ai_params.line_margin
	for k in range(int(n.x + 150.0), int(n.y - 150.0), 20):
		assert_lte(absf(line.offset_at(k)), lim + 0.5, "racing line inside the narrow road at %d" % k)


# --- couch, network ---

func test_couch_split_screen_race_runs_with_both_players_on_the_circuit() -> void:
	_main = MAIN_SCENE.instantiate()
	_main.presentation_enabled = true
	_main.layout_override = _layout()
	_main.human_count = 2
	_main.player_devices = [3, 4] as Array[int]
	add_child_autofree(_main)
	await wait_physics_frames(2)
	_main.start_race()
	await wait_physics_frames(60)
	assert_not_null(_main.player_views)
	assert_eq(_main.player_views.views.size(), 2)
	assert_not_null(_main.jumps, "local couch races have the jump")
	for v in _main.player_views.views:
		assert_eq(v.camera.target, _main.cars[v.racer_id])


func test_network_races_have_the_real_leap() -> void:
	var link := NetLink.new()
	add_child_autofree(link)
	link.host(24761)
	_main = MAIN_SCENE.instantiate()
	_main.presentation_enabled = false
	_main.human_count = 2
	_main.layout_override = _layout()
	_main.net = NetRace.new(link, NetRace.Role.HOST)
	add_child_autofree(_main)
	await wait_physics_frames(2)
	assert_not_null(_main.jumps, "J5: jumping online")
	assert_true(_main.track.has_node("Ravine0"), "the ravine")
	assert_true(_main.track.has_node("Jump0"), "the ramp markings")
	var gap := false
	for i in _main.track.centerline.size():
		gap = gap or _main.track.in_flyover_gap(i)
	assert_true(gap, "no deck over the gap, as offline")
	assert_false(_main.hud_track_name.contains("ONLINE"), "no online note any more")
	link.close()
