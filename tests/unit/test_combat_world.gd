extends GutTest
## CombatWorld rules: ammunition, cooldown, every verified weapon type, barrier
## and lifetime limits, wrecks, respawn grace, reset and determinism.

const DT := 1.0 / 60.0
const W := WeaponRules.Weapon

var _rules: WeaponRules


func before_each() -> void:
	_rules = WeaponRules.new()


func _world(cars: int = 3) -> CombatWorld:
	var w := CombatWorld.new(_rules, cars)
	w.enabled = true
	return w


## cars on the X axis, all facing +X.
func _cars(xs: Array, heading := 0.0) -> Array:
	var out := []
	for x in xs:
		out.append({"position": Vector2(x, 0), "heading": heading, "present": true})
	return out


func _run(w: CombatWorld, cars: Array, seconds: float) -> Array[int]:
	var destroyed: Array[int] = []
	for i in int(round(seconds / DT)):
		destroyed.append_array(w.step(DT, cars).destroyed)
	return destroyed


func test_default_loadout_is_front_missiles_and_rear_mines() -> void:
	var r: WeaponRules = load("res://src/combat/default_weapon_rules.tres")
	assert_eq(r.front_weapon, W.FRONT_MISSILE)
	assert_eq(r.rear_weapon, W.MINE)
	assert_gt(r.front_ammo, 0)
	assert_gt(r.rear_ammo, 0)


func test_disabled_world_never_fires() -> void:
	var w := CombatWorld.new(_rules, 2)
	assert_false(w.request(0, CombatWorld.FRONT, _cars([0, 200])))
	assert_eq(w.projectiles.size(), 0)
	assert_eq(w.ammo[0][0], _rules.front_ammo)


func test_ammo_and_cooldown() -> void:
	var w := _world(2)
	var cars := _cars([0, 5000])
	assert_true(w.request(0, CombatWorld.FRONT, cars))
	assert_eq(w.ammo[0][0], _rules.front_ammo - 1)
	assert_false(w.request(0, CombatWorld.FRONT, cars), "cooldown")
	_run(w, cars, _rules.fire_cooldown + DT)
	assert_true(w.request(0, CombatWorld.FRONT, cars))


func test_empty_weapon_does_not_fire() -> void:
	_rules.front_ammo = 1
	var w := _world(2)
	var cars := _cars([0, 5000])
	assert_true(w.request(0, CombatWorld.FRONT, cars))
	_run(w, cars, _rules.fire_cooldown + DT)
	assert_false(w.request(0, CombatWorld.FRONT, cars))
	assert_eq(w.events.filter(func(e: Dictionary) -> bool: return e.kind == "empty").size(), 1)


func test_front_missile_destroys_car_ahead_not_behind_or_owner() -> void:
	var w := _world(3)
	var cars := _cars([0, 300, -150])
	w.request(0, CombatWorld.FRONT, cars)
	var destroyed := _run(w, cars, 1.0)
	assert_eq(destroyed, [1] as Array[int])
	assert_true(w.is_wrecked(1))
	assert_false(w.is_wrecked(0))
	assert_false(w.is_wrecked(2))


func test_front_missile_can_be_dodged() -> void:
	var w := _world(2)
	var cars := _cars([0, 300])
	w.request(0, CombatWorld.FRONT, cars)
	cars[1].position = Vector2(300, 60)  # target moved out of the line
	assert_eq(_run(w, cars, 1.0).size(), 0)


func test_rear_missile_hits_car_behind() -> void:
	_rules.rear_weapon = W.REAR_MISSILE
	var w := _world(3)
	var cars := _cars([0, 300, -250])
	w.request(0, CombatWorld.REAR, cars)
	assert_eq(_run(w, cars, 1.0), [2] as Array[int])


func test_missile_explodes_at_the_barrier_and_after_its_lifetime() -> void:
	var pts := PackedVector2Array()
	for i in 50:
		pts.append(Vector2(i * 20.0, 0.0))
	for i in 50:
		pts.append(Vector2(1000.0 - i * 20.0, 2000.0))
	var w := CombatWorld.new(_rules, 1, ClosedPath.new(pts), 75.0)
	w.enabled = true
	var cars := [{"position": Vector2(100, 0), "heading": PI / 2.0, "present": true}]  # aimed at the barrier
	w.request(0, CombatWorld.FRONT, cars)
	w.step(DT * 10, cars)
	assert_eq(w.projectiles.size(), 0, "stopped at the barrier")
	var open := _world(1)
	open.request(0, CombatWorld.FRONT, _cars([0]))
	_run(open, _cars([0]), _rules.missile_lifetime + 0.1)
	assert_eq(open.projectiles.size(), 0, "fizzles after its lifetime")


func test_mine_explodes_after_the_fuse_destroying_cars_close_by() -> void:
	var w := _world(3)
	var cars := _cars([0, 400, 2000])
	w.request(0, CombatWorld.REAR, cars)
	assert_eq(w.mines.size(), 1)
	var mine_pos: Vector2 = w.mines[0].pos
	cars[1].position = mine_pos + Vector2(20, 0)  # a car parks on the mine
	cars[0].position = Vector2(3000, 0)  # owner drove away
	assert_eq(_run(w, cars, _rules.mine_fuse - 0.1).size(), 0, "nothing before the fuse ends")
	assert_eq(_run(w, cars, 0.2), [1] as Array[int])
	assert_eq(w.mines.size(), 0)


func test_mine_also_destroys_its_owner_if_close() -> void:
	var w := _world(1)
	var cars := _cars([0])
	w.request(0, CombatWorld.REAR, cars)
	assert_eq(_run(w, cars, _rules.mine_fuse + 0.1), [0] as Array[int])


func test_homing_missile_turns_towards_the_nearest_car() -> void:
	_rules.front_weapon = W.HOMING_MISSILE
	var w := _world(3)
	var cars := _cars([0, 0, 2000])
	cars[1].position = Vector2(300, 140)  # off to the side, nearest
	w.request(0, CombatWorld.FRONT, cars)
	assert_eq(_run(w, cars, 1.5), [1] as Array[int])


func test_super_missile_orbits_and_destroys_cars_that_get_close() -> void:
	_rules.front_weapon = W.SUPER_MISSILE
	var w := _world(2)
	var cars := _cars([0, 500])
	w.request(0, CombatWorld.FRONT, cars)
	for i in 30:
		w.step(DT, cars)
		assert_almost_eq(w.projectiles[0].pos.distance_to(cars[0].position), _rules.super_orbit_radius, 0.01)
	cars[1].position = Vector2(0, _rules.super_orbit_radius)
	assert_eq(_run(w, cars, 1.0), [1] as Array[int])
	_run(w, cars, _rules.super_duration)
	assert_eq(w.projectiles.size(), 0, "expires")


func test_wreck_then_respawn_with_grace() -> void:
	var w := _world(2)
	var cars := _cars([0, 300])
	w.request(0, CombatWorld.FRONT, cars)
	_run(w, cars, 1.0)
	assert_true(w.is_wrecked(1))
	assert_false(w.can_fire(1, CombatWorld.FRONT), "wrecked cars cannot fire")
	var respawned := []
	for i in int(_rules.wreck_time / DT) + 2:
		respawned.append_array(w.step(DT, cars).respawned)
	assert_eq(respawned, [1])
	assert_false(w.is_wrecked(1))
	assert_gt(w.grace_left[1], 0.0)
	_rules.fire_cooldown = 0.0
	w.request(0, CombatWorld.FRONT, cars)
	assert_eq(_run(w, cars, 0.5).size(), 0, "protected during respawn grace")


func test_reset_restores_everything() -> void:
	var w := _world(2)
	var cars := _cars([0, 300])
	w.request(0, CombatWorld.FRONT, cars)
	w.request(1, CombatWorld.REAR, cars)
	_run(w, cars, 0.5)
	w.reset()
	assert_eq(w.ammo, [[_rules.front_ammo, _rules.rear_ammo], [_rules.front_ammo, _rules.rear_ammo]])
	assert_eq(w.projectiles.size() + w.mines.size() + w.events.size(), 0)
	assert_false(w.is_wrecked(1))


func test_same_inputs_give_identical_state() -> void:
	var snaps := []
	for k in 2:
		var w := _world(3)
		var cars := _cars([0, 300, -200])
		for i in 240:
			if i % 40 == 0:
				w.request(i % 3, i % 2, cars)
			w.step(DT, cars)
		snaps.append(var_to_bytes(w.state_snapshot()))
	assert_eq(snaps[1], snaps[0])
