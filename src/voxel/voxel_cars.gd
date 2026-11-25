class_name VoxelCars
extends RefCounted
## Converts HyperCars' top-down car artwork into little voxel racing models.
##
## Any body drawing works (packaged templates, the user's custom/ art, won
## cars, the junker): the picture is sampled into a grid of fine voxels
## (Vox.CAR_VOXEL_PX = 2 display px), and each column is extruded to a height
## shaped like a car:
##   * the body is rounded towards its silhouette (distance to the edge),
##   * the dark window panes become a glass cabin: rear window rising to the
##     roof (where the number roundel sits), windscreen sloping down to the
##     bonnet, side windows along the cabin edges,
##   * wheel arches are cut over the four wheels (WheelLayout positions),
##   * lamp voxels sit at the game's lamp anchors (LightingPilot): emissive
##     head lamps at the nose, tail lamps at the tail.
## The top of every column keeps the drawing's own colour, so liveries,
## stripes and numbers survive; sides are the same paint, a little darker
## towards the sill. Meshes are cached per texture.

const MODEL_SHADER := preload("res://src/voxel/shaders/voxel_model.gdshader")
const DISPLAY := Vector2(64.0, 36.0)
## Heights in car voxels (2 px each).
const BOTTOM := 2
const BODY_MAX := 7
const CABIN_TOP := 10
const WHEEL_R := 3
const WHEEL_W := 3

static var _material: ShaderMaterial
static var _bodies: Dictionary = {}
static var _wheel: ArrayMesh


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = MODEL_SHADER
	return _material


static func voxel_size() -> float:
	return Vox.CAR_VOXEL_PX * Vox.PX


## The voxel body for a car drawing (nose +X, the car's right +Z, centred,
## standing on y = 0).
static func body_mesh(tex: Texture2D, layout: WheelLayout = null, body_logical: String = "") -> ArrayMesh:
	var key := "%s|%d|%s" % [tex.resource_path if tex != null else "", tex.get_instance_id() if tex != null else 0, body_logical]
	if _bodies.has(key):
		return _bodies[key]
	var mesh := _build_body(tex, layout, body_logical)
	_bodies[key] = mesh
	return mesh


static func _build_body(tex: Texture2D, layout: WheelLayout, body_logical: String) -> ArrayMesh:
	var nx := int(DISPLAY.x / Vox.CAR_VOXEL_PX)
	var nz := int(DISPLAY.y / Vox.CAR_VOXEL_PX)
	var n := nx * nz
	var occ := PackedByteArray()
	occ.resize(n)
	var cols: Array[Color] = []
	cols.resize(n)
	var img := Vox.rgba(tex)
	if img != null:
		var fx := float(img.get_width()) / nx
		var fz := float(img.get_height()) / nz
		for cz in nz:
			for cx in nx:
				var cnt := 0
				var tot := 0
				var sum := Vector3.ZERO
				for py in range(int(cz * fz), int((cz + 1) * fz)):
					for px in range(int(cx * fx), int((cx + 1) * fx)):
						var p := img.get_pixel(px, py)
						tot += 1
						if p.a > 0.7:
							cnt += 1
							sum += Vector3(p.r, p.g, p.b)
				if tot > 0 and cnt >= tot * 0.45:
					occ[cz * nx + cx] = 1
					var m := sum / cnt
					cols[cz * nx + cx] = Color(m.x, m.y, m.z)
	else:  # no drawing: a plain grey wedge so the race still shows a car
		for cz in range(3, nz - 3):
			for cx in range(2, nx - 2):
				occ[cz * nx + cx] = 1
				cols[cz * nx + cx] = Color(0.6, 0.6, 0.62)
	# distance (cells) to the silhouette edge, 4-neighbour
	var dist := PackedInt32Array()
	dist.resize(n)
	for i in n:
		dist[i] = 0 if occ[i] == 0 else 99
	for _pass in 2:
		for cz in nz:
			for cx in nx:
				var i := cz * nx + cx
				if occ[i] == 0:
					continue
				var best := dist[i]
				for o in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
					var x2: int = cx + o.x
					var z2: int = cz + o.y
					var dn := 0
					if x2 >= 0 and z2 >= 0 and x2 < nx and z2 < nz and occ[z2 * nx + x2] == 1:
						dn = dist[z2 * nx + x2] + 1
					best = mini(best, dn)
				dist[i] = best
		# second sweep from the other corner
		for cz in range(nz - 1, -1, -1):
			for cx in range(nx - 1, -1, -1):
				var i := cz * nx + cx
				if occ[i] == 0:
					continue
				var best := dist[i]
				for o in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
					var x2: int = cx + o.x
					var z2: int = cz + o.y
					var dn := 0
					if x2 >= 0 and z2 >= 0 and x2 < nx and z2 < nz and occ[z2 * nx + x2] == 1:
						dn = dist[z2 * nx + x2] + 1
					best = mini(best, dn)
				dist[i] = best
	# window panes: dark, bluish, not too saturated, away from the edge
	var glass := PackedByteArray()
	glass.resize(n)
	var glass_count := 0
	for i in n:
		if occ[i] == 0 or dist[i] < 1:
			continue
		var c: Color = cols[i]
		var mx := maxf(c.r, maxf(c.g, c.b))
		var mn := minf(c.r, minf(c.g, c.b))
		var sat := (mx - mn) / mx if mx > 0.0 else 0.0
		var lum := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
		if mx < 0.45 and c.b > c.r + 0.05 and sat < 0.65 and lum < 0.3:
			glass[i] = 1
			glass_count += 1
	# the cabin: glass columns, and the roof in the largest gap between them
	var gcols := PackedInt32Array()
	for cx in nx:
		for cz in nz:
			if glass[cz * nx + cx] == 1:
				gcols.append(cx)
				break
	var cabin_x0 := int(nx * 0.3)
	var cabin_x1 := int(nx * 0.66)
	var roof_x0 := int(nx * 0.4)
	var roof_x1 := int(nx * 0.52)
	var use_glass := glass_count >= 12 and gcols.size() >= 3
	if use_glass:
		cabin_x0 = gcols[0]
		cabin_x1 = gcols[gcols.size() - 1]
		var gap := 0
		for k in range(1, gcols.size()):
			if gcols[k] - gcols[k - 1] - 1 > gap:
				gap = gcols[k] - gcols[k - 1] - 1
				roof_x0 = gcols[k - 1] + 1
				roof_x1 = gcols[k] - 1
		if gap < 2:  # one pane: the middle third of it is the roof
			var span := cabin_x1 - cabin_x0
			roof_x0 = cabin_x0 + span / 3
			roof_x1 = cabin_x1 - span / 3
	# cabin lateral extent per column (glass rows; the roof spans its neighbours)
	var zlo := PackedInt32Array()
	var zhi := PackedInt32Array()
	zlo.resize(nx)
	zhi.resize(nx)
	for cx in nx:
		zlo[cx] = 99
		zhi[cx] = -1
		for cz in nz:
			var i := cz * nx + cx
			if use_glass:
				if glass[i] == 1:
					zlo[cx] = mini(zlo[cx], cz)
					zhi[cx] = maxi(zhi[cx], cz)
			elif cx >= cabin_x0 and cx <= cabin_x1 and occ[i] == 1 and dist[i] >= 2:
				zlo[cx] = mini(zlo[cx], cz)
				zhi[cx] = maxi(zhi[cx], cz)
	var roof_lo := 99
	var roof_hi := -1
	for cx in [roof_x0 - 1, roof_x1 + 1, roof_x0 - 2, roof_x1 + 2]:
		if cx >= 0 and cx < nx and zhi[cx] >= 0:
			roof_lo = mini(roof_lo, zlo[cx])
			roof_hi = maxi(roof_hi, zhi[cx])
	if roof_hi < 0:
		roof_lo = nz / 2 - 3
		roof_hi = nz / 2 + 2
	for cx in range(roof_x0, roof_x1 + 1):
		zlo[cx] = roof_lo
		zhi[cx] = roof_hi
	# wheel arches (WheelLayout, display px -> cells)
	var at := Vector3(16.5, -16.5, 10.5)
	if layout != null:
		at = layout.positions(body_logical)
	var arches: Array[Vector2] = []
	for ax in [at.x, at.y]:
		for az in [-at.z, at.z]:
			arches.append(Vector2((ax + DISPLAY.x * 0.5) / Vox.CAR_VOXEL_PX, (az + DISPLAY.y * 0.5) / Vox.CAR_VOXEL_PX))
	var g := VoxelGrid.new(Vector3i(nx, CABIN_TOP + 2, nz), voxel_size(), Vector3.ZERO)
	for cz in nz:
		for cx in nx:
			var i := cz * nx + cx
			if occ[i] == 0:
				continue
			var d := dist[i]
			var top := clampi(4 + d, 4, BODY_MAX)
			var bottom := BOTTOM
			for a in arches:
				if absf(cx + 0.5 - a.x) < WHEEL_R + 0.4 and absf(cz + 0.5 - a.y) < WHEEL_W * 0.5 + 0.9:
					bottom = WHEEL_R * 2
					top = maxi(top, bottom + 1)
			var paint: Color = cols[i]
			var base := paint
			if glass[i] == 1:
				base = _body_colour_near(cols, occ, glass, nx, nz, cx, cz)
			for y in range(bottom, top):
				var k := 0.74 + 0.26 * float(y - bottom) / maxf(1.0, float(top - bottom - 1))
				var c := paint if (y == top - 1 and glass[i] == 0) else base * Color(k, k, k)
				g.set_v(cx, y, cz, Vox.SOLID, c)
			if d >= 2 and bottom == BOTTOM:  # chassis between the wheels
				g.set_v(cx, BOTTOM - 1, cz, Vox.SOLID, Color(0.12, 0.11, 0.12))
			# the cabin
			if cx < cabin_x0 or cx > cabin_x1 or cz < zlo[cx] or cz > zhi[cx]:
				continue
			var ctop := CABIN_TOP
			var is_glass := glass[i] == 1 or not use_glass and (cx < roof_x0 or cx > roof_x1)
			if cx < roof_x0:  # rear window rising to the roof
				ctop = int(round(lerpf(CABIN_TOP - 1.6, CABIN_TOP, float(cx - cabin_x0 + 1) / float(maxi(1, roof_x0 - cabin_x0)))))
			elif cx > roof_x1:  # windscreen falling to the bonnet
				ctop = int(round(lerpf(CABIN_TOP, CABIN_TOP - 2.6, float(cx - roof_x1) / float(maxi(1, cabin_x1 - roof_x1)))))
			var edge := cz == zlo[cx] or cz == zhi[cx]
			for y in range(top, ctop):
				var glass_col := Color(0.16, 0.22, 0.3) if not use_glass else (paint if glass[i] == 1 else Color(0.16, 0.22, 0.3))
				if is_glass:
					g.set_v(cx, y, cz, Vox.GLASS, glass_col.lightened(0.08 if y == ctop - 1 else 0.0))
				elif y == ctop - 1:
					g.set_v(cx, y, cz, Vox.SOLID, paint)  # the roof (number roundel)
				elif edge:
					g.set_v(cx, y, cz, Vox.GLASS, Color(0.15, 0.2, 0.27))  # side windows
				else:
					g.set_v(cx, y, cz, Vox.SOLID, base)
	# lamps at the game's anchors (LightingPilot): the nose and the tail
	for side in [-1.0, 1.0]:
		var hz := int((DISPLAY.y * 0.5 + side * LightingPilot.HEAD_LAMP.y) / Vox.CAR_VOXEL_PX)
		var tz := int((DISPLAY.y * 0.5 + side * absf(LightingPilot.TAIL_LAMP.y)) / Vox.CAR_VOXEL_PX)
		var xf := _front_most(occ, nx, nz, hz)
		if xf >= 0:
			for y in [3, 4]:
				g.set_v(xf, y, hz, Vox.HEAD, Color(1.0, 0.92, 0.62))
				g.set_v(xf, y, hz - int(side), Vox.HEAD, Color(1.0, 0.92, 0.62))
		var xr := _rear_most(occ, nx, nz, tz)
		if xr >= 0:
			for y in [3, 4]:
				g.set_v(xr, y, tz, Vox.TAIL, Color(0.75, 0.08, 0.06))
				g.set_v(xr, y, tz - int(side), Vox.TAIL, Color(0.75, 0.08, 0.06))
	var pivot := Vector3(DISPLAY.x, 0.0, DISPLAY.y) * 0.5 * Vox.PX
	return VoxelMesher.build_mesh(g, material(), pivot, 0.05)


static func _front_most(occ: PackedByteArray, nx: int, nz: int, cz: int) -> int:
	cz = clampi(cz, 0, nz - 1)
	for cx in range(nx - 1, -1, -1):
		if occ[cz * nx + cx] == 1:
			return cx
	return -1


static func _rear_most(occ: PackedByteArray, nx: int, nz: int, cz: int) -> int:
	cz = clampi(cz, 0, nz - 1)
	for cx in nx:
		if occ[cz * nx + cx] == 1:
			return cx
	return -1


## Paint under a window pane: the nearest non-glass body cell in its column.
static func _body_colour_near(cols: Array[Color], occ: PackedByteArray, glass: PackedByteArray, nx: int, nz: int, cx: int, cz: int) -> Color:
	for r in range(1, nz):
		for z2 in [cz - r, cz + r]:
			if z2 >= 0 and z2 < nz:
				var i: int = z2 * nx + cx
				if occ[i] == 1 and glass[i] == 0:
					return cols[i]
	return Color(0.5, 0.5, 0.5)


## One voxel wheel (axle along Z, centred): tyre with a chunky tread that
## shows the wheel turning, and a metal hub.
static func wheel_mesh() -> ArrayMesh:
	if _wheel != null:
		return _wheel
	var d := WHEEL_R * 2
	var g := VoxelGrid.new(Vector3i(d, d, WHEEL_W), voxel_size(), Vector3.ZERO)
	for y in d:
		for x in d:
			var p := Vector2(x + 0.5 - WHEEL_R, y + 0.5 - WHEEL_R)
			var r := p.length()
			if r > WHEEL_R + 0.25:
				continue
			for z in WHEEL_W:
				if r < 1.3:
					g.set_v(x, y, z, Vox.METAL, Color(0.74, 0.72, 0.68) if z != 1 else Color(0.4, 0.39, 0.38))
				else:
					var sector := int(floor((p.angle() + PI) / (TAU / 10.0))) % 2
					var c := Color(0.16, 0.15, 0.16) if sector == 0 else Color(0.07, 0.07, 0.08)
					if r < 2.0:
						c = Color(0.22, 0.21, 0.22)
					g.set_v(x, y, z, Vox.SOLID, c)
	_wheel = VoxelMesher.build_mesh(g, material(), Vector3(d, d, WHEEL_W) * 0.5 * voxel_size(), 0.0)
	return _wheel
