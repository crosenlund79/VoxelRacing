extends GutTest
## CarModel: steering, both control modes, momentum/sliding, wall response, determinism.

const DT := 1.0 / 60.0


func _params() -> DrivingParams:
	var p := DrivingParams.new()
	p.max_speed = 400.0
	p.acceleration = 200.0
	p.release_deceleration = 150.0
	p.brake_deceleration = 500.0
	p.turn_rate_degrees = 180.0
	p.full_steer_speed = 0.0
	p.grip = 4.0
	p.wall_restitution = 0.5
	p.wall_tangent_retention = 0.8
	return p


func _run(model: CarModel, seconds: float, steer: float, fire: bool) -> void:
	for i in int(round(seconds / DT)):
		model.update(DT, steer, fire)
		model.integrate(DT)


func test_fire_to_accelerate_fire_held_accelerates_along_heading() -> void:
	var m := CarModel.new(_params(), CarModel.ControlMode.FIRE_TO_ACCELERATE)
	m.heading = PI / 2.0
	m.update(DT, 0.0, true)
	assert_almost_eq(m.forward_speed(), 200.0 * DT, 0.001)
	assert_almost_eq(m.velocity.normalized().dot(Vector2.DOWN), 1.0, 0.0001, "moves where the car points")


func test_fire_to_accelerate_release_brakes_automatically() -> void:
	var m := CarModel.new(_params(), CarModel.ControlMode.FIRE_TO_ACCELERATE)
	m.velocity = Vector2(300, 0)
	m.update(DT, 0.0, false)
	assert_almost_eq(m.forward_speed(), 300.0 - 150.0 * DT, 0.001)


func test_fire_to_brake_accelerates_without_fire() -> void:
	var m := CarModel.new(_params(), CarModel.ControlMode.FIRE_TO_BRAKE)
	m.update(DT, 0.0, false)
	assert_almost_eq(m.forward_speed(), 200.0 * DT, 0.001)


func test_fire_to_brake_fire_applies_stronger_braking() -> void:
	var m := CarModel.new(_params(), CarModel.ControlMode.FIRE_TO_BRAKE)
	m.velocity = Vector2(300, 0)
	m.update(DT, 0.0, true)
	assert_almost_eq(m.forward_speed(), 300.0 - 500.0 * DT, 0.001)


func test_default_params_brake_is_stronger_than_release() -> void:
	var p: DrivingParams = load("res://src/driving/default_driving_params.tres")
	assert_gt(p.brake_deceleration, p.release_deceleration)


func test_speed_is_capped_at_max_speed() -> void:
	var m := CarModel.new(_params())
	_run(m, 5.0, 0.0, true)
	assert_almost_eq(m.forward_speed(), 400.0, 0.001)


func test_braking_stops_without_reversing() -> void:
	var m := CarModel.new(_params())
	m.velocity = Vector2(50, 0)
	_run(m, 2.0, 0.0, false)
	assert_eq(m.velocity, Vector2.ZERO)


func test_steering_is_car_relative_and_uses_turn_rate() -> void:
	var m := CarModel.new(_params())
	m.update(0.5, 1.0, false)
	assert_almost_eq(m.heading, PI / 2.0, 0.0001, "right turns clockwise on screen (+Y)")
	m.update(0.5, -1.0, false)
	assert_almost_eq(m.heading, 0.0, 0.0001)


func test_no_steer_keeps_heading() -> void:
	var m := CarModel.new(_params())
	m.heading = 1.0
	_run(m, 1.0, 0.0, true)
	assert_almost_eq(m.heading, 1.0, 0.00001)


func test_full_steer_speed_scales_turning_at_low_speed() -> void:
	var p := _params()
	p.full_steer_speed = 100.0
	var m := CarModel.new(p)
	m.update(0.1, 1.0, false)
	assert_almost_eq(m.heading, 0.0, 0.00001, "no turning at rest when scaling is enabled")
	m.velocity = Vector2(50, 0)
	m.update(0.1, 1.0, true)
	assert_almost_eq(m.heading, deg_to_rad(180.0) * 0.5 * 0.1, 0.002)


func test_momentum_makes_car_slide_after_turning() -> void:
	var m := CarModel.new(_params())
	m.velocity = Vector2(400, 0)
	m.update(DT, 1.0, true)
	assert_gt(absf(m.lateral_speed()), 1.0, "velocity lags the new heading")


func test_grip_decays_sideways_velocity() -> void:
	var m := CarModel.new(_params())
	m.velocity = Vector2(0, 100)  # purely sideways relative to heading 0
	m.update(0.25, 0.0, false)
	assert_almost_eq(absf(m.lateral_speed()), 100.0 * exp(-4.0 * 0.25), 0.01)


func test_wall_collision_bounces_and_keeps_some_tangent_speed() -> void:
	var m := CarModel.new(_params())
	m.velocity = Vector2(100, -200)  # moving up into a wall whose normal points down
	m.apply_wall_collision(Vector2.DOWN)
	assert_almost_eq(m.velocity.x, 80.0, 0.001)
	assert_almost_eq(m.velocity.y, 100.0, 0.001)


func test_wall_collision_ignores_motion_away_from_wall() -> void:
	var m := CarModel.new(_params())
	m.velocity = Vector2(100, 50)
	m.apply_wall_collision(Vector2.DOWN)
	assert_eq(m.velocity, Vector2(100, 50))


func test_model_is_deterministic() -> void:
	var a := CarModel.new(_params())
	var b := CarModel.new(_params())
	for i in 240:
		var steer := float((i / 30) % 3 - 1)
		var fire := (i % 50) < 35
		a.update(DT, steer, fire)
		a.integrate(DT)
		b.update(DT, steer, fire)
		b.integrate(DT)
	assert_eq(a.position, b.position)
	assert_eq(a.heading, b.heading)
