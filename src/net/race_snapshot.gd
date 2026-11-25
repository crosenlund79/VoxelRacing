class_name RaceSnapshot
extends RefCounted
## Authoritative race state the host sends to the client (M5.1): every car's
## pose, motion and presence, each racer's laps / progress / finish, the race
## clock and state, and (with weapons) the combat state. M6: each car's
## condition and each racer's DNF. J5: the jump state of the cars that are
## flying or down in a gap (nothing for cars on the road). Plain arrays only, so
## var_to_bytes encodes them compactly and safely. Pure functions: capture on
## the host, apply on the client.

const CAR_FIELDS := 7     # x, y, heading, vx, vy, present, condition
const RACER_FIELDS := 7   # laps, next checkpoint, progress, finish position, finish time, lap start, dnf
const JUMP_FIELDS := 5    # car id, seconds in the air (-1 on the ground), lift, jump index, seconds left down
## Snapshot layout: [tick, state, elapsed, cars, racers, finish order, combat ([] = no weapons), jumps,
## pit state per car (PitWorld.pack; empty without pit lanes)].
const SIZE := 9


static func capture(race: Node, tick: int) -> Array:
	var cars := PackedFloat32Array()
	var damage: DamageWorld = race.damage
	for c: Car in race.cars:
		cars.append_array([c.global_position.x, c.global_position.y, c.model.heading,
			c.model.velocity.x, c.model.velocity.y, 1.0 if c.visible else 0.0, damage.condition[c.racer_id]])
	var session: RaceSession = race.session
	var racers := PackedFloat32Array()
	for r in session.racers:
		racers.append_array([r.tracker.laps_completed, r.tracker.next_checkpoint, r.progress,
			r.finish_position, r.finish_time, r.lap_start, 1.0 if r.dnf else 0.0])
	var snap := [tick, session.state, session.elapsed, cars, racers, PackedInt32Array(session.finish_order)]
	var combat: CombatWorld = race.combat
	snap.append(capture_combat(combat) if combat.enabled else [])
	snap.append(capture_jumps(race.jumps))
	snap.append(PackedInt32Array(race.pit_state) if race.pits != null else PackedInt32Array())
	return snap


## Only the cars that are not simply on the road (flying, down in a gap).
static func capture_jumps(jumps: JumpWorld) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if jumps == null:
		return out
	for i in jumps.airborne.size():
		if jumps.airborne[i] == 1 or jumps.down_left[i] > 0.0:
			out.append_array([i, jumps.air_time[i] if jumps.airborne[i] == 1 else -1.0, jumps.lift[i],
				jumps.jump_of[i], jumps.down_left[i]])
	return out


## Car c's jump state in a snapshot: {air, air_time, lift, jump, down} (on the road when absent).
static func jump_state(snap: Array, c: int) -> Dictionary:
	var a: PackedFloat32Array = snap[7]
	for k in range(0, a.size(), JUMP_FIELDS):
		if int(a[k]) == c:
			return {"air": a[k + 1] >= 0.0, "air_time": maxf(0.0, a[k + 1]), "lift": a[k + 2], "jump": int(a[k + 3]),
				"down": a[k + 4]}
	return {"air": false, "air_time": 0.0, "lift": 0.0, "jump": -1, "down": 0.0}


## 0 on the road, 1 flying, 2 down in a gap.
static func jump_phase(state: Dictionary) -> int:
	return 1 if state.air else (2 if state.down > 0.0 else 0)


## Sets car c's jump state on this computer (air_time advanced by `ahead` seconds).
static func set_jump(jumps: JumpWorld, c: int, state: Dictionary, ahead: float = 0.0) -> void:
	jumps.airborne[c] = 1 if state.air else 0
	jumps.air_time[c] = state.air_time + ahead if state.air else 0.0
	jumps.lift[c] = state.lift
	jumps.down_left[c] = maxf(0.0, state.down - ahead) if state.down > 0.0 else 0.0
	jumps.jump_of[c] = state.jump if state.air or state.down > 0.0 else -1


static func capture_combat(combat: CombatWorld) -> Array:
	var ammo := PackedByteArray()  # rounds (max 99) and weapon types fit in a byte
	var timers := PackedFloat32Array()
	for i in combat.car_count():
		ammo.append_array([clampi(combat.ammo[i][0], 0, 255), clampi(combat.ammo[i][1], 0, 255), combat.loadout[i][0], combat.loadout[i][1]])
		timers.append_array([combat.cooldown[i], combat.wreck_left[i], combat.grace_left[i],
			combat.slot_cooldown[i][0], combat.slot_cooldown[i][1]])
	var shots := PackedFloat32Array()
	for p in combat.projectiles:
		shots.append_array([p.type, p.owner, p.pos.x, p.pos.y, p.dir.x, p.dir.y, p.get("angle", 0.0), p.age])
	var mines := PackedFloat32Array()
	for m in combat.mines:
		mines.append_array([m.owner, m.pos.x, m.pos.y, m.age])
	return [ammo, timers, shots, mines, 1 if combat.locked else 0]


static func encode(snap: Array) -> PackedByteArray:
	return var_to_bytes(snap)


## Empty when the bytes are not an encoded array (checked before decoding).
static func decode(bytes: PackedByteArray) -> Array:
	if bytes.size() < 8 or (bytes.decode_u32(0) & 0xFF) != TYPE_ARRAY:
		return []
	var v: Variant = bytes_to_var(bytes)
	return v if v is Array else []


## Structure check before a received snapshot is used.
static func is_valid(snap: Array, car_count: int, racer_count: int) -> bool:
	if snap.size() != SIZE:
		return false
	if typeof(snap[0]) != TYPE_INT or typeof(snap[1]) != TYPE_INT or snap[1] < 0 or snap[1] > 2:
		return false
	if not snap[3] is PackedFloat32Array or snap[3].size() != car_count * CAR_FIELDS:
		return false
	if not snap[4] is PackedFloat32Array or snap[4].size() != racer_count * RACER_FIELDS:
		return false
	if not snap[5] is PackedInt32Array:
		return false
	if not snap[6] is Array or not snap[7] is PackedFloat32Array or snap[7].size() % JUMP_FIELDS != 0:
		return false
	if not snap[8] is PackedInt32Array or (snap[8].size() != 0 and snap[8].size() != car_count):
		return false
	for k in range(0, snap[7].size(), JUMP_FIELDS):
		var id := int(snap[7][k])
		var j := int(snap[7][k + 3])
		if id < 0 or id >= car_count or j < -1 or j > 8:
			return false
	return true


static func tick_of(snap: Array) -> int:
	return snap[0]


## Car c's [position, heading, velocity, present] in a snapshot.
static func car_state(snap: Array, c: int) -> Dictionary:
	var a: PackedFloat32Array = snap[3]
	var k := c * CAR_FIELDS
	return {"position": Vector2(a[k], a[k + 1]), "heading": a[k + 2], "velocity": Vector2(a[k + 3], a[k + 4]),
		"present": a[k + 5] > 0.5}


## Applies the race state except car poses and combat (those follow the
## client's interpolated moment; see NetRace).
static func apply_race(race: Node, snap: Array) -> void:
	var session: RaceSession = race.session
	session.state = snap[1]
	session.elapsed = snap[2]
	var racers: PackedFloat32Array = snap[4]
	for i in session.racers.size():
		var r := session.racers[i]
		var k := i * RACER_FIELDS
		if k + RACER_FIELDS > racers.size():
			break
		r.tracker.laps_completed = int(racers[k])
		r.tracker.next_checkpoint = int(racers[k + 1])
		r.progress = racers[k + 2]
		r.finish_position = int(racers[k + 3])
		r.finish_time = racers[k + 4]
		r.lap_start = racers[k + 5]
		r.dnf = racers[k + 6] > 0.5
	var damage: DamageWorld = race.damage
	var cars: PackedFloat32Array = snap[3]
	for c in damage.car_count():
		var k := c * CAR_FIELDS + 6
		if k >= cars.size():
			break
		var cond := clampf(cars[k], 0.0, damage.rules.max_condition)
		if cond < damage.condition[c] - 0.01:
			damage.since_hit[c] = 0.0  # hit flash on this computer too
		damage.condition[c] = cond
		damage.retired[c] = 1 if cond <= 0.0 else 0
	var order: Array[int] = []
	for id in snap[5]:
		order.append(id)
	session.finish_order = order
	race.pit_state = PackedInt32Array(snap[8])  # the host's pit state (HUD, the client's own limiter)


static func apply_combat(combat: CombatWorld, c: Array) -> void:
	var ammo: PackedByteArray = c[0]
	var timers: PackedFloat32Array = c[1]
	for i in combat.car_count():
		combat.ammo[i] = [ammo[i * 4], ammo[i * 4 + 1]]
		combat.loadout[i] = [ammo[i * 4 + 2], ammo[i * 4 + 3]]
		combat.cooldown[i] = timers[i * 5]
		combat.wreck_left[i] = timers[i * 5 + 1]
		combat.grace_left[i] = timers[i * 5 + 2]
		combat.slot_cooldown[i] = [timers[i * 5 + 3], timers[i * 5 + 4]]
	var shots: PackedFloat32Array = c[2]
	var projectiles: Array = []
	for k in range(0, shots.size(), 8):
		projectiles.append({"type": int(shots[k]), "owner": int(shots[k + 1]), "pos": Vector2(shots[k + 2], shots[k + 3]),
			"dir": Vector2(shots[k + 4], shots[k + 5]), "angle": shots[k + 6], "age": shots[k + 7], "target": -1})
	combat.projectiles = projectiles
	var mine_data: PackedFloat32Array = c[3]
	var mines: Array = []
	for k in range(0, mine_data.size(), 4):
		mines.append({"owner": int(mine_data[k]), "pos": Vector2(mine_data[k + 1], mine_data[k + 2]), "age": mine_data[k + 3]})
	combat.mines = mines
	if c.size() > 4:
		combat.locked = int(c[4]) == 1  # Weapons Hot: the host's lock
