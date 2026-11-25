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
## Keys: V cycles the camera, G toggles the original 2D presentation (A / B).

## Canvas visibility layers (bit values): the 2D world hidden in voxel mode,
## and the ground decals drawn only into the decal viewport.
const HIDE_LAYER := 1 << 9
const DECAL_LAYER := 1 << 8
## Camera presets: pitch (degrees from the ground), zoom, name.
const VIEWS := [
	[58.0, 1.22, "MINIATURE"],
	[72.0, 1.12, "HIGH"],
	[44.0, 1.34, "LOW"],
	[90.0, 1.0, "TOP-DOWN"],
]
const CAMERA_DISTANCE := 48.0
## Decal viewport (tyre marks): size, and how much more ground it covers than the screen.
const DECAL_SIZE := Vector2i(720, 420)
const DECAL_MARGIN := 1.18

## Off for headless runs (tests) or when the player chose the 2D look.
static var enabled := true
## The camera preset and the 2D / voxel choice last for the whole session.
static var view_index := 0
static var voxel_mode := true

var main: Node2D
var vtrack: VoxelTrack
var camera: Camera3D
var sun: DirectionalLight3D
var world_env: WorldEnvironment
var decal_vp: SubViewport
var ready_3d := false
var cars3d: Array[Dictionary] = []
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
	_build_cars()
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
	_show_hint("BUILDING THE VOXEL WORLD...")
	_hint_left = 600.0
	vtrack = VoxelTrack.new()
	vtrack.name = "VoxelTrack"
	add_child(vtrack)
	vtrack.built.connect(_on_track_built)
	var decals := main.get_node_or_null("Decals") as Node2D
	vtrack.build(main.track, decals)


func _on_track_built() -> void:
	_build_props()
	_build_lamps()
	vtrack.terrain_material.set_shader_parameter("decal_tex", decal_vp.get_texture())
	vtrack.terrain_material.set_shader_parameter("decal_on", 1.0)
	ready_3d = true
	_hint_left = 0.0
	_hint.visible = false
	_apply_mode()
	_sync(0.0)


func _exit_tree() -> void:
	if _saved_mask != 0 and is_inside_tree():
		get_viewport().canvas_cull_mask = _saved_mask


# ------------------------------------------------------------ 2D / 3D switch

## Culls HyperCars' 2D world visuals (voxel mode) or shows them (2D mode).
func _apply_mode() -> void:
	var vp := get_viewport()
	if _saved_mask == 0:
		_saved_mask = vp.canvas_cull_mask
		_tag_2d_world()
	var on := voxel_mode and ready_3d
	if on:
		vp.canvas_cull_mask = _saved_mask & ~(HIDE_LAYER | DECAL_LAYER)
	else:
		vp.canvas_cull_mask = _saved_mask | HIDE_LAYER | DECAL_LAYER
	visible = on
	camera.current = on
	if not on and main.camera != null:
		main.camera.zoom = Vector2.ONE
	if main.get("player_views") != null:
		_setup_split_views(on)


## Visibility layers: what the voxel world replaces is moved to HIDE_LAYER;
## tyre marks to DECAL_LAYER (only the decal viewport draws them).
func _tag_2d_world() -> void:
	main.visibility_layer = main.visibility_layer | DECAL_LAYER
	main.track.visibility_layer = HIDE_LAYER
	if main.scenery != null:
		main.scenery.visibility_layer = HIDE_LAYER
	if main.lighting != null:
		main.lighting.visibility_layer = HIDE_LAYER
	var decals := main.get_node_or_null("Decals") as Node2D
	if decals != null:
		decals.visibility_layer = DECAL_LAYER
		for d in decals.get_children():
			if d is MultiMeshInstance2D and (d as CanvasItem).z_index < Track.BRIDGE_DECK_Z:
				(d as CanvasItem).visibility_layer = DECAL_LAYER
	for c in main.cars:
		for child in c.get_children():
			if child is CanvasItem:
				(child as CanvasItem).visibility_layer = HIDE_LAYER


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := event as InputEventKey
	var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
	if code != KEY_V and code != KEY_G:
		return
	for action in InputMap.get_actions():  # never steal a key the player bound to something
		if not String(action).begins_with("ui_") and InputMap.event_is_action(event, action, true):
			return
	if code == KEY_V and voxel_mode:
		view_index = (view_index + 1) % VIEWS.size()
		_show_hint("CAMERA: %s   (V)" % VIEWS[view_index][2])
	elif code == KEY_G:
		voxel_mode = not voxel_mode
		_apply_mode()
		_show_hint("VOXEL WORLD   (G)" if voxel_mode else "ORIGINAL 2D   (G)")
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
		e.background_color = Color(0.03, 0.035, 0.06)
		e.ambient_light_color = amb.lerp(Color(0.35, 0.42, 0.7), 0.4)
		e.ambient_light_energy = 0.34
		e.glow_intensity = 0.9
		e.glow_hdr_threshold = 0.85
		e.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
		e.adjustment_saturation = 1.0
		e.tonemap_exposure = 1.15
		sun.light_color = Color(0.62, 0.7, 1.0)
		sun.light_energy = 0.32
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

func _build_cars() -> void:
	var holder := Node3D.new()
	holder.name = "Cars"
	add_child(holder)
	var layout: WheelLayout = main.wheel_layout
	for i in main.cars.size():
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
		cars3d.append({
			"root": root, "tilt": tilt, "body": body, "wheels": wheels, "spins": spins, "lights": lights,
			"roll": 0.0, "pitch": 0.0, "spin": 0.0, "h": 0.0, "prev_v": Vector2.ZERO, "prev_pos": c.global_position,
			"brake": 0.0,
		})


func _sync_cars(delta: float) -> void:
	var lp: LightingPilot = main.lighting
	var night := lp != null and lp.enabled
	var elevated: bool = main.track.layout.has_elevation()
	var dv: DamageView = main.damage_view
	for i in cars3d.size():
		var d: Dictionary = cars3d[i]
		var c: Car = main.cars[i]
		var root: Node3D = d.root
		root.visible = c.visible
		if not c.visible:
			continue
		var pos := c.global_position
		var rot := c.global_rotation
		# height: bridge deck, kerbs, jumps
		var h := 0.0
		if elevated and main.draw_level_of(i) == 1:
			h = vtrack.deck_height_px(main.progress[i].distance)
		else:
			h = clampf(vtrack.height_px_at(pos), 0.0, VoxelTrack.KERB_H * VoxelTrack.CELL)
		if main.jumps != null:
			h += main.jumps.height(i)
			if main.jumps.is_down(i):
				h = -2.0 if main.jumps.is_down_in_flyover(i) else VoxelTrack.PIT_H * VoxelTrack.CELL
		var moved: float = (pos - d.prev_pos).length()
		if moved > 60.0:  # placed / respawned: no smoothing
			d.h = h
		else:
			d.h = lerpf(d.h, h, 1.0 - exp(-delta * 18.0))
		root.position = Vox.to3(pos, d.h)
		root.rotation = Vector3(0.0, Vox.yaw(rot), 0.0)
		# body roll and pitch from the car's acceleration (presentation only)
		var vel: Vector2 = c.model.velocity if c.model != null else Vector2.ZERO
		var fwd := Vector2.from_angle(rot)
		var right := Vector2(-fwd.y, fwd.x)
		var acc := Vector2.ZERO
		if delta > 0.0 and moved < 60.0:
			acc = (vel - (d.prev_v as Vector2)) / delta
		var a_lat := acc.dot(right)
		var a_long := acc.dot(fwd)
		var k := 1.0 - exp(-delta * 7.0)
		d.roll = lerpf(d.roll, clampf(a_lat * 0.00011, -0.11, 0.11), k)
		d.pitch = lerpf(d.pitch, clampf(-a_long * 0.00006, -0.05, 0.06), k)
		if c.airborne:
			d.pitch = lerpf(d.pitch, -0.08, k)
		(d.tilt as Node3D).rotation = Vector3(d.roll, 0.0, d.pitch)
		# braking (brake lights by day too)
		var along := vel.dot(fwd)
		var braking := a_long < -110.0 and along > 30.0
		d.brake = lerpf(d.brake, 1.0 if braking else 0.0, 1.0 - exp(-delta * 12.0))
		# wheels: steering (CarWheels' smoothed value) and rolling
		var steer := 0.0
		var cw := c.get_node_or_null("Wheels")
		if cw != null:
			steer = float(cw.get("_steer"))
		var steer_angle := CarWheels.steer_angle(main.wheel_layout, steer)
		var forward_px := (pos - (d.prev_pos as Vector2)).dot(fwd) if moved < 60.0 else 0.0
		d.spin = fposmod(d.spin - forward_px / (VoxelCars.WHEEL_R * Vox.CAR_VOXEL_PX), TAU)
		var wheels: Array = d.wheels
		var spins: Array = d.spins
		for w in 4:
			(wheels[w] as Node3D).rotation.y = -steer_angle if w < 2 else 0.0
			(spins[w] as Node3D).rotation.z = d.spin
		# paint: junker tints, fallen tint, wear; lamps
		var body: MeshInstance3D = d.body
		var tint := c.sprite.modulate * c.sprite.self_modulate
		body.set_instance_shader_parameter("tint", tint)
		if dv != null:
			body.set_instance_shader_parameter("wear", dv.wear_of(i))
		var hb := 0.0
		var head_col := LightingPilot.HEADLIGHT_COLOR
		if lp != null:
			head_col = lp.head_color_of(c.racer_id)
			if i < lp.high_beam.size():
				hb = lp.high_beam[i]
		body.set_instance_shader_parameter("head_tint", head_col)
		body.set_instance_shader_parameter("head_glow", (0.55 + 0.35 * hb) if night else 0.0)
		body.set_instance_shader_parameter("tail_glow", (0.3 + 0.7 * d.brake) if night else 0.7 * d.brake)
		if night:
			var lights: Array = d.lights
			for s in 2:
				var spot: SpotLight3D = lights[s]
				spot.spot_range = 20.0 * lerpf(1.0, LightingPilot.HIGH_BEAM_SCALE, hb)
				spot.light_energy = 5.0 * lerpf(1.0, LightingPilot.HIGH_BEAM_ENERGY, hb)
				spot.light_color = head_col
			(lights[2] as OmniLight3D).light_energy = 0.7 + 1.6 * d.brake
		d.prev_v = vel
		d.prev_pos = pos


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
	if main.scenery != null:
		for s in main.scenery.get_children():
			if s is Sprite2D:
				sprites.append(s)
	var branches: Node = main.track.get_node_or_null("Branches")
	if branches != null:
		for s in branches.get_children():
			if s is Sprite2D:
				sprites.append(s)
	for spr in sprites:
		var logical := _logical_of(spr.texture)
		if logical.is_empty():
			continue
		var kind := VoxelProps.kind_of(logical)
		var spec: Dictionary = AssetCatalog.SPECS.get(logical, {})
		var nominal: Vector2 = spec.get("display_size", spr.texture.get_size())
		var frame_size := spr.texture.get_size() / Vector2(maxi(1, spr.hframes), maxi(1, spr.vframes))
		var shown := frame_size * spr.global_scale.abs()
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
		var v := _rng.randf_range(-0.05, 0.05)
		mi.set_instance_shader_parameter("tint", Color(1.0 + v, 1.0 + v * 0.6, 1.0 + v * 0.3))
		if VoxelProps.sways(kind):
			mi.set_instance_shader_parameter("sway", 0.006 if kind == VoxelProps.Kind.FLAG else 0.004)
		if kind == VoxelProps.Kind.FLOOD:
			_glowing.append(mi)
		holder.add_child(mi)


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
		light.light_energy = lp.lamp_energy * 5.5
		light.shadow_enabled = false
		light.visible = false
		holder.add_child(light)
		lamps3d.append(light)


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
	if not ready_3d or not voxel_mode:
		return
	_sync(delta)


func _sync(delta: float) -> void:
	var night: bool = main.lighting != null and main.lighting.enabled
	if int(night) != _night:
		_night = int(night)
		_apply_time_of_day(night)
	var view: Array = VIEWS[view_index]
	var pitch := deg_to_rad(view[0])
	var zoom: float = view[1]
	var cam2: Camera2D = main.camera
	var centre := cam2.get_screen_center_position()
	var z2 := Vector2(zoom, zoom * sin(pitch))
	cam2.zoom = z2
	_place_camera(camera, centre, pitch, zoom)
	_sync_cars(delta)
	# tyre marks: the decal viewport covers the visible ground (plus a margin)
	var dz := z2 * (float(DECAL_SIZE.x) / 1280.0) / DECAL_MARGIN
	decal_vp.canvas_transform = Transform2D(0.0, dz, 0.0, Vector2(DECAL_SIZE) * 0.5 - centre * dz)
	var m := vtrack.terrain_material
	m.set_shader_parameter("decal_cam", centre)
	m.set_shader_parameter("decal_zoom", dz)
	m.set_shader_parameter("decal_size", Vector2(DECAL_SIZE))
	if main.get("player_views") != null and _split_cams.size() > 0:
		_sync_split_views(pitch, zoom)


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
