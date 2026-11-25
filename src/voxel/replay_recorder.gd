class_name ReplayRecorder
extends Node
## VoxelRacing action replays, part 1: what happened. Watches the live race
## (never writes to it) and keeps, around every entertaining moment, the cars'
## voxel poses and the weapons in flight at 30 samples per second, plus the
## moment's events. Only the stretches around scored events are kept (a short
## rolling buffer supplies each moment's lead-in), so long races stay small.
##
## A sample: [t, cars: PackedFloat32Array (K per car), missiles, mines]
##   car:     x, y, z (3D), yaw, roll, pitch, steer, brake, health share, flags, speed (px/s), head, slope
##   missile: rid, type, x2d, y2d, angle, level
##   mine:    x2d, y2d, age, level
## An event: {t, kind, score, pos (2D), ...}
## kinds: destroyed, wreck, hit, mine_blast, fire, crash, pileup, overtake,
##        finish, taunt, air

const RATE := 1.0 / 30.0
const RING := 6.0
const PRE := 3.6
const POST := 3.4
const MAX_CAPTURES := 30
## The longest a moment may run (s).
const MAX_LEN := 13.0
## Events below this are only kept inside other moments (sparks, launches).
const CAPTURE_SCORE := 4.5
const K := 13
const F_VISIBLE := 1
const F_WRECKED := 2
const F_BODY := 4

var main: Node2D
var stage: VoxelStage
var t := 0.0
var ring: Array = []
## {start, end, score, events: Array, samples: Array, open: bool, key: Dictionary}
var captures: Array = []
## Names and colours for the overlay.
var names: PackedStringArray = []
var player_id := 0
var night := false
var _last_sample := -INF
var _combat_cursor := 0
var _prev_place := PackedInt32Array()
var _wrecked := PackedByteArray()
var _finished := PackedByteArray()
var _air_from := PackedFloat32Array()
var _crashes: Array = []
var _pair_cool := {}
var _next_rid := 1
var _running := false
var _race_number := -1


func setup(p_stage: VoxelStage) -> void:
	stage = p_stage
	main = stage.main
	name = "ReplayRecorder"
	process_physics_priority = 100  # after the race's own tick
	var n: int = main.cars.size()
	_prev_place.resize(n)
	_wrecked.resize(n)
	_finished.resize(n)
	_air_from.resize(n)
	for i in n:
		var c: Car = main.cars[i]
		c.wall_hit.connect(_on_wall_hit.bind(i))
		c.car_hit.connect(_on_car_hit.bind(i))
		names.append(RivalRoster.short_name(i).to_upper() if i > 0 else "YOU")


## Forget everything (a new race).
func reset() -> void:
	t = 0.0
	ring.clear()
	captures.clear()
	_last_sample = -INF
	_combat_cursor = main.combat.events.size() if main.combat != null else 0
	_prev_place.fill(0)
	_wrecked.fill(0)
	_finished.fill(0)
	_air_from.fill(-1.0)
	_crashes.clear()
	_pair_cool.clear()
	player_id = int(main.get("local_player_id")) if main.get("local_player_id") != null else 0
	if main.session.spectator:
		player_id = -1
	for i in names.size():
		names[i] = "YOU" if i == player_id else RivalRoster.short_name(i).to_upper()


func _physics_process(_delta: float) -> void:
	if stage == null or not stage.ready_3d:
		return
	var session: RaceSession = main.session
	if main.races_started != _race_number:
		_race_number = main.races_started
		reset()
		_running = false
	var racing := session.state == RaceSession.State.RACING or (session.state == RaceSession.State.FINISHED and not session.all_finished())
	if session.state == RaceSession.State.RACING and not _running:
		_running = true
	if not _running:
		return
	if not racing:
		# the last finisher is in: close the open moments
		for cap in captures:
			cap.open = false
		_running = false
		return
	t += Car.FIXED_STEP
	_read_combat()
	_watch_cars()
	if t - _last_sample >= RATE - 0.0001:
		_last_sample = t
		_sample()


# ------------------------------------------------------------ sampling

func _sample() -> void:
	var n: int = main.cars.size()
	var cars := PackedFloat32Array()
	cars.resize(n * K)
	for i in n:
		var d: Dictionary = stage.cars3d[i]
		var c: Car = main.cars[i]
		var o := i * K
		var p := Vox.to3(c.global_position, float(d.h))
		cars[o] = p.x
		cars[o + 1] = p.y
		cars[o + 2] = p.z
		cars[o + 3] = Vox.yaw(c.global_rotation)
		cars[o + 4] = float(d.roll)
		cars[o + 5] = float(d.pitch)
		cars[o + 6] = float(d.steer)
		cars[o + 7] = float(d.brake)
		cars[o + 8] = main.damage.fraction(i) if main.damage != null else 1.0
		var flags := 0
		if c.visible:
			flags |= F_VISIBLE
		if _is_wrecked(i):
			flags |= F_WRECKED
		if (d.body as Node3D).visible:
			flags |= F_BODY
		cars[o + 9] = flags
		cars[o + 10] = c.model.velocity.length() if c.model != null else 0.0
		cars[o + 11] = float(d.get("head", 0.0))
		cars[o + 12] = float(d.get("slope", 0.0))
	var missiles := PackedFloat32Array()
	var mines := PackedFloat32Array()
	var combat: CombatWorld = main.combat
	if combat != null:
		for p in combat.projectiles:
			if not p.has("rid"):
				p["rid"] = _next_rid
				_next_rid += 1
			var ang: float = (p.dir as Vector2).angle() if p.has("dir") else 0.0
			missiles.append_array([float(p.rid), float(p.type), p.pos.x, p.pos.y, ang, float(p.get("level", 0))])
		for m in combat.mines:
			mines.append_array([m.pos.x, m.pos.y, float(m.age), float(m.get("level", 0))])
	var s := [t, cars, missiles, mines]
	ring.append(s)
	while ring.size() > 2 and t - float(ring[0][0]) > RING:
		ring.pop_front()
	for cap in captures:
		if cap.open:
			if t <= cap.end:
				(cap.samples as Array).append(s)
			else:
				cap.open = false


func _is_wrecked(i: int) -> bool:
	var combat: CombatWorld = main.combat
	var dw: DamageWorld = main.damage
	return (combat != null and combat.enabled and combat.is_wrecked(i)) or (dw != null and dw.is_retired(i))


# ------------------------------------------------------------ events

## Adds an event; worthy ones open (or extend) a captured moment.
func add_event(e: Dictionary) -> void:
	e.t = t
	var score: float = e.score
	if player_id >= 0 and (int(e.get("car", -9)) == player_id or int(e.get("by", -9)) == player_id):
		score += 2.0
		e.score = score
	# an open moment takes what happens inside it; a notable event (score 3+)
	# may stretch it a little, never beyond MAX_LEN
	for cap in captures:
		if not cap.open or t > float(cap.end):
			continue
		var room := float(cap.start) + MAX_LEN - t
		if score >= CAPTURE_SCORE and room < _post(e) * 0.6:
			cap.open = false  # too long already: this one gets a moment of its own
			break
		(cap.events as Array).append(e)
		if score >= 3.0:
			cap.score = float(cap.score) + score * 0.35
			cap.end = minf(maxf(float(cap.end), t + _post(e)), float(cap.start) + MAX_LEN)
		if score > float(cap.key.score):
			cap.key = e
		return
	if score < CAPTURE_SCORE:
		return
	var start := t - PRE
	var launch: float = e.get("launch_t", -1.0)
	if launch >= 0.0 and t - launch < RING - 1.0:
		start = minf(start, launch - 1.2)  # from the missile's launch
	var cap := {"start": start, "end": t + _post(e), "score": score, "events": [e], "samples": [], "open": true, "key": e}
	for s in ring:
		if float(s[0]) >= start:
			(cap.samples as Array).append(s)
	captures.append(cap)
	if captures.size() > MAX_CAPTURES:
		var worst := -1
		for k in captures.size():
			if not captures[k].open and (worst < 0 or float(captures[k].score) < float(captures[worst].score)):
				worst = k
		if worst >= 0:
			captures.remove_at(worst)


func _post(e: Dictionary) -> float:
	match String(e.kind):
		"destroyed", "wreck", "pileup":
			return POST + 1.4
		"finish":
			return 2.6
	return POST


## Lower-score events in the rolling window are attached to a new moment
## later (fire before a hit) by the theater from the samples; launches are
## remembered here so a hit can find its missile.
var _launches: Array = []


func _read_combat() -> void:
	var combat: CombatWorld = main.combat
	if combat == null:
		return
	if _combat_cursor > combat.events.size():
		_combat_cursor = 0
	while _combat_cursor < combat.events.size():
		var e: Dictionary = combat.events[_combat_cursor]
		_combat_cursor += 1
		match String(e.kind):
			"fire":
				var rid := -1
				for p in combat.projectiles:  # the round just launched
					if int(p.owner) == int(e.owner) and not p.has("rid") and float(p.age) < 0.1:
						p["rid"] = _next_rid
						rid = _next_rid
						_next_rid += 1
				_launches.append({"t": t, "owner": int(e.owner), "type": int(e.type), "rid": rid})
				while _launches.size() > 40:
					_launches.pop_front()
				if int(e.type) != WeaponRules.Weapon.MINE:
					add_event({"kind": "fire", "score": 1.0, "pos": e.pos, "car": -1, "by": int(e.owner), "type": int(e.type), "rid": rid})
			"destroyed":
				var victim := int(e.car)
				var rid := _launch_rid(int(e.owner), int(e.type))
				var score := 9.0
				if int(e.owner) == victim:
					score = 7.0  # own goal: still funny
				add_event({"kind": "destroyed", "score": score, "pos": e.pos, "car": victim, "by": int(e.owner),
					"type": int(e.type), "rid": rid, "launch_t": _launch_t(int(e.owner), int(e.type))})
				_wrecked[victim] = 1
			"explode":
				if int(e.car) >= 0:
					add_event({"kind": "hit", "score": 4.0, "pos": e.pos, "car": int(e.car), "by": int(e.owner), "type": int(e.type),
						"rid": _launch_rid(int(e.owner), int(e.type))})
				else:
					add_event({"kind": "blast", "score": 1.0, "pos": e.pos, "car": -1, "by": int(e.owner), "type": int(e.type)})
			"mine_blast":
				add_event({"kind": "mine_blast", "score": 2.0, "pos": e.pos, "car": -1, "by": int(e.owner), "type": WeaponRules.Weapon.MINE})


func _launch_rid(owner: int, type: int) -> int:
	for k in range(_launches.size() - 1, -1, -1):
		var l: Dictionary = _launches[k]
		if l.owner == owner and l.type == type and t - float(l.t) < 8.0:
			return int(l.rid)
	return -1


func _launch_t(owner: int, type: int) -> float:
	for k in range(_launches.size() - 1, -1, -1):
		var l: Dictionary = _launches[k]
		if l.owner == owner and l.type == type and t - float(l.t) < 8.0:
			return float(l.t)
	return -1.0


func _on_wall_hit(_normal: Vector2, speed: float, i: int) -> void:
	_crash(i, -1, speed)


func _on_car_hit(other: Car, speed: float, i: int) -> void:
	if other.racer_id < i:
		return  # each pair once (both cars report it)
	_crash(i, other.racer_id, speed)


func _crash(i: int, other: int, speed: float) -> void:
	if not _running or speed < 150.0:
		return
	var c: Car = main.cars[i]
	var pos := c.global_position
	if other >= 0:
		pos = (pos + (main.cars[other] as Car).global_position) * 0.5
	_crashes.append({"t": t, "a": i, "b": other, "pos": pos})
	while _crashes.size() > 0 and t - float(_crashes[0].t) > 1.6:
		_crashes.pop_front()
	# a pile-up: three or more cars in crashes close together
	var involved := {}
	for k in _crashes:
		if (k.pos as Vector2).distance_to(pos) < 260.0:
			involved[k.a] = true
			if k.b >= 0:
				involved[k.b] = true
	if involved.size() >= 3:
		add_event({"kind": "pileup", "score": 8.0, "pos": pos, "car": i, "by": other, "cars": involved.keys()})
		_crashes.clear()
		return
	var score := 1.5 + clampf((speed - 150.0) / 120.0, 0.0, 3.0)
	add_event({"kind": "crash", "score": score, "pos": pos, "car": i, "by": other, "speed": speed})


func _watch_cars() -> void:
	var session: RaceSession = main.session
	var n: int = main.cars.size()
	var path: ClosedPath = main.track.path if main.track != null else null
	for i in n:
		var c: Car = main.cars[i]
		if not session.is_participating(i):
			continue
		var r: RacerState = session.racers[i]
		# wrecks from damage (combat kills report themselves)
		var w := _is_wrecked(i)
		if w and _wrecked[i] == 0 and c.visible:
			add_event({"kind": "wreck", "score": 7.0, "pos": c.global_position, "car": i, "by": -1})
		_wrecked[i] = 1 if w else 0
		# finishes (close ones are the moment)
		if r.is_finished() and _finished[i] == 0:
			_finished[i] = 1
			var gap := INF
			for j in n:
				if j != i and session.racers[j].is_finished() and session.racers[j].finish_position == r.finish_position - 1:
					gap = r.finish_time - session.racers[j].finish_time
			if gap < 1.0:
				var score := 6.0 if gap > 0.5 else 9.0
				if r.finish_position <= 3:
					score += 1.0
				add_event({"kind": "finish", "score": score, "pos": c.global_position, "car": i, "by": -1, "gap": gap,
					"place": r.finish_position})
		# big air
		if c.airborne:
			if _air_from[i] < 0.0:
				_air_from[i] = t
		elif _air_from[i] >= 0.0:
			var dur := t - _air_from[i]
			_air_from[i] = -1.0
			if dur > 0.55:
				add_event({"kind": "air", "score": 3.0 + dur * 2.0, "pos": c.global_position, "car": i, "by": -1, "dur": dur})
	# overtakes: two cars swap places on the road, close together
	if session.state != RaceSession.State.RACING and session.state != RaceSession.State.FINISHED:
		return
	var place := PackedInt32Array()
	place.resize(n)
	for i in n:
		place[i] = session.position_of(i) if session.is_participating(i) and not session.racers[i].is_done() else 0
	if t > 4.0:
		for a in n:
			if place[a] <= 0 or _prev_place[a] <= 0 or place[a] != _prev_place[a] - 1:
				continue
			for b in n:
				if b == a or place[b] != _prev_place[b] + 1 or _prev_place[b] != place[a]:
					continue
				var ca: Car = main.cars[a]
				var cb: Car = main.cars[b]
				if ca.global_position.distance_to(cb.global_position) > 170.0 or _wrecked[a] == 1 or _wrecked[b] == 1:
					continue
				var key := a * 100 + b
				if t - float(_pair_cool.get(key, -100.0)) < 6.0:
					continue
				_pair_cool[key] = t
				_pair_cool[b * 100 + a] = t
				var score := 2.5
				var corner := false
				var final := false
				if path != null:
					var s: float = main.progress[a].distance
					var turn := absf(wrapf(path.tangent_at(s + 140.0).angle() - path.tangent_at(s - 140.0).angle(), -PI, PI))
					corner = turn > deg_to_rad(28.0)
					var lap: int = session.racers[a].tracker.current_lap()
					final = lap >= session.lap_count() and fposmod(s, path.length) > path.length * 0.8
				if corner:
					score += 2.0
				if final:
					score += 4.0
				if place[a] <= 3:
					score += 1.0
				add_event({"kind": "overtake", "score": score, "pos": (ca.global_position + cb.global_position) * 0.5,
					"car": b, "by": a, "corner": corner, "final": final, "place": place[a]})
				if stage.race_fx != null and stage.race_fx.has_method("on_overtake"):
					stage.race_fx.on_overtake(a, b)
	_prev_place = place


## The finished moments worth showing, best first (at most `count`, about
## `budget` seconds in all), then in race order.
func highlights(count: int = 5, budget: float = 52.0, min_score: float = 6.0) -> Array:
	var pool: Array = []
	for cap in captures:
		if (cap.samples as Array).size() >= 20 and float(cap.key.score) + 0.0 >= min_score:
			pool.append(cap)
	pool.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.score) > float(b.score))
	var out: Array = []
	var total := 0.0
	var kinds := {}
	for cap in pool:
		var len_s := float(cap.samples[-1][0]) - float(cap.samples[0][0])
		var kind := String(cap.key.kind)
		if kinds.get(kind, 0) >= 2 and pool.size() > count:
			continue  # variety: at most two of a kind while there is choice
		if out.size() >= count or (total + len_s > budget and not out.is_empty()):
			continue
		var overlaps := false
		for o in out:  # the same footage twice: no
			var a := maxf(float(o.samples[0][0]), float(cap.samples[0][0]))
			var b := minf(float(o.samples[-1][0]), float(cap.samples[-1][0]))
			if b - a > len_s * 0.4:
				overlaps = true
		if overlaps:
			continue
		out.append(cap)
		kinds[kind] = int(kinds.get(kind, 0)) + 1
		total += len_s
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.start) < float(b.start))
	return out
