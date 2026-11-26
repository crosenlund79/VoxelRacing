extends SubViewport
## VoxelRacing: the garage as a miniature voxel workshop, rendered in its own
## 3D world behind the garage screen (GarageScreen shows this viewport's
## texture in place of the old 2D backdrop).
##
## The car being prepared stands on a slowly turning turntable under a warm
## spotlight, built from its own voxel model (VoxelCars) and showing its
## current damage (VoxelCarDamage, from the garage's condition). Around it:
## a brick and panel workshop with a red tool chest, a workbench with a
## pegboard, shelves, a weapons rack with the voxel missiles and mines, tyre
## stacks, crates, oil drums, racing posters, a flickering neon sign, a
## turning wall fan, a swinging work lamp, a safety board that never gets
## past zero, and a mechanic who potters about. The camera drifts slowly.
##
## Repairs: the mechanic rushes in and hammers, the missing voxels pop back in
## a few steps with sparks and stars (VoxelFx), and the mended car shines.
##
## Presentation only: it never touches the garage's rules or money. Rendered
## and processed only while the garage is on screen; built the first time the
## garage opens. Loaded with preload (no class_name).

const Props := preload("res://src/ui/garage_workshop_props.gd")
const Mechanic := preload("res://src/ui/garage_mechanic.gd")

## Design resolution of the screen it fills.
const BASE := Vector2i(1280, 720)
## Where the car stands on screen (the band above the garage's panels).
const CAR_SCREEN := Vector2(585, 130)
const FOV := 38.0
const TABLE_R := 2.5
const TABLE_TOP := 0.25
const BACK_Z := -4.6
const FRONT_Z := 9.0
const ROOM_X := 9.5
const ROOM_H := 6.0
const SPIN := 0.2
## Where the mechanic works on the car, and the car's middle.
const REPAIR_SPOT := Vector3(-2.95, 0, 0.45)
const CAR_MIDDLE := Vector3(0, 0.75, 0)
## Repair show: pops start after REPAIR_DELAY, one step every REPAIR_STEP s.
const REPAIR_STEPS := 6
const REPAIR_DELAY := 0.3
const REPAIR_STEP := 0.16
const NEIGHBOURS: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
	Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]

var _resolver: AssetResolver
var _layout: WheelLayout
var _built := false
var _active := false
var _cam: Camera3D
var _table: Node3D
var _car: Node3D
var _body: MeshInstance3D
var _wheels: Array[MeshInstance3D] = []
var _mech: Mechanic
var _fx: VoxelFx
var _fan: Node3D
var _swing: Node3D
var _neon_pit: MeshInstance3D
var _neon_stop: MeshInstance3D
var _neon_tube: MeshInstance3D
var _neon_light: OmniLight3D
var _glint: OmniLight3D
var _tick: AudioStreamPlayer
var _ding: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
var _time := 0.0
var _spin_speed := SPIN
var _zoom := 0.0
var _shine := 0.0

# the car shown
var _tex: Texture2D
var _logical := ""
var _wheels_on := true
var _car_pending := false
var _pristine: VoxelVehicle.Model
var _pristine_mesh: ArrayMesh
var _seed := 7
var _damage: VoxelCarDamage
var _want := 100.0   ## the condition asked for
var _shown := -1.0   ## the condition shown (or being repaired towards)
var _rep: Dictionary = {}
var _fit_t := 0.0


func _init() -> void:
	size = BASE
	own_world_3d = true
	transparent_bg = false
	msaa_3d = Viewport.MSAA_2X
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	process_mode = Node.PROCESS_MODE_DISABLED


func setup(resolver: AssetResolver) -> void:
	_resolver = resolver


## On screen (renders and animates) or put away (costs nothing).
func set_active(on: bool) -> void:
	if on == _active:
		return
	_active = on
	if on:
		_build()
		_fit_resolution()
		if _car_pending:
			_apply_car()
	elif _built:  # put away: any show ends at once
		_finish_repair()
		_fit_t = 0.0
		_shine = 0.0
		_glint.visible = false
		_body.set_instance_shader_parameter("head_glow", 0.25)
		_body.set_instance_shader_parameter("tail_glow", 0.2)
		_body.set_instance_shader_parameter("tint", Color.WHITE)
	render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


## The car on the turntable: its body drawing, body logical name, whether it
## has the shared wheels, and its condition (0..100).
func set_car(tex: Texture2D, logical: String, wheels: bool, condition: float) -> void:
	_tex = tex
	_logical = logical
	_wheels_on = wheels
	_want = condition
	_car_pending = true
	if _built:
		_apply_car()


## The car's condition (0..100): shown at once, or with the repair show when it
## went up while the workshop is on screen (`animate`).
func set_condition(c: float, animate: bool) -> void:
	_want = c
	if not _built or _pristine == null or absf(c - _shown) < 0.01:
		return
	if animate and _active and c > _shown:
		_start_repair(c)
	else:
		_finish_repair()
		_show_condition(c)


func is_repairing() -> bool:
	return not _rep.is_empty()


## A part fitted (armour, an upgrade): the mechanic hurries over and hammers
## it on, the car twinkles. Nothing about the car's model changes.
func fit_part() -> void:
	if not _built or not _active or is_repairing():
		return
	_mech.rush_to(REPAIR_SPOT, CAR_MIDDLE, 0.9)
	_fit_t = 1.25  # the twinkle once he is done


# ------------------------------------------------------------ building

func _fit_resolution() -> void:
	# render at the window's own pixel size (crisp at 1080p), capped for cost
	var win := Vector2(get_tree().root.size) if is_inside_tree() else Vector2(BASE)
	var s := clampf(minf(win.x / BASE.x, win.y / BASE.y), 0.5, 1.5)
	size = Vector2i(roundi(BASE.x * s), roundi(BASE.y * s))


func _build() -> void:
	if _built:
		return
	_built = true
	_rng.seed = 4242
	_layout = load("res://src/presentation/default_wheel_layout.tres")
	_build_environment()
	_build_room()
	_build_turntable()
	_build_furniture()
	_fx = VoxelFx.new()
	add_child(_fx)
	_fx.ground = func(x: float, z: float) -> float:
		return TABLE_TOP if Vector2(x, z).length() < TABLE_R else 0.0
	_build_mechanic()
	_build_camera()
	_tick = AudioStreamPlayer.new()
	_tick.bus = "Effects"
	_tick.volume_db = -7.0
	add_child(_tick)
	_ding = AudioStreamPlayer.new()
	_ding.bus = "Effects"
	_ding.volume_db = -3.0
	add_child(_ding)


func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = VrStyle.INK
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.55, 0.92)
	e.ambient_light_energy = 0.5
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.1
	e.glow_enabled = true
	e.glow_intensity = 0.5
	e.glow_bloom = 0.04
	e.glow_hdr_threshold = 0.9
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.12
	we.environment = e
	add_child(we)
	# a cool fill from the open door behind the camera
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.6, 0.66, 1.0)
	fill.light_energy = 0.35
	fill.basis = Basis.looking_at(Vector3(0.35, -0.6, -1.0).normalized(), Vector3.UP)
	add_child(fill)
	# the key light: a warm spot on the turntable
	var key := SpotLight3D.new()
	key.position = Vector3(0.8, 6.2, 2.6)
	key.light_color = Color(1.0, 0.92, 0.8)
	key.light_energy = 10.0
	key.spot_range = 14.0
	key.spot_angle = 30.0
	key.spot_angle_attenuation = 0.7
	key.shadow_enabled = true
	add_child(key)
	key.look_at(Vector3(0, 0.4, 0), Vector3.UP)
	# a narrow fill from the camera's side, on the car only
	var front := SpotLight3D.new()
	front.position = Vector3(2.5, 3.2, 8.0)
	front.light_color = Color(0.85, 0.88, 1.0)
	front.light_energy = 5.0
	front.spot_range = 14.0
	front.spot_angle = 13.0
	front.spot_angle_attenuation = 1.4
	add_child(front)
	front.look_at(Vector3(0, 0.6, 0), Vector3.UP)
	_glint = OmniLight3D.new()
	_glint.position = Vector3(0.4, 1.9, 1.4)
	_glint.light_color = Color(1.0, 0.97, 0.88)
	_glint.omni_range = 4.5
	_glint.light_energy = 0.0
	_glint.visible = false
	add_child(_glint)


func _mi(mesh: Mesh, at: Vector3, parent: Node = self, yaw: float = 0.0) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = at
	m.rotation.y = yaw
	parent.add_child(m)
	return m


func _build_room() -> void:
	_mi(Props.floor_mesh(-ROOM_X, ROOM_X, BACK_Z, FRONT_Z, TABLE_R), Vector3.ZERO)
	_mi(Props.wall_mesh(ROOM_X * 2.0, ROOM_H), Vector3(-ROOM_X, 0, BACK_Z))
	var side := Props.wall_mesh(FRONT_Z - BACK_Z, ROOM_H, 3)
	_mi(side, Vector3(-ROOM_X, 0, FRONT_Z), self, PI * 0.5)
	_mi(side, Vector3(ROOM_X, 0, BACK_Z), self, -PI * 0.5)


func _build_turntable() -> void:
	_table = Node3D.new()
	add_child(_table)
	_mi(Props.turntable_mesh(TABLE_R), Vector3.ZERO, _table)
	_car = Node3D.new()
	_car.position.y = TABLE_TOP
	_table.add_child(_car)
	_body = MeshInstance3D.new()
	_body.set_instance_shader_parameter("head_glow", 0.25)
	_body.set_instance_shader_parameter("tail_glow", 0.2)
	_car.add_child(_body)
	for k in 4:
		var w := MeshInstance3D.new()
		w.mesh = VoxelCars.wheel_mesh()
		w.set_instance_shader_parameter("tint", Color(0.62, 0.62, 0.68))  # hubs less glaring side-on
		_car.add_child(w)
		_wheels.append(w)


func _build_furniture() -> void:
	var wall := BACK_Z
	# left: the red tool chest and a poster (behind the title), the workbench
	# with its pegboard under a swinging lamp, the wall fan
	_mi(Props.tool_cabinet_mesh(), Vector3(-9.3, 0, wall))
	_mi(Props.poster_mesh(0), Vector3(-6.95, 0.3, wall + 0.01))
	_mi(Props.poster_mesh(1), Vector3(-ROOM_X + 0.01, 0.35, -2.2), self, PI * 0.5)
	_mi(Props.drum_mesh(VrStyle.RED), Vector3(-8.9, 0, -1.0))
	_mi(Props.drum_mesh(Color("2b6f8c")), Vector3(-8.75, 0, 0.0), self, 1.0)
	_mi(Props.workbench_mesh(), Vector3(-6.05, 0, wall))
	_mi(Props.pegboard_mesh(), Vector3(-6.05, 1.2, wall))
	_swing = Node3D.new()
	_swing.position = Vector3(-4.55, 5.0, wall + 0.8)
	add_child(_swing)
	_lamp(_swing, 2.75)
	_mi(Props.fan_housing_mesh(), Vector3(-2.15, 1.45, wall + 0.01))
	_fan = Node3D.new()
	_fan.position = Vector3(-2.15, 1.45, wall + 0.16)
	add_child(_fan)
	_mi(Props.fan_blades_mesh(), Vector3.ZERO, _fan)
	# the neon sign over the car: "STOP" is an old tube that stutters now and then
	var neon := Props.neon_meshes("PIT", "STOP", VrStyle.PINK, VrStyle.TEAL)
	var at := Vector3(0.1, 1.3, wall + 0.01)
	_mi(neon[0], at)
	_neon_pit = _mi(neon[1], at + Vector3(0, 0, 0.01))
	_neon_stop = _mi(neon[2], at + Vector3(0, 0, 0.01))
	_neon_tube = _mi(neon[3], at + Vector3(0, 0, 0.01))
	_neon_pit.set_instance_shader_parameter("lamp_glow", 0.6)
	_neon_stop.set_instance_shader_parameter("lamp_glow", 0.6)
	_neon_tube.set_instance_shader_parameter("lamp_glow", 0.45)
	_neon_light = OmniLight3D.new()
	_neon_light.position = at + Vector3(0, 0.45, 0.9)
	_neon_light.light_color = VrStyle.PINK
	_neon_light.omni_range = 4.0
	_neon_light.light_energy = 1.1
	add_child(_neon_light)
	# right: the safety board over a stack of crates, the weapons rack, tyres,
	# shelves along the right wall, an oil drum
	_mi(Props.safety_sign_mesh(), Vector3(3.8, 1.2, wall + 0.01))
	var crate := Props.crate_mesh()
	_mi(crate, Vector3(3.1, 0, wall + 0.5), self, 0.1)
	_mi(crate, Vector3(4.6, 0, wall + 0.55), self, -0.25)
	var rack := _mi(Props.rack_mesh(), Vector3(5.75, 0.45, wall))
	var kinds := ["super", "homing", "missile"]
	for k in kinds.size():
		var m := _mi(VoxelWeapons.missile_mesh(kinds[k]), Vector3(1.25, 0.72 + k * 0.36, 0.28), rack)
		m.set_instance_shader_parameter("lamp_glow", 0.15)
	for k in 2:
		var mine := _mi(VoxelWeapons.mine_mesh(), Vector3(0.68 + k * 1.15, 0.25, 0.32), rack, k * 0.6)
		mine.set_instance_shader_parameter("lamp_glow", 0.5)
	_mi(Props.crate_mesh(true), Vector3(8.0, 0, -0.2), self, 0.3)
	_mi(Props.crate_mesh(true), Vector3(8.05, 0.75, -0.15), self, 0.1)
	_mi(Props.shelves_mesh(), Vector3(ROOM_X, 0, wall + 0.1), self, -PI * 0.5)
	_mi(Props.poster_mesh(2), Vector3(ROOM_X - 0.01, 0.35, 1.4), self, -PI * 0.5)
	var lamp_r := Node3D.new()
	lamp_r.position = Vector3(7.0, 5.0, wall + 2.1)
	add_child(lamp_r)
	_lamp(lamp_r, 2.75)
	var tyre := VoxelCars.wheel_mesh()
	var tyre_h := VoxelVehicle.WHEEL_W * VoxelVehicle.vs()
	for k in 4:
		_mi(tyre, Vector3(8.3, tyre_h * (k + 0.5), -2.4), self, k * 0.4).rotation.x = PI * 0.5
	for k in 3:
		_mi(tyre, Vector3(7.55, tyre_h * (k + 0.5), -1.7), self, k * 0.7).rotation.x = PI * 0.5
	var leaning := _mi(tyre, Vector3(8.6, 0.36, -0.9), self, 0.2)
	leaning.rotation = Vector3(0, PI * 0.5, 0.25)
	_mi(Props.drum_mesh(Color("2b6f8c")), Vector3(8.6, 0, 2.6))


## A hanging work lamp under `pivot` (the ceiling hook), its shade `cable`
## units below, with its warm light.
func _lamp(pivot: Node3D, cable: float) -> void:
	var m := _mi(Props.lamp_mesh(cable), Vector3(0, -cable, 0), pivot)
	m.set_instance_shader_parameter("lamp_glow", 0.5)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var l := OmniLight3D.new()
	l.position = Vector3(0, -cable - 0.6, 0)
	l.light_color = Color(1.0, 0.72, 0.42)
	l.omni_range = 5.0
	l.omni_attenuation = 1.2
	l.light_energy = 2.2
	pivot.add_child(l)


func _build_mechanic() -> void:
	_mech = Mechanic.new()
	add_child(_mech)
	_mech.spots = [
		{"pos": Vector3(-4.55, 0, BACK_Z + 1.25), "face": Vector3(-4.55, 1, BACK_Z), "act": "tinker", "time": 6.0},
		{"pos": Vector3(-2.95, 0, 0.75), "face": CAR_MIDDLE, "act": "polish", "time": 5.0},
		{"pos": Vector3(-8.55, 0, BACK_Z + 1.3), "face": Vector3(-8.55, 1, BACK_Z), "act": "rummage", "time": 3.5},
		{"pos": Vector3(-3.8, 0, 1.9), "face": CAR_MIDDLE, "act": "look", "time": 4.0},
		{"pos": Vector3(-5.6, 0, -1.4), "face": CAR_MIDDLE, "act": "look", "time": 3.0},
	]
	_mech.camera_hint = Vector3(0, 2, 14)
	_mech.place(Vector3(-2.95, 0, 0.75), CAR_MIDDLE)
	_mech.struck.connect(_on_struck)


func _build_camera() -> void:
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_FRUSTUM
	_cam.near = 0.2
	_cam.far = 90.0
	# a shifted lens: the car sits in the band above the panels, perspective intact
	var h := 2.0 * _cam.near * tan(deg_to_rad(FOV) * 0.5)
	var w := h * float(BASE.x) / BASE.y
	var ndc := Vector2(CAR_SCREEN.x / BASE.x * 2.0 - 1.0, 1.0 - CAR_SCREEN.y / BASE.y * 2.0)
	_cam.size = h
	_cam.frustum_offset = Vector2(-ndc.x * w * 0.5, -ndc.y * h * 0.5)
	add_child(_cam)
	_cam.make_current()
	_place_camera()


func _place_camera() -> void:
	var yaw := 0.08 + sin(_time * 0.071) * 0.24
	var dist := 11.2 + sin(_time * 0.047 + 1.3) * 0.45 - _zoom * 0.9
	var height := 1.3 + sin(_time * 0.061) * 0.12 + _zoom * 0.1
	_cam.position = CAR_MIDDLE + Vector3(sin(yaw) * dist, height, cos(yaw) * dist)
	_cam.look_at(CAR_MIDDLE, Vector3.UP)
	if _mech != null:
		_mech.camera_hint = _cam.position


# ------------------------------------------------------------ the car

func _apply_car() -> void:
	_car_pending = false
	_finish_repair()
	_pristine_mesh = VoxelCars.body_mesh(_tex, _layout, _logical)
	_pristine = VoxelCars.model(_tex, _logical)
	_body.mesh = _pristine_mesh
	_seed = absi(hash(_logical)) % 100000 + 7
	var at := VoxelCars.wheels_of(_layout, _tex, _logical)
	var k := 0
	for ax in [at.x, at.y]:
		for az in [-at.z, at.z]:
			_wheels[k].position = Vector3(ax, VoxelCars.WHEEL_R * Vox.CAR_VOXEL_PX, az) * Vox.PX
			_wheels[k].visible = _wheels_on
			_wheels[k].scale.z = _pristine.tyre.x if k < 2 else _pristine.tyre.y
			k += 1
	_damage = null
	_shown = -1.0
	_show_condition(_want)


## The car's damage for a condition: the same seed always takes off the same
## components, so a better condition is a subset of a worse one.
func _damage_for(c: float) -> VoxelCarDamage:
	var d := VoxelCarDamage.new(_pristine, null, _seed)
	d.preset(VoxelCarDamage.target_loss(clampf(c / 100.0, 0.0, 1.0)))
	return d


func _show_condition(c: float) -> void:
	_shown = c
	_damage = _damage_for(c)
	_put_on(_damage)


func _put_on(d: VoxelCarDamage) -> void:
	_body.mesh = _pristine_mesh
	d.mesh_instance = _body
	d.rebuild()
	d._apply()


# ------------------------------------------------------------ repairs

func _start_repair(c: float) -> void:
	_finish_repair()
	var from := _damage if _damage != null else _damage_for(_shown)
	var to := _damage_for(c)
	_shown = c
	# the components to put back (and the battered ones to beat straight)
	var cells: Array[int] = []
	for k in from.gone.size():
		if (from.gone[k] == 1 and to.gone[k] == 0) or (from.hurt[k] == 1 and to.hurt[k] == 0):
			cells.append(k)
	cells.shuffle()
	_put_on(from)
	_rep = {"t": 0.0, "from": from, "to": to, "cells": cells, "done": 0}
	_mech.rush_to(REPAIR_SPOT, CAR_MIDDLE, REPAIR_DELAY + REPAIR_STEPS * REPAIR_STEP + 0.35)


func _step_repair(delta: float) -> void:
	if _rep.is_empty():
		return
	_rep.t = float(_rep.t) + delta
	var t: float = _rep.t
	while int(_rep.done) < REPAIR_STEPS and t >= REPAIR_DELAY + int(_rep.done) * REPAIR_STEP:
		_rep.done = int(_rep.done) + 1
		_restore_step(int(_rep.done))
	if int(_rep.done) >= REPAIR_STEPS and t >= REPAIR_DELAY + REPAIR_STEPS * REPAIR_STEP + 0.08:
		_finish_repair()
		_shine_now()


## Puts back the k-th share of the missing components (1..REPAIR_STEPS),
## with sparks and a star where they land.
func _restore_step(k: int) -> void:
	var from: VoxelCarDamage = _rep.from
	var to: VoxelCarDamage = _rep.to
	var cells: Array[int] = _rep.cells
	var n := cells.size()
	var a := (k - 1) * n / REPAIR_STEPS
	var b := k * n / REPAIR_STEPS
	var xf := _body.global_transform
	for i in range(a, b):
		var id := cells[i]
		from.gone[id] = to.gone[id]
		from.hurt[id] = to.hurt[id]
		_sparks(xf * (_pristine.parts[id].centre as Vector3), 5)
	if n == 0:  # nothing visible to mend (light scratches): sparks on the bodywork
		for s2 in 3:
			_sparks(_car.global_transform * Vector3(_rng.randf_range(-1.6, 1.6), _rng.randf_range(0.5, 1.1), _rng.randf_range(-0.8, 0.8)), 4)
	else:
		from._count_lamps()
		from._apply()
	var top := xf * Vector3(_rng.randf_range(-1.2, 1.2), 1.3, _rng.randf_range(-0.6, 0.6))
	_fx.star(top, Vector3(_rng.randf_range(-0.8, 0.8), 3.2, _rng.randf_range(-0.8, 0.8)),
		[VrStyle.YELLOW, VrStyle.PAPER, Color(1.0, 0.62, 0.25)][k % 3], 0.42, 0.75)
	_play(_tick, "ui/ui_move", 0.85 + k * 0.09)


func _finish_repair() -> void:
	if _rep.is_empty():
		return
	var to: VoxelCarDamage = _rep.to
	_rep = {}
	_damage = to
	_put_on(to)


## The mended car shines: a glint of light, the head lamps blink, the paint
## brightens for a moment and little white stars sparkle on it.
func _shine_now() -> void:
	_shine = 1.0
	_glint.visible = true
	var xf := _body.global_transform
	for k in 7:
		var p := xf * Vector3(_rng.randf_range(-1.7, 1.7), _rng.randf_range(0.8, 1.35), _rng.randf_range(-0.9, 0.9))
		_fx.star(p, Vector3(0, _rng.randf_range(0.6, 1.4), 0), Color(1.0, 1.0, 0.92), _rng.randf_range(0.26, 0.4), _rng.randf_range(0.6, 0.95))
	_play(_ding, "ui/ui_select", 1.25)


func _sparks(at: Vector3, n: int) -> void:
	for k in n:
		var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.4, 1.4), _rng.randf_range(-1, 1)).normalized()
		_fx.spark(at, dir * _rng.randf_range(2.0, 4.5), Color(1.0, _rng.randf_range(0.78, 1.0), _rng.randf_range(0.35, 0.65)),
			0.06, _rng.randf_range(0.2, 0.4), 1.3, 0.8)


func _on_struck(at: Vector3) -> void:
	if _mech.is_busy_repairing():
		_sparks(at, 7)
		if _rng.randf() < 0.35:
			_fx.star(at + Vector3(0, 0.2, 0), Vector3(_rng.randf_range(-0.6, 0.6), 2.6, _rng.randf_range(-0.6, 0.6)), VrStyle.YELLOW, 0.3, 0.55)
	else:
		_sparks(at, 2)  # tinkering at the bench


func _play(player: AudioStreamPlayer, logical: String, pitch: float) -> void:
	if _resolver == null:
		return
	player.stream = _resolver.get_audio(logical)
	player.pitch_scale = pitch
	player.play()


# ------------------------------------------------------------ motion

func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	_time += delta
	_step_repair(delta)
	if _fit_t > 0.0:
		_fit_t -= delta
		if _fit_t <= 0.0:
			_shine_now()
	var busy := is_repairing() or _mech.is_busy_repairing()
	# the turntable stops while the mechanic works, the camera leans in
	_spin_speed = move_toward(_spin_speed, 0.0 if busy else SPIN, delta * (0.8 if busy else 0.12))
	_table.rotation.y = fposmod(_table.rotation.y + _spin_speed * delta, TAU)
	_zoom = move_toward(_zoom, 1.0 if busy else 0.0, delta * (1.6 if busy else 0.5))
	_place_camera()
	# little things that move
	_fan.rotation.z -= delta * 7.0
	_swing.rotation.z = sin(_time * 1.25) * 0.06
	_swing.rotation.x = sin(_time * 0.83 + 1.0) * 0.035
	var flick := 1.0
	var ph := fposmod(_time, 9.0)
	if ph > 7.6:  # the old tube stutters now and then
		flick = 0.12 if fposmod(_time * 13.0, 1.0) < 0.45 + 0.3 * sin(_time * 5.0) else 1.0
	_neon_stop.set_instance_shader_parameter("lamp_glow", 0.6 * flick)
	_neon_light.light_energy = 1.1 * (0.35 + 0.65 * flick)
	# the shine after a repair
	if _shine > 0.0:
		_shine = maxf(0.0, _shine - delta / 1.1)
		var s := _shine * _shine
		_glint.light_energy = 5.0 * s
		_glint.visible = _shine > 0.0
		var u := 1.0 - _shine  # 0 .. 1 over the shine
		var blink := 1.0 if (u < 0.55 and fposmod(u, 0.26) < 0.13) else 0.0
		_body.set_instance_shader_parameter("head_glow", 0.25 + 2.2 * blink)
		_body.set_instance_shader_parameter("tail_glow", 0.2 + 1.4 * blink)
		_body.set_instance_shader_parameter("tint", Color(1, 1, 1).lerp(Color(1.3, 1.27, 1.17), s))
