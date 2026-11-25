class_name WeaponRules
extends Resource
## Combat rules shared by every car (player and rivals).
##
## VERIFIED from the original Super Cars II manual (1991): one FRONT and one REAR
## weapon type per race, fired with joystick Forward / Backwards; front missiles
## fly straight ahead until they hit something and can be dodged; rear missiles
## the same, backwards; homing missiles home in on the nearest car; the super
## missile rotates round its car destroying anything that gets too close; mines
## are dropped and explode after a few seconds, destroying anything close.
## Weapons destroy cars ("blast it to pieces").
## PROVISIONAL (not in the manual): every number below, the fixed loadout (the
## original buys it in the shop), and what happens to a destroyed car (user
## decision 2026-11-14: wrecked on the spot, then continues).

enum Weapon { NONE, FRONT_MISSILE, REAR_MISSILE, HOMING_MISSILE, SUPER_MISSILE, MINE }
## Combat style (M3.5). CLASSIC = the M3 rules (one shared cooldown per car).
## TACTICAL = separate front / rear slot cooldowns plus a brief shared firing lock.
enum Style { CLASSIC, TACTICAL }

## The five weapons in shop / display order.
const ALL_WEAPONS: Array[Weapon] = [Weapon.FRONT_MISSILE, Weapon.REAR_MISSILE, Weapon.HOMING_MISSILE,
	Weapon.SUPER_MISSILE, Weapon.MINE]

## Fixed loadout for everyone (user decision: front missiles + rear mines). Ammo PROVISIONAL.
@export var front_weapon: Weapon = Weapon.FRONT_MISSILE
@export var front_ammo := 5
@export var rear_weapon: Weapon = Weapon.MINE
@export var rear_ammo := 5

## Time between shots from the same car (s), Classic style. PROVISIONAL.
@export var fire_cooldown := 0.6
## Tactical style: per-slot cooldowns (s) and the brief shared lock after any
## shot that stops firing both slots at once (s). PROVISIONAL (user-specified 1.5 / 3).
@export var tactical_front_cooldown := 1.5
@export var tactical_rear_cooldown := 3.0
@export var tactical_shared_lock := 0.35
## Missile speed (px/s; cars top out at 420). PROVISIONAL.
@export var missile_speed := 820.0
## Missile flight time before it fizzles (s). PROVISIONAL.
@export var missile_lifetime := 2.4
## Distance from a car's centre at which a missile hits it (px). PROVISIONAL.
@export var hit_radius := 24.0
## Homing missile steering (degrees/s) and how far it looks for its target (px). PROVISIONAL.
@export var homing_turn_rate_degrees := 140.0
@export var homing_range := 900.0
## "A few seconds" before a mine explodes, and its blast radius (px). PROVISIONAL numbers.
@export var mine_fuse := 3.0
@export var mine_blast_radius := 70.0
## Super missile orbit radius (px), how long it orbits (s), and its hit radius (px). PROVISIONAL.
@export var super_orbit_radius := 56.0
@export var super_orbit_speed_degrees := 360.0
@export var super_duration := 5.0
@export var super_hit_radius := 22.0
## A destroyed car stays wrecked this long (s), then continues from where it stopped,
## and cannot be destroyed again for respawn_grace s. PROVISIONAL.
@export var wreck_time := 3.0
@export var respawn_grace := 1.5


## Ammunition per race length (2026-11): the starting rounds are multiplied by
## the factor for the race's laps, so combat lasts in long races (3 laps = the
## standard loadout). Lengths not listed use the nearest shorter one.
@export var ammo_scale_by_laps: Dictionary = {3: 1.0, 7: 2.0, 20: 5.0, 50: 10.0}
## Most rounds of one weapon a car can carry.
const MAX_ROUNDS := 99


func ammo_scale(laps: int) -> float:
	var best := 1.0
	var best_laps := -1
	for l in ammo_scale_by_laps:
		if int(l) <= laps and int(l) > best_laps:
			best_laps = int(l)
			best = float(ammo_scale_by_laps[l])
	return best


func ammo_for(slot: int) -> int:
	return front_ammo if slot == 0 else rear_ammo


func weapon_for(slot: int) -> Weapon:
	return front_weapon if slot == 0 else rear_weapon


## Slot a weapon is mounted in: 0 = front (Forward), 1 = rear (Backwards).
## Front: front, homing and super missiles. Rear: rear missiles and mines.
## The manual lets the player choose FRONT or REAR for each purchase; which
## weapons fit which slot is a HyperCars decision (see the brief).
static func slot_of(w: Weapon) -> int:
	match w:
		Weapon.FRONT_MISSILE, Weapon.HOMING_MISSILE, Weapon.SUPER_MISSILE: return 0
		Weapon.REAR_MISSILE, Weapon.MINE: return 1
	return -1


static func compatible(w: Weapon, slot: int) -> bool:
	return w != Weapon.NONE and slot_of(w) == slot


static func style_name(style: Style) -> String:
	return "TACTICAL" if style == Style.TACTICAL else "CLASSIC"


static func weapon_name(w: Weapon) -> String:
	match w:
		Weapon.FRONT_MISSILE: return "Front missiles"
		Weapon.REAR_MISSILE: return "Rear missiles"
		Weapon.HOMING_MISSILE: return "Homing missiles"
		Weapon.SUPER_MISSILE: return "Super missile"
		Weapon.MINE: return "Mines"
	return "None"
