class_name VoxelWeapons
extends RefCounted
## VoxelRacing: voxel missiles and mines (fine car voxels, nose / front +X).

static var _missile: ArrayMesh
static var _mine: ArrayMesh


## A stubby rocket: red nose, white body with a stripe, dark fins and a
## glowing exhaust (lamp_glow).
static func missile_mesh() -> ArrayMesh:
	if _missile != null:
		return _missile
	var g := VoxelGrid.new(Vector3i(11, 5, 5), VoxelCars.voxel_size(), Vector3.ZERO)
	for x in range(1, 10):
		for y in range(1, 4):
			for z in range(1, 4):
				var c := Color(0.92, 0.92, 0.9)
				if x >= 8:
					c = Color(0.85, 0.16, 0.12)
				elif x == 5:
					c = Color(0.95, 0.75, 0.15)
				g.set_v(x, y, z, Vox.SOLID, c)
	g.set_v(10, 2, 2, Vox.SOLID, Color(0.85, 0.16, 0.12))
	for f in [Vector3i(1, 0, 2), Vector3i(1, 4, 2), Vector3i(1, 2, 0), Vector3i(1, 2, 4), Vector3i(2, 0, 2), Vector3i(2, 4, 2), Vector3i(2, 2, 0), Vector3i(2, 2, 4)]:
		g.set_v(f.x, f.y, f.z, Vox.METAL, Color(0.2, 0.2, 0.24))
	for y in range(1, 4):
		for z in range(1, 4):
			g.set_v(0, y, z, Vox.GLOW, Color(1.0, 0.6, 0.2))
	_missile = VoxelMesher.build_mesh(g, VoxelCars.material(), Vector3(5.5, 2.5, 2.5) * VoxelCars.voxel_size(), 0.03)
	return _missile


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
