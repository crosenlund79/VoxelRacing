extends GutTest
## Larkspur Ring (fast and flowing) and Ravenhook (technical, with the
## Raven's Leap flyover jump over the climb and two narrow sections): valid
## original geometry, every theme, all nine rivals completing No Guns,
## Classic and Tactical races with no checkpoint trouble, the jump over live
## traffic, couch, the network bridge restriction and the title's LAYOUT list.

const MAIN_SCENE := preload("res://src/main/main.tscn")
const LARKSPUR := "res://src/track/layouts/larkspur_ring.tres"
const RAVENHOOK := "res://src/track/layouts/ravenhook.tres"
const P := RaceSession.PLAYER_ID

var _main: Node2D


class Drive extends DriverInput:
	var throttle := true
	func _init(t: bool) -> void:
		throttle = t
	func drive(_r: Node, _s: float) -> Dictionary:
		return {"steer": 0.0, "fire": throttle}


func after_each() -> void:
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0
	Engine.max_physics_steps_per_frame = 8


func _make(layout: String, variant := 1, presentation := false) -> void:
	_main = MAIN_SCENE.instantiate()
	_main.presentation_enabled = presentation
	_main.layout_override = load(layout)
	_main.track_variant = variant
	add_child_autofree(_main)
	await wait_physics_frames(2)


func test_both_layouts_are_valid_original_and_in_the_layout_menu() -> void:
	var others: Array = ["res://src/track/circuit_01.tres", "res://src/track/layouts/exp_figure8_01.tres",
		"res://src/track/layouts/kestrel_ridge.tres"]
	for path in [LARKSPUR, RAVENHOOK]:
		var l: TrackLayout = load(path)
		assert_eq(l.validate(), PackedStringArray(), path)
		for o in others + [LARKSPUR, RAVENHOOK]:
			if o != path:
				assert_ne((load(o) as TrackLayout).control_points, l.control_points, "%s is its own geometry" % path)
	assert_eq(DevLayouts.ids(), ["kestrel_ridge", "larkspur_ring", "ravenhook"] as Array[String])
	assert_eq(DevLayouts.DEFAULT, "kestrel_ridge", "Kestrel Ridge stays the default")
	assert_eq(DevLayouts.display_name("larkspur_ring"), "Larkspur Ring")
	assert_eq(DevLayouts.display_name("ravenhook"), "Ravenhook")


func test_larkspur_is_fast_and_ravenhook_technical() -> void:
	var lark: TrackLayout = load(LARKSPUR)
	var raven: TrackLayout = load(RAVENHOOK)
	assert_true(TrackLayout.find_crossings(lark.sample_centerline()).is_empty(), "Larkspur: one flowing loop")
	assert_false(lark.has_jumps())
	var raven_x := TrackLayout.find_crossings(raven.sample_centerline())
	assert_eq(raven_x.size(), 1, "Ravenhook crosses itself once")
	assert_true(raven.is_flyover(0, ClosedPath.new(raven.sample_centerline()).length), "with a flyover jump")
	assert_eq(raven.narrow_sections.size(), 2, "two tactical narrowings")
	var tight := func(l: TrackLayout) -> int: return Array(l.corner_radii).filter(func(r: float) -> bool: return r <= 130.0).size()
	assert_gt(tight.call(raven), tight.call(lark) + 3, "Ravenhook has many more tight corners")
	var wide := func(l: TrackLayout) -> int: return Array(l.corner_radii).filter(func(r: float) -> bool: return r >= 380.0).size()
	assert_gte(wide.call(lark), 5, "Larkspur's wide sweepers")


func test_every_theme_builds() -> void:
	for path in [LARKSPUR, RAVENHOOK]:
		for variant in [1, 2, 3]:
			await _make(path, variant, true)
			assert_eq(_main.track.theme.variant, variant)
			if path == RAVENHOOK:
				assert_true(_main.track.has_node("Ravine0"))
				assert_true(_main.track.has_node("BridgeDeck"))
			_main.queue_free()
			await wait_physics_frames(2)


func _ai_race(path: String, weapons: bool, style := WeaponRules.Style.CLASSIC) -> Dictionary:
	await _make(path)
	_main.set_weapons_enabled(weapons)
	_main.set_combat_style(style)
	_main.set_menu_choice(2)
	_main.set_sim_speed(8)
	_main.start_race()
	var gate_from_upper := [0]
	var jumps := {}
	var was_air := {}
	_main.track.checkpoint_reached.connect(func(_i: int, body: Node2D) -> void:
		if body is Car and _main.car_levels[body.racer_id] != 0:
			gate_from_upper[0] += 1)
	var t := 0
	while _main.session.state != RaceSession.State.FINISHED and t < 60 * 60 * 10:
		await wait_physics_frames(1)
		t += 1
		if _main.jumps != null:
			for id in range(1, 10):
				var a: bool = _main.jumps.is_airborne(id)
				if a and not was_air.get(id, false):
					jumps[id] = jumps.get(id, 0) + 1
				was_air[id] = a
	return {"gate_from_upper": gate_from_upper[0], "jumps": jumps}


func _assert_complete(r: Dictionary, label: String) -> void:
	assert_eq(_main.session.state, RaceSession.State.FINISHED, label)
	assert_eq(_main.session.finish_order.size(), 9, label)
	for p in _main.session.participants():
		assert_true(p.dnf or p.finish_time >= 0.0, "%s %s finished or retired (no safety net)" % [label, p.display_name])
		if not p.dnf:
			assert_eq(p.tracker.laps_completed, _main.session.lap_count(), label)
			if _main.jumps != null:
				assert_gte(r.jumps.get(p.id, 0), _main.session.lap_count(), "%s %s jumped every lap" % [label, p.display_name])
	assert_eq(r.gate_from_upper, 0, label + ": no gate from the upper level")


func test_larkspur_all_rivals_no_guns_and_classic() -> void:
	_assert_complete(await _ai_race(LARKSPUR, false), "Larkspur No Guns")
	_main.queue_free()
	await wait_physics_frames(2)
	_assert_complete(await _ai_race(LARKSPUR, true), "Larkspur Classic")


func test_ravenhook_all_rivals_no_guns_classic_and_tactical() -> void:
	_assert_complete(await _ai_race(RAVENHOOK, false), "Ravenhook No Guns")
	_main.queue_free()
	await wait_physics_frames(2)
	_assert_complete(await _ai_race(RAVENHOOK, true), "Ravenhook Classic")
	_main.queue_free()
	await wait_physics_frames(2)
	_assert_complete(await _ai_race(RAVENHOOK, true, WeaponRules.Style.TACTICAL), "Ravenhook Tactical")


func test_ravens_leap_flies_over_traffic_on_the_climb() -> void:
	await _make(RAVENHOOK)
	_main.start_race()
	await wait_physics_frames(2)
	for id in range(1, 10):
		_main.cars[id].active = false
		_main.cars[id].place(Transform2D(0.0, Vector2(-9000 - id * 300, -9000)))
	var x: Dictionary = TrackLayout.find_crossings(_main.track.centerline)[0]
	var path: ClosedPath = _main.track.path
	var below := 3
	var c3: Car = _main.cars[below]
	c3.place(Transform2D(path.tangent_at(x.s_a).angle(), path.point_at(x.s_a)))
	c3.active = false
	_main.progress[below].reset(c3.global_position)
	var lip: float = _main.track.layout.jumps[0].x
	var c: Car = _main.cars[P]
	c.place(Transform2D(path.tangent_at(lip - 300.0).angle(), path.point_at(lip - 300.0)))
	c.model.velocity = path.tangent_at(lip - 300.0) * 420.0
	_main.progress[P].reset(c.global_position)
	_main.jumps.place(P, lip - 300.0)
	_main.inputs[P] = Drive.new(true)
	var hits := []
	c.car_hit.connect(func(o: Car, _s: float) -> void: hits.append(o.racer_id))
	var flew := false
	for f in 120:
		await wait_physics_frames(1)
		if c.airborne:
			flew = true
		elif flew:
			break
	assert_true(flew, "took off")
	assert_false(_main.jumps.is_down(P), "cleared the gap")
	assert_false(hits.has(below), "over the car on the climb")


func test_narrow_sections_narrow_the_road_and_the_racing_line() -> void:
	await _make(RAVENHOOK)
	var l: TrackLayout = _main.track.layout
	for n in l.narrow_sections:
		var mid := (n.x + n.y) * 0.5
		assert_almost_eq(_main.racing_line.half_width_at(mid), n.z * 0.5, 0.5)
		assert_lte(absf(_main.racing_line.offset_at(mid)), n.z * 0.5 - _main.ai_params.line_margin + 0.5)


func test_couch_and_network_on_ravenhook() -> void:
	_main = MAIN_SCENE.instantiate()
	_main.presentation_enabled = true
	_main.layout_override = load(RAVENHOOK)
	_main.human_count = 2
	_main.player_devices = [3, 4] as Array[int]
	add_child_autofree(_main)
	await wait_physics_frames(2)
	_main.start_race()
	await wait_physics_frames(30)
	assert_eq(_main.player_views.views.size(), 2)
	assert_not_null(_main.jumps, "couch races have the jump")
	_main.queue_free()
	await wait_physics_frames(2)
	var link := NetLink.new()
	add_child_autofree(link)
	link.host(24791)
	_main = MAIN_SCENE.instantiate()
	_main.presentation_enabled = false
	_main.human_count = 2
	_main.layout_override = load(RAVENHOOK)
	_main.net = NetRace.new(link, NetRace.Role.HOST)
	add_child_autofree(_main)
	await wait_physics_frames(2)
	assert_not_null(_main.jumps, "J5: Ravenhook's jump online too")
	assert_false(_main.hud_track_name.contains("ONLINE"))
	link.close()


func test_races_on_both_circuits_are_deterministic() -> void:
	for id in ["larkspur_ring", "ravenhook"]:
		var args := PackedStringArray(["mode=spectate", "ticks=2400", "weapons=1", "layout=" + id])
		var a := ProbeRunner.run(args)
		assert_ne(a, "")
		assert_eq(ProbeRunner.run(args), a, id + ": same in a fresh process")
		assert_eq(ProbeRunner.run(args + PackedStringArray(["speed=8"])), a, id + ": x8 = x1")
