class_name VoxelStage
extends Node3D
## VoxelRacing: the 3D voxel presentation of a HyperCars race.
##
## HyperCars' 2D race runs exactly as before (physics, AI, rules, audio, HUD).
## This node mirrors it as a voxel miniature:
##   * the 2D world visuals (track, scenery, car sprites, night lights) are
##     culled from the screen with canvas visibility layers, nothing is freed
##     or changed in the simulation;
##   * VoxelTrack converts the circuit, VoxelProps the scenery, VoxelCars the
##     cars; every frame the 3D cars follow the 2D cars (plus bridge height,
##     jump height, body roll / pitch, steering and rolling wheels);
##   * an orthographic camera looks down at the same point as the 2D camera.
##     With pitch only (no yaw) the ground plane maps to the screen by an
##     affine transform, so the 2D camera gets the matching non-uniform zoom
##     (k, k * sin(pitch)) and every remaining 2D effect (smoke, sparks,
##     missiles, mines, explosions, markers) stays exactly where it belongs;
##   * tyre marks (HyperCars' decal layer) render each frame into a small
##     viewport that the terrain shader samples per voxel, so they lie on the
##     road under the cars;
##   * day / night follows the game's TIME setting and the L key (LightingPilot).
## Keys: V cycles the camera presets.

## Canvas visibility layers (bit values): the 2D world hidden in voxel mode,
## and the ground decals drawn only into the decal viewport.
const HIDE_LAYER := 1 << 9
const DECAL_LAYER := 1 << 8
## Camera presets: pitch (degrees from the ground), zoom, name.
## Tilt-shift: depth-of-field blur at the far top / bottom of the screen
## (the pitched orthographic camera sees depth change with screen height).
const VIEWS := [
	[58.0, 1.22, "MINIATURE", 1.7],
	[72.0, 1.12, "HIGH", 0.0],
	[44.0, 1.34, "LOW", 2.2],
	[90.0, 1.0, "TOP-DOWN", 0.0],
]
const CAMERA_DISTANCE := 48.0
## Decal viewport (tyre marks): size, and how much more ground it covers than the screen.
const DECAL_SIZE := Vector2i(1024, 600)
const DECAL_MARGIN := 1.18

## Off for headless runs (tests) or when the player chose the 2D look.
static var enabled := true
## The camera preset lasts for the whole session.
static var view_index := 0

var main: Node2D
var vtrack: VoxelTrack
var camera: Camera3D
var _tilt: MeshInstance3D
const TILT_SHADER := preload("res://src/voxel/shaders/tilt_shift.gdshader")
var sun: DirectionalLight3D
var world_env: WorldEnvironment
var decal_vp: SubViewport
var ready_3d := false
var cars3d: Array[Dictionary] = []
var race_fx: VoxelRaceFx
## Action replays (races only, not Battle Royale).
var recorder: ReplayRecorder
var replay: ReplayTheater
## Emitted once the voxel world is complete (the loading race finishes).
signal world_ready
var build_msec := 0
var _cars_part := 0.0
var _props_part := 0.0
var lamps3d: Array[Light3D] = []
var _night := -1
var _hint: Label
var _hint_left := 0.0
var _saved_mask := 0
var _texture_names: Dictionary = {}
var _rng := RandomNumberGenerator.new()


static func available() -> bool:
	return enabled and DisplayServer.get_name() != "headless"


func setup(p_main: Node2D) -> void:
	main = p_main
	name = "VoxelStage"
	if main.get("camera") != null:
		# the camera moves with the physics ticks; the voxel view interpolates
		(main.camera as Camera2D).process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	_rng.seed = 7
	world_env = WorldEnvironment.new()
	world_env.environment = make_environment()
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = CAMERA_DISTANCE + 70.0
	sun.directional_shadow_split_1 = 0.45
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.0
	sun.shadow_blur = 1.2
	add_child(sun)
	camera = Camera3D.new()
	camera.name = "VoxelCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 1.0
	camera.far = CAMERA_DISTANCE * 3.0
	add_child(camera)
	_tilt = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_tilt.mesh = quad
	_tilt.extra_cull_margin = 16384.0
	_tilt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tm := ShaderMaterial.new()
	tm.shader = TILT_SHADER
	_tilt.material_override = tm
	camera.add_child(_tilt)
	_tilt.position = Vector3(0, 0, -2.0)
	_setup_decals()
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 18)
	_hint.add_theme_color_override("font_color", Color(1, 0.95, 0.8))
	_hint.add_theme_color_override("font_outline_color", Color(0.1, 0.08, 0.06))
	_hint.add_theme_constant_override("outline_size", 6)
	_hint.position = Vector2(1280 - 420, 690)
	_hint.size = Vector2(400, 24)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.visible = false
	var layer := CanvasLayer.new()
	layer.layer = 20
	layer.add_child(_hint)
	add_child(layer)
	_build()


## The whole voxel world, a slice per frame (the loading race follows
## `progress`; `world_ready` when the race can be shown).
func _build() -> void:
	var t0 := Time.get_ticks_msec()
	vtrack = VoxelTrack.new()
	vtrack.name = "VoxelTrack"
	add_child(vtrack)
	var decals := main.get_node_or_null("Decals") as Node2D
	await vtrack.build(main.track, decals)
	if not is_inside_tree():
		return
	await _build_cars()
	race_fx = VoxelRaceFx.new()
	add_child(race_fx)
	race_fx.setup(self)
	if main.effects != null:
		main.effects.celebrated.connect(_confetti)
	if main.get("session") != null and main.get("races_started") != null and main.get("progress") != null:
		recorder = ReplayRecorder.new()
		add_child(recorder)
		recorder.setup(self)
		replay = ReplayTheater.new()
		add_child(replay)
		replay.setup(self, recorder)
	await _build_props()
	if not is_inside_tree():
		return
	_build_lamps()
	vtrack.terrain_material.set_shader_parameter("decal_tex", decal_vp.get_texture())
	vtrack.terrain_material.set_shader_parameter("decal_on", 1.0)
	ready_3d = true
	_apply_mode()
	_sync(0.0)
	build_msec = Time.get_ticks_msec() - t0
	world_ready.emit()


## Overall build progress 0..1.
func progress() -> float:
	if ready_3d:
		return 1.0
	var t := vtrack.progress if vtrack != null else 0.0
	return t * 0.74 + _cars_part * 0.12 + _props_part * 0.14


func _exit_tree() -> void:
	if _saved_mask != 0 and is_inside_tree():
		get_viewport().canvas_cull_mask = _saved_mask


# ------------------------------------------------------------ the 2D world off screen

## The simulation's 2D world stays (physics, rules, track data); its pictures
## leave the screen: the voxel world shows the race.
func _apply_mode() -> void:
	var vp := get_viewport()
	if _saved_mask == 0:
		_saved_mask = vp.canvas_cull_mask
		_tag_2d_world()
	vp.canvas_cull_mask = _saved_mask & ~(HIDE_LAYER | DECAL_LAYER)
	visible = true
	# split-screen views have their own cameras: the full-screen one would be hidden
	camera.current = main.get("player_views") == null
	if main.get("player_views") != null:
		_setup_split_views(true)


## Visibility layers: what the voxel world replaces is moved to HIDE_LAYER;
## tyre marks to DECAL_LAYER (only the decal viewport draws them).
func _tag_2d_world() -> void:
	main.visibility_layer = main.visibility_layer | DECAL_LAYER
	main.track.visibility_layer = HIDE_LAYER
	if main.get("scenery") != null:
		main.scenery.visibility_layer = HIDE_LAYER
	if main.get("combat_view") != null:  # mine halos are painted on the ground
		main.combat_view.visibility_layer = DECAL_LAYER
		main.combat_view.halos.visibility_layer = DECAL_LAYER
	if main.lighting != null:
		main.lighting.visibility_layer = HIDE_LAYER
	var decals := main.get_node_or_null("Decals") as Node2D
	if decals != null:
		decals.visibility_layer = DECAL_LAYER
		for d in decals.get_children():
			if not (d is Sprite2D) and (d as CanvasItem).z_index < Track.BRIDGE_DECK_Z:
				(d as CanvasItem).visibility_layer = DECAL_LAYER  # tyre marks, burn marks, the BR zone
	for c in main.cars:
		for child in c.get_children():
			if child is CanvasItem:
				(child as CanvasItem).visibility_layer = HIDE_LAYER


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(PlayerControls.CAMERA_VIEW, false, true):
		return
	view_index = (view_index + 1) % VIEWS.size()
	_show_hint(PlayerControls.fmt("CAMERA: %s   ({camera_view})") % VIEWS[view_index][2])
	get_viewport().set_input_as_handled()


func _show_hint(text: String) -> void:
	_hint.text = text
	_hint.visible = true
	_hint_left = 2.2


# ------------------------------------------------------------ environment

static func make_environment() -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.2, 0.24, 0.2)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.64, 0.68, 0.78)
	e.ambient_light_energy = 0.62
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.0
	e.tonemap_white = 6.0
	e.ssao_enabled = true
	e.ssao_radius = 0.7
	e.ssao_intensity = 1.8
	e.ssao_power = 1.4
	e.ssao_detail = 0.6
	e.glow_enabled = true
	e.glow_intensity = 0.4
	e.glow_strength = 0.9
	e.glow_bloom = 0.0
	e.glow_hdr_threshold = 1.1
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.1
	e.adjustment_contrast = 1.04
	return e


func _apply_time_of_day(night: bool) -> void:
	var e := world_env.environment
	var theme: TrackTheme = main.track_theme
	var weather: String = theme.weather if theme != null else ""
	if night:
		var amb: Color = theme.night_ambient if theme != null else Color(0.42, 0.44, 0.58)
		# P003: a proper night - the darkness comes from the world's lighting
		# (dim moonlight, little ambient), the light from lamps and headlights
		e.background_color = Color(0.015, 0.018, 0.035)
		e.ambient_light_color = amb.lerp(Color(0.3, 0.38, 0.72), 0.5)
		e.ambient_light_energy = NIGHT_AMBIENT
		e.glow_intensity = 1.0
		e.glow_hdr_threshold = 0.8
		e.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
		e.adjustment_saturation = 1.05
		e.tonemap_exposure = 1.05
		sun.light_color = Color(0.55, 0.65, 1.0)
		sun.light_energy = NIGHT_MOON
		sun.basis = Basis.looking_at(Vector3(-0.35, -1.0, -0.45).normalized(), Vector3.UP)
	else:
		e.background_color = Color(0.2, 0.24, 0.2)
		e.ambient_light_color = Color(0.62, 0.68, 0.84)
		e.ambient_light_energy = 0.42
		e.glow_intensity = 0.3
		e.glow_hdr_threshold = 1.2
		e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
		e.adjustment_saturation = 1.18
		e.tonemap_exposure = 0.92
		sun.light_color = Color(1.0, 0.95, 0.86)
		sun.light_energy = 0.95
		if weather == "rain":
			sun.light_energy = 0.6
			e.ambient_light_energy = 0.6
			e.adjustment_saturation = 0.95
		elif weather == "snow":
			sun.light_color = Color(0.92, 0.95, 1.0)
			e.ambient_light_color = Color(0.7, 0.76, 0.9)
		# light from the lower left of the screen, shadows fall up and to the right
		sun.basis = Basis.looking_at(Vector3(0.52, -1.15, -0.62).normalized(), Vector3.UP)
	for l in lamps3d:
		l.visible = night
	for d in cars3d:
		for l in d.lights:
			(l as Light3D).visible = night
	for p in _glowing:
		(p as GeometryInstance3D).set_instance_shader_parameter("lamp_glow", 1.0 if night else 0.0)


# ------------------------------------------------------------ cars

var _cars_holder: Node3D


func _build_cars() -> void:
	var holder := Node3D.new()
	holder.name = "Cars"
	add_child(holder)
	_cars_holder = holder
	var t := Time.get_ticks_usec()
	for i in main.cars.size():
		if Time.get_ticks_usec() - t > 20000:
			await get_tree().process_frame
			t = Time.get_ticks_usec()
		_cars_part = float(i) / main.cars.size()
		cars3d.append(make_car(i, holder))


## One car's voxel node tree (root > tilt > body, wheels, lamps, marker) and
## its presentation state. Also used by the replay theater for its own cars.
func make_car(i: int, holder: Node3D) -> Dictionary:
	var layout: WheelLayout = main.wheel_layout
	var c: Car = main.cars[i]
	var look: Dictionary = main._car_looks[i] if i < main._car_looks.size() else {}
	var body_logical: String = look.get("body_logical", "")
	var root := Node3D.new()
	root.name = "Car%d" % i
	holder.add_child(root)
	var tilt := Node3D.new()
	root.add_child(tilt)
	var body := MeshInstance3D.new()
	body.mesh = VoxelCars.body_mesh(c.sprite.texture, layout, body_logical)
	tilt.add_child(body)
	var marker := MeshInstance3D.new()
	marker.mesh = _marker_mesh()
	marker.position = Vector3(0, 2.6, 0)
	marker.visible = false
	marker.set_instance_shader_parameter("lamp_glow", 0.35)
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(marker)
	var wheels: Array[Node3D] = []
	var spins: Array[MeshInstance3D] = []
	var at := layout.positions(body_logical)
	var show_wheels: bool = look.get("wheels", true)
	for ax in [at.x, at.y]:
		for az in [-at.z, at.z]:
			var pivot := Node3D.new()
			pivot.position = Vector3(ax, VoxelCars.WHEEL_R * Vox.CAR_VOXEL_PX, az) * Vox.PX
			root.add_child(pivot)
			var w := MeshInstance3D.new()
			w.mesh = VoxelCars.wheel_mesh()
			pivot.add_child(w)
			pivot.visible = show_wheels
			wheels.append(pivot)
			spins.append(w)
	var lights: Array[Light3D] = []
	for side in [-1.0, 1.0]:
		var spot := SpotLight3D.new()
		spot.position = Vector3(LightingPilot.HEAD_LAMP.x, 8.0, side * LightingPilot.HEAD_LAMP.y) * Vox.PX
		spot.basis = Basis.looking_at(Vector3(1.0, -0.2, side * 0.04).normalized(), Vector3.UP)
		spot.spot_range = 20.0
		spot.spot_angle = 26.0
		spot.spot_angle_attenuation = 0.8
		spot.light_energy = 5.0
		spot.light_color = main.lighting.head_color_of(c.racer_id) if main.lighting != null else LightingPilot.HEADLIGHT_COLOR
		spot.light_specular = 0.2
		spot.visible = false
		root.add_child(spot)
		lights.append(spot)
	var tail := OmniLight3D.new()
	tail.position = Vector3(-36.0, 6.0, 0.0) * Vox.PX
	tail.omni_range = 2.6
	tail.light_energy = 0.8
	tail.light_color = Color(1.0, 0.12, 0.06)
	tail.visible = false
	root.add_child(tail)
	lights.append(tail)
	# the driver, for the overtaking taunt (hidden until a head pops out)
	var head := Node3D.new()
	head.name = "Driver"
	head.visible = false
	tilt.add_child(head)
	var face := MeshInstance3D.new()
	face.mesh = VoxelWeapons.head_mesh(HELMETS[i % HELMETS.size()])
	head.add_child(face)
	var shoulder := Node3D.new()
	shoulder.name = "Shoulder"
	shoulder.position = Vector3(-0.05, 0.12, 0.0)
	head.add_child(shoulder)
	var arm := MeshInstance3D.new()
	arm.mesh = VoxelWeapons.arm_mesh()
	shoulder.add_child(arm)
	return {
		"tick_pos": c.global_position, "tick_prev": c.global_position, "tick_rot": c.global_rotation, "rot_prev": c.global_rotation,
		"tick_v": Vector2.ZERO, "acc_long": 0.0, "acc_lat": 0.0, "pitch_v": 0.0, "roll_v": 0.0, "wheelspin": 0.0, "spin_rear": 0.0,
		"head_node": head, "head": 0.0, "head_side": 1.0, "head_box": body.mesh.get_aabb() if body.mesh != null else AABB(),
		"root": root, "tilt": tilt, "body": body, "wheels": wheels, "spins": spins, "lights": lights,
		"roll": 0.0, "pitch": 0.0, "spin": 0.0, "h": 0.0, "prev_v": Vector2.ZERO, "prev_pos": c.global_position,
		"brake": 0.0, "steer": 0.0, "prev_rot": c.global_rotation, "marker": marker, "show_wheels": show_wheels,
		"grid": VoxelCars.body_grid(c.sprite.texture, layout, body_logical), "pristine_mesh": body.mesh,
	}


func _sync_cars(delta: float) -> void:
	var lp: LightingPilot = main.lighting
	var night := lp != null and lp.enabled
	var elevated: bool = main.track.layout.has_elevation()
	for i in cars3d.size():
		var d: Dictionary = cars3d[i]
		var c: Car = main.cars[i]
		var root: Node3D = d.root
		root.visible = c.visible
		if not c.visible:
			continue
		var alpha := Engine.get_physics_interpolation_fraction()
		var pos := (d.tick_prev as Vector2).lerp(d.tick_pos, alpha)
		var rot := lerp_angle(float(d.rot_prev), float(d.tick_rot), alpha)
		# height: bridge deck, kerbs, jumps
		var h := 0.0
		if elevated and main.draw_level_of(i) == 1:
			h = vtrack.deck_height_px(main.progress[i].distance)
		else:
			h = clampf(vtrack.height_px_at(pos), 0.0, VoxelTrack.KERB_H * VoxelTrack.CELL)
		if _jumps() != null:
			h += _jumps().height(i)
			if _jumps().is_down(i):
				h = -2.0 if _jumps().is_down_in_flyover(i) else VoxelTrack.PIT_H * VoxelTrack.CELL
		var moved: float = (pos - d.prev_pos).length()
		if moved > 60.0:  # placed / respawned: no smoothing
			d.h = h
		else:
			d.h = lerpf(d.h, h, 1.0 - exp(-delta * 18.0))
		root.position = Vox.to3(pos, d.h)
		root.rotation = Vector3(0.0, Vox.yaw(rot), 0.0)
		# weight transfer (presentation only): the nose lifts and the tail
		# squats under acceleration, the nose dives under braking, the body
		# leans out of corners - a spring with a little overshoot
		var vel: Vector2 = c.model.velocity if c.model != null else Vector2.ZERO
		var fwd := Vector2.from_angle(rot)
		var a_long: float = d.acc_long
		var a_lat: float = d.acc_lat
		if moved >= 60.0:
			a_long = 0.0
			a_lat = 0.0
		var pitch_target := clampf(a_long * PITCH_PER_ACC, -PITCH_DIVE_MAX, PITCH_LIFT_MAX)
		var roll_target := clampf(a_lat * ROLL_PER_ACC, -ROLL_MAX, ROLL_MAX)
		if c.airborne:
			pitch_target = 0.05
		var dt := minf(delta, 0.05)
		d.pitch_v = float(d.pitch_v) + (SPRING_K * (pitch_target - float(d.pitch)) - SPRING_C * float(d.pitch_v)) * dt
		d.pitch = float(d.pitch) + float(d.pitch_v) * dt
		d.roll_v = float(d.roll_v) + (SPRING_K * (roll_target - float(d.roll)) - SPRING_C * float(d.roll_v)) * dt
		d.roll = float(d.roll) + float(d.roll_v) * dt
		(d.tilt as Node3D).rotation = Vector3(d.roll, 0.0, d.pitch)
		# wheelspin: hard throttle at low speed spins the rear wheels (and the
		# race fx puts tyre smoke under them); strongest from a standstill
		var along := vel.dot(fwd)
		var spin_want := clampf((a_long - 110.0) / 180.0, 0.0, 1.0) * clampf(1.0 - absf(along) / 190.0, 0.0, 1.0)
		if not c.active or c.airborne:
			spin_want = 0.0
		d.wheelspin = lerpf(float(d.wheelspin), spin_want, 1.0 - exp(-dt * (14.0 if spin_want > float(d.wheelspin) else 4.0)))
		# braking (brake lights by day too)
		var braking := a_long < -110.0 and along > 30.0
		d.brake = lerpf(d.brake, 1.0 if braking else 0.0, 1.0 - exp(-delta * 12.0))
		# wheels: steering (the steering command when the car is driven here,
		# otherwise its turning rate) and rolling
		var turn_rate := deg_to_rad(c.model.params.turn_rate_degrees) if c.model != null else 3.0
		var yaw_rate := wrapf(rot - float(d.prev_rot), -PI, PI) / maxf(delta, 0.0001) if moved < 60.0 else 0.0
		var target := clampf(c.steer, -1.0, 1.0) if c.active else clampf(yaw_rate / turn_rate, -1.0, 1.0)
		d.steer = lerpf(d.steer, target, 1.0 - exp(-delta / 0.07))
		d.prev_rot = rot
		var steer_angle := deg_to_rad(main.wheel_layout.max_steer_degrees) * clampf(d.steer, -1.0, 1.0)
		var forward_px := (pos - (d.prev_pos as Vector2)).dot(fwd) if moved < 60.0 else 0.0
		d.spin = fposmod(d.spin - forward_px / (VoxelCars.WHEEL_R * Vox.CAR_VOXEL_PX), TAU)
		d.spin_rear = fposmod(float(d.spin_rear) - forward_px / (VoxelCars.WHEEL_R * Vox.CAR_VOXEL_PX) - float(d.wheelspin) * 34.0 * dt, TAU)
		var wheels: Array = d.wheels
		var spins: Array = d.spins
		for w in 4:
			(wheels[w] as Node3D).rotation.y = -steer_angle if w < 2 else 0.0
			(spins[w] as Node3D).rotation.z = d.spin if w < 2 else d.spin_rear
		# paint: junker tints, fallen tint, wear; lamps
		var body: MeshInstance3D = d.body
		var tint := c.sprite.modulate
		if _jumps() != null and _jumps().is_down(i):
			tint *= JumpView.FALLEN_TINT
		body.set_instance_shader_parameter("tint", tint)
		# respawn protection blinks the car, as in HyperCars
		var cw: CombatWorld = main.combat
		if cw != null and cw.enabled and cw.grace_left[i] > 0.0:
			body.visible = sin(Time.get_ticks_msec() * 0.024) > -0.3
		else:
			body.visible = true
		var marker: MeshInstance3D = d.marker
		var mk: Dictionary = main.player_marker.marked if main.player_marker != null else {}
		marker.visible = mk.has(c.racer_id)
		if marker.visible:
			marker.set_instance_shader_parameter("tint", mk[c.racer_id])
			marker.position.y = 2.6 + sin(Time.get_ticks_msec() * 0.005) * 0.18
			marker.rotation.y = -root.rotation.y
		var hb := 0.0
		var head_col := LightingPilot.HEADLIGHT_COLOR
		if lp != null:
			head_col = lp.head_color_of(c.racer_id)
			if i < lp.high_beam.size():
				hb = lp.high_beam[i]
		body.set_instance_shader_parameter("head_tint", head_col)
		body.set_instance_shader_parameter("head_glow", (0.55 + 0.35 * hb) if night else 0.0)
		body.set_instance_shader_parameter("tail_glow", (0.3 + 0.7 * d.brake) if night else 0.7 * d.brake)
		var dmg: VoxelCarDamage = race_fx.damage[i] if race_fx != null and i < race_fx.damage.size() else null
		var lights_all: Array = d.lights
		var gone := dmg != null and dmg.wrecked
		(lights_all[0] as Light3D).visible = night and not gone and (dmg == null or dmg.lamps[0] > 0)
		(lights_all[1] as Light3D).visible = night and not gone and (dmg == null or dmg.lamps[1] > 0)
		(lights_all[2] as Light3D).visible = night and not gone and (dmg == null or dmg.lamps[2] + dmg.lamps[3] > 0)
		if night:
			var lights: Array = d.lights
			for s in 2:
				var spot: SpotLight3D = lights[s]
				spot.spot_range = 25.0 * lerpf(1.0, LightingPilot.HIGH_BEAM_SCALE, hb)
				spot.light_energy = 7.5 * lerpf(1.0, LightingPilot.HIGH_BEAM_ENERGY, hb)
				spot.light_color = head_col
			(lights[2] as OmniLight3D).light_energy = 0.7 + 1.6 * d.brake
		d.prev_v = vel
		d.prev_pos = pos


## Night (P003): ambient and moonlight energies; the lamp posts' pools.
const NIGHT_AMBIENT := 0.13
const NIGHT_MOON := 0.13
const POST_SPACING := 420.0
const POST_OFFSET := 132.0
const POST_MAX := 26


## Weight transfer (P003, presentation only): body pitch / roll per px/s2 of
## acceleration, limits (radians), and the spring that carries it.
const PITCH_PER_ACC := 0.00026
const PITCH_LIFT_MAX := 0.075
const PITCH_DIVE_MAX := 0.06
const ROLL_PER_ACC := 0.00011
const ROLL_MAX := 0.1
const SPRING_K := 140.0
const SPRING_C := 15.0


## Helmet colours of the drivers (the player first, then the rivals).
const HELMETS := [Color("f7b731"), Color("e8e8f0"), Color("e8432e"), Color("59c3f2"), Color("7bc950"),
	Color("f45b9b"), Color("2ec4b6"), Color("a37ef0"), Color("ff8c2e"), Color("3d4a8a")]


## The overtaking taunt, pose v in 0..1 (0: inside): the driver's head pops out
## of the window on `head_side`, looks back, the arm winds up and throws.
func pose_head(d: Dictionary, v: float) -> void:
	var head: Node3D = d.head_node
	head.visible = v > 0.001 and v < 0.999
	if not head.visible:
		return
	var box: AABB = d.head_box
	var side: float = d.head_side
	var out := smoothstep(0.0, 0.18, v) * (1.0 - smoothstep(0.84, 1.0, v))
	var cx := box.get_center().x - box.size.x * 0.06
	var top := box.end.y
	head.position = Vector3(cx, lerpf(top * 0.35, top - 0.08, out), side * lerpf(box.size.z * 0.18, box.size.z * 0.5 + 0.12, out))
	# looks back towards the car behind, a little cheeky tilt
	var look := smoothstep(0.1, 0.3, v) * (1.0 - smoothstep(0.7, 0.9, v))
	head.rotation = Vector3(side * 0.35 * out, side * look * 2.2, 0.0)
	var shoulder: Node3D = head.get_node("Shoulder")
	shoulder.position = Vector3(-0.05, 0.12, side * 0.18)
	# wind up (arm raised forward), then the throw backwards
	var wind := smoothstep(0.18, 0.34, v)
	var throw := smoothstep(0.36, 0.48, v)
	shoulder.rotation = Vector3(side * 0.45, 0.0, PI + 0.9 * wind - 2.4 * throw)


# ------------------------------------------------------------ scenery

var _glowing: Array = []


## Logical asset name of a texture the race resolved (reverse of AssetResolver).
func _logical_of(tex: Texture2D) -> String:
	if _texture_names.is_empty():
		for key in AssetCatalog.SPECS:
			var t: Texture2D = main.resolver.get_texture(key)
			if t != null:
				_texture_names[t.get_instance_id()] = key
	return _texture_names.get(tex.get_instance_id() if tex != null else 0, "")


func _build_props() -> void:
	var holder := Node3D.new()
	holder.name = "Props"
	add_child(holder)
	var sprites: Array[Sprite2D] = []
	if main.get("scenery") != null:
		for s in main.scenery.get_children():
			if s is Sprite2D:
				sprites.append(s)
	for s in main.track.get_children():  # arena props (Battle Royale)
		if s is Sprite2D and String(s.name).begins_with("Prop"):
			if String(s.name).begins_with("PropJunker"):
				_junker(holder, s)
			else:
				sprites.append(s)
	var branches: Node = main.track.get_node_or_null("Branches")
	if branches != null:
		for s in branches.get_children():
			if s is Sprite2D:
				sprites.append(s)
	var t := Time.get_ticks_usec()
	for n in sprites.size():
		var spr := sprites[n]
		if Time.get_ticks_usec() - t > 20000:
			_props_part = float(n) / sprites.size()
			await get_tree().process_frame
			if not is_inside_tree():
				return
			t = Time.get_ticks_usec()
		var logical := _logical_of(spr.texture)
		if logical.is_empty():
			continue
		var kind := VoxelProps.kind_of(logical)
		var spec: Dictionary = AssetCatalog.SPECS.get(logical, {})
		var nominal: Vector2 = spec.get("display_size", spr.texture.get_size())
		var frame_size := spr.texture.get_size() / Vector2(maxi(1, spr.hframes), maxi(1, spr.vframes))
		var shown := frame_size * spr.global_scale.abs()
		if VoxelProps.is_decoration(kind) and _on_drivable(spr.global_position, shown):
			continue  # (2D drew it under the road; in voxels it would stand on it)
		var mesh := VoxelProps.mesh_for(logical, spr.texture, nominal, spr.hframes)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		var pos := spr.global_position
		var yaw := Vox.yaw(spr.global_rotation)
		if kind == VoxelProps.Kind.FLAG:
			yaw = Vox.yaw(-PI * 0.25)
		if kind == VoxelProps.Kind.BOARD or kind == VoxelProps.Kind.PIT:
			# the drawn face (local +Y in 2D) looks at the road
			var face := Vector2(-sin(spr.global_rotation), cos(spr.global_rotation))
			var to_road := _to_road(pos)
			if face.dot(to_road) < 0.0:
				yaw += PI
		var s := (shown.x / nominal.x + shown.y / nominal.y) * 0.5 if nominal.x > 0.0 else 1.0
		mi.scale = Vector3.ONE * s
		mi.position = Vox.to3(pos, vtrack.height_px_at(pos))
		mi.rotation.y = yaw
		if kind == VoxelProps.Kind.BOARD:
			mi.rotation.x = -0.62  # leaning back: the face looks up at the camera
		var v := _rng.randf_range(-0.05, 0.05)
		mi.set_instance_shader_parameter("tint", Color(1.0 + v, 1.0 + v * 0.6, 1.0 + v * 0.3))
		if VoxelProps.sways(kind):
			mi.set_instance_shader_parameter("sway", 0.006 if kind == VoxelProps.Kind.FLAG else 0.004)
		if kind == VoxelProps.Kind.FLOOD:
			_glowing.append(mi)
		holder.add_child(mi)


## Whether a prop of `size` (px) at p would cover any drivable ground.
func _on_drivable(p: Vector2, size: Vector2) -> bool:
	var r := maxf(size.x, size.y) * 0.32
	if vtrack.drivable_at(p):
		return true
	for k in 8:
		if vtrack.drivable_at(p + Vector2.from_angle(k * TAU / 8.0) * r):
			return true
	return false


## Direction from a point to the nearest centreline sample.
func _to_road(p: Vector2) -> Vector2:
	var best := Vector2.ZERO
	var bd := INF
	for q in main.track.centerline:
		var d2 := p.distance_squared_to(q)
		if d2 < bd:
			bd = d2
			best = q
	return best - p


## The environment's lamp posts (LightingPilot's lamps): physical posts by
## day, real lights at night.
func _build_lamps() -> void:
	var lp: LightingPilot = main.lighting
	if lp == null:
		return
	var holder := Node3D.new()
	holder.name = "Lamps"
	add_child(holder)
	var sprites: Array = lp._lamp_sprites
	var lights: Array = lp._lamps
	for k in mini(sprites.size(), lights.size()):
		var spr: Sprite2D = sprites[k]
		var l2: PointLight2D = lights[k]
		var base := spr.global_position
		var toward := (l2.global_position - base).normalized()
		var flood: bool = main.track_theme != null and main.track_theme.variant == 4
		var post := MeshInstance3D.new()
		post.mesh = VoxelProps.lamp_mesh(flood)
		var ground := vtrack.height_px_at(base)
		post.position = Vox.to3(base, ground)
		post.rotation.y = Vox.yaw(toward.angle())
		holder.add_child(post)
		_glowing.append(post)
		var head := VoxelProps.lamp_head(flood)
		var light := SpotLight3D.new()
		var lpos := base + toward * head.x
		light.position = Vox.to3(lpos, ground + head.y - 6.0)
		var aim := Vox.to3(base + toward * 90.0, 0.0) - light.position
		light.basis = Basis.looking_at(aim.normalized(), Vector3.UP)
		light.spot_angle = 62.0
		light.spot_angle_attenuation = 0.6
		light.spot_range = 26.0 if flood else 20.0
		light.light_color = lp.lamp_color
		light.light_energy = lp.lamp_energy * 7.0
		light.shadow_enabled = false
		light.visible = false
		holder.add_child(light)
		lamps3d.append(light)
	_build_posts(holder)


## P003: more voxel lamp posts round the circuit (presentation only): every
## POST_SPACING px along the centre line, alternating sides, on open ground
## beside the road; each casts a pool of light on the asphalt at night.
func _build_posts(holder: Node3D) -> void:
	var track = main.track
	if track == null or track.get("centerline") == null or (track.centerline as PackedVector2Array).size() < 8:
		return
	var cl: PackedVector2Array = track.centerline
	var lp: LightingPilot = main.lighting
	var flood: bool = main.track_theme != null and main.track_theme.variant == 4
	var existing: Array[Vector2] = []
	for l in lp._lamp_sprites if lp != null else []:
		existing.append((l as Sprite2D).global_position)
	var total := 0.0
	var next := POST_SPACING * 0.5
	var side := 1.0
	var placed := 0
	for k in cl.size():
		var a := cl[k]
		var b := cl[(k + 1) % cl.size()]
		total += a.distance_to(b)
		if total < next:
			continue
		next += POST_SPACING
		side = -side
		var t := (b - a).normalized()
		var n := Vector2(-t.y, t.x) * side
		var spot := Vector2.ZERO
		var ok := false
		for extra in [0.0, 24.0, 48.0, -12.0]:
			spot = a + n * (POST_OFFSET + extra)
			if vtrack.class_at(spot) == VoxelTrack.C_GRASS and not _on_drivable(spot, Vector2(28, 28)):
				ok = true
				break
		if not ok:
			continue
		var crowded := false
		for e in existing:
			if e.distance_to(spot) < 170.0:
				crowded = true
		if crowded:
			continue
		existing.append(spot)
		var post := MeshInstance3D.new()
		post.mesh = VoxelProps.lamp_mesh(flood)
		var ground := vtrack.height_px_at(spot)
		post.position = Vox.to3(spot, ground)
		post.rotation.y = Vox.yaw((-n).angle())
		holder.add_child(post)
		_glowing.append(post)
		var head := VoxelProps.lamp_head(flood)
		var light := SpotLight3D.new()
		light.position = Vox.to3(spot - n * head.x, ground + head.y - 6.0)
		var aim := Vox.to3(spot - n * 110.0, 0.0) - light.position
		light.basis = Basis.looking_at(aim.normalized(), Vector3.UP)
		light.spot_angle = 58.0
		light.spot_angle_attenuation = 0.7
		light.spot_range = 22.0
		light.light_color = lp.lamp_color if lp != null else LightingPilot.LAMP_COLOR
		light.light_energy = (lp.lamp_energy if lp != null else 1.15) * 7.0
		light.shadow_enabled = false
		light.visible = false
		holder.add_child(light)
		lamps3d.append(light)
		placed += 1
		if placed >= POST_MAX:
			break


# ------------------------------------------------------------ decals

func _setup_decals() -> void:
	decal_vp = SubViewport.new()
	decal_vp.name = "DecalView"
	decal_vp.size = DECAL_SIZE
	decal_vp.world_2d = get_viewport().world_2d
	decal_vp.transparent_bg = true
	decal_vp.disable_3d = true
	decal_vp.canvas_cull_mask = DECAL_LAYER
	decal_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(decal_vp)


# ------------------------------------------------------------ camera and frame

func _process(delta: float) -> void:
	if _hint_left > 0.0:
		_hint_left -= delta
		_hint.visible = _hint_left > 0.0
		_hint.modulate.a = clampf(_hint_left * 2.0, 0.0, 1.0)
	if not ready_3d:
		return
	_sync(delta)


## Smooth motion at any refresh rate (P003): the race moves in 60 Hz physics
## ticks; cars and the camera are drawn between the last two ticks. (Without
## this, a smoothed spectator camera glided every frame while the cars
## stepped: after the player's finish the other cars looked blurred.)
var _phys_frame := -1
var _ticks_new := false
var _cam_prev := Vector2.ZERO
var _cam_cur := Vector2.ZERO


func _capture_tick() -> void:
	var pf := Engine.get_physics_frames()
	_ticks_new = pf != _phys_frame
	if not _ticks_new:
		return
	var steps := maxi(1, pf - _phys_frame) if _phys_frame >= 0 else 1
	_phys_frame = pf
	var centre: Vector2 = main.camera.get_screen_center_position()
	_cam_prev = _cam_cur if _cam_cur.distance_to(centre) < 200.0 else centre
	_cam_cur = centre
	var dt := steps * Car.FIXED_STEP
	for i in cars3d.size():
		var d: Dictionary = cars3d[i]
		var c: Car = main.cars[i]
		var p := c.global_position
		var r := c.global_rotation
		var jump: bool = (p - (d.tick_pos as Vector2)).length() > 60.0
		d.tick_prev = p if jump else d.tick_pos
		d.rot_prev = r if jump else d.tick_rot
		d.tick_pos = p
		d.tick_rot = r
		# acceleration in the car's frame, per tick (weight transfer)
		var vel: Vector2 = c.model.velocity if c.model != null else Vector2.ZERO
		var acc := Vector2.ZERO if jump else (vel - (d.tick_v as Vector2)) / dt
		d.tick_v = vel
		var fwd := Vector2.from_angle(r)
		d.acc_long = acc.dot(fwd)
		d.acc_lat = acc.dot(Vector2(-fwd.y, fwd.x))


func _sync(delta: float) -> void:
	_capture_tick()
	var night: bool = main.lighting != null and main.lighting.enabled
	if int(night) != _night:
		_night = int(night)
		_apply_time_of_day(night)
	var view: Array = VIEWS[view_index]
	var pitch := deg_to_rad(view[0])
	var zoom: float = view[1]
	var cam2: Camera2D = main.camera
	var centre := _cam_prev.lerp(_cam_cur, Engine.get_physics_interpolation_fraction())
	var z2 := Vector2(zoom, zoom * sin(pitch))
	cam2.zoom = z2
	_place_camera(camera, centre, pitch, zoom)
	_tilt_shift(view[3])
	_sync_cars(delta)
	race_fx.sync(delta)
	# an action replay hides the live race (which carries on underneath)
	var replaying := replay != null and replay.playing
	_cars_holder.visible = not replaying
	race_fx.visible = not replaying
	race_fx.burns_visible(not replaying)
	if replaying:
		centre = replay.focus_2d()
		z2 = Vector2(1.0, 1.0) * 0.9
	# tyre marks: the decal viewport covers the visible ground (plus a margin)
	var dz := z2 * (float(DECAL_SIZE.x) / 1280.0) / DECAL_MARGIN
	decal_vp.canvas_transform = Transform2D(0.0, dz, 0.0, Vector2(DECAL_SIZE) * 0.5 - centre * dz)
	var m := vtrack.terrain_material
	m.set_shader_parameter("decal_cam", centre)
	m.set_shader_parameter("decal_zoom", dz)
	m.set_shader_parameter("decal_size", Vector2(DECAL_SIZE))
	if main.get("player_views") != null and _split_cams.size() > 0:
		_sync_split_views(pitch, zoom)


## Tilt-shift strength for the camera preset (0 = off).
func _tilt_shift(amount: float) -> void:
	_tilt.visible = amount > 0.0
	(_tilt.material_override as ShaderMaterial).set_shader_parameter("amount", amount)


static func _place_camera(cam: Camera3D, centre: Vector2, pitch: float, zoom: float) -> void:
	cam.size = 720.0 * Vox.PX / zoom
	var target := Vox.to3(centre)
	cam.position = target + Vector3(0.0, sin(pitch), cos(pitch)) * CAMERA_DISTANCE
	cam.rotation = Vector3(-pitch, 0.0, 0.0)


# ------------------------------------------------------------ split screen

var _split_cams: Array[Camera3D] = []


## Couch split-screen (PlayerViews): each view's SubViewport shares this 3D
## world and gets its own voxel camera, synced to that view's 2D camera.
func _setup_split_views(on: bool) -> void:
	var pv = main.get("player_views")
	if pv == null:
		return
	for cam in _split_cams:
		cam.queue_free()
	_split_cams.clear()
	for v in pv.views:
		var vp: SubViewport = v.viewport
		var cam2: Camera2D = v.camera
		vp.canvas_cull_mask = (_saved_mask & ~(HIDE_LAYER | DECAL_LAYER)) if on else (_saved_mask | HIDE_LAYER | DECAL_LAYER)
		if not on:
			cam2.zoom = PlayerViews.VIEW_ZOOM
			vp.world_3d = null
			continue
		vp.world_3d = get_viewport().world_3d
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.near = 1.0
		cam.far = CAMERA_DISTANCE * 3.0
		vp.add_child(cam)
		cam.make_current()
		cam.set_meta("camera2d", cam2)
		_split_cams.append(cam)


func _sync_split_views(pitch: float, zoom: float) -> void:
	for cam in _split_cams:
		var cam2: Camera2D = cam.get_meta("camera2d")
		if not is_instance_valid(cam2):
			continue
		var z := zoom * PlayerViews.VIEW_ZOOM.x
		cam2.zoom = Vector2(z, z * sin(pitch))
		_place_camera(cam, cam2.get_screen_center_position(), pitch, z)


## The little floating chevron over the local player's car (tinted per player).
static var _marker: ArrayMesh


static func _marker_mesh() -> ArrayMesh:
	if _marker != null:
		return _marker
	# a chevron pointing down at the car (seen from above: screen down is +Z)
	var rows := ["1110111", "1111111", "0111110", "0011100", "0001000"]
	var vs := VoxelCars.voxel_size() * 1.2
	var g := VoxelGrid.new(Vector3i(7, 2, rows.size()), vs, Vector3.ZERO)
	for z in rows.size():
		for x in 7:
			if rows[z][x] == "1":
				g.set_v(x, 0, z, Vox.GLOW, Color.WHITE)
				g.set_v(x, 1, z, Vox.GLOW, Color.WHITE)
	_marker = VoxelMesher.build_mesh(g, VoxelCars.material(), Vector3(3.5, 1.0, rows.size() * 0.5) * vs, 0.0)
	return _marker


## Voxel confetti at the finish line.
func _confetti(at: Vector2) -> void:
	var cols := [Color("e8432e"), Color("f2b632"), Color("2ec4b6"), Color("f6f1e1"), Color("e45ba0"), Color("4f7cff")]
	var base := Vox.to3(at, 30.0)
	for k in 90:
		var a := randf() * TAU
		var v := Vector3(cos(a), 0.0, sin(a)) * randf_range(1.0, 6.0) + Vector3(0, randf_range(4.0, 10.0), 0)
		race_fx.fx.spark(base, v, cols[k % cols.size()], randf_range(0.09, 0.15), randf_range(1.6, 2.6), 0.25, 0.35)


func _jumps() -> JumpWorld:
	return main.get("jumps")


## A scrapped car on the Battle Royale pile: the junker as a voxel model,
## a little sunk and battered.
func _junker(holder: Node3D, spr: Sprite2D) -> void:
	var logical := AssetCatalog.body_of(AssetCatalog.CAR_JUNKER)
	var mi := MeshInstance3D.new()
	mi.mesh = VoxelCars.body_mesh(main.resolver.get_texture(logical), main.wheel_layout, logical)
	mi.position = Vox.to3(spr.global_position, vtrack.height_px_at(spr.global_position) - 2.0)
	mi.rotation = Vector3(_rng.randf_range(-0.25, 0.25), Vox.yaw(spr.global_rotation), _rng.randf_range(-0.3, 0.3))
	mi.set_instance_shader_parameter("tint", spr.modulate)
	holder.add_child(mi)
