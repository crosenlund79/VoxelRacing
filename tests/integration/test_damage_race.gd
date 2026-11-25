extends GutTest
## M6 in real races: weapon destructions, barrier and car impacts wear cars
## down; armour; zero condition = DNF (out of the race, classified last, never
## blocks the road); rivals live by the same rules; garage races carry the
## damage; spectator and couch races; HUD; flat circuit, figure-eight bridge
## and jump.

const MAIN_SCENE := preload("res://src/main/main.tscn")
const FIGURE8 := "res://src/track/layouts/exp_figure8_01.tres"
const P := RaceSession.PLAYER_ID
const P2 := RaceSession.PLAYER_2_ID
const W := WeaponRules.Weapon

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
	for a in [PlayerControls.FIRE, PlayerControls.FIRE_FRONT, PlayerControls.FIRE_REAR]:
		Input.action_release(a)


func _make(humans := 1, garage: PlayerGarage = null, layout := "") -> void:
	_main = MAIN_SCENE.instantiate()
	_main.presentation_enabled = false
	_main.garage = garage
	if humans == 2:
		_main.human_count = 2
		_main.player_devices = [3, 4] as Array[int]
	if layout != "":
		_main.layout_override = load(layout)
	add_child_autofree(_main)
	await wait_physics_frames(2)


func _rules() -> DamageRules:
	return _main.damage_rules


## Parks every rival far away (out of the way, inactive).
func _park_rivals() -> void:
	for id in range(1, 10):
		_main.cars[id].active = false
		_main.cars[id].place(Transform2D(0.0, Vector2(-6000 - id * 300, -6000)))
		_main.progress[id].reset(_main.cars[id].global_position)


## Puts racer id at arc distance s (side px to the right of the centre line),
## heading `angle` off the road direction, moving at speed.
func _place(id: int, s: float, speed: float, angle := 0.0, throttle := true, side := 0.0) -> void:
	var path: ClosedPath = _main.track.path
	var dir := path.tangent_at(s).rotated(angle)
	var c: Car = _main.cars[id]
	c.place(Transform2D(dir.angle(), path.point_at(s) + path.tangent_at(s).orthogonal() * -side))
	c.model.velocity = dir * speed
	c.active = true
	_main.progress[id].reset(c.global_position)
	_main.inputs[id] = Drive.new(throttle)


func _finish(id: int) -> void:
	var cps: int = _main.track.checkpoint_count()
	for lap in _main.session.lap_count():
		for i in range(1, cps):
			_main.session.checkpoint_reached(i, id)
		_main.session.checkpoint_reached(0, id)


## A mine on top of racer id, about to explode.
func _mine_on(id: int) -> void:
	_main.combat.mines.append({"owner": 9 if id != 9 else 8, "pos": _main.cars[id].global_position,
		"age": _main.combat.rules.mine_fuse - 0.01})


func _start(weapons := false) -> void:
	_main.set_weapons_enabled(weapons)
	_main.start_race()
	await wait_physics_frames(2)


# --- damage sources ---

func test_a_weapon_destruction_also_wears_the_car_down() -> void:
	await _make()
	await _start(true)
	_mine_on(P)
	await wait_physics_frames(3)
	assert_true(_main.combat.is_wrecked(P), "the explosion and wreck are unchanged")
	assert_almost_eq(_main.damage.condition[P], 100.0 - _rules().mine_damage, 0.01, "lasting damage")
	assert_false(_main.session.racers[P].dnf, "one explosion is not a DNF")
	await wait_seconds(_main.combat.rules.wreck_time + 0.2)
	assert_true(_main.cars[P].active, "respawned and racing on")


func test_barrier_impacts_damage_by_severity_and_scrapes_are_free() -> void:
	var lost := []
	var cap := 0.0
	for speed in [90.0, 400.0]:
		await _make()
		await _start()
		_park_rivals()
		cap = _rules().wall_max_damage
		var impacts := []
		_main.cars[P].wall_hit.connect(func(_n: Vector2, s: float) -> void: impacts.append(s))
		_place(P, 700.0, speed, PI / 2.0, speed > 100.0, 0.0 if speed > 100.0 else 30.0)  # straight into the barrier
		await wait_physics_frames(40)
		assert_gt(impacts.size(), 0, "hit the barrier at %d" % speed)
		var expected := 0.0
		for s in impacts:
			expected += _rules().wall_damage(s)
		assert_almost_eq(100.0 - _main.damage.condition[P], expected, 0.01)
		lost.append(100.0 - _main.damage.condition[P])
		_main.queue_free()
		await wait_physics_frames(2)
	assert_eq(lost[0], 0.0, "a gentle touch costs nothing")
	assert_gt(lost[1], 5.0, "a hard crash hurts")
	assert_lte(lost[1], cap * 2.0 + 0.01, "capped per impact")


func test_ramming_damages_both_cars_and_nudges_do_not() -> void:
	var results := []
	for speed in [100.0, 420.0]:
		await _make()
		await _start()
		_park_rivals()
		_place(5, 900.0, 0.0, 0.0, false)  # parked ahead
		_place(P, 830.0 if speed < 200.0 else 700.0, speed, 0.0, speed > 200.0)
		var closing := []
		_main.cars[P].car_hit.connect(func(o: Car, s: float) -> void:
			if o.racer_id == 5:
				closing.append(s))
		await wait_physics_frames(45)
		assert_gt(closing.size(), 0, "contact at %d" % speed)
		results.append([100.0 - _main.damage.condition[P], 100.0 - _main.damage.condition[5]])
		_main.queue_free()
		await wait_physics_frames(2)
	assert_eq(results[0], [0.0, 0.0], "a nudge costs nothing")
	assert_gt(results[1][0], 0.0, "the rammer is damaged")
	assert_almost_eq(results[1][0], results[1][1], 0.01, "and so is the rammed car, equally")


func test_armour_reduces_what_the_player_takes() -> void:
	var g := PlayerGarage.new(load("res://src/garage/default_garage_rules.tres"))
	g.money = 5000
	g.buy_armour()
	g.buy_armour()
	await _make(1, g)
	await _start(true)
	assert_almost_eq(_main.damage.armour[P], g.armour_reduction(), 0.0001)
	_mine_on(P)
	_mine_on(3)
	await wait_physics_frames(3)
	var mine := _rules().mine_damage
	assert_almost_eq(100.0 - _main.damage.condition[P], mine * (1.0 - g.armour_reduction()), 0.01, "armoured player")
	assert_almost_eq(100.0 - _main.damage.condition[3], mine, 0.01, "rivals have no armour")


# --- DNF ---

func test_zero_condition_is_a_dnf_out_of_the_way_and_classified_last() -> void:
	await _make()
	await _start(true)
	_main.damage.condition[P] = 5.0
	_mine_on(P)
	await wait_physics_frames(3)
	var me: RacerState = _main.session.racers[P]
	assert_true(me.dnf, "out of the race")
	assert_true(_main.damage.is_retired(P))
	assert_eq(_main.session.state, RaceSession.State.FINISHED, "the race is over for the player")
	assert_eq(Vector2i(_main.cars[P].collision_layer, _main.cars[P].collision_mask), Vector2i.ZERO, "never blocks the road")
	assert_false(_main._combat_states()[P].present, "out of combat")
	await wait_seconds(_main.combat.rules.wreck_time + 0.5)
	assert_false(_main.cars[P].active, "never respawns")
	assert_false(_main.cars[P].visible, "taken off the road")
	assert_eq(_main.session.position_of(P), _main.session.racer_count(), "last while the others race on")
	for id in range(1, 10):
		_finish(id)
	await wait_physics_frames(2)
	assert_true(_main.session.all_finished())
	assert_eq(_main.session.finish_order[-1], P, "classified after every finisher")
	_main._refresh_hud()
	var texts := []
	for l in _main.hud._message_box.find_children("*", "Label", true, false):
		texts.append(l.text)
	assert_has(texts, "DNF", "results say DNF")


func test_rivals_take_the_same_damage_and_can_retire() -> void:
	await _make()
	_main.set_menu_choice(2)
	await _start(true)
	var id := -1
	for k in range(1, 10):
		if not _main.combat.is_wrecked(k) and _main.combat.grace_left[k] <= 0.0:
			id = k
			break
	_main.damage.condition[id] = 10.0
	_mine_on(id)
	await wait_physics_frames(3)
	assert_true(_main.session.racers[id].dnf, "a rival is out legitimately")
	assert_false(_main.cars[id].active)
	assert_eq(_main.session.standings()[-1].id, id)


func test_armed_spectator_race_with_damage_completes_with_a_full_classification() -> void:
	await _make()
	_main.set_menu_choice(2)
	_main.set_sim_speed(8)
	await _start(true)
	var t := 0
	while _main.session.state != RaceSession.State.FINISHED and t < 60 * 60 * 8:
		await wait_physics_frames(8)
		t += 8
	assert_eq(_main.session.state, RaceSession.State.FINISHED)
	assert_eq(_main.session.finish_order.size(), 9, "every rival classified")
	var worn := 0
	for id in range(1, 10):
		var r: RacerState = _main.session.racers[id]
		assert_true(r.dnf or r.finish_time >= 0.0, "%s finished or retired" % r.display_name)
		if _main.damage.condition[id] < 100.0:
			worn += 1
		assert_eq(r.dnf, _main.damage.is_retired(id))
	assert_gt(worn, 4, "a weapons race wears cars down")


# --- garage ---

func test_garage_race_carries_damage_and_repairs_before_the_next_race() -> void:
	var g := PlayerGarage.new(load("res://src/garage/default_garage_rules.tres"))
	g.condition = 80.0
	await _make(1, g)
	await _start(true)
	assert_eq(_main.damage.condition[P], 80.0, "starts with the garage's condition")
	_mine_on(P)
	await wait_physics_frames(3)
	_finish(P)
	await wait_physics_frames(2)
	assert_almost_eq(g.condition, 80.0 - _rules().mine_damage, 0.01, "damage carried to the garage")
	var money := g.money
	assert_true(g.repair(10.0))
	assert_eq(g.money, money - 10 * g.rules.repair_price_per_point)
	_main.close_garage(false)
	_main.reset_race()
	assert_almost_eq(_main.damage.condition[P], 80.0 - _rules().mine_damage + 10.0, 0.5, "repaired car on the grid")


func test_quick_races_and_spectating_start_fully_repaired() -> void:
	await _make()
	await _start()
	for id in _main.grid_order:
		assert_eq(_main.damage.condition[id], 100.0)
		assert_eq(_main.damage.armour[id], 0.0)


# --- couch and HUD ---

func test_couch_one_player_out_the_other_races_on() -> void:
	await _make(2)
	await _start(true)
	_main.damage.condition[P2] = 3.0
	_mine_on(P2)
	await wait_physics_frames(3)
	assert_true(_main.session.racers[P2].dnf)
	assert_eq(_main.session.state, RaceSession.State.RACING, "Player 1 still racing")
	await wait_process_frames(2)
	var views: Array = _main.player_views.views
	for v in views:
		assert_true(v.hud._cond_row.visible)
	var p2_view = views.filter(func(v) -> bool: return v.racer_id == P2)[0]
	assert_true(p2_view.hud._out_label.visible, "Player 2 sees the DNF notice")
	assert_eq(p2_view.hud._cond_label.text, "OUT")
	_finish(P)
	await wait_physics_frames(2)
	assert_eq(_main.session.state, RaceSession.State.FINISHED, "results once Player 1 is in")


func test_hud_shows_condition_flash_and_critical() -> void:
	await _make()
	await _start(true)
	await wait_process_frames(1)
	var hud: Hud = _main.hud
	assert_true(hud._cond_row.visible)
	assert_eq(hud._cond_label.text, "100%")
	_main.damage.condition[P] = 30.0
	_mine_on(P)
	await wait_physics_frames(3)
	await wait_process_frames(1)
	assert_string_contains(hud._cond_label.text, "CRITICAL")
	assert_lt(hud._cond_bar.size.x, 120.0 * 0.2)


func test_spectator_hud_follows_the_chosen_drivers_condition() -> void:
	await _make()
	_main.set_menu_choice(2)
	await _start(true)
	_main.follow_driver(6)
	_main.damage.condition[6] = 41.0
	await wait_process_frames(2)
	assert_eq(_main.hud._cond_label.text, "41%")
	assert_false(_main.hud._out_label.visible)


# --- layouts ---

func test_falling_into_the_jump_gap_damages_the_car() -> void:
	await _make(1, null, FIGURE8)
	await _start()
	_park_rivals()
	var lip: float = _main.track.layout.jumps[0].x
	_place(P, lip - 30.0, 240.0, 0.0, false)
	_main.jumps.place(P, lip - 30.0)
	await wait_until(func() -> bool: return _main.jumps.is_down(P), 2.0)
	assert_almost_eq(_main.damage.condition[P], 100.0 - _rules().jump_fall_damage, 0.01)


func test_figure_eight_race_with_damage_completes() -> void:
	await _make(1, null, FIGURE8)
	_main.set_menu_choice(2)
	_main.set_sim_speed(8)
	await _start(true)
	var t := 0
	while _main.session.state != RaceSession.State.FINISHED and t < 60 * 60 * 8:
		await wait_physics_frames(8)
		t += 8
	assert_eq(_main.session.state, RaceSession.State.FINISHED)
	assert_eq(_main.session.finish_order.size(), 9)


## Found in the J6 sweep: a rival queued for ever behind a retired car, which
## is off the road (invisible, no collisions) but still sat in the AI's
## traffic. Rivals now ignore retired cars (and cars down in a jump's gap).
func test_rivals_drive_past_a_retired_car_on_their_line() -> void:
	await _make()
	await _start()
	_park_rivals()
	var s := 1200.0
	_place(3, s, 0.0, 0.0, false, -28.0)  # two retired side by side: no lane to pass in
	_place(5, s, 0.0, 0.0, false, 28.0)
	for id in [3, 5]:  # worn down to nothing, as in a race
		assert_true(_main.damage.damage(id, 1000.0))
		_main._retire(id)
	await wait_physics_frames(2)
	assert_true(AiDriverInput._gone(_main, 3))
	var c: Car = _main.cars[4]
	c.place(Transform2D(_main.track.path.tangent_at(s - 150.0).angle(), _main.track.path.point_at(s - 150.0)))
	c.model.velocity = _main.track.path.tangent_at(s - 150.0) * 120.0
	c.active = true
	_main.progress[4].reset(c.global_position)  # Hank, with his own AI
	await wait_physics_frames(180)
	assert_gt(_main.progress[4].distance, s + 200.0, "the rival drove on past the retired car")
