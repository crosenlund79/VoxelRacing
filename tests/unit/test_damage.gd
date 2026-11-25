extends GutTest
## M6: vehicle condition (DamageRules / DamageWorld), DNF classification in
## RaceSession, and repairs / armour in PlayerGarage.

const W := WeaponRules.Weapon

var _rules: DamageRules


func before_each() -> void:
	_rules = load("res://src/damage/default_damage_rules.tres")


func _world(n := 3) -> DamageWorld:
	return DamageWorld.new(_rules, n)


func test_minor_impacts_cost_nothing_and_severe_ones_are_capped() -> void:
	assert_eq(_rules.wall_damage(60.0), 0.0, "a scrape")
	assert_eq(_rules.wall_damage(_rules.wall_threshold), 0.0)
	assert_almost_eq(_rules.wall_damage(210.0), (210.0 - _rules.wall_threshold) * _rules.wall_damage_per_speed, 0.001)
	assert_eq(_rules.wall_damage(5000.0), _rules.wall_max_damage, "capped")
	assert_eq(_rules.car_damage(90.0), 0.0, "a nudge")
	assert_gt(_rules.car_damage(300.0), _rules.car_damage(200.0), "harder contacts hurt more")
	assert_eq(_rules.car_damage(5000.0), _rules.car_max_damage)


func test_every_weapon_damages_but_one_hit_never_retires_a_healthy_car() -> void:
	for w in WeaponRules.ALL_WEAPONS:
		var d := _world(1)
		assert_false(d.weapon_hit(0, w), "%s alone does not retire" % WeaponRules.weapon_name(w))
		assert_almost_eq(d.condition[0], _rules.max_condition - _rules.weapon_damage(w), 0.001)
		assert_gt(_rules.weapon_damage(w), 0.0)
		assert_lt(_rules.weapon_damage(w), _rules.max_condition * 0.5, "far from a one-shot DNF")


func test_repeated_hits_wear_the_car_down_to_a_dnf() -> void:
	var d := _world(1)
	var hits := 0
	while not d.is_retired(0):
		d.weapon_hit(0, W.MINE)
		hits += 1
	assert_eq(hits, int(ceil(_rules.max_condition / _rules.mine_damage)))
	assert_eq(d.condition[0], 0.0)
	assert_false(d.damage(0, 50.0), "no more damage once out")
	assert_false(d.is_critical(0), "retired, not critical")


func test_critical_threshold() -> void:
	var d := _world(1)
	d.set_start(0, _rules.critical_condition + 1.0, 0.0)
	assert_false(d.is_critical(0))
	d.damage(0, 1.0)
	assert_true(d.is_critical(0))


func test_armour_reduces_damage_without_invulnerability() -> void:
	var plain := _world(1)
	var armoured := _world(1)
	armoured.set_start(0, 100.0, 0.35)
	plain.weapon_hit(0, W.FRONT_MISSILE)
	armoured.weapon_hit(0, W.FRONT_MISSILE)
	assert_almost_eq(100.0 - armoured.condition[0], (100.0 - plain.condition[0]) * 0.65, 0.001)
	var hits := 0
	while not armoured.is_retired(0) and hits < 100:
		armoured.weapon_hit(0, W.FRONT_MISSILE)
		hits += 1
	assert_true(armoured.is_retired(0), "armour delays a DNF, it does not prevent it")
	armoured.set_start(0, 100.0, 5.0)
	assert_lte(armoured.armour[0], 0.95, "reduction is capped below 100 %")


func test_car_contact_hurts_both_once_per_tick() -> void:
	var d := _world(3)
	var amount := _rules.car_damage(320.0)
	d.car_impact(0, 1, 320.0)
	d.car_impact(1, 0, 320.0)  # the other car reporting the same contact
	assert_almost_eq(d.condition[0], 100.0 - amount, 0.001)
	assert_almost_eq(d.condition[1], 100.0 - amount, 0.001)
	assert_eq(d.condition[2], 100.0)
	d.step(1.0 / 60.0)
	d.car_impact(0, 1, 320.0)
	assert_almost_eq(d.condition[0], 100.0 - 2.0 * amount, 0.001, "next tick counts again")
	d.car_impact(0, 2, 320.0, true, false)
	assert_eq(d.condition[2], 100.0, "a car that cannot be hurt (finished) is spared")


func test_reset_restores_everyone() -> void:
	var d := _world(2)
	d.set_start(1, 40.0, 0.2)
	d.damage(1, 60.0)
	assert_true(d.is_retired(1))
	d.reset()
	assert_false(d.is_retired(1))
	assert_eq(d.condition[1], 100.0)
	assert_eq(d.armour[1], 0.0)


# --- DNF in the race session ---

func _session(spectator := false) -> RaceSession:
	var s := RaceSession.new(3, 1, PackedStringArray(["YOU", "A", "B", "C"]))
	s.set_spectator(spectator)
	s.start()
	return s


func _finish(s: RaceSession, id: int) -> void:
	s.checkpoint_reached(1, id)
	s.checkpoint_reached(2, id)
	s.checkpoint_reached(0, id)


func test_retired_cars_rank_behind_running_cars_and_are_classified_last() -> void:
	var s := _session()
	for id in 4:
		s.set_progress(id, 100.0 * (4 - id))
	assert_true(s.retire(1))
	assert_false(s.retire(1), "only once")
	assert_eq(s.standings().map(func(r: RacerState) -> int: return r.id), [0, 2, 3, 1])
	_finish(s, 0)
	assert_eq(s.state, RaceSession.State.FINISHED, "the human finished")
	_finish(s, 3)
	assert_true(s.retire(2))
	assert_eq(s.finish_order, [0, 3, 1, 2] as Array[int], "finishers, then the retired cars by distance covered")
	assert_true(s.racers[1].dnf and s.racers[1].is_finished())
	assert_eq(s.racers[1].finish_time, -1.0)
	assert_eq(s.reversed_grid()[0], 2, "the last-classified car starts in front next race")


func test_human_dnf_ends_the_race_for_the_human() -> void:
	var s := _session()
	assert_true(s.retire(0))
	assert_eq(s.state, RaceSession.State.FINISHED)
	assert_false(s.all_finished(), "the rivals race on")
	assert_eq(s.position_of(0), 4, "behind every running car")
	assert_eq(s.racers[0].finish_position, 0, "not classified until the race is over")
	_finish(s, 1)
	_finish(s, 2)
	_finish(s, 3)
	assert_eq(s.racers[0].finish_position, 4)


func test_spectator_race_ends_when_every_car_has_finished_or_retired() -> void:
	var s := _session(true)
	_finish(s, 1)
	s.retire(2)
	assert_eq(s.state, RaceSession.State.RACING)
	s.retire(3)
	assert_eq(s.state, RaceSession.State.FINISHED)
	assert_eq(s.finish_order.size(), 3)
	assert_false(s.retire(1), "a finished car cannot retire")


# --- garage repairs and armour ---

func _garage() -> PlayerGarage:
	return PlayerGarage.new(load("res://src/garage/default_garage_rules.tres"))


func test_repairs_cost_money_per_point_of_damage() -> void:
	var g := _garage()
	var price := g.rules.repair_price_per_point
	assert_eq(g.full_repair_cost(), 0)
	assert_false(g.can_repair(10.0), "nothing to repair")
	g.condition = 60.0
	assert_eq(g.full_repair_cost(), 40 * price)
	var money := g.money
	assert_true(g.repair(10.0))
	assert_eq(g.condition, 70.0)
	assert_eq(g.money, money - 10 * price)
	assert_true(g.repair(500.0), "capped at full")
	assert_eq(g.condition, 100.0)
	assert_eq(g.money, money - 40 * price)


func test_repair_all_repairs_what_the_money_pays_for() -> void:
	var g := _garage()
	g.condition = 10.0
	g.money = 7 * g.rules.repair_price_per_point + 1
	assert_eq(g.repair_affordable(), 7.0)
	assert_eq(g.condition, 17.0)
	assert_eq(g.money, 1)
	assert_eq(g.repair_affordable(), 0.0)


func test_no_dead_end_a_broke_wreck_can_still_race() -> void:
	var g := _garage()
	g.condition = 0.0
	g.money = 0
	for w in WeaponRules.ALL_WEAPONS:
		while g.can_sell(w):
			g.sell(w)
	g.money = 0
	assert_eq(g.race_condition(), g.rules.min_start_condition, "free emergency patch-up")
	g.begin_race()
	assert_eq(g.condition, g.rules.min_start_condition)
	assert_eq(g.last_patch, g.rules.min_start_condition)
	g.settle_race(1, 0, 0, 55.0)
	assert_eq(g.money, g.rules.prize_for(1), "racing pays again")
	assert_eq(g.condition, 55.0)


func test_damage_carries_over_and_dnf_pays_nothing() -> void:
	var g := _garage()
	g.begin_race()
	assert_false(g.can_repair(1.0), "no repairs while racing")
	assert_false(g.can_buy_armour())
	var money := g.money
	g.settle_race(0, 3, 2, 0.0)
	assert_eq(g.money, money, "DNF: no prize")
	assert_eq(g.condition, 0.0)
	assert_eq(g.count(W.FRONT_MISSILE), 3, "rounds left still kept")
	assert_eq(g.count(W.MINE), 2)


func test_abandoned_race_leaves_the_car_as_it_was() -> void:
	var g := _garage()
	g.condition = 12.0
	g.begin_race()
	assert_eq(g.condition, g.rules.min_start_condition)
	g.abandon_race()
	assert_eq(g.condition, 12.0)


func test_armour_grades_are_bought_in_order() -> void:
	var g := _garage()
	g.money = 1000
	assert_eq(g.armour_reduction(), 0.0)
	assert_eq(g.next_armour_price(), g.rules.armour_price[1])
	assert_true(g.buy_armour())
	assert_eq(g.armour, 1)
	assert_almost_eq(g.armour_reduction(), g.rules.armour_reduction[1], 0.0001)
	assert_eq(g.money, 1000 - g.rules.armour_price[1])
	g.money = g.rules.armour_price[2] - 1
	assert_false(g.buy_armour(), "unaffordable")
	g.money = 5000
	assert_true(g.buy_armour())
	assert_false(g.can_buy_armour(), "best grade fitted")
	assert_eq(g.next_armour_price(), 0)
	assert_lt(g.armour_reduction(), 0.5, "a modest upgrade")
