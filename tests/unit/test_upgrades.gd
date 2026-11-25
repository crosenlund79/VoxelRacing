extends GutTest
## Vehicle upgrades (2026-11-23): Engine, Brakes, Chassis and Steering, three
## paid tiers above stock; explicit modest multipliers on the stock handling;
## paid once, capped, kept between races and saved; old saves load as stock.

var _rules: GarageRules
var _base: DrivingParams


func before_each() -> void:
	_rules = load("res://src/garage/default_garage_rules.tres").duplicate()
	_base = load("res://src/driving/default_driving_params.tres")


func _garage() -> PlayerGarage:
	var g := PlayerGarage.new(_rules)
	g.money = 10000
	return g


func test_stock_changes_nothing() -> void:
	var g := _garage()
	for kind in GarageRules.UPGRADES:
		assert_eq(g.upgrade_level(kind), 0)
	assert_same(g.driving(_base), _base, "stock: the very same handling")


func test_each_tier_is_an_explicit_modest_modifier() -> void:
	var p := _rules.upgraded(_base, {"engine": 3, "brakes": 2, "chassis": 1, "steering": 3})
	assert_almost_eq(p.acceleration, _base.acceleration * 1.12, 0.001, "engine 3: +12 % acceleration")
	assert_almost_eq(p.max_speed, _base.max_speed * 1.045, 0.001, "engine 3: +4.5 % top speed")
	assert_almost_eq(p.brake_deceleration, _base.brake_deceleration * 1.16, 0.001, "brakes 2: Fire to Brake")
	assert_almost_eq(p.release_deceleration, _base.release_deceleration * 1.16, 0.001, "brakes 2: Fire to Accelerate")
	assert_almost_eq(p.grip, _base.grip * 1.05, 0.001, "chassis 1: grip")
	assert_almost_eq(p.turn_rate_degrees, _base.turn_rate_degrees * 1.09, 0.001, "steering 3: turning")
	assert_eq(p.car_restitution, _base.car_restitution, "contacts stay the same for every car")
	assert_eq(p.contact_yaw_factor, _base.contact_yaw_factor)
	assert_eq(_base.acceleration, (load("res://src/driving/default_driving_params.tres") as DrivingParams).acceleration, "the stock resource is untouched")
	for kind in GarageRules.UPGRADES:
		assert_ne(_rules.upgrade_effect(kind, 1), "", "every tier is described")


func test_buying_pays_once_and_stops_at_the_best_tier() -> void:
	var g := _garage()
	var money := g.money
	var paid := 0
	for k in 3:
		paid += g.next_upgrade_price("engine")
		assert_true(g.buy_upgrade("engine"))
	assert_eq(g.upgrade_level("engine"), 3)
	assert_eq(g.money, money - paid, "each tier paid exactly once")
	assert_eq(paid, 300 + 550 + 900)
	assert_false(g.buy_upgrade("engine"), "capped")
	assert_eq(g.money, money - paid)
	assert_false(g.buy_upgrade("turbo"), "no such part")


func test_no_purchase_without_money_or_during_a_race() -> void:
	var g := _garage()
	g.money = 100
	assert_false(g.buy_upgrade("brakes"), "unaffordable")
	assert_eq(g.money, 100)
	g.money = 1000
	g.begin_race()
	assert_false(g.buy_upgrade("brakes"), "the shop is closed during a race")


func test_upgrades_are_saved_and_old_saves_are_stock() -> void:
	var path := "user://test_run/upgrades_%d.cfg" % randi()
	var g := PlayerGarage.load_or_new(_rules, path)
	g.money = 5000
	g.buy_upgrade("chassis")
	g.buy_upgrade("chassis")
	g.buy_upgrade("steering")
	var again := PlayerGarage.load_or_new(_rules, path)
	assert_eq(again.upgrade_level("chassis"), 2)
	assert_eq(again.upgrade_level("steering"), 1)
	assert_eq(again.upgrade_level("engine"), 0)
	var old := ConfigFile.new()  # a garage saved before upgrades existed
	old.set_value("garage", "money", 77)
	old.save(path)
	var legacy := PlayerGarage.load_or_new(_rules, path)
	assert_eq(legacy.money, 77)
	for kind in GarageRules.UPGRADES:
		assert_eq(legacy.upgrade_level(kind), 0, "%s: stock" % kind)
	var edited := ConfigFile.new()
	edited.set_value("garage", "upgrades", {"engine": 9, "brakes": -3})
	edited.save(path)
	var clamped := PlayerGarage.load_or_new(_rules, path)
	assert_eq(clamped.upgrade_level("engine"), 3, "an edited file cannot exceed the best tier")
	assert_eq(clamped.upgrade_level("brakes"), 0)
	SafeSave.remove(path)


func test_a_new_career_starts_stock() -> void:
	var g := _garage()
	g.buy_upgrade("engine")
	g.reset()
	assert_eq(g.upgrade_level("engine"), 0)
