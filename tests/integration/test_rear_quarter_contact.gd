extends GutTest
## Rear-quarter contact in the race scene: a car tagged on its rear corner is
## knocked off line by a controlled amount and recovers; a square push from
## behind and a nudge do (almost) nothing; humans and rivals obey the same
## rules; the front wheels show the steering more clearly (visual only).

const MAIN_SCENE := preload("res://src/main/main.tscn")
const P := RaceSession.PLAYER_ID

var _main: Node2D


class Drive extends DriverInput:
	var throttle := true
	func _init(t: bool) -> void:
		throttle = t
	func drive(_r: Node, _s: float) -> Dictionary:
		return {"steer": 0.0, "fire": throttle}


func after_each() -> void:
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0
	Engine.max_physics_steps_per_frame = 8


func _make() -> void:
	_main = MAIN_SCENE.instantiate()
	_main.presentation_enabled = false
	add_child_autofree(_main)
	await wait_physics_frames(2)
	_main.start_race()
	await wait_physics_frames(2)
	for id in range(1, 10):
		_main.cars[id].active = false
		_main.cars[id].place(Transform2D(0.0, Vector2(-9000 - id * 300, -9000)))


func _put(id: int, s: float, lateral: float, speed: float, input: DriverInput) -> void:
	var path: ClosedPath = _main.track.path
	var tan := path.tangent_at(s)
	var c: Car = _main.cars[id]
	c.place(Transform2D(tan.angle(), path.point_at(s) + tan.orthogonal() * lateral))
	c.model.velocity = tan * speed
	c.active = true
	_main.progress[id].reset(c.global_position)
	_main.inputs[id] = input


## The victim (rolling straight) is struck by the rammer from behind, offset
## sideways by `offset`; returns the victim's largest heading change (deg).
func _ram(victim: int, rammer: int, offset: float, closing: float) -> float:
	await _make()
	_put(victim, 700.0, 0.0, 150.0, Drive.new(false))
	_put(rammer, 610.0, offset, 150.0 + closing, Drive.new(false))
	var h0: float = _main.cars[victim].model.heading
	var most := 0.0
	for f in 120:
		await wait_physics_frames(1)
		most = maxf(most, absf(angle_difference(h0, _main.cars[victim].model.heading)))
	_main.queue_free()
	await wait_physics_frames(2)
	return rad_to_deg(most)


func test_a_rear_quarter_hit_unsettles_and_a_square_push_does_not() -> void:
	var quarter := await _ram(5, 3, 26.0, 250.0)
	var square := await _ram(5, 3, 0.0, 250.0)
	var nudge := await _ram(5, 3, 26.0, 70.0)
	assert_gt(quarter, 8.0, "a hard rear-quarter hit knocks the car off line (%.1f deg)" % quarter)
	assert_lt(quarter, 30.0, "but never spins it")
	assert_lt(square, 1.0, "a square push only pushes")
	assert_lt(nudge, quarter * 0.5, "a nudge does little")


func test_humans_and_rivals_respond_the_same() -> void:
	var rival_hit := await _ram(5, 3, 26.0, 220.0)
	var player_hit := await _ram(P, 3, 26.0, 220.0)
	assert_almost_eq(player_hit, rival_hit, 0.5, "the same rules for the player and the rivals")


func test_a_knocked_rival_recovers_its_line() -> void:
	await _make()
	var victim := 4
	_put(victim, 700.0, 0.0, 300.0, AiDriverInput.new(victim, _main.drivers[victim]))
	_main.inputs[victim].begin_race(1)
	_main.cars[victim].model.apply_contact_yaw(Vector2(-28, 18).rotated(_main.cars[victim].model.heading),
		Vector2(-400, 0).rotated(_main.cars[victim].model.heading))
	await wait_seconds(2.5)
	var s: float = fposmod(_main.progress[victim].distance, _main.track.path.length)
	var road: float = _main.track.path.tangent_at(s).angle()
	assert_lt(absf(angle_difference(road, _main.cars[victim].model.heading)), deg_to_rad(25.0), "back on its line")
	assert_lt(absf(_main.progress[victim].lateral), _main.track.layout.road_width * 0.5, "still on the road")


func test_front_wheels_turn_further_visually_only() -> void:
	var layout: WheelLayout = load("res://src/presentation/default_wheel_layout.tres")
	assert_gte(layout.max_steer_degrees, 22.0, "clearly visible steering")
	assert_lte(layout.max_steer_degrees, 34.0, "believable, not cartoonish (30 since 2026-11-22)")
	assert_almost_eq(rad_to_deg(CarWheels.steer_angle(layout, 1.0)), layout.max_steer_degrees, 0.001)
	assert_eq((load("res://src/driving/default_driving_params.tres") as DrivingParams).turn_rate_degrees, 210.0,
		"the driving model's steering is unchanged")
