class_name VoxelWeapons
extends RefCounted
## VoxelRacing: voxel missiles and mines (fine car voxels, nose / front +X).

static var _missiles: Dictionary = {}
static var _mine: ArrayMesh


## A stubby rocket: red nose, white body with a stripe, dark fins and a
## glowing exhaust (lamp_glow).
## kind: "missile" (white, red nose), "homing" (white, teal nose), "super"
## (black and yellow).
static func missile_mesh(kind: String = "missile") -> ArrayMesh:
	if _missiles.has(kind):
		return _missiles[kind]
	var body := Color(0.92, 0.92, 0.9)
	var nose := Color(0.85, 0.16, 0.12)
	var band := Color(0.95, 0.75, 0.15)
	if kind == "homing":
		nose = VrStyle.TEAL
		band = VrStyle.TEAL.lightened(0.3)
	elif kind == "super":
		body = Color(0.14, 0.14, 0.17)
		nose = VrStyle.YELLOW
		band = VrStyle.RED
	var g := VoxelGrid.new(Vector3i(11, 5, 5), VoxelCars.voxel_size(), Vector3.ZERO)
	for x in range(1, 10):
		for y in range(1, 4):
			for z in range(1, 4):
				var c := body
				if x >= 8:
					c = nose
				elif x == 5:
					c = band
				g.set_v(x, y, z, Vox.SOLID, c)
	g.set_v(10, 2, 2, Vox.SOLID, nose)
	for f in [Vector3i(1, 0, 2), Vector3i(1, 4, 2), Vector3i(1, 2, 0), Vector3i(1, 2, 4), Vector3i(2, 0, 2), Vector3i(2, 4, 2), Vector3i(2, 2, 0), Vector3i(2, 2, 4)]:
		g.set_v(f.x, f.y, f.z, Vox.METAL, Color(0.2, 0.2, 0.24))
	for y in range(1, 4):
		for z in range(1, 4):
			g.set_v(0, y, z, Vox.GLOW, Color(1.0, 0.6, 0.2))
	var mesh := VoxelMesher.build_mesh(g, VoxelCars.material(), Vector3(5.5, 2.5, 2.5) * VoxelCars.voxel_size(), 0.03)
	_missiles[kind] = mesh
	return mesh


## A squat mine: dark casing, hazard stripes, a blinking red lamp (lamp_glow).
static func mine_mesh() -> ArrayMesh:
	if _mine != null:
		return _mine
	var n := 9
	var g := VoxelGrid.new(Vector3i(n, 4, n), VoxelCars.voxel_size(), Vector3.ZERO)
	for z in n:
		for x in n:
			var p := Vector2(x + 0.5 - n * 0.5, z + 0.5 - n * 0.5)
			var r := p.length()
			if r > n * 0.5:
				continue
			for y in 2:
				var stripe := int(floor((p.angle() + PI) / (TAU / 8.0))) % 2 == 0
				var c := Color(0.95, 0.78, 0.1) if (r > n * 0.5 - 1.3 and stripe) else Color(0.16, 0.16, 0.18)
				g.set_v(x, y, z, Vox.METAL, c)
			if r < 1.8:
				g.set_v(x, 2, z, Vox.METAL, Color(0.3, 0.3, 0.33))
	g.set_v(n / 2, 3, n / 2, Vox.GLOW, Color(1.0, 0.15, 0.1))
	_mine = VoxelMesher.build_mesh(g, VoxelCars.material(), Vector3(n * 0.5, 0.0, n * 0.5) * VoxelCars.voxel_size(), 0.03)
	return _mine


static var _can: ArrayMesh
static var _heads: Dictionary = {}
static var _arm: ArrayMesh


## A cartoon soda can (red with a white stripe, silver ends) - the cheeky
## overtaking taunt. Lies along +Y; centred.
static func can_mesh() -> ArrayMesh:
	if _can != null:
		return _can
	var g := VoxelGrid.new(Vector3i(5, 8, 5), VoxelCars.voxel_size(), Vector3.ZERO)
	for y in 8:
		for z in 5:
			for x in 5:
				if (x == 0 or x == 4) and (z == 0 or z == 4):
					continue  # rounded corners
				var c := Color(0.86, 0.12, 0.1)
				if y == 0 or y == 7:
					c = Color(0.78, 0.8, 0.84)
				elif y == 4:
					c = Color(0.97, 0.95, 0.9)
				g.set_v(x, y, z, Vox.METAL if y == 0 or y == 7 else Vox.SOLID, c)
	g.set_v(2, 7, 1, Vox.METAL, Color(0.45, 0.46, 0.5))  # the ring pull
	_can = VoxelMesher.build_mesh(g, VoxelCars.material(), Vector3(2.5, 4.0, 2.5) * VoxelCars.voxel_size(), 0.03)
	return _can


## A driver's head in a helmet of `color`, face (visor) towards +X.
static func head_mesh(color: Color) -> ArrayMesh:
	var key := color.to_html()
	if _heads.has(key):
		return _heads[key]
	var g := VoxelGrid.new(Vector3i(6, 7, 6), VoxelCars.voxel_size(), Vector3.ZERO)
	var skin := Color(0.96, 0.76, 0.6)
	for y in 7:
		for z in 6:
			for x in 6:
				if (x == 0 or x == 5) and (z == 0 or z == 5) and y > 4:
					continue
				var c := color
				if y <= 1:
					c = skin  # chin and neck
				elif x == 5 and y >= 2 and y <= 3 and z >= 1 and z <= 4:
					c = Color(0.1, 0.12, 0.18)  # visor
				elif y == 4 and x >= 4:
					c = color.lightened(0.35)
				g.set_v(x, y, z, Vox.SOLID, c)
	var mesh := VoxelMesher.build_mesh(g, VoxelCars.material(), Vector3(3.0, 0.0, 3.0) * VoxelCars.voxel_size(), 0.03)
	_heads[key] = mesh
	return mesh


## The throwing arm (shoulder at the origin, hand towards -Y).
static func arm_mesh() -> ArrayMesh:
	if _arm != null:
		return _arm
	var g := VoxelGrid.new(Vector3i(2, 7, 2), VoxelCars.voxel_size(), Vector3.ZERO)
	for y in 7:
		for z in 2:
			for x in 2:
				g.set_v(x, y, z, Vox.SOLID, Color(0.96, 0.76, 0.6) if y < 2 else Color(0.2, 0.22, 0.3))
	_arm = VoxelMesher.build_mesh(g, VoxelCars.material(), Vector3(1.0, 7.0, 1.0) * VoxelCars.voxel_size(), 0.03)
	return _arm
