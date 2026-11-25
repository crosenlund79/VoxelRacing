extends GutTest
## J1: elevation-aware collisions and progression on the experimental
## figure-eight (exp_figure8_01). Cars on different road levels never touch,
## cars on the same level still do, each level has its own barriers, gates are
## never triggered from the bridge, and all nine rivals complete their laps.

const MAIN_SCENE := preload("res://src/main/main.tscn")
const FIGURE8 := "res://src/track/layouts/exp_figure8_01.tres"

var _main: Node2D


class Coast extends DriverInput:
	## Holds the throttle and steers straight (scripted test driver).
	func drive(_race: Node, _step: float) -> Dictionary:
		return {"steer": 0.0, "fire": true}


func after_each() -> void:
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0
	Engine.max_physics_steps_per_frame = 8


func _make() -> void:
	_main = MAIN_SCENE.instantiate()
	_main.weapons_lock_enabled = false  # fires at once (the start lock: test_weapons_hot.gd)
	_main.presentation_enabled = false
	_main.layout_override = load(FIGURE8)
	add_child_autofree(_main)
	await wait_physics_frames(2)


func _crossing() -> Dictionary:
	return TrackLayout.find_crossings(_main.track.centerline)[0]


## Puts racer id on its branch `before` px ahead of arc distance s, moving at speed.
func _place(id: int, s: float, speed: float) -> void:
	var path: ClosedPath = _main.track.path
	var c: Car = _main.cars[id]
	var tan := path.tangent_at(s)
	c.place(Transform2D(tan.angle(), path.point_at(s)))
	c.model.velocity = tan * speed
	_main.progress[id].reset(c.global_position)
	_main.inputs[id] = Coast.new()


func test_cars_on_different_levels_cross_through_each_other() -> void:
	await _make()
	_main.start_race()
	await wait_physics_frames(2)
	var x := _crossing()
	var up := 1
	var down := 2
	_place(up, x.s_a - 140.0, 280.0)
	_place(down, x.s_b - 140.0, 280.0)
	var hits := []
	var walls := []
	for id in [up, down]:
		_main.cars[id].car_hit.connect(func(o: Car, _s: float) -> void: hits.append([id, o.racer_id]))
		_main.cars[id].wall_hit.connect(func(_n: Vector2, _s: float) -> void: walls.append(id))
	var closest := INF
	var layers_at_closest := Vector2i.ZERO
	var start_up: float = _main.progress[up].distance
	var start_down: float = _main.progress[down].distance
	for f in 70:
		await wait_physics_frames(1)
		var d: float = _main.cars[up].global_position.distance_to(_main.cars[down].global_position)
		if d < closest:
			closest = d
			layers_at_closest = Vector2i(_main.cars[up].collision_layer, _main.cars[down].collision_layer)
	assert_lt(closest, 20.0, "the two cars overlapped at the crossing")
	assert_eq(layers_at_closest, Vector2i(Track.CAR_UPPER_LAYER, Track.CAR_LAYER), "upper car on the bridge, lower car underneath")
	assert_eq(hits.filter(func(h: Array) -> bool: return (h[0] == up and h[1] == down) or (h[0] == down and h[1] == up)).size(), 0, "never touched")
	assert_eq(walls.size(), 0, "neither met the other level's barriers")
	assert_gt(_main.progress[up].distance - start_up, 240.0, "upper car carried on along its branch")
	assert_gt(_main.progress[down].distance - start_down, 240.0, "lower car carried on along its branch (no jump to the other branch)")


func test_cars_on_the_same_level_still_collide_on_the_bridge() -> void:
	await _make()
	_main.start_race()
	await wait_physics_frames(2)
	var x := _crossing()
	_place(3, x.s_a - 60.0, 120.0)
	_place(4, x.s_a - 180.0, 400.0)
	var hits := []
	_main.cars[4].car_hit.connect(func(o: Car, _s: float) -> void: hits.append(o.racer_id))
	await wait_physics_frames(60)
	assert_eq(_main.car_levels[3], 1)
	assert_eq(_main.car_levels[4], 1)
	assert_has(hits, 3, "rear-ended on the bridge")


func test_bridge_has_its_own_barriers() -> void:
	await _make()
	_main.start_race()
	await wait_physics_frames(2)
	var x := _crossing()
	var path: ClosedPath = _main.track.path
	var c: Car = _main.cars[5]
	_place(5, x.s_a, 0.0)
	var side := path.tangent_at(x.s_a).orthogonal()
	c.global_rotation = side.angle()
	c.model.heading = side.angle()
	c.model.velocity = side * 300.0  # straight at the bridge railing
	var walls := []
	c.wall_hit.connect(func(_n: Vector2, _s: float) -> void: walls.append(_main.car_levels[5]))
	await wait_physics_frames(40)
	assert_gt(walls.size(), 0, "stopped by the railing")
	assert_eq(walls[0], 1, "an upper-level barrier")
	assert_lt(c.global_position.distance_to(path.point_at(x.s_a)), _main.track.layout.road_width * 0.5 + 5.0, "stayed on the bridge")


func test_all_rivals_complete_their_laps_without_bridge_gate_triggers() -> void:
	await _make()
	_main.set_weapons_enabled(false)
	_main.set_menu_choice(2)  # spectate: the nine rivals
	_main.set_sim_speed(8)
	_main.start_race()
	var from_bridge := []
	_main.track.checkpoint_reached.connect(func(i: int, body: Node2D) -> void:
		if body is Car and _main.car_levels[body.racer_id] != 0:
			from_bridge.append(i))
	var switches := 0
	var last: PackedInt32Array = _main.car_levels.duplicate()
	var t := 0
	while _main.session.state != RaceSession.State.FINISHED and t < 60 * 60 * 6:
		await wait_physics_frames(8)
		t += 8
		for i in last.size():
			if _main.car_levels[i] != last[i]:
				switches += 1
		last = _main.car_levels.duplicate()
	assert_eq(_main.session.state, RaceSession.State.FINISHED)
	for r in _main.session.participants():
		assert_eq(r.tracker.laps_completed, _main.session.lap_count(), "%s finished every lap" % r.display_name)
		assert_gte(r.finish_time, 0.0, "%s finished on track (not classified by the safety net)" % r.display_name)
	assert_eq(from_bridge.size(), 0, "no gate triggered from the bridge")
	assert_gte(switches, 9 * _main.session.lap_count() * 2 - 9, "every car went up and down the bridge each lap")


func test_flat_circuit_never_changes_levels() -> void:
	_main = MAIN_SCENE.instantiate()
	_main.weapons_lock_enabled = false  # fires at once (the start lock: test_weapons_hot.gd)
	_main.presentation_enabled = false
	add_child_autofree(_main)
	await wait_physics_frames(2)
	assert_false(_main.track.has_node("WallsUpper"))
	_main.start_race()
	await wait_physics_frames(120)
	for i in _main.cars.size():
		assert_eq(_main.car_levels[i], 0)
		assert_eq(_main.level_of(i), 0)
	assert_eq(_main.car.collision_layer, 2)
	assert_eq(_main.car.collision_mask, 3)


func test_prototype_race_is_deterministic() -> void:
	var args := PackedStringArray(["mode=spectate", "ticks=2400", "weapons=0", "layout=exp_figure8_01"])
	var a := ProbeRunner.run(args)
	assert_ne(a, "")
	assert_eq(ProbeRunner.run(args), a, "same result in a fresh process")


# --- J2: bridge visuals and draw order (presentation only) ---

func _make_presented(variant := 1) -> void:
	_main = MAIN_SCENE.instantiate()
	_main.weapons_lock_enabled = false  # fires at once (the start lock: test_weapons_hot.gd)
	_main.presentation_enabled = true
	_main.track_variant = variant
	_main.layout_override = load(FIGURE8)
	add_child_autofree(_main)
	await wait_physics_frames(2)


func _min_distance_to_road(p: Vector2) -> float:
	var best := INF
	for q in _main.track.centerline:
		best = minf(best, q.distance_to(p))
	return best


func test_bridge_is_its_own_layer_with_railings_and_shadow() -> void:
	for variant in [1, 2, 3]:
		await _make_presented(variant)
		var t: Track = _main.track
		var deck: Polygon2D = t.get_node("BridgeDeck")
		var road: Polygon2D = t.get_node("Road")
		assert_eq(deck.z_index, Track.BRIDGE_DECK_Z)
		var zone_samples := 0
		for i in t.centerline.size():
			zone_samples += t.level_of_sample(i)
		assert_eq(deck.polygons.size(), zone_samples, "deck = the elevated stretch")
		assert_eq(road.polygons.size() + deck.polygons.size(), t.centerline.size(), "every stretch drawn once")
		var shadows := t.find_children("BridgeShadow*", "Polygon2D", false, false)
		assert_eq(shadows.size(), 1)
		assert_eq(shadows[0].z_index, Track.BRIDGE_SHADOW_Z)
		var rails := t.find_children("Barrier*Upper*", "Line2D", false, false)
		assert_eq(rails.size(), 2, "a railing on each side of the bridge")
		for r in rails:
			assert_eq(r.z_index, Track.BRIDGE_DECK_Z)
		assert_almost_eq(t.bridge_height(t.layout.elevation_zones[0].x + 1.0), 0.0, 0.01, "meets the ground at its ends")
		assert_almost_eq(t.bridge_height(TrackLayout.find_crossings(t.centerline)[0].s_a), 1.0, 0.001, "full height over the crossing")
		_main.free()


func test_flat_circuit_visuals_are_unchanged() -> void:
	_main = MAIN_SCENE.instantiate()
	_main.weapons_lock_enabled = false  # fires at once (the start lock: test_weapons_hot.gd)
	_main.presentation_enabled = true
	add_child_autofree(_main)
	await wait_physics_frames(2)
	var t: Track = _main.track
	assert_false(t.has_node("BridgeDeck"))
	assert_eq(t.find_children("BridgeShadow*", "", false, false).size(), 0)
	for side in ["BarrierLeft", "BarrierRight"]:
		assert_true((t.get_node(side) as Line2D).closed, side + " still one closed line")
	assert_eq(t.get_node("Road").polygons.size(), t.centerline.size())
	assert_false(_main.effects._marks_upper != null)
	assert_false(_main.combat_view.level_of.is_valid())


func test_cars_and_weapons_draw_on_their_level() -> void:
	await _make_presented()
	_main.set_weapons_enabled(true)
	_main.start_race()
	await wait_physics_frames(2)
	var x := _crossing()
	_place(3, x.s_a - 100.0, 0.0)  # on the bridge
	_place(4, x.s_b - 100.0, 0.0)  # below it
	await wait_physics_frames(2)
	await wait_process_frames(2)
	assert_eq(_main.cars[3].z_index, Track.UPPER_Z_OFFSET, "bridge car above the deck")
	assert_eq(_main.cars[4].z_index, 0, "lower car under the deck")
	assert_gt(_main.cars[3].z_index, Track.BRIDGE_DECK_Z)
	assert_lt(_main.cars[4].z_index, Track.BRIDGE_SHADOW_Z)
	assert_gt(_main.player_marker.z_index, Track.UPPER_Z_OFFSET + 3, "your marker on top of both levels")
	var view: CombatView = _main.combat_view
	_main.combat.mines.clear()  # only the two test mines
	_main.combat.cooldown.fill(0.0)  # the AI may have fired (and hit) on the grid
	_main.combat.wreck_left.fill(0.0)
	_main.combat.grace_left.fill(0.0)
	assert_true(_main.combat.request(3, CombatWorld.REAR, _main._combat_states()), "mine dropped on the bridge")
	assert_true(_main.combat.request(4, CombatWorld.REAR, _main._combat_states()), "mine dropped below")
	await wait_process_frames(2)
	var by_owner := {}
	for k in _main.combat.mines.size():
		by_owner[_main.combat.mines[k].owner] = view._mines[k].z_index
	assert_eq(by_owner[3], -2 + Track.UPPER_Z_OFFSET)
	assert_eq(by_owner[4], -2)
	_main.cars[4].global_position += Vector2(5000, 5000)  # owner leaves: a mine keeps its level
	await wait_process_frames(2)
	assert_eq(view._mine_levels, [1, 0] as Array[int])


func test_tyre_marks_on_the_bridge_draw_on_the_deck() -> void:
	await _make_presented()
	var fx: RaceEffects = _main.effects
	assert_not_null(fx._marks_upper)
	assert_eq(fx._marks_upper.z_index, Track.BRIDGE_DECK_Z)
	var slot: int = fx._mark_next
	fx._stamp(Vector2(10, 10), 0.0, 0.8, 1)
	assert_eq(fx._mark_upper[slot], 1, "slot belongs to the deck layer")
	assert_eq(fx._mm(slot), fx._marks_upper.multimesh)
	var next: int = fx._mark_next
	fx._stamp(Vector2(20, 10), 0.0, 0.8, 0)
	assert_eq(fx._mark_upper[next], 0, "a ground mark stays on the ground layer")
	assert_eq(fx._mm(next), fx._marks.multimesh)


func test_scenery_and_lamps_stay_off_both_roads() -> void:
	_main = MAIN_SCENE.instantiate()
	_main.weapons_lock_enabled = false  # fires at once (the start lock: test_weapons_hot.gd)
	_main.presentation_enabled = true
	_main.lighting_on_start = true
	_main.layout_override = load(FIGURE8)
	add_child_autofree(_main)
	await wait_physics_frames(2)
	var half: float = _main.track.layout.road_width * 0.5
	for spr in _main.scenery.get_children():
		if spr is Sprite2D:
			assert_gt(_min_distance_to_road(spr.position), half, "prop %s off the roads" % spr.texture.resource_path.get_file())
	for lamp in _main.lighting._lamp_sprites:
		assert_gt(_min_distance_to_road(lamp.position), half + 19.0, "lamp off the roads")


# --- Figure-eight fixes: no ghosting at the bridge ends ---

## A rival right behind you as you reach either end of the bridge must bump
## into you, not pass through you while the two of you are on different levels.
func test_cars_on_the_same_road_never_pass_through_each_other_at_bridge_ends() -> void:
	for at_start in [true, false]:
		await _make()
		_main.start_race()
		await wait_physics_frames(2)
		var zone: Vector2 = _main.track.layout.elevation_zones[0]
		var edge := zone.x if at_start else zone.y
		_place(0, edge + 6.0, 60.0)    # you: just past the bridge end, slow
		_place(4, edge - 46.0, 380.0)  # Hank: right behind you, fast
		_main.inputs[0] = DriverInput.new()  # you coast
		var hits := []
		_main.cars[4].car_hit.connect(func(o: Car, _s: float) -> void: hits.append(o.racer_id))
		var passed_through := false
		for f in 30:
			await wait_physics_frames(1)
			if _main.progress[4].distance > _main.progress[0].distance and not hits.has(0):
				passed_through = true
		assert_has(hits, 0, "rear-ended you at the %s of the bridge" % ("start" if at_start else "end"))
		assert_false(passed_through, "never through you at the %s of the bridge" % ("start" if at_start else "end"))
		_main.free()


## A car straddling either end of the bridge is drawn whole above the deck
## (never half under it); a car on the lower road under the bridge stays below.
func test_cars_at_bridge_ends_are_drawn_whole_above_the_deck() -> void:
	await _make_presented()
	_main.start_race()
	await wait_physics_frames(2)
	var zone: Vector2 = _main.track.layout.elevation_zones[0]
	var x := _crossing()
	for s in [zone.x - 30.0, zone.x + 10.0, zone.y - 10.0, zone.y + 30.0]:
		_place(3, s, 0.0)
		_place(4, x.s_b, 0.0)  # under the bridge
		await wait_physics_frames(2)
		await wait_process_frames(2)
		assert_gt(_main.cars[3].z_index, Track.BRIDGE_DECK_Z, "whole car above the deck at s=%.0f" % s)
		assert_lt(_main.cars[4].z_index, Track.BRIDGE_SHADOW_Z, "the car below stays under it")


# --- J4: elevation-aware combat in full races ---

func test_armed_ai_races_finish_without_cross_level_kills_at_the_crossing() -> void:
	for style in [WeaponRules.Style.CLASSIC, WeaponRules.Style.TACTICAL]:
		await _make()
		_main.set_weapons_enabled(true)
		_main.set_combat_style(style)
		_main.set_menu_choice(2)  # the nine rivals, their own weapon decisions
		_main.set_sim_speed(8)
		_main.start_race()
		var crossing: Vector2 = _crossing().point
		var across := 0
		var kills := 0
		var cursor := 0
		var t := 0
		while _main.session.state != RaceSession.State.FINISHED and t < 60 * 60 * 6:
			await wait_physics_frames(1)
			t += 1
			while cursor < _main.combat.events.size():
				var e: Dictionary = _main.combat.events[cursor]
				cursor += 1
				if e.kind != "destroyed" or e.owner == e.car:
					continue
				kills += 1
				if e.type == WeaponRules.Weapon.MINE:
					continue  # a mine keeps the level it was dropped on (its owner may have moved on): test_combat_levels
				if _main.car_levels[e.owner] != _main.car_levels[e.car] and _main.car_transitions[e.owner] == 0 \
						and _main.car_transitions[e.car] == 0 and _main.cars[e.car].global_position.distance_to(crossing) < 160.0:
					across += 1
		assert_eq(_main.session.state, RaceSession.State.FINISHED, "style %d race finishes" % style)
		assert_gt(kills, 5, "weapons still destroy cars on their own level")
		assert_eq(across, 0, "nobody destroyed from the other level at the crossing")
		_main.set_sim_speed(1)
		_main.free()
