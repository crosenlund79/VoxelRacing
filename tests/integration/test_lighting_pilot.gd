extends GutTest
## Lighting pilot (experiment): toggles with L, stays presentation-only (a race
## is bit-identical with lighting on or off), adds no collision, and leaves the
## HUD layer undimmed.

const MAIN_SCENE := preload("res://src/main/main.tscn")


func after_each() -> void:
	Input.action_release(PlayerControls.TOGGLE_LIGHTING)


func test_lighting_does_not_change_the_race() -> void:
	var off := ProbeRunner.run(["mode=race", "ticks=900", "weapons=1", "lighting=0"])
	var on := ProbeRunner.run(["mode=race", "ticks=900", "weapons=1", "lighting=1"])
	assert_eq(off.length(), 32, off)
	assert_eq(on, off, "normal race with weapons")
	var s_off := ProbeRunner.run(["mode=spectate", "ticks=900", "weapons=0", "lighting=0"])
	var s_on := ProbeRunner.run(["mode=spectate", "ticks=900", "weapons=0", "lighting=1"])
	assert_eq(s_on, s_off, "spectating, no guns")


func test_toggle_with_l_and_light_setup() -> void:
	var m := MAIN_SCENE.instantiate()
	add_child_autofree(m)
	await wait_physics_frames(2)
	var l: LightingPilot = m.lighting
	assert_false(l.enabled, "off by default")
	Input.action_press(PlayerControls.TOGGLE_LIGHTING)
	await wait_physics_frames(2)
	Input.action_release(PlayerControls.TOGGLE_LIGHTING)
	assert_true(l.enabled)
	assert_eq(l._lamps.size(), LightingPilot.LAMP_COUNT, "ten trackside lamps")
	assert_eq(l._car_lights.size(), 10, "one twin-beam headlight light per car")
	assert_eq(l._tail_lights.size(), 10, "one twin-lamp tail light per car")
	assert_eq(l._lenses.size(), 10, "four lamp lenses per car")
	assert_lte(l.light_count(), 34, "limited light count")
	assert_eq(l.find_children("*", "CollisionObject2D", true, false).size(), 0)
	assert_eq(l.find_children("*", "CanvasModulate", true, false).size(), 1)
	assert_true(m.hud is CanvasLayer, "HUD on its own layer, unaffected by the world tint")


func test_lamps_stand_clear_of_the_road() -> void:
	var m := MAIN_SCENE.instantiate()
	add_child_autofree(m)
	await wait_physics_frames(2)
	var half: float = m.track.layout.road_width * 0.5
	for s in m.lighting._lamp_sprites:
		var p: Dictionary = m.track.path.project(s.global_position)
		assert_gt(absf(p.lateral), half, "lamp post off the road")


func _night(dynamic: bool) -> Node2D:
	var m := MAIN_SCENE.instantiate()
	m.presentation_enabled = true
	m.night = true
	m.dynamic_vehicle_lights = dynamic
	add_child_autofree(m)
	return m


func test_fallback_uses_no_vehicle_light_passes() -> void:
	var m := _night(false)
	await wait_physics_frames(2)
	var l: LightingPilot = m.lighting
	assert_true(l.enabled)
	assert_eq(l._car_lights.size() + l._tail_lights.size(), 0, "no 2D lights for the cars")
	assert_eq(l._beam_sprites.size(), 10, "an additive beam per car")
	assert_eq(l._tail_sprites.size(), 10)
	assert_eq(l._lenses.size(), 10, "lamp lenses in both modes")


func test_brake_lights_and_high_beams() -> void:
	var m := _night(true)
	await wait_physics_frames(2)
	var l: LightingPilot = m.lighting
	var c: Car = m.car
	var t: Track = m.track
	m.start_race()
	await wait_physics_frames(2)
	# hold every rival far behind so nobody is ahead of the player in the beam
	for i in range(1, m.cars.size()):
		m.cars[i].visible = false
	# the longest straight: the high beam comes on at speed
	var s := _straight_start(t)
	var tan := t.path.tangent_at(s)
	c.place(Transform2D(tan.angle(), t.path.point_at(s)))
	m.progress[0].reset(c.global_position)
	l._last_pos[0] = c.global_position
	l._speed[0] = m.driving_params.max_speed
	c.model.velocity = tan * m.driving_params.max_speed
	Input.action_press(PlayerControls.FIRE)
	await wait_seconds(0.8)
	assert_gt(l.high_beam[0], 0.5, "high beam on a clear straight at speed")
	assert_gt(l._car_lights[0].texture_scale, 1.2, "a longer beam")
	# a car right ahead: the beam dips
	var other: Car = m.cars[1]
	other.visible = true
	other.place(Transform2D(tan.angle(), c.global_position + tan * 260.0))
	await wait_seconds(0.8)
	assert_lt(l.high_beam[0], 0.5, "dipped for the car ahead")
	# lift off and brake: brake lights
	Input.action_release(PlayerControls.FIRE)
	var braked := false
	for k in 30:
		await wait_physics_frames(1)
		await wait_process_frames(1)
		braked = braked or l.braking[0] == 1
	assert_true(braked, "brake lights while slowing hard")
	assert_eq(l._tail_lights[0].energy if l.braking[0] == 1 else LightingPilot.BRAKE_ENERGY, LightingPilot.BRAKE_ENERGY)


func _straight_start(t: Track) -> float:
	var best := 0.0
	var best_len := 0.0
	var s := 0.0
	var run := 0.0
	while s < t.path.length:
		if absf(t.path.tangent_at(s).angle_to(t.path.tangent_at(s + 40.0))) < 0.02:
			run += 40.0
			if run > best_len:
				best_len = run
				best = s - run
		else:
			run = 0.0
		s += 40.0
	return best + 40.0


func after_all() -> void:
	Input.action_release(PlayerControls.FIRE)
