class_name GarageRules
extends Resource
## Prices, prize money and starting supplies for the garage (M3.5 Stage 2).
##
## VERIFIED from the original Super Cars II manual (1991): you start with a set
## amount of money; prize money comes from finishing positions (only the top
## five win money); after a race you buy and sell weapons; you choose FRONT or
## REAR for each, two weapon types per race; selling pays less than the shop
## price; the only limit on how many you buy is your money.
## PROVISIONAL (not in the manual / not implemented): every number below; prices
## are fixed (the original's fluctuating prices are not implemented); a stock
## cap per weapon type guards against runaway numbers.

const W := WeaponRules.Weapon

@export var start_money := 300
## Prize money for finishing 1st, 2nd, ... (positions beyond the list win nothing).
@export var prize_money: Array[int] = [550, 400, 300, 200, 125]  # 2026-11-17 economy review (was 500 / 350 / 250 / 150 / 100)
## Shop price of one round of each weapon.
@export var price_front_missile := 40
@export var price_rear_missile := 40
@export var price_homing_missile := 90
@export var price_super_missile := 150
@export var price_mine := 30
## Selling pays this fraction of the shop price (rounded down, at least 1).
@export_range(0.0, 0.99) var sell_fraction := 0.5
## Most rounds of one weapon type a player can own.
@export var max_stock := 99
## Supplies at the start of a garage session: rounds owned and equipped.
@export var start_front_missiles := 5
@export var start_mines := 5

## M6 repairs and armour (VERIFIED from the manual: repairs and armour are
## bought in the shop between races; armour came in grades). PROVISIONAL numbers.
## Price of one point of condition (a full repair from 0 % costs 100 points).
@export var repair_price_per_point := 2  # was 3 (economy review, docs/ECONOMY.md)
## Emergency patch-up: a car below this condition (%) is always patched up to
## it for free before a garage race, so a player can always race (no dead end).
@export var min_start_condition := 50.0  # was 30 (economy review)
## Armour grades: names, damage reduction and the price of each grade on top
## of the previous one (grade 0 = no armour).
@export var armour_names: PackedStringArray = PackedStringArray(["NONE", "LIGHT", "HEAVY"])
@export var armour_reduction: PackedFloat32Array = PackedFloat32Array([0.0, 0.2, 0.35])
@export var armour_price: PackedInt32Array = PackedInt32Array([0, 250, 400])


## Vehicle upgrades (2026-11-23): three paid tiers above stock per part,
## bought once and kept (the garage's own car setup: whichever car the
## player drives). Each tier is a small, explicit multiplier on the stock
## handling (the environment's handling first, then the upgrade); stock (0)
## changes nothing. Rivals are never upgraded. PROVISIONAL numbers.
const UPGRADES: Array[String] = ["engine", "brakes", "chassis", "steering"]
## Price of tiers 1, 2 and 3 of each part.
@export var upgrade_prices: Dictionary = {"engine": [300, 550, 900], "brakes": [200, 380, 650],
	"chassis": [220, 420, 700], "steering": [200, 380, 650]}
## Engine: acceleration and top speed (+ fraction at tiers 0..3).
@export var engine_acceleration: PackedFloat32Array = PackedFloat32Array([0.0, 0.04, 0.08, 0.12])
@export var engine_top_speed: PackedFloat32Array = PackedFloat32Array([0.0, 0.015, 0.03, 0.045])
## Brakes: braking with Fire held (Fire to Brake) and off the throttle (Fire to Accelerate).
@export var brakes_deceleration: PackedFloat32Array = PackedFloat32Array([0.0, 0.08, 0.16, 0.24])
## Chassis: grip, i.e. resistance to sliding sideways (not armour).
@export var chassis_grip: PackedFloat32Array = PackedFloat32Array([0.0, 0.05, 0.10, 0.15])
## Steering: turning rate.
@export var steering_turn_rate: PackedFloat32Array = PackedFloat32Array([0.0, 0.03, 0.06, 0.09])


func max_upgrade() -> int:
	return 3


## Price of the next tier above `level` (0 when the best is fitted).
func upgrade_price(kind: String, level: int) -> int:
	var prices: Array = upgrade_prices.get(kind, [])
	return int(prices[level]) if level >= 0 and level < mini(prices.size(), max_upgrade()) else 0


## The stock handling `base` with these upgrade levels fitted ({kind: level});
## base itself when everything is stock.
func upgraded(base: DrivingParams, levels: Dictionary) -> DrivingParams:
	var e := clampi(int(levels.get("engine", 0)), 0, max_upgrade())
	var b := clampi(int(levels.get("brakes", 0)), 0, max_upgrade())
	var c := clampi(int(levels.get("chassis", 0)), 0, max_upgrade())
	var s := clampi(int(levels.get("steering", 0)), 0, max_upgrade())
	if e + b + c + s == 0:
		return base
	var p := base.duplicate() as DrivingParams
	p.acceleration = base.acceleration * (1.0 + engine_acceleration[e])
	p.max_speed = base.max_speed * (1.0 + engine_top_speed[e])
	p.brake_deceleration = base.brake_deceleration * (1.0 + brakes_deceleration[b])
	p.release_deceleration = base.release_deceleration * (1.0 + brakes_deceleration[b])
	p.grip = base.grip * (1.0 + chassis_grip[c])
	p.turn_rate_degrees = base.turn_rate_degrees * (1.0 + steering_turn_rate[s])
	return p


## One line on what a tier of a part does ("+8 % acceleration, +3 % top speed").
func upgrade_effect(kind: String, level: int) -> String:
	level = clampi(level, 0, max_upgrade())
	match kind:
		"engine": return "+%d %% acceleration, +%.1f %% top speed" % [roundi(engine_acceleration[level] * 100.0), engine_top_speed[level] * 100.0]
		"brakes": return "+%d %% braking" % roundi(brakes_deceleration[level] * 100.0)
		"chassis": return "+%d %% grip (less sliding)" % roundi(chassis_grip[level] * 100.0)
		"steering": return "+%d %% turning" % roundi(steering_turn_rate[level] * 100.0)
	return ""


static func upgrade_title(kind: String) -> String:
	return kind.to_upper()


func price(w: int) -> int:
	match w:
		W.FRONT_MISSILE: return price_front_missile
		W.REAR_MISSILE: return price_rear_missile
		W.HOMING_MISSILE: return price_homing_missile
		W.SUPER_MISSILE: return price_super_missile
		W.MINE: return price_mine
	return 0


func sell_price(w: int) -> int:
	var p := price(w)
	return 0 if p <= 0 else maxi(1, int(floor(p * sell_fraction)))


## Prize multiplier by race length (laps): a longer race costs more repairs and
## rounds for the same result (2026-11-17 review, docs/ECONOMY.md; 7 laps
## measured, 20 / 50 extrapolated). Lengths not listed pay x1.
@export var prize_scale_by_laps: Dictionary = {3: 1.0, 7: 2.0, 20: 3.0, 50: 5.0}


## Prize for a 1-based finishing position (0 = not classified) in a race of
## this many laps.
func prize_for(position: int, laps: int = 3) -> int:
	if position < 1 or position > prize_money.size():
		return 0
	return int(round(prize_money[position - 1] * float(prize_scale_by_laps.get(laps, 1.0))))


## Price of repairing `points` of condition (whole points; at least 1 per point started).
func repair_price(points: float) -> int:
	return int(ceil(maxf(points, 0.0) - 0.0001)) * repair_price_per_point if points > 0.0 else 0


func max_armour() -> int:
	return armour_reduction.size() - 1


## Shop value of a loadout (used to keep rival loadouts equal in value).
func loadout_value(front_weapon: int, front_ammo: int, rear_weapon: int, rear_ammo: int) -> int:
	return price(front_weapon) * front_ammo + price(rear_weapon) * rear_ammo
