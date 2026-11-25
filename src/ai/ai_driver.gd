class_name AiDriver
extends RefCounted
## One computer driver. Each tick it reads its car's state and nearby traffic and
## returns the same inputs a player has: steer (-1, 0, +1) and fire. It drives in
## Fire to Accelerate mode: fire accelerates, releasing fire brakes.
## Personality traits in AiParams shape decisions only (braking point, corner
## commitment, passing, reactions to pressure); with neutral traits this is the
## M2 driver. Randomness comes from a per-race seeded generator.
## Pure logic (no scene access), so it is unit-testable.

var line: RacingLine
var params: AiParams
var rng := RandomNumberGenerator.new()
## Separate generator for weapon decisions, so driving decisions are unchanged by combat.
var weapon_rng := RandomNumberGenerator.new()
## Current sideways shift from the racing line (px), used for passing.
var lane_bias := 0.0
## Commitment chosen for the current corner (1.0 outside corners).
var commitment := 1.0
## True while the driver is in a braking/corner zone.
var in_corner := false
## Seconds of fluster left (hesitation / over-correction under pressure).
var fluster_time := 0.0
## Seconds left of reduced commitment after the planned line was disrupted.
var disrupted_time := 0.0
## Side chosen for the current pass attempt (-1/+1, 0 = none).
var pass_side_choice := 0.0
var _was_passing := false
## Counters for validation and tests.
var overcommits := 0
var flusters := 0
var defends := 0
var disruptions := 0
var impulse_passes := 0
var _defending := false
## Combat counters / state.
var front_shots := 0
var wasted_shots := 0
var mines_dropped := 0
var held_for_reserve := 0
## Seconds of retaliation left after being destroyed.
var retaliating := 0.0
## M3.5 Tactical counters / state.
var rear_shots := 0
var brilliant_shots := 0
var shots_by_weapon: Dictionary = {}
var _aim: Array[float] = [0.0, 0.0]
## Micro Nemesis: who destroyed this driver last (-1 none) and for how long the
## grudge still matters (s).
var grudge_id := -1
var grudge_left := 0.0
## Wreck ahead: seconds it has been in view; counters for tests.
var _hazard_seen := 0.0
var hazard_avoids := 0
## Own line wander (time and phase, per race).
var _time := 0.0
var _wander_phase := 0.0
## Track branches (2026-11-17): the route chosen for each branch (by index,
## RacingLine.ROUTE_*), the lap each was planned for, and pit stops.
var route_choice := {}
var _planned := {}
var pitting := false
var _pit_latched := false
var _override_wanted := false
var _override_sent := false
## Statistics: pit stops started, overrides asked, choices per split lane.
var pit_entries := 0
var pit_overrides := 0
var missed_pits := 0
var route_counts := {}
## Service bays: seconds of patience left while every bay is taken, and
## whether this stop was given up (drives through). Statistics: waits begun
## and stops given up.
var _wait_left := 0.0
var _gave_up := false
var pit_waits := 0
var pit_abandons := 0


func _init(p_line: RacingLine, p_params: AiParams) -> void:
	line = p_line
	params = p_params
	begin_race(0)


## Resets per-race state and seeds the decision randomness.
func begin_race(seed_value: int) -> void:
	rng.seed = seed_value
	weapon_rng.seed = seed_value + 7919
	front_shots = 0
	wasted_shots = 0
	mines_dropped = 0
	held_for_reserve = 0
	retaliating = 0.0
	rear_shots = 0
	brilliant_shots = 0
	_burst_left = 0.0
	shots_by_weapon = {}
	_aim = [0.0, 0.0]
	grudge_id = -1
	grudge_left = 0.0
	_hazard_seen = 0.0
	hazard_avoids = 0
	_time = 0.0
	_wander_phase = TAU * float(posmod(seed_value, 997)) / 997.0
	lane_bias = 0.0
	commitment = 1.0
	in_corner = false
	fluster_time = 0.0
	overcommits = 0
	flusters = 0
	disrupted_time = 0.0
	pass_side_choice = 0.0
	_was_passing = false
	defends = 0
	disruptions = 0
	impulse_passes = 0
	_defending = false
	route_choice = {}
	_planned = {}
	pitting = false
	_pit_latched = false
	_override_wanted = false
	_override_sent = false
	pit_entries = 0
	pit_overrides = 0
	missed_pits = 0
	route_counts = {}
	_wait_left = 0.0
	_gave_up = false
	pit_waits = 0
	pit_abandons = 0


## me: {position, heading, speed, distance, lateral}
## others: Array of {distance, lateral, speed} for the other cars.
## distance values are unwrapped race progress along the centreline.
## Returns {steer: float, fire: bool}.
func decide(me: Dictionary, others: Array, delta: float) -> Dictionary:
	var s: float = me.distance
	var speed: float = me.speed
	_time += delta
	if line.layout != null:
		_plan_branches(me, others)
		_update_pit_latch(s, me)
		_update_beside(s, me)
	var target_lateral := own_line(s)
	var blocked := false
	var lift := false

	var ahead := _nearest_car_ahead(me, others)
	var passing := false
	if not ahead.is_empty():
		var pass_lateral := NAN
		var wants: bool = ahead.speed < speed - params.pass_speed_margin
		if not wants and params.pass_impulse_chance > 0.0 and rng.randf() < params.pass_impulse_chance * delta:
			wants = true
			impulse_passes += 1
		if wants and _may_start_pass(s):
			pass_lateral = _pass_lateral(me, ahead, others, s)
		if not is_nan(pass_lateral):
			blocked = true
			passing = true
			target_lateral = pass_lateral
		elif ahead.gap < params.follow_gap and not _parked_in_bay_ahead(me, ahead):
			lift = true
	_was_passing = passing
	if not passing and params.defend_distance > 0.0:
		var chaser := _closing_car_behind(me, others)
		if not chaser.is_empty():
			var bd := _room(s)
			target_lateral = lerpf(target_lateral, clampf(chaser.lateral, bd.x, bd.y), params.defend_strength)
			blocked = true
			if not _defending:
				defends += 1
			_defending = true
		else:
			_defending = false

	# a wrecked car ahead: seen in time (personality), steer round it if there is room
	var hazard := _hazard_ahead(me, others, speed)
	if hazard.is_empty():
		_hazard_seen = 0.0
	else:
		_hazard_seen += delta
		if _hazard_seen >= params.hazard_reaction:
			var avoid := choose_pass_lateral(me.lateral, hazard.lateral, s)
			if not is_nan(avoid):
				if _hazard_seen - delta < params.hazard_reaction:
					hazard_avoids += 1  # reacted to this wreck
				target_lateral = avoid
				blocked = true
			elif hazard.gap < params.follow_gap * 1.5:
				lift = true

	_update_fluster(me, others, delta)
	var flustered := fluster_time > 0.0
	if flustered and params.fluster_lift_chance > 0.0 and rng.randf() < params.fluster_lift_chance:
		lift = true

	var desired_bias := target_lateral - line.offset_at(s, route_at(s))
	var rate := params.lane_change_rate if blocked else params.lane_return_rate
	lane_bias = move_toward(lane_bias, desired_bias, rate * delta)

	var lookahead := params.lookahead_base + params.lookahead_per_speed * speed
	var deadband := deg_to_rad(params.steer_deadband_degrees)
	if flustered:
		lookahead *= 1.0 - params.fluster_overcorrection
		deadband *= 1.0 - params.fluster_overcorrection
	var room_now := _room(s)
	var room_ahead := _room(s + lookahead)
	var aim_lateral := clampf(line.offset_at(s + lookahead, route_at(s + lookahead)) + lane_bias,
		maxf(room_now.x, room_ahead.x), minf(room_now.y, room_ahead.y))
	var bay_aim := _bay_aim(s + lookahead, me)  # turning into (or out of) its service bay
	if not is_nan(bay_aim):
		aim_lateral = bay_aim
	var aim := line.point_with_lateral(s + lookahead, aim_lateral)
	var error := wrapf((aim - me.position).angle() - me.heading, -PI, PI)
	var steer := 0.0
	if absf(error) > deadband:
		steer = signf(error)

	var speed_point := s + speed * params.brake_anticipation
	var planned := line.speed_at(speed_point, _speed_route(speed_point))
	if _pit_latched:
		planned = minf(planned, _pit_stop_speed(s, me, delta))
	_update_corner(planned < line.top_speed - 1.0, not _nearest_car_ahead(me, others, true).is_empty())
	var target_speed := planned * commitment if in_corner else planned
	if in_corner and _defending:
		target_speed *= params.defend_commitment
	if params.disrupted_threshold > 0.0:
		disrupted_time = maxf(0.0, disrupted_time - delta)
		if absf(lane_bias) > params.disrupted_threshold and not passing:
			if disrupted_time <= 0.0:
				disruptions += 1
			disrupted_time = params.disrupted_recovery
		if in_corner and disrupted_time > 0.0:
			target_speed *= params.disrupted_commitment
	var fire := speed < target_speed and not lift
	var out := {"steer": steer, "fire": fire}
	if _pit_latched and _override_wanted and not _override_sent and me.get("pit", {}).get("in_lane", false):
		_override_sent = true  # the shared limiter override (no literal double tap)
		pit_overrides += 1
		out["pit_override"] = true
	return out


## Picks this corner's commitment when entering a braking/corner zone.
func _update_corner(zone: bool, chasing: bool) -> void:
	if zone and not in_corner:
		commitment = params.corner_commitment
		if params.commitment_variation > 0.0:
			commitment += rng.randf_range(-params.commitment_variation, params.commitment_variation)
		if params.overcommit_chance > 0.0 and rng.randf() < params.overcommit_chance:
			commitment += params.overcommit_extra
			overcommits += 1
		if chasing:
			commitment += params.chase_aggression
	elif not zone:
		commitment = 1.0
	in_corner = zone


## Under pressure (a car close behind or alongside) the driver may become flustered.
func _update_fluster(me: Dictionary, others: Array, delta: float) -> void:
	fluster_time = maxf(0.0, fluster_time - delta)
	if params.pressure_distance <= 0.0 or fluster_time > 0.0:
		return
	if under_pressure(me, others) and rng.randf() < params.fluster_chance_per_second * delta:
		fluster_time = params.fluster_duration
		flusters += 1


func under_pressure(me: Dictionary, others: Array) -> bool:
	if params.pressure_distance <= 0.0:
		return false
	for o in others:
		var gap := _gap(me, o)
		if gap <= 0.0 and gap > -params.pressure_distance and absf(o.lateral - me.lateral) < params.car_clearance * 2.0:
			return true
	return false


## Pass position honouring the driver's side preference and lane-clearance check.
func _pass_lateral(me: Dictionary, ahead: Dictionary, others: Array, s: float) -> float:
	var lateral := choose_pass_lateral(me.lateral, ahead.lateral, s)
	if params.pass_side != 0:
		if not _was_passing or pass_side_choice == 0.0:
			if params.pass_side == 2:
				pass_side_choice = -1.0 if rng.randf() < 0.5 else 1.0
			else:
				pass_side_choice = -_turn_direction(s)
		var candidate: float = ahead.lateral + pass_side_choice * params.pass_offset
		var room := _room(s)
		if candidate >= room.x and candidate <= room.y:
			lateral = candidate
	if not is_nan(lateral) and params.pass_check_clearance:
		for o in others:
			var gap := _gap(me, o)
			if is_equal_approx(gap, ahead.gap) and is_equal_approx(o.lateral, ahead.lateral):
				continue
			if gap > -60.0 and gap < params.traffic_distance and absf(o.lateral - lateral) < params.car_clearance:
				return NAN
	return lateral


## Sign of the next corner's turn (+1 right, -1 left, 0 straight) within pass_lookahead + 300 px.
func _turn_direction(s: float) -> float:
	var t0 := line.center.tangent_at(s)
	var d := 100.0
	while d <= params.pass_lookahead + 300.0:
		var t1 := line.center.tangent_at(s + d)
		var turn := t0.cross(t1)
		if absf(turn) > 0.2:
			return signf(turn)
		d += 50.0
	return 0.0


## Nearest car behind within defend_distance that is at least as fast; empty if none.
func _closing_car_behind(me: Dictionary, others: Array) -> Dictionary:
	var best := {}
	for o in others:
		var gap := _gap(me, o)
		if gap >= 0.0 or gap < -params.defend_distance or o.speed < me.speed - 10.0:
			continue
		if best.is_empty() or gap > best.gap:
			best = {"gap": gap, "lateral": o.lateral, "speed": o.speed}
	return best


func _may_start_pass(s: float) -> bool:
	if not params.pass_on_straights_only:
		return true
	var d := 0.0
	while d <= params.pass_lookahead:
		if line.speed_at(s + d) < line.top_speed - 1.0:
			return false
		d += 50.0
	return true


func _gap(me: Dictionary, other: Dictionary) -> float:
	return wrapf(other.distance - me.distance, -line.center.length * 0.5, line.center.length * 0.5)


## Closest car ahead within traffic_distance, as {gap, lateral, speed}; empty if none.
## Only cars in our path count unless any_lane is true.
func _nearest_car_ahead(me: Dictionary, others: Array, any_lane: bool = false) -> Dictionary:
	var best := {}
	for o in others:
		var gap := _gap(me, o)
		if gap <= 0.0 or gap > params.traffic_distance:
			continue
		if not any_lane and absf(o.lateral - me.lateral) > params.car_clearance:
			continue
		if best.is_empty() or gap < best.gap:
			best = {"gap": gap, "lateral": o.lateral, "speed": o.speed}
	return best


## This driver's own line at s: the shared racing line, shifted by the
## driver's preferred offset and slow wander, kept inside the road.
func own_line(s: float) -> float:
	var lateral := line.offset_at(s, route_at(s)) + params.line_offset
	if params.line_wander > 0.0:
		lateral += params.line_wander * sin(TAU * _time / maxf(params.line_wander_period, 0.5) + _wander_phase)
	var room := _room(s)
	return clampf(lateral, room.x, room.y)


## The nearest wrecked car in this driver's path within its reading distance.
func _hazard_ahead(me: Dictionary, others: Array, speed: float) -> Dictionary:
	var reach := maxf(params.traffic_distance, speed * params.hazard_lookahead)
	var best := {}
	for o in others:
		if not o.get("wrecked", false):
			continue
		var gap := _gap(me, o)
		if gap <= 0.0 or gap > reach or absf(o.lateral - me.lateral) > params.car_clearance + 12.0:
			continue
		if best.is_empty() or gap < best.gap:
			best = {"gap": gap, "lateral": o.lateral}
	return best


## Lateral position to pass a car at other_lateral: the side with room that is
## closest to where we are. NAN when neither side has room inside the road.
func choose_pass_lateral(my_lateral: float, other_lateral: float, s: float = NAN) -> float:
	var options: Array[float] = []
	var room := Vector2(-line.road_half_width + params.pass_margin, line.road_half_width - params.pass_margin) \
		if is_nan(s) else _room(s)
	for side in [-1.0, 1.0]:
		var candidate: float = other_lateral + side * params.pass_offset
		if candidate >= room.x and candidate <= room.y:
			options.append(candidate)
	if options.is_empty():
		return NAN
	options.sort_custom(func(a: float, b: float) -> bool: return absf(a - my_lateral) < absf(b - my_lateral))
	return options[0]


## Called when this driver's car was destroyed (starts retaliation if any).
func on_destroyed() -> void:
	retaliating = params.retaliation_time


## Weapon decision for one tick. Only called when weapons are enabled.
## me: as decide(). targets: Array of {position, velocity, distance, lateral, speed, wrecked}.
## ctx: {front_ready, rear_ready, front_ammo, front_start, laps_left, lap_count,
##       missile_speed, hit_radius, mine_fuse, pressure}.
## Returns {front: bool, rear: bool}.
func decide_weapons(me: Dictionary, targets: Array, ctx: Dictionary, delta: float) -> Dictionary:
	retaliating = maxf(0.0, retaliating - delta)
	grudge_left = maxf(0.0, grudge_left - delta)
	var boost := params.retaliation_boost if retaliating > 0.0 else 1.0
	var relief := 0.15 if retaliating > 0.0 else 0.0
	var out := {"front": false, "rear": false}
	relief += _impulse(delta)
	if ctx.front_ready:
		var pacing := spend_penalty(ctx.front_ammo, ctx.front_start, ctx) + reserve_penalty(ctx.front_ammo, ctx)
		var threshold := params.attack_min_confidence - relief + pacing
		if params.confidence_variation > 0.0:
			threshold += weapon_rng.randf_range(-params.confidence_variation, params.confidence_variation)
		if ctx.get("pressure", false):
			threshold -= params.pressure_attack_drop
		var quality := front_shot_quality(me, targets, ctx)
		if quality >= threshold and quality > 0.0 and weapon_rng.randf() < params.attack_rate * boost * delta:
			out.front = true
			front_shots += 1
		elif params.waste_chance > 0.0 and weapon_rng.randf() < params.waste_chance * _waste_scale(ctx) * delta:
			out.front = true
			front_shots += 1
			wasted_shots += 1
		elif quality > 0.0 and quality < threshold and quality >= threshold - maxf(pacing, 0.0):
			held_for_reserve += 1  # a shot the ammunition plan turned down
	if ctx.rear_ready:
		var mq := mine_quality(me, targets, ctx)
		var rear_threshold := params.mine_min_quality - relief + spend_penalty(ctx.get("rear_ammo", 0), ctx.get("rear_start", 0), ctx)
		if mq >= rear_threshold and weapon_rng.randf() < params.mine_rate * boost * delta:
			out.rear = true
			mines_dropped += 1
	return out


## Best front-missile shot: 1 = the missile is predicted to pass through a target's
## centre, 0 = no target it can reach.
func front_shot_quality(me: Dictionary, targets: Array, ctx: Dictionary) -> float:
	var fwd := Vector2.from_angle(me.heading)
	var best := 0.0
	for t in targets:
		if t.wrecked:
			continue
		var rel: Vector2 = t.position - me.position
		var along := rel.dot(fwd)
		if along < 40.0 or along > params.attack_range:
			continue
		if params.opportunist and not (t.speed < me.speed * 0.6 or t.speed < 150.0 or along < 160.0):
			continue
		var time: float = along / maxf(1.0, ctx.missile_speed - t.velocity.dot(fwd))
		var predicted: Vector2 = t.position + t.velocity * time - me.position
		var miss := absf(predicted.cross(fwd))
		var q := clampf(1.0 - miss / (ctx.hit_radius * 1.5), 0.0, 1.0) * (1.0 - 0.3 * along / params.attack_range)
		best = maxf(best, _with_grudge(q, t))
	return best


## Best mine drop: 1 = a following car reaches the drop point exactly when the fuse ends.
func mine_quality(me: Dictionary, targets: Array, ctx: Dictionary) -> float:
	var best := 0.0
	for t in targets:
		if t.wrecked or t.speed < 50.0:
			continue
		var gap: float = wrapf(me.distance - t.distance, -line.center.length * 0.5, line.center.length * 0.5)
		if gap <= 20.0:
			continue
		if absf(t.lateral - me.lateral) > 45.0:
			continue
		var arrival: float = gap / t.speed
		best = maxf(best, _with_grudge(clampf(1.0 - absf(arrival - ctx.mine_fuse) / 0.8, 0.0, 1.0), t))
	return best


## Micro Nemesis: a shot that would hit the driver who destroyed us looks a
## little better (personality), fading with the grudge. Only a real chance
## (quality above zero) is improved: nobody chases revenge.
func _with_grudge(q: float, t: Dictionary) -> float:
	if q <= 0.0 or grudge_left <= 0.0 or t.get("id", -2) != grudge_id:
		return q
	return minf(1.0, q + params.grudge_bonus * grudge_left / maxf(params.grudge_time, 0.01))


## Race progress for ammunition pacing (0..1): the continuous share of the
## race distance when known ("progress"), else completed laps.
static func race_progress(ctx: Dictionary) -> float:
	if ctx.has("progress"):
		return clampf(float(ctx.progress), 0.0, 1.0)
	var laps: int = maxi(1, ctx.get("lap_count", 1))
	return clampf(float(laps - int(ctx.get("laps_left", laps))) / float(laps), 0.0, 1.0)


## The share of its starting rounds this driver means to have used by progress p.
func spend_target(p: float) -> float:
	return params.ammo_spend_target * pow(clampf(p, 0.0, 1.0), maxf(params.ammo_spend_curve, 0.05))


## Ammunition over the race (2026-11-23): how much harder (+) or easier (-) a
## shot must be, from the rounds left against this driver's own schedule
## (spend_target), the race length (longer races keep closer to it) and the
## weapon's value. Ahead of schedule a shot needs to be better, by
## ammo_discipline; behind it a shot is taken more readily, the more so the
## later in the race (rounds are there to be used). In the closing stage
## nothing is saved any more. weapon: the type (Tactical), -1 = not considered.
func spend_penalty(ammo: int, start: int, ctx: Dictionary, weapon: int = -1) -> float:
	if start <= 0:
		return 0.0
	var p := race_progress(ctx)
	var laps: int = maxi(1, ctx.get("lap_count", 1))
	var used := 1.0 - float(ammo) / float(start)
	var target := spend_target(p)
	var tolerance := lerpf(0.2, 0.08, clampf((laps - 3) / 47.0, 0.0, 1.0)) * (0.5 if params.ammo_pacing else 1.0)
	var pen := 0.0
	if used > target + tolerance:  # ahead of schedule
		pen = params.ammo_discipline * (used - target - tolerance) * 2.0
	elif used < target - tolerance:  # behind it: spend, the more readily the later it is
		# (a disciplined driver still wants a decent chance: its relief is capped lower)
		pen = -minf(0.45 * (1.0 - 0.5 * params.ammo_discipline), (target - tolerance - used) * (0.8 + 1.4 * p))
	if _closing(ctx):
		pen = minf(pen, 0.0) - 0.1 * params.ammo_discipline
	match weapon:  # the valuable types are kept for the better chances
		WeaponRules.Weapon.HOMING_MISSILE: pen += 0.04 * params.ammo_discipline
		WeaponRules.Weapon.SUPER_MISSILE: pen += 0.08 * params.ammo_discipline
	return pen


## The closing stage of the race: the last lap, or the last 8 % of a long one.
static func _closing(ctx: Dictionary) -> bool:
	return int(ctx.get("laps_left", 99)) <= 1 or race_progress(ctx) >= 0.92


## The soft reserve: with ammo_reserve front rounds or fewer, shots must be
## clearly better (+0.12) until the closing stage. Never an absolute hold.
func reserve_penalty(ammo: int, ctx: Dictionary) -> float:
	if params.ammo_reserve <= 0 or ammo > params.ammo_reserve or _closing(ctx):
		return 0.0
	return 0.12


## Impulsive drivers (ammo_impulse): a trigger-happy spell now and then; the
## threshold relief while it lasts.
var _burst_left := 0.0


func _impulse(delta: float) -> float:
	if params.ammo_impulse <= 0.0:
		return 0.0
	_burst_left = maxf(0.0, _burst_left - delta)
	if _burst_left <= 0.0 and weapon_rng.randf() < params.ammo_impulse * delta:
		_burst_left = params.impulse_time
	return params.impulse_drop if _burst_left > 0.0 else 0.0


## Disciplined drivers waste fewer rounds when they are ahead of their budget.
func _waste_scale(ctx: Dictionary) -> float:
	return clampf(1.0 - spend_penalty(ctx.front_ammo, ctx.front_start, ctx) * 2.0, 0.1, 1.0)


## Remembers who destroyed this driver (Micro Nemesis; -1 / self: nobody).
func on_destroyed_by(offender: int, self_id: int) -> void:
	if offender < 0 or offender == self_id or params.grudge_bonus <= 0.0:
		return
	grudge_id = offender
	grudge_left = params.grudge_time


## --- M3.5 Tactical decisions. The same weapons, ammunition and cooldowns as
## everyone (CombatWorld enforces them); personality traits only shape when a
## driver judges a shot worth taking. Uses weapon_rng only, so driving decisions
## never change. ctx (in addition to decide_weapons): front_weapon, rear_weapon,
## rear_ammo, rear_start, position, field, homing_range, super_orbit_radius,
## super_hit_radius.
func decide_weapons_tactical(me: Dictionary, targets: Array, ctx: Dictionary, delta: float) -> Dictionary:
	retaliating = maxf(0.0, retaliating - delta)
	grudge_left = maxf(0.0, grudge_left - delta)
	var boost := params.retaliation_boost if retaliating > 0.0 else 1.0
	var relief := 0.15 if retaliating > 0.0 else 0.0
	var pressure: bool = ctx.get("pressure", false)
	var out := {"front": false, "rear": false}
	relief += _impulse(delta)
	for slot in 2:
		var ready: bool = ctx.front_ready if slot == 0 else ctx.rear_ready
		if not ready:
			_aim[slot] = 0.0
			continue
		var weapon: int = ctx.front_weapon if slot == 0 else ctx.rear_weapon
		var is_mine := weapon == WeaponRules.Weapon.MINE
		var q := tactical_quality(weapon, me, targets, ctx)
		var ammo: int = ctx.front_ammo if slot == 0 else ctx.rear_ammo
		var pacing := spend_penalty(ammo, ctx.front_start if slot == 0 else ctx.rear_start, ctx, weapon) \
			+ (reserve_penalty(ammo, ctx) if slot == 0 else 0.0)
		var threshold := (params.mine_min_quality if is_mine else params.attack_min_confidence) - relief + pacing
		if params.confidence_variation > 0.0:
			threshold += weapon_rng.randf_range(-params.confidence_variation, params.confidence_variation)
		if pressure:
			threshold -= params.pressure_attack_drop
		var rate := (params.mine_rate if is_mine else params.attack_rate) * boost
		if slot == 1:
			rate *= params.rear_eagerness
			threshold -= 0.1 * (params.rear_eagerness - 1.0)
		var good := q > 0.0 and q >= threshold
		_aim[slot] = _aim[slot] + delta if good else 0.0
		var aimed := pressure or _aim[slot] >= params.tactical_aim_time
		var fire := false
		if q >= 0.9 and params.brilliance_rate > 0.0 and weapon_rng.randf() < params.brilliance_rate * delta:
			fire = true
			brilliant_shots += 1
		elif good and aimed and weapon_rng.randf() < rate * delta:
			fire = true
		elif slot == 0 and params.waste_chance > 0.0 and weapon_rng.randf() < params.waste_chance * _waste_scale(ctx) * delta:
			fire = true
			wasted_shots += 1
		elif q > 0.0 and not good and q >= threshold - maxf(pacing, 0.0):
			held_for_reserve += 1  # a shot the ammunition plan turned down
		if fire:
			_aim[slot] = 0.0
			shots_by_weapon[weapon] = shots_by_weapon.get(weapon, 0) + 1
			if slot == 0:
				out.front = true
				front_shots += 1
			else:
				out.rear = true
				if is_mine:
					mines_dropped += 1
				else:
					rear_shots += 1
	return out


## How good firing this weapon is right now (0..1), from the targets' actual
## positions, directions and speeds.
func tactical_quality(weapon: int, me: Dictionary, targets: Array, ctx: Dictionary) -> float:
	match weapon:
		WeaponRules.Weapon.FRONT_MISSILE:
			return front_shot_quality(me, targets, ctx)
		WeaponRules.Weapon.REAR_MISSILE:
			return rear_shot_quality(me, targets, ctx)
		WeaponRules.Weapon.HOMING_MISSILE:
			return homing_quality(me, targets, ctx)
		WeaponRules.Weapon.SUPER_MISSILE:
			return super_quality(me, targets, ctx)
		WeaponRules.Weapon.MINE:
			return mine_quality(me, targets, ctx)
	return 0.0


## Rear missile: like a front shot, backwards. The missile flies at missile_speed
## while a follower drives into it, so the closing speed is the sum.
func rear_shot_quality(me: Dictionary, targets: Array, ctx: Dictionary) -> float:
	var back := -Vector2.from_angle(me.heading)
	var best := 0.0
	for t in targets:
		if t.wrecked:
			continue
		var rel: Vector2 = t.position - me.position
		var along := rel.dot(back)
		if along < 40.0 or along > params.attack_range:
			continue
		if params.opportunist and not _opportunity(me, t, along):
			continue
		var time: float = along / maxf(1.0, ctx.missile_speed - t.velocity.dot(back))
		var predicted: Vector2 = t.position + t.velocity * time - me.position
		var miss := absf(predicted.cross(back))
		var q := clampf(1.0 - miss / (ctx.hit_radius * 1.5), 0.0, 1.0) * (1.0 - 0.3 * along / params.attack_range)
		best = maxf(best, _with_grudge(q, t))
	return best


## Homing missile: it locks on the nearest car (in any direction), so the shot
## is only good when that car is ahead within the nose cone and in range.
func homing_quality(me: Dictionary, targets: Array, ctx: Dictionary) -> float:
	var nearest := {}
	var best_d: float = ctx.get("homing_range", 900.0)
	for t in targets:
		if t.wrecked:
			continue
		var d: float = me.position.distance_to(t.position)
		if d < best_d:
			best_d = d
			nearest = t
	if nearest.is_empty() or best_d > params.attack_range * 1.2:
		return 0.0
	var fwd := Vector2.from_angle(me.heading)
	var rel: Vector2 = nearest.position - me.position
	if params.opportunist and not _opportunity(me, nearest, rel.dot(fwd)):
		return 0.0
	var angle := absf(fwd.angle_to(rel))
	var cone := clampf(1.0 - (angle - deg_to_rad(20.0)) / deg_to_rad(75.0), 0.0, 1.0)
	var reach := clampf(1.0 - maxf(0.0, best_d - 450.0) / 450.0, 0.0, 1.0)
	if best_d < 50.0:
		reach *= 0.5  # too close to turn onto
	return cone * reach


## Super missile: it circles its car, so it pays when cars are (or are about to be)
## around the orbit. Needs super_min_targets cars nearby.
func super_quality(me: Dictionary, targets: Array, ctx: Dictionary) -> float:
	var orbit: float = ctx.get("super_orbit_radius", 56.0)
	var sum := 0.0
	var close := 0
	for t in targets:
		if t.wrecked:
			continue
		var d: float = me.position.distance_to(t.position)
		if d < orbit + 110.0:
			close += 1
		sum += clampf(1.0 - maxf(0.0, d - orbit) / 170.0, 0.0, 1.0)
	if close < params.super_min_targets:
		return 0.0
	return clampf(sum * 0.6, 0.0, 1.0)


## Opportunist test: slow, recovering or very close targets only.
func _opportunity(me: Dictionary, t: Dictionary, along: float) -> bool:
	return t.speed < me.speed * 0.6 or t.speed < 150.0 or absf(along) < 160.0


## Ammunition holding per slot (reserve / pacing traits), from the slot's own count.
# ------------------------------------------------------------- branches

## How far ahead of a branch the route (and a pit stop) is decided (px).
const PLAN_DISTANCE := 450.0


## The route this driver takes at s: its choice in a split, the pit lane when
## stopping (or already in it), else the racing road.
func route_at(s: float) -> int:
	if line.layout == null:
		return RacingLine.ROUTE_MAIN
	var k := line.layout.branch_at(s, line.center.length)
	if k < 0:
		return RacingLine.ROUTE_MAIN
	if k == _beside_branch:  # beside the divider: the lane it is really in, whatever the plan said
		var kind: String = line.layout.branches[k].kind
		if kind == "pit":
			return RacingLine.ROUTE_PIT if _beside_lane == 1 else RacingLine.ROUTE_MAIN
		return RacingLine.ROUTE_ALT if _beside_lane == 1 else RacingLine.ROUTE_MAIN
	if line.layout.branches[k].kind == "pit":
		return RacingLine.ROUTE_PIT if (pitting or _pit_latched) else RacingLine.ROUTE_MAIN
	return route_choice.get(k, RacingLine.ROUTE_MAIN)


## The lateral room at s on this driver's route, kept pass_margin inside
## (the whole road, symmetric, without branches: the old limits exactly).
func _room(s: float) -> Vector2:
	var b := line.bounds_at(s, route_at(s))
	if route_at(s) == RacingLine.ROUTE_PIT:  # beside the bays: their apron is room too (passing a stopped car)
		var pb: Dictionary = line.layout.branches[line.layout.pit_branch()]
		var apron := TrackLayout.bay_apron(pb, fposmod(s, line.center.length))
		if apron > 0.0:
			b = Vector2(b.x - apron, b.y) if int(pb.side) < 0 else Vector2(b.x, b.y + apron)
	var m := minf(params.pass_margin, maxf(0.0, (b.y - b.x) * 0.5 - 2.0))
	return Vector2(b.x + m, b.y - m)


## Speeds: an overridden pit limiter drives the pit lane at racing speeds.
func _speed_route(s: float) -> int:
	var r := route_at(s)
	return RacingLine.ROUTE_MAIN if r == RacingLine.ROUTE_PIT and _override_sent else r


## Decides each branch once per lap, PLAN_DISTANCE before it begins.
func _plan_branches(me: Dictionary, others: Array) -> void:
	var length := line.center.length
	for k in line.layout.branches.size():
		var b: Dictionary = line.layout.branches[k]
		var ahead := fposmod(float(b.from) - me.distance, length)
		if ahead <= 0.0 or ahead > PLAN_DISTANCE + me.speed * 0.6:
			continue
		var key := roundi((me.distance + ahead) / length)
		if _planned.get(k, -999) == key:
			continue
		_planned[k] = key
		if b.kind == "split":
			route_choice[k] = _choose_split(k, me, others)
			route_counts[route_choice[k]] = route_counts.get(route_choice[k], 0) + 1
		else:
			_plan_pit(me)


## A split: the quicker lane, unless traffic or temperament says otherwise.
func _choose_split(k: int, me: Dictionary, others: Array) -> int:
	var b: Dictionary = line.layout.branches[k]
	var length := line.center.length
	var d := line.layout.divider_at(float(b.from) + float(b.ramp) + TrackLayout.DIVIDER_NOSE + 1.0, length)
	var mid := (d.x + d.y) * 0.5 if d != Vector2.INF else 0.0
	var span: float = float(b.to) - me.distance + 300.0
	var traffic := [0, 0]
	var chase_lane := -1
	for o in others:
		var gap := _gap(me, o)
		if gap <= 0.0 or gap > span or o.get("wrecked", false):
			continue
		var lane := 0 if o.lateral < mid else 1
		traffic[lane] += 1
		if gap < 300.0 and chase_lane < 0:
			chase_lane = lane
	var best := RacingLine.ROUTE_MAIN
	var best_score := INF
	for lane in 2:
		var route := RacingLine.ROUTE_ALT if lane == 1 else RacingLine.ROUTE_MAIN
		var score: float = line.route_time(k, route) + params.route_traffic_weight * traffic[lane] \
			+ rng.randf_range(-1.0, 1.0) * params.route_whim
		if params.chase_aggression > 0.0 and lane == chase_lane:
			score -= 0.4  # follows a rival through the section
		if score < best_score:
			best_score = score
			best = route
	return best


## Pit strategy, once per lap before the pit entry: condition, laps to go,
## temperament (pitting below pit_threshold, earlier in long races; staying
## out anyway by pit_stay_out_chance); and whether to break the speed limit.
func _plan_pit(me: Dictionary) -> void:
	var pit: Dictionary = me.get("pit", {})
	pitting = false
	_gave_up = false
	_override_wanted = false
	if pit.is_empty() or not pit.get("open", false):
		return
	var condition: float = pit.get("condition", 1.0)
	var laps_left: int = pit.get("laps_left", 0)
	if laps_left < 2:
		return  # the last lap: nothing to gain
	var threshold := params.pit_threshold + 0.1 * clampf((laps_left - 3) / 10.0, 0.0, 1.0)
	if condition >= threshold:
		return
	if condition > 0.15 and rng.randf() < params.pit_stay_out_chance:
		return  # one more lap
	pitting = true
	pit_entries += 1
	var late_fight: bool = int(pit.get("position", 10)) <= 3 and laps_left <= 3
	var chance := params.pit_speeding * (3.0 if late_fight else 1.0)
	_override_wanted = rng.randf() < chance


## Keeps the pit route from the pit branch's start to its end once stopping.
func _update_pit_latch(s: float, me: Dictionary) -> void:
	var k := line.layout.branch_at(s, line.center.length)
	var in_pit_branch: bool = k >= 0 and line.layout.branches[k].kind == "pit"
	if in_pit_branch and pitting and not _pit_latched:
		_pit_latched = true
		_override_sent = false
		_gave_up = false
		_wait_left = params.pit_patience
	elif not in_pit_branch and _pit_latched:
		_pit_latched = false
		pitting = false
	elif _pit_latched and not me.get("pit", {}).get("in_lane", false):
		# missed the entry (pushed wide, blocked): give up this stop and race on
		var b: Dictionary = line.layout.branches[k]
		var w := fposmod(s, line.center.length)
		if w > float(b.from) + float(b.ramp) + TrackLayout.DIVIDER_NOSE + 20.0 and w < float(b.box):
			_pit_latched = false
			pitting = false
			missed_pits += 1


## Beside a divider, the car is committed to the lane it is in: its route
## follows that lane until the branch ends (a plan dropped or changed while in
## the other lane - a missed stop, a shove, a respawn - must never steer it
## into the divider).
var _beside_branch := -1
var _beside_lane := 0


func _update_beside(s: float, me: Dictionary) -> void:
	var d := line.layout.divider_at(s, line.center.length)
	var k := line.layout.branch_at(s, line.center.length)
	if d == Vector2.INF or k < 0:
		if k != _beside_branch:
			_beside_branch = -1
		return  # (on the ramps before / after the divider: keep the last lane until the branch ends)
	_beside_branch = k
	_beside_lane = 1 if float(me.lateral) > (d.x + d.y) * 0.5 else 0


## A car ahead that sits in a service bay while this driver is leaving the
## apron (or driving the through-lane): no reason to stop behind it.
func _parked_in_bay_ahead(me: Dictionary, ahead: Dictionary) -> bool:
	if line.layout == null or is_nan(_apron_exit(me)) or wants_bay(me):
		return false
	var b: Dictionary = line.layout.branches[line.layout.pit_branch()]
	var strip := line.layout.bay_strip(b, line.center.length)
	return (float(ahead.lateral) - strip.x) * signf(float(b.side)) > 0.0


## Leaving the bays (served, given up, or just on the apron): back to the
## middle of the through-lane at once (NAN = not on the apron).
func _apron_exit(me: Dictionary) -> float:
	var pb := line.layout.pit_branch()
	if pb < 0 or not me.get("pit", {}).get("in_lane", false):
		return NAN
	var b: Dictionary = line.layout.branches[pb]
	var strip := line.layout.bay_strip(b, line.center.length)
	var side := signf(float(b.side))
	if (float(me.lateral) - strip.x) * side < -4.0:
		return NAN  # in the through-lane already
	return strip.x - float(b.lane) * 0.5 * side


## Speed (px/s) a driver keeps while finishing its turn into the bay.
const BAY_CREEP := 26.0


## Wants a service bay on this pass: stopping, not yet served, not given up.
func wants_bay(me: Dictionary) -> bool:
	var pit: Dictionary = me.get("pit", {})
	return _pit_latched and pitting and not _gave_up and pit.get("open", false) and not pit.get("served", false)


## Still heading for a stop (also just before the pit branch, when the bay is chosen).
func stopping() -> bool:
	return pitting and not _gave_up


## Speed limit for a stop: brake to a standstill in its service bay, hold there
## during service, then drive on. With every bay taken: wait short of the bays
## (personality: pit_patience) for one to come free, else give up the stop.
## An overriding driver brakes late for its bay (it may arrive too fast).
func _pit_stop_speed(s: float, me: Dictionary, delta: float) -> float:
	if not wants_bay(me):
		return INF
	var pit: Dictionary = me.get("pit", {})
	var b: Dictionary = line.layout.branches[line.layout.pit_branch()]
	var w := fposmod(s, line.center.length)
	var decel := line.plan_decel * (1.35 if _override_sent else 1.0)
	var bay: int = pit.get("bay", -1)
	if bay < 0:  # every bay taken: wait before them, or drive on
		var stop_at := TrackLayout.bay_span(b).x - TrackLayout.BAY_TAPER - 30.0
		if _wait_left <= 0.0 or w > stop_at + 20.0:
			_gave_up = true
			pit_abandons += 1
			return INF
		if float(me.speed) < 20.0:
			if is_equal_approx(_wait_left, params.pit_patience):
				pit_waits += 1
			_wait_left -= delta
		return sqrt(2.0 * decel * maxf(0.0, stop_at - w))
	var to_bay: float = TrackLayout.bay_centre(b, bay) - w
	if int(pit.get("in_bay", -1)) == bay:
		return 0.0  # in its bay: stop here (short of the stub at the bay's far end)
	if to_bay < -float(b.box_length) * 0.4:
		return INF  # overshot: carry on (no reversing), no service this time
	# creep on while still turning in (stopping short of the bay would park it half outside)
	return maxf(BAY_CREEP, sqrt(2.0 * decel * maxf(0.0, to_bay - 6.0)))


## Aim lateral offset at arc distance s for a driver turning into its bay
## (NAN = follow the route): from the through-lane into the bay over the
## last stretch before it, and straight out again once served.
func _bay_aim(s: float, me: Dictionary) -> float:
	if line.layout == null:
		return NAN
	if not wants_bay(me):
		return _apron_exit(me)
	var bay: int = me.get("pit", {}).get("bay", -1)
	if bay < 0:
		return NAN
	var b: Dictionary = line.layout.branches[line.layout.pit_branch()]
	var strip := line.layout.bay_strip(b, line.center.length)
	var through := strip.x - float(b.lane) * 0.5 * signf(float(b.side))
	var c := TrackLayout.bay_centre(b, bay)
	var w := fposmod(s, line.center.length)
	# turn in by where the car itself is: only once it is past the bay before
	# (a car parked there), and fully in line with the bay just short of its centre
	var at := fposmod(float(me.distance), line.center.length)
	var half_bay: float = float(b.box_length) * 0.5
	var t := smoothstep(c - half_bay - 75.0, c - 25.0, at)
	var lateral := lerpf(through, (strip.x + strip.y) * 0.5, t)
	# never aim past the wall: the apron only opens up around the bays
	var sw := line.layout.side_widths_at(w, line.center.length)
	var edge := (sw.y - 30.0) if int(b.side) > 0 else (-sw.x + 30.0)
	return minf(lateral, edge) if int(b.side) > 0 else maxf(lateral, edge)

