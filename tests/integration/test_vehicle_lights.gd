extends GutTest
## Vehicle lights (Stabilization 2026-11-22): the two headlights sit at the
## front corners and shine forward along the car's heading, the two red lights
## sit at the rear corners, in all eight headings and in both light modes
## (DYNAMIC VEHICLE LIGHTS on: 2D lights; off: glow sprites). The lamp anchors
## come from the car's logical outline (nose +X), never from the drawing: a
## custom body of any resolution gets exactly the same lamps. Brake lights
## brighten only while braking.

const MAIN_SCENE := preload("res://src/main/main.tscn")
const HEADINGS := [0.0, 45.0, 90.0, 135.0, 180.0, -135.0, -90.0, -45.0]

var _art_root := ""


func after_each() -> void:
	AssetResolver.test_root = ""
	CarArt.clear_cache()
	if _art_root != "":
		var f := _art_root.path_join("graphics/cars/body_player.png")
		DirAccess.remove_absolute(f)
		_art_root = ""


func _night(dynamic: bool) -> Node2D:
	var m := MAIN_SCENE.instantiate()
	m.presentation_enabled = true
	m.night = true
	m.dynamic_vehicle_lights = dynamic
	add_child_autofree(m)
	return m


## Poses the player's car at a heading (degrees) and lets the lights follow.
func _pose(m: Node2D, deg: float) -> void:
	var c: Car = m.car
	var at: Vector2 = m.track.path.point_at(300.0)
	c.place(Transform2D(deg_to_rad(deg), at))
	m.lighting._last_pos[0] = at
	await wait_process_frames(2)


## [front, side] of a world point relative to the car (px along its heading / to its right).
func _local(c: Car, p: Vector2) -> Vector2:
	var fwd := Vector2.from_angle(c.global_rotation)
	var d := p - c.global_position
	return Vector2(d.dot(fwd), d.dot(Vector2(-fwd.y, fwd.x)))  # (+Y = the car's right)


func _check_heading(m: Node2D, deg: float, dynamic: bool) -> void:
	await _pose(m, deg)
	var l: LightingPilot = m.lighting
	var c: Car = m.car
	var a := LightingPilot.lamp_anchors()
	var lenses: Array = l._lenses[0]
	for k in 4:
		var got := _local(c, lenses[k].global_position)
		assert_almost_eq(got, a[k], Vector2.ONE * 0.5, "%s lens %d at heading %d" % [LightingPilot.LAMP_NAMES[k], k, deg])
	assert_gt(_local(c, lenses[0].global_position).x, 20.0, "headlights at the front (heading %d)" % deg)
	assert_lt(_local(c, lenses[2].global_position).x, -20.0, "red lights at the rear (heading %d)" % deg)
	assert_gt(absf(_local(c, lenses[0].global_position).y - _local(c, lenses[1].global_position).y), 14.0, "two headlights, one per corner")
	# where the beam's light actually lands: the centre of the light / glow texture
	var beam_centre: Vector2
	var tail_centre: Vector2
	if dynamic:
		var head: PointLight2D = l._car_lights[0]
		var tail: PointLight2D = l._tail_lights[0]
		beam_centre = head.global_transform * head.offset
		tail_centre = tail.global_transform * tail.offset
	else:
		var b: Sprite2D = l._beam_sprites[0]
		var ts: Sprite2D = l._tail_sprites[0]
		beam_centre = b.global_transform * b.offset
		tail_centre = ts.global_transform * ts.offset
	var beam := _local(c, beam_centre)
	assert_gt(beam.x, 100.0, "beam shines ahead of the nose (heading %d): %s" % [deg, beam])
	assert_lt(absf(beam.y), 2.0, "beam straight along the heading")
	assert_lt(_local(c, tail_centre).x, -20.0, "red glow behind the car (heading %d)" % deg)


func test_lamps_and_beams_follow_every_heading_dynamic_lights() -> void:
	var m := _night(true)
	await wait_physics_frames(2)
	for deg in HEADINGS:
		await _check_heading(m, deg, true)


func test_lamps_and_beams_follow_every_heading_glow_sprites() -> void:
	var m := _night(false)
	await wait_physics_frames(2)
	for deg in HEADINGS:
		await _check_heading(m, deg, false)


func test_high_beam_stays_anchored_at_the_front() -> void:
	var m := _night(true)
	await wait_physics_frames(2)
	await _pose(m, 30.0)
	var l: LightingPilot = m.lighting
	var head: PointLight2D = l._car_lights[0]
	var dipped := _local(m.car, head.global_transform * head.offset).x
	l.set_process(false)
	l.high_beam[0] = 1.0
	l._high_beam_target[0] = 1.0
	l._frame = 1  # (not a high-beam re-evaluation frame for car 0)
	l._process(1.0 / 60.0)
	assert_gt(head.texture_scale, 1.3, "high beam")
	# the light texture is scaled about its centre: the offset grows with it, so
	# the beam still starts at the lamps (texture origin = the car centre)
	var origin_tex := Vector2(LightingPilot.BEAM_ORIGIN_X, head.texture.get_height() * 0.5)
	var origin_local := (origin_tex - Vector2(head.texture.get_size()) * 0.5) * head.texture_scale + head.offset
	assert_almost_eq(origin_local, Vector2.ZERO, Vector2.ONE * 0.5, "the beam still starts at the car, not behind it")
	assert_gt(_local(m.car, head.global_transform * head.offset).x, dipped, "and reaches further ahead")


func test_custom_body_of_any_size_gets_the_same_lamps() -> void:
	_art_root = ProjectSettings.globalize_path("user://test_run/lights_art_%d" % randi())
	DirAccess.make_dir_recursive_absolute(_art_root.path_join("graphics/cars"))
	var img := Image.create(512, 288, false, Image.FORMAT_RGBA8)  # 4x the template, no painted lamps at all
	img.fill(Color(0.2, 0.7, 0.3, 1.0))
	img.save_png(_art_root.path_join("graphics/cars/body_player.png"))
	AssetResolver.test_root = _art_root
	CarArt.clear_cache()
	var m := _night(true)
	await wait_physics_frames(2)
	assert_eq(m.car.sprite.texture.get_width(), 512, "the custom body is used")
	for deg in [0.0, 90.0, -135.0]:
		await _check_heading(m, deg, true)


func test_brake_lights_brighten_only_when_braking() -> void:
	var m := _night(true)
	await wait_physics_frames(2)
	await _pose(m, 0.0)
	var l: LightingPilot = m.lighting
	l.set_process(false)  # (driven by hand below: one step = one 60 Hz frame)
	var c: Car = m.car
	var fwd := Vector2.from_angle(c.global_rotation)
	var dt := 1.0 / 60.0
	var step := func(px: float) -> void:
		c.global_position += fwd * px
		l._process(dt)
	step.call(0.0)
	assert_eq(l.braking[0], 0, "standing still: no brake lights")
	assert_almost_eq(l._tail_lights[0].energy, LightingPilot.TAIL_ENERGY, 0.001, "running lights")
	assert_almost_eq(l._lenses[0][2].modulate.a, 0.7, 0.01)
	for k in 60:  # accelerate to a steady 300 px/s
		step.call(minf(5.0, k * 0.25))
		assert_eq(l.braking[0], 0, "speeding up or cruising: no brake lights (frame %d)" % k)
	var px := 5.0
	var braked := false
	for k in 20:  # slow hard
		px = maxf(px - 0.35, 0.6)
		step.call(px)
		if l.braking[0] == 1:
			braked = true
			assert_almost_eq(l._tail_lights[0].energy, LightingPilot.BRAKE_ENERGY, 0.001, "brighter while braking")
			assert_gt(l._lenses[0][2].modulate.a, 0.9)
	assert_true(braked, "brake lights while slowing hard")
	for k in 30:  # steady again
		step.call(0.6)
	assert_eq(l.braking[0], 0, "steady again: back to running lights")
	assert_almost_eq(l._tail_lights[0].energy, LightingPilot.TAIL_ENERGY, 0.001)


func test_lamp_outline_is_the_car_art_contract() -> void:
	for name in [AssetCatalog.CAR_PLAYER, AssetCatalog.body_of(AssetCatalog.CAR_PLAYER), AssetCatalog.CAR_JUNKER]:
		assert_eq(AssetCatalog.SPECS[name].display_size, LightingPilot.CAR_SIZE, name)
	var a := LightingPilot.lamp_anchors()
	assert_eq(a.size(), 4)
	for k in 2:
		assert_between(a[k].x, 0.0, LightingPilot.CAR_SIZE.x * 0.5, "headlight inside the front half")
		assert_between(a[k + 2].x, -LightingPilot.CAR_SIZE.x * 0.5, 0.0, "red light inside the rear half")
	assert_lt(a[0].y, 0.0, "front-left on the left (-Y)")
	assert_gt(a[1].y, 0.0, "front-right on the right (+Y)")


## Headlight colour (2026-11-23): the player's own headlights take the chosen
## palette colour in both light modes; rivals keep the standard colour; the
## lamp anchors and the beam direction are those of every colour; the rear
## lights stay red. The palette keeps a near-white core (readable roads).
func _check_colour(dynamic: bool) -> void:
	var m := MAIN_SCENE.instantiate()
	m.presentation_enabled = true
	m.night = true
	m.dynamic_vehicle_lights = dynamic
	m.headlight_color = 2  # ICE BLUE (the setting, passed in by the game)
	add_child_autofree(m)
	await wait_process_frames(3)
	var l: LightingPilot = m.lighting
	var ice := LightingPilot.headlight_color(2)
	assert_eq(l.head_color_of(0), ice)
	assert_eq(l.head_color_of(3), LightingPilot.HEADLIGHT_COLOR, "rivals: the standard colour")
	if dynamic:
		assert_eq(l._car_lights[0].color, ice)
		assert_eq(l._car_lights[3].color, LightingPilot.HEADLIGHT_COLOR)
		assert_eq(l._tail_lights[0].color, LightingPilot.TAIL_COLOR, "rear lights stay red")
	else:
		assert_eq(Color(l._beam_sprites[0].modulate, 1.0), ice)
		assert_eq(Color(l._beam_sprites[3].modulate, 1.0), Color(LightingPilot.HEADLIGHT_COLOR, 1.0))
		assert_eq(Color(l._tail_sprites[0].modulate, 1.0), Color(LightingPilot.TAIL_COLOR, 1.0), "rear glow stays red")
	assert_eq(l._lenses[0][0].modulate, LightingPilot.lens_color(ice), "front lenses: tinted round a white core")
	await _check_heading(m, 45.0, dynamic)  # anchors and beam direction unchanged


func test_headlight_colour_dynamic_lights() -> void:
	await _check_colour(true)


func test_headlight_colour_glow_sprites() -> void:
	await _check_colour(false)


func test_headlight_palette_is_subtle_and_saved() -> void:
	assert_eq(LightingPilot.headlight_color(0), LightingPilot.HEADLIGHT_COLOR, "the default is today's colour")
	for k in LightingPilot.HEADLIGHT_PALETTE.size():
		var c := LightingPilot.headlight_color(k)
		assert_gt(minf(c.r, minf(c.g, c.b)), 0.35, "%s is a tint, not a saturated colour" % LightingPilot.headlight_name(k))
		var lens := LightingPilot.lens_color(c)
		assert_gt(minf(lens.r, minf(lens.g, lens.b)), 0.6, "%s lenses keep a near-white core" % LightingPilot.headlight_name(k))
	var path := "user://test_run/lights_settings_%d.cfg" % randi()
	var s := AudioSettings.new(path)
	assert_eq(s.headlight_color, 0)
	s.headlight_color = 3
	s.save_settings()
	var again := AudioSettings.new(path)
	again.load_settings()
	assert_eq(again.headlight_color, 3, "saved")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
