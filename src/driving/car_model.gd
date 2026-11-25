class_name CarModel
extends RefCounted
## Pure, deterministic top-down driving model (no scene dependencies).
## Heading 0 points along +X. Steering rotates the car; velocity keeps its
## momentum and is pulled towards the heading by grip, which produces sliding.

enum ControlMode { FIRE_TO_ACCELERATE, FIRE_TO_BRAKE }

var params: DrivingParams
var control_mode: ControlMode = ControlMode.FIRE_TO_ACCELERATE
var position := Vector2.ZERO
var heading := 0.0
var velocity := Vector2.ZERO
## Extra rotation (rad/s) from being struck by another car; fades quickly.
var yaw_rate := 0.0
## Pit limiter (2026-11-17): top speed while set (INF = none). Above it the
## car slows smoothly (LIMITER_DECEL_SHARE of its braking), never abruptly.
var speed_cap := INF
const LIMITER_DECEL_SHARE := 0.6
## VoxelRacing (P003): grip multiplier from what is on the road under the car
## (debris, see DebrisField); 1.0 = the established HyperCars handling.
var grip_scale := 1.0


func _init(p_params: DrivingParams = null, p_mode: ControlMode = ControlMode.FIRE_TO_ACCELERATE) -> void:
	params = p_params if p_params != null else DrivingParams.new()
	control_mode = p_mode


func forward() -> Vector2:
	return Vector2.from_angle(heading)


func forward_speed() -> float:
	return velocity.dot(forward())


func lateral_speed() -> float:
	return velocity.dot(forward().orthogonal())


## True when the current input means "accelerate" in the active control mode.
func is_accelerating(fire: bool) -> bool:
	return fire if control_mode == ControlMode.FIRE_TO_ACCELERATE else not fire


## Deceleration applied when not accelerating, per control mode.
func braking_deceleration() -> float:
	return params.release_deceleration if control_mode == ControlMode.FIRE_TO_ACCELERATE else params.brake_deceleration


## Advances velocity and heading by delta. steer: -1 left, 0 none, +1 right.
func update(delta: float, steer: float, fire: bool) -> void:
	var steer_factor := 1.0
	if params.full_steer_speed > 0.0:
		steer_factor = clampf(velocity.length() / params.full_steer_speed, 0.0, 1.0)
	heading = wrapf(heading + clampf(steer, -1.0, 1.0) * deg_to_rad(params.turn_rate_degrees) * steer_factor * delta, -PI, PI)
	if yaw_rate != 0.0:  # knocked by another car (see resolve_car_collision)
		heading = wrapf(heading + yaw_rate * delta, -PI, PI)
		yaw_rate *= exp(-params.contact_yaw_damping * delta)
		if absf(yaw_rate) < 0.01:
			yaw_rate = 0.0

	var fwd_dir := forward()
	var side_dir := fwd_dir.orthogonal()
	var fwd := velocity.dot(fwd_dir)
	var side := velocity.dot(side_dir)

	if fwd > speed_cap:  # the pit limiter (only ever set in a pit lane / penalty): slow down smoothly
		var accelerating := is_accelerating(fire)
		var dec := params.brake_deceleration * LIMITER_DECEL_SHARE
		if not accelerating:
			dec = maxf(dec, braking_deceleration())  # braking anyway: whichever is stronger
		fwd = maxf(speed_cap if accelerating else 0.0, fwd - dec * delta)
	elif is_accelerating(fire):
		var top := minf(params.max_speed, speed_cap)
		if fwd < top:
			fwd = minf(fwd + params.acceleration * delta, top)
		else:
			fwd = move_toward(fwd, top, braking_deceleration() * delta)
	else:
		fwd = move_toward(fwd, 0.0, braking_deceleration() * delta)

	side *= exp(-params.grip * grip_scale * delta)
	velocity = fwd_dir * fwd + side_dir * side


## Moves position by velocity (used when no physics body integrates the motion).
func integrate(delta: float) -> void:
	position += velocity * delta


## Collision response against a wall with outward normal (pointing towards the car).
func apply_wall_collision(normal: Vector2) -> void:
	var into := velocity.dot(normal)
	if into >= 0.0:
		return
	var tangent := velocity - normal * into
	velocity = tangent * params.wall_tangent_retention - normal * into * params.wall_restitution


## Equal-mass contact between two cars. normal points from b towards a.
## Only the closing velocity along the normal changes, identically for both cars.
## With the contact point (and both cars' centres), each car is also turned a
## little by where it was struck (rear quarter most, nose least).
static func resolve_car_collision(a: CarModel, b: CarModel, normal: Vector2, contact := Vector2.INF,
		a_centre := Vector2.ZERO, b_centre := Vector2.ZERO) -> void:
	var closing := (a.velocity - b.velocity).dot(normal)
	if closing >= 0.0:
		return
	var restitution := (a.params.car_restitution + b.params.car_restitution) * 0.5
	var impulse := -(1.0 + restitution) * closing * 0.5
	a.velocity += normal * impulse
	b.velocity -= normal * impulse
	if contact != Vector2.INF:
		a.apply_contact_yaw(contact - a_centre, normal * impulse)
		b.apply_contact_yaw(contact - b_centre, -normal * impulse)


## Yaw from an impulse j (px/s) received at offset r (px) from the car's centre.
func apply_contact_yaw(r: Vector2, j: Vector2) -> void:
	if params.contact_yaw_factor <= 0.0:
		return
	var along := r.dot(forward()) / params.car_half_length  # -1 tail .. +1 nose
	var where := params.contact_front_factor
	if along < 0.0:
		where = lerpf(params.contact_front_factor, 1.0, clampf(-along / 0.6, 0.0, 1.0))
	var kick := params.contact_yaw_factor * where * r.cross(j) / (params.car_half_length * params.car_half_length)
	yaw_rate = clampf(yaw_rate + kick, -params.contact_yaw_max, params.contact_yaw_max)
