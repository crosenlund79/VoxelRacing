extends RefCounted
## VoxelRacing: the voxel models of the garage workshop (GarageWorkshop): the
## room, its furniture, tools, signs and posters. Every model is a VoxelGrid
## meshed with the cars' own voxel material (bevelled blocks, baked AO, lamp
## glow), so the workshop and the cars share one look. Built once, the first
## time the garage opens. Loaded with preload (no class_name).

const VS := 0.125      ## prop voxel: the cars' fine voxel
const RS := 0.25       ## room voxel: floor and walls
const FINE := 0.0625   ## posters and signs

const WOOD := Color("a06a44")
const WOOD_DARK := Color("6b4229")
const STEEL := Color("a3a9bd")
const STEEL_DARK := Color("4b5068")
const RUBBER := Color(0.09, 0.09, 0.11)
const CARDBOARD := Color("b48655")
const SKIN := Color(0.96, 0.76, 0.6)
const BRICK := Color("5e3d5c")
const PANEL := Color("3a4072")
const FLOOR_A := Color("3d3962")
const FLOOR_B := Color("46406e")

## A 3x5 (W, M, N wider) pixel font for the signs.
const GLYPHS := {
	"A": [".#.", "#.#", "###", "#.#", "#.#"],
	"B": ["##.", "#.#", "##.", "#.#", "##."],
	"D": ["##.", "#.#", "#.#", "#.#", "##."],
	"E": ["###", "#..", "##.", "#..", "###"],
	"H": ["#.#", "#.#", "###", "#.#", "#.#"],
	"I": ["###", ".#.", ".#.", ".#.", "###"],
	"L": ["#..", "#..", "#..", "#..", "###"],
	"M": ["#...#", "##.##", "#.#.#", "#...#", "#...#"],
	"N": ["#..#", "##.#", "#.##", "#..#", "#..#"],
	"O": ["###", "#.#", "#.#", "#.#", "###"],
	"P": ["##.", "#.#", "##.", "#..", "#.."],
	"S": [".##", "#..", ".#.", "..#", "##."],
	"T": ["###", ".#.", ".#.", ".#.", ".#."],
	"U": ["#.#", "#.#", "#.#", "#.#", "###"],
	"W": ["#...#", "#...#", "#.#.#", "#.#.#", ".#.#."],
	"X": ["#.#", "#.#", ".#.", "#.#", "#.#"],
	"Y": ["#.#", "#.#", ".#.", ".#.", ".#."],
	"0": ["###", "#.#", "#.#", "#.#", "###"],
	"!": ["#", "#", "#", ".", "#"],
	" ": ["..", "..", "..", "..", ".."],
}


static func mesh(g: VoxelGrid, pivot: Vector3 = Vector3.ZERO, jitter: float = 0.06) -> ArrayMesh:
	return VoxelMesher.build_mesh(g, VoxelCars.material(), pivot, jitter)


# ------------------------------------------------------------ text

static func text_width(t: String, scale: int = 1) -> int:
	var w := 0
	for ch in t:
		var rows: Array = GLYPHS.get(ch, GLYPHS[" "])
		w += ((rows[0] as String).length() + 1) * scale
	return maxi(0, w - scale)


## Writes `t` with its top row at y_top (rows go down), facing +Z at layer z.
static func draw_text(g: VoxelGrid, t: String, x0: int, y_top: int, z: int, m: int, c: Color, scale: int = 1) -> void:
	var x := x0
	for ch in t:
		var rows: Array = GLYPHS.get(ch, GLYPHS[" "])
		var w := (rows[0] as String).length()
		for r in 5:
			var row: String = rows[r]
			for k in w:
				if row[k] != "#":
					continue
				for sy in scale:
					for sx in scale:
						g.set_v(x + k * scale + sx, y_top - r * scale - sy, z, m, c)
		x += (w + 1) * scale


# ------------------------------------------------------------ the room

## The floor (top at y = 0) over x0..x1, z0..z1: concrete tiles with grout, a
## dashed yellow ring around the turntable and glossy oil stains.
static func floor_mesh(x0: float, x1: float, z0: float, z1: float, ring_r: float) -> ArrayMesh:
	var nx := int((x1 - x0) / RS)
	var nz := int((z1 - z0) / RS)
	var g := VoxelGrid.new(Vector3i(nx, 1, nz), RS, Vector3(x0, -RS, z0))
	var stains := [Vector3(-5.6, -3.9, 0.9), Vector3(7.8, -2.2, 0.7), Vector3(-2.2, 3.6, 0.6), Vector3(3.6, -4.6, 0.5)]
	for z in nz:
		for x in nx:
			var wx := x0 + (x + 0.5) * RS
			var wz := z0 + (z + 0.5) * RS
			var tile := (floori(wx) + floori(wz)) % 2 == 0
			var c := FLOOR_A if tile else FLOOR_B
			c = c.lightened(0.05 * Vox.hash3(floori(wx), 3, floori(wz)))
			var m := Vox.SOLID
			if posmod(x, 4) == 0 or posmod(z, 4) == 0:
				c = c.darkened(0.22)
			var r := Vector2(wx, wz).length()
			var ang := Vector2(wx, wz).angle()
			if absf(r - (ring_r + 0.45)) < 0.14 and int(floor((ang + PI) / (TAU / 28.0))) % 2 == 0:
				c = VrStyle.YELLOW.darkened(0.12)
			for s in stains:
				var st: Vector3 = s
				var d := Vector2(wx - st.x, (wz - st.y) * 1.4).length() + Vox.hash3(x, 9, z) * 0.25
				if d < st.z:
					c = c.lerp(Color(0.07, 0.06, 0.09), 0.75 * (1.0 - d / st.z * 0.5))
					m = Vox.METAL
			g.set_v(x, 0, z, m, c)
	return mesh(g, Vector3.ZERO, 0.05)


## A wall `length` long (along +X) and `height` high, facing +Z with its face
## at z = 0: chequered skirting, a red stripe, blue panelling, a dark trim and
## plum bricks above.
static func wall_mesh(length: float, height: float, seed_x: int = 0) -> ArrayMesh:
	var nx := int(length / RS)
	var ny := int(height / RS)
	var g := VoxelGrid.new(Vector3i(nx, ny, 1), RS, Vector3.ZERO)
	for y in ny:
		for x in nx:
			var c: Color
			var xs := x + seed_x
			if y <= 1:
				c = VrStyle.PAPER.darkened(0.25) if (xs + y) % 2 == 0 else VrStyle.INK
			elif y == 2:
				c = VrStyle.RED
			elif y <= 9:
				c = PANEL.darkened(0.25) if xs % 8 == 0 else PANEL.lightened(0.04 * (y % 2))
			elif y == 10:
				c = Color("272b52")
			else:
				var brick := (xs + (y % 2)) / 2
				c = BRICK.lightened(0.12 * Vox.hash3(brick, y, 5)).darkened(0.1 * Vox.hash3(y, brick, 2))
				if (xs + (y % 2)) % 2 == 0:
					c = c.darkened(0.06)
			g.set_v(x, y, 0, Vox.SOLID, c)
	return mesh(g, Vector3(0, 0, RS), 0.04)


# ------------------------------------------------------------ the turntable

## The car's turntable: a steel disc with grooves and a hazard-striped rim
## (radius r, top at RS); centred on the origin, standing on y = 0.
static func turntable_mesh(r: float) -> ArrayMesh:
	var n := int(ceil(r / VS)) * 2
	var g := VoxelGrid.new(Vector3i(n, 2, n), VS, Vector3.ZERO)
	var rc := r / VS
	for z in n:
		for x in n:
			var p := Vector2(x + 0.5 - n * 0.5, z + 0.5 - n * 0.5)
			var d := p.length()
			if d > rc:
				continue
			var c := Color("5d6380")
			var m := Vox.SOLID
			if d > rc - 1.6:
				var seg := int(floor((p.angle() + PI) / (TAU / 36.0))) % 2 == 0
				c = VrStyle.YELLOW if seg else VrStyle.INK
			elif int(d) % 5 == 0:
				c = c.darkened(0.25)
			elif d < 3.2:
				c = VrStyle.RED
				m = Vox.METAL
			else:
				m = Vox.METAL
				c = c.lightened(0.06 * Vox.hash3(x, 1, z))
			g.set_v(x, 1, z, m, c)
			if d < rc - 0.8:
				g.set_v(x, 0, z, Vox.SOLID, Color("2a2d44"))
	return mesh(g, Vector3(n * 0.5, 0, n * 0.5) * VS, 0.03)


# ------------------------------------------------------------ furniture

## The workbench: a wooden top at 1 unit with a lower shelf, a vice, tools and
## a mug. Back edge against z = 0, from x = 0 along +X (3 units), towards +Z.
static func workbench_mesh() -> ArrayMesh:
	var g := VoxelGrid.new(Vector3i(24, 11, 8), VS, Vector3.ZERO)
	for x in 24:
		for z in 7:
			var grain := WOOD.darkened(0.08 * float((x / 3 + z * 2) % 3))
			g.set_v(x, 7, z, Vox.SOLID, grain if z < 6 else WOOD_DARK)
			if x >= 1 and x <= 22 and z >= 1:
				g.set_v(x, 2, z, Vox.SOLID, WOOD_DARK)
	for lx in [0, 22]:
		for lz in [0, 5]:
			g.box(Vector3i(lx, 0, lz), Vector3i(lx + 1, 6, lz + 1), Vox.SOLID, STEEL_DARK)
	# a red toolbox and a paint can on the shelf
	g.box(Vector3i(3, 3, 2), Vector3i(8, 4, 5), Vox.SOLID, VrStyle.RED)
	g.box(Vector3i(5, 5, 3), Vector3i(6, 5, 4), Vox.METAL, STEEL)
	g.box(Vector3i(13, 3, 2), Vector3i(14, 5, 3), Vox.SOLID, VrStyle.TEAL)
	g.set_v(13, 6, 2, Vox.METAL, STEEL)
	g.box(Vector3i(16, 3, 2), Vector3i(20, 4, 5), Vox.SOLID, CARDBOARD)
	# the vice at the right end
	g.box(Vector3i(19, 8, 5), Vector3i(21, 9, 7), Vox.METAL, STEEL_DARK)
	g.box(Vector3i(19, 10, 5), Vector3i(21, 10, 5), Vox.METAL, STEEL)
	g.box(Vector3i(19, 10, 7), Vector3i(21, 10, 7), Vox.METAL, STEEL)
	# a spanner, a hammer and a mug on the top
	g.box(Vector3i(3, 8, 4), Vector3i(7, 8, 4), Vox.METAL, STEEL)
	g.set_v(2, 8, 3, Vox.METAL, STEEL)
	g.set_v(2, 8, 5, Vox.METAL, STEEL)
	g.box(Vector3i(10, 8, 3), Vector3i(13, 8, 3), Vox.SOLID, WOOD_DARK)
	g.box(Vector3i(14, 8, 2), Vector3i(14, 9, 4), Vox.METAL, STEEL_DARK)
	g.box(Vector3i(16, 8, 1), Vector3i(17, 9, 2), Vox.SOLID, VrStyle.PAPER)
	g.set_v(18, 9, 1, Vox.SOLID, VrStyle.PAPER)
	g.set_v(16, 9, 1, Vox.SOLID, Color(0.25, 0.15, 0.1))  # coffee
	return mesh(g)


## The pegboard over the bench (3 x 1.5 units, face at z = 0): perforated
## board with a tool outline wall: spanners, a hammer, screwdrivers, pliers.
static func pegboard_mesh() -> ArrayMesh:
	var g := VoxelGrid.new(Vector3i(24, 12, 2), VS, Vector3.ZERO)
	var board := Color("c39463")
	for y in 12:
		for x in 24:
			var c := board
			if x == 0 or x == 23 or y == 0 or y == 11:
				c = WOOD_DARK
			elif x % 2 == 1 and y % 2 == 1:
				c = board.darkened(0.35)
			g.set_v(x, y, 0, Vox.SOLID, c)
	# spanners of three sizes
	for k in 3:
		var x := 2 + k * 2
		g.box(Vector3i(x, 3, 1), Vector3i(x, 6 + k, 1), Vox.METAL, STEEL)
		g.set_v(x - 1 if k != 1 else x + 1, 7 + k, 1, Vox.METAL, STEEL)
		g.set_v(x, 2, 1, Vox.METAL, STEEL)
	# the hammer
	g.box(Vector3i(10, 3, 1), Vector3i(10, 8, 1), Vox.SOLID, WOOD)
	g.box(Vector3i(9, 9, 1), Vector3i(12, 9, 1), Vox.METAL, STEEL_DARK)
	# screwdrivers with coloured handles
	var handles: Array[Color] = [VrStyle.RED, VrStyle.YELLOW, VrStyle.TEAL]
	for k in 3:
		var x := 14 + k * 2
		g.box(Vector3i(x, 6, 1), Vector3i(x, 8, 1), Vox.SOLID, handles[k])
		g.box(Vector3i(x, 3, 1), Vector3i(x, 5, 1), Vox.METAL, STEEL)
	# pliers
	g.box(Vector3i(20, 3, 1), Vector3i(20, 6, 1), Vox.SOLID, VrStyle.RED)
	g.box(Vector3i(22, 3, 1), Vector3i(22, 6, 1), Vox.SOLID, VrStyle.RED)
	g.set_v(21, 7, 1, Vox.METAL, STEEL_DARK)
	g.box(Vector3i(21, 8, 1), Vector3i(21, 9, 1), Vox.METAL, STEEL)
	return mesh(g)


## The red rolling tool chest (1.5 x 2 x 0.9 units), drawers with steel
## handles, a sticker; back against z = 0, from x = 0.
static func tool_cabinet_mesh() -> ArrayMesh:
	var g := VoxelGrid.new(Vector3i(12, 17, 8), VS, Vector3.ZERO)
	var red := VrStyle.RED
	g.box(Vector3i(0, 1, 0), Vector3i(11, 14, 6), Vox.SOLID, red)
	for y in [4, 7, 9, 11, 13]:
		for x in 12:
			g.set_v(x, y, 6, Vox.SOLID, VrStyle.RED_DARK)
	for y in [2, 5, 8, 10, 12]:
		for x in range(3, 9):
			g.set_v(x, y + 1 if y == 2 else y, 7, Vox.METAL, STEEL)
	# top chest with a lid
	g.box(Vector3i(0, 15, 0), Vector3i(11, 15, 6), Vox.SOLID, Color("2b2f4d"))
	g.box(Vector3i(4, 16, 2), Vector3i(7, 16, 3), Vox.METAL, STEEL_DARK)
	# castors
	for cx in [1, 10]:
		for cz in [1, 5]:
			g.set_v(cx, 0, cz, Vox.SOLID, RUBBER)
	# a yellow lightning sticker on the side
	for k in 4:
		g.set_v(0, 9 - k, 3 + (k % 2), Vox.SOLID, VrStyle.YELLOW)
	return mesh(g, Vector3.ZERO, 0.04)


## Steel shelving (3.5 x 2.75 units, 0.6 deep): paint cans, boxes, oil
## bottles, a helmet and a trophy. Back against z = 0, from x = 0.
static func shelves_mesh() -> ArrayMesh:
	var g := VoxelGrid.new(Vector3i(28, 23, 5), VS, Vector3.ZERO)
	for ux in [0, 27]:
		for uz in [0, 4]:
			g.box(Vector3i(ux, 0, uz), Vector3i(ux, 22, uz), Vox.METAL, STEEL_DARK)
	for sy in [1, 8, 15, 22]:
		g.box(Vector3i(0, sy, 0), Vector3i(27, sy, 4), Vox.SOLID, WOOD if sy != 22 else WOOD_DARK)
	# bottom shelf: two boxes and a crate of bottles
	g.box(Vector3i(2, 2, 0), Vector3i(8, 6, 3), Vox.SOLID, CARDBOARD)
	g.box(Vector3i(2, 4, 3), Vector3i(8, 4, 3), Vox.SOLID, CARDBOARD.darkened(0.25))
	g.box(Vector3i(10, 2, 1), Vector3i(15, 4, 3), Vox.SOLID, CARDBOARD.lightened(0.08))
	for k in 4:
		g.box(Vector3i(18 + k * 2, 2, 2), Vector3i(18 + k * 2, 5, 2), Vox.SOLID, VrStyle.GREEN.darkened(0.15))
		g.set_v(18 + k * 2, 6, 2, Vox.SOLID, VrStyle.INK)
	# middle shelf: paint cans
	var cans: Array[Color] = [VrStyle.RED, VrStyle.TEAL, VrStyle.YELLOW, VrStyle.SKY, VrStyle.PINK]
	for k in cans.size():
		var x := 2 + k * 5
		g.box(Vector3i(x, 9, 1), Vector3i(x + 2, 11, 3), Vox.SOLID, cans[k])
		g.box(Vector3i(x, 12, 1), Vector3i(x + 2, 12, 3), Vox.METAL, STEEL)
		g.set_v(x + 1, 10, 4, Vox.SOLID, VrStyle.PAPER)  # label
	# top shelf: a helmet, the trophy, spray cans
	g.box(Vector3i(2, 16, 1), Vector3i(6, 19, 4), Vox.SOLID, VrStyle.RED)
	g.box(Vector3i(3, 17, 4), Vector3i(6, 18, 4), Vox.GLASS, Color(0.12, 0.14, 0.2))
	g.box(Vector3i(2, 19, 1), Vector3i(6, 19, 3), Vox.SOLID, VrStyle.PAPER)
	g.box(Vector3i(11, 16, 1), Vector3i(15, 16, 3), Vox.SOLID, VrStyle.INK)
	g.box(Vector3i(12, 17, 2), Vector3i(14, 17, 2), Vox.METAL, VrStyle.YELLOW.darkened(0.1))
	g.set_v(13, 18, 2, Vox.METAL, VrStyle.YELLOW)
	g.box(Vector3i(11, 19, 1), Vector3i(15, 21, 3), Vox.METAL, VrStyle.YELLOW)
	g.box(Vector3i(12, 20, 2), Vector3i(14, 21, 2), Vox.METAL, VrStyle.YELLOW.darkened(0.3))
	g.set_v(10, 20, 2, Vox.METAL, VrStyle.YELLOW)
	g.set_v(16, 20, 2, Vox.METAL, VrStyle.YELLOW)
	for k in 3:
		g.box(Vector3i(20 + k * 2, 16, 2), Vector3i(20 + k * 2, 19, 2), Vox.SOLID, [VrStyle.PINK, VrStyle.SKY, VrStyle.GREEN][k])
		g.set_v(20 + k * 2, 20, 2, Vox.SOLID, VrStyle.PAPER)
	return mesh(g)


## A wooden crate (0.75 units), or an olive ammunition crate with a hazard
## band. Centred on x / z, standing on y = 0.
static func crate_mesh(ammo: bool = false) -> ArrayMesh:
	var g := VoxelGrid.new(Vector3i(6, 6, 6), VS, Vector3.ZERO)
	var base := Color("5f6a3a") if ammo else WOOD
	for y in 6:
		for z in 6:
			for x in 6:
				var edge := int(x == 0 or x == 5) + int(y == 0 or y == 5) + int(z == 0 or z == 5)
				var c := base
				if edge >= 2:
					c = base.darkened(0.35)
				elif not ammo and y % 2 == 1:
					c = base.darkened(0.12)
				if ammo and y == 3 and edge < 2:
					c = VrStyle.YELLOW if (x + z) % 2 == 0 else VrStyle.INK
				g.set_v(x, y, z, Vox.SOLID, c)
	return mesh(g, Vector3(3, 0, 3) * VS)


## An oil drum (r 0.44, 1.1 high) with two ridges and a steel lid.
static func drum_mesh(colour: Color) -> ArrayMesh:
	var g := VoxelGrid.new(Vector3i(7, 9, 7), VS, Vector3.ZERO)
	for y in 9:
		for z in 7:
			for x in 7:
				var d := Vector2(x - 3, z - 3).length()
				if d > 3.3:
					continue
				var c := colour
				var m := Vox.SOLID
				if y == 8:
					c = STEEL_DARK
					m = Vox.METAL
					if x == 4 and z == 2:
						c = STEEL
				elif y == 3 or y == 6:
					c = colour.lightened(0.18)
				elif y == 0:
					c = colour.darkened(0.3)
				g.set_v(x, y, z, m, c)
	# a white band with a drop
	for x in range(1, 6):
		g.set_v(x, 4, 6, Vox.SOLID, VrStyle.PAPER)
	g.set_v(3, 5, 6, Vox.SOLID, VrStyle.PAPER)
	return mesh(g, Vector3(3.5, 0, 3.5) * VS)


## A hanging work lamp's shade with its warm bulb (GLOW), hanging from the
## origin (shade top), and its cable `cable` units long going up.
static func lamp_mesh(cable: float) -> ArrayMesh:
	var nc := int(cable / VS)
	var g := VoxelGrid.new(Vector3i(7, 4 + nc, 7), VS, Vector3.ZERO)
	var shade := Color("2f6a5e")
	for y in 3:
		var r := 1.2 + y * 1.0
		for z in 7:
			for x in 7:
				var d := Vector2(x - 3, z - 3).length()
				if d <= r + 0.3 and (y == 2 and d > r - 1.0 or y < 2 and d > r - 1.5 or y == 0):
					g.set_v(x, 3 - y, z, Vox.SOLID, shade if y < 2 or d > r - 0.5 else shade.lightened(0.3))
	for z in range(2, 5):
		for x in range(2, 5):
			g.set_v(x, 1, z, Vox.GLOW, Color(1.0, 0.82, 0.5))
	g.set_v(3, 0, 3, Vox.GLOW, Color(1.0, 0.86, 0.6))
	for y in range(4, 4 + nc):
		g.set_v(3, y, 3, Vox.SOLID, Color(0.12, 0.12, 0.14))
	return mesh(g, Vector3(3.5, 4, 3.5) * VS, 0.0)


## A wall fan's housing (motor and guard ring), facing +Z, centred.
static func fan_housing_mesh() -> ArrayMesh:
	var g := VoxelGrid.new(Vector3i(13, 13, 4), VS, Vector3.ZERO)
	for y in 13:
		for x in 13:
			var d := Vector2(x - 6, y - 6).length()
			if d > 5.4 and d < 6.5:
				g.set_v(x, y, 3, Vox.METAL, STEEL)
				g.set_v(x, y, 0, Vox.METAL, STEEL_DARK)
			if d < 1.6:
				g.set_v(x, y, 0, Vox.SOLID, VrStyle.INK)
				g.set_v(x, y, 1, Vox.SOLID, STEEL_DARK)
			if (x == 6 or y == 6) and d < 6.5 and d > 1.5:
				g.set_v(x, y, 3, Vox.METAL, STEEL.darkened(0.15))
	return mesh(g, Vector3(6.5, 6.5, 0) * VS)


## The fan's three blades (turned by the workshop), centred, in the z = 0 plane.
static func fan_blades_mesh() -> ArrayMesh:
	var g := VoxelGrid.new(Vector3i(11, 11, 1), VS, Vector3.ZERO)
	for y in 11:
		for x in 11:
			var p := Vector2(x - 5, y - 5)
			var d := p.length()
			if d < 1.2:
				g.set_v(x, y, 0, Vox.SOLID, VrStyle.RED)
				continue
			if d > 5.0:
				continue
			var a := fposmod(p.angle(), TAU / 3.0)
			if a < 0.75:
				g.set_v(x, y, 0, Vox.SOLID, VrStyle.PAPER.darkened(0.08))
	return mesh(g, Vector3(5.5, 5.5, 0.5) * VS, 0.0)


## The weapons rack's board: dark steel with a hazard border, a small shelf
## for the mines (2.5 x 1.75 units, face at z = 0, from x = 0).
static func rack_mesh() -> ArrayMesh:
	var g := VoxelGrid.new(Vector3i(20, 14, 5), VS, Vector3.ZERO)
	for y in 14:
		for x in 20:
			var c := STEEL_DARK.darkened(0.2)
			if x == 0 or x == 19 or y == 0 or y == 13:
				c = VrStyle.YELLOW if (x + y) % 4 < 2 else VrStyle.INK
			g.set_v(x, y, 0, Vox.SOLID, c)
	for y in [5, 8, 11]:
		for x in [3, 16]:
			g.set_v(x, y, 1, Vox.METAL, STEEL)
	g.box(Vector3i(1, 1, 1), Vector3i(18, 1, 4), Vox.SOLID, WOOD_DARK)
	return mesh(g)


# ------------------------------------------------------------ signs and posters

## A neon sign: [backing board, the first word (GLOW), the second word
## (GLOW), the frame tube (GLOW)]; the words are separate so one can flicker.
## Centred on x, bottom at y = 0, face towards +Z.
static func neon_meshes(first: String, second: String, letters: Color, frame: Color) -> Array:
	var vs := 0.08
	var w := text_width(first + " " + second) + 6
	var h := 11
	var board := VoxelGrid.new(Vector3i(w, h, 1), vs, Vector3.ZERO)
	board.box(Vector3i(0, 0, 0), Vector3i(w - 1, h - 1, 0), Vox.SOLID, Color("16182e"))
	var g1 := VoxelGrid.new(Vector3i(w, h, 1), vs, Vector3(0, 0, vs))
	draw_text(g1, first, 3, 7, 0, Vox.GLOW, letters)
	var g2 := VoxelGrid.new(Vector3i(w, h, 1), vs, Vector3(0, 0, vs))
	draw_text(g2, second, 3 + text_width(first + " ") + 1, 7, 0, Vox.GLOW, letters)
	var tube := VoxelGrid.new(Vector3i(w, h, 1), vs, Vector3(0, 0, vs))
	for x in range(1, w - 1):
		tube.set_v(x, 1, 0, Vox.GLOW, frame)
		tube.set_v(x, h - 2, 0, Vox.GLOW, frame)
	for y in range(1, h - 1):
		tube.set_v(1, y, 0, Vox.GLOW, frame)
		tube.set_v(w - 2, y, 0, Vox.GLOW, frame)
	var pivot := Vector3(w * 0.5, 0, 0) * vs
	return [mesh(board, pivot, 0.02), mesh(g1, pivot, 0.0), mesh(g2, pivot, 0.0), mesh(tube, pivot, 0.0)]


## The safety board: "DAYS WITHOUT AN EXPLOSION" and a big red counter at 0.
## Centred on x, bottom at y = 0, face towards +Z.
static func safety_sign_mesh() -> ArrayMesh:
	var l1 := "DAYS WITHOUT"
	var l2 := "AN EXPLOSION"
	var tw := maxi(text_width(l1), text_width(l2))
	var w := tw + 2 + 14
	var h := 16
	var vs := 0.05
	var g := VoxelGrid.new(Vector3i(w, h, 2), vs, Vector3.ZERO)
	for y in h:
		for x in w:
			var c := VrStyle.PAPER.darkened(0.06)
			if x == 0 or y == 0 or x == w - 1 or y == h - 1:
				c = VrStyle.INK
			elif y >= h - 3:
				c = VrStyle.YELLOW  # header band
			g.set_v(x, y, 0, Vox.SOLID, c)
	draw_text(g, l1, 2, h - 5, 1, Vox.SOLID, VrStyle.INK)
	draw_text(g, l2, 2, h - 11, 1, Vox.SOLID, VrStyle.INK)
	# the counter: a red box with a big white 0
	var bx := w - 13
	g.box(Vector3i(bx, 2, 1), Vector3i(bx + 10, h - 5, 1), Vox.SOLID, VrStyle.RED)
	draw_text(g, "0", bx + 2, h - 6, 1, Vox.SOLID, VrStyle.PAPER, 2)
	return mesh(g, Vector3(w * 0.5, 0, 0) * vs, 0.03)


## A framed racing poster (1.25 x 1.75 units + frame); kind 0 the sunset
## racer, 1 the champion's trophy, 2 BOOM. Centred on x, bottom at y = 0.
static func poster_mesh(kind: int) -> ArrayMesh:
	var w := 20
	var h := 28
	var g := VoxelGrid.new(Vector3i(w + 2, h + 2, 2), FINE, Vector3.ZERO)
	for y in h + 2:
		for x in w + 2:
			g.set_v(x, y, 0, Vox.SOLID, VrStyle.INK if kind != 1 else WOOD_DARK)
	for y in h:
		for x in w:
			g.set_v(x + 1, y + 1, 1, Vox.SOLID, _poster_pixel(kind, x, y, w, h))
	if kind == 2:
		draw_text(g, "BOOM", 1 + (w - text_width("BOOM")) / 2, h, 1, Vox.SOLID, VrStyle.PAPER)
	return mesh(g, Vector3((w + 2) * 0.5, 0, 0) * FINE, 0.03)


static func _poster_pixel(kind: int, x: int, y: int, w: int, h: int) -> Color:
	var t := float(y) / h
	match kind:
		0:  # sunset racer: a striped retro sun over a chequered road, a red car
			var c := Color("3b2d6b")
			if t < 0.78:
				c = VrStyle.PINK
			if t < 0.6:
				c = Color("ff8a4c")
			if t < 0.45:
				c = VrStyle.YELLOW
			var sun := Vector2(x + 0.5 - w * 0.5, y + 0.5 - 13.0).length()
			if sun < 6.2 and (y > 13 or y % 2 == 0):
				c = VrStyle.PAPER if y > 15 else Color("ffd27a")
			if y <= 8:
				c = VrStyle.INK
			if y == 7:
				c = VrStyle.PAPER if x % 2 == 0 else VrStyle.INK
			var car := [".....######.......", "...###########....", ".#################", "##################", "..##........##...."]
			var cy := 13 - y
			if cy >= 0 and cy < car.size():
				var row: String = car[cy]
				var cx := x - 1
				if cx >= 0 and cx < row.length() and row[cx] == "#":
					c = VrStyle.RED if cy < 4 else VrStyle.INK
					if cy == 0 or (cy == 1 and cx > 9 and cx < 13):
						c = Color(0.2, 0.25, 0.4)
			if y <= 2:
				c = VrStyle.RED
			return c
		1:  # champion: a gold trophy on teal rays, little stars
			var c := VrStyle.TEAL
			var a := Vector2(x + 0.5 - w * 0.5, y + 0.5 - 17.0).angle()
			if int(floor((a + PI) / (TAU / 12.0))) % 2 == 0:
				c = VrStyle.TEAL.lightened(0.15)
			var cx := absf(x + 0.5 - w * 0.5)
			if y >= 14 and y <= 22 and cx < 6.0 - (22 - y) * 0.35:
				c = VrStyle.YELLOW
			if y >= 17 and y <= 20 and cx >= 6.0 and cx < 7.6:
				c = VrStyle.YELLOW.darkened(0.15)  # handles
			if y >= 10 and y < 14 and cx < 1.2:
				c = VrStyle.YELLOW.darkened(0.2)
			if y >= 6 and y < 10 and cx < 4.5:
				c = WOOD_DARK
			if y >= 16 and y <= 20 and x == w / 2 and y != 16 or (y == 20 and x == w / 2 - 1):
				c = VrStyle.RED  # a "1" on the cup
			for s in [Vector2i(3, 24), Vector2i(16, 25), Vector2i(2, 12), Vector2i(17, 11)]:
				if (x == s.x and absi(y - s.y) <= 1) or (y == s.y and absi(x - s.x) <= 1):
					c = VrStyle.PAPER
			if y <= 3:
				c = VrStyle.INK
				if y >= 1 and y <= 2 and x >= 3 and x <= 16 and x % 2 == 1:
					c = VrStyle.YELLOW
			return c
		_:  # BOOM: a red burst on yellow with a missile
			var c := VrStyle.YELLOW
			var p := Vector2(x + 0.5 - w * 0.5, y + 0.5 - 15.0)
			var spikes := 0.75 + 0.25 * cos(p.angle() * 8.0)
			if p.length() < 9.0 * spikes:
				c = Color("ff8a4c")
			if p.length() < 6.5 * spikes:
				c = VrStyle.RED
			var mx := x - 3
			var my := y - 5
			if absi(mx - my) <= 1 and mx >= 0 and mx < 8:
				c = VrStyle.PAPER if mx < 6 else VrStyle.RED_DARK
			if y >= 23:
				c = VrStyle.INK
			return c

