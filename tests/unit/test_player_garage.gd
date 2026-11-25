extends GutTest
## M3.5 Stage 2: the garage economy (money, prices, buying, selling, equipping,
## prize money, ammunition carried between races) and the rival loadouts.

const W := WeaponRules.Weapon

var _rules: GarageRules


func before_each() -> void:
	_rules = load("res://src/garage/default_garage_rules.tres").duplicate()


func _garage() -> PlayerGarage:
	return PlayerGarage.new(_rules)


func test_starting_supplies() -> void:
	var g := _garage()
	assert_eq(g.money, _rules.start_money)
	assert_eq(g.count(W.FRONT_MISSILE), _rules.start_front_missiles)
	assert_eq(g.count(W.MINE), _rules.start_mines)
	assert_eq(g.equipped, [W.FRONT_MISSILE, W.MINE] as Array[int])
	assert_eq(g.race_loadout(), [W.FRONT_MISSILE, 5, W.MINE, 5])
	for w in WeaponRules.ALL_WEAPONS:
		assert_gt(_rules.price(w), 0, "every weapon has a price")
		assert_lt(_rules.sell_price(w), _rules.price(w), "selling pays less")


func test_buy_spends_money_and_adds_rounds() -> void:
	var g := _garage()
	assert_true(g.buy(W.HOMING_MISSILE, 2))
	assert_eq(g.money, _rules.start_money - 2 * _rules.price(W.HOMING_MISSILE))
	assert_eq(g.count(W.HOMING_MISSILE), 2)


func test_cannot_buy_without_money_and_money_never_goes_negative() -> void:
	var g := _garage()
	var n := 0
	while g.buy(W.SUPER_MISSILE):
		n += 1
	assert_eq(n, _rules.start_money / _rules.price(W.SUPER_MISSILE))
	assert_true(g.money >= 0)
	assert_false(g.buy(W.SUPER_MISSILE))
	assert_false(g.buy(W.MINE, 0), "no zero-round purchases")
	assert_false(g.buy(W.MINE, -3), "no negative purchases")
	assert_false(g.buy(W.NONE))


func test_stock_cap() -> void:
	_rules.start_money = 100000
	var g := _garage()
	assert_true(g.buy(W.MINE, _rules.max_stock - _rules.start_mines))
	assert_false(g.buy(W.MINE))
	assert_eq(g.count(W.MINE), _rules.max_stock)


func test_sell_pays_less_and_buy_then_sell_always_loses_money() -> void:
	var g := _garage()
	for w in WeaponRules.ALL_WEAPONS:
		var before := g.money
		if g.buy(w):
			assert_true(g.sell(w))
			assert_lt(g.money, before, WeaponRules.weapon_name(w))
	assert_eq(_rules.sell_price(W.FRONT_MISSILE), _rules.price(W.FRONT_MISSILE) / 2)


func test_cannot_sell_more_than_owned() -> void:
	var g := _garage()
	assert_false(g.sell(W.HOMING_MISSILE))
	assert_false(g.sell(W.MINE, _rules.start_mines + 1))
	assert_true(g.sell(W.MINE, _rules.start_mines))
	assert_eq(g.count(W.MINE), 0)
	assert_eq(g.race_loadout(), [W.FRONT_MISSILE, 5, W.MINE, 0], "still mounted, nothing to fire")


func test_equip_only_compatible_weapons() -> void:
	var g := _garage()
	assert_true(g.equip(PlayerGarage.FRONT, W.HOMING_MISSILE))
	assert_true(g.equip(PlayerGarage.REAR, W.REAR_MISSILE))
	assert_false(g.equip(PlayerGarage.FRONT, W.MINE))
	assert_false(g.equip(PlayerGarage.REAR, W.SUPER_MISSILE))
	assert_eq(g.equipped, [W.HOMING_MISSILE, W.REAR_MISSILE] as Array[int])
	assert_true(g.equip(PlayerGarage.REAR, W.NONE), "a slot may be left empty")
	assert_eq(g.race_loadout(), [W.HOMING_MISSILE, 0, W.NONE, 0])


func test_race_settles_prize_and_ammo_exactly_once() -> void:
	var g := _garage()
	g.begin_race()
	assert_true(g.race_pending())
	assert_false(g.buy(W.MINE), "shop closed during a race")
	assert_false(g.equip(PlayerGarage.FRONT, W.HOMING_MISSILE))
	var prize := g.settle_race(2, 3, 1)
	assert_eq(prize, _rules.prize_for(2))
	assert_eq(g.money, _rules.start_money + _rules.prize_for(2))
	assert_eq(g.count(W.FRONT_MISSILE), 3, "used rounds are gone")
	assert_eq(g.count(W.MINE), 1)
	assert_eq(g.settle_race(1, 99, 99), -1, "a race pays once")
	assert_eq(g.money, _rules.start_money + _rules.prize_for(2))
	assert_eq(g.count(W.FRONT_MISSILE), 3, "no duplication from a repeat settle")
	assert_eq(g.races_settled, 1)
	assert_eq(g.last_position, 2)


func test_settle_without_a_race_does_nothing() -> void:
	var g := _garage()
	assert_eq(g.settle_race(1, 5, 5), -1)
	assert_eq(g.money, _rules.start_money)


func test_settle_cannot_add_rounds() -> void:
	var g := _garage()
	g.begin_race()
	g.settle_race(10, 50, -4)
	assert_eq(g.count(W.FRONT_MISSILE), 5, "never more than were carried")
	assert_eq(g.count(W.MINE), 0, "never negative")


func test_unequipped_rounds_are_not_touched_by_a_race() -> void:
	var g := _garage()
	g.buy(W.HOMING_MISSILE, 2)
	g.begin_race()
	g.settle_race(4, 0, 0)
	assert_eq(g.count(W.HOMING_MISSILE), 2)
	assert_eq(g.count(W.FRONT_MISSILE), 0)


func test_abandoned_race_pays_nothing_and_uses_nothing() -> void:
	var g := _garage()
	g.begin_race()
	g.abandon_race()
	assert_false(g.race_pending())
	assert_eq(g.money, _rules.start_money)
	assert_eq(g.count(W.FRONT_MISSILE), 5)
	assert_true(g.buy(W.MINE), "shop open again")


func test_prize_money_top_five_only() -> void:
	assert_eq(_rules.prize_for(1), 550)
	assert_gt(_rules.prize_for(1), _rules.prize_for(2))
	assert_gt(_rules.prize_for(5), 0)
	assert_eq(_rules.prize_for(6), 0)
	assert_eq(_rules.prize_for(10), 0)
	assert_eq(_rules.prize_for(0), 0)


func test_rival_loadouts_are_valid_bounded_and_equal_in_value() -> void:
	for id in range(1, 10):
		var l := RivalArmoury.loadout(id)
		assert_true(WeaponRules.compatible(l[0], 0), "rival %d front" % id)
		assert_true(WeaponRules.compatible(l[2], 1), "rival %d rear" % id)
		assert_between(l[1], 1, 20)
		assert_between(l[3], 1, 20)
		assert_eq(_rules.loadout_value(l[0], l[1], l[2], l[3]), RivalArmoury.BUDGET, "rival %d value" % id)
	var q := RivalArmoury.QUICK_RACE_PLAYER
	assert_eq(_rules.loadout_value(q[0], q[1], q[2], q[3]), RivalArmoury.BUDGET)
	var used := {}
	for id in range(1, 10):
		used[RivalArmoury.loadout(id)[0]] = true
		used[RivalArmoury.loadout(id)[2]] = true
	assert_eq(used.size(), 5, "all five weapons appear in the field")


## Economy review (2026-11-17, docs/ECONOMY.md): a race's wear (measured mean
## about 55 % per car) costs less to repair than a podium pays, the free
## patch-up keeps a broke car well clear of the critical zone, and the shop
## stays affordable from the starting money.
func test_economy_invariants() -> void:
	var r: GarageRules = load("res://src/garage/default_garage_rules.tres")
	assert_lt(55 * r.repair_price_per_point, r.prize_for(3), "a podium pays a typical race's repairs")
	assert_gt(r.min_start_condition, DamageRules.new().critical_condition, "patched cars start clear of critical")
	assert_lte(100 * r.repair_price_per_point, r.prize_for(1), "a win pays a full rebuild")
	assert_gte(r.start_money, r.price_front_missile * 5, "the starting money buys a few rounds")
	for k in range(1, 5):
		assert_gt(r.prize_for(k), r.prize_for(k + 1), "prizes fall with position")
	assert_eq(r.prize_for(6), 0, "top five only (manual)")


const SAVE := "user://test_run/test_garage_save.cfg"


func _saved() -> PlayerGarage:
	return PlayerGarage.load_or_new(_rules, SAVE)


func test_career_is_saved_and_loaded() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	var g := _saved()
	assert_eq(g.money, _rules.start_money, "no file: a fresh career")
	g.buy(W.HOMING_MISSILE, 2)
	g.equip(0, W.HOMING_MISSILE)
	g.begin_race()
	g.settle_race(2, 1, 3, 61.0)
	var again := _saved()
	assert_eq(again.money, g.money)
	assert_eq(again.count(W.HOMING_MISSILE), 1)
	assert_eq(again.count(W.MINE), 3)
	assert_eq(again.equipped, [W.HOMING_MISSILE, W.MINE] as Array[int])
	assert_almost_eq(again.condition, 61.0, 0.01)
	assert_eq(again.races_settled, 1)


## Quitting mid-race = leaving the race: the save still holds the state
## before it (no prize, no rounds used, no damage), so nothing is duplicated
## or lost by reloading.
func test_a_race_in_progress_is_never_saved() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	var g := _saved()
	g.condition = 20.0
	g.save()
	var money := g.money
	g.begin_race()  # patched up to the minimum for the race
	g.money += 9999  # whatever happens in memory during the race...
	g.save()  # ...is not written while the race runs
	var reloaded := _saved()
	assert_eq(reloaded.money, money)
	assert_eq(reloaded.count(W.FRONT_MISSILE), _rules.start_front_missiles)
	assert_almost_eq(reloaded.condition, 20.0, 0.01, "no free patch-up banked")
	reloaded.begin_race()
	assert_eq(reloaded.settle_race(1, 0, 0), _rules.prize_for(1))
	assert_eq(reloaded.settle_race(1, 0, 0), -1, "settled once")


func test_broken_save_is_clamped_and_reset_starts_over() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("garage", "money", -50)
	cfg.set_value("garage", "stock", {str(W.MINE): 5000})
	cfg.set_value("garage", "equipped", [W.MINE, W.FRONT_MISSILE])  # wrong slots
	cfg.set_value("garage", "armour", 9)
	cfg.save(SAVE)
	var g := _saved()
	assert_eq(g.money, 0)
	assert_eq(g.count(W.MINE), _rules.max_stock)
	assert_eq(g.equipped, [W.FRONT_MISSILE, W.MINE] as Array[int], "invalid slots ignored")
	assert_eq(g.armour, _rules.armour_names.size() - 1)
	g.reset()
	var fresh := _saved()
	assert_eq(fresh.money, _rules.start_money)
	assert_eq(fresh.races_settled, 0)
	assert_eq(fresh.condition, 100.0)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))


## Longer garage races pay more: the same result costs more repairs and
## rounds over 7 / 20 / 50 laps (review 2026-11-17).
func test_prize_scales_with_race_length() -> void:
	assert_eq(_rules.prize_for(1, 3), 550)
	assert_eq(_rules.prize_for(1, 7), 1100)
	assert_eq(_rules.prize_for(3, 20), 900)
	assert_eq(_rules.prize_for(5, 50), 625)
	assert_eq(_rules.prize_for(6, 50), 0, "still the top five only")
	assert_eq(_rules.prize_for(2, 5), _rules.prize_for(2), "other lengths pay x1")
	var g := PlayerGarage.new(_rules)
	g.begin_race()
	assert_eq(g.settle_race(2, 0, 0, -1.0, 7), 800)
