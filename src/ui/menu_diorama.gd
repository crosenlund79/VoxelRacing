class_name MenuDiorama
extends Node3D
## The main menu's backdrop: a floating voxel island with a little circuit on
## it, at golden hour. Voxel cars (the game's own models; the player's chosen
## car among them) lap it with their own rhythms, overtaking each other; a
## grandstand, trees, lamp posts and flags line it; the camera drifts slowly
## around the island with a tilt-shift blur, like a model railway.

const VS := 0.25
const NX := 168
const NZ := 120
const ROAD_W := 30
const CARS := ["cars/body_player", "cars/body_ai_1", "cars/body_ai_2", "cars/body_ai_3", "cars/body_ai_5", "cars/body_ai_6", "cars/body_ai_9"]
const TILT_SHADER := preload("res://src/voxel/shaders/tilt_shift.gdshader")

var camera: Camera3D
var _env: WorldEnvironment
var _environment: Environment
var _path := Curve3D.new()
var _length := 0.0
var _cars: Array[Node3D] = []
var _bodies: Array[MeshInstance3D] = []
var _wheels: Array = []
var _s := PackedFloat32Array()
var _lane := PackedFloat32Array()
var _speed := PackedFloat32Array()
var _time := 0.0
var _fx: VoxelFx
var _rng := RandomNumberGenerator.new()
var _resolver := AssetResolver.new()
var _layout: WheelLayout = load("res://src/presentation/default_wheel_layout.tres")

static var _island: ArrayMesh


func _ready() -> void:
	_rng.seed = 2026
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("2b2550")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.58, 0.9)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.05
	e.ssao_enabled = true
	e.ssao_radius = 0.8
	e.ssao_intensity = 1.6
	e.glow_enabled = true
	e.glow_intensity = 0.55
	e.glow_hdr_threshold = 0.95
	e.fog_enabled = true
	e.fog_light_color = Color("5a3f7a")
	e.fog_density = 0.006
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.15
	env.environment = e
	add_child(env)
	_env = env
	_environment = e
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.78, 0.52)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 110.0
	sun.basis = Basis.looking_at(Vector3(-0.75, -0.55, -0.4).normalized(), Vector3.UP)
	add_child(sun)
	var island := MeshInstance3D.new()
	island.mesh = island_mesh()
	add_child(island)
	_build_path()
	_build_props()
	_fx = VoxelFx.new()
	add_child(_fx)
	_fx.ground = func(_x: float, _z: float) -> float: return 0.0
	for k in CARS.size():
		_add_car(CARS[k], k)
	camera = Camera3D.new()
	camera.fov = 34.0
	camera.near = 0.5
	camera.far = 300.0
	add_child(camera)
	var tilt := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	tilt.mesh = quad
	tilt.extra_cull_margin = 16384.0
	tilt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tm := ShaderMaterial.new()
	tm.shader = TILT_SHADER
	tm.set_shader_parameter("amount", 2.4)
	tm.set_shader_parameter("band", 0.3)
	tm.render_priority = Material.RENDER_PRIORITY_MIN  # under the exhaust puffs (see VoxelStage)
	tilt.material_override = tm
	camera.add_child(tilt)
	tilt.position = Vector3(0, 0, -1.0)
	_place_camera()


## Shown with the title, or put away while a race uses the 3D world: an
## environment applies to the whole world even when hidden, so it is released.
func set_active(on: bool) -> void:
	visible = on
	set_process(on)
	_env.environment = _environment if on else null
	if on:
		camera.make_current()
	else:
		camera.clear_current()


## Shows the player's chosen car (a logical car image name) in the pack.
func set_player_car(logical: String) -> void:
	if _bodies.is_empty():
		return
	var body := AssetCatalog.body_of(logical)
	_bodies[0].mesh = VoxelCars.body_mesh(_resolver.get_texture(body), _layout, body)
	if not _wheels.is_empty():
		VoxelCars.place_wheels(_wheels[0], _layout, _resolver.get_texture(body), body)


func _add_car(logical: String, k: int) -> void:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	body.mesh = VoxelCars.body_mesh(_resolver.get_texture(logical), _layout, logical)
	body.set_instance_shader_parameter("head_glow", 0.35)
	body.set_instance_shader_parameter("tail_glow", 0.3)
	root.add_child(body)
	var at := VoxelCars.wheels_of(_layout, _resolver.get_texture(logical), logical)
	var ws: Array = []
	for ax in [at.x, at.y]:
		for az in [-at.z, at.z]:
			var w := MeshInstance3D.new()
			w.mesh = VoxelCars.wheel_mesh()
			w.position = Vector3(ax, VoxelCars.WHEEL_R * Vox.CAR_VOXEL_PX, az) * Vox.PX
			root.add_child(w)
			ws.append(w)
	add_child(root)
	_cars.append(root)
	_bodies.append(body)
	_wheels.append(ws)
	_s.append(_length * (1.0 - k * 0.075))
	_lane.append([-1.6, 1.4, -1.0, 1.8, -1.9, 0.6, -0.9][k % 7])
	_speed.append(11.0 + _rng.randf_range(-0.8, 0.8))


## The cars are choreographed, not simulated (P003): two lanes, each car
## keeps a safe gap to the one ahead in its lane, and only pulls out to
## overtake when the other lane is clear - so they race, but never touch.
const LANE := 1.65
const CAR_LEN := 4.4
const SAFE_GAP := 6.6
var _lane_target := PackedFloat32Array()
var _lane_rate := PackedFloat32Array()
var _v := PackedFloat32Array()
var _settle := PackedFloat32Array()


func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	_time += delta
	var n := _cars.size()
	if _v.size() != n:
		_v.resize(n)
		_lane_target.resize(n)
		_lane_rate.resize(n)
		_settle.resize(n)
		for k in n:
			_v[k] = _speed[k]
			_lane_target[k] = signf(_lane[k]) * LANE if absf(_lane[k]) > 0.1 else LANE
			_lane[k] = _lane_target[k]
	for k in n:
		# the pace this car would like: its own rhythm
		var want := _speed[k] + sin(_time * (0.3 + k * 0.07) + k * 2.1) * 1.1
		var ahead := _nearest(k, _lane_target[k], true)
		var here := _nearest(k, _lane[k], true)  # mid lane change: the old lane too
		if here[0] >= 0 and here[1] < ahead[1]:
			ahead = here
		if ahead[0] >= 0 and ahead[1] < SAFE_GAP + 2.0:
			var other := -_lane_target[k]
			_settle[k] -= delta
			# pull out when the other lane is clear alongside and a little ahead
			if want > _v[ahead[0]] + 0.3 and _settle[k] <= 0.0 and _clear(k, other):
				_lane_target[k] = other
				_settle[k] = 2.5
			else:  # tuck in behind: match its pace, a safe gap
				var gap: float = ahead[1]
				want = minf(want, _v[ahead[0]] - clampf((SAFE_GAP - gap) * 0.9, -0.4, 3.0))
		_v[k] = move_toward(_v[k], maxf(want, 3.0), delta * 4.0)
	for k in n:
		_s[k] = fposmod(_s[k] + _v[k] * delta, _length)
		var old_lane := _lane[k]
		_lane[k] = move_toward(_lane[k], _lane_target[k], delta * 1.4)
		_lane_rate[k] = (_lane[k] - old_lane) / maxf(delta, 0.001)
		var p := _path.sample_baked(_s[k], true)
		var ahead_p := _path.sample_baked(fposmod(_s[k] + 1.0, _length), true)
		var dir := (ahead_p - p).normalized()
		var right := Vector3(-dir.z, 0, dir.x)
		var car := _cars[k]
		car.position = p + right * _lane[k]
		var drift := atan2(_lane_rate[k], maxf(_v[k], 1.0))  # nose into the lane change
		car.basis = Basis.looking_at(-right, Vector3.UP).rotated(Vector3.UP, -drift)
		for w in (_wheels[k] as Array):
			(w as Node3D).rotation.z -= _v[k] * delta / (VoxelCars.WHEEL_R * Vox.CAR_VOXEL_PX * Vox.PX)
		if _rng.randf() < delta * 8.0:
			var back := car.global_transform * Vector3(-2.0, 0.2, 0.0)
			_fx.puff(back, Vector3(0, 0.5, 0), Color(0.95, 0.9, 0.85), _rng.randf_range(0.2, 0.32), 0.6, 0.45)
	_place_camera()


## The nearest car ahead of k (by distance along the circuit) whose lane
## overlaps `lane`: [index, gap] (index -1: none).
func _nearest(k: int, lane: float, _forward: bool) -> Array:
	var best := -1
	var best_d := INF
	for j in _cars.size():
		if j == k:
			continue
		if absf(_lane[j] - lane) > LANE * 1.4 and absf(_lane_target[j] - lane) > LANE * 1.4:
			continue
		var d := fposmod(_s[j] - _s[k], _length)
		if d < best_d:
			best_d = d
			best = j
	if best >= 0 and best_d < _length * 0.25:
		# the real distance (shorter than the arc on the inside of a bend)
		best_d = minf(best_d, _cars[k].position.distance_to(_cars[best].position))
	return [best, best_d]


## Whether `lane` is free beside car k (from a car length behind to a safe
## gap ahead).
func _clear(k: int, lane: float) -> bool:
	for j in _cars.size():
		if j == k:
			continue
		if absf(_lane[j] - lane) > LANE * 1.4 and absf(_lane_target[j] - lane) > LANE * 1.4:
			continue
		var d := fposmod(_s[j] - _s[k] + _length * 0.5, _length) - _length * 0.5
		if d > -CAR_LEN * 1.6 and d < SAFE_GAP + 1.5:
			return false
	return true


func _place_camera() -> void:
	if camera == null:
		return
	var a := _time * 0.06 + 0.6
	var centre := Vector3(-4.0, 0.0, 2.0)
	camera.position = centre + Vector3(cos(a) * 40.0, 26.0 + sin(_time * 0.2) * 1.5, sin(a) * 40.0)
	camera.look_at(centre + Vector3(0, -2.0, 0), Vector3.UP)
	# keep the island to the right of the menu column
	camera.h_offset = -9.0


# ------------------------------------------------------------ the island

## Centre line of the circuit (a rounded rectangle) in island cells.
static func _centre(t: float) -> Vector2:
	var hx := 52.0
	var hz := 30.0
	var r := 24.0
	var straight_x := (hx - r) * 2.0
	var straight_z := (hz - r) * 2.0
	var arc := PI * 0.5 * r
	var total := 2.0 * straight_x + 2.0 * straight_z + 4.0 * arc
	var d := fposmod(t, 1.0) * total
	var segs := [
		["line", Vector2(-hx + r, hz), Vector2(hx - r, hz)],
		["arc", Vector2(hx - r, hz - r), PI * 0.5, 0.0],
		["line", Vector2(hx, hz - r), Vector2(hx, -hz + r)],
		["arc", Vector2(hx - r, -hz + r), 0.0, -PI * 0.5],
		["line", Vector2(hx - r, -hz), Vector2(-hx + r, -hz)],
		["arc", Vector2(-hx + r, -hz + r), -PI * 0.5, -PI],
		["line", Vector2(-hx, -hz + r), Vector2(-hx, hz - r)],
		["arc", Vector2(-hx + r, hz - r), PI, PI * 0.5],
	]
	for seg in segs:
		var len: float = (seg[1] as Vector2).distance_to(seg[2]) if seg[0] == "line" else arc
		if d <= len:
			if seg[0] == "line":
				return (seg[1] as Vector2).lerp(seg[2], d / len)
			var ang: float = lerpf(seg[2], seg[3], d / len)
			return (seg[1] as Vector2) + Vector2(cos(ang), sin(ang)) * r
		d -= len
	return Vector2(-hx + r, hz)


func _build_path() -> void:
	for k in 160:
		var c := _centre(k / 160.0)
		_path.add_point(Vector3(c.x, 0.0, c.y) * VS)
	_path.add_point(_path.get_point_position(0))
	_length = _path.get_baked_length()


func _build_props() -> void:
	var trees := ["scenery/tree_round", "scenery/tree_bloom", "scenery/bush"]
	for k in 26:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(0.0, 1.0)
		var p := Vector2(cos(a) * r * 6.5, sin(a) * r * 1.6)  # the infield
		if k >= 14:  # the outer verges
			var t := _rng.randf()
			var c := _centre(t) * VS
			p = c * 1.28
			if absf(p.x) > NX * VS * 0.47 or absf(p.y) > NZ * VS * 0.47:
				continue
		var logical: String = trees[k % trees.size()]
		var spec: Dictionary = AssetCatalog.SPECS[logical]
		var mi := MeshInstance3D.new()
		mi.mesh = VoxelProps.mesh_for(logical, _resolver.get_texture(logical), spec.display_size)
		mi.position = Vector3(p.x, 0.0, p.y)
		mi.rotation.y = _rng.randf() * TAU
		mi.scale = Vector3.ONE * _rng.randf_range(0.38, 0.55)
		mi.set_instance_shader_parameter("sway", 0.004)
		add_child(mi)
	# a grandstand along the main straight, lamp posts at the corners
	var stand := MeshInstance3D.new()
	var gs: Dictionary = AssetCatalog.SPECS[AssetCatalog.GRANDSTAND]
	stand.mesh = VoxelProps.mesh_for(AssetCatalog.GRANDSTAND, _resolver.get_texture(AssetCatalog.GRANDSTAND), gs.display_size)
	stand.position = Vector3(2.0, 0.0, -30.0 * VS - 5.2)
	stand.scale = Vector3.ONE * 0.75
	add_child(stand)
	for c in [Vector2(52, 30), Vector2(-52, 30), Vector2(52, -30), Vector2(-52, -30)]:
		var lamp := MeshInstance3D.new()
		lamp.mesh = VoxelProps.lamp_mesh(false)
		lamp.position = Vector3(c.x * 1.05, 0, c.y * 1.25) * VS
		lamp.rotation.y = atan2(c.y, -c.x)
		lamp.set_instance_shader_parameter("lamp_glow", 0.9)
		add_child(lamp)
		var light := OmniLight3D.new()
		light.position = lamp.position + Vector3(0, 3.2, 0)
		light.light_color = Color(1.0, 0.82, 0.55)
		light.light_energy = 1.6
		light.omni_range = 9.0
		add_child(light)


static func island_mesh() -> ArrayMesh:
	if _island != null:
		return _island
	var depth := 4
	var g := VoxelGrid.new(Vector3i(NX, depth + 4, NZ), VS, Vector3.ZERO)
	for z in NZ:
		for x in NX:
			var p := Vector2(x - NX * 0.5 + 0.5, z - NZ * 0.5 + 0.5)
			# a soft, rounded island outline
			var q := Vector2(absf(p.x) / (NX * 0.5), absf(p.y) / (NZ * 0.5))
			var edge := pow(q.x, 6.0) + pow(q.y, 6.0)
			if edge > 0.92 + 0.08 * Vox.hash3(x / 3, 0, z / 3):
				continue
			# distance to the circuit's centre line (a rounded rectangle)
			var qq := Vector2(absf(p.x) - (52.0 - 24.0), absf(p.y) - (30.0 - 24.0))
			var sd := Vector2(maxf(qq.x, 0.0), maxf(qq.y, 0.0)).length() + minf(maxf(qq.x, qq.y), 0.0) - 24.0
			var d := absf(sd)
			var h := Vox.hash3(x, 9, z)
			for y in depth:
				var soil := Color("6b4a33").darkened(0.08 * (depth - y) * 0.5 + 0.06 * h)
				if y < depth - 3 and (y + int(h * 3)) % 3 == 0:
					soil = Color("7d5a3c")
				g.set_v(x, y, z, Vox.SOLID, soil)
			var top := Color("7bc950").darkened(0.12 + 0.12 * h)
			var top_y := depth
			if d < ROAD_W * 0.5:
				top = Color(0.26, 0.27, 0.31).lightened(0.06 * h)
				# the start line on the main straight
				if absf(p.x) < 1.5 and p.y > 0:
					top = Color.WHITE if (int(p.y) + int(p.x + 2)) % 2 == 0 else VrStyle.INK
			elif d < ROAD_W * 0.5 + 2:
				top = VrStyle.RED if int((p.x + p.y * 0.3) / 3.0) % 2 == 0 else VrStyle.PAPER
				g.set_v(x, depth + 1, z, Vox.SOLID, top)
			elif d < ROAD_W * 0.5 + 4.5 and d > ROAD_W * 0.5 + 2.5 and p.length() > 40:
				# outer barriers: red / white blocks
				var bc := VrStyle.RED if int((atan2(p.y, p.x) + PI) * 18.0) % 2 == 0 else VrStyle.PAPER
				for y in range(depth + 1, depth + 3):
					g.set_v(x, y, z, Vox.SOLID, bc)
			elif h > 0.94:
				g.set_v(x, depth + 1, z, Vox.SOLID, [VrStyle.YELLOW, VrStyle.PINK, Color.WHITE][int(h * 997) % 3])
			g.set_v(x, top_y, z, Vox.SOLID, top)
	_island = VoxelMesher.build_mesh(g, VoxelCars.material(), Vector3(NX * 0.5, depth + 1, NZ * 0.5) * VS, 0.05)
	return _island
