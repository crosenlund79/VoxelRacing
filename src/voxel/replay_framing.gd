extends RefCounted
## Action replays: a clear view of the moment. The voxel scenery has no
## physics bodies, so this keeps its own map of what stands around the
## circuit (world boxes of the props, lamp posts, the start gantry, the set
## dressing and every spectator, in a coarse grid) and answers one question
## for the replay director: from this camera position, what stands between
## the lens and the cars, the missile or the explosion?
##
## Two kinds of things get in the way. Big ones (grandstands, buildings, the
## giant toys, seated crowds, the ground itself and its barriers) stay: the
## director moves the camera instead. Small clutter (trees, bushes, rocks,
## lamp posts, flags, boards, fences, standing spectators, the gantry) is
## tidied away while the shot lasts and put back at the next cut.

## Grid cell (3D units) of the occluder map.
const CELL := 6.0
## Set dressing kinds that are buildings: never hidden, the camera moves.
const BIG_KINDS := ["barn", "cottage", "windmill", "cabin", "pit_garages", "tent", "shed", "containers", "container",
	"screen", "stall", "duck", "mug", "blocks", "robot", "ambulance", "tow_truck"]
## Props that are buildings or giant toys (VoxelProps.Kind): never hidden.
const BIG_PROPS := [VoxelProps.Kind.STAND, VoxelProps.Kind.PIT, VoxelProps.Kind.CUP, VoxelProps.Kind.DICE,
	VoxelProps.Kind.SLAB]
## Anything else with a footprint or height beyond this (units) counts as big.
const BIG_SIZE := 9.0
const BIG_HEIGHT := 6.5

var stage: Node3D
var vtrack: Node3D
var built := false
## Per box: its world AABB, whether it is big, and its item.
var _boxes: Array[AABB] = []
var _big := PackedByteArray()
var _item_of := PackedInt32Array()
## Items: {"node": Node3D} or {"mm": MultiMesh, "i": int, "xf": Transform3D}.
var _items: Array[Dictionary] = []
var _grid: Dictionary = {}
var _hidden: Dictionary = {}  # item index -> true


func setup(p_stage: Node3D) -> void:
	stage = p_stage
	vtrack = stage.get("vtrack")


## The occluder map; built once, when the first replay starts (the world is
## complete by then).
func build() -> void:
	if built:
		return
	built = true
	var props := stage.get_node_or_null("Props")
	if props != null:
		var kinds := _prop_kinds()
		for n in props.get_children():
			var mi := n as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			var kind: int = kinds.get(mi.mesh.get_instance_id(), -1)
			if mi.mesh.has_meta("grandstand") or kind in BIG_PROPS:
				_add_node(mi, true)
			elif kind >= 0:
				_add_node(mi, false, false)  # vegetation, posts, boards: tidied away, whatever their size
			else:
				_add_node(mi, false)
	var lamps := stage.get_node_or_null("Lamps")
	if lamps != null:
		for n in lamps.get_children():
			if n is MeshInstance3D:
				_add_node(n, false, false)  # (tall, but thin: tidied away)
	var gantry := stage.get_node_or_null("StartLights") as MeshInstance3D
	if gantry != null and gantry.mesh != null:
		_add_gantry(gantry)
	var life: Node = stage.get("life")
	if life != null:
		var dressing := life.get_node_or_null("Dressing")
		if dressing != null:
			for n in dressing.get_children():
				if n is MeshInstance3D:
					_add_node(n, String(n.get_meta("kind", "")) in BIG_KINDS)
		var people = life.get("_people")
		if people is Array:
			for person in people:
				if not (person is Dictionary) or not person.has("mm"):
					continue
				var mm: MultiMesh = person.mm
				var i := int(person.i)
				if mm == null or mm.mesh == null or i >= mm.instance_count:
					continue
				var xf := mm.get_instance_transform(i)
				var item := _items.size()
				_items.append({"mm": mm, "i": i, "xf": xf})
				# seated spectators belong to their stand: never hidden
				_add_box((xf * mm.mesh.get_aabb()).grow(0.08), person.has("seat"), item)
		# Tabletop Mayhem's toys (VoxelToybox, P007): tall ones are scenery the
		# camera works around, little ones are clutter it may hide
		var toys := life.get_node_or_null("Toybox")
		if toys != null:
			for n in toys.get_children():
				_add_toys(n)


## VoxelProps kind of each prop mesh (from its mesh cache, keyed by the
## drawing's logical name).
func _prop_kinds() -> Dictionary:
	var out := {}
	var cache = (load("res://src/voxel/voxel_props.gd") as GDScript).get("_meshes")
	if not (cache is Dictionary):
		return out
	for key in cache:
		var mesh = cache[key]
		if mesh is Mesh:
			out[(mesh as Mesh).get_instance_id()] = VoxelProps.kind_of(String(key).get_slice("|", 0))
	return out


func _add_node(mi: MeshInstance3D, big: bool, by_size := true) -> void:
	var box := _world_aabb(mi)
	if box.size == Vector3.ZERO:
		return
	if by_size and (maxf(box.size.x, box.size.z) > BIG_SIZE or box.size.y > BIG_HEIGHT):
		big = true
	var item := _items.size()
	_items.append({"node": mi})
	_add_box(box, big, item)


func _add_toys(n: Node) -> void:
	var gxf := (n as Node3D).global_transform if n is Node3D else Transform3D.IDENTITY
	if n is MultiMeshInstance3D:
		var mm := (n as MultiMeshInstance3D).multimesh
		if mm == null or mm.mesh == null:
			return
		for i in mm.instance_count:
			var xf := mm.get_instance_transform(i)
			var box := gxf * (xf * mm.mesh.get_aabb())
			var item := _items.size()
			_items.append({"mm": mm, "i": i, "xf": xf})
			_add_box(box.grow(0.05), box.size.y > 0.9 or maxf(box.size.x, box.size.z) > BIG_SIZE, item)
	elif n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		_add_node(n, false)
	for c in n.get_children():
		_add_toys(c)


## The start gantry is an arch: its two posts and the beam, not one box
## (the road under it stays clear).
func _add_gantry(g: MeshInstance3D) -> void:
	var a := g.mesh.get_aabb()
	var item := _items.size()
	_items.append({"node": g})
	var post := minf(a.size.x * 0.12, 0.6)
	var parts := [AABB(a.position, Vector3(post, a.size.y, a.size.z)),
		AABB(a.position + Vector3(a.size.x - post, 0, 0), Vector3(post, a.size.y, a.size.z)),
		AABB(a.position + Vector3(0, a.size.y * 0.72, 0), Vector3(a.size.x, a.size.y * 0.28, a.size.z))]
	for p in parts:
		_add_box(g.global_transform * (p as AABB), false, item)


func _world_aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var c := stack.pop_back() as Node
		var gi := c as VisualInstance3D
		if gi != null and (gi is MeshInstance3D or gi is MultiMeshInstance3D):
			var b := gi.global_transform * gi.get_aabb()
			if b.size != Vector3.ZERO:
				out = b if first else out.merge(b)
				first = false
		for ch in c.get_children():
			if ch is Node3D:
				stack.append(ch)
	return out


func _add_box(box: AABB, big: bool, item: int) -> void:
	var k := _boxes.size()
	_boxes.append(box)
	_big.append(1 if big else 0)
	_item_of.append(item)
	var c0 := Vector2i(floori(box.position.x / CELL), floori(box.position.z / CELL))
	var c1 := Vector2i(floori(box.end.x / CELL), floori(box.end.z / CELL))
	for x in range(c0.x, c1.x + 1):
		for z in range(c0.y, c1.y + 1):
			var key := Vector2i(x, z)
			var list: PackedInt32Array = _grid.get(key, PackedInt32Array())
			list.append(k)
			_grid[key] = list  # (packed arrays are values: store it back)


func _candidates(lo: Vector3, hi: Vector3) -> PackedInt32Array:
	var out := PackedInt32Array()
	var seen := {}
	var c0 := Vector2i(floori(lo.x / CELL), floori(lo.z / CELL))
	var c1 := Vector2i(floori(hi.x / CELL), floori(hi.z / CELL))
	for x in range(c0.x, c1.x + 1):
		for z in range(c0.y, c1.y + 1):
			var list = _grid.get(Vector2i(x, z))
			if list == null:
				continue
			for k in (list as PackedInt32Array):
				if not seen.has(k):
					seen[k] = true
					out.append(k)
	return out


## What blocks the view from `eye` to the subject points `pts` (each
## [Vector3 point, float weight, owner car id]). `look` and `fov` describe the shot, for
## the clutter right in front of the lens. Returns {"cost": weighted share
## of blocked sight lines that only moving the camera can fix (0 = clear,
## 100+ = the camera stands inside something), "small": item ids to tidy
## away}. `movers`: [AABB, car id] of things that cannot be tidied away
## either (the other cars in the race; a car never blocks its own points).
func probe(eye: Vector3, pts: Array, look: Vector3, fov: float, clutter := true, movers: Array = []) -> Dictionary:
	var lo := eye
	var hi := eye
	for sp in pts:
		var p: Vector3 = sp[0]
		lo = lo.min(p)
		hi = hi.max(p)
	var cand := _candidates(lo - Vector3.ONE, hi + Vector3.ONE)
	var small := {}
	var cost := 0.0
	# the lens inside a building or a stand
	for k in cand:
		if _boxes[k].grow(0.15).has_point(eye):
			if _big[k] == 1:
				cost += 100.0
			else:
				small[_item_of[k]] = true
	for mv in movers:
		if (mv[0] as AABB).has_point(eye):
			cost += 100.0
	# sight lines to the subjects
	for sp in pts:
		var p: Vector3 = sp[0]
		var w: float = sp[1]
		var d := p - eye
		var dist := d.length()
		if dist < 0.05:
			continue
		var stop := eye + d * maxf(0.0, (dist - 0.3) / dist)
		var big_hit := _terrain_blocks(eye, stop)
		for k in cand:
			if _boxes[k].intersects_segment(eye, stop) != null:
				if _big[k] == 1:
					big_hit = true
				else:
					small[_item_of[k]] = true
		if not big_hit:
			var owner: int = sp[2] if sp.size() > 2 else -1
			for mv in movers:
				if int(mv[1]) != owner and (mv[0] as AABB).intersects_segment(eye, stop) != null:
					big_hit = true
					break
		if big_hit:
			cost += w
	# clutter in the foreground: the near part of the frame (its corners and
	# lower half, where a car parked by the lens would fill the picture)
	if eye.distance_to(look) > 0.1:
		var f := (look - eye).normalized()
		var r := f.cross(Vector3.UP)
		r = r.normalized() if r.length() > 0.01 else Vector3.RIGHT
		var u := r.cross(f)
		var tv := tan(deg_to_rad(fov) * 0.5) * 0.8
		var th := tv * 16.0 / 9.0
		cost += _near_ground(eye, f, r, u, th, tv, minf(4.2, eye.distance_to(look) * 0.45))
		var reach := minf(4.5, eye.distance_to(look) * 0.55)
		# small clutter anywhere in front of the subject (a long lens makes
		# spectators 5 units away fill the picture)
		var far := eye.distance_to(look) * 0.7
		var near_c := _candidates(eye - Vector3.ONE * (far + 1.0), eye + Vector3.ONE * (far + 1.0)) if clutter else PackedInt32Array()
		for o: Vector2 in [Vector2(-1, -0.7), Vector2(1, -0.7), Vector2(-1, 0.7), Vector2(1, 0.7), Vector2(0, -0.9), Vector2(0, 0),
				Vector2(-0.5, -0.4), Vector2(0.5, -0.4), Vector2(-1, 0), Vector2(1, 0), Vector2(-1.2, -0.3), Vector2(1.2, -0.3),
				Vector2(-0.5, 0.3), Vector2(0.5, 0.3), Vector2(-0.25, -0.75), Vector2(0.25, -0.75)]:
			var dir := (f + r * th * o.x + u * tv * o.y).normalized()
			var end := eye + dir * reach
			var end_far := eye + dir * far
			for mv in movers:
				if (mv[0] as AABB).intersects_segment(eye, end) != null:
					cost += 0.3  # another car right in front of the lens
					break
			for k in near_c:
				if _big[k] == 1:
					if _boxes[k].intersects_segment(eye, end) != null:
						cost += 0.15  # a wall filling a corner of the frame
				elif _boxes[k].intersects_segment(eye, end_far) != null:
					small[_item_of[k]] = true
	return {"cost": cost, "small": small.keys()}


func _h(p: Vector3) -> float:
	return vtrack.height_px_at(Vector2(p.x, p.z) / Vox.PX) * Vox.PX


## The ground right in front of the lens: a barrier (or a hill crest) there
## fills the bottom of the picture. A cost for each frame ray that runs into
## ground raised above the lens's surroundings.
func _near_ground(eye: Vector3, f: Vector3, r: Vector3, u: Vector3, th: float, tv: float, reach: float) -> float:
	if vtrack == null or not vtrack.has_method("height_px_at"):
		return 0.0
	var base := _h(eye)
	for k in 8:
		var a := k * TAU / 8.0
		base = minf(base, _h(eye + Vector3(cos(a), 0.0, sin(a)) * 1.6))
	var cost := 0.0
	for o: Vector2 in [Vector2(-1, -0.7), Vector2(1, -0.7), Vector2(0, -0.9), Vector2(-0.5, -0.4), Vector2(0.5, -0.4),
			Vector2(-1, 0), Vector2(1, 0), Vector2(0, 0)]:
		var dir := (f + r * th * o.x + u * tv * o.y).normalized()
		var s := 0.3
		while s <= reach:
			var p := eye + dir * s
			var h := _h(p)
			if h > base + 0.3 and h > p.y:
				cost += 0.25
				break
			s += 0.25
	return cost


## True where the ground (hills, barriers, kerbs) rises above the segment.
func _terrain_blocks(a: Vector3, b: Vector3) -> bool:
	if vtrack == null or not vtrack.has_method("height_px_at"):
		return false
	var steps := int(a.distance_to(b) / 0.22)
	if steps < 2:
		return false
	for s in range(1, steps):
		var t := float(s) / steps
		if t > 0.94:
			break
		var p := a.lerp(b, t)
		var h: float = vtrack.height_px_at(Vector2(p.x, p.z) / Vox.PX) * Vox.PX
		if h > p.y + 0.02:
			return true
	return false


## Tidy the given items away (until restore_all).
func hide_items(ids: Array) -> void:
	for id in ids:
		var item := int(id)
		if _hidden.has(item):
			continue
		var it: Dictionary = _items[item]
		if it.has("node"):
			var n := it.node as Node3D
			if not is_instance_valid(n) or not n.visible:
				continue
			n.visible = false
		else:
			var mm: MultiMesh = it.mm
			if not is_instance_valid(mm):
				continue
			mm.set_instance_transform(int(it.i), Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), (it.xf as Transform3D).origin))
		_hidden[item] = true


## Everything tidied away comes back.
func restore_all() -> void:
	for item in _hidden.keys():
		var it: Dictionary = _items[int(item)]
		if it.has("node"):
			if is_instance_valid(it.node):
				(it.node as Node3D).visible = true
		elif is_instance_valid(it.mm):
			(it.mm as MultiMesh).set_instance_transform(int(it.i), it.xf)
	_hidden.clear()
