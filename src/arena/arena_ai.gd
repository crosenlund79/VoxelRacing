class_name ArenaAi
extends RefCounted
## A rival in the Battle Royale arena: picks an opponent (any car, never
## preferring the human), hunts it, keeps the distance its personality likes,
## shoots when the missile has a clear, well-aimed line, drops mines on
## pursuers, evades when chased, steers round the scrap and does not keep
## driving into walls. Same steering / throttle commands as a human. The
## personality comes from the rival's existing traits (AiParams):
##   aggression (1 - ammo_discipline): Rocco charges and rams, Victor, Greta
##     and Nina keep their distance and wait for clean shots;
##   hazard_lookahead: how early a pursuer is noticed and evaded;
##   line_wander: Finn's unpredictable lines; grudge_bonus: revenge targets.
## Deterministic per seed; no planning, no perfect aim, no scripted winner.

var params: AiParams
var rng := RandomNumberGenerator.new()
var aggression := 0.5
var standoff := 180.0
var aim_tolerance := 0.12
var evade_chance := 0.5
var wander := 0.0
var target := -1
var grudge := -1
var _retarget := 0.0
var _evade_left := 0.0
var _evade_side := 1.0
var _stuck := 0.0
var _unstick_left := 0.0
var _time := 0.0
## Counters for tests and tuning.
var shots := 0
var mines := 0
var evades := 0


func _init(p_params: AiParams, seed_value: int) -> void:
	params = p_params
	rng.seed = seed_value
	aggression = clampf(1.0 - params.ammo_discipline, 0.05, 0.95)
	standoff = lerpf(70.0, 330.0, params.ammo_discipline)
	aim_tolerance = deg_to_rad(lerpf(24.0, 9.0, params.ammo_discipline))
	evade_chance = clampf(params.hazard_lookahead / 1.3, 0.25, 1.0)
	wander = clampf(params.line_wander / 26.0, 0.0, 1.0)


## Who destroyed or damaged us last (revenge, personality-weighted).
func hit_by(id: int) -> void:
	if id >= 0 and params.grudge_bonus > 0.08:
		grudge = id


## me: {id, position, heading, velocity}; others: alive opponents
## [{id, position, heading, velocity, condition}]. Returns
## {steer, fire (accelerate), front, rear}.
func decide(me: Dictionary, others: Array, layout: ArenaLayout, dt: float, front_ready: bool, rear_ready: bool) -> Dictionary:
	_time += dt
	var pos: Vector2 = me.position
	var heading: float = me.heading
	var fwd := Vector2.from_angle(heading)
	var speed: float = (me.velocity as Vector2).length()
	var out := {"steer": 0.0, "fire": true, "front": false, "rear": false}
	if others.is_empty():
		return out
	_retarget -= dt
	var t := _find(others, target)
	if t.is_empty() or _retarget <= 0.0:
		target = _choose(pos, fwd, others)
		t = _find(others, target)
		_retarget = 1.0 + rng.randf() * 0.8
	# a pursuer close behind and pointing at us: evade (calculated drivers more often)
	var threat := _pursuer(pos, fwd, others)
	if threat >= 0 and _evade_left <= 0.0 and rng.randf() < evade_chance * dt * 3.0:
		_evade_left = 0.9 + rng.randf() * 0.6
		_evade_side = 1.0 if rng.randf() < 0.5 else -1.0
		evades += 1
	var goal: Vector2
	var tpos: Vector2 = t.position
	var tvel: Vector2 = t.velocity
	var dist := pos.distance_to(tpos)
	var lead := tpos + tvel * clampf(dist / 820.0, 0.0, 0.8)
	if _evade_left > 0.0:
		_evade_left -= dt
		goal = pos + fwd.rotated(_evade_side * 1.2) * 300.0
	elif dist < standoff and aggression < 0.55:
		# too close for a calculated driver: circle out to shooting distance
		var side := (pos - tpos).orthogonal().normalized()
		goal = tpos + (pos - tpos).normalized() * standoff + side * 160.0
	else:
		goal = lead  # hunt (aggressive drivers ram straight through)
	if wander > 0.0:
		goal += fwd.orthogonal() * sin(_time * 1.7 + rng.randf() * 0.2) * 140.0 * wander
	var desired := (goal - pos).angle()
	# look ahead: steer round walls and obstacles towards the freer side
	var reach := 70.0 + speed * 0.4
	if layout.blocked(pos + fwd * reach, 26.0):
		var left := layout.blocked(pos + fwd.rotated(-0.7) * reach, 26.0)
		var right := layout.blocked(pos + fwd.rotated(0.7) * reach, 26.0)
		if left and not right:
			desired = heading + 1.2
		elif right and not left:
			desired = heading - 1.2
		else:
			desired = heading + (1.4 if (goal - pos).cross(fwd) < 0.0 else -1.4)
		if speed > 260.0:
			out.fire = false  # brake to make the turn
	var diff := wrapf(desired - heading, -PI, PI)
	if absf(diff) > 0.07:
		out.steer = signf(diff)
	if absf(diff) > 1.6 and speed > 300.0:
		out.fire = false
	# stuck against something: full lock until free (the arena also nudges stalled cars)
	if speed < 30.0:
		_stuck += dt
	else:
		_stuck = 0.0
	if _stuck > 0.8:
		_unstick_left = 1.0
		_stuck = 0.0
	if _unstick_left > 0.0:
		_unstick_left -= dt
		out.steer = _evade_side
		out.fire = true
	# weapons: a clear, aimed line for the missile; mines for pursuers
	if front_ready:
		for o in others:
			var d: float = pos.distance_to(o.position)
			if d > 680.0 or d < 50.0:
				continue
			var aim: Vector2 = (o.position + o.velocity * (d / 820.0)) - pos
			if absf(wrapf(aim.angle() - heading, -PI, PI)) > aim_tolerance * (1.0 if o.id == target else 0.6):
				continue
			if layout.clear_line(pos, o.position):
				out.front = true
				shots += 1
				break
	if rear_ready and threat >= 0 and rng.randf() < (0.4 + aggression * 0.6) * dt * 4.0:
		out.rear = true
		mines += 1
	return out


func _find(others: Array, id: int) -> Dictionary:
	for o in others:
		if o.id == id:
			return o
	return {}


## The opponent to hunt: near and ahead; calculated drivers favour damaged
## cars, grudges weigh in; a little randomness so not everyone picks the same.
func _choose(pos: Vector2, fwd: Vector2, others: Array) -> int:
	var best := -1
	var best_score := INF
	for o in others:
		var to: Vector2 = o.position - pos
		var score := to.length() + 260.0 * absf(fwd.angle_to(to)) / PI
		score -= (1.0 - float(o.condition)) * 260.0 * (1.0 - aggression)
		if o.id == grudge:
			score -= 900.0 * params.grudge_bonus
		score += rng.randf() * 160.0
		if score < best_score:
			best_score = score
			best = o.id
	return best


## An opponent close behind, pointing at us (-1 none).
func _pursuer(pos: Vector2, fwd: Vector2, others: Array) -> int:
	for o in others:
		var to: Vector2 = pos - o.position
		if to.length() > 280.0 or fwd.dot(-to.normalized()) > -0.3:
			continue
		if Vector2.from_angle(o.heading).dot(to.normalized()) > 0.85:
			return o.id
	return -1
