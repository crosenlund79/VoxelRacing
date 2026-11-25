extends GutTest
## Two Car scenes under physics: cars never pass through each other, contact
## is symmetric (equal masses, shared restitution) and is reported.

const CAR_SCENE := preload("res://src/driving/car.tscn")

var _a: Car
var _b: Car


func _spawn(pos: Vector2, heading: float) -> Car:
	var c: Car = CAR_SCENE.instantiate()
	# Position before entering the tree so the physics server starts with it
	# (as on the race grid); avoids a stale overlap at the origin.
	c.position = pos
	c.rotation = heading
	add_child_autofree(c)
	c.setup(DrivingParams.new(), CarModel.ControlMode.FIRE_TO_ACCELERATE, null)
	c.place(Transform2D(heading, pos))
	c.active = true
	return c


func before_each() -> void:
	_a = _spawn(Vector2(0, 0), 0.0)
	_b = _spawn(Vector2(200, 0), PI)


func test_head_on_cars_bounce_apart_without_overlapping() -> void:
	watch_signals(_a)
	watch_signals(_b)
	_a.model.velocity = Vector2(200, 0)
	_b.model.velocity = Vector2(-200, 0)
	await wait_physics_frames(40)
	assert_lt(_a.global_position.x + 30.0, _b.global_position.x - 30.0 + 2.0, "bodies stay apart")
	assert_lte(_a.model.velocity.x, 0.0, "A pushed back")
	assert_gte(_b.model.velocity.x, 0.0, "B pushed back")
	assert_true(get_signal_emit_count(_a, "car_hit") + get_signal_emit_count(_b, "car_hit") > 0)


func test_rear_end_contact_transfers_speed_to_car_ahead() -> void:
	_b.queue_free()
	_b = _spawn(Vector2(120, 0), 0.0)
	await wait_physics_frames(2)
	_a.model.velocity = Vector2(300, 0)
	_b.model.velocity = Vector2(50, 0)
	await wait_physics_frames(15)
	assert_gt(_b.model.forward_speed(), 50.0, "car ahead is shoved forward")
	assert_lt(_a.global_position.x, _b.global_position.x)


func test_resolve_is_symmetric_and_conserves_momentum() -> void:
	var p := DrivingParams.new()
	var a := CarModel.new(p)
	var b := CarModel.new(p)
	a.velocity = Vector2(300, 20)
	b.velocity = Vector2(-100, 0)
	var total := a.velocity + b.velocity
	CarModel.resolve_car_collision(a, b, Vector2.LEFT)
	assert_almost_eq(a.velocity + b.velocity, total, Vector2(0.001, 0.001))
	assert_almost_eq(a.velocity.x - b.velocity.x, -(400.0) * p.car_restitution, 0.001)
	assert_almost_eq(a.velocity.y, 20.0, 0.001, "tangential speed untouched")


func test_separating_cars_are_not_changed() -> void:
	var a := CarModel.new()
	var b := CarModel.new()
	a.velocity = Vector2(-50, 0)
	b.velocity = Vector2(50, 0)
	CarModel.resolve_car_collision(a, b, Vector2.LEFT)
	assert_eq(a.velocity, Vector2(-50, 0))
	assert_eq(b.velocity, Vector2(50, 0))
