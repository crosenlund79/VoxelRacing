class_name RivalArmoury
extends RefCounted
## Fixed Tactical-combat loadouts (M3.5): each rival carries one front and one
## rear weapon type chosen to suit their personality. No AI shop or economy.
## Every loadout costs the same at garage prices (BUDGET), so nobody gets more
## firepower than anyone else; only the mix differs. Classic combat keeps the
## M3 loadout (front missiles + mines) for everyone.
## The player's Tactical quick-race loadout has the same value.

const W := WeaponRules.Weapon
## Shop value of every Tactical loadout at the default garage prices.
const BUDGET := 600

## racer id -> [front weapon, rounds, rear weapon, rounds]
const LOADOUTS := {
	1: [W.FRONT_MISSILE, 9, W.REAR_MISSILE, 6],   # Victor: precise straight shots, measured rear cover
	2: [W.FRONT_MISSILE, 12, W.MINE, 4],          # Rocco: lots of missiles to spray
	3: [W.HOMING_MISSILE, 4, W.MINE, 8],          # Ellie: forgiving homing missiles
	4: [W.FRONT_MISSILE, 6, W.REAR_MISSILE, 9],   # Hank: rear-heavy, punishes whoever is behind
	5: [W.HOMING_MISSILE, 4, W.REAR_MISSILE, 6],  # Maya: picks off targets of opportunity
	6: [W.SUPER_MISSILE, 2, W.MINE, 10],          # Dante: the showy super missile
	7: [W.FRONT_MISSILE, 9, W.MINE, 8],           # Greta: efficient standard kit
	8: [W.SUPER_MISSILE, 3, W.MINE, 5],           # Finn: all-or-nothing
	9: [W.HOMING_MISSILE, 6, W.MINE, 2],          # Nina: few, high-confidence homing shots
}
## The player's loadout in Tactical quick races (same value as the rivals').
const QUICK_RACE_PLAYER := [W.FRONT_MISSILE, 9, W.MINE, 8]


static func loadout(racer_id: int) -> Array:
	return LOADOUTS.get(racer_id, QUICK_RACE_PLAYER)
