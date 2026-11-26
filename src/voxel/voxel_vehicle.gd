class_name VoxelVehicle
extends RefCounted
## VoxelRacing P006 "Built to Break": the racing cars as layered voxel
## vehicles, each driver's own real-world-inspired design (no logos, no
## branding), built in code at a finer vehicle voxel (VS_PX = 4/3 display px,
## 1.5x the old car voxel): 48 x 27 voxels on the 64 x 36 px game footprint
## (the race's collision footprint is unchanged).
##
## Every voxel belongs to a component:
##   * CORE  - the crash cell (floor pan, bulkheads, pillars and roof rails,
##             seats, dash, suspension). Never comes off; after an explosion
##             it stays as the charred wreck. Component id 0.
##   * INNER - engine, radiator, exhaust, fuel tank... visible once the
##             bodywork over them is gone; some break away under heavy damage.
##   * OUTER - bumpers, grille, bonnet, boot lid, roof, glass, fenders, doors,
##             skirts, lamps, mirrors, spoilers and wings: multi-voxel panels
##             that break away whole.
## One mesh per design holds every component; faces between components are
## kept, so the shader can hide a component (instance mask, no re-meshing)
## and what was under it shows. A detached component flies off as its own
## mesh (part_mesh) with its own colours. Presentation only.

const VS_PX := 4.0 / 3.0
const NX := 48
const NY := 20
const NZ := 27
const ZC := 13
## Wheels: radius / centre height in vehicle voxels (7 display px: Cartoon
## Motorsport's bigger wheels) and tyre width.
const WHEEL_R := 5.25
const WHEEL_Y := 5.25
const WHEEL_W := 4

const CORE := 0
const INNER := 1
const OUTER := 2

## Which design each packaged body is (driver identity: see README).
const DESIGNS := {
	"cars/body_player": "gt", "cars/body_player_2": "gt2", "cars/body_junker": "wagon",
	"cars/body_ai_1": "sedan", "cars/body_ai_2": "muscle", "cars/body_ai_3": "roadster",
	"cars/body_ai_4": "pony", "cars/body_ai_5": "coupe", "cars/body_ai_6": "exotic",
	"cars/body_ai_7": "formula", "cars/body_ai_8": "rally", "cars/body_ai_9": "supercar",
}
const FALLBACK := ["sedan", "coupe", "gt", "pony", "rally", "supercar"]

## Component properties by name (the part before "_L" / "_R" etc.):
## [layer, toughness, detaches, goes in an explosion].
const KINDS := {
	"cell": [CORE, 99.0, false, false],
	"engine": [INNER, 99.0, false, false],
	"radiator": [INNER, 1.5, true, true], "exhaust": [INNER, 2.0, true, true],
	"tank": [INNER, 2.2, true, true], "battery": [INNER, 1.3, true, true],
	"bumper": [OUTER, 0.8, true, true], "grille": [OUTER, 0.75, true, true],
	"hood": [OUTER, 1.3, true, true], "trunk": [OUTER, 1.3, true, true],
	"roof": [OUTER, 2.1, true, true], "windscreen": [OUTER, 0.95, true, true],
	"backlight": [OUTER, 0.95, true, true], "fender": [OUTER, 1.1, true, true],
	"quarter": [OUTER, 1.25, true, true], "door": [OUTER, 1.55, true, true],
	"skirt": [OUTER, 0.8, true, true], "panel": [OUTER, 1.0, true, true],
	"head": [OUTER, 0.6, true, true], "tail": [OUTER, 0.6, true, true],
	"wing": [OUTER, 0.9, true, true], "mirror": [OUTER, 0.35, true, true],
	"scoop": [OUTER, 0.7, true, true], "pod": [OUTER, 0.6, true, true],
	"flap": [OUTER, 0.45, true, true], "rack": [OUTER, 0.7, true, true],
	"nose": [OUTER, 1.0, true, true], "sidepod": [OUTER, 1.2, true, true],
	"cover": [OUTER, 1.2, true, true], "airbox": [OUTER, 1.1, true, true],
}

const GLASS := Color(0.15, 0.21, 0.29)
const TRIM := Color(0.07, 0.07, 0.08)
const CHROME := Color(0.78, 0.79, 0.8)
const CHASSIS := Color(0.16, 0.15, 0.16)
const STEEL := Color(0.36, 0.37, 0.4)
const LENS := Color(1.0, 0.94, 0.7)
const RED_LENS := Color(0.8, 0.07, 0.05)

static var _models: Dictionary = {}
static var _wheel: ArrayMesh


static func vs() -> float:
	return VS_PX * Vox.PX


## Model-space offset of a vehicle grid (centred, standing on y = 0): the
## same as the old cars' (64 x 36 display px).
static func pivot() -> Vector3:
	return Vector3(NX, 0.0, NZ) * 0.5 * vs()


## A built vehicle: its voxels, components, shared mesh and where its lamps,
## exhausts, wheels and driver are.
class Model extends RefCounted:
	var design := ""
	var grid: VoxelGrid
	var tags := PackedByteArray()  ## component id per grid cell (grid indexing)
	var parts: Array[Dictionary] = []
	var keep := PackedByteArray()
	var mesh: ArrayMesh
	## Wheel centres (display px): front axle x, rear axle x, half track.
	var wheels := Vector3(16.5, -16.5, 10.5)
	## Tyre width scale, front / rear.
	var tyre := Vector2(1.0, 1.0)
	var head_lamps: Array[Vector3] = []
	var tail_lamps: Array[Vector3] = []
	var exhausts: Array[Vector3] = []
	## The driver's place (head pose of the overtaking taunt).
	var cabin := AABB(Vector3(-0.3, 0.0, -0.6), Vector3(0.8, 1.0, 1.2))
	var roof_top := 1.0
	var roof_x := 0.0
	var nose_x := 2.0
	var tail_x := -2.0
	var floor_y := 0.17

	func id_of(part_name: String) -> int:
		for k in parts.size():
			if parts[k].name == part_name:
				return k
		return -1


## The vehicle for a body drawing (cached). The packaged bodies are their
## drivers' designs; any other drawing (the user's own art) gets a design and
## its main paint from the drawing.
static func model_for(tex: Texture2D, body_logical: String = "") -> Model:
	var logical := body_logical
	if not DESIGNS.has(logical) and logical.begins_with("cars/car_"):
		logical = logical.replace("cars/car_", "cars/body_")
	var design := String(DESIGNS.get(logical, ""))
	var paint := Color(0, 0, 0, 0)
	var packaged := tex != null and tex.resource_path.begins_with("res://assets/graphics/cars/template_body")
	if design.is_empty():
		design = FALLBACK[absi(hash(logical)) % FALLBACK.size()]
	if tex != null and not packaged:
		paint = _dominant(tex)
	var key := design + ("|" + paint.to_html(false) if paint.a > 0.0 else "")
	if _models.has(key):
		return _models[key]
	var m := _build(design, paint)
	_models[key] = m
	return m


## Wheel centres (display px) of a body: the design's own, unless the wheel
## layout sets this body's wheels.
static func wheels_for(layout: WheelLayout, tex: Texture2D, body_logical: String) -> Vector3:
	if layout != null and layout.per_car.has(body_logical):
		return layout.per_car[body_logical]
	return model_for(tex, body_logical).wheels


## The most common strong colour of a drawing (the user's own art).
static func _dominant(tex: Texture2D) -> Color:
	var img := Vox.rgba(tex)
	if img == null:
		return Color(0.6, 0.6, 0.62)
	var counts := {}
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var p := img.get_pixel(x, y)
			if p.a < 0.7 or p.get_luminance() < 0.18:
				continue
			var k := Vector3i(int(p.r * 8.0), int(p.g * 8.0), int(p.b * 8.0))
			counts[k] = int(counts.get(k, 0)) + 1
	var best := Vector3i(5, 5, 5)
	var n := 0
	for k in counts:
		if counts[k] > n:
			n = counts[k]
			best = k
	return Color((best.x + 0.5) / 8.0, (best.y + 0.5) / 8.0, (best.z + 0.5) / 8.0)


## A detached component as its own mesh, centred on its centre (cached).
static func part_mesh(m: Model, id: int) -> ArrayMesh:
	var p: Dictionary = m.parts[id]
	if p.get("mesh") != null:
		return p.mesh
	var lo: Vector3i = p.lo
	var hi: Vector3i = p.hi
	var g := VoxelGrid.new(hi - lo + Vector3i.ONE, vs(), Vector3.ZERO)
	var src := m.grid
	for y in range(lo.y, hi.y + 1):
		for z in range(lo.z, hi.z + 1):
			for x in range(lo.x, hi.x + 1):
				var i := ((y + 1) * src.sz + z + 1) * src.sx + x + 1
				if m.tags[i] == id and src.mat[i] != Vox.AIR:
					g.set_v(x - lo.x, y - lo.y, z - lo.z, src.mat[i], src.get_c(x, y, z))
	var corner := Vector3(lo) * vs() - pivot()
	var mesh := VoxelMesher.build_mesh(g, VoxelCars.material(), (p.centre as Vector3) - corner, 0.05)
	p.mesh = mesh
	return mesh


## One finer voxel wheel (axle along Z, centred): tyre with a chunky tread that
## shows the wheel turning, a rim (tinted per driver) and a hub.
static func wheel_mesh() -> ArrayMesh:
	if _wheel != null:
		return _wheel
	var d := 11
	var g := VoxelGrid.new(Vector3i(d, d, WHEEL_W), vs(), Vector3.ZERO)
	for y in d:
		for x in d:
			var p := Vector2(x + 0.5 - d * 0.5, y + 0.5 - d * 0.5)
			var r := p.length()
			if r > WHEEL_R + 0.2:
				continue
			for z in WHEEL_W:
				var outer := z == 0 or z == WHEEL_W - 1
				if r < 3.2:
					# a big toy-car rim: five spokes, a dark hub
					var spoke := int(floor((p.angle() + PI) / (TAU / 10.0))) % 2 == 0
					var c := Color(0.85, 0.83, 0.78)
					if r < 1.1:
						c = Color(0.42, 0.41, 0.4)
					elif r > 2.6:
						c = Color(0.7, 0.69, 0.66)
					elif not spoke and outer:
						c = Color(0.24, 0.23, 0.23)
					g.set_v(x, y, z, Vox.METAL, c if outer else Color(0.34, 0.33, 0.33))
				else:
					var sector := int(floor((p.angle() + PI) / (TAU / 16.0))) % 2
					var c := Color(0.16, 0.15, 0.16) if sector == 0 else Color(0.08, 0.08, 0.09)
					if r < 4.1:
						c = Color(0.21, 0.2, 0.21)
					g.set_v(x, y, z, Vox.SOLID, c)
	_wheel = VoxelMesher.build_mesh(g, VoxelCars.material(), Vector3(d, d, WHEEL_W) * 0.5 * vs(), 0.0)
	return _wheel


# ============================================================ building

## The builder: a grid, a component tag per cell and the components.
class B extends RefCounted:
	var m: Model
	var g: VoxelGrid
	var x0 := 1
	var L := 46
	var fa := 36.5
	var ra := 9.0
	var track := 9.0
	var paint := Color.WHITE

	func _init(model: Model) -> void:
		m = model
		g = VoxelGrid.new(Vector3i(NX, NY, NZ), VoxelVehicle.vs(), Vector3.ZERO)
		m.grid = g
		m.tags.resize(g.mat.size())
		part("cell")

	## The id of a component (created on first use).
	func part(part_name: String) -> int:
		var k := m.id_of(part_name)
		if k >= 0:
			return k
		var kind := part_name.split("_")[0]
		var props: Array = VoxelVehicle.KINDS.get(kind, [VoxelVehicle.OUTER, 1.0, true, true])
		var lamp := -1
		if part_name == "head_L":
			lamp = 0
		elif part_name == "head_R":
			lamp = 1
		elif part_name == "tail_L":
			lamp = 2
		elif part_name == "tail_R":
			lamp = 3
		m.parts.append({"name": part_name, "layer": props[0], "tough": props[1], "detach": props[2], "blast": props[3],
			"lamp": lamp, "n": 0, "centre": Vector3.ZERO, "lo": Vector3i.ZERO, "hi": Vector3i.ZERO, "colour": Color.WHITE, "mesh": null})
		return m.parts.size() - 1

	func idx(x: int, y: int, z: int) -> int:
		return ((y + 1) * g.sz + z + 1) * g.sx + x + 1

	func put(x: int, y: int, z: int, mat: int, c: Color, part_name: String) -> void:
		if x < 0 or y < 0 or z < 0 or x >= NX or y >= NY or z >= NZ:
			return
		g.set_v(x, y, z, mat, c)
		m.tags[idx(x, y, z)] = part(part_name)

	func clear(x: int, y: int, z: int) -> void:
		if x < 0 or y < 0 or z < 0 or x >= NX or y >= NY or z >= NZ:
			return
		g.set_v(x, y, z, Vox.AIR, Color.BLACK)
		m.tags[idx(x, y, z)] = 0

	func has(x: int, y: int, z: int) -> bool:
		return g.get_m(x, y, z) != Vox.AIR

	func tag_at(x: int, y: int, z: int) -> String:
		if x < 0 or y < 0 or z < 0 or x >= NX or y >= NY or z >= NZ:
			return ""
		return m.parts[m.tags[idx(x, y, z)]].name

	## Car-relative box: u along the car from its tail, zc from the centre line
	## (both sides when `sym`; then names ending in "_S" get _L / _R).
	func box(u0: int, u1: int, y0: int, y1: int, zc0: int, zc1: int, mat: int, c: Color, part_name: String, sym := false) -> void:
		for side in ([-1, 1] if sym else [1]):
			var pn := part_name
			if pn.ends_with("_S"):
				pn = pn.left(pn.length() - 1) + ("L" if side < 0 else "R")
			for u in range(u0, u1 + 1):
				for y in range(y0, y1 + 1):
					for zc in range(zc0, zc1 + 1):
						put(x0 + u, y, ZC + zc * side, mat, c, pn)

	## Recolours the voxels of a box that are already there (keeps material and
	## component unless given).
	func paint_box(u0: int, u1: int, y0: int, y1: int, zc0: int, zc1: int, c: Color, sym := false, only_part := "") -> void:
		for side in ([-1, 1] if sym else [1]):
			for u in range(u0, u1 + 1):
				for y in range(y0, y1 + 1):
					for zc in range(zc0, zc1 + 1):
						var x: int = x0 + u
						var z: int = ZC + zc * side
						if not has(x, y, z):
							continue
						if not only_part.is_empty() and not tag_at(x, y, z).begins_with(only_part):
							continue
						g.set_v(x, y, z, g.get_m(x, y, z), c)

	## Lamps on the face of the body: for each (y, zc) the front-most (or
	## rear-most) voxel and `depth` behind it become lamp voxels of the
	## lamp component on that side.
	func lamp_face(front: bool, y0: int, y1: int, zc0: int, zc1: int, depth := 1, col := Color(0, 0, 0, 0)) -> void:
		var mat := Vox.HEAD if front else Vox.TAIL
		var c := col if col.a > 0.0 else (VoxelVehicle.LENS if front else VoxelVehicle.RED_LENS)
		for side in [-1, 1]:
			var pn := ("head_" if front else "tail_") + ("L" if side < 0 else "R")
			for y in range(y0, y1 + 1):
				for zc in range(zc0, zc1 + 1):
					var z: int = ZC + zc * side
					var xs: Array = range(NX - 1, -1, -1) if front else range(NX)
					for x in xs:
						if has(x, y, z):
							for k in depth:
								var xx: int = x - k if front else x + k
								if has(xx, y, z) or k == 0:
									put(xx, y, z, mat, c, pn)
							break

	## A face feature (grille, intake): recolours the front-most / rear-most
	## voxels and moves them to a component.
	func face(front: bool, y0: int, y1: int, zc0: int, zc1: int, c: Color, part_name: String, mat := Vox.SOLID, sym := true) -> void:
		for side in ([-1, 1] if sym else [1]):
			var pn := part_name
			if pn.ends_with("_S"):
				pn = pn.left(pn.length() - 1) + ("L" if side < 0 else "R")
			for y in range(y0, y1 + 1):
				for zc in range(zc0, zc1 + 1):
					var z: int = ZC + zc * side
					var xs: Array = range(NX - 1, -1, -1) if front else range(NX)
					for x in xs:
						if has(x, y, z):
							put(x, y, z, mat, c, pn)
							break

	## Recolours top-facing exterior voxels in a lateral band (stripes).
	func stripe_top(zc0: int, zc1: int, c: Color, u0 := 0, u1 := 99) -> void:
		for u in range(maxi(u0, 0), mini(u1, L - 1) + 1):
			var x: int = x0 + u
			for side in [-1, 1]:
				for zc in range(zc0, zc1 + 1):
					var z: int = ZC + zc * side
					for y in range(NY - 1, -1, -1):
						if has(x, y, z):
							var t := tag_at(x, y, z)
							var mt := g.get_m(x, y, z)
							if mt == Vox.SOLID and t != "cell" and not t.begins_with("wing") and m.parts[m.tags[idx(x, y, z)]].layer == VoxelVehicle.OUTER:
								g.set_v(x, y, z, mt, c)
							break

	## Recolours side-facing exterior voxels between heights (side stripes);
	## `fn` (optional) picks the voxels: fn(u, y) -> bool.
	func stripe_side(y0: int, y1: int, c: Color, u0 := 0, u1 := 99, fn := Callable()) -> void:
		for u in range(maxi(u0, 0), mini(u1, L - 1) + 1):
			var x: int = x0 + u
			for y in range(y0, y1 + 1):
				if fn.is_valid() and not bool(fn.call(u, y)):
					continue
				for side in [-1, 1]:
					for k in ZC + 1:
						var z: int = ZC + (ZC - k) * side
						if has(x, y, z):
							var mt := g.get_m(x, y, z)
							if mt == Vox.SOLID and m.parts[m.tags[idx(x, y, z)]].layer == VoxelVehicle.OUTER:
								g.set_v(x, y, z, mt, c)
							break


## Piecewise linear profile: pts = [[u, value], ...] (sorted by u).
static func _pl(pts: Array, u: float) -> float:
	if pts.is_empty():
		return 0.0
	if u <= float(pts[0][0]):
		return float(pts[0][1])
	for k in range(1, pts.size()):
		var a: Array = pts[k - 1]
		var b: Array = pts[k]
		if u <= float(b[0]):
			var t := (u - float(a[0])) / maxf(0.001, float(b[0]) - float(a[0]))
			return lerpf(float(a[1]), float(b[1]), t)
	return float(pts[pts.size() - 1][1])


static func _build(design: String, custom_paint: Color) -> Model:
	var m := Model.new()
	m.design = design
	var b := B.new(m)
	match design:
		"muscle":
			_muscle(b, custom_paint)
		"sedan":
			_sedan(b, custom_paint)
		"roadster":
			_roadster(b, custom_paint)
		"pony":
			_pony(b, custom_paint)
		"coupe":
			_coupe(b, custom_paint)
		"exotic":
			_exotic(b, custom_paint)
		"supercar":
			_supercar(b, custom_paint)
		"formula":
			_formula(b, custom_paint)
		"rally":
			_rally(b, custom_paint)
		"wagon":
			_wagon(b, custom_paint)
		"gt2":
			_gt(b, custom_paint if custom_paint.a > 0.0 else Color(0.1, 0.2, 0.66), Color(0.78, 0.85, 1.0))
		_:
			_gt(b, custom_paint if custom_paint.a > 0.0 else Color(0.68, 0.19, 0.09), Color(0.96, 0.89, 0.72))
	_finish(b)
	return m


## Measures the components (size, centre, colour, bounds), the lamp and wheel
## positions, and meshes the whole vehicle.
static func _finish(b: B) -> void:
	var m := b.m
	var g := b.g
	var n := m.parts.size()
	var sums: Array[Vector3] = []
	var lo: Array[Vector3i] = []
	var hi: Array[Vector3i] = []
	var cols: Array[Vector3] = []
	sums.resize(n)
	lo.resize(n)
	hi.resize(n)
	cols.resize(n)
	var cnt := PackedInt32Array()
	cnt.resize(n)
	for k in n:
		sums[k] = Vector3.ZERO
		lo[k] = Vector3i(999, 999, 999)
		hi[k] = Vector3i(-1, -1, -1)
		cols[k] = Vector3.ZERO
	var top_y := 0
	var nose := 0
	var tail := NX
	for y in NY:
		for z in NZ:
			for x in NX:
				var i := b.idx(x, y, z)
				if g.mat[i] == Vox.AIR:
					m.tags[i] = 0
					continue
				var k := m.tags[i]
				cnt[k] += 1
				sums[k] += Vector3(x, y, z) + Vector3.ONE * 0.5
				lo[k] = Vector3i(mini(lo[k].x, x), mini(lo[k].y, y), mini(lo[k].z, z))
				hi[k] = Vector3i(maxi(hi[k].x, x), maxi(hi[k].y, y), maxi(hi[k].z, z))
				var c := g.get_c(x, y, z)
				cols[k] += Vector3(c.r, c.g, c.b)
				top_y = maxi(top_y, y)
				nose = maxi(nose, x)
				tail = mini(tail, x)
	var v := vs()
	var piv := pivot()
	for k in n:
		var p: Dictionary = m.parts[k]
		p.n = cnt[k]
		if cnt[k] == 0:
			p.detach = false
			p.blast = false
			continue
		p.centre = sums[k] / cnt[k] * v - piv
		p.lo = lo[k]
		p.hi = hi[k]
		var cc: Vector3 = cols[k] / cnt[k]
		p.colour = Color(cc.x, cc.y, cc.z)
	# what each fitting is mounted on: an outer component touching nothing
	# but other bodywork goes with the bigger panel it touches most (lamps
	# with their bumper, a mirror with its door, a scoop with its bonnet)
	var touch := []
	for k in n:
		touch.append({})
	for y in NY:
		for z in NZ:
			for x in NX:
				var i := b.idx(x, y, z)
				if g.mat[i] == Vox.AIR:
					continue
				var k := m.tags[i]
				for o in [1, g.sx, g.sx * g.sz]:
					var j: int = i + o
					if g.mat[j] == Vox.AIR or m.tags[j] == k:
						continue
					var k2 := m.tags[j]
					touch[k][k2] = int(touch[k].get(k2, 0)) + 1
					touch[k2][k] = int(touch[k2].get(k, 0)) + 1
	for k in range(1, n):
		var p: Dictionary = m.parts[k]
		p.on = -1
		if int(p.layer) != OUTER or int(p.n) == 0:
			continue
		var best := -1
		var best_n := 0
		var grounded := false
		for k2 in touch[k]:
			var q: Dictionary = m.parts[k2]
			if int(q.layer) != OUTER:
				grounded = true
				break
			if int(q.n) > int(p.n) and int(touch[k][k2]) > best_n:
				best_n = touch[k][k2]
				best = k2
		if not grounded and best >= 0:
			p.on = best
	m.keep.resize(256)
	for k in n:
		var p: Dictionary = m.parts[k]
		m.keep[k] = 1 if (not p.detach and not p.blast) else 0
	m.nose_x = (nose + 1) * v - piv.x
	m.tail_x = tail * v - piv.x
	m.head_lamps.clear()
	m.tail_lamps.clear()
	for pn in ["head_L", "head_R"]:
		var k := m.id_of(pn)
		m.head_lamps.append(m.parts[k].centre if k >= 0 and int(m.parts[k].n) > 0 else Vector3(m.nose_x, 0.5, 0.4 * (-1.0 if pn.ends_with("L") else 1.0)))
	for pn in ["tail_L", "tail_R"]:
		var k := m.id_of(pn)
		m.tail_lamps.append(m.parts[k].centre if k >= 0 and int(m.parts[k].n) > 0 else Vector3(m.tail_x, 0.5, 0.4 * (-1.0 if pn.ends_with("L") else 1.0)))
	m.wheels = Vector3((b.x0 + b.fa) * VS_PX - NX * VS_PX * 0.5, (b.x0 + b.ra) * VS_PX - NX * VS_PX * 0.5, b.track * VS_PX)
	m.mesh = VoxelMesher.build_mesh(g, VoxelCars.material(), piv, 0.045, m.tags, m.keep)


# ------------------------------------------------------------ the body shell

## A closed (or open-topped) car body from profiles, sorted into components.
## Spec keys (u = voxels from the tail, y = voxels up, w = half widths):
##   L, top, bot, hw: profiles [[u, value], ...]; top_fn(u, zc) -> int extra
##   cabin: c0 (rear window base) .. c1 (windscreen base), rw .. ws flat roof,
##   roof profile, chw / rhw cabin half widths at the belt / roof;
##   open: no roof (a cockpit carved into the body); fa, ra axles; track;
##   bumper (top y); grille_hw; doors (2 / 4); bp (B pillar u);
##   paint, roof_col, pillar_col, bumper_col, interior, glass; engine
##   ("front" / "rear"); rear_glass_from (u: lower rear slope is the lid);
##   sail (rear-window sides are bodywork); round (rounded shoulders).
static func _body(b: B, s: Dictionary) -> void:
	b.L = int(s.get("L", 46))
	b.x0 = (NX - b.L) / 2
	b.fa = float(s.fa)
	b.ra = float(s.ra)
	b.track = float(s.track)
	b.paint = s.paint
	var L := b.L
	var x0 := b.x0
	var top_pts: Array = s.top
	var bot_pts: Array = s.bot
	var hw_pts: Array = s.hw
	var roof_pts: Array = s.get("roof", [])
	var top_fn: Callable = s.get("top_fn", Callable())
	var open: bool = s.get("open", false)
	var c0 := int(s.c0)
	var c1 := int(s.c1)
	var rw := int(s.get("rw", c0 + 3))
	var ws := int(s.get("ws", c1 - 4))
	var chw: float = s.get("chw", 10.5)
	var rhw: float = s.get("rhw", 9.0)
	var rounded: bool = s.get("round", true)
	var tyre: float = s.get("tyre_w", 1.0)
	var tyre_r: float = s.get("tyre_rear", tyre)
	var flare: float = s.get("flare", 0.0)
	var arch_lift: float = s.get("arch_lift", 0.0)
	# solid, cabin and arch masks (local index)
	var n := NX * NY * NZ
	var solid := PackedByteArray()
	solid.resize(n)
	var cab := PackedByteArray()
	cab.resize(n)
	var arch := PackedByteArray()
	arch.resize(n)
	var belt_of := PackedInt32Array()
	belt_of.resize(NX)
	var li := func(x: int, y: int, z: int) -> int:
		return (y * NZ + z) * NX + x
	for x in NX:
		var u := x - x0
		if u < 0 or u >= L:
			continue
		var uc := u + 0.5
		# flared wheel arches: the body swells out (and up) over each wheel
		var fl := 0.0
		for a in [b.fa, b.ra]:
			fl = maxf(fl, clampf((WHEEL_R + 3.2 - absf(uc - float(a))) / 1.8, 0.0, 1.0))
		var w := minf(_pl(hw_pts, uc) + flare * fl, 13.0)
		var t0 := int(floor(_pl(top_pts, uc)))
		var bo := int(floor(_pl(bot_pts, uc)))
		belt_of[x] = t0
		for z in NZ:
			var zc := z - ZC
			var az := absf(zc)
			if az > w:
				continue
			var t := t0 + (int(top_fn.call(u, zc)) if top_fn.is_valid() else 0)
			if az >= b.track - 2.5:
				t += int(round(arch_lift * fl))
			var bb := bo
			if rounded and az > w - 1.0:
				t -= 1
				bb += 1
			for y in range(bb, t + 1):
				solid[li.call(x, y, z)] = 1
			if not open and u >= c0 and u <= c1 and not roof_pts.is_empty():
				var r := int(floor(_pl(roof_pts, uc)))
				var rtop := float(_pl(roof_pts, (rw + ws) * 0.5))
				for y in range(t0 + 1, r + 1):
					var f := clampf(float(y - t0) / maxf(1.0, rtop - t0), 0.0, 1.0)
					if az <= lerpf(chw, rhw, f) and y < NY:
						solid[li.call(x, y, z)] = 1
						cab[li.call(x, y, z)] = 1
	# an open cockpit carved into the body
	if open:
		var ohw: float = s.get("ohw", 8.0)
		for x in range(x0 + c0, x0 + c1 + 1):
			var bo := int(floor(_pl(bot_pts, x - x0 + 0.5)))
			for z in NZ:
				if absf(z - ZC) > ohw:
					continue
				for y in range(bo + 1, NY):
					solid[li.call(x, y, z)] = 0
	# wheel arches
	for a in [b.fa, b.ra]:
		var ax: float = x0 + a
		var inner := b.track - WHEEL_W * 0.5 * (tyre if a == b.fa else tyre_r) - 1.0
		for x in range(int(ax - WHEEL_R - 2), int(ax + WHEEL_R + 3)):
			if x < 0 or x >= NX:
				continue
			for y in range(0, int(WHEEL_Y + WHEEL_R + 2)):
				var dx := x + 0.5 - ax
				var dy := y + 0.5 - WHEEL_Y
				if dx * dx + dy * dy >= (WHEEL_R + 0.75) * (WHEEL_R + 0.75):
					continue
				for z in NZ:
					if absf(z - ZC) >= inner:
						solid[li.call(x, y, z)] = 0
						arch[li.call(x, y, z)] = 1
	var is_solid := func(x: int, y: int, z: int) -> bool:
		if x < 0 or y < 0 or z < 0 or x >= NX or y >= NY or z >= NZ:
			return false
		return solid[(y * NZ + z) * NX + x] == 1
	var is_arch := func(x: int, y: int, z: int) -> bool:
		if x < 0 or y < 0 or z < 0 or x >= NX or y >= NY or z >= NZ:
			return false
		return arch[(y * NZ + z) * NX + x] == 1
	# bumper reach: front-most / rear-most body column per z
	var bumper_y := int(s.get("bumper", 4))
	var fm := PackedInt32Array()
	var rm := PackedInt32Array()
	fm.resize(NZ)
	rm.resize(NZ)
	for z in NZ:
		fm[z] = -1
		rm[z] = NX
		for x in NX:
			for y in range(0, bumper_y + 1):
				if solid[li.call(x, y, z)] == 1:
					fm[z] = maxi(fm[z], x)
					rm[z] = mini(rm[z], x)
	var paint: Color = s.paint
	var roof_col: Color = s.get("roof_col", paint)
	var pillar_col: Color = s.get("pillar_col", paint)
	var bumper_col: Color = s.get("bumper_col", paint.darkened(0.08))
	var glass: Color = s.get("glass", GLASS)
	var grille_hw: float = s.get("grille_hw", 6.0)
	var doors := int(s.get("doors", 2))
	var bp := int(s.get("bp", (c0 + c1) / 2))
	var rear_glass_from := int(s.get("rear_glass_from", -1))
	var sail: bool = s.get("sail", false)
	var f_start := b.fa - WHEEL_R - 2.5
	var r_end := b.ra + WHEEL_R + 2.5
	var edge := float(s.get("edge", 1.6))
	for x in NX:
		var u := x - x0
		for y in NY:
			for z in NZ:
				if solid[li.call(x, y, z)] == 0:
					continue
				var up: bool = not is_solid.call(x, y + 1, z)
				var dn: bool = not is_solid.call(x, y - 1, z)
				var fw: bool = not is_solid.call(x + 1, y, z)
				var bw: bool = not is_solid.call(x - 1, y, z)
				var sd: bool = not is_solid.call(x, y, z + 1) or not is_solid.call(x, y, z - 1)
				if not (up or dn or fw or bw or sd):
					continue  # inside: hollow (internals come later)
				var zc := z - ZC
				var side := "L" if zc < 0 else "R"
				var w := _pl(hw_pts, u + 0.5)
				var shade := lerpf(0.8, 1.0, clampf(float(y - 2) / 7.0, 0.0, 1.0))
				var pn := "cell"
				var col := paint
				var mt := Vox.SOLID
				var liner := false
				for o in [Vector3i(0, 1, 0), Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1), Vector3i(0, -1, 0)]:
					if is_arch.call(x + o.x, y + o.y, z + o.z):
						liner = true
						break
				var region := "door"
				if u + 0.5 >= f_start:
					region = "fender"
				elif u + 0.5 <= r_end:
					region = "quarter"
				if cab[li.call(x, y, z)] == 1:
					# the greenhouse
					if u > ws:
						if absf(zc) >= _cab_hw(chw, rhw, y, belt_of[x], roof_pts, rw, ws) - 0.99:
							pn = "cell"
							col = pillar_col
						else:
							pn = "windscreen"
							col = glass
							mt = Vox.GLASS
					elif u < rw:
						if absf(zc) >= _cab_hw(chw, rhw, y, belt_of[x], roof_pts, rw, ws) - 0.99:
							pn = "cell"
							col = pillar_col
						elif rear_glass_from >= 0 and u < rear_glass_from:
							pn = "trunk"
							col = roof_col if up else paint
						else:
							pn = "backlight"
							col = glass
							mt = Vox.GLASS
						if sail and sd and not up:
							pn = "cell"
							col = paint
							mt = Vox.SOLID
					elif up and not sd:
						var rr := _cab_hw(chw, rhw, y, belt_of[x], roof_pts, rw, ws)
						if absf(zc) >= rr - 0.99:
							pn = "cell"
							col = roof_col.darkened(0.05)
						else:
							pn = "roof"
							col = roof_col
					elif up:
						pn = "cell"
						col = roof_col.darkened(0.05)
					elif u == bp and doors >= 2:
						pn = "cell"
						col = pillar_col
					else:
						col = glass
						mt = Vox.GLASS
						if region == "door":
							pn = ("door_F" + side if (doors == 4 and u > bp) else ("door_R" + side if doors == 4 else "door_" + side))
						else:
							pn = ("quarter_" if region == "quarter" else "fender_") + side
				elif y <= bumper_y and fm[z] >= 0 and (x >= fm[z] - 1 or x <= rm[z] + 1):
					pn = "bumper_F" if u > L / 2 else "bumper_R"
					col = bumper_col * Color(shade, shade, shade)
				elif liner:
					var near_front := absf(x + 0.5 - (x0 + b.fa)) < absf(x + 0.5 - (x0 + b.ra))
					pn = ("fender_" if near_front else "quarter_") + side
					col = paint * Color(0.75, 0.75, 0.75)
				elif dn and not (fw or bw or sd):
					pn = "cell"
					col = CHASSIS
				elif fw and u > L / 2:
					if up:
						pn = "hood"
					elif absf(zc) <= grille_hw:
						pn = "grille"
						col = paint * Color(shade, shade, shade)
					else:
						pn = "fender_" + side
						col = paint * Color(shade, shade, shade)
				elif bw and u < L / 2:
					if up and absf(zc) < w - edge:
						pn = "trunk"
					else:
						pn = "panel_R"
						col = paint * Color(shade, shade, shade)
				elif sd or absf(zc) >= w - edge:
					col = paint * Color(shade, shade, shade)
					if up:
						col = paint
					if region == "door":
						if y <= int(floor(_pl(bot_pts, u + 0.5))) + 1 + (1 if rounded and absf(zc) > w - 1.0 else 0) and sd:
							pn = "skirt_" + side
							col = paint * Color(0.72, 0.72, 0.72)
						elif doors == 4:
							pn = ("door_F" if u > bp else "door_R") + side
						else:
							pn = "door_" + side
					else:
						pn = region + "_" + side
				elif up:
					if u > c1:
						pn = "hood"
					elif u < c0:
						pn = "trunk"
					elif region == "door":
						pn = ("door_F" + side if (doors == 4 and u > bp) else ("door_R" + side if doors == 4 else "door_" + side))
					else:
						pn = region + "_" + side
				else:
					pn = "cell"
					col = paint.darkened(0.35)
				b.put(x, y, z, mt, col, pn)
	b.m.floor_y = (float(_pl(bot_pts, L * 0.5)) + 0.5) * vs()
	# seats, dash, wheel, bulkheads, engine bay and boot
	_interior(b, s, solid, belt_of)
	# where the driver sits and the roof is
	var seat_u := int(s.get("seat_u", (c0 + c1) / 2 - 1))
	var roof_y := float(_pl(roof_pts, (rw + ws) * 0.5)) if not roof_pts.is_empty() and not open else float(_pl(top_pts, seat_u)) + 3.0
	var piv := pivot()
	b.m.roof_top = (roof_y + 1.0) * vs()
	b.m.roof_x = (x0 + (rw + ws) * 0.5) * vs() - piv.x
	var cab_w := (chw if not open else float(s.get("ohw", 8.0))) * 2.0 * vs()
	var sx := (x0 + seat_u + 1.0) * vs() - piv.x
	b.m.cabin = AABB(Vector3(sx - 0.35, 0.0, -cab_w * 0.5), Vector3(0.7, b.m.roof_top, cab_w))
	b.m.tyre = Vector2(tyre, float(s.get("tyre_rear", tyre)))


static func _cab_hw(chw: float, rhw: float, y: int, belt: int, roof_pts: Array, rw: int, ws: int) -> float:
	var rtop := float(_pl(roof_pts, (rw + ws) * 0.5))
	var f := clampf(float(y - belt) / maxf(1.0, rtop - belt), 0.0, 1.0)
	return lerpf(chw, rhw, f)


## The inside: floor-level crash cell (seats, dash, steering wheel, transmission
## tunnel, bulkheads, suspension) and the engine bay / boot internals.
static func _interior(b: B, s: Dictionary, solid: PackedByteArray, belt_of: PackedInt32Array) -> void:
	var x0 := b.x0
	var L := b.L
	var c0 := int(s.c0)
	var c1 := int(s.c1)
	var bot := int(floor(_pl(s.bot, L * 0.5)))
	var belt := int(floor(_pl(s.top, (c0 + c1) * 0.5)))
	var seat: Color = s.get("interior", Color(0.13, 0.12, 0.12))
	var open: bool = s.get("open", false)
	var inner_hw := int(s.get("ohw", s.get("chw", 10.0))) - 1
	var hollow := func(x: int, y: int, z: int) -> bool:
		if x < 0 or y < 0 or z < 0 or x >= NX or y >= NY or z >= NZ:
			return false
		return not b.has(x, y, z)
	var inside := func(x: int, y: int, z: int) -> bool:
		if x < 0 or y < 0 or z < 0 or x >= NX or y >= NY or z >= NZ:
			return false
		return solid[(y * NZ + z) * NX + x] == 1 and not b.has(x, y, z)
	var fill := func(u0: int, u1: int, y0: int, y1: int, zc0: int, zc1: int, c: Color, pn: String, mat: int, sym: bool, need_inside: bool) -> void:
		for side in ([-1, 1] if sym else [1]):
			for u in range(u0, u1 + 1):
				for y in range(y0, y1 + 1):
					for zc in range(zc0, zc1 + 1):
						var x: int = x0 + u
						var z: int = ZC + zc * side
						var ok: bool = inside.call(x, y, z) if need_inside else hollow.call(x, y, z)
						if ok:
							b.put(x, y, z, mat, c, pn)
	# bulkheads: firewall at the windscreen base, the rear bulkhead
	for u in [c1, c0]:
		var x: int = x0 + u
		for y in range(bot + 1, belt_of[clampi(x, 0, NX - 1)] + 1):
			for z in NZ:
				if inside.call(x, y, z):
					b.put(x, y, z, Vox.SOLID, b.paint.darkened(0.45), "cell")
	# transmission tunnel, seats, dash, steering wheel
	var seat_u := int(s.get("seat_u", (c0 + c1) / 2 - 1))
	fill.call(c0 + 1, c1 - 1, bot + 1, bot + 2, -1, 1, CHASSIS, "cell", Vox.SOLID, false, open)
	var seat_z: Array = s.get("seats", [[-6, -3], [3, 6]])
	for sz2 in seat_z:
		var za: int = sz2[0]
		var zb: int = sz2[1]
		fill.call(seat_u, seat_u + 3, bot + 1, bot + 2, za, zb, seat, "cell", Vox.SOLID, false, false)
		fill.call(seat_u - 1, seat_u - 1, bot + 1, belt + 2, za, zb, seat.lightened(0.06), "cell", Vox.SOLID, false, false)
	fill.call(c1 - 2, c1 - 1, belt - 1, belt, -inner_hw, inner_hw, TRIM, "cell", Vox.SOLID, false, false)
	var dz: Array = seat_z[0]
	var wz := (int(dz[0]) + int(dz[1])) / 2
	for k in [-1, 0, 1]:
		b.put(x0 + c1 - 3, belt + 1, ZC + wz + k, Vox.SOLID, TRIM, "cell")
	b.put(x0 + c1 - 3, belt + 2, ZC + wz, Vox.SOLID, TRIM, "cell")
	b.put(x0 + c1 - 3, belt, ZC + wz, Vox.SOLID, TRIM, "cell")
	# suspension towers by the wheels (part of the cell)
	for a in [b.fa, b.ra]:
		var ax := int(floor(x0 + a))
		var tz := int(round(b.track - WHEEL_W * 0.5 - 1.5))
		for side in [-1, 1]:
			for y in range(int(WHEEL_Y), int(floor(_pl(s.top, ax - x0))) ):
				for dx in [0, 1]:
					var z: int = ZC + tz * side
					if inside.call(ax + dx - 1, y, z):
						b.put(ax + dx - 1, y, z, Vox.METAL, STEEL, "cell")
			for zc in range(2, tz + 1):
				if inside.call(ax, int(WHEEL_Y) - 1, ZC + zc * side):
					b.put(ax, int(WHEEL_Y) - 1, ZC + zc * side, Vox.METAL, STEEL.darkened(0.2), "cell")
	# engine bay and boot
	var rear_engine: bool = s.get("engine", "front") == "rear"
	var eng_col: Color = s.get("engine_col", Color(0.72, 0.12, 0.1))
	var top_mid := int(floor(_pl(s.top, (c1 + L) * 0.5)))
	var e0: int
	var e1: int
	if rear_engine:
		e1 = c0 - 1
		e0 = maxi(2, e1 - 9)
		top_mid = int(floor(_pl(s.top, (e0 + e1) * 0.5)))
	else:
		e0 = c1 + 1
		e1 = mini(c1 + 10, L - 5)
	fill.call(e0, e1, bot + 1, top_mid - 2, -3, 3, Color(0.22, 0.22, 0.24), "engine", Vox.METAL, false, true)
	fill.call(e0 + 1, e1 - 1, top_mid - 1, top_mid - 1, 2, 3, eng_col, "engine", Vox.SOLID, true, true)
	fill.call(e0 + 2, e1 - 2, top_mid - 1, top_mid - 1, -1, 1, CHROME, "engine", Vox.METAL, false, true)
	fill.call(e0, e1, bot + 1, bot + 3, 4, 5, Color(0.3, 0.3, 0.33), "engine", Vox.METAL, true, true)
	# radiator behind the nose, battery, fuel tank
	var rad_u := L - 3 if s.get("rad_front", true) else (e0 - 1)
	fill.call(rad_u, rad_u, bot + 2, int(floor(_pl(s.top, rad_u))) - 2, -8, 8, Color(0.18, 0.19, 0.2), "radiator", Vox.METAL, false, true)
	var bat_u := e1 - 2 if not rear_engine else c1 + 3
	fill.call(bat_u, bat_u + 1, bot + 1, bot + 3, 7, 8, Color(0.1, 0.1, 0.1), "battery", Vox.SOLID, false, true)
	var tank_u0 := 2 if not rear_engine else c1 + 2
	var tank_u1 := int(b.ra) - 6 if not rear_engine else L - 6
	if tank_u1 > tank_u0:
		fill.call(tank_u0, tank_u1, bot + 1, bot + 2, -5, 5, Color(0.28, 0.28, 0.3), "tank", Vox.METAL, false, true)
	# exhaust: pipes under the car to tips at the tail (or a centre exit)
	var tips: Array = s.get("tips", [[-6, 0], [6, 0]])
	for tp in tips:
		var tz: int = tp[0]
		var ty: int = bot + 1 + int(tp[1])
		var u_from := e0 if not rear_engine else e0 + 2
		for u in range(-1, u_from + 1):
			var x: int = x0 + u
			if u <= 0:
				b.put(x, ty, ZC + tz, Vox.METAL, Color(0.6, 0.6, 0.62) if u == -1 else Color(0.1, 0.1, 0.1), "exhaust")
			elif inside.call(x, ty, ZC + tz):
				b.put(x, ty, ZC + tz, Vox.METAL, STEEL, "exhaust")
		b.m.exhausts.append(Vector3((x0 - 1) * vs(), (ty + 0.5) * vs(), (ZC + tz + 0.5) * vs()) - pivot())


## Wing on struts across the tail (or a lip when struts = 0).
static func _wing(b: B, u0: int, u1: int, y: int, hw: int, c: Color, strut_zc: int, strut_from: int, endplates := true, thick := 1) -> void:
	b.box(u0, u1, y, y + thick - 1, -hw, hw, Vox.SOLID, c, "wing")
	if endplates:
		b.box(u0, u1, y - 1, y + thick, hw, hw, Vox.SOLID, c.darkened(0.25), "wing", true)
	if strut_zc > 0:
		b.box(u0 + (u1 - u0) / 2, u0 + (u1 - u0) / 2, strut_from, y - 1, strut_zc, strut_zc, Vox.METAL, TRIM, "wing", true)


## Door mirrors on stalks by the windscreen base.
static func _mirrors(b: B, u: int, y: int, zc: int, c: Color) -> void:
	for side in [-1, 1]:
		var pn := "mirror_" + ("L" if side < 0 else "R")
		b.put(b.x0 + u, y, ZC + zc * side, Vox.SOLID, c, pn)
		b.put(b.x0 + u, y, ZC + (zc + 1) * side, Vox.SOLID, c, pn)
		b.put(b.x0 + u, y + 1, ZC + (zc + 1) * side, Vox.SOLID, c, pn)
		b.put(b.x0 + u - 1, y + 1, ZC + (zc + 1) * side, Vox.GLASS, Color(0.55, 0.62, 0.7), pn)


# ============================================================ the designs
#
# Cartoon Motorsport: toy-car proportions - big wheels at the corners under
# flared arches, short overhangs, chunky bumpers standing proud of the body,
# expressive faces (a bonnet brow over a recessed grille, big lamps), and
# each car's defining feature pushed a little further. No accessories: the
# personality is the design.

## A chunky toy bumper across the nose (front) or tail: a bar one voxel proud
## of the body with rounded ends; `lip` adds a dark splitter under it.
static func _bumper(b: B, front: bool, y0: int, y1: int, hw: int, c: Color, mat := Vox.SOLID, lip := Color(0, 0, 0, 0)) -> void:
	var x := b.x0 + (b.L if front else -1)
	var pn := "bumper_F" if front else "bumper_R"
	for y in range(y0, y1 + 1):
		for zc in range(-hw, hw + 1):
			if absi(zc) == hw and (y == y1 or y == y0) and y1 > y0:
				continue
			if b.tag_at(x, y, ZC + zc) == "exhaust":
				continue
			b.put(x, y, ZC + zc, mat, c, pn)
	if lip.a > 0.0:
		for zc in range(-hw + 1, hw):
			if b.tag_at(x, y0 - 1, ZC + zc) != "exhaust":
				b.put(x, y0 - 1, ZC + zc, Vox.SOLID, lip, pn)


## The bonnet's brow: its front edge overhangs the grille by a voxel.
static func _brow(b: B, y: int, hw: int, c: Color) -> void:
	for zc in range(-hw, hw + 1):
		b.put(b.x0 + b.L, y, ZC + zc, Vox.SOLID, c, "hood")


## A square lamp on the nose or tail, both sides: `size` x `size` voxels
## from (y0, zc0) outwards (no cut corners: small ones would read as crosses).
static func _lamp_round(b: B, front: bool, y0: int, zc0: int, size := 3, col := Color(0, 0, 0, 0)) -> void:
	for dy in size:
		for dz in size:
			b.lamp_face(front, y0 + dy, y0 + dy, zc0 + dz, zc0 + dz, 1, col)


## Rocco "Mad Dog": a classic American muscle car, pushed - long bonnet with
## a power bulge and a shaker scoop, a raked stance on fat rear tyres, short
## deck, tunnel-back roof, a full-width black grille under a scowling bonnet
## brow with four round lamps, chrome bumpers, chrome side pipes, the black
## tail stripe and a tall wing; gold and black.
static func _muscle(b: B, cp: Color) -> void:
	var paint := cp if cp.a > 0.0 else Color(0.9, 0.66, 0.15)
	var black := Color(0.06, 0.06, 0.07)
	var bulge := func(u: int, zc: int) -> int:
		return 1 if u >= 29 and u <= 43 and absi(zc) <= 4 else 0
	_body(b, {
		"L": 46, "fa": 37.6, "ra": 8.6, "track": 10.3, "tyre_w": 1.05, "tyre_rear": 1.4, "flare": 1.0, "arch_lift": 1.0,
		"paint": paint, "top_fn": bulge,
		"top": [[0, 11.4], [2, 12.6], [30, 12.2], [44, 11.8], [45, 11.2]],
		"bot": [[0, 3], [3, 2.5], [43, 2.5], [45, 3]],
		"hw": [[0, 11.4], [2, 12.0], [16, 11.8], [24, 11.8], [45, 12.0]],
		"c0": 11, "rw": 15, "ws": 22, "c1": 28, "roof": [[11, 12], [15, 17.6], [22, 17.6], [28, 12]],
		"chw": 10.8, "rhw": 9.2, "sail": true, "roof_col": black, "bumper": 4,
		"grille_hw": 11.0, "interior": Color(0.1, 0.09, 0.09), "seat_u": 17, "tips": [[-6, 0], [6, 0]],
		"engine_col": Color(0.85, 0.2, 0.1),
	})
	b.face(true, 6, 10, 0, 11, black, "grille")
	_lamp_round(b, true, 7, 3)
	_lamp_round(b, true, 7, 7)
	_brow(b, 11, 11, paint)
	_bumper(b, true, 3, 5, 12, CHROME, Vox.METAL, black)
	# black bonnet bulge, shaker scoop, the black stripe round the tail
	b.stripe_top(0, 4, black, 29, 43)
	b.box(33, 37, 14, 15, -2, 2, Vox.SOLID, black, "scoop")
	b.box(37, 37, 15, 15, -1, 1, Vox.SOLID, Color(0.2, 0.2, 0.21), "scoop")
	b.stripe_top(0, 13, black, 3, 5)
	b.stripe_side(3, 12, black, 3, 5)
	b.face(false, 6, 11, 0, 12, black, "panel_R")
	b.lamp_face(false, 7, 9, 3, 10, 1)
	_bumper(b, false, 3, 5, 12, CHROME, Vox.METAL)
	# chrome side pipes along the sills
	b.box(13, 27, 3, 3, 13, 13, Vox.METAL, CHROME, "exhaust_S", true)
	_wing(b, 0, 3, 18, 12, paint, 0, 0, true, 1)
	b.box(1, 2, 12, 17, 11, 11, Vox.SOLID, paint.darkened(0.15), "wing", true)
	_mirrors(b, 27, 13, 11, CHROME)


## Victor "The Professor": a quick performance saloon - three crisp boxes on
## big wheels in boxy flared arches, four doors, a split grille between twin
## round lamps, a body-coloured bumper with a dark intake, a boot lip; sage
## green with a cream pinstripe.
static func _sedan(b: B, cp: Color) -> void:
	var paint := cp if cp.a > 0.0 else Color(0.47, 0.57, 0.47)
	var cream := Color(0.93, 0.89, 0.74)
	_body(b, {
		"L": 46, "fa": 37.6, "ra": 8.6, "track": 10.3, "tyre_w": 1.1, "tyre_rear": 1.15, "flare": 1.0,
		"paint": paint,
		"top": [[0, 11.4], [2, 12.2], [31, 12.2], [42, 11.8], [45, 11.0]],
		"bot": [[0, 3], [3, 2.5], [43, 2.5], [45, 3]],
		"hw": [[0, 11.4], [2, 11.8], [45, 11.8]],
		"c0": 9, "rw": 13, "ws": 25, "c1": 31, "roof": [[9, 12], [13, 18.6], [25, 18.6], [31, 12]],
		"chw": 11.0, "rhw": 9.4, "doors": 4, "bp": 19, "bumper": 5, "grille_hw": 5.0,
		"interior": Color(0.55, 0.42, 0.3), "seat_u": 21, "pillar_col": TRIM,
		"tips": [[-5, 0], [-7, 0]], "engine_col": Color(0.25, 0.3, 0.45),
	})
	b.face(true, 7, 10, 0, 11, TRIM, "grille")
	b.face(true, 7, 10, 0, 0, paint, "grille")
	b.face(true, 7, 10, 4, 4, paint, "grille")
	_lamp_round(b, true, 8, 5)
	_lamp_round(b, true, 8, 8)
	_brow(b, 11, 10, paint)
	_bumper(b, true, 3, 6, 11, paint.darkened(0.04), Vox.SOLID, TRIM)
	b.paint_box(46, 46, 4, 4, 0, 7, TRIM, true, "bumper")
	b.lamp_face(false, 8, 10, 5, 11, 1)
	_bumper(b, false, 3, 6, 11, paint.darkened(0.04))
	b.box(0, 1, 13, 13, -10, 10, Vox.SOLID, paint, "trunk")
	b.stripe_side(9, 9, cream, 2, 43)
	_mirrors(b, 30, 13, 11, paint)


## Ellie "Sparrow": a light British-style roadster - small and round, big
## round-topped fenders, open top, a little chrome-framed windscreen, roll
## hoops, pop-up lamps standing up like eyes and a smiling mouth; steel blue
## with two white chevrons.
static func _roadster(b: B, cp: Color) -> void:
	var paint := cp if cp.a > 0.0 else Color(0.3, 0.42, 0.56)
	var white := Color(0.96, 0.96, 0.93)
	_body(b, {
		"L": 40, "fa": 32.6, "ra": 7.4, "track": 10.0, "flare": 1.3, "arch_lift": 1.0,
		"paint": paint, "open": true, "ohw": 7.6,
		"top": [[0, 10.2], [3, 11.0], [33, 11.0], [37, 10.4], [39, 9.4]],
		"bot": [[0, 3], [3, 2.5], [37, 2.5], [39, 3]],
		"hw": [[0, 9.8], [2, 10.8], [36, 10.8], [39, 9.6]],
		"c0": 12, "c1": 23, "chw": 7.6, "bumper": 3, "grille_hw": 5.0,
		"interior": Color(0.5, 0.17, 0.1), "seat_u": 15, "tips": [[-5, 0]], "seats": [[-6, -3], [3, 6]],
		"engine_col": Color(0.2, 0.2, 0.22),
	})
	b.box(23, 23, 12, 13, -8, 8, Vox.GLASS, Color(0.6, 0.7, 0.78), "windscreen")
	b.box(23, 23, 12, 14, 9, 9, Vox.METAL, CHROME, "cell", true)
	b.box(23, 23, 14, 14, -8, 8, Vox.METAL, CHROME, "windscreen")
	for zc in [3, 6]:
		b.box(13, 13, 12, 14, zc, zc, Vox.METAL, CHROME, "cell", true)
	b.box(13, 13, 14, 14, 3, 6, Vox.METAL, CHROME, "cell", true)
	# pop-up lamps standing up on the bonnet
	b.box(32, 34, 12, 13, 5, 8, Vox.SOLID, paint, "head_S", true)
	b.box(34, 34, 12, 13, 6, 7, Vox.HEAD, LENS, "head_S", true)
	# a smiling mouth
	b.face(true, 5, 5, 0, 3, TRIM, "grille")
	b.face(true, 6, 6, 4, 5, TRIM, "grille")
	_bumper(b, true, 3, 4, 9, CHROME, Vox.METAL)
	_lamp_round(b, false, 7, 6, 2)
	_bumper(b, false, 3, 4, 9, CHROME, Vox.METAL)
	for u in range(27, 34):
		for zc in range(0, 8):
			var k := (u - zc + 60) % 7
			if k < 2 and u - zc >= 24:
				b.paint_box(u, u, 0, NY - 1, zc, zc, white, true, "hood")
	_mirrors(b, 22, 12, 10, CHROME)


## Hank "The Wall": a modern American pony car - a high, heavy body on fat
## rear tyres, slit windows under a low roof, blacked-out pillars, a wide
## black grille with slanted slim lamps glaring under the bonnet brow, a
## power dome and a ducktail; teal with twin white stripes.
static func _pony(b: B, cp: Color) -> void:
	var paint := cp if cp.a > 0.0 else Color(0.15, 0.56, 0.56)
	var white := Color(0.96, 0.96, 0.93)
	var dome := func(u: int, zc: int) -> int:
		return 1 if u >= 30 and u <= 42 and absi(zc) <= 4 else 0
	_body(b, {
		"L": 46, "fa": 37.6, "ra": 8.6, "track": 10.3, "tyre_w": 1.1, "tyre_rear": 1.35, "flare": 0.9, "arch_lift": 1.0,
		"paint": paint, "top_fn": dome,
		"top": [[0, 12.4], [2, 13.2], [29, 13.2], [44, 12.8], [45, 12.2]],
		"bot": [[0, 3], [3, 2.5], [43, 2.5], [45, 3]],
		"hw": [[0, 11.6], [2, 12.0], [45, 12.0]],
		"c0": 13, "rw": 17, "ws": 23, "c1": 29, "roof": [[13, 13], [17, 18.2], [23, 18.2], [29, 13]],
		"chw": 10.6, "rhw": 9.2, "pillar_col": TRIM, "bumper": 5, "grille_hw": 11.0,
		"interior": Color(0.1, 0.1, 0.11), "seat_u": 18, "tips": [[-7, 0], [7, 0]], "engine_col": Color(0.15, 0.15, 0.17),
	})
	b.face(true, 7, 11, 0, 11, TRIM, "grille")
	b.lamp_face(true, 11, 11, 7, 9)
	b.lamp_face(true, 10, 10, 9, 11)
	_brow(b, 12, 11, paint)
	_bumper(b, true, 3, 5, 12, paint, Vox.SOLID, TRIM)
	b.paint_box(46, 46, 4, 4, 0, 8, TRIM, true, "bumper")
	b.stripe_top(2, 4, white)
	_wing(b, 0, 1, 14, 11, paint, 0, 0, false, 1)
	b.face(false, 9, 11, 0, 3, TRIM, "panel_R")
	b.lamp_face(false, 9, 10, 4, 10, 1)
	_bumper(b, false, 3, 5, 12, paint, Vox.SOLID, TRIM)
	_mirrors(b, 28, 14, 11, TRIM)


## Maya "Ghost": a rear-engined GT coupe - a round, bubbly body, big round
## lamps on high front fenders (a frog's eyes), a bonnet sloping between
## them, the fastback falling to a slatted engine lid, wide rear hips and a
## ducktail; cream with a blue centre stripe.
static func _coupe(b: B, cp: Color) -> void:
	var paint := cp if cp.a > 0.0 else Color(0.9, 0.87, 0.77)
	var blue := Color(0.48, 0.6, 0.88)
	var peaks := func(u: int, zc: int) -> int:
		if u >= 29 and absi(zc) >= 7:
			return 2
		if u <= 14 and u >= 2 and absi(zc) >= 9:
			return 1
		return 0
	_body(b, {
		"L": 42, "fa": 34.6, "ra": 8.4, "track": 10.2, "tyre_rear": 1.25, "flare": 0.9,
		"paint": paint, "top_fn": peaks,
		"top": [[0, 10.4], [4, 11.6], [26, 11.8], [30, 11.2], [38, 10.0], [41, 8.8]],
		"bot": [[0, 3], [3, 2.5], [39, 2.5], [41, 3]],
		"hw": [[0, 10.6], [3, 11.6], [22, 11.2], [38, 11.6], [41, 10.2]],
		"c0": 4, "rw": 16, "ws": 21, "c1": 27, "roof": [[4, 12], [9, 15.2], [16, 17.8], [21, 17.8], [27, 12]],
		"chw": 10.0, "rhw": 8.0, "rear_glass_from": 10, "engine": "rear",
		"bumper": 4, "grille_hw": 5.0, "interior": Color(0.47, 0.31, 0.2), "seat_u": 17,
		"tips": [[-1, 0], [1, 0]], "engine_col": Color(0.3, 0.3, 0.32),
	})
	_lamp_round(b, true, 10, 8, 3)
	b.face(true, 4, 5, 0, 5, TRIM, "grille")
	_bumper(b, true, 3, 4, 9, paint, Vox.SOLID, TRIM)
	b.lamp_face(false, 9, 9, 1, 10, 1)
	b.stripe_top(0, 1, blue)
	for u in range(5, 10, 2):
		b.paint_box(u, u, 0, NY - 1, 0, 6, TRIM, true, "trunk")
	_wing(b, 1, 3, 12, 9, paint, 0, 0, false, 1)
	_bumper(b, false, 3, 4, 10, paint, Vox.SOLID, TRIM)
	_mirrors(b, 26, 13, 10, paint)


## Dante "Showboat": an Italian mid-engined exotic - a low, long wedge,
## high front fenders, a long raked windscreen, deep side intakes, a slatted
## engine cover and a big rear wing on endplates; burgundy with gold.
static func _exotic(b: B, cp: Color) -> void:
	var paint := cp if cp.a > 0.0 else Color(0.5, 0.08, 0.17)
	var gold := Color(0.94, 0.74, 0.27)
	var peaks := func(u: int, zc: int) -> int:
		return 1 if u >= 31 and u <= 42 and absi(zc) >= 9 else 0
	_body(b, {
		"L": 46, "fa": 37.6, "ra": 8.6, "track": 10.3, "tyre_w": 1.05, "tyre_rear": 1.4, "flare": 1.0, "arch_lift": 1.0,
		"paint": paint, "top_fn": peaks,
		"top": [[0, 11.8], [3, 12.0], [16, 11.4], [30, 10.2], [40, 9.2], [45, 8.0]],
		"bot": [[0, 3], [3, 2.5], [43, 2.5], [45, 2.5]],
		"hw": [[0, 11.6], [2, 12.0], [20, 11.4], [38, 11.8], [45, 10.6]],
		"c0": 15, "rw": 18, "ws": 23, "c1": 32, "roof": [[15, 12], [18, 16.2], [23, 16.2], [32, 10.4]],
		"chw": 9.6, "rhw": 7.6, "engine": "rear", "bumper": 3, "grille_hw": 9.0,
		"interior": Color(0.36, 0.25, 0.18), "seat_u": 20, "tips": [[-1, 2], [1, 2]], "pillar_col": paint,
		"engine_col": Color(0.85, 0.15, 0.1),
	})
	b.lamp_face(true, 8, 9, 7, 10)
	b.face(true, 4, 6, 0, 9, TRIM, "bumper_F")
	_bumper(b, true, 3, 3, 11, TRIM)
	b.stripe_top(2, 3, gold)
	for u in range(3, 15, 2):
		b.paint_box(u, u, 0, NY - 1, 0, 7, TRIM, true, "trunk")
	b.paint_box(11, 15, 5, 9, 11, 13, TRIM, true)
	_lamp_round(b, false, 9, 3, 2)
	_lamp_round(b, false, 9, 7, 2)
	_bumper(b, false, 3, 4, 11, TRIM)
	_wing(b, 0, 3, 14, 12, paint, 0, 0, true, 1)
	b.box(0, 2, 12, 13, 12, 12, Vox.SOLID, paint.darkened(0.2), "wing", true)
	_mirrors(b, 31, 12, 10, paint)


## Nina "The Hunter": a modern mid-engined American supercar - a sharp,
## predatory nose with slim slanted lamps, a deep black front intake, huge
## side intakes, black pillars and roof, wide rear hips on fat tyres and a
## spoiler on struts; pink with black.
static func _supercar(b: B, cp: Color) -> void:
	var paint := cp if cp.a > 0.0 else Color(0.8, 0.27, 0.49)
	var peaks := func(u: int, zc: int) -> int:
		if u >= 31 and u <= 42 and absi(zc) >= 9:
			return 1
		if u >= 3 and u <= 14 and absi(zc) >= 10:
			return 1
		return 0
	_body(b, {
		"L": 46, "fa": 37.6, "ra": 8.6, "track": 10.3, "tyre_w": 1.05, "tyre_rear": 1.4, "flare": 1.0, "arch_lift": 1.0,
		"paint": paint, "top_fn": peaks,
		"top": [[0, 12.0], [3, 12.2], [15, 11.8], [30, 10.2], [42, 9.2], [45, 8.6]],
		"bot": [[0, 3], [3, 2.5], [43, 2.5], [45, 2.5]],
		"hw": [[0, 11.8], [3, 12.2], [22, 11.4], [40, 12.0], [45, 11.0]],
		"c0": 16, "rw": 19, "ws": 24, "c1": 31, "roof": [[16, 12], [19, 16.4], [24, 16.4], [31, 10.4]],
		"chw": 9.6, "rhw": 7.6, "engine": "rear", "pillar_col": TRIM, "roof_col": TRIM, "bumper": 3,
		"grille_hw": 8.0, "interior": Color(0.1, 0.1, 0.11), "seat_u": 21, "tips": [[-1, 0], [1, 0], [-3, 0], [3, 0]],
		"engine_col": Color(0.85, 0.85, 0.88),
	})
	b.lamp_face(true, 9, 9, 6, 11)
	b.lamp_face(true, 10, 10, 9, 11)
	b.face(true, 4, 7, 0, 8, TRIM, "bumper_F")
	_bumper(b, true, 3, 3, 11, TRIM)
	b.paint_box(13, 17, 5, 10, 11, 13, TRIM, true)
	b.lamp_face(false, 10, 10, 4, 11, 1)
	b.face(false, 6, 9, 0, 3, TRIM, "panel_R")
	_bumper(b, false, 3, 4, 11, TRIM)
	_wing(b, 1, 3, 15, 11, paint, 8, 13, true, 1)
	_mirrors(b, 30, 12, 10, TRIM)


## The player: a Le Mans GT racer - very low and wide, round lamps on the
## fender fronts, a dark mouth, side ducts, a long Kamm tail with a lip
## spoiler, fat rear tyres; twin racing stripes over the whole car.
static func _gt(b: B, paint: Color, stripe: Color) -> void:
	var peaks := func(u: int, zc: int) -> int:
		if u >= 31 and u <= 42 and absi(zc) >= 9:
			return 1
		if u >= 3 and u <= 14 and absi(zc) >= 10:
			return 1
		return 0
	_body(b, {
		"L": 46, "fa": 37.6, "ra": 8.6, "track": 10.3, "tyre_w": 1.05, "tyre_rear": 1.3, "flare": 1.0, "arch_lift": 1.0,
		"paint": paint, "top_fn": peaks,
		"top": [[0, 11.6], [3, 11.8], [16, 11.2], [30, 10.6], [42, 9.6], [45, 8.6]],
		"bot": [[0, 3], [3, 2.5], [43, 2.5], [45, 2.5]],
		"hw": [[0, 12.0], [3, 12.2], [22, 11.6], [42, 12.0], [45, 11.0]],
		"c0": 15, "rw": 18, "ws": 23, "c1": 29, "roof": [[15, 12], [18, 16.0], [23, 16.0], [29, 10.6]],
		"chw": 10.2, "rhw": 8.2, "engine": "rear", "bumper": 3, "grille_hw": 7.0,
		"interior": Color(0.12, 0.12, 0.13), "seat_u": 19, "tips": [[-2, 1], [2, 1]],
		"engine_col": Color(0.3, 0.3, 0.33),
	})
	_lamp_round(b, true, 8, 8, 3)
	b.face(true, 5, 7, 0, 6, TRIM, "grille")
	_bumper(b, true, 3, 4, 10, paint, Vox.SOLID, TRIM)
	b.stripe_top(1, 3, stripe)
	b.paint_box(24, 26, 0, NY - 1, 5, 6, TRIM, true, "door")
	for u in range(4, 13, 2):
		b.paint_box(u, u, 0, NY - 1, 0, 0, TRIM, false, "trunk")
	_lamp_round(b, false, 9, 8)
	_lamp_round(b, false, 9, 4)
	b.face(false, 6, 8, 0, 3, TRIM, "panel_R")
	_bumper(b, false, 3, 5, 11, TRIM)
	_wing(b, 0, 1, 13, 11, paint, 0, 0, false, 1)
	_mirrors(b, 28, 12, 10, paint)


## Finn "Wildcard": a rally hatchback - a tall, stubby box on knobbly big
## wheels in square flared arches, a chunky black bumper, a lamp pod on the
## bonnet, a roof scoop, mud flaps and a wing on the hatch; black with a
## yellow zigzag.
static func _rally(b: B, cp: Color) -> void:
	var paint := cp if cp.a > 0.0 else Color(0.12, 0.12, 0.13)
	var yellow := Color(0.98, 0.77, 0.16)
	_body(b, {
		"L": 40, "fa": 32.6, "ra": 7.4, "track": 10.6, "tyre_w": 1.1, "flare": 2.0, "arch_lift": 1.0,
		"paint": paint,
		"top": [[0, 12.0], [2, 12.6], [26, 12.6], [37, 12.2], [39, 11.2]],
		"bot": [[0, 3.5], [2, 3], [37, 3], [39, 3.5]],
		"hw": [[0, 10.8], [2, 11.0], [39, 10.8]],
		"c0": 3, "rw": 6, "ws": 21, "c1": 27, "roof": [[3, 13], [6, 18], [21, 18], [27, 13]],
		"chw": 10.4, "rhw": 9.4, "doors": 2, "bp": 15, "bumper": 5,
		"grille_hw": 6.0, "interior": Color(0.15, 0.15, 0.2), "seat_u": 16, "tips": [[8, 0]],
		"engine_col": Color(0.95, 0.7, 0.15), "pillar_col": paint,
	})
	b.face(true, 8, 10, 0, 6, TRIM, "grille")
	b.lamp_face(true, 9, 10, 7, 10)
	_brow(b, 12, 10, paint)
	_bumper(b, true, 3, 6, 11, Color(0.16, 0.16, 0.17))
	b.lamp_face(false, 9, 11, 9, 10, 1)
	_bumper(b, false, 3, 5, 11, Color(0.16, 0.16, 0.17))
	var zig := func(u: int, y: int) -> bool:
		var t := 6 + absi((u % 8) - 4)
		return y == t or y == t + 1
	b.stripe_side(6, 12, yellow, 1, 38, zig)
	b.box(12, 15, 19, 19, -2, 2, Vox.SOLID, yellow, "scoop")
	b.box(15, 15, 19, 19, -1, 1, Vox.SOLID, TRIM, "scoop")
	_wing(b, 2, 5, 19, 11, yellow, 6, 18, false, 1)
	# lamp pod on the bonnet front
	b.box(33, 34, 13, 14, -7, 7, Vox.SOLID, TRIM, "pod")
	for zc in [-6, -2, 2, 6]:
		b.box(35, 35, 13, 14, zc - 1, zc, Vox.HEAD, LENS, "pod")
	for a in [[b.fa, "flap_F"], [b.ra, "flap_R"]]:
		var u := int(float(a[0]) - WHEEL_R - 1.5)
		b.box(u, u, 1, 5, 10, 12, Vox.SOLID, Color(0.78, 0.12, 0.1), String(a[1]) + "_S", true)
	_mirrors(b, 26, 14, 11, paint)


## The junker: an old, saggy estate car - a long boxy roof, rusty chrome,
## round lamps in a tired face and panels from other cars in other colours.
static func _wagon(b: B, cp: Color) -> void:
	var paint := cp if cp.a > 0.0 else Color(0.6, 0.58, 0.5)
	var rust := Color(0.45, 0.24, 0.12)
	var tired := Color(0.58, 0.55, 0.5)
	_body(b, {
		"L": 44, "fa": 35.6, "ra": 8.4, "track": 10.2, "flare": 0.6, "round": false,
		"paint": paint,
		"top": [[0, 11.4], [2, 12.0], [42, 12.0], [43, 11.4]],
		"bot": [[0, 3], [43, 3]],
		"hw": [[0, 11.6], [1, 12.0], [42, 12.0], [43, 11.6]],
		"c0": 1, "rw": 3, "ws": 25, "c1": 30, "roof": [[1, 12], [3, 18.6], [25, 18.6], [30, 12]],
		"chw": 11.2, "rhw": 10.2, "doors": 4, "bp": 19, "bumper": 4,
		"grille_hw": 7.0, "interior": Color(0.35, 0.3, 0.25), "seat_u": 21, "tips": [[-6, 0]],
		"engine_col": Color(0.3, 0.32, 0.3),
	})
	b.face(true, 6, 10, 0, 6, Color(0.42, 0.4, 0.36), "grille", Vox.METAL)
	_lamp_round(b, true, 7, 8, 3)
	_bumper(b, true, 3, 5, 11, tired, Vox.METAL)
	b.lamp_face(false, 7, 10, 10, 11, 1)
	_bumper(b, false, 3, 5, 11, tired, Vox.METAL)
	var swaps := {"door_FL": Color(0.38, 0.47, 0.58), "fender_R": Color(0.42, 0.55, 0.32), "trunk": Color(0.5, 0.33, 0.2),
		"door_RR": Color(0.72, 0.7, 0.62), "hood": Color(0.55, 0.53, 0.47)}
	var g := b.g
	for y in NY:
		for z in NZ:
			for x in NX:
				if not b.has(x, y, z):
					continue
				var t := b.tag_at(x, y, z)
				var mt := g.get_m(x, y, z)
				if mt != Vox.SOLID:
					continue
				if swaps.has(t):
					g.set_v(x, y, z, mt, (swaps[t] as Color) * g.get_c(x, y, z) / paint)
				if b.m.parts[b.m.tags[b.idx(x, y, z)]].layer == OUTER and Vox.hash3(x * 3, y * 5, z * 7) < 0.04:
					g.set_v(x, y, z, mt, rust.lerp(g.get_c(x, y, z), 0.3))
	_mirrors(b, 29, 13, 12, CHROME)


## Greta "Clockwork": a Formula-style single-seater - open wheels on
## wishbones, a narrow tub with the driver's helmet in the cockpit, a long
## nose with a front wing, sidepods, an airbox and a rear wing; olive with a
## checkered nose (her drawing's).
static func _formula(b: B, cp: Color) -> void:
	var paint := cp if cp.a > 0.0 else Color(0.4, 0.42, 0.2)
	var cream := Color(0.92, 0.9, 0.78)
	b.L = 46
	b.x0 = 1
	b.fa = 38.0
	b.ra = 7.6
	b.track = 10.3
	b.paint = paint
	var carbon := Color(0.1, 0.1, 0.11)
	# the tub (crash cell): floor, sides, cockpit rim, seat, helmet
	b.box(12, 34, 2, 2, -4, 4, Vox.SOLID, carbon, "cell")
	b.box(12, 34, 3, 6, -3, 3, Vox.SOLID, paint, "cell")
	b.box(19, 27, 5, 7, -2, 2, Vox.AIR, Color.BLACK, "cell")
	b.box(19, 27, 7, 7, -3, -3, Vox.SOLID, paint, "cell")
	b.box(19, 27, 7, 7, 3, 3, Vox.SOLID, paint, "cell")
	b.box(20, 21, 4, 6, -2, 2, Vox.SOLID, carbon, "cell")
	b.box(22, 23, 7, 8, -1, 1, Vox.SOLID, cream, "cell")
	b.box(23, 23, 8, 8, -1, 1, Vox.GLASS, Color(0.1, 0.12, 0.16), "cell")
	b.box(26, 26, 7, 7, -1, 1, Vox.SOLID, carbon, "cell")
	# nose cone with a checkered tip, front wing
	for u in range(34, 46):
		var t := float(u - 34) / 11.0
		var hw := int(round(lerpf(3.0, 1.0, t)))
		var top := int(round(lerpf(6.0, 4.0, t)))
		for y in range(3, top + 1):
			for zc in range(-hw, hw + 1):
				var c := paint
				if u >= 40 and y == top and (u + zc + 20) % 2 == 0:
					c = cream
				b.put(b.x0 + u, y, ZC + zc, Vox.SOLID, c, "nose")
	b.box(43, 45, 1, 1, -12, 12, Vox.SOLID, paint, "wing_F")
	b.box(44, 45, 2, 2, -12, 12, Vox.SOLID, cream, "wing_F")
	b.box(42, 45, 1, 3, 12, 12, Vox.SOLID, carbon, "wing_F", true)
	b.box(44, 44, 3, 3, -1, 1, Vox.SOLID, carbon, "wing_F")
	# sidepods with radiators inside and dark intakes
	for side in [-1, 1]:
		var pn := "sidepod_" + ("L" if side < 0 else "R")
		for u in range(13, 29):
			var t := clampf(float(u - 13) / 15.0, 0.0, 1.0)
			var top := int(round(lerpf(4.0, 6.0, t)))
			for y in range(2, top + 1):
				for zc in range(4, 9):
					var c := paint if y > 2 else carbon
					if u == 28 and y > 2 and zc < 8:
						c = carbon
					b.put(b.x0 + u, y, ZC + zc * side, Vox.SOLID, c, pn)
		b.box(16, 24, 3, 4, 5, 7, Vox.METAL, Color(0.18, 0.19, 0.2), "radiator_" + ("L" if side < 0 else "R"))
		for u in range(16, 25):
			for zc in range(5, 8):
				for y in range(3, 5):
					b.put(b.x0 + u, y, ZC + zc * side, Vox.METAL, Color(0.18, 0.19, 0.2), "radiator_" + ("L" if side < 0 else "R"))
	# airbox / roll hoop over the engine, engine cover tapering to the tail
	b.box(16, 18, 7, 10, -2, 2, Vox.SOLID, paint, "airbox")
	b.box(18, 18, 8, 9, -1, 1, Vox.SOLID, carbon, "airbox")
	b.box(6, 15, 3, 8, -3, 3, Vox.SOLID, paint, "cover")
	for u in range(4, 16):
		var top := int(round(lerpf(5.0, 8.0, float(u - 4) / 11.0)))
		var hw := 1 if u < 8 else (2 if u < 11 else 3)
		for y in range(3, top + 1):
			for zc in range(-hw, hw + 1):
				b.put(b.x0 + u, y, ZC + zc, Vox.SOLID, paint, "cover")
	b.box(7, 14, 3, 5, -2, 2, Vox.METAL, Color(0.25, 0.25, 0.27), "engine")
	b.box(8, 13, 6, 6, -1, 1, Vox.METAL, Color(0.75, 0.6, 0.3), "engine")
	# rear wing on a centre pillar
	b.box(0, 3, 12, 12, -8, 8, Vox.SOLID, paint, "wing")
	b.box(1, 3, 11, 11, -8, 8, Vox.SOLID, cream, "wing")
	b.box(0, 3, 9, 13, 8, 8, Vox.SOLID, carbon, "wing", true)
	b.box(2, 2, 6, 10, 0, 0, Vox.SOLID, carbon, "wing")
	# wishbones to the wheels, gearbox, exhaust, rain light
	for a in [b.fa, b.ra]:
		var u := int(floor(a))
		for side in [-1, 1]:
			for zc in range(3, int(b.track) - 1):
				b.put(b.x0 + u, 5, ZC + zc * side, Vox.METAL, carbon, "cell")
				b.put(b.x0 + u - 1, 6, ZC + zc * side, Vox.METAL, carbon, "cell")
	b.box(3, 6, 3, 5, -1, 1, Vox.METAL, Color(0.3, 0.3, 0.32), "cell")
	b.box(2, 2, 4, 4, 0, 0, Vox.METAL, Color(0.6, 0.6, 0.62), "exhaust")
	b.box(0, 0, 7, 7, 0, 0, Vox.TAIL, RED_LENS, "tail_L")
	b.box(0, 0, 8, 8, 0, 0, Vox.TAIL, RED_LENS, "tail_R")
	# lamps in the sidepod fronts (for night races), mirrors
	b.box(29, 29, 4, 4, 6, 7, Vox.HEAD, LENS, "head_S", true)
	_mirrors(b, 27, 6, 4, carbon)
	b.m.exhausts.append(Vector3((b.x0 + 1.5) * vs(), 4.5 * vs(), (ZC + 0.5) * vs()) - pivot())
	b.m.floor_y = 2.0 * vs()
	b.m.roof_top = 10.0 * vs()
	b.m.roof_x = (b.x0 + 17.0) * vs() - pivot().x
	b.m.cabin = AABB(Vector3((b.x0 + 23.0) * vs() - pivot().x - 0.3, 0.0, -0.3), Vector3(0.6, 8.0 * vs(), 0.6))
	b.m.tyre = Vector2(1.2, 1.45)
