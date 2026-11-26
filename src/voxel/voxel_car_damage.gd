class_name VoxelCarDamage
extends RefCounted
## VoxelRacing: a car's bodywork coming apart, voxel by voxel.
##
## Each car keeps its own copy of its pristine voxel model. The race's own
## damage state (DamageWorld condition) sets how much of the body is gone;
## the voxels that go are chosen on the surface, nearest the side that was
## hit (wall normal, the other car, the weapon blast), in small clusters, and
## become debris with their real colours. What they expose is the car's
## inside, scorched a little. Lamps break with their bodywork (the car's
## lights follow). Repairs / respawns restore the model.
##
## Presentation only: it never changes the race's damage.

## Share of the body gone at zero condition (the car stays recognisable).
const MAX_LOSS := 0.42
## Damage starts to show below this condition share.
const SHOW_FROM := 0.97
const SCORCH := Color(0.16, 0.13, 0.11)

var pristine: VoxelGrid
var grid: VoxelGrid
var mesh_instance: MeshInstance3D
var solids := PackedInt32Array()  ## interior indices of breakable voxels
var total := 0
var removed := 0
var dirty := false
var wrecked := false
## Lamps left, per side (front-left, front-right, rear-left, rear-right).
var lamps := PackedInt32Array([0, 0, 0, 0])
var _rng := RandomNumberGenerator.new()
var _hull: ArrayMesh


func _init(p_pristine: VoxelGrid, p_mesh_instance: MeshInstance3D, seed_value: int) -> void:
	pristine = p_pristine
	mesh_instance = p_mesh_instance
	_rng.seed = seed_value
	restore()


## Back to the undamaged model.
func restore() -> void:
	grid = pristine.copy()
	solids.clear()
	var sz := grid.size()
	for y in sz.y:
		for z in sz.z:
			for x in sz.x:
				var m := grid.get_m(x, y, z)
				if m != Vox.AIR and y >= VoxelCars.BOTTOM:  # the chassis plate never breaks
					solids.append(_idx(x, y, z))
	total = solids.size()
	removed = 0
	wrecked = false
	_count_lamps()
	dirty = true


func loss() -> float:
	return float(removed) / maxf(1.0, float(total))


## Target share of bodywork gone for a condition share (1 = healthy).
static func target_loss(condition_share: float) -> float:
	if condition_share >= SHOW_FROM:
		return 0.0
	return clampf((SHOW_FROM - condition_share) / SHOW_FROM, 0.0, 1.0) * MAX_LOSS


## Breaks voxels until `target` of the body is gone, nearest `toward` (a unit
## direction in the car's model space: +X nose, +Z right). Returns the voxels
## that broke away: [[model position, colour], ...].
func break_to__perf(target: float, toward: Vector3) -> Array:
	var out: Array = []
	var want := int(target * total) - removed
	if want <= 0 or solids.is_empty():
		return out
	var sz := grid.size()
	var centre := Vector3(sz.x, sz.y * 0.6, sz.z) * 0.5
	var dir := toward.normalized() if toward.length() > 0.01 else Vector3(_rng.randf_range(-1, 1), 0.3, _rng.randf_range(-1, 1)).normalized()
	var guard := 0
	while want > 0 and guard < 40 and not solids.is_empty():
		guard += 1
		# sample candidates, keep exposed ones facing the hit
		var best := -1
		var best_score := -INF
		for k in 24:
			var si := _rng.randi_range(0, solids.size() - 1)
			var cell := _cell(solids[si])
			if not _exposed(cell):
				continue
			var p := (Vector3(cell) + Vector3(0.5, 0.5, 0.5) - centre)
			var score := p.normalized().dot(dir) * 2.0 + p.length() * 0.05 + _rng.randf() * 0.9
			if score > best_score:
				best_score = score
				best = si
		if best < 0:
			continue
		# a small cluster around it
		var seed_cell := _cell(solids[best])
		var cluster := [seed_cell]
		for o in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			if cluster.size() >= 1 + _rng.randi_range(0, 3):
				break
			var c2: Vector3i = seed_cell + o
			if _breakable(c2):
				cluster.append(c2)
		for c in cluster:
			if want <= 0:
				break
			var cell: Vector3i = c
			var col := grid.get_c(cell.x, cell.y, cell.z)
			out.append([_model_pos(cell), col])
			grid.set_v(cell.x, cell.y, cell.z, Vox.AIR, Color.BLACK)
			var at := solids.find(_idx(cell.x, cell.y, cell.z))
			if at >= 0:
				solids.remove_at(at)
			removed += 1
			want -= 1
			_scorch_around(cell)
	if not out.is_empty():
		_count_lamps()
		dirty = true
	return out


## Everything that is left flies apart (destruction). Voxels come in 2x2x2
## chunks (fewer, chunkier pieces) with their dominant colour, plus single
## glowing embers. Returns [[model position, colour, size in voxels], ...].
func explode() -> Array:
	var out: Array = []
	var sz := grid.size()
	for y in range(0, sz.y, 2):
		for z in range(0, sz.z, 2):
			for x in range(0, sz.x, 2):
				var n := 0
				var first := Color.BLACK
				var cols := {}
				for dy in 2:
					for dz in 2:
						for dx in 2:
							var m := grid.get_m(x + dx, y + dy, z + dz)
							if m == Vox.AIR:
								continue
							n += 1
							var c := grid.get_c(x + dx, y + dy, z + dz)
							var key := c.to_html(false)
							cols[key] = int(cols.get(key, 0)) + 1
							if n == 1:
								first = c
				if n == 0:
					continue
				var best := first
				var best_n := 0
				for key in cols:
					if cols[key] > best_n:
						best_n = cols[key]
						best = Color.html(key)
				var size := 2.0 if n >= 4 else 1.2
				out.append([_model_pos(Vector3i(x, y, z)) + Vector3.ONE * grid.vs * 0.5, best, size])
	wrecked = true
	return out


## The burnt-out remains after an explosion: the chassis plate and a few
## charred stumps (shared per car).
func hull_mesh() -> ArrayMesh:
	if _hull != null:
		return _hull
	var h := pristine.copy()
	var sz := h.size()
	for y in sz.y:
		for z in sz.z:
			for x in sz.x:
				if h.get_m(x, y, z) == Vox.AIR:
					continue
				var keep := y < VoxelCars.BOTTOM + 1 or (y < VoxelCars.BOTTOM + 3 and Vox.hash3(x, y, z) > 0.55)
				if keep:
					var g := 0.1 + 0.08 * Vox.hash3(x, 3, z)
					h.set_v(x, y, z, Vox.SOLID, Color(g * 1.2, g, g * 0.9))
				else:
					h.set_v(x, y, z, Vox.AIR, Color.BLACK)
	_hull = VoxelMesher.build_mesh(h, VoxelCars.material(), VoxelCars.pivot(), 0.1)
	return _hull


## Rebuilds the mesh if the model changed (call at most a few times a frame).
func rebuild__perf() -> void:
	if not dirty:
		return
	dirty = false
	if wrecked:
		mesh_instance.mesh = hull_mesh()
	else:
		mesh_instance.mesh = VoxelMesher.build_mesh(grid, VoxelCars.material(), VoxelCars.pivot(), 0.05)


func _idx(x: int, y: int, z: int) -> int:
	var sz := grid.size()
	return (y * sz.z + z) * sz.x + x


func _cell(i: int) -> Vector3i:
	var sz := grid.size()
	return Vector3i(i % sz.x, i / (sz.x * sz.z), (i / sz.x) % sz.z)


func _breakable(c: Vector3i) -> bool:
	return c.y >= VoxelCars.BOTTOM and grid.get_m(c.x, c.y, c.z) != Vox.AIR


func _exposed(c: Vector3i) -> bool:
	for o in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var n: Vector3i = c + o
		if grid.get_m(n.x, n.y, n.z) == Vox.AIR:
			return true
	return false


## Newly exposed inside: darker, a little burnt (only where it was hidden).
func _scorch_around(c: Vector3i) -> void:
	for o in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var n: Vector3i = c + o
		var m := grid.get_m(n.x, n.y, n.z)
		if m == Vox.AIR or m == Vox.HEAD or m == Vox.TAIL:
			continue
		if _rng.randf() < 0.55:
			var col := grid.get_c(n.x, n.y, n.z)
			grid.set_v(n.x, n.y, n.z, Vox.SOLID if m != Vox.GLASS else m, col.lerp(SCORCH, 0.45))


func _model_pos(c: Vector3i) -> Vector3:
	return grid.origin + (Vector3(c) + Vector3.ONE * 1.5) * grid.vs - VoxelCars.pivot()


func _count_lamps() -> void:
	lamps = PackedInt32Array([0, 0, 0, 0])
	var sz := grid.size()
	for y in sz.y:
		for z in sz.z:
			for x in sz.x:
				var m := grid.get_m(x, y, z)
				if m == Vox.HEAD:
					lamps[0 if z < sz.z / 2 else 1] += 1
				elif m == Vox.TAIL:
					lamps[2 if z < sz.z / 2 else 3] += 1


## DIAGNOSTIC probe (Performance Investigation 001)
func rebuild() -> void:
	var __t := Time.get_ticks_usec()
	rebuild__perf()
	PerfProbe.add(&"pres.car_remesh", __t)


## DIAGNOSTIC probe (Performance Investigation 001)
func break_to(target: float, toward: Vector3) -> Array:
	var __t := Time.get_ticks_usec()
	var __r = break_to__perf(target, toward)
	PerfProbe.add(&"pres.car_break", __t)
	return __r
