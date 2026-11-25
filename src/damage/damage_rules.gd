class_name DamageRules
extends Resource
## M6: vehicle condition and how it wears down. Every number is PROVISIONAL and
## tunable here (default_damage_rules.tres); none is buried in gameplay code.
##
## Super Cars II had lasting car damage repaired in the shop between races and
## armour to reduce it (manual: Armour, 3 grades; repairs). The exact original
## numbers are not known; these are HyperCars values, calibrated against
## measured impacts in AI races (barrier impacts rarely exceed 150 px/s, car
## contacts reach 400+ px/s when ramming a wreck).
## Condition does not change handling: the approved driving physics stay as
## they are; at zero condition the car is out of the race (DNF).

## Full condition (100 = 100 %).
@export var max_condition := 100.0
## Condition lost when a weapon destroys the car (on top of the wreck and
## respawn, which are unchanged). A single hit never retires a healthy car.
@export var front_missile_damage := 12.0
@export var rear_missile_damage := 12.0
@export var homing_missile_damage := 12.0
@export var super_missile_damage := 16.0
@export var mine_damage := 14.0
## Barrier impacts: speed into the barrier (px/s) below the threshold is a
## scrape and costs nothing; above it, damage = (speed - threshold) * factor,
## at most wall_max_damage per impact.
@export var wall_threshold := 110.0
@export var wall_damage_per_speed := 0.05
@export var wall_max_damage := 12.0
## Car-to-car contacts: closing speed (px/s) above the threshold damages BOTH
## cars by (speed - threshold) * factor, at most car_max_damage each. One
## contact between a pair counts once per tick.
@export var car_threshold := 120.0
@export var car_damage_per_speed := 0.02
@export var car_max_damage := 8.0
## J3: dropping into a jump's gap.
@export var jump_fall_damage := 10.0
## At or below this condition the HUD warns that the car is critical.
@export var critical_condition := 25.0
## A retired car (DNF) stays on the road as a smoking wreck this long (s),
## passable, before it is taken off the track.
@export var retired_show_time := 3.0


func weapon_damage(weapon: int) -> float:
	match weapon:
		WeaponRules.Weapon.FRONT_MISSILE: return front_missile_damage
		WeaponRules.Weapon.REAR_MISSILE: return rear_missile_damage
		WeaponRules.Weapon.HOMING_MISSILE: return homing_missile_damage
		WeaponRules.Weapon.SUPER_MISSILE: return super_missile_damage
		WeaponRules.Weapon.MINE: return mine_damage
	return 0.0


## Damage from a barrier impact at this speed (before armour).
func wall_damage(speed: float) -> float:
	return clampf((speed - wall_threshold) * wall_damage_per_speed, 0.0, wall_max_damage)


## Damage to each car from a contact at this closing speed (before armour).
func car_damage(speed: float) -> float:
	return clampf((speed - car_threshold) * car_damage_per_speed, 0.0, car_max_damage)
