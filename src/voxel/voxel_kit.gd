class_name VoxelKit
extends RefCounted
## VoxelRacing (P004): hand-built voxel set dressing that gives each circuit
## its own character - a countryside venue (barns, hay, cows, a windmill), an
## industrial yard (containers, drums, sheds), a winter village (cabins,
## snowmen), an established raceway (pit garages, hospitality tents, TV
## towers, service vehicles) and the tabletop (giant toys). Built once per
## kind from code (no art files), cached, shared by every placement.
## Models stand on y = 0, centred on x/z, the "front" faces +Z.

const C := Vox.CELL_PX * Vox.PX  # one world voxel (0.25 units)

static var _meshes: Dictionary = {}
## Parts that animate (windmill sails, fans, cow heads): kind -> mesh.
static var _parts: Dictionary = {}


static func mesh(kind: String) -> ArrayMesh:
	if not _meshes.has(kind):
		_meshes[kind] = _build(kind)
	return _meshes[kind]


static func part(kind: String) -> ArrayMesh:
	if not _parts.has(kind):
		_parts[kind] = _build_part(kind)
	return _parts[kind]


## Footprint radius (px) of a kind, for placement.
static func radius_px(kind: String) -> float:
	return {"barn": 70.0, "cottage": 46.0, "windmill": 34.0, "hay": 14.0, "tractor": 26.0, "cow": 14.0,
		"stall": 30.0, "fence": 34.0, "container": 50.0, "containers": 56.0, "drums": 18.0, "fire_drum": 8.0,
		"shed": 52.0, "scrap": 30.0, "cabin": 42.0, "snowman": 10.0, "sledge": 10.0, "pit_garages": 96.0,
		"tent": 44.0, "tv_tower": 18.0, "screen": 44.0, "tow_truck": 30.0, "ambulance": 30.0, "tyre_wall": 30.0,
		"duck": 22.0, "blocks": 26.0, "robot": 16.0, "mug": 26.0, "flagpole": 8.0, "bench": 16.0}.get(kind, 30.0)


## Kinds whose windows / signs glow at night.
static func glows(kind: String) -> bool:
	return kind in ["barn", "cottage", "cabin", "stall", "pit_garages", "tent", "screen", "ambulance", "fire_drum", "shed", "tow_truck", "robot"]


# ------------------------------------------------------------ helpers

static func _grid(nx: int, ny: int, nz: int) -> VoxelGrid:
	return VoxelGrid.new(Vector3i(nx, ny, nz), C, Vector3.ZERO)


static func _done(g: VoxelGrid, pivot := Vector3(-1, 0, -1)) -> ArrayMesh:
	var s := g.size()
	var p := pivot
	if p.x < 0.0:
		p = Vector3(s.x * 0.5, 0.0, s.z * 0.5)
	return VoxelMesher.build_mesh(g, VoxelCars.material(), p * C, 0.035)


static func _box(g: VoxelGrid, a: Vector3i, b: Vector3i, c: Color, m: int = Vox.SOLID) -> void:
	var s := g.size()
	g.box(Vector3i(maxi(a.x, 0), maxi(a.y, 0), maxi(a.z, 0)), Vector3i(mini(b.x, s.x - 1), mini(b.y, s.y - 1), mini(b.z, s.z - 1)), m, c)


## A gable roof along X over [x0..x1] x [z0..z1] from height y0.
static func _roof(g: VoxelGrid, x0: int, x1: int, z0: int, z1: int, y0: int, c: Color, snow := false) -> void:
	var half := (z1 - z0 + 1) / 2
	for k in half + 1:
		var c2 := c.darkened(0.12) if k % 2 == 0 else c
		if snow and k >= half - 1:
			c2 = Color(0.95, 0.97, 1.0)
		_box(g, Vector3i(x0 - 1, y0 + k, z0 + k - 1), Vector3i(x1 + 1, y0 + k, z1 - k + 1), c2)
	if snow:
		_box(g, Vector3i(x0 - 1, y0 + half + 1, z0 + half - 1), Vector3i(x1 + 1, y0 + half + 1, z1 - half + 1), Color(0.96, 0.98, 1.0))


static func _wheel(g: VoxelGrid, x: int, y: int, z: int, r: int, w: int) -> void:
	for dz in w:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if dx * dx + dy * dy <= r * r + r:
					var hub := dx * dx + dy * dy <= 1
					g.set_v(x + dx, y + dy, z + dz, Vox.METAL if hub else Vox.SOLID, Color(0.55, 0.56, 0.6) if hub else Color(0.09, 0.09, 0.1))


# ------------------------------------------------------------ the kinds

static func _build(kind: String) -> ArrayMesh:
	match kind:
		"barn":
			var g := _grid(30, 22, 22)
			var red := Color("b83a2e")
			_box(g, Vector3i(1, 0, 2), Vector3i(28, 11, 19), red)
			for x in range(1, 29, 3):  # plank lines
				_box(g, Vector3i(x, 0, 19), Vector3i(x, 11, 19), red.darkened(0.15))
			_box(g, Vector3i(10, 0, 19), Vector3i(19, 8, 20), Color(0.95, 0.93, 0.88))  # door frame
			_box(g, Vector3i(11, 0, 20), Vector3i(18, 7, 20), red.darkened(0.25))
			for k in range(0, 8):  # the X on the doors
				g.set_v(11 + k, k, 20, Vox.SOLID, Color(0.95, 0.93, 0.88))
				g.set_v(18 - k, k, 20, Vox.SOLID, Color(0.95, 0.93, 0.88))
			_box(g, Vector3i(13, 13, 19), Vector3i(16, 15, 20), Color(1.0, 0.8, 0.4), Vox.GLOW)  # hayloft light
			_roof(g, 1, 28, 2, 19, 12, Color("4a4f5c"))
			return _done(g)
		"cottage":
			var g := _grid(18, 20, 16)
			var wall := Color(0.95, 0.92, 0.84)
			_box(g, Vector3i(1, 0, 2), Vector3i(16, 8, 13), wall)
			_box(g, Vector3i(7, 0, 13), Vector3i(9, 5, 14), Color("6b4a33"))  # door
			for wx in [3, 12]:
				_box(g, Vector3i(wx, 3, 13), Vector3i(wx + 2, 5, 14), Color(1.0, 0.85, 0.45), Vox.GLOW)
			_box(g, Vector3i(3, 3, 1), Vector3i(5, 5, 2), Color(1.0, 0.85, 0.45), Vox.GLOW)
			_roof(g, 1, 16, 2, 13, 9, Color("c4523a"))
			_box(g, Vector3i(12, 9, 4), Vector3i(13, 17, 5), Color(0.55, 0.42, 0.36))  # chimney
			for x in range(0, 18, 2):  # flower boxes
				g.set_v(x, 0, 15, Vox.SOLID, [VrStyle.PINK, VrStyle.YELLOW, Color.WHITE][x % 3])
			return _done(g)
		"windmill":
			var g := _grid(12, 34, 12)
			for y in 26:
				var r := 5 - y / 7
				_box(g, Vector3i(6 - r, y, 6 - r), Vector3i(5 + r, y, 5 + r), Color(0.93, 0.9, 0.84) if y % 6 != 5 else Color(0.8, 0.76, 0.7))
			_roof(g, 2, 9, 2, 9, 26, Color("5a4638"))
			_box(g, Vector3i(5, 0, 10), Vector3i(6, 3, 11), Color("6b4a33"))
			_box(g, Vector3i(5, 14, 10), Vector3i(6, 15, 11), Color(1.0, 0.85, 0.45), Vox.GLOW)
			return _done(g)
		"hay":
			var g := _grid(6, 4, 4)
			_box(g, Vector3i(0, 0, 0), Vector3i(5, 3, 3), Color("e3c25a"))
			for x in [1, 4]:
				_box(g, Vector3i(x, 0, 0), Vector3i(x, 3, 3), Color("c9a640"))
			return _done(g)
		"tractor":
			var g := _grid(14, 10, 9)
			var green := Color("3f8f3a")
			_box(g, Vector3i(4, 2, 2), Vector3i(12, 5, 6), green)
			_box(g, Vector3i(2, 2, 2), Vector3i(6, 8, 6), green.darkened(0.1))  # cab
			_box(g, Vector3i(3, 5, 2), Vector3i(5, 7, 6), Color(0.35, 0.5, 0.6), Vox.GLASS)
			_box(g, Vector3i(2, 9, 1), Vector3i(6, 9, 7), Color(0.95, 0.85, 0.2))  # roof
			_box(g, Vector3i(10, 6, 3), Vector3i(10, 8, 3), Color(0.2, 0.2, 0.22), Vox.METAL)  # exhaust
			_wheel(g, 3, 3, 0, 3, 2)
			_wheel(g, 3, 3, 7, 3, 2)
			_wheel(g, 11, 2, 0, 2, 2)
			_wheel(g, 11, 2, 7, 2, 2)
			g.set_v(13, 4, 3, Vox.GLOW, Color(1, 0.95, 0.75))
			g.set_v(13, 4, 5, Vox.GLOW, Color(1, 0.95, 0.75))
			return _done(g)
		"cow":
			var g := _grid(9, 7, 5)
			var white := Color(0.96, 0.95, 0.92)
			_box(g, Vector3i(1, 3, 1), Vector3i(7, 5, 3), white)
			for p in [Vector3i(2, 5, 1), Vector3i(3, 4, 3), Vector3i(5, 5, 2), Vector3i(6, 4, 1), Vector3i(4, 3, 1)]:
				g.set_v(p.x, p.y, p.z, Vox.SOLID, Color(0.12, 0.12, 0.12))
			for lx in [1, 6]:
				for lz in [1, 3]:
					_box(g, Vector3i(lx, 0, lz), Vector3i(lx, 2, lz), white.darkened(0.1))
			g.set_v(0, 4, 2, Vox.SOLID, Color(0.12, 0.12, 0.12))  # tail
			return _done(g)
		"stall":
			var g := _grid(14, 14, 10)
			var wood := Color("a8763e")
			_box(g, Vector3i(1, 0, 4), Vector3i(12, 4, 8), wood)
			_box(g, Vector3i(1, 5, 8), Vector3i(12, 5, 8), Color(0.95, 0.92, 0.85))  # counter top
			for x in [1, 12]:
				_box(g, Vector3i(x, 5, 1), Vector3i(x, 10, 1), wood.darkened(0.2))
				_box(g, Vector3i(x, 5, 8), Vector3i(x, 10, 8), wood.darkened(0.2))
			for x in range(0, 14):  # striped awning
				var cc := VrStyle.RED if (x / 2) % 2 == 0 else VrStyle.PAPER
				_box(g, Vector3i(x, 11, 0), Vector3i(x, 11, 9), cc)
				g.set_v(x, 10, 9, Vox.SOLID, cc)
			_box(g, Vector3i(3, 12, 1), Vector3i(10, 13, 1), VrStyle.YELLOW, Vox.GLOW)  # sign
			for p in [Vector3i(3, 6, 7), Vector3i(6, 6, 7), Vector3i(9, 6, 7)]:  # food!
				g.set_v(p.x, p.y, p.z, Vox.SOLID, [Color("d98b3a"), Color("f4d35e"), Color("e8432e")][p.x % 3])
			return _done(g)
		"fence":
			var g := _grid(26, 5, 2)
			var wood := Color("8a6a46")
			for x in range(0, 26, 5):
				_box(g, Vector3i(x, 0, 0), Vector3i(x, 4, 1), wood.darkened(0.15))
			_box(g, Vector3i(0, 1, 1), Vector3i(25, 1, 1), wood)
			_box(g, Vector3i(0, 3, 1), Vector3i(25, 3, 1), wood)
			return _done(g)
		"container", "containers":
			var two := kind == "containers"
			var g := _grid(26, 22 if two else 11, 11)
			var cols := [Color("2f6d9e"), Color("b8482f"), Color("3e8a5c"), Color("d8a33a")]
			for lvl in (2 if two else 1):
				var cc: Color = cols[(lvl * 3 + 1) % cols.size()]
				var y0 := lvl * 11
				_box(g, Vector3i(lvl * 2, y0, 0), Vector3i(23 + lvl * 2 if lvl == 0 else 25, y0 + 9, 10), cc)
				for x in range(lvl * 2, 24 + lvl * 2, 2):  # ribs
					_box(g, Vector3i(x, y0 + 1, 10), Vector3i(x, y0 + 8, 10), cc.darkened(0.18))
			return _done(g)
		"drums":
			var g := _grid(9, 5, 7)
			for p in [Vector2i(1, 1), Vector2i(5, 1), Vector2i(3, 4)]:
				var cc := Color("2f5d8a") if p.x == 5 else Color("8f3b2a")
				_box(g, Vector3i(p.x, 0, p.y), Vector3i(p.x + 2, 3, p.y + 2), cc)
				_box(g, Vector3i(p.x, 1, p.y), Vector3i(p.x + 2, 1, p.y + 2), cc.darkened(0.25))
			return _done(g)
		"fire_drum":
			var g := _grid(3, 6, 3)
			_box(g, Vector3i(0, 0, 0), Vector3i(2, 3, 2), Color("5a4a3a"))
			_box(g, Vector3i(0, 4, 0), Vector3i(2, 4, 2), Color(1.0, 0.55, 0.15), Vox.GLOW)
			g.set_v(1, 5, 1, Vox.GLOW, Color(1.0, 0.8, 0.3))
			return _done(g)
		"shed":
			var g := _grid(24, 16, 20)
			var metal := Color(0.62, 0.64, 0.66)
			_box(g, Vector3i(1, 0, 1), Vector3i(22, 10, 18), metal)
			for x in range(1, 23, 2):
				_box(g, Vector3i(x, 0, 18), Vector3i(x, 10, 18), metal.darkened(0.12))
			_box(g, Vector3i(7, 0, 18), Vector3i(16, 7, 19), Color(0.3, 0.32, 0.36))  # roll door
			_box(g, Vector3i(3, 7, 18), Vector3i(5, 8, 19), Color(1.0, 0.85, 0.45), Vox.GLOW)
			_box(g, Vector3i(0, 11, 0), Vector3i(23, 12, 19), Color(0.45, 0.47, 0.5))
			_box(g, Vector3i(15, 13, 6), Vector3i(19, 13, 10), Color(0.35, 0.36, 0.38))  # fan housing
			return _done(g)
		"scrap":
			var g := _grid(14, 8, 12)
			var rng := RandomNumberGenerator.new()
			rng.seed = 99
			for k in 60:
				var x := rng.randi_range(1, 12)
				var z := rng.randi_range(1, 10)
				var h := int(6.0 * (1.0 - Vector2(x - 7, z - 6).length() / 8.0))
				for y in maxi(h, 0):
					g.set_v(x, y, z, Vox.METAL if rng.randf() < 0.3 else Vox.SOLID, [Color("6b5444"), Color("8a7a6a"), Color("4a5560"), Color("a0522d")][rng.randi() % 4])
			return _done(g)
		"cabin":
			var g := _grid(18, 18, 16)
			var logc := Color("7a4f2e")
			for y in 8:
				_box(g, Vector3i(1, y, 2), Vector3i(16, y, 13), logc if y % 2 == 0 else logc.darkened(0.12))
			_box(g, Vector3i(7, 0, 13), Vector3i(9, 5, 14), Color("4a3020"))
			for wx in [3, 12]:
				_box(g, Vector3i(wx, 3, 13), Vector3i(wx + 2, 5, 14), Color(1.0, 0.78, 0.4), Vox.GLOW)
			_roof(g, 1, 16, 2, 13, 8, Color("5a3a2a"), true)
			_box(g, Vector3i(3, 8, 4), Vector3i(4, 16, 5), Color(0.5, 0.45, 0.42))
			_box(g, Vector3i(3, 17, 4), Vector3i(4, 17, 5), Color(0.96, 0.98, 1.0))
			return _done(g)
		"snowman":
			var g := _grid(7, 12, 7)
			var snow := Color(0.97, 0.98, 1.0)
			for s in [[3, 0, 3], [2, 4, 3], [2, 7, 2]]:  # [r, y0, h]
				for y in range(s[1], s[1] + s[2] + 1):
					for z in 7:
						for x in 7:
							if Vector2(x - 3, z - 3).length() <= float(s[0]):
								g.set_v(x, y, z, Vox.SOLID, snow)
			g.set_v(3, 8, 6, Vox.SOLID, Color(1.0, 0.55, 0.1))  # carrot
			g.set_v(2, 9, 5, Vox.SOLID, Color(0.1, 0.1, 0.1))
			g.set_v(4, 9, 5, Vox.SOLID, Color(0.1, 0.1, 0.1))
			_box(g, Vector3i(1, 10, 1), Vector3i(5, 10, 5), Color(0.12, 0.12, 0.14))  # hat
			_box(g, Vector3i(2, 11, 2), Vector3i(4, 11, 4), Color(0.12, 0.12, 0.14))
			_box(g, Vector3i(2, 7, 5), Vector3i(4, 7, 6), VrStyle.RED)  # scarf
			return _done(g)
		"sledge":
			var g := _grid(8, 3, 4)
			_box(g, Vector3i(1, 1, 0), Vector3i(6, 1, 3), VrStyle.RED)
			for z in [0, 3]:
				_box(g, Vector3i(0, 0, z), Vector3i(7, 0, z), Color(0.7, 0.72, 0.76), Vox.METAL)
			return _done(g)
		"pit_garages":
			var g := _grid(56, 16, 18)
			var wall := Color(0.86, 0.87, 0.9)
			_box(g, Vector3i(0, 0, 1), Vector3i(55, 10, 16), wall)
			_box(g, Vector3i(0, 11, 0), Vector3i(55, 12, 17), Color(0.3, 0.32, 0.38))
			_box(g, Vector3i(0, 9, 17), Vector3i(55, 10, 17), VrStyle.RED)
			for k in 5:  # bays with roll-up doors, lit inside at night
				var x0 := 2 + k * 11
				_box(g, Vector3i(x0, 0, 16), Vector3i(x0 + 8, 7, 17), Color(0.22, 0.24, 0.3))
				_box(g, Vector3i(x0, 6, 16), Vector3i(x0 + 8, 7, 17), Color(1.0, 0.93, 0.75), Vox.GLOW)
				_box(g, Vector3i(x0 + 3, 9, 17), Vector3i(x0 + 5, 10, 17), [VrStyle.YELLOW, VrStyle.TEAL, VrStyle.PINK, VrStyle.SKY, VrStyle.GREEN][k], Vox.GLOW)
			for x in range(20, 36):  # a race-control box on top
				_box(g, Vector3i(x, 13, 4), Vector3i(x, 15, 12), Color(0.9, 0.9, 0.93))
			_box(g, Vector3i(21, 14, 12), Vector3i(34, 14, 12), Color(0.4, 0.6, 0.8), Vox.GLASS)
			return _done(g)
		"tent":
			var g := _grid(18, 13, 18)
			for y in 12:
				var r := 8 - (maxi(y - 5, 0) * 8) / 7
				for z in range(9 - r, 9 + r):
					for x in range(9 - r, 9 + r):
						if y < 6 and x > 9 - r and x < 8 + r and z > 9 - r and z < 8 + r:
							continue  # hollow below the roof line
						var stripe := ((x + z) / 3) % 2 == 0
						g.set_v(x, y, z, Vox.SOLID, Color.WHITE if stripe else VrStyle.TEAL)
			_box(g, Vector3i(6, 0, 16), Vector3i(11, 4, 17), Color(0, 0, 0, 0), Vox.AIR)  # entrance
			_box(g, Vector3i(7, 2, 9), Vector3i(10, 3, 9), Color(1.0, 0.9, 0.6), Vox.GLOW)
			return _done(g)
		"tv_tower":
			var g := _grid(7, 26, 7)
			var steel := Color(0.55, 0.57, 0.6)
			for y in 20:
				for c in [Vector2i(0, 0), Vector2i(6, 0), Vector2i(0, 6), Vector2i(6, 6)]:
					g.set_v(c.x, y, c.y, Vox.METAL, steel)
				if y % 4 == 0:
					_box(g, Vector3i(0, y, 0), Vector3i(6, y, 0), steel)
					_box(g, Vector3i(0, y, 6), Vector3i(6, y, 6), steel)
			_box(g, Vector3i(0, 20, 0), Vector3i(6, 20, 6), Color(0.35, 0.37, 0.4))
			_box(g, Vector3i(2, 21, 2), Vector3i(3, 23, 3), Color(0.12, 0.12, 0.14))  # the cameraman's camera
			_box(g, Vector3i(3, 22, 3), Vector3i(4, 22, 5), Color(0.12, 0.12, 0.14))
			g.set_v(4, 22, 6, Vox.GLOW, VrStyle.RED)  # tally light
			_box(g, Vector3i(4, 21, 1), Vector3i(5, 24, 2), Color(0.2, 0.25, 0.45))  # the operator
			_box(g, Vector3i(4, 25, 1), Vector3i(5, 25, 2), Color(0.96, 0.76, 0.6))
			return _done(g)
		"screen":
			var g := _grid(26, 20, 3)
			_box(g, Vector3i(3, 0, 1), Vector3i(4, 8, 2), Color(0.3, 0.3, 0.33))
			_box(g, Vector3i(21, 0, 1), Vector3i(22, 8, 2), Color(0.3, 0.3, 0.33))
			_box(g, Vector3i(0, 8, 0), Vector3i(25, 19, 1), Color(0.12, 0.12, 0.15))
			for y in range(9, 19):
				for x in range(1, 25):
					var cc := VrStyle.SKY.lerp(VrStyle.NIGHT_LIGHT, float(y - 9) / 10.0)
					if y in [12, 13] and x in range(5, 20):
						cc = VrStyle.YELLOW
					if y == 16 and x in range(3, 23):
						cc = VrStyle.PAPER
					g.set_v(x, y, 2, Vox.GLOW, cc)
			return _done(g)
		"tow_truck", "ambulance":
			var amb := kind == "ambulance"
			var g := _grid(18, 10, 9)
			var body := Color(0.97, 0.97, 0.95) if amb else Color("f0a81c")
			_box(g, Vector3i(1, 2, 1), Vector3i(16, 4, 7), body)
			_box(g, Vector3i(11, 5, 1), Vector3i(16, 7, 7), body)
			_box(g, Vector3i(15, 5, 2), Vector3i(16, 6, 6), Color(0.35, 0.5, 0.62), Vox.GLASS)
			if amb:
				_box(g, Vector3i(1, 5, 1), Vector3i(10, 7, 7), body)
				_box(g, Vector3i(4, 4, 0), Vector3i(8, 4, 0), VrStyle.RED)
				_box(g, Vector3i(5, 3, 0), Vector3i(7, 5, 0), VrStyle.RED)
				g.set_v(14, 8, 2, Vox.GLOW, Color(0.3, 0.5, 1.0))
				g.set_v(14, 8, 6, Vox.GLOW, Color(1.0, 0.2, 0.2))
			else:
				for y in range(5, 9):  # the crane arm
					g.set_v(4 + (y - 5), y, 4, Vox.METAL, Color(0.25, 0.25, 0.28))
				g.set_v(8, 8, 4, Vox.METAL, Color(0.25, 0.25, 0.28))
				g.set_v(13, 8, 3, Vox.GLOW, Color(1.0, 0.6, 0.1))
				g.set_v(13, 8, 5, Vox.GLOW, Color(1.0, 0.6, 0.1))
			for wx in [4, 13]:
				_wheel(g, wx, 2, 0, 2, 1)
				_wheel(g, wx, 2, 7, 2, 1)
			return _done(g)
		"tyre_wall":
			var g := _grid(20, 6, 4)
			for x in range(0, 20, 4):
				for y in range(0, 6, 2):
					var cc := Color(0.1, 0.1, 0.11)
					if y == 4 and x % 8 == 0:
						cc = VrStyle.RED
					elif y == 4:
						cc = VrStyle.PAPER
					_box(g, Vector3i(x, y, 0), Vector3i(x + 3, y + 1, 3), cc)
			return _done(g)
		"duck":
			var g := _grid(12, 13, 9)
			var yel := Color("f7d23a")
			for yy in 7:
				for z in 9:
					for x in 12:
						if Vector3(x - 5.5, (yy - 3.0) * 1.3, z - 4.0).length() < 4.6:
							g.set_v(x, yy, z, Vox.SOLID, yel)
			for yy in range(6, 12):
				for z in 9:
					for x in 12:
						if Vector3(x - 8.0, yy - 9.0, z - 4.0).length() < 2.8:
							g.set_v(x, yy, z, Vox.SOLID, yel)
			_box(g, Vector3i(11, 8, 3), Vector3i(11, 9, 5), Color(1.0, 0.5, 0.1))
			g.set_v(10, 10, 2, Vox.SOLID, Color(0.08, 0.08, 0.1))
			g.set_v(10, 10, 6, Vox.SOLID, Color(0.08, 0.08, 0.1))
			_box(g, Vector3i(0, 4, 3), Vector3i(1, 5, 5), yel.darkened(0.08))
			return _done(g)
		"blocks":
			var g := _grid(16, 9, 12)
			var spots := [[0, 0, 0, VrStyle.RED], [5, 0, 1, VrStyle.SKY], [10, 0, 0, VrStyle.YELLOW], [2, 3, 1, VrStyle.GREEN], [7, 3, 2, VrStyle.PINK], [4, 6, 2, VrStyle.TEAL]]
			for s in spots:
				_box(g, Vector3i(s[0], s[1], s[2]), Vector3i(s[0] + 4, s[1] + 2, s[2] + 7), s[3])
				for sx in [s[0] + 1, s[0] + 3]:  # studs
					g.set_v(sx, s[1] + 3, s[2] + 2, Vox.SOLID, (s[3] as Color).lightened(0.15))
					g.set_v(sx, s[1] + 3, s[2] + 5, Vox.SOLID, (s[3] as Color).lightened(0.15))
			return _done(g)
		"robot":
			var g := _grid(8, 15, 6)
			var steel := Color(0.72, 0.74, 0.8)
			_box(g, Vector3i(1, 0, 2), Vector3i(2, 4, 3), steel.darkened(0.2))
			_box(g, Vector3i(5, 0, 2), Vector3i(6, 4, 3), steel.darkened(0.2))
			_box(g, Vector3i(0, 5, 1), Vector3i(7, 10, 4), steel)
			_box(g, Vector3i(2, 7, 5), Vector3i(5, 8, 5), VrStyle.RED, Vox.GLOW)
			_box(g, Vector3i(2, 11, 1), Vector3i(5, 13, 4), steel.lightened(0.1))
			g.set_v(2, 12, 5, Vox.GLOW, VrStyle.SKY)
			g.set_v(5, 12, 5, Vox.GLOW, VrStyle.SKY)
			g.set_v(3, 14, 2, Vox.METAL, steel)
			return _done(g)
		"mug":
			var g := _grid(14, 13, 12)
			for y in 12:
				for z in 12:
					for x in 12:
						var r := Vector2(x - 5.5, z - 5.5).length()
						if r < 5.6 and (r > 4.4 or y == 0):
							g.set_v(x, y, z, Vox.SOLID, VrStyle.PAPER if (y / 3) % 2 == 0 else VrStyle.TEAL)
						elif r <= 4.4 and y == 9:
							g.set_v(x, y, z, Vox.SOLID, Color("4a2c1a"))  # coffee
			for y in range(3, 9):
				g.set_v(12, y, 5, Vox.SOLID, VrStyle.PAPER)
				g.set_v(12, y, 6, Vox.SOLID, VrStyle.PAPER)
			_box(g, Vector3i(11, 3, 5), Vector3i(12, 3, 6), VrStyle.PAPER)
			_box(g, Vector3i(11, 8, 5), Vector3i(12, 8, 6), VrStyle.PAPER)
			return _done(g)
		"flagpole":
			var g := _grid(3, 24, 3)
			_box(g, Vector3i(1, 0, 1), Vector3i(1, 23, 1), Color(0.8, 0.82, 0.86), Vox.METAL)
			return _done(g)
		"bench":
			var g := _grid(10, 4, 4)
			_box(g, Vector3i(0, 2, 0), Vector3i(9, 2, 3), Color("8a6a46"))
			for x in [1, 8]:
				_box(g, Vector3i(x, 0, 0), Vector3i(x, 1, 3), Color(0.25, 0.25, 0.28))
			return _done(g)
	var g := _grid(4, 4, 4)
	_box(g, Vector3i.ZERO, Vector3i(3, 3, 3), Color.MAGENTA)
	return _done(g)


## Animated parts, each around its own pivot (origin).
static func _build_part(kind: String) -> ArrayMesh:
	match kind:
		"sails":  # windmill sails, turning about Z
			var g := _grid(25, 25, 2)
			for k in 4:
				for r in range(2, 12):
					for w in range(0, 3):
						var p: Vector2i = [Vector2i(12 + r, 12 + w), Vector2i(12 - w, 12 + r), Vector2i(12 - r, 12 - w), Vector2i(12 + w, 12 - r)][k]
						g.set_v(p.x, p.y, 0, Vox.SOLID, Color(0.95, 0.93, 0.88) if w > 0 else Color("6b4a33"))
			_box(g, Vector3i(11, 11, 0), Vector3i(13, 13, 1), Color("6b4a33"))
			return VoxelMesher.build_mesh(g, VoxelCars.material(), Vector3(12.5, 12.5, 1.0) * C, 0.02)
		"fan":  # a roof vent fan, turning about Y
			var g := _grid(5, 1, 5)
			for k in 5:
				g.set_v(k, 0, 2, Vox.METAL, Color(0.75, 0.76, 0.78))
				g.set_v(2, 0, k, Vox.METAL, Color(0.75, 0.76, 0.78))
			return VoxelMesher.build_mesh(g, VoxelCars.material(), Vector3(2.5, 0.0, 2.5) * C, 0.0)
		"cow_head":  # looks around (turns about Y at the neck)
			var g := _grid(4, 4, 3)
			var white := Color(0.96, 0.95, 0.92)
			_box(g, Vector3i(0, 0, 0), Vector3i(2, 2, 2), white)
			_box(g, Vector3i(3, 0, 0), Vector3i(3, 1, 2), Color(0.95, 0.7, 0.7))  # snout
			g.set_v(2, 2, 0, Vox.SOLID, Color(0.1, 0.1, 0.1))
			g.set_v(2, 2, 2, Vox.SOLID, Color(0.1, 0.1, 0.1))
			g.set_v(1, 3, 0, Vox.SOLID, Color(0.85, 0.8, 0.7))
			g.set_v(1, 3, 2, Vox.SOLID, Color(0.85, 0.8, 0.7))
			return VoxelMesher.build_mesh(g, VoxelCars.material(), Vector3(0.0, 1.0, 1.5) * C, 0.02)
		"pennant":  # a flag on the flagpole (sways)
			var g := _grid(8, 5, 1)
			for y in 5:
				for x in 8:
					if x < 8 - absi(y - 2) * 2:
						g.set_v(x, y, 0, Vox.SOLID, VrStyle.RED if y % 2 == 0 else VrStyle.YELLOW)
			return VoxelMesher.build_mesh(g, VoxelCars.material(), Vector3(0.0, 2.5, 0.5) * C, 0.0)
	return mesh("x")
