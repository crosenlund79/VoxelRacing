extends GutTest
## M3.5 Stage 1: per-car loadouts (all five weapons, slot compatibility) and the
## Classic / Tactical combat styles in CombatWorld.

const DT := 1.0 / 60.0
const W := WeaponRules.Weapon
const F := CombatWorld.FRONT
const R := CombatWorld.REAR

var _rules: WeaponRules


func before_each() -> void:
	_rules = WeaponRules.new()


func _world(cars: int = 3, style := WeaponRules.Style.CLASSIC) -> CombatWorld:
	var w := CombatWorld.new(_rules, cars)
	w.enabled = true
	w.style = style
	return w


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


func test_slot_compatibility() -> void:
	for w in [W.FRONT_MISSILE, W.HOMING_MISSILE, W.SUPER_MISSILE]:
		assert_true(WeaponRules.compatible(w, F))
		assert_false(WeaponRules.compatible(w, R))
	for w in [W.REAR_MISSILE, W.MINE]:
		assert_true(WeaponRules.compatible(w, R))
		assert_false(WeaponRules.compatible(w, F))
	assert_false(WeaponRules.compatible(W.NONE, F))
	assert_eq(WeaponRules.ALL_WEAPONS.size(), 5)


func test_default_loadout_matches_rules_and_reset_restores_it() -> void:
	var w := _world(3)
	for i in 3:
		assert_eq(w.loadout[i], [_rules.front_weapon, _rules.rear_weapon])
		assert_eq(w.ammo[i], [_rules.front_ammo, _rules.rear_ammo])
	w.set_loadout(1, W.HOMING_MISSILE, 3, W.REAR_MISSILE, 2)
	assert_eq(w.loadout[1], [W.HOMING_MISSILE, W.REAR_MISSILE])
	assert_eq(w.ammo[1], [3, 2])
	assert_eq(w.start_ammo[1], [3, 2])
	w.reset()
	assert_eq(w.loadout[1], [_rules.front_weapon, _rules.rear_weapon])


func test_incompatible_weapon_is_not_mounted() -> void:
	var w := _world(2)
	w.set_loadout(0, W.MINE, 4, W.HOMING_MISSILE, 4)
	assert_eq(w.loadout[0], [W.NONE, W.NONE])
	assert_eq(w.ammo[0], [0, 0])
	assert_false(w.can_fire(0, F))
	assert_false(w.request(0, F, _cars([0, 300])))
	assert_eq(w.events.size(), 0, "no weapon: no empty click either")


func test_negative_ammo_is_clamped() -> void:
	var w := _world(2)
	w.set_loadout(0, W.FRONT_MISSILE, -5, W.MINE, 2)
	assert_eq(w.ammo[0], [0, 2])


func test_individual_loadouts_fire_their_own_weapons() -> void:
	var w := _world(3)
	w.set_loadout(1, W.SUPER_MISSILE, 1, W.REAR_MISSILE, 1)
	var cars := _cars([0, 2000, 4000])
	w.request(0, F, cars)
	w.request(1, F, cars)
	w.request(2, R, cars)
	var types := w.events.filter(func(e: Dictionary) -> bool: return e.kind == "fire").map(func(e: Dictionary) -> int: return e.type)
	assert_eq(types, [W.FRONT_MISSILE, W.SUPER_MISSILE, W.MINE])


func test_rear_missile_destroys_car_behind_not_owner_or_car_ahead() -> void:
	var w := _world(3)
	w.set_loadout(0, W.FRONT_MISSILE, 1, W.REAR_MISSILE, 1)
	var cars := _cars([0, -300, 200])
	assert_true(w.request(0, R, cars))
	assert_eq(w.ammo[0][R], 0)
	var destroyed := _run(w, cars, 1.0)
	assert_eq(destroyed, [1] as Array[int])
	assert_false(w.is_wrecked(0))
	assert_false(w.is_wrecked(2))


func test_homing_missile_turns_onto_an_off_axis_target() -> void:
	var w := _world(2)
	w.set_loadout(0, W.HOMING_MISSILE, 1, W.MINE, 0)
	var cars := _cars([0])
	cars.append({"position": Vector2(350, 140), "heading": 0.0, "present": true})
	assert_true(w.request(0, F, cars))
	assert_eq(w.projectiles[0].target, 1)
	var destroyed := _run(w, cars, 1.5)
	assert_eq(destroyed, [1] as Array[int], "a straight missile would pass 140 px wide")


func test_super_missile_orbits_and_destroys_a_close_car() -> void:
	var w := _world(2)
	w.set_loadout(0, W.SUPER_MISSILE, 1, W.MINE, 0)
	var cars := _cars([0, 0])
	cars[1].position = Vector2(0, _rules.super_orbit_radius)
	assert_true(w.request(0, F, cars))
	var destroyed := _run(w, cars, 1.0)
	assert_eq(destroyed, [1] as Array[int])
	assert_false(w.is_wrecked(0))


## P1: the orbit passing over a car that is already wrecked (or protected after
## its respawn) is not a new hit, so it no longer logs an explosion every tick
## (it logged 35 for this single destruction before). Destruction itself is
## unchanged; with a longer orbit a car still inside it when its wreck time and
## grace have run out is destroyed again, with one more explosion.
func test_super_missile_logs_one_explosion_per_real_hit() -> void:
	for duration in [_rules.super_duration, 7.0]:
		_rules.super_duration = duration
		var w := _world(2)
		w.set_loadout(0, W.SUPER_MISSILE, 1, W.MINE, 0)
		var cars := _cars([0, 0])
		cars[1].position = Vector2(0, _rules.super_orbit_radius)
		assert_true(w.request(0, F, cars))
		var destroyed := _run(w, cars, duration + 0.1)
		var expected := 1 if duration < 6.0 else 2
		assert_eq(destroyed.size(), expected, "destructions over a %.0f s orbit" % duration)
		assert_eq(w.destroyed_count[1], expected)
		var hits := w.events.filter(func(e: Dictionary) -> bool: return e.kind == "explode" and e.car == 1)
		assert_eq(hits.size(), expected, "one explosion per real hit, not one per tick")
		var ends := w.events.filter(func(e: Dictionary) -> bool: return e.kind == "explode" and e.car == -1)
		assert_eq(ends.size(), 1, "the missile's own end")


func test_mine_explodes_after_the_fuse() -> void:
	var w := _world(2)
	var cars := _cars([0, -34])
	assert_true(w.request(0, R, cars))
	assert_eq(_run(w, cars, _rules.mine_fuse - 0.1).size(), 0)
	var destroyed := _run(w, cars, 0.2)
	assert_true(destroyed.has(1))


func test_classic_shared_cooldown_blocks_both_slots() -> void:
	var w := _world(2)
	var cars := _cars([0, 5000])
	assert_true(w.request(0, F, cars))
	assert_false(w.request(0, R, cars), "shared cooldown")
	_run(w, cars, _rules.fire_cooldown + DT)
	assert_true(w.request(0, R, cars))
	assert_almost_eq(w.slot_cooldown_length(F), 0.6, 0.0001)


func test_tactical_front_and_rear_cooldowns_are_independent() -> void:
	var w := _world(2, WeaponRules.Style.TACTICAL)
	w.set_loadout(0, W.FRONT_MISSILE, 5, W.REAR_MISSILE, 5)  # (a stationary car would meet its own mine)
	var cars := _cars([0, 5000])
	assert_eq(_rules.tactical_front_cooldown, 1.5)
	assert_eq(_rules.tactical_rear_cooldown, 3.0)
	assert_true(w.request(0, F, cars))
	assert_false(w.request(0, R, cars), "brief shared lock")
	_run(w, cars, _rules.tactical_shared_lock + DT)
	assert_false(w.can_fire(0, F), "front still cooling down")
	assert_true(w.request(0, R, cars), "rear slot is independent")
	_run(w, cars, 1.5 - _rules.tactical_shared_lock)
	assert_true(w.request(0, F, cars), "front ready after 1.5 s")
	_run(w, cars, _rules.tactical_shared_lock + DT)
	assert_false(w.can_fire(0, R), "rear needs 3 s")
	_run(w, cars, 3.0 - 1.5)
	assert_true(w.can_fire(0, R))


func test_tactical_front_cannot_fire_faster_than_its_cooldown() -> void:
	var w := _world(2, WeaponRules.Style.TACTICAL)
	_rules.front_ammo = 20
	w.reset()
	var cars := _cars([0, 99999])
	var fired := 0
	for i in int(6.0 / DT):
		if w.request(0, F, cars):
			fired += 1
		w.step(DT, cars)
	assert_eq(fired, 4, "t = 0, 1.5, 3.0, 4.5")


func test_tactical_cooldowns_are_configurable() -> void:
	_rules.tactical_front_cooldown = 0.5
	_rules.tactical_rear_cooldown = 1.0
	_rules.tactical_shared_lock = 0.1
	var w := _world(2, WeaponRules.Style.TACTICAL)
	var cars := _cars([0, 99999])
	assert_true(w.request(0, F, cars))
	_run(w, cars, 0.5 + DT)
	assert_true(w.request(0, F, cars))
	assert_almost_eq(w.slot_cooldown_length(R), 1.0, 0.0001)


func test_tactical_empty_click_only_takes_the_shared_lock() -> void:
	var w := _world(2, WeaponRules.Style.TACTICAL)
	w.set_loadout(0, W.FRONT_MISSILE, 0, W.MINE, 1)
	var cars := _cars([0, 99999])
	assert_false(w.request(0, F, cars))
	assert_eq(w.events[-1].kind, "empty")
	_run(w, cars, _rules.tactical_shared_lock + DT)
	assert_true(w.request(0, R, cars))


func test_ai_and_player_follow_the_same_tactical_rules() -> void:
	var w := _world(3, WeaponRules.Style.TACTICAL)
	var cars := _cars([0, 3000, 6000])
	for id in 3:
		assert_true(w.request(id, F, cars))
		assert_almost_eq(w.slot_wait(id, F), 1.5, 0.0001)


func test_classic_snapshot_is_unchanged_without_custom_loadouts() -> void:
	var w := _world(2)
	assert_eq(w.state_snapshot().size(), 6)
	w.style = WeaponRules.Style.TACTICAL
	assert_eq(w.state_snapshot().size(), 7)
