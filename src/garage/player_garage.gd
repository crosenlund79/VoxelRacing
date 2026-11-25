class_name PlayerGarage
extends RefCounted
## The player's money, weapon inventory and car (condition, armour) for the
## garage career, saved to user://garage.cfg after every change when a save
## path is set (the game sets it; tests usually do not). Nothing is saved while
## a race is running: quitting mid-race is the same as leaving the race (no
## prize, no rounds used, no damage), so a save never holds a half-settled race. The single authority for what the
## player owns: the race only receives a copy of the equipped rounds, and the
## rounds left after the race are written back once by settle_race().
## Quick races and spectating never use it.
## Pure logic (no scene access), so it is unit-testable.

const W := WeaponRules.Weapon
const FRONT := 0
const REAR := 1

var rules: GarageRules
var money := 0
## Rounds owned per weapon type (WeaponRules.Weapon -> int).
var stock: Dictionary = {}
## Equipped weapon type per slot: [front, rear] (W.NONE = empty slot).
var equipped: Array[int] = [W.NONE, W.NONE]
## Weapon cycling (2026-11-23): true = the car carries every owned weapon type
## (the equipped one is active, the others are cycled to in the race); false =
## only the equipped types (the simple single-weapon loadout).
var carry_all := true
## Vehicle upgrades (2026-11-23): tier per part (0 = stock .. 3), bought
## once, kept between races and saved; the garage's car setup (whichever car
## the player drives).
var upgrades: Dictionary = {"engine": 0, "brakes": 0, "chassis": 0, "steering": 0}
## Races paid so far, and what the last settled race paid.
var races_settled := 0
var last_position := 0
var last_prize := 0
## Pit speeding fines charged at the last settled race ($).
var last_fine := 0
## M6: the car's condition (0 .. 100 %), carried from race to race, and its
## armour grade (0 = none). Condition before the last race and after it.
var condition := 100.0
var armour := 0
var last_condition_before := 100.0
## Free emergency patch-up given at the start of the last race (points).
var last_patch := 0.0
var _race_pending := false
## Where the career is saved ("" = not saved).
var save_path := ""

const DEFAULT_PATH := "user://garage.cfg"
static var default_path := DEFAULT_PATH


func _init(p_rules: GarageRules) -> void:
	rules = p_rules
	money = rules.start_money
	for w in WeaponRules.ALL_WEAPONS:
		stock[w] = 0
	stock[W.FRONT_MISSILE] = rules.start_front_missiles
	stock[W.MINE] = rules.start_mines
	equipped = [W.FRONT_MISSILE, W.MINE]


func count(w: int) -> int:
	return stock.get(w, 0)


func can_buy(w: int, n: int = 1) -> bool:
	return not _race_pending and stock.has(w) and n > 0 and money >= rules.price(w) * n \
		and count(w) + n <= rules.max_stock


## Buys n rounds; false (nothing changes) when unaffordable or over the cap.
func buy(w: int, n: int = 1) -> bool:
	if not can_buy(w, n):
		return false
	money -= rules.price(w) * n
	stock[w] += n
	save()
	return true


func can_sell(w: int, n: int = 1) -> bool:
	return not _race_pending and stock.has(w) and n > 0 and count(w) >= n


## Sells n rounds at the lower sell price.
func sell(w: int, n: int = 1) -> bool:
	if not can_sell(w, n):
		return false
	money += rules.sell_price(w) * n
	stock[w] -= n
	save()
	return true


## Mounts weapon type w in its slot (W.NONE empties the given slot).
func equip(slot: int, w: int) -> bool:
	if _race_pending or slot < 0 or slot > 1:
		return false
	if w != W.NONE and not WeaponRules.compatible(w, slot):
		return false
	equipped[slot] = w
	save()
	return true


## [front weapon, front rounds, rear weapon, rear rounds] the car carries.
func race_loadout() -> Array:
	return [equipped[FRONT], count(equipped[FRONT]) if equipped[FRONT] != W.NONE else 0,
		equipped[REAR], count(equipped[REAR]) if equipped[REAR] != W.NONE else 0]


## The other owned types the car carries per slot: [{type: rounds}, {type: rounds}]
## (only types with rounds, never the equipped one; empty with carry_all off).
func race_carried() -> Array:
	var out: Array = [{}, {}]
	if not carry_all:
		return out
	for w in WeaponRules.ALL_WEAPONS:
		var slot := WeaponRules.slot_of(w)
		if w != equipped[slot] and count(w) > 0:
			out[slot][w] = count(w)
	return out


func set_carry_all(on: bool) -> bool:
	if _race_pending:
		return false
	carry_all = on
	save()
	return true


# ----------------------------------------------------- upgrades

func upgrade_level(kind: String) -> int:
	return int(upgrades.get(kind, 0))


func next_upgrade_price(kind: String) -> int:
	return rules.upgrade_price(kind, upgrade_level(kind))


func can_buy_upgrade(kind: String) -> bool:
	return not _race_pending and upgrades.has(kind) and upgrade_level(kind) < rules.max_upgrade() \
		and next_upgrade_price(kind) > 0 and money >= next_upgrade_price(kind)


## Buys the next tier of a part: paid once, capped at the best tier.
func buy_upgrade(kind: String) -> bool:
	if not can_buy_upgrade(kind):
		return false
	money -= next_upgrade_price(kind)
	upgrades[kind] = upgrade_level(kind) + 1
	save()
	return true


## The handling this garage's car races with (stock handling `base` + upgrades).
func driving(base: DrivingParams) -> DrivingParams:
	return rules.upgraded(base, upgrades)


# ----------------------------------------------------- condition (M6)

## Points of condition missing.
func damage_points() -> float:
	return maxf(0.0, 100.0 - condition)


## Price of a full repair.
func full_repair_cost() -> int:
	return rules.repair_price(damage_points())


## Repairs `points` of condition (whole points, capped at full); false when
## there is nothing to repair or it is unaffordable.
func can_repair(points: float = 1.0) -> bool:
	return not _race_pending and damage_points() > 0.0 and points > 0.0 \
		and money >= rules.repair_price(minf(points, damage_points()))


func repair(points: float) -> bool:
	points = minf(points, damage_points())
	if not can_repair(points):
		return false
	money -= rules.repair_price(points)
	condition = minf(100.0, condition + ceil(points - 0.0001))
	save()
	return true


## Repairs everything, or as much as the money pays for. Returns points repaired.
func repair_affordable() -> float:
	if _race_pending or damage_points() <= 0.0:
		return 0.0
	var points := minf(ceil(damage_points() - 0.0001), floor(money / float(maxi(1, rules.repair_price_per_point))))
	if points <= 0.0:
		return 0.0
	var before := condition
	repair(points)
	return condition - before


## Condition the car starts the next race with: its own, or the free
## emergency patch-up when it is below the minimum.
func race_condition() -> float:
	return maxf(condition, rules.min_start_condition)


## Damage reduction of the fitted armour.
func armour_reduction() -> float:
	return rules.armour_reduction[clampi(armour, 0, rules.max_armour())]


func armour_name(grade: int = armour) -> String:
	return rules.armour_names[clampi(grade, 0, rules.armour_names.size() - 1)]


## Price of the next armour grade (0 when the best is fitted).
func next_armour_price() -> int:
	return rules.armour_price[armour + 1] if armour < rules.max_armour() else 0


func can_buy_armour() -> bool:
	return not _race_pending and armour < rules.max_armour() and money >= next_armour_price()


func buy_armour() -> bool:
	if not can_buy_armour():
		return false
	money -= next_armour_price()
	armour += 1
	save()
	return true


## A garage race has started: the shop is closed until it is settled. A car
## below the minimum condition gets the free emergency patch-up now.
func begin_race() -> void:
	_race_pending = true
	last_condition_before = condition
	last_patch = maxf(0.0, rules.min_start_condition - condition)
	condition = race_condition()


func race_pending() -> bool:
	return _race_pending


## Pays the prize for the finishing position and keeps the rounds left in the
## equipped weapons. Applies once per begun race; returns the prize, or -1 if
## there was no race to settle (repeat calls change nothing).
## condition_left: the car's condition at the end (%; -1 keeps it unchanged).
## laps: the race length (longer races pay more, GarageRules.prize_for).
## left_by_type: the rounds left of every type carried ({type: rounds}; weapon
## cycling) - when given, it replaces front_left / rear_left.
func settle_race(position: int, front_left: int, rear_left: int, condition_left: float = -1.0, laps: int = 3,
		fine: int = 0, left_by_type: Dictionary = {}) -> int:
	if not _race_pending:
		return -1
	_race_pending = false
	if condition_left >= 0.0:
		condition = clampf(condition_left, 0.0, 100.0)
	if not left_by_type.is_empty():
		for w in left_by_type:  # rounds are only ever used up, never gained
			if stock.has(int(w)):
				stock[int(w)] = clampi(int(left_by_type[w]), 0, count(int(w)))
	else:
		for slot in 2:
			var w := equipped[slot]
			if w != W.NONE:
				var left := front_left if slot == FRONT else rear_left
				stock[w] = clampi(left, 0, count(w))
	last_position = position
	last_prize = rules.prize_for(position, laps)
	last_fine = fine
	money = maxi(0, money + last_prize - fine)  # a pit speeding fine: from the winnings or the balance, never below $0
	races_settled += 1
	save()
	return last_prize


## A begun race that never finished (left before the flag): nothing is paid,
## no rounds are used up and the car is as it was (no patch-up either).
func abandon_race() -> void:
	if _race_pending:
		condition = last_condition_before
	_race_pending = false


## Writes the career (never in the middle of a race).
func save() -> void:
	if save_path == "" or _race_pending:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("garage", "money", money)
	var st := {}
	for w in stock:
		st[str(w)] = stock[w]
	cfg.set_value("garage", "stock", st)
	cfg.set_value("garage", "equipped", [equipped[0], equipped[1]])
	cfg.set_value("garage", "carry_all", carry_all)
	cfg.set_value("garage", "upgrades", upgrades.duplicate())
	cfg.set_value("garage", "condition", condition)
	cfg.set_value("garage", "armour", armour)
	cfg.set_value("garage", "races", races_settled)
	SafeSave.save(cfg, save_path)  # (atomic: never half written)


## The saved career at path, or a fresh one (missing or broken file). Values
## are clamped to what the rules allow, so an edited file cannot break the game.
static func load_or_new(p_rules: GarageRules, path: String = "") -> PlayerGarage:
	var g := PlayerGarage.new(p_rules)
	g.save_path = path if path != "" else default_path
	var cfg := ConfigFile.new()
	if SafeSave.load(cfg, g.save_path) != OK:
		return g
	g.money = maxi(0, int(cfg.get_value("garage", "money", g.money)))
	var st = cfg.get_value("garage", "stock", {})
	if st is Dictionary:
		for w in g.stock:
			g.stock[w] = clampi(int(st.get(str(w), g.stock[w])), 0, p_rules.max_stock)
	var eq = cfg.get_value("garage", "equipped", [])
	if eq is Array and eq.size() == 2:
		for slot in 2:
			var w := int(eq[slot])
			if w == W.NONE or (g.stock.has(w) and WeaponRules.compatible(w, slot)):
				g.equipped[slot] = w
	g.carry_all = bool(cfg.get_value("garage", "carry_all", true))
	var up = cfg.get_value("garage", "upgrades", {})  # (older saves: stock)
	if up is Dictionary:
		for kind in g.upgrades:
			g.upgrades[kind] = clampi(int(up.get(kind, 0)), 0, p_rules.max_upgrade())
	g.condition = clampf(float(cfg.get_value("garage", "condition", 100.0)), 0.0, 100.0)
	g.armour = clampi(int(cfg.get_value("garage", "armour", 0)), 0, p_rules.armour_names.size() - 1)
	g.races_settled = maxi(0, int(cfg.get_value("garage", "races", 0)))
	return g


## Money paid outside a race (a career championship bonus), saved at once.
func add_money(amount: int) -> void:
	money += maxi(0, amount)
	save()


## Starts the career over (starting money and supplies, a repaired car).
func reset() -> void:
	var fresh := PlayerGarage.new(rules)
	money = fresh.money
	stock = fresh.stock
	equipped = fresh.equipped
	carry_all = true
	upgrades = fresh.upgrades
	condition = 100.0
	armour = 0
	races_settled = 0
	last_prize = 0
	last_position = 0
	_race_pending = false
	save()


## Total shop value of everything owned (for display).
func inventory_value() -> int:
	var v := 0
	for w in stock:
		v += rules.price(w) * stock[w]
	return v
