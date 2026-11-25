extends GutTest
## Combat in the full scene: player Up/Down weapons, wreck and respawn, the
## Weapons ON / No Guns option, armed races completing (10-car race and
## spectator), and determinism with weapons on and off (fresh processes).

const MAIN_SCENE := preload("res://src/main/main.tscn")
## M2.3 commit 5b7f2e5 probe hashes (mode, 1800 ticks, no weapons). Weapons OFF
## must reproduce them exactly. Update only for an approved gameplay change.
## Re-recorded 2026-11-16 (race experience: rival lines and ammo pacing change races).
## Re-recorded 2026-11-17 for the human (race-mode) probes only: the approved
## steering precision change ramps the scripted player's key steering. Spectator
## hashes, pit lanes, split sections and lighting change nothing here.
const M23_RACE_HASH := "697e9845ef0994db14bd6c5232bf2ca2"
const M23_SPECTATE_HASH := "00d5a4084c654f1c3c3b7a282ab81edd"

var _main: Node2D


func before_each() -> void:
	_main = MAIN_SCENE.instantiate()
	_main.weapons_lock_enabled = false  # fires at once (the start lock: test_weapons_hot.gd)
	_main.presentation_enabled = false
	add_child_autofree(_main)
	await wait_physics_frames(2)


func after_each() -> void:
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0
	Engine.max_physics_steps_per_frame = 8
	for a in [PlayerControls.FIRE, PlayerControls.FIRE_FRONT, PlayerControls.FIRE_REAR, PlayerControls.STEER_LEFT, PlayerControls.STEER_RIGHT]:
		Input.action_release(a)


func _tap(action: String) -> void:
	Input.action_press(action)
	await wait_physics_frames(2)
	Input.action_release(action)
	await wait_physics_frames(1)


func test_weapons_off_matches_m23_exactly() -> void:
	assert_eq(ProbeRunner.run(["mode=race", "ticks=1800", "weapons=0", "damage=0", "lock=0", "contact=0"]), M23_RACE_HASH)
	assert_eq(ProbeRunner.run(["mode=spectate", "ticks=1800", "weapons=0", "damage=0", "lock=0", "contact=0"]), M23_SPECTATE_HASH)


func test_weapons_on_is_identical_at_normal_and_fast_speed() -> void:
	var normal := ProbeRunner.run(["mode=spectate", "speed=1", "ticks=1500", "weapons=1"])
	var fast := ProbeRunner.run(["mode=spectate", "speed=4", "ticks=1500", "weapons=1"])
	assert_eq(normal.length(), 32, normal)
	assert_eq(fast, normal)


func test_up_down_on_the_grid_toggles_weapons() -> void:
	assert_false(_main.weapons_enabled, "default in the bare scene: No Guns")
	await _tap(PlayerControls.FIRE_FRONT)
	assert_true(_main.weapons_enabled)
	assert_true(_main.combat.enabled)
	await _tap(PlayerControls.FIRE_REAR)
	assert_false(_main.weapons_enabled)


func test_no_guns_means_nobody_fires() -> void:
	_main.set_menu_choice(2)
	_main.start_race()
	await wait_physics_frames(600)
	assert_eq(_main.combat.events.size(), 0)
	for id in range(1, 10):
		assert_eq(_main.combat.ammo[id], [_main.weapon_rules.front_ammo, _main.weapon_rules.rear_ammo])


func test_player_front_missile_destroys_a_car_ahead_which_respawns() -> void:
	_main.set_weapons_enabled(true)
	await _tap(PlayerControls.FIRE)  # start; the player is at the back of the grid
	var ammo_before: int = _main.combat.ammo[0][0]
	await _tap(PlayerControls.FIRE_FRONT)
	assert_eq(_main.combat.ammo[0][0], ammo_before - 1)
	var victim := -1
	for i in 90:
		await wait_physics_frames(1)
		for e in _main.combat.events:
			if e.kind == "destroyed" and e.owner == 0:
				victim = e.car
		if victim >= 0:
			break
	assert_gt(victim, 0, "the missile destroyed a rival ahead")
	if victim < 0:
		return
	assert_false(_main.cars[victim].active, "wrecked car stops")
	await wait_until(func() -> bool: return not _main.combat.is_wrecked(victim), _main.weapon_rules.wreck_time + 1.0)
	await wait_physics_frames(2)
	assert_true(_main.cars[victim].active, "continues after the wreck time")


func test_player_rear_drops_a_mine() -> void:
	_main.set_weapons_enabled(true)
	await _tap(PlayerControls.FIRE)
	await _tap(PlayerControls.FIRE_REAR)
	assert_eq(_main.combat.mines.size(), 1)
	assert_eq(_main.combat.ammo[0][1], _main.weapon_rules.rear_ammo - 1)


func test_armed_spectator_race_completes_and_is_marked() -> void:
	_main.set_menu_choice(2)
	_main.set_weapons_enabled(true)
	_main.set_sim_speed(8)
	_main.start_race()
	await wait_until(func() -> bool: return _main.history.race_count() >= 1, 150.0)
	assert_eq(_main.history.race_count(), 1)
	assert_eq(_main.history.weapons, [true] as Array[bool])
	var order: Array = _main.history.results[0]
	assert_eq(order.size(), 9, "all nine classified")
	var shots := 0
	for id in range(1, 10):
		shots += _main.combat.shots_fired[id]
	assert_gt(shots, 0, "rivals used their weapons")


func test_armed_ten_car_race_lets_opponents_finish() -> void:
	_main.set_weapons_enabled(true)
	_main.set_sim_speed(8)
	await _tap(PlayerControls.FIRE)
	# M6: a rival can retire (DNF) in an armed race; nobody may get stuck
	await wait_until(func() -> bool:
		for r in _main.session.racers:
			if not r.is_player and not r.is_done():
				return false
		return true, 150.0)
	var finished := 0
	var retired := 0
	for r in _main.session.racers:
		if not r.is_player and r.is_finished():
			finished += 1
		elif not r.is_player and r.dnf:
			retired += 1
	assert_eq(finished + retired, 9, "every opponent finishes or retires in an armed race")
	assert_gt(finished, 5, "most finish")
