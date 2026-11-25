class_name VoxelProps
extends RefCounted
## Converts HyperCars' top-down scenery artwork into voxel props.
##
## Each prop drawing is sampled into voxel columns (Vox.CELL_PX) and extruded
## with a profile that fits what it is: trees get a trunk and a rounded
## canopy, pines a cone, bushes and rocks low domes, flowers a petal layer,
## tyre stacks rings, grandstands stepped tiers, advertising boards and the
## pit building stand up with the drawing on their face, Tabletop Mayhem's
## giant pencils, cups and dice get their real shapes. Colours always come
## from the drawing, so every biome (and the user's own custom/ art) keeps
## its look. One mesh per logical asset, shared by every placement.

const VS := Vox.CELL_PX

enum Kind { DOME, TREE, PINE, BUSH, ROCK, FLOWERS, TYRES, FLAG, STAND, LAMP, FLOOD, BOARD, CRATE, PIT, FLAT, PENCIL, CUP, DICE, SLAB }

static var _meshes: Dictionary = {}


static func kind_of(logical: String) -> Kind:
	var l := logical.to_lower()
	if l.ends_with("tree_round") or l.ends_with("tree_bloom") or l == "variant_2/scenery/prop_1":
		return Kind.TREE
	if l == "variant_3/scenery/prop_1":
		return Kind.PINE
	if l.ends_with("bush") or l == "variant_2/scenery/prop_2" or l == "variant_3/scenery/prop_2":
		return Kind.BUSH
	if l.ends_with("rock") or l == "variant_2/scenery/prop_3" or l == "variant_3/scenery/prop_3":
		return Kind.ROCK
	if l.ends_with("flowers"):
		return Kind.FLOWERS
	if l.ends_with("tyre_stack"):
		return Kind.TYRES
	if l.ends_with("flag"):
		return Kind.FLAG
	if l.ends_with("grandstand"):
		return Kind.STAND
	if l.ends_with("lamp_post"):
		return Kind.LAMP
	if l == "variant_4/scenery/prop_1":
		return Kind.FLOOD
	if l == "variant_4/scenery/prop_2" or l.ends_with("pit_sign"):
		return Kind.BOARD
	if l == "variant_4/scenery/prop_3":
		return Kind.CRATE
	if l.ends_with("pit_building"):
		return Kind.PIT
	if l.ends_with("card"):
		return Kind.FLAT
	if l.ends_with("paperclip"):
		return Kind.FLAT
	if l.ends_with("pencil"):
		return Kind.PENCIL
	if l == "variant_5/scenery/prop_1":
		return Kind.CUP
	if l == "variant_5/scenery/prop_2":
		return Kind.DICE
	if l == "variant_5/scenery/prop_3":
		return Kind.SLAB
	return Kind.DOME


## Props that sway in the wind (canopies, flags).
static func sways(kind: Kind) -> bool:
	return kind == Kind.TREE or kind == Kind.PINE or kind == Kind.FLAG


## The voxel mesh for a prop drawing shown at `display` px (frame 0 of a sheet).
static func mesh_for(logical: String, tex: Texture2D, display: Vector2, hframes: int = 1) -> ArrayMesh:
	var key := "%s|%d|%d|%d" % [logical, tex.get_instance_id() if tex != null else 0, int(display.x), int(display.y)]
	if _meshes.has(key):
		return _meshes[key]
	var mesh := _build(kind_of(logical), tex, display, hframes)
	_meshes[key] = mesh
	return mesh


static func _build(kind: Kind, tex: Texture2D, display: Vector2, hframes: int) -> ArrayMesh:
	var img := Vox.rgba(tex)
	var region := Rect2i(0, 0, 1, 1)
	if img != null:
		region = Rect2i(0, 0, img.get_width() / maxi(1, hframes), img.get_height())
	var nxc := maxi(1, int(round(display.x / VS)))
	var nzc := maxi(1, int(round(display.y / VS)))
	match kind:
		Kind.BOARD, Kind.PIT:
			return _standing(kind, img, region, nxc, nzc, display)
		Kind.FLAG:
			return _flag(img, region)
		Kind.LAMP, Kind.FLOOD:
			return lamp_mesh(kind == Kind.FLOOD)
	var s := _sample(img, region, nxc, nzc)
	var occ: PackedByteArray = s[0]
	var cols: Array = s[1]
	var maxh := 40
	var g := VoxelGrid.new(Vector3i(nxc, maxh, nzc), VS * Vox.PX, Vector3.ZERO)
	var diam := float(mini(nxc, nzc))
	var top_y := 0
	for z in nzc:
		for x in nxc:
			var i := z * nxc + x
			if occ[i] == 0:
				continue
			var c: Color = cols[i]
			var u := (x + 0.5) / nxc * 2.0 - 1.0
			var v := (z + 0.5) / nzc * 2.0 - 1.0
			var r := clampf(sqrt(u * u + v * v), 0.0, 1.0)
			var dome := sqrt(maxf(0.0, 1.0 - r * r))
			var nse := Vox.hash3(x, 7, z)
			var y0 := 0
			var y1 := 1
			match kind:
				Kind.TREE:
					var ch := diam * 0.34
					var mid := 4.0 + ch * 0.42
					y0 = int(round(mid - ch * 0.45 * dome - 0.5))
					y1 = int(round(mid + ch * 0.58 * dome * (0.88 + 0.24 * nse))) + 1
				Kind.PINE:
					y0 = 3 + int(r * 3.0)
					y1 = 3 + int(round(minf(diam * 0.62, 20.0) * (1.0 - r) + 1.0 + nse))
				Kind.BUSH:
					y1 = 1 + int(round(diam * 0.24 * dome * (0.85 + 0.3 * nse)))
				Kind.ROCK:
					y1 = 1 + int(round(diam * 0.3 * dome * (0.7 + 0.5 * Vox.hash3(x / 3, 1, z / 3))))
				Kind.FLOWERS:
					y1 = 1 + (1 if (c.s > 0.35 and c.v > 0.55) else 0)
				Kind.TYRES:
					y1 = 6
					if r < 0.42:  # the hollow middle of the stack
						y1 = 1
						c = Color(0.1, 0.09, 0.09)
				Kind.STAND:
					var back := 1.0 - (z + 0.5) / nzc  # image top = back of the stand
					y1 = 2 + int(floor(back * 5.0)) * 3
				Kind.CRATE:
					y1 = int(round(diam * 0.7))
				Kind.FLAT:
					y1 = 1
				Kind.SLAB:
					y1 = 2
				Kind.PENCIL:
					var vv := (z + 0.5) / nzc * 2.0 - 1.0
					y1 = 1 + int(round(nzc * 0.5 * sqrt(maxf(0.0, 1.0 - vv * vv)) * 1.6))
				Kind.CUP:
					y1 = int(round(diam * 0.42))
					if c.v < 0.35:
						y1 = int(round(diam * 0.32))  # the coffee, inside the rim
				Kind.DICE:
					y1 = int(round(diam * 0.86))
				_:
					y1 = 1 + int(round(diam * 0.3 * dome))
			y1 = clampi(y1, y0 + 1, maxh - 1)
			top_y = maxi(top_y, y1)
			for y in range(y0, y1):
				var k := 0.78 + 0.22 * float(y - y0) / maxf(1.0, float(y1 - y0 - 1))
				var vc := c if y == y1 - 1 else Color(c.r * k, c.g * k, c.b * k)
				if kind == Kind.TYRES:
					vc = Color(0.13, 0.12, 0.13).lerp(c, 0.35) if y % 2 == 0 else Color(0.06, 0.06, 0.07)
					if y == y1 - 1 and r >= 0.42:
						vc = vc.lightened(0.18)
				if kind == Kind.STAND and y < y1 - 1:
					vc = Color(0.55, 0.54, 0.56).darkened(0.1 * (y % 3))
				g.set_v(x, y, z, Vox.METAL if kind == Kind.FLAT and c.s < 0.1 and c.v > 0.6 else Vox.SOLID, vc)
	if kind == Kind.TREE or kind == Kind.PINE:  # the trunk
		var cx := nxc / 2
		var cz := nzc / 2
		var th := 6 if kind == Kind.TREE else 4
		for y in th:
			for dz in [-1, 0]:
				for dx in [-1, 0]:
					g.set_v(cx + dx, y, cz + dz, Vox.SOLID, Color(0.36, 0.25, 0.16).darkened(0.1 * ((y + dx) % 2)))
	if kind == Kind.STAND:  # back wall and roof posts
		for x in nxc:
			for y in range(0, 20):
				if y >= 17 or x % 12 == 0:
					g.set_v(x, y, 0, Vox.SOLID, Color(0.86, 0.84, 0.8) if y < 17 else Color(0.78, 0.2, 0.16))
	var pivot := Vector3(nxc * 0.5, 0.0, nzc * 0.5) * VS * Vox.PX
	return VoxelMesher.build_mesh(g, VoxelCars.material(), pivot, 0.07)


## Mean colour and coverage of the drawing per voxel column.
static func _sample(img: Image, region: Rect2i, nxc: int, nzc: int) -> Array:
	var occ := PackedByteArray()
	occ.resize(nxc * nzc)
	var cols := []
	cols.resize(nxc * nzc)
	if img == null:
		occ.fill(1)
		cols.fill(Color(0.5, 0.6, 0.4))
		return [occ, cols]
	var fx := float(region.size.x) / nxc
	var fz := float(region.size.y) / nzc
	for z in nzc:
		for x in nxc:
			var cnt := 0
			var tot := 0
			var sum := Vector3.ZERO
			var y0 := region.position.y + int(z * fz)
			var y1 := maxi(y0 + 1, region.position.y + int((z + 1) * fz))
			var x0 := region.position.x + int(x * fx)
			var x1 := maxi(x0 + 1, region.position.x + int((x + 1) * fx))
			for py in range(y0, y1):
				for px in range(x0, x1):
					var p := img.get_pixel(px, py)
					tot += 1
					if p.a > 0.5:
						cnt += 1
						sum += Vector3(p.r, p.g, p.b)
			if tot > 0 and cnt * 2 >= tot:
				occ[z * nxc + x] = 1
				var m := sum / cnt
				cols[z * nxc + x] = Color(m.x, m.y, m.z)
	return [occ, cols]


## Boards and the pit building stand up, the drawing on the face that looks
## at the road (the sprite's +Y side), on legs / as a building with a roof.
static func _standing(kind: Kind, img: Image, region: Rect2i, nxc: int, nzc: int, display: Vector2) -> ArrayMesh:
	var face_h := nzc
	var depth := 2
	var legs := 3
	if kind == Kind.PIT:
		face_h = int(round(nzc * 0.6))
		depth = 16
		legs = 0
	var s := _sample(img, region, nxc, face_h)
	var occ: PackedByteArray = s[0]
	var cols: Array = s[1]
	var g := VoxelGrid.new(Vector3i(nxc, face_h + legs + 3, depth), VS * Vox.PX, Vector3.ZERO)
	var back := Color(0.62, 0.62, 0.66)
	for row in face_h:
		var y := legs + face_h - 1 - row
		for x in nxc:
			var i := row * nxc + x
			if occ[i] == 0:
				continue
			for z in depth:
				var c: Color = cols[i] if z == depth - 1 else back
				if kind == Kind.PIT and z < depth - 1:
					c = Color(0.74, 0.74, 0.76) if y < face_h + legs - 1 else Color(0.5, 0.52, 0.56)
				g.set_v(x, y, z, Vox.SOLID, c)
	if kind == Kind.PIT:  # roof edge
		for x in nxc:
			for z in depth:
				g.set_v(x, face_h, z, Vox.SOLID, Color(0.86, 0.2, 0.16) if (x / 4) % 2 == 0 else Color(0.95, 0.95, 0.95))
	for lx in [1, nxc - 2]:
		for y in legs:
			g.set_v(lx, y, 0, Vox.METAL, Color(0.55, 0.55, 0.58))
	var pivot := Vector3(nxc * 0.5, 0.0, depth * 0.5) * VS * Vox.PX
	return VoxelMesher.build_mesh(g, VoxelCars.material(), pivot, 0.03)


## A flag on a pole: the cloth uses the flag drawing's first frame.
static func _flag(img: Image, region: Rect2i) -> ArrayMesh:
	var w := 9
	var h := 6
	var pole := 15
	var s := _sample(img, region, w, h)
	var occ: PackedByteArray = s[0]
	var cols: Array = s[1]
	var g := VoxelGrid.new(Vector3i(w + 1, pole + 1, 1), VS * Vox.PX, Vector3.ZERO)
	for y in pole + 1:
		g.set_v(0, y, 0, Vox.METAL, Color(0.85, 0.85, 0.86))
	for row in h:
		for x in w:
			var c: Color = cols[row * w + x] if occ[row * w + x] == 1 else Color(0.9, 0.25, 0.2)
			g.set_v(x + 1, pole - row, 0, Vox.SOLID, c)
	return VoxelMesher.build_mesh(g, VoxelCars.material(), Vector3(0.5, 0.0, 0.5) * VS * Vox.PX, 0.02)


static var _lamp: ArrayMesh
static var _flood: ArrayMesh


## Trackside lamp (pole, arm along +X, glowing head) or a floodlight tower.
## The head's centre is at lamp_head(flood).
static func lamp_mesh(flood: bool = false) -> ArrayMesh:
	if flood and _flood != null:
		return _flood
	if not flood and _lamp != null:
		return _lamp
	var pole := 22 if flood else 15
	var g := VoxelGrid.new(Vector3i(9, pole + 5, 7), VS * Vox.PX, Vector3.ZERO)
	var metal := Color(0.36, 0.37, 0.4)
	for y in pole:
		for dz in [3]:
			g.set_v(1, y, dz, Vox.METAL, metal)
			if y < 2:
				g.box(Vector3i(0, 0, 2), Vector3i(2, 1, 4), Vox.METAL, metal.darkened(0.2))
	if flood:
		g.box(Vector3i(0, pole, 0), Vector3i(4, pole + 3, 6), Vox.METAL, Color(0.2, 0.2, 0.22))
		for z in [1, 3, 5]:
			for y in [pole + 1, pole + 2]:
				g.set_v(4, y, z, Vox.GLOW, Color(1.0, 0.95, 0.8))
	else:
		for x in range(1, 6):
			g.set_v(x, pole, 3, Vox.METAL, metal)
		g.box(Vector3i(4, pole - 1, 2), Vector3i(7, pole, 4), Vox.METAL, Color(0.24, 0.24, 0.26))
		for x in range(4, 8):
			for z in range(2, 5):
				g.set_v(x, pole - 2, z, Vox.GLOW, Color(1.0, 0.92, 0.7))
	var mesh := VoxelMesher.build_mesh(g, VoxelCars.material(), Vector3(1.5, 0.0, 3.5) * VS * Vox.PX, 0.02)
	if flood:
		_flood = mesh
	else:
		_lamp = mesh
	return mesh


## Where a lamp's light sits relative to its base (px; x along the arm, height).
static func lamp_head(flood: bool) -> Vector2:
	return Vector2(4.0 * VS, 23.0 * VS) if flood else Vector2(4.5 * VS, 12.5 * VS)
