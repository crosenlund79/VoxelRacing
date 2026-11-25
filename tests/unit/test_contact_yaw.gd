extends GutTest
## Aggressive contact: a car struck behind its centre (the rear quarter) is
## turned more than one struck at the nose; harder hits turn more; the knock
## is capped and fades; the same rules for every car; off at factor 0.

var _p: DrivingParams


func before_each() -> void:
	_p = (load("res://src/driving/default_driving_params.tres") as DrivingParams).duplicate()


func _car() -> CarModel:
	var m := CarModel.new(_p)
	m.heading = 0.0  # facing +X
	return m


func test_rear_quarter_turns_more_than_the_nose() -> void:
	var rear := _car()
	var nose := _car()
	var side := Vector2(0, -40)  # struck from the side
	rear.apply_contact_yaw(Vector2(-28, 18), side)
	nose.apply_contact_yaw(Vector2(28, 18), side)
	assert_ne(rear.yaw_rate, 0.0)
	assert_gt(absf(rear.yaw_rate), absf(nose.yaw_rate) * 2.5, "the tail is the easy side to rotate")
	assert_almost_eq(absf(nose.yaw_rate) / absf(rear.yaw_rate), _p.contact_front_factor, 0.02)


func test_harder_hits_turn_more_and_are_capped() -> void:
	var soft := _car()
	var hard := _car()
	var huge := _car()
	soft.apply_contact_yaw(Vector2(-28, 18), Vector2(-20, 0))
	hard.apply_contact_yaw(Vector2(-28, 18), Vector2(-60, 0))
	huge.apply_contact_yaw(Vector2(-28, 18), Vector2(-5000, 0))
	assert_gt(absf(hard.yaw_rate), absf(soft.yaw_rate) * 2.5)
	assert_almost_eq(absf(huge.yaw_rate), _p.contact_yaw_max, 0.0001, "never more than the cap")


func test_a_square_hit_does_not_rotate() -> void:
	var m := _car()
	m.apply_contact_yaw(Vector2(-32, 0), Vector2(200, 0))
	assert_eq(m.yaw_rate, 0.0)


func test_the_knock_fades_and_never_becomes_a_spin() -> void:
	var m := _car()
	m.velocity = Vector2(300, 0)
	m.apply_contact_yaw(Vector2(-28, 18), Vector2(-5000, 0))  # the hardest possible knock
	var turned := 0.0
	var h0 := m.heading
	for i in 180:
		m.update(1.0 / 60.0, 0.0, true)  # no counter-steering at all
	turned = absf(angle_difference(h0, m.heading))
	assert_lt(turned, deg_to_rad(30.0), "at most a recoverable twitch (%.1f deg)" % rad_to_deg(turned))
	assert_gt(turned, deg_to_rad(10.0), "but noticeable")
	assert_eq(m.yaw_rate, 0.0, "faded out")


func test_off_at_factor_zero_and_ordinary_driving_is_untouched() -> void:
	_p.contact_yaw_factor = 0.0
	var m := _car()
	m.apply_contact_yaw(Vector2(-28, 18), Vector2(-150, 0))
	assert_eq(m.yaw_rate, 0.0)
	var a := CarModel.new(load("res://src/driving/default_driving_params.tres"))
	var b := CarModel.new(_p)
	for i in 120:
		a.update(1.0 / 60.0, 1.0 if i % 30 < 10 else 0.0, true)
		b.update(1.0 / 60.0, 1.0 if i % 30 < 10 else 0.0, true)
	assert_eq(a.heading, b.heading, "steering, throttle and grip are unchanged")
	assert_eq(a.velocity, b.velocity)


func test_collision_resolution_turns_both_cars_by_their_own_contact() -> void:
	var front := _car()  # the struck car, ahead
	var back := _car()  # the rammer
	front.velocity = Vector2(150, 0)
	back.velocity = Vector2(400, 0)
	var a_centre := Vector2(0, 0)
	var b_centre := Vector2(-60, 20)
	var contact := Vector2(-30, 14)  # the struck car's left rear corner, the rammer's right front
	CarModel.resolve_car_collision(front, back, Vector2(1, 0), contact, a_centre, b_centre)
	assert_gt(absf(front.yaw_rate), absf(back.yaw_rate) * 2.0, "the car hit in the rear quarter turns most")
	assert_gt(front.velocity.x, 150.0, "and is pushed on as before")
