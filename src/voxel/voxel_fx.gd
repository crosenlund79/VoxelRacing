class_name VoxelFx
extends Node3D
## VoxelRacing: every physical effect of a race, built from voxels and drawn
## with a few MultiMeshes:
##   * debris: pieces of cars (their own voxel colours) that fly, bounce,
##     tumble, settle on the track and stay for the race (bounded ring buffer;
##     settled pieces cost nothing per frame). Cars driving through settled
##     debris kick it up again (spatial hash lookup);
##   * sparks and fire: short-lived glowing voxels;
##   * smoke and dust: soft voxel puffs;
##   * stars: little glowing voxel stars popping out of collisions;
##   * pieces (P006): whole components that broke off cars (a door, a
##     bumper, a wing) - their own meshes and colours - fly, tumble, bounce,
##     come to rest lying flat and stay; passing cars shove them about,
##     light pieces further than heavy ones. Oldest pieces make room for new
##     ones past PIECES_MAX.
## Presentation only: nothing here touches the race.

const DEBRIS_MAX := 9000
const FX_MAX := 1400
const PUFF_MAX := 500
const STAR_MAX := 96
const GRAVITY := 26.0
const HASH_CELL := 2.0
const FX_SHADER := preload("res://src/voxel/shaders/voxel_fx.gdshader")
const SMOKE_SHADER := preload("res://src/voxel/shaders/voxel_smoke.gdshader")

## Ground height (3D units) at a world x, z (set by VoxelStage).
var ground: Callable
## Time scale (action replays' slow motion).
var speed := 1.0
## Debris weight (P003): heavier pieces fall faster, bounce lower, skid less
## and spin down sooner. Tune here.
const DEBRIS_GRAVITY := 38.0
const DEBRIS_BOUNCE := 0.2
const DEBRIS_SKID := 0.42
const DEBRIS_SETTLE_SPEED := 1.1

var _debris: MultiMesh
var _fx: MultiMesh
var _puffs: MultiMesh
var _stars: MultiMesh
var _rng := RandomNumberGenerator.new()

# debris pool
var d_pos := PackedVector3Array()
var d_vel := PackedVector3Array()
var d_rot := PackedVector3Array()
var d_spin := PackedVector3Array()
var d_size := PackedFloat32Array()
var d_floor := PackedFloat32Array()
var d_state := PackedByteArray()  # 0 free, 1 flying, 2 settled
var d_glow := PackedFloat32Array()
var _d_next := 0
var _d_high := 0
var _flying: Array[int] = []
var _hash := {}

# short-lived pools: [pos, vel, rot, spin, size, life, max_life, grav, glow]
var _f := {}
var _p := {}
var _s := {}
var _lights: Array[OmniLight3D] = []
## Component pieces (P006): [node, vel, spin, state (1 flying, 2 resting),
## mass, half extents, floor]. Weight: heavier pieces bounce lower, skid less
## and are shoved less.
const PIECES_MAX := 200
const PIECE_GRAVITY := 30.0
var _pieces: Array[Dictionary] = []
var _piece_next := 0
var _piece_flying := 0
var _light_life := PackedFloat32Array()


func _ready() -> void:
	_rng.seed = 2002
	var cube := _cube_mesh()
	var fx_mat := ShaderMaterial.new()
	fx_mat.shader = FX_SHADER
	_debris = _multimesh(cube, fx_mat, DEBRIS_MAX, "Debris")
	_fx = _multimesh(cube, fx_mat, FX_MAX, "Sparks")
	var smoke_mat := ShaderMaterial.new()
	smoke_mat.shader = SMOKE_SHADER
	_puffs = _multimesh(cube, smoke_mat, PUFF_MAX, "Smoke")
	_stars = _multimesh(_star_mesh(), fx_mat, STAR_MAX, "Stars")
	for pool in [_f, _p, _s]:
		var cap: int = FX_MAX if pool == _f else (PUFF_MAX if pool == _p else STAR_MAX)
		for key in ["pos", "vel", "rot", "spin"]:
			var a := PackedVector3Array()
			a.resize(cap)
			pool[key] = a
		for key in ["size", "life", "max", "grav", "glow"]:
			var b := PackedFloat32Array()
			b.resize(cap)
			pool[key] = b
		pool["next"] = 0
		pool["active"] = []
	for key in ["pos", "vel", "rot", "spin"]:
		pass
	d_pos.resize(DEBRIS_MAX)
	d_vel.resize(DEBRIS_MAX)
	d_rot.resize(DEBRIS_MAX)
	d_spin.resize(DEBRIS_MAX)
	d_size.resize(DEBRIS_MAX)
	d_floor.resize(DEBRIS_MAX)
	d_state.resize(DEBRIS_MAX)
	d_glow.resize(DEBRIS_MAX)
	for k in 3:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.62, 0.3)
		l.omni_range = 7.0
		l.light_energy = 0.0
		l.visible = false
		add_child(l)
		_lights.append(l)
	_light_life.resize(3)


func _multimesh(mesh: Mesh, mat: Material, count: int, node_name: String) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = count
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.name = node_name
	mi.multimesh = mm
	mi.material_override = mat
	mi.extra_cull_margin = 16384.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if node_name != "Smoke" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mm


## One bevelled unit voxel, white (instance colours tint it).
static func _cube_mesh() -> ArrayMesh:
	var g := VoxelGrid.new(Vector3i.ONE, 1.0, Vector3.ZERO)
	g.set_v(0, 0, 0, Vox.SOLID, Color.WHITE)
	return VoxelMesher.build_mesh(g, null, Vector3(0.5, 0.5, 0.5), 0.0)


## A little five-pointed voxel star lying flat (unit size, 2 voxels thick).
static func _star_mesh() -> ArrayMesh:
	var n := 11
	var g := VoxelGrid.new(Vector3i(n, 2, n), 1.0 / n, Vector3.ZERO)
	var poly := PackedVector2Array()
	for k in 10:
		var r := 1.0 if k % 2 == 0 else 0.45
		var a := -PI * 0.5 + k * PI / 5.0
		poly.append(Vector2(cos(a), sin(a)) * r)
	for z in n:
		for x in n:
			var p := Vector2((x + 0.5) / n * 2.0 - 1.0, (z + 0.5) / n * 2.0 - 1.0)
			if Geometry2D.is_point_in_polygon(p, poly):
				g.set_v(x, 0, z, Vox.SOLID, Color.WHITE)
				g.set_v(x, 1, z, Vox.SOLID, Color.WHITE)
	return VoxelMesher.build_mesh(g, null, Vector3(0.5, 1.0 / n, 0.5), 0.0)


# ------------------------------------------------------------ spawning

## A piece of a car: flies with `vel`, settles on the ground (or `floor_y`,
## e.g. a bridge deck) and stays.
func debris(pos: Vector3, vel: Vector3, color: Color, size: float, floor_y: float = -INF, glow: float = 0.0) -> void:
	var i := _d_next
	_d_next = (_d_next + 1) % DEBRIS_MAX
	if d_state[i] == 2:
		_unhash(i)
	elif d_state[i] == 1:
		_flying.erase(i)
	d_pos[i] = pos
	d_vel[i] = vel
	d_rot[i] = Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU)
	d_spin[i] = Vector3(_rng.randf_range(-12, 12), _rng.randf_range(-12, 12), _rng.randf_range(-12, 12))
	d_size[i] = size
	d_floor[i] = floor_y
	d_state[i] = 1
	d_glow[i] = glow
	_flying.append(i)
	_debris.set_instance_color(i, color)
	_debris.set_instance_custom_data(i, Color(glow, 0, 0, 0))
	_d_high = maxi(_d_high, i + 1)
	_debris.visible_instance_count = _d_high


## A whole component breaking off a car: `mesh` centred on its centre, placed
## at `xf`, flying with `vel` and tumbling at `spin` (rad/s, axis * rate);
## `mass` in voxels. It comes to rest on the ground (or `floor_y`) and stays.
func piece(mesh: Mesh, xf: Transform3D, vel: Vector3, spin: Vector3, mass: float, floor_y: float = -INF,
		tint: Color = Color.WHITE, charred: float = 0.0) -> void:
	if mesh == null:
		return
	var p: Dictionary
	if _pieces.size() < PIECES_MAX:
		var mi := MeshInstance3D.new()
		mi.name = "Piece"
		add_child(mi)
		p = {"node": mi}
		_pieces.append(p)
	else:
		p = _pieces[_piece_next]
		_piece_next = (_piece_next + 1) % PIECES_MAX
		if int(p.get("state", 0)) == 1:
			_piece_flying -= 1
	var node: MeshInstance3D = p.node
	node.mesh = mesh
	node.visible = true
	node.global_transform = xf
	node.set_instance_shader_parameter("tint", tint)
	node.set_instance_shader_parameter("charred", charred)
	var ab := mesh.get_aabb()
	p.ext = ab.size * 0.5 * xf.basis.get_scale()
	p.off = ab.get_center()
	p.vel = vel
	p.spin = spin
	p.mass = maxf(mass, 1.0)
	p.floor = floor_y
	p.state = 1
	_piece_flying += 1


## Components of a vehicle breaking away: each flies as its own piece from
## where it sat on the car (`body_xf`), with the car's velocity `carv`, out
## from the car's centre and towards `out_dir`; `blast` throws them hard
## (an explosion). A few sparks and dark crumbs come with them.
func throw_parts(model: VoxelVehicle.Model, ids: Array, body_xf: Transform3D, carv: Vector3, out_dir: Vector3,
		floor_y: float, blast: bool) -> void:
	var centre := body_xf * Vector3(0, 0.45, 0)
	var basis := body_xf.basis.orthonormalized().scaled(body_xf.basis.get_scale())
	for id in ids:
		var p: Dictionary = model.parts[int(id)]
		var mass := float(p.n)
		var wp: Vector3 = body_xf * (p.centre as Vector3)
		var away := wp - centre
		var vel: Vector3
		var k := clampf(sqrt(40.0 / maxf(mass, 1.0)), 0.45, 1.6)
		if blast:
			away.y = maxf(away.y, 0.0) + 0.3
			vel = carv * 0.35 + away.normalized() * _rng.randf_range(3.0, 7.5) * k + Vector3(0, _rng.randf_range(3.0, 7.0) * k, 0)
		else:
			away.y = 0.0
			vel = carv * _rng.randf_range(0.55, 0.85) + (away.normalized() * 0.7 + out_dir) * _rng.randf_range(1.2, 3.2) * k \
				+ Vector3(0, _rng.randf_range(1.5, 3.5) * k, 0)
		var spin := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized() \
			* _rng.randf_range(3.0, 10.0) * k * (1.5 if blast else 1.0)
		var xf := Transform3D(basis, wp)
		piece(VoxelVehicle.part_mesh(model, int(id)), xf, vel, spin, mass, floor_y, Color.WHITE,
			_rng.randf_range(0.0, 0.22) if blast else 0.0)
		# a couple of crumbs and sparks where it tore off
		for c in (2 if blast else 1):
			debris(wp, vel * 0.6 + Vector3(_rng.randf_range(-1, 1), 1.0, _rng.randf_range(-1, 1)),
				(p.colour as Color).darkened(0.3), VoxelCars.voxel_size() * _rng.randf_range(0.7, 1.0), floor_y)
		for c in 3:
			spark(wp, (vel.normalized() + Vector3(_rng.randf_range(-0.8, 0.8), 0.6, _rng.randf_range(-0.8, 0.8))) * _rng.randf_range(2.5, 6.0),
				Color(1.0, _rng.randf_range(0.75, 1.0), 0.45), 0.06, _rng.randf_range(0.2, 0.4), 1.2, 1.0)


## Wheels flying off a wreck (their own meshes, rim tint kept).
func throw_wheels(wheels: Array, centre: Vector3, carv: Vector3, floor_y: float) -> void:
	for w in wheels:
		var pivot := w as Node3D
		if pivot == null or not pivot.visible:
			continue
		var mi: MeshInstance3D = pivot.get_child(0) as MeshInstance3D if pivot.get_child_count() > 0 else null
		var mesh: Mesh = mi.mesh if mi != null else VoxelCars.wheel_mesh()
		var tint: Color = mi.get_instance_shader_parameter("tint") if mi != null and mi.get_instance_shader_parameter("tint") != null else Color.WHITE
		var xf := mi.global_transform if mi != null else pivot.global_transform
		var out := xf.origin - centre
		out.y = 0.5
		piece(mesh, xf, carv * 0.3 + out.normalized() * _rng.randf_range(3.0, 6.0) + Vector3(0, _rng.randf_range(3.0, 6.0), 0),
			Vector3(_rng.randf_range(-6, 6), _rng.randf_range(-6, 6), _rng.randf_range(-6, 6)), 60.0, floor_y, tint, 0.3)


func piece_count() -> int:
	var n := 0
	for p in _pieces:
		if int(p.get("state", 0)) != 0:
			n += 1
	return n


func spark(pos: Vector3, vel: Vector3, color: Color, size: float, life: float, glow: float = 1.0, grav: float = 1.0) -> void:
	_spawn(_f, _fx, FX_MAX, pos, vel, color, size, life, glow, grav)


func puff(pos: Vector3, vel: Vector3, color: Color, size: float, life: float, alpha: float = 0.7) -> void:
	_spawn(_p, _puffs, PUFF_MAX, pos, vel, color, size, life, alpha, -0.05)


func star(pos: Vector3, vel: Vector3, color: Color, size: float, life: float) -> void:
	_spawn(_s, _stars, STAR_MAX, pos, vel, color, size, life, 0.7, 0.9)


func _spawn(pool: Dictionary, mm: MultiMesh, cap: int, pos: Vector3, vel: Vector3, color: Color, size: float, life: float, glow: float, grav: float) -> void:
	var i: int = pool.next
	pool.next = (i + 1) % cap
	var active: Array = pool.active
	if pool.life[i] > 0.0:
		active.erase(i)
	pool.pos[i] = pos
	pool.vel[i] = vel
	pool.rot[i] = Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU) if mm != _stars else Vector3(0, _rng.randf() * TAU, 0)
	pool.spin[i] = Vector3(_rng.randf_range(-8, 8), _rng.randf_range(-8, 8), _rng.randf_range(-8, 8)) if mm != _stars else Vector3(0, _rng.randf_range(4, 9) * (1 if _rng.randf() < 0.5 else -1), 0)
	pool.size[i] = size
	pool.life[i] = life
	pool.max[i] = life
	pool.grav[i] = grav
	pool.glow[i] = glow
	active.append(i)
	mm.set_instance_color(i, color)
	mm.visible_instance_count = maxi(mm.visible_instance_count, i + 1)


## A glowing flash of light (explosions), fading quickly.
func flash(pos: Vector3, energy: float = 6.0, life: float = 0.45) -> void:
	var k := 0
	for j in _lights.size():
		if _light_life[j] < _light_life[k]:
			k = j
	_lights[k].position = pos + Vector3(0, 1.2, 0)
	_lights[k].light_energy = energy
	_lights[k].visible = true
	_light_life[k] = life


## A car-sized explosion: fire, sparks, smoke and a flash (its body debris
## comes from VoxelCarDamage).
func explosion(pos: Vector3, scale: float = 1.0) -> void:
	for k in int(46 * scale):
		var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.2, 1.4), _rng.randf_range(-1, 1)).normalized()
		var col := Color(1.0, _rng.randf_range(0.35, 0.85), _rng.randf_range(0.05, 0.25))
		spark(pos + dir * 0.3, dir * _rng.randf_range(2.5, 9.0) * scale, col, _rng.randf_range(0.12, 0.3) * scale,
			_rng.randf_range(0.35, 0.8), 1.0, -0.15)
	for k in int(24 * scale):
		var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.3, 1.2), _rng.randf_range(-1, 1)).normalized()
		spark(pos, dir * _rng.randf_range(8.0, 16.0), Color(1.0, 0.95, 0.7), 0.07, _rng.randf_range(0.3, 0.6), 1.3, 1.0)
	for k in int(10 * scale):
		var off := Vector3(_rng.randf_range(-0.8, 0.8), _rng.randf_range(0.2, 0.9), _rng.randf_range(-0.8, 0.8))
		var g := _rng.randf_range(0.12, 0.28)
		puff(pos + off, Vector3(off.x, 1.4, off.z) * 0.8, Color(g, g * 0.95, g * 0.92), _rng.randf_range(0.5, 0.9) * scale,
			_rng.randf_range(1.2, 2.2), 0.75)
	flash(pos, 7.0 * scale)


## Collision feedback at a point, by severity 0..1: voxel sparks, and from
## firm knocks upwards little spinning voxel stars.
func impact(pos: Vector3, normal: Vector3, severity: float) -> void:
	severity = clampf(severity, 0.0, 1.0)
	for k in int(4 + severity * 12):
		var dir := (normal + Vector3(_rng.randf_range(-0.9, 0.9), _rng.randf_range(0.3, 1.2), _rng.randf_range(-0.9, 0.9))).normalized()
		spark(pos, dir * _rng.randf_range(3.0, 8.0), Color(1.0, _rng.randf_range(0.8, 1.0), _rng.randf_range(0.4, 0.7)),
			0.07, _rng.randf_range(0.2, 0.42), 1.2, 1.0)
	if severity > 0.3:
		var stars := 1 + int(severity * 3.0)
		for k in stars:
			var a := _rng.randf() * TAU
			var dir := Vector3(cos(a) * 0.6, 1.0, sin(a) * 0.6)
			var col: Color = [Color(1.0, 0.86, 0.2), Color(1.0, 0.98, 0.85), Color(1.0, 0.6, 0.2)][k % 3]
			star(pos + Vector3(0, 0.4, 0), dir * _rng.randf_range(2.5, 4.0), col, _rng.randf_range(0.45, 0.7), _rng.randf_range(0.55, 0.8))
	if severity > 0.6:
		for k in 4:
			var off := Vector3(_rng.randf_range(-0.4, 0.4), 0.2, _rng.randf_range(-0.4, 0.4))
			puff(pos + off, off * 1.5 + Vector3(0, 0.6, 0), Color(0.8, 0.76, 0.68), _rng.randf_range(0.25, 0.4), 0.7, 0.55)


# ------------------------------------------------------------ cars kick debris

## A car (centre, velocity in units/s, radius in units) kicks up the settled
## debris it drives through.
func scatter_near(centre: Vector3, vel: Vector3, radius: float) -> int:
	var v_speed := Vector2(vel.x, vel.z).length()
	if v_speed < 1.5:
		return 0
	var kicked := 0
	var c0 := Vector2i(floori((centre.x - radius) / HASH_CELL), floori((centre.z - radius) / HASH_CELL))
	var c1 := Vector2i(floori((centre.x + radius) / HASH_CELL), floori((centre.z + radius) / HASH_CELL))
	var r2 := radius * radius
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var key := Vector2i(cx, cz)
			if not _hash.has(key):
				continue
			var list: Array = _hash[key]
			for k in range(list.size() - 1, -1, -1):
				var i: int = list[k]
				var p := d_pos[i]
				var dx := p.x - centre.x
				var dz := p.z - centre.z
				if dx * dx + dz * dz > r2 or absf(p.y - centre.y) > 1.2:
					continue
				list.remove_at(k)
				var away := Vector3(dx, 0.0, dz).normalized()
				if away == Vector3.ZERO:
					away = Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized()
				# heavy bits: shoved along and skittering, hardly lifted
				d_vel[i] = vel * _rng.randf_range(0.25, 0.5) + away * (1.0 + v_speed * _rng.randf_range(0.1, 0.25)) \
					+ Vector3(0, 0.6 + v_speed * _rng.randf_range(0.03, 0.09), 0)
				d_spin[i] = Vector3(_rng.randf_range(-8, 8), _rng.randf_range(-8, 8), _rng.randf_range(-8, 8))
				d_state[i] = 1
				_flying.append(i)
				kicked += 1
			if list.is_empty():
				_hash.erase(key)
	for p in _pieces:
		if int(p.get("state", 0)) != 2:
			continue
		var node: Node3D = p.node
		var at := node.global_position
		var dx := at.x - centre.x
		var dz := at.z - centre.z
		var reach := radius + maxf((p.ext as Vector3).x, (p.ext as Vector3).z) * 0.6
		if dx * dx + dz * dz > reach * reach or absf(at.y - centre.y) > 1.4:
			continue
		var away := Vector3(dx, 0.0, dz).normalized()
		if away == Vector3.ZERO:
			away = Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized()
		var k := clampf(sqrt(14.0 / float(p.mass)), 0.22, 1.3)
		p.vel = (vel * _rng.randf_range(0.3, 0.6) + away * (1.0 + v_speed * _rng.randf_range(0.1, 0.22))) * k \
			+ Vector3(0, (0.8 + v_speed * _rng.randf_range(0.03, 0.08)) * k, 0)
		p.spin = Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized() * _rng.randf_range(3.0, 9.0) * k
		p.state = 1
		_piece_flying += 1
		kicked += 1
	return kicked


func _hash_key(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / HASH_CELL), floori(p.z / HASH_CELL))


func _unhash(i: int) -> void:
	var key := _hash_key(d_pos[i])
	if _hash.has(key):
		(_hash[key] as Array).erase(i)


## Forget everything (a fresh race).
func clear() -> void:
	for i in _d_high:
		d_state[i] = 0
		_debris.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -1000, 0)))
	_flying.clear()
	_hash.clear()
	_d_next = 0
	_d_high = 0
	_debris.visible_instance_count = 0
	for p in _pieces:
		(p.node as Node3D).visible = false
		(p.node as MeshInstance3D).mesh = null
		p.state = 0
	_piece_next = 0
	_piece_flying = 0
	for pool in [_f, _p, _s]:
		var mm: MultiMesh = _fx if pool == _f else (_puffs if pool == _p else _stars)
		for i in (pool.active as Array):
			pool.life[i] = 0.0
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -1000, 0)))
		(pool.active as Array).clear()


func debris_count() -> int:
	var n := 0
	for i in _d_high:
		if d_state[i] != 0:
			n += 1
	return n


func settled_count() -> int:
	var n := 0
	for i in _d_high:
		if d_state[i] == 2:
			n += 1
	return n


# ------------------------------------------------------------ simulation

func _process(delta: float) -> void:
	delta = minf(delta, 0.05) * speed
	_step_debris(delta)
	if _piece_flying > 0:
		_step_pieces(delta)
	_step_pool(_f, _fx, delta)
	_step_pool(_p, _puffs, delta)
	_step_pool(_s, _stars, delta)
	for k in _lights.size():
		if _light_life[k] > 0.0:
			_light_life[k] -= delta
			_lights[k].light_energy *= exp(-delta * 7.0)
			if _light_life[k] <= 0.0:
				_lights[k].visible = false


func _floor_at(i: int, p: Vector3) -> float:
	var f := d_floor[i]
	if ground.is_valid():
		f = maxf(f, ground.call(p.x, p.z))
	return f


func _step_debris(dt: float) -> void:
	var still: Array[int] = []
	for i in _flying:
		var p := d_pos[i]
		var v := d_vel[i]
		var half := d_size[i] * 0.5
		var old_floor := _floor_at(i, p)
		v.y -= DEBRIS_GRAVITY * dt
		v *= 1.0 - 0.35 * dt
		var np := p + v * dt
		var nf := _floor_at(i, np)
		if nf > old_floor + 0.3 and np.y - half < nf:  # hit a wall / barrier side: bounce back
			np.x = p.x
			np.z = p.z
			v.x *= -0.35
			v.z *= -0.35
			nf = old_floor
		var settled := false
		if np.y - half <= nf:
			np.y = nf + half
			if v.y < 0.0:
				v.y = -v.y * DEBRIS_BOUNCE
				v.x *= DEBRIS_SKID
				v.z *= DEBRIS_SKID
				d_spin[i] *= 0.32
			if v.length() < DEBRIS_SETTLE_SPEED:
				settled = true
		var r := d_rot[i] + d_spin[i] * dt
		if settled:
			v = Vector3.ZERO
			r = Vector3(0.0, r.y, 0.0)  # lies flat
			np.y = nf + half
		d_pos[i] = np
		d_vel[i] = v
		d_rot[i] = r
		_debris.set_instance_transform(i, Transform3D(Basis.from_euler(r).scaled(Vector3.ONE * d_size[i]), np))
		if d_glow[i] > 0.0:
			d_glow[i] = maxf(0.0, d_glow[i] - dt * 0.8)
			_debris.set_instance_custom_data(i, Color(d_glow[i], 0, 0, 0))
		if settled:
			d_state[i] = 2
			var key := _hash_key(np)
			if not _hash.has(key):
				_hash[key] = []
			(_hash[key] as Array).append(i)
		else:
			still.append(i)
	_flying = still


func _step_pieces(dt: float) -> void:
	if dt <= 0.0:
		return
	var flying := 0
	for p in _pieces:
		if int(p.get("state", 0)) != 1:
			continue
		var node: Node3D = p.node
		var xf := node.global_transform
		var v: Vector3 = p.vel
		var spin: Vector3 = p.spin
		var mass: float = p.mass
		var ext: Vector3 = p.ext
		v.y -= PIECE_GRAVITY * dt
		v *= 1.0 - 0.3 * dt
		var pos := xf.origin + v * dt
		var b := xf.basis
		if spin.length() > 0.01:
			b = Basis(spin.normalized(), spin.length() * dt) * b
		var bn := b.orthonormalized()
		var half := absf(bn.x.y) * ext.x + absf(bn.y.y) * ext.y + absf(bn.z.y) * ext.z
		var old_floor := _piece_floor(p, xf.origin)
		var nf := _piece_floor(p, pos)
		if nf > old_floor + 0.3 and pos.y - half < nf:  # a wall / barrier side: bounce back
			pos.x = xf.origin.x
			pos.z = xf.origin.z
			v.x *= -0.3
			v.z *= -0.3
			nf = old_floor
		var rest := false
		if pos.y - half <= nf:
			pos.y = nf + half
			if v.y < 0.0:
				var bounce := 0.32 / (1.0 + mass / 60.0)
				v.y = -v.y * bounce
				var skid := 0.62 - 0.25 * clampf(mass / 120.0, 0.0, 1.0)
				v.x *= skid
				v.z *= skid
				spin = spin * 0.45 + Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)) * minf(v.length(), 2.0)
			if v.length() < 0.9:
				rest = true
		if rest:
			# lies flat: the axis nearest the vertical turns upright (yaw kept)
			var axes := [b.x, b.y, b.z]
			var exts := [ext.x, ext.y, ext.z]
			var best := 0
			for k in 3:
				if absf((axes[k] as Vector3).normalized().y) > absf((axes[best] as Vector3).normalized().y):
					best = k
			var a := (axes[best] as Vector3).normalized()
			var up := Vector3.UP if a.y >= 0.0 else Vector3.DOWN
			var q := Quaternion(a, up) if a.dot(up) < 0.9999 else Quaternion.IDENTITY
			b = Basis(q) * b
			pos.y = nf + float(exts[best])
			v = Vector3.ZERO
			spin = Vector3.ZERO
			p.state = 2
		else:
			flying += 1
		node.global_transform = Transform3D(b, pos)
		p.vel = v
		p.spin = spin
	_piece_flying = flying


func _piece_floor(p: Dictionary, at: Vector3) -> float:
	var f: float = p.floor
	if ground.is_valid():
		f = maxf(f, ground.call(at.x, at.z))
	return f


func _step_pool(pool: Dictionary, mm: MultiMesh, dt: float) -> void:
	var active: Array = pool.active
	if active.is_empty():
		return
	var keep: Array = []
	var is_star := mm == _stars
	var is_puff := mm == _puffs
	for i in active:
		var life: float = pool.life[i] - dt
		pool.life[i] = life
		if life <= 0.0:
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -1000, 0)))
			continue
		keep.append(i)
		var t: float = 1.0 - life / pool.max[i]  # 0 .. 1 over the life
		var v: Vector3 = pool.vel[i]
		v.y -= GRAVITY * pool.grav[i] * dt
		if is_puff:
			v *= 1.0 - 1.6 * dt
		elif is_star:
			v *= 1.0 - 2.2 * dt
		var p: Vector3 = pool.pos[i] + v * dt
		if ground.is_valid() and not is_puff:
			var f: float = ground.call(p.x, p.z)
			if p.y < f + 0.05:
				p.y = f + 0.05
				v.y = absf(v.y) * 0.3
				v.x *= 0.6
				v.z *= 0.6
		pool.vel[i] = v
		pool.pos[i] = p
		var r: Vector3 = pool.rot[i] + pool.spin[i] * dt
		pool.rot[i] = r
		var s: float = pool.size[i]
		var custom := Color(0, 0, 0, 0)
		if is_puff:
			s *= 0.6 + t * 0.9
			custom = Color(0, pool.glow[i] * (1.0 - t) * minf(1.0, t * 6.0 + 0.3), 0, 0)
		elif is_star:
			s *= minf(1.0, t * 5.0) * (1.0 - smoothstep(0.7, 1.0, t))  # pop in, shrink away
			custom = Color(pool.glow[i], 0, 0, 0)
		else:
			s *= 1.0 - t * 0.7
			custom = Color(pool.glow[i] * (1.0 - t * 0.8), 0, 0, 0)
		mm.set_instance_transform(i, Transform3D(Basis.from_euler(r).scaled(Vector3.ONE * maxf(s, 0.001)), p))
		mm.set_instance_custom_data(i, custom)
	pool.active = keep
