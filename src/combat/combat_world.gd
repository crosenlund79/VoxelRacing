class_name CombatWorld
extends RefCounted
## Deterministic combat simulation: ammunition, cooldowns, missiles, mines,
## the super missile, hits, wrecks and respawns. Pure logic (no physics bodies,
## no randomness), advanced once per fixed physics tick, so fast simulation and
## tests reproduce it exactly. Every car follows exactly the same rules.
## Each car carries its own loadout (one front and one rear weapon type and
## their ammunition); by default everyone gets the WeaponRules loadout (M3).
## Style CLASSIC: one shared cooldown per car (M3). Style TACTICAL: separate
## front / rear slot cooldowns and a brief shared lock after any shot.
## Projectiles explode on a car within hit_radius or at the barrier line.

const FRONT := 0
const REAR := 1
const W := WeaponRules.Weapon

var rules: WeaponRules
var enabled := false
## Battle Royale: rounds are never used up (only the slot cooldowns limit firing).
var unlimited := false
## Battle Royale: is a point inside a wall or obstacle (missiles explode there)?
var blocked: Callable
## Weapons Hot: until the whole starting field has crossed the start line
## nobody can fire (no shot, no ammunition, no cooldown, no event).
var locked := false
var style: WeaponRules.Style = WeaponRules.Style.CLASSIC
var path: ClosedPath
## J4: the track layout when it has road levels (elevation zones); null on a
## flat circuit, where none of the level rules apply. Cars then carry `level`
## (0 ground, 1 bridge), `band` (near a bridge end: on both levels) and
## `index` (their position along the centreline) in their state.
var layout: TrackLayout = null
## (J3) Cars may also carry `air` (flying over a jump): nothing on the ground
## meets them.
var road_half_width := 75.0
## Branches (pit lanes, split sections): the layout whose road edges and
## dividers stop missiles; null = none (then road_half_width / narrow sections).
var branch_layout: TrackLayout = null
## Per car: ammo [front, rear], cooldown, wreck and grace timers, counters.
var ammo: Array = []
var cooldown := PackedFloat32Array()
var wreck_left := PackedFloat32Array()
var grace_left := PackedFloat32Array()
var destroyed_count := PackedInt32Array()
var shots_fired := PackedInt32Array()
## Per car: [front weapon, rear weapon] and the ammunition it started the race with.
var loadout: Array = []
var start_ammo: Array = []
## Per car (Tactical): [front, rear] slot cooldowns. cooldown[] is the shared lock.
var slot_cooldown: Array = []
## Weapon cycling (2026-11-23): per car, per slot, the other weapon types it
## carries and their rounds ({type: rounds}; the active type is not in it).
## Empty for everyone except a garage player who owns several types for a slot.
var carried: Array = []
var _custom_loadouts := false
## Live projectiles: {type, owner, pos, dir, age, target, angle}.
var projectiles: Array = []
## Live mines: {owner, pos, age}.
var mines: Array = []
## Append-only event log for presentation: {kind, type, pos, car, owner}.
## kinds: fire, empty, explode, destroyed, respawn, mine_blast.
var events: Array = []


func _init(p_rules: WeaponRules, car_count: int, p_path: ClosedPath = null, p_road_half_width := 75.0) -> void:
	rules = p_rules
	path = p_path
	road_half_width = p_road_half_width
	cooldown.resize(car_count)
	wreck_left.resize(car_count)
	grace_left.resize(car_count)
	destroyed_count.resize(car_count)
	shots_fired.resize(car_count)
	reset()


## New race: default loadout and full ammunition, no projectiles, nobody wrecked.
## Loadouts for the race (set_loadout) are applied after reset.
func reset() -> void:
	ammo.clear()
	loadout.clear()
	start_ammo.clear()
	slot_cooldown.clear()
	carried.clear()
	_custom_loadouts = false
	for i in cooldown.size():
		ammo.append([rules.ammo_for(FRONT), rules.ammo_for(REAR)])
		loadout.append([rules.weapon_for(FRONT), rules.weapon_for(REAR)])
		start_ammo.append([rules.ammo_for(FRONT), rules.ammo_for(REAR)])
		slot_cooldown.append([0.0, 0.0])
		carried.append([{}, {}])
	cooldown.fill(0.0)
	wreck_left.fill(0.0)
	grace_left.fill(0.0)
	destroyed_count.fill(0)
	shots_fired.fill(0)
	projectiles.clear()
	mines.clear()
	events.clear()
	locked = false


func car_count() -> int:
	return cooldown.size()


func is_wrecked(id: int) -> bool:
	return wreck_left[id] > 0.0


## Sets one car's weapons and ammunition for this race (before the start).
## A weapon that does not fit its slot is not mounted.
func set_loadout(id: int, front_weapon: int, front_ammo: int, rear_weapon: int, rear_ammo: int) -> void:
	var f: int = front_weapon if WeaponRules.compatible(front_weapon, FRONT) else W.NONE
	var r: int = rear_weapon if WeaponRules.compatible(rear_weapon, REAR) else W.NONE
	var fa := maxi(0, front_ammo) if f != W.NONE else 0
	var ra := maxi(0, rear_ammo) if r != W.NONE else 0
	loadout[id] = [f, r]
	ammo[id] = [fa, ra]
	start_ammo[id] = [fa, ra]
	_custom_loadouts = true


## Weapon cycling: the other types this car carries for a slot, with their
## rounds (types that do not fit the slot, or the active one, are ignored).
## Set after set_loadout; never scaled with the race length.
func set_carried(id: int, slot: int, rounds_by_type: Dictionary) -> void:
	var d := {}
	for w in rounds_by_type:
		if WeaponRules.compatible(int(w), slot) and int(w) != weapon_of(id, slot):
			d[int(w)] = maxi(0, int(rounds_by_type[w]))
	carried[id][slot] = d


## Every type the car carries for a slot in shop order: [[type, rounds, active], ...].
func slot_types(id: int, slot: int) -> Array:
	var out: Array = []
	for w in WeaponRules.ALL_WEAPONS:
		if w == weapon_of(id, slot):
			out.append([w, ammo[id][slot], true])
		elif carried[id][slot].has(w):
			out.append([w, carried[id][slot][w], false])
	return out


## Rounds left of every type the car carries (active and carried), {type: rounds}.
func rounds_by_type(id: int) -> Dictionary:
	var out := {}
	for slot in 2:
		for t in slot_types(id, slot):
			out[t[0]] = t[1]
	return out


## Switches a slot to the next carried type that still has rounds (shop order,
## wrapping). Cooldowns and the shared lock are untouched, nothing is fired and
## no round is used. Returns false when there is nothing to switch to.
func cycle(id: int, slot: int) -> bool:
	if not enabled or carried[id][slot].is_empty():
		return false
	var types := slot_types(id, slot)
	var at := -1  # (an empty slot starts from the first carried type)
	for i in types.size():
		if types[i][2]:
			at = i
	for k in range(1, types.size() + 1):
		var t: Array = types[(at + k) % types.size()]
		if not t[2] and t[1] > 0:
			var old: int = weapon_of(id, slot)
			if old != W.NONE:
				carried[id][slot][old] = ammo[id][slot]
			carried[id][slot].erase(t[0])
			loadout[id][slot] = t[0]
			ammo[id][slot] = t[1]
			events.append({"kind": "switch", "type": t[0], "pos": Vector2.ZERO, "car": id, "owner": id})
			return true
	return false


## Long races: every listed car's starting rounds times factor (rounded up,
## at most WeaponRules.MAX_ROUNDS).
func scale_ammo(factor: float, ids: Array) -> void:
	if factor == 1.0:
		return
	for id in ids:
		for slot in 2:
			var n := mini(WeaponRules.MAX_ROUNDS, int(ceil(ammo[id][slot] * factor - 0.0001)))
			ammo[id][slot] = n
			start_ammo[id][slot] = n


func weapon_of(id: int, slot: int) -> int:
	return loadout[id][slot]


func can_fire(id: int, slot: int) -> bool:
	return enabled and not locked and not is_wrecked(id) and cooldown[id] <= 0.0 and ammo[id][slot] > 0 \
		and weapon_of(id, slot) != W.NONE \
		and (style == WeaponRules.Style.CLASSIC or slot_cooldown[id][slot] <= 0.0)


## Seconds until this slot can fire again (the longer of the slot cooldown and the shared lock).
func slot_wait(id: int, slot: int) -> float:
	if style == WeaponRules.Style.CLASSIC:
		return cooldown[id]
	return maxf(cooldown[id], slot_cooldown[id][slot])


## Full length of this slot's cooldown (for HUD bars).
func slot_cooldown_length(slot: int) -> float:
	if style == WeaponRules.Style.CLASSIC:
		return rules.fire_cooldown
	return rules.tactical_front_cooldown if slot == FRONT else rules.tactical_rear_cooldown


## Fire request from a car (player key or AI decision). cars: see step().
## Returns true when a weapon was launched.
func request(id: int, slot: int, cars: Array) -> bool:
	if not enabled or locked or is_wrecked(id) or cooldown[id] > 0.0:
		return false
	var tactical := style == WeaponRules.Style.TACTICAL
	if tactical and slot_cooldown[id][slot] > 0.0:
		return false
	var weapon: int = weapon_of(id, slot)
	if weapon == W.NONE:
		return false
	if ammo[id][slot] <= 0:
		events.append({"kind": "empty", "type": weapon, "pos": cars[id].position, "car": id, "owner": id})
		cooldown[id] = rules.tactical_shared_lock if tactical else rules.fire_cooldown
		return false
	if not unlimited:
		ammo[id][slot] -= 1
	if tactical:
		cooldown[id] = rules.tactical_shared_lock
		slot_cooldown[id][slot] = rules.tactical_front_cooldown if slot == FRONT else rules.tactical_rear_cooldown
	else:
		cooldown[id] = rules.fire_cooldown
	shots_fired[id] += 1
	var c: Dictionary = cars[id]
	var fwd := Vector2.from_angle(c.heading)
	match weapon:
		W.FRONT_MISSILE, W.HOMING_MISSILE:
			var p := {"type": weapon, "owner": id, "pos": c.position + fwd * 36.0 * Car.SIZE, "dir": fwd, "age": 0.0, "target": -1}
			_launch_level(p, c)
			if weapon == W.HOMING_MISSILE:
				p.target = nearest_car(id, cars)
			projectiles.append(p)
		W.REAR_MISSILE:
			var p := {"type": weapon, "owner": id, "pos": c.position - fwd * 36.0 * Car.SIZE, "dir": -fwd, "age": 0.0, "target": -1}
			_launch_level(p, c)
			projectiles.append(p)
		W.SUPER_MISSILE:
			var p := {"type": weapon, "owner": id, "pos": c.position + fwd * rules.super_orbit_radius,
				"dir": fwd, "age": 0.0, "target": -1, "angle": c.heading}
			_launch_level(p, c)
			projectiles.append(p)
		W.MINE:
			var m := {"owner": id, "pos": c.position - fwd * 34.0 * Car.SIZE, "age": 0.0}
			if layout != null:  # a mine stays on the road level where it was dropped
				m.level = c.get("level", 0)
				m.band = c.get("band", false)
			mines.append(m)
	events.append({"kind": "fire", "type": weapon, "pos": c.position, "car": id, "owner": id})
	return true


## Nearest other car that is not wrecked (-1 if none within homing_range).
func nearest_car(id: int, cars: Array) -> int:
	var best := -1
	var best_d := rules.homing_range
	for j in cars.size():
		if j == id or is_wrecked(j) or not cars[j].present:
			continue
		if layout != null and not _meets(cars[id], cars[j]):
			continue  # never locks onto a car on the other road level
		var d: float = cars[id].position.distance_to(cars[j].position)
		if d < best_d:
			best_d = d
			best = j
	return best


## Advances one tick. cars[i] = {position, heading, present}. present = false for
## cars not in the race (e.g. the player when spectating).
## Returns {destroyed: [ids], respawned: [ids]}.
func step(dt: float, cars: Array) -> Dictionary:
	var destroyed: Array[int] = []
	var respawned: Array[int] = []
	if not enabled:
		return {"destroyed": destroyed, "respawned": respawned}
	for i in cooldown.size():
		cooldown[i] = maxf(0.0, cooldown[i] - dt)
		if style == WeaponRules.Style.TACTICAL:
			slot_cooldown[i][FRONT] = maxf(0.0, slot_cooldown[i][FRONT] - dt)
			slot_cooldown[i][REAR] = maxf(0.0, slot_cooldown[i][REAR] - dt)
		grace_left[i] = maxf(0.0, grace_left[i] - dt)
		if wreck_left[i] > 0.0:
			wreck_left[i] = maxf(0.0, wreck_left[i] - dt)
			if wreck_left[i] <= 0.0:
				grace_left[i] = rules.respawn_grace
				respawned.append(i)
				events.append({"kind": "respawn", "type": W.NONE, "pos": cars[i].position, "car": i, "owner": i})
	var alive: Array = []
	for p in projectiles:
		p.age += dt
		var keep := true
		match p.type:
			W.SUPER_MISSILE:
				var owner_car: Dictionary = cars[p.owner]
				if layout != null:  # orbits on its owner's road level (in the air too)
					p.level = owner_car.get("level", 0)
					p.band = owner_car.get("band", false)
					p.air = owner_car.get("air", false)
				p.angle += deg_to_rad(rules.super_orbit_speed_degrees) * dt
				p.pos = owner_car.position + Vector2.from_angle(p.angle) * rules.super_orbit_radius
				if p.age >= rules.super_duration or is_wrecked(p.owner):
					keep = false
					events.append({"kind": "explode", "type": p.type, "pos": p.pos, "car": -1, "owner": p.owner})
				else:
					for j in cars.size():
						# a car already wrecked or protected after its respawn cannot be
						# destroyed again (_destroy ignores it), so the orbit passing over it
						# is not a new hit: no repeated explosion event every tick
						if j != p.owner and cars[j].present and not is_wrecked(j) and grace_left[j] <= 0.0 \
								and p.pos.distance_to(cars[j].position) < rules.super_hit_radius * Car.SIZE \
								and (layout == null or _meets(p, cars[j])):
							_hit(j, p, destroyed)
			_:
				if p.type == W.HOMING_MISSILE and p.target >= 0 and not is_wrecked(p.target):
					var want: Vector2 = (cars[p.target].position - p.pos).normalized()
					var turn := clampf(p.dir.angle_to(want), -deg_to_rad(rules.homing_turn_rate_degrees) * dt,
						deg_to_rad(rules.homing_turn_rate_degrees) * dt)
					p.dir = p.dir.rotated(turn)
				p.pos += p.dir * rules.missile_speed * dt
				if layout != null:
					_follow_level(p)
				if p.age >= rules.missile_lifetime:
					keep = false
					events.append({"kind": "explode", "type": p.type, "pos": p.pos, "car": -1, "owner": p.owner})
				else:
					var hit := _car_at(p.pos, rules.hit_radius * Car.SIZE, cars, p.owner if p.age < 0.25 else -1, p)
					if hit >= 0:
						keep = false
						_hit(hit, p, destroyed)
					elif _outside_road(p):
						keep = false
						events.append({"kind": "explode", "type": p.type, "pos": p.pos, "car": -1, "owner": p.owner})
		if keep:
			alive.append(p)
	projectiles = alive
	var live_mines: Array = []
	for m in mines:
		m.age += dt
		if m.age >= rules.mine_fuse:
			events.append({"kind": "mine_blast", "type": W.MINE, "pos": m.pos, "car": -1, "owner": m.owner})
			for j in cars.size():
				if cars[j].present and m.pos.distance_to(cars[j].position) <= rules.mine_blast_radius \
						and (layout == null or _meets(m, cars[j])):
					_destroy(j, m.owner, m.pos, W.MINE, destroyed)
		else:
			live_mines.append(m)
	mines = live_mines
	return {"destroyed": destroyed, "respawned": respawned}


func _hit(car: int, p: Dictionary, destroyed: Array[int]) -> void:
	events.append({"kind": "explode", "type": p.type, "pos": p.pos, "car": car, "owner": p.owner})
	_destroy(car, p.owner, p.pos, p.type, destroyed)


func _destroy(car: int, owner: int, pos: Vector2, type: int, destroyed: Array[int]) -> void:
	if is_wrecked(car) or grace_left[car] > 0.0:
		return
	wreck_left[car] = rules.wreck_time
	destroyed_count[car] += 1
	destroyed.append(car)
	events.append({"kind": "destroyed", "type": type, "pos": pos, "car": car, "owner": owner})


func _car_at(pos: Vector2, radius: float, cars: Array, ignore: int, item: Dictionary = {}) -> int:
	var best := -1
	var best_d := radius
	for j in cars.size():
		if j == ignore or not cars[j].present:
			continue
		if layout != null and not _meets(item, cars[j]):
			continue  # passes over / under a car on the other road level
		var d: float = pos.distance_to(cars[j].position)
		if d < best_d:
			best_d = d
			best = j
	return best


func _outside_road(p: Dictionary) -> bool:
	if blocked.is_valid():
		return blocked.call(p.pos)  # Battle Royale: arena walls and obstacles stop missiles
	if path == null:
		return false
	var proj := path.project(p.pos, p.get("hint", -1))
	p["hint"] = proj.index
	if branch_layout != null:  # widened road, solid dividers (and narrow sections)
		return branch_layout.road_blocked(proj.distance, path.length, proj.lateral)
	if layout != null and not layout.narrow_sections.is_empty():
		return absf(proj.lateral) > layout.half_width_at(proj.distance, path.length)  # narrow sections
	return absf(proj.lateral) > road_half_width


## J4: can two things at these road levels touch? Things near a bridge end
## (band) belong to both levels; otherwise the levels must match.
static func levels_meet(level_a: int, band_a: bool, level_b: int, band_b: bool) -> bool:
	return band_a or band_b or level_a == level_b


func _meets(a: Dictionary, b: Dictionary) -> bool:
	if a.get("air", false) != b.get("air", false):
		return false  # J3: a car in the air is out of reach of ground weapons (and the reverse)
	return levels_meet(a.get("level", 0), a.get("band", false), b.get("level", 0), b.get("band", false))


## A new projectile starts on its shooter's branch and level; a super missile
## follows its owner (updated each tick).
func _launch_level(p: Dictionary, shooter: Dictionary) -> void:
	if layout == null:
		return
	p.level = shooter.get("level", 0)
	p.band = shooter.get("band", false)
	if p.type == W.SUPER_MISSILE:
		p.air = shooter.get("air", false)
	else:
		p.hint = shooter.get("index", -1)
		_follow_level(p)


## A flying missile's level from where it is along its own branch of the road
## (projection near its previous point, so it never jumps to the other road at
## the crossing): it leaves the bridge where the bridge ends.
func _follow_level(p: Dictionary) -> void:
	var proj := path.project(p.pos, p.get("hint", -1))
	p.hint = proj.index
	p.level = layout.level_at(proj.distance, path.length)
	p.band = layout.in_transition(proj.distance, path.length)


## Weapons Hot: the starting field is through, weapons are live for everyone
## (logged once as an "unlock" event, so presentation and the network client
## see the exact moment).
func unlock() -> void:
	if not locked:
		return
	locked = false
	events.append({"kind": "unlock", "type": W.NONE, "pos": Vector2.ZERO, "car": -1, "owner": -1})


## Exact combat state for determinism checks.
func state_snapshot() -> Array:
	var out := [ammo, cooldown, wreck_left, grace_left, destroyed_count, shots_fired]
	if style != WeaponRules.Style.CLASSIC or _custom_loadouts:
		out.append([style, loadout, slot_cooldown])
	for p in projectiles:
		out.append([p.type, p.owner, p.pos, p.dir, p.age])
	for m in mines:
		out.append([m.owner, m.pos, m.age])
	return out
