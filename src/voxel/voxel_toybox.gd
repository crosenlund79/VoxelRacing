class_name VoxelToybox
extends Node3D
## VoxelRacing: Tabletop Mayhem's toy box. The giant desk around the circuit
## (and around the Battle Royale yard) is strewn with oversized toys and desk
## things for the tiny racing cars: building bricks and brick towers, tin
## soldiers on parade, dice, playing cards fanned out and a house of cards,
## pencils with an eraser and a ruler, crayons and their box, a domino run
## that has started to topple, jigsaw pieces, marbles, spinning tops (they
## spin), little traffic signs and cones, letter blocks, a toy rocket on its
## pad and a toy town.
##
## Built from code in the established voxel style (VoxelGrid + VoxelMesher +
## VoxelCars.material()), one mesh per kind, cached and shared; repeated
## pieces of a kind are drawn as one MultiMesh. Placed as small scenes
## ("vignettes") on open desk only: never on anything drivable, clear of the
## barriers, stands, lamps, spectators and other scenery, low things near the
## road and tall things further out - and never where they would stand
## between the camera (which looks north) and the road. Purely visual: no
## physics bodies, and the race never sees any of it.

const C := VoxelKit.C
## Display scale per kind (the toys are oversized next to the cars).
const SCALE := {"die": 1.7, "die_red": 1.7, "card_heart": 1.6, "card_diamond": 1.6, "card_spade": 1.6,
	"card_back": 1.6, "card_house": 1.3, "pencil": 1.6, "pencil_sky": 1.6, "pencil_green": 1.6,
	"pencil_purple": 1.6, "crayon_0": 1.6, "crayon_1": 1.6, "crayon_2": 1.6, "crayon_3": 1.6, "crayon_4": 1.6,
	"crayon_box": 1.6, "eraser": 1.6, "ruler": 1.6, "brick_0": 1.6, "brick_1": 1.6, "brick_2": 1.6,
	"brick_3": 1.6, "brick_4": 1.6, "brick_5": 1.6, "brick_tower": 1.5, "soldier": 1.5, "drummer": 1.5,
	"domino_0": 1.25, "domino_1": 1.25, "domino_2": 1.25, "puzzle_0": 1.6, "puzzle_1": 1.6, "puzzle_2": 1.6,
	"puzzle_3": 1.6, "cone": 1.4, "sign_noentry": 1.4, "sign_yield": 1.4, "sign_arrow": 1.4, "sign_speed": 1.4,
	"sign_warn": 1.4, "rocket": 1.5, "top_0": 1.6, "top_1": 1.6, "marble_0": 1.2, "marble_1": 1.2,
	"marble_2": 1.2, "marble_3": 1.2, "marble_4": 1.2, "abc_0": 1.7, "abc_1": 1.7, "abc_2": 1.7,
	"house_0": 1.6, "house_1": 1.6, "house_2": 1.6, "tower": 1.5,
	"kit:duck": 2.4, "kit:mug": 2.2, "kit:robot": 2.1, "kit:blocks": 1.9}
## Kinds with lit windows (glow at night).
const GLOWS := ["house_0", "house_1", "house_2", "tower", "rocket", "kit:robot"]
## Spinning tops spin (individual nodes, not batched).
const SPINS := ["top_0", "top_1"]
## Vignettes per environment: [name, count]. Circuits scale with their length.
const CIRCUIT_SET := [["town", 2], ["rocket", 1], ["card_house", 1], ["brick_tower", 2], ["parade", 2],
	["traffic", 4], ["abc", 3], ["crayons", 3], ["dice", 4], ["domino", 3], ["desk", 3], ["cards", 4],
	["bricks", 3], ["puzzle", 3], ["marbles", 4], ["tops", 2]]
const ARENA_SET := [["town", 2], ["rocket", 2], ["card_house", 2], ["brick_tower", 2], ["robots", 2],
	["duck", 1], ["parade", 3], ["traffic", 4], ["abc", 4], ["crayons", 3], ["dice", 5], ["dice_tower", 1],
	["mug", 1], ["domino", 4], ["desk", 4], ["cards", 5], ["bricks", 4], ["puzzle", 4], ["marbles", 5],
	["tops", 3]]
## How far from the road edge (px) a vignette may stand, by height class.
const BANDS := {"low": Vector2(44.0, 300.0), "mid": Vector2(96.0, 480.0), "tall": Vector2(220.0, 720.0)}
## Single pieces strewn along the walls / road edges (lying along them, never
## crossing): [kind, long axis is X].
const STRAYS := [["pencil", true], ["pencil_sky", true], ["pencil_green", true], ["pencil_purple", true],
	["crayon_0", true], ["crayon_1", true], ["crayon_2", true], ["crayon_3", true], ["crayon_4", true],
	["ruler", true], ["eraser", true], ["brick_0", false], ["brick_1", false], ["brick_3", false],
	["brick_4", false], ["card_back", false], ["card_heart", false], ["card_spade", false],
	["card_diamond", false], ["puzzle_1", false], ["puzzle_2", false], ["cone", false], ["marble_0", false],
	["marble_2", false], ["marble_4", false]]
## Screen-space reach of height when the camera looks north (px of ground per
## px of height at the steepest preset pitch: cos / sin of ~58 degrees, with a
## margin for the lower presets).
const LEAN := 0.7

static var _meshes: Dictionary = {}

var life: VoxelLife
var stage: VoxelStage
var vtrack: VoxelTrack
var _rng := RandomNumberGenerator.new()
var _batches: Dictionary = {}  # kind -> Array[Transform3D]
var _tops: Array = []  # [holder, spinner, phase]
var _time := 0.0
var placed_vignettes := 0
var placed_pieces := 0
## Everything is placed (the meshes and the placement take a few frames).
var done := false


static func mesh(kind: String) -> ArrayMesh:
	if not _meshes.has(kind):
		_meshes[kind] = VoxelKit.mesh(kind.substr(4)) if kind.begins_with("kit:") else _build(kind)
	return _meshes[kind]


## Dresses the desk (life: the circuit's VoxelLife, for its free-ground test
## and its record of occupied spots). Meshes are built a slice per frame, so
## the loading screen keeps animating.
func setup(p_life: VoxelLife) -> void:
	life = p_life
	stage = life.stage
	vtrack = life.vtrack
	name = "Toybox"
	_rng.seed = life._rng.seed + 5
	var arena: bool = life.main.track is Arena
	var plan: Array = []
	var factor := 1.6  # (the arena's desk is all open ground: more of everything)
	if not arena:
		var cl: PackedVector2Array = life.main.track.centerline
		var length := 0.0
		for k in cl.size():
			length += cl[k].distance_to(cl[(k + 1) % cl.size()])
		factor = clampf(length / 8000.0, 0.7, 1.5)
	for entry in (ARENA_SET if arena else CIRCUIT_SET):
		for n in maxi(1, int(round(float(entry[1]) * factor))):
			plan.append(_vignette(entry[0], _rng.randi()))
	# the meshes first (cached for the session), a few per frame
	var kinds: Dictionary = {}
	for st in STRAYS:
		kinds[st[0]] = true
	for items in plan:
		for it in items:
			kinds[it.kind] = true
	var t := Time.get_ticks_usec()
	for kind in kinds:
		if not _meshes.has(kind):
			mesh(kind)
			if Time.get_ticks_usec() - t > 10000:
				await get_tree().process_frame
				if not is_inside_tree():
					return
				t = Time.get_ticks_usec()
	for o in life._occupied:  # (spectators, set dressing, lamps; then the big props in full)
		_occ_add(o[0], o[1])
	_occupy_props()
	# tall scenes first (they need the most room), then mid, then low
	var by_tier := {"tall": [], "mid": [], "low": []}
	for items in plan:
		by_tier[_tier(items)].append(items)
	t = Time.get_ticks_usec()
	var work := 0
	var frames := 0
	for tier in ["tall", "mid", "low"]:
		for items in by_tier[tier]:
			_place(items, tier, arena)
			if Time.get_ticks_usec() - t > 6000:
				work += Time.get_ticks_usec() - t
				frames += 1
				await get_tree().process_frame
				if not is_inside_tree():
					return
				t = Time.get_ticks_usec()
	_strays(arena)
	_commit()
	work += Time.get_ticks_usec() - t
	done = true
	print("VoxelToybox: %d of %d scenes, %d pieces, placed in %d ms over %d frames" % [placed_vignettes, plan.size(), placed_pieces, work / 1000, frames + 1])


## Occupied ground (px circles), bucketed for quick lookups.
const OCC_CELL := 128.0
var _occ: Dictionary = {}


func _occ_add(p: Vector2, r: float) -> void:
	var a := Vector2i(((p - Vector2(r, r)) / OCC_CELL).floor())
	var b := Vector2i(((p + Vector2(r, r)) / OCC_CELL).floor())
	for cy in range(a.y, b.y + 1):
		for cx in range(a.x, b.x + 1):
			var key := Vector2i(cx, cy)
			if not _occ.has(key):
				_occ[key] = []
			_occ[key].append([p, r])


func _occ_hit(p: Vector2, r: float) -> bool:
	var a := Vector2i(((p - Vector2(r, r)) / OCC_CELL).floor())
	var b := Vector2i(((p + Vector2(r, r)) / OCC_CELL).floor())
	for cy in range(a.y, b.y + 1):
		for cx in range(a.x, b.x + 1):
			for o in _occ.get(Vector2i(cx, cy), []):
				if p.distance_to(o[0]) < r + float(o[1]):
					return true
	return false


## Open desk for a circle (px): VoxelLife's test (nothing drivable, no barrier,
## inside the world, no stand), with the occupied ground looked up in buckets.
func _free(p: Vector2, r: float) -> bool:
	if not life._inside(p, r + 8.0):
		return false
	if vtrack.class_at(p) != VoxelTrack.C_GRASS or vtrack.drivable_at(p):
		return false
	for k in 8:
		for q in [p + Vector2.from_angle(k * TAU / 8.0) * r, p + Vector2.from_angle(k * TAU / 8.0 + 0.4) * r * 0.5]:
			if vtrack.class_at(q) != VoxelTrack.C_GRASS or vtrack.drivable_at(q):
				return false
	if _occ_hit(p, r):
		return false
	return not life._in_stand(p, r)


## The environment's own big props (the 2D landmarks' giant pencils, cards and
## dice) keep their whole footprint free, not just a spot at their centre.
func _occupy_props() -> void:
	var props := stage.get_node_or_null("Props")
	if props == null:
		return
	for n in props.get_children():
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var a := mi.mesh.get_aabb()
		var sx := a.size.x * absf(mi.scale.x) / Vox.PX
		var sz := a.size.z * absf(mi.scale.z) / Vox.PX
		if maxf(sx, sz) < 70.0:
			continue
		var c := Vector2(mi.position.x, mi.position.z) / Vox.PX
		var bx := mi.transform.basis.x
		var ax := Vector2(bx.x, bx.z).normalized()
		var along := ax if sx >= sz else Vector2(-ax.y, ax.x)
		var half_long := maxf(sx, sz) * 0.5
		var half_short := maxf(minf(sx, sz) * 0.5, 12.0)
		var steps := int(ceil(half_long / half_short))
		for i in range(-steps, steps + 1):
			_occ_add(c + along * half_long * float(i) / steps, half_short + 8.0)


func _process(delta: float) -> void:
	_time += delta
	for tp in _tops:
		var ph: float = tp[2]
		# a slow wobble (precession) and a fast spin
		(tp[0] as Node3D).rotation = Vector3(sin(_time * 1.7 + ph) * 0.07, 0.0, cos(_time * 1.7 + ph) * 0.07)
		(tp[1] as Node3D).rotate_y(delta * 13.0)


# ------------------------------------------------------------ placement

## Size of a kind (px): [footprint radius, height].
func _dims(kind: String, sc: float) -> Vector2:
	var aabb := mesh(kind).get_aabb()
	var s: float = float(SCALE.get(kind, 1.5)) * sc / Vox.PX
	var rx := maxf(absf(aabb.position.x), absf(aabb.end.x))
	var rz := maxf(absf(aabb.position.z), absf(aabb.end.z))
	return Vector2(Vector2(rx, rz).length() * s, aabb.end.y * s)


## A vignette's radius and height (px).
func _extent(items: Array) -> Vector2:
	var r := 0.0
	var h := 0.0
	for it in items:
		var d := _dims(it.kind, it.get("scale", 1.0))
		r = maxf(r, (it.off as Vector2).length() + d.x)
		h = maxf(h, d.y + float(it.get("lift", 0.0)))
	return Vector2(r, h)


func _tier(items: Array) -> String:
	var h := _extent(items).y
	return "low" if h < 46.0 else ("mid" if h < 135.0 else "tall")


func _place(items: Array, tier: String, arena: bool) -> void:
	var ext := _extent(items)
	var band: Vector2 = BANDS[tier] * Vector2(1.0, 1.3 if arena else 1.0)
	var core := ext.x * 0.55
	for attempt in 90:
		var p := Vector2.ZERO
		if arena:
			var at := _arena_edge()
			p = (at[0] as Vector2) + (at[1] as Vector2) * (_rng.randf_range(band.x, band.y) + core)
		else:
			var cl: PackedVector2Array = life.main.track.centerline
			var f := life._frame(_rng.randi_range(0, cl.size() - 1), 1.0 if _rng.randf() < 0.5 else -1.0)
			p = (f[0] as Vector2) + (f[2] as Vector2) * (float(f[3]) + _rng.randf_range(band.x, band.y) + core)
		if not _free(p, 16.0):
			continue
		var rot := _rng.randf() * TAU
		var pieces: Array = []  # [kind, transform, footprint circles]
		var ok := true
		for i in items.size():
			var piece := _piece(items[i], p, rot, minf(band.x, 70.0))
			if piece.is_empty():
				if i == 0 or items.size() <= 2:
					ok = false
					break
				continue  # (a stray piece of the scene may be left out)
			pieces.append(piece)
		if not ok or pieces.size() * 10 < items.size() * 6:
			continue
		for pc in pieces:
			_add(pc[0], pc[1])
			for c in pc[2]:
				_occ_add(c[0], float(c[1]) + 6.0)
		placed_vignettes += 1
		return


## One piece of a scene at p (scene turned by rot): [kind, transform,
## footprint circles], or [] when it would not stand on open desk, keep `gap`
## from the road, or (seen from the camera, which looks north) reach over it.
func _piece(it: Dictionary, p: Vector2, rot: float, gap: float) -> Array:
	var at := p + (it.off as Vector2).rotated(rot)
	var yaw: float
	if it.get("face", false):  # front (+Z) towards the camera, a little turned
		yaw = float(it.get("yaw", 0.0)) + _rng.randf_range(-0.35, 0.35)
	else:
		yaw = Vox.yaw(rot) + float(it.get("yaw", 0.0))
	var s: float = float(SCALE.get(it.kind, 1.5)) * float(it.get("scale", 1.0))
	var circles := _footprint(it.kind, at, yaw, s)
	var h := mesh(it.kind).get_aabb().end.y * s / Vox.PX + float(it.get("lift", 0.0))
	for c in circles:
		var cp: Vector2 = c[0]
		var cr: float = c[1]
		if not _free(cp, cr):
			return []
		for k in 8:
			var dir := Vector2.from_angle(k * TAU / 8.0)
			if vtrack.drivable_at(cp + dir * (cr + gap)):
				return []
			if h > 30.0 and vtrack.drivable_at(cp + Vector2(0.0, -h * LEAN) + dir * (cr + 12.0)):
				return []
		if h > 30.0 and life._in_stand(cp + Vector2(0.0, -h * LEAN), cr * 0.6):
			return []
	var basis := Basis(Vector3.UP, yaw)
	if it.has("tilt"):
		basis = basis * Basis(Vector3.RIGHT, float(it.tilt))
	basis = basis.scaled(Vector3.ONE * s)
	var origin := Vox.to3(at, vtrack.height_px_at(at) + float(it.get("lift", 0.0)))
	return [it.kind, Transform3D(basis, origin), circles]


## The ground a piece covers (px): one circle, or three along a long piece.
func _footprint(kind: String, at: Vector2, yaw: float, s: float) -> Array:
	var a := mesh(kind).get_aabb()
	var hx := maxf(absf(a.position.x), absf(a.end.x)) * s / Vox.PX
	var hz := maxf(absf(a.position.z), absf(a.end.z)) * s / Vox.PX
	if hx > hz * 1.8:  # long along its X
		var d := Vector2(cos(yaw), -sin(yaw))
		var r := maxf(hz, hx / 3.0) * 1.05
		return [[at - d * hx * 0.66, r], [at, r], [at + d * hx * 0.66, r]]
	if hz > hx * 1.8:  # long along its Z
		var d := Vector2(sin(yaw), cos(yaw))
		var r := maxf(hx, hz / 3.0) * 1.05
		return [[at - d * hz * 0.66, r], [at, r], [at + d * hz * 0.66, r]]
	return [[at, Vector2(hx, hz).length() * 0.85]]


func _add(kind: String, xf: Transform3D) -> void:
	if kind in SPINS:
		_spin_top(kind, xf)
	else:
		if not _batches.has(kind):
			_batches[kind] = []
		_batches[kind].append(xf)
	placed_pieces += 1


## Single pieces along the walls (arena) or the road edges (circuits),
## every so often, lying along the edge.
func _strays(arena: bool) -> void:
	var spots: Array = []  # [point on the edge, along (unit), outward (unit)]
	if arena:
		var b: PackedVector2Array = (life.main.track as Arena).layout.boundary
		for i in b.size():
			var a := b[i]
			var c := b[(i + 1) % b.size()]
			var t := (c - a).normalized()
			var n := Vector2(-t.y, t.x)
			if n.dot((a + c) * 0.5) < 0.0:
				n = -n
			var s := _rng.randf_range(30.0, 120.0)
			while s < a.distance_to(c):
				spots.append([a + t * s, t, n, 13.0])
				s += _rng.randf_range(90.0, 170.0)
	else:
		var cl: PackedVector2Array = life.main.track.centerline
		var total := 0.0
		var next := _rng.randf_range(50.0, 200.0)
		for k in cl.size():
			total += cl[k].distance_to(cl[(k + 1) % cl.size()])
			if total < next:
				continue
			next += _rng.randf_range(150.0, 280.0)
			var side := 1.0 if _rng.randf() < 0.5 else -1.0
			var f := life._frame(k, side)
			spots.append([f[0], f[1], f[2], float(f[3])])
	for sp in spots:
		var pick: Array = STRAYS[_rng.randi_range(0, STRAYS.size() - 1)]
		var kind: String = pick[0]
		var aabb := mesh(kind).get_aabb()
		var sc: float = SCALE.get(kind, 1.5)
		var half_len := maxf(aabb.size.x, aabb.size.z) * 0.5 * sc / Vox.PX
		var half_w := minf(aabb.size.x, aabb.size.z) * 0.5 * sc / Vox.PX
		var h := aabb.end.y * sc / Vox.PX
		var t: Vector2 = sp[1]
		var n: Vector2 = sp[2]
		for attempt in 6:
			var d := float(sp[3]) + _rng.randf_range(26.0, 150.0) + half_w
			var p: Vector2 = (sp[0] as Vector2) + n * d + t * _rng.randf_range(-30.0, 30.0)
			var along := t.rotated(_rng.randf_range(-0.12, 0.12))
			if not _line_ok(p, along, half_len, half_w, h):
				continue
			var yaw := atan2(-along.y, along.x) if pick[1] else atan2(along.x, along.y)
			if _rng.randf() < 0.5:
				yaw += PI
			var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc)
			_add(kind, Transform3D(basis, Vox.to3(p, vtrack.height_px_at(p))))
			for f in [-0.6, 0.0, 0.6]:
				_occ_add(p + along * half_len * f, half_w + 12.0)
			break


## A long piece (half length along `along`, half width) at p: open desk all
## along it, clear of the road, and not reaching over it from the camera.
func _line_ok(p: Vector2, along: Vector2, half_len: float, half_w: float, h: float) -> bool:
	for f: float in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		var q := p + along * half_len * f
		if not _free(q, half_w + 4.0):
			return false
		for k in 8:
			if vtrack.drivable_at(q + Vector2.from_angle(k * TAU / 8.0) * (half_w + 24.0)):
				return false
		if vtrack.drivable_at(q + Vector2(0.0, -h * LEAN - half_w)):
			return false
	return true


## A point on the arena's outer wall and the outward normal there.
func _arena_edge() -> Array:
	var b: PackedVector2Array = (life.main.track as Arena).layout.boundary
	var total := 0.0
	for i in b.size():
		total += b[i].distance_to(b[(i + 1) % b.size()])
	var s := _rng.randf() * total
	for i in b.size():
		var a := b[i]
		var c := b[(i + 1) % b.size()]
		var len := a.distance_to(c)
		if s <= len:
			var t := (c - a) / len
			var n := Vector2(-t.y, t.x)
			if n.dot((a + c) * 0.5) < 0.0:
				n = -n
			return [a + t * s, n]
		s -= len
	return [b[0], b[0].normalized()]


func _spin_top(kind: String, xf: Transform3D) -> void:
	var holder := Node3D.new()
	holder.position = xf.origin
	add_child(holder)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh(kind)
	mi.scale = xf.basis.get_scale()
	holder.add_child(mi)
	_tops.append([holder, mi, _rng.randf() * TAU])


## One draw per kind: a MultiMesh for repeated pieces, a plain instance for
## single ones. Shadows only from pieces that stand up.
func _commit() -> void:
	for kind in _batches:
		var xfs: Array = _batches[kind]
		var gi: GeometryInstance3D
		if xfs.size() == 1:
			var mi := MeshInstance3D.new()
			mi.mesh = mesh(kind)
			mi.transform = xfs[0]
			gi = mi
		else:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh(kind)
			mm.instance_count = xfs.size()
			for i in xfs.size():
				mm.set_instance_transform(i, xfs[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			gi = mmi
		gi.name = "Toys_" + kind.replace(":", "_")
		var tall := mesh(kind).get_aabb().end.y * float(SCALE.get(kind, 1.5)) >= 0.9
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if tall else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var v := 1.0 + _rng.randf_range(-0.03, 0.03)
		gi.set_instance_shader_parameter("tint", Color(v, v, v))
		add_child(gi)
		if kind in GLOWS:
			stage._glowing.append(gi)
	_batches.clear()


# ------------------------------------------------------------ the scenes

## A scene's pieces: {kind, off (px, scene space), yaw, lift (px), scale,
## face (front to the camera), tilt (about the piece's X)}.
func _vignette(v: String, rseed: int) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = rseed
	var out: Array = []
	match v:
		"dice":
			out.append({"kind": "die", "off": Vector2(-34, 0), "face": true})
			out.append({"kind": "die_red", "off": Vector2(42, 20), "yaw": 0.5, "face": true})
		"dice_tower":
			out.append({"kind": "die", "off": Vector2.ZERO, "face": true})
			out.append({"kind": "die_red", "off": Vector2(4, -2), "lift": 12 * 4.0 * 1.7, "face": true, "yaw": 0.3})
			out.append({"kind": "die", "off": Vector2(78, 30), "yaw": 0.7})
		"cards":
			var suits := ["card_heart", "card_spade", "card_diamond", "card_heart", "card_spade"]
			for k in 5:  # fanned from a pivot below
				var a := (k - 2) * 0.3
				out.append({"kind": suits[k], "off": Vector2(0, 70) + Vector2(0, -70).rotated(a), "yaw": -a, "lift": k * 6.5})
			out.append({"kind": "card_back", "off": Vector2(120, 10), "yaw": 0.4})
		"card_house":
			out.append({"kind": "card_house", "off": Vector2.ZERO, "face": true})
			out.append({"kind": "card_diamond", "off": Vector2(-130, 70), "yaw": 0.9})
			out.append({"kind": "card_back", "off": Vector2(120, 80), "yaw": -0.5})
		"desk":  # pencils side by side (never crossing), an eraser and a ruler
			out.append({"kind": "pencil", "off": Vector2(0, -40)})
			out.append({"kind": "pencil_sky", "off": Vector2(30, -8), "yaw": 0.04})
			out.append({"kind": "pencil_green", "off": Vector2(-24, 22), "yaw": -0.03})
			out.append({"kind": "eraser", "off": Vector2(200, 40), "yaw": 0.35})
			out.append({"kind": "ruler", "off": Vector2(-10, 82)})
		"crayons":
			out.append({"kind": "crayon_box", "off": Vector2.ZERO, "face": true})
			var spots := [Vector2(86, 18), Vector2(96, 52), Vector2(-92, 34), Vector2(-74, 72), Vector2(10, 92)]
			for k in spots.size():
				out.append({"kind": "crayon_%d" % k, "off": spots[k], "yaw": 0.2 + (k % 3) * 0.18})
		"marbles":
			var pts: Array[Vector2] = []
			for k in 40:
				if pts.size() >= 9:
					break
				var q := Vector2.from_angle(r.randf() * TAU) * r.randf_range(0.0, 84.0)
				var ok := true
				for o in pts:
					if o.distance_to(q) < (66.0 if pts.size() == 0 or o == pts[0] else 48.0):
						ok = false
				if ok:
					pts.append(q)
			for k in pts.size():
				out.append({"kind": "marble_%d" % (k % 5), "off": pts[k], "yaw": r.randf() * TAU, "scale": 1.35 if k == 0 else 1.0})
		"bricks":
			out.append({"kind": "brick_0", "off": Vector2(-50, -10), "yaw": 0.2})
			out.append({"kind": "brick_2", "off": Vector2(-50, -10), "yaw": 0.2, "lift": 5 * 4.0 * 1.6})
			out.append({"kind": "brick_1", "off": Vector2(40, -30), "yaw": 1.3})
			out.append({"kind": "brick_3", "off": Vector2(30, 50), "yaw": -0.4})
			out.append({"kind": "brick_4", "off": Vector2(-20, 70), "yaw": 1.9})
			out.append({"kind": "brick_5", "off": Vector2(95, 20), "yaw": 0.7})
		"brick_tower":
			out.append({"kind": "brick_tower", "off": Vector2.ZERO})
			out.append({"kind": "brick_1", "off": Vector2(80, 40), "yaw": 0.6})
			out.append({"kind": "brick_4", "off": Vector2(-70, 60), "yaw": -0.3})
			out.append({"kind": "brick_5", "off": Vector2(20, 95), "yaw": 1.4})
		"puzzle":
			for k in 4:
				var q := Vector2.from_angle(k * TAU / 4.0 + r.randf() * 0.6) * r.randf_range(50.0, 72.0)
				out.append({"kind": "puzzle_%d" % k, "off": q, "yaw": r.randf() * TAU})
		"traffic":
			out.append({"kind": ["sign_speed", "sign_warn"][r.randi() % 2], "off": Vector2(-60, -10), "face": true})
			out.append({"kind": "sign_yield", "off": Vector2(0, -20), "face": true})
			out.append({"kind": ["sign_arrow", "sign_noentry"][r.randi() % 2], "off": Vector2(60, -10), "face": true})
			for k in 4:
				out.append({"kind": "cone", "off": Vector2(-66 + k * 44, 40), "yaw": r.randf() * TAU})
		"parade":  # two files of tin soldiers behind a drummer
			out.append({"kind": "drummer", "off": Vector2(0, 0)})
			for row in 4:
				for col in 2:
					out.append({"kind": "soldier", "off": Vector2(col * 44.0 - 22.0, -52.0 - row * 46.0)})
		"abc":
			out.append({"kind": "abc_0", "off": Vector2(-36, 0), "face": true})
			out.append({"kind": "abc_1", "off": Vector2(36, 4), "face": true})
			out.append({"kind": "abc_2", "off": Vector2(0, 2), "lift": 10 * 4.0 * 1.7, "face": true})
			out.append({"kind": "abc_0", "off": Vector2(100, 60), "face": true, "yaw": 0.6})
		"tops":
			out.append({"kind": "top_0", "off": Vector2(-50, 0)})
			out.append({"kind": "top_1", "off": Vector2(50, 20)})
		"rocket":
			out.append({"kind": "rocket", "off": Vector2.ZERO, "face": true})
			for k in 3:
				out.append({"kind": "cone", "off": Vector2.from_angle(0.6 + k * 2.1) * 92.0})
		"town":
			out.append({"kind": "house_0", "off": Vector2(-110, 10), "face": true})
			out.append({"kind": "house_1", "off": Vector2(20, -40), "face": true})
			out.append({"kind": "tower", "off": Vector2(130, -10), "face": true})
			out.append({"kind": "house_2", "off": Vector2(-20, 90), "face": true, "scale": 0.85})
		"domino":  # a winding run; the first few have already fallen
			var n := 15
			for k in n:
				var s := float(k) / (n - 1)
				var q := Vector2((s - 0.5) * 420.0, sin(s * TAU * 0.8) * 70.0)
				var nxt := Vector2((s + 0.02 - 0.5) * 420.0, sin((s + 0.02) * TAU * 0.8) * 70.0)
				var t := (nxt - q).normalized()
				var it := {"kind": "domino_%d" % (k % 3), "off": q, "yaw": atan2(t.x, t.y)}
				var fallen := [1.25, 1.05, 0.75, 0.4]
				if k < fallen.size():
					it.tilt = fallen[k]
				out.append(it)
		"duck":
			out.append({"kind": "kit:duck", "off": Vector2.ZERO, "face": true})
			out.append({"kind": "marble_1", "off": Vector2(90, 40)})
			out.append({"kind": "marble_3", "off": Vector2(110, 0)})
		"mug":
			out.append({"kind": "kit:mug", "off": Vector2.ZERO})
			out.append({"kind": "pencil_purple", "off": Vector2(40, 110), "yaw": 0.1})
		"robots":
			out.append({"kind": "kit:robot", "off": Vector2(-40, 0), "face": true})
			out.append({"kind": "kit:robot", "off": Vector2(40, 10), "face": true})
			out.append({"kind": "kit:blocks", "off": Vector2(0, 90), "yaw": 0.3})
	return out


# ------------------------------------------------------------ the models

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


## A pixel pattern (rows of "X" / ".") painted on a face.
## put: Callable(col, row) for every X.
static func _pattern(rows: Array, put: Callable) -> void:
	for row in rows.size():
		var line: String = rows[row]
		for col in line.length():
			if line[col] == "X":
				put.call(col, row)


const HEART := [".XX.XX.", "XXXXXXX", "XXXXXXX", ".XXXXX.", "..XXX..", "...X..."]
const DIAMOND := ["...X...", "..XXX..", ".XXXXX.", "XXXXXXX", ".XXXXX.", "..XXX..", "...X..."]
const SPADE := ["...X...", "..XXX..", ".XXXXX.", "XXXXXXX", "XXXXXXX", ".XX.XX.", "...X...", "..XXX.."]
const LETTERS := {
	"A": [".XXX.", "X...X", "X...X", "XXXXX", "X...X", "X...X"],
	"B": ["XXXX.", "X...X", "XXXX.", "X...X", "X...X", "XXXX."],
	"C": [".XXXX", "X....", "X....", "X....", "X....", ".XXXX"],
	"D": ["XXXX.", "X...X", "X...X", "X...X", "X...X", "XXXX."],
}
const DIGITS := {
	"3": ["XXX", "..X", "XXX", "..X", "XXX"],
	"0": ["XXX", "X.X", "X.X", "X.X", "XXX"],
}
## Pip spots on a 3 x 3 grid for 1..6.
const PIPS := {1: [Vector2i(1, 1)], 2: [Vector2i(0, 0), Vector2i(2, 2)], 3: [Vector2i(0, 0), Vector2i(1, 1), Vector2i(2, 2)],
	4: [Vector2i(0, 0), Vector2i(2, 0), Vector2i(0, 2), Vector2i(2, 2)],
	5: [Vector2i(0, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(0, 2), Vector2i(2, 2)],
	6: [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2)]}
const WOOD := Color("e8c58e")
const ORANGE := Color("ff8c2e")
const PURPLE := Color("a37ef0")
const BRICKS := [Color("f7c531"), Color("3f8fe0"), Color("5cb85c"), Color("f2efe6"), Color("ff8c2e"), Color("f45b9b")]
const CRAYONS := [Color("f7c531"), Color("3f8fe0"), Color("5cb85c"), Color("a37ef0"), Color("ff8c2e")]
const MARBLES := [Color("59c3f2"), Color("7bc950"), Color("f7b731"), Color("f45b9b"), Color("2ec4b6")]


static func _build(kind: String) -> ArrayMesh:
	match kind:
		"die", "die_red":
			return _die(kind == "die_red")
		"card_heart", "card_diamond", "card_spade", "card_back":
			return _card(kind.substr(5))
		"card_house":
			return _card_house()
		"pencil", "pencil_sky", "pencil_green", "pencil_purple":
			var cols := {"pencil": Color("f7c531"), "pencil_sky": Color("3f8fe0"), "pencil_green": Color("5cb85c"), "pencil_purple": PURPLE}
			return _pencil(cols[kind], kind == "pencil")
		"crayon_box":
			return _crayon_box()
		"eraser":
			var g := _grid(12, 4, 7)
			_box(g, Vector3i(0, 0, 0), Vector3i(6, 3, 6), Color("f49ab5"))
			_box(g, Vector3i(7, 0, 0), Vector3i(11, 3, 6), Color("5b8fd9"))
			_box(g, Vector3i(0, 3, 0), Vector3i(0, 3, 6), Color(0, 0, 0), Vox.AIR)  # worn end
			_box(g, Vector3i(1, 3, 2), Vector3i(1, 3, 4), Color("e07f9c"))
			return _done(g)
		"ruler":
			var g := _grid(64, 2, 8)
			var y := Color("f7c948")
			_box(g, Vector3i(0, 0, 0), Vector3i(63, 1, 7), y)
			for x in range(2, 62):
				var k := x - 2
				var reach := 3 if k % 8 == 0 else (2 if k % 4 == 0 else (1 if k % 2 == 0 else 0))
				for dz in reach:
					g.set_v(x, 1, 7 - dz, Vox.SOLID, VrStyle.INK)
				if k % 8 == 0 and k > 0:
					g.set_v(x, 1, 2, Vox.SOLID, VrStyle.INK)  # (the numbers, in miniature)
					g.set_v(x, 1, 3, Vox.SOLID, VrStyle.INK)
			_box(g, Vector3i(59, 0, 2), Vector3i(60, 1, 3), y, Vox.AIR)  # hanging hole
			return _done(g)
		"brick_tower":
			return _brick_tower()
		"soldier", "drummer":
			return _soldier(kind == "drummer")
		"domino_0", "domino_1", "domino_2":
			var vals: Array = [[6, 3], [5, 2], [4, 1]][int(kind.substr(7))]
			return _domino(vals[0], vals[1])
		"puzzle_0", "puzzle_1", "puzzle_2", "puzzle_3":
			return _puzzle([Color("3f8fe0"), Color("5cb85c"), Color("f7c531"), PURPLE][int(kind.substr(7))])
		"cone":
			var g := _grid(7, 10, 7)
			_box(g, Vector3i(0, 0, 0), Vector3i(6, 0, 6), Color(0.22, 0.22, 0.26))
			for y in range(1, 10):
				var rr := 3.2 - (y - 1) * 0.33
				for z in 7:
					for x in 7:
						if Vector2(x - 3, z - 3).length() <= rr:
							g.set_v(x, y, z, Vox.SOLID, VrStyle.PAPER if y == 4 or y == 5 else Color("ff7a1a"))
			return _done(g)
		"sign_noentry", "sign_yield", "sign_arrow", "sign_speed", "sign_warn":
			return _sign(kind.substr(5))
		"rocket":
			return _rocket()
		"top_0", "top_1":
			return _top(kind == "top_1")
		"marble_0", "marble_1", "marble_2", "marble_3", "marble_4":
			var g := _grid(9, 9, 9)
			var base: Color = MARBLES[int(kind.substr(7))]
			for y in 9:
				for z in 9:
					for x in 9:
						if Vector3(x - 4, y - 4, z - 4).length() <= 4.25:
							var ribbon := absf(y - 4.0 - 1.6 * sin((x - z) * 0.55)) < 0.75
							g.set_v(x, y, z, Vox.METAL, VrStyle.PAPER if ribbon else base)
			g.set_v(3, 8, 3, Vox.METAL, Color(1, 1, 1))  # a glint
			return _done(g)
		"abc_0", "abc_1", "abc_2":
			var k := int(kind.substr(4))
			var faces := [Color("3f8fe0"), Color("f7c531"), Color("5cb85c"), Color("f45b9b")]
			var letters := ["A", "B", "C", "D"]
			return _abc(faces[k % 4], faces[(k + 1) % 4], faces[(k + 2) % 4], letters[k], letters[(k + 1) % 4], letters[(k + 2) % 4])
		"house_0", "house_1", "house_2":
			var k := int(kind.substr(6))
			return _house([Color("f7c531"), Color("8fc7f2"), Color("f49ab5")][k], [VrStyle.TEAL, Color("d9553f"), PURPLE][k])
		"tower":
			return _tower()
	if kind.begins_with("crayon_"):
		return _crayon(CRAYONS[int(kind.substr(7)) % CRAYONS.size()])
	if kind.begins_with("brick_"):
		return _brick(BRICKS[int(kind.substr(6)) % BRICKS.size()])
	var g := _grid(4, 4, 4)
	_box(g, Vector3i.ZERO, Vector3i(3, 3, 3), Color.MAGENTA)
	return _done(g)


## A die with rounded edges and sunken pips: top, front (+Z), right (+X),
## left, back (opposite faces add up to seven).
static func _die(red: bool) -> ArrayMesh:
	var n := 12
	var g := _grid(n, n, n)
	var body := Color("d9453a") if red else Color(0.97, 0.95, 0.9)
	var pip := VrStyle.PAPER if red else VrStyle.INK
	for y in n:
		for z in n:
			for x in n:
				var e := int(x == 0 or x == n - 1) + int(y == 0 or y == n - 1) + int(z == 0 or z == n - 1)
				if e < 2:
					g.set_v(x, y, z, Vox.SOLID, body)
	var faces := {"top": 6 if red else 5, "front": 2 if red else 3, "right": 4 if red else 1, "left": 3 if red else 6, "back": 5 if red else 4}
	var at := [2, 5, 8]
	for face in faces:
		for sp in PIPS[faces[face]]:
			for du in 2:
				for dv in 2:
					var u: int = at[sp.x] + du
					var v: int = at[sp.y] + dv
					var s: Vector3i
					var inner: Vector3i
					match face:
						"top":
							s = Vector3i(u, n - 1, v)
							inner = Vector3i(u, n - 2, v)
						"front":
							s = Vector3i(u, n - 1 - v, n - 1)
							inner = s - Vector3i(0, 0, 1)
						"back":
							s = Vector3i(u, n - 1 - v, 0)
							inner = s + Vector3i(0, 0, 1)
						"right":
							s = Vector3i(n - 1, n - 1 - v, u)
							inner = s - Vector3i(1, 0, 0)
						_:
							s = Vector3i(0, n - 1 - v, u)
							inner = s + Vector3i(1, 0, 0)
					g.set_v(s.x, s.y, s.z, Vox.AIR, body)
					g.set_v(inner.x, inner.y, inner.z, Vox.SOLID, pip)
	return _done(g)


## A playing card lying flat (top edge towards -Z): a big suit in the middle
## and an "A" in two corners; or its back (navy with dots and a white rim).
static func _card(suit: String) -> ArrayMesh:
	var nx := 17
	var nz := 24
	var g := _grid(nx, 1, nz)
	var white := Color(0.98, 0.97, 0.94)
	for z in nz:
		for x in nx:
			if (x == 0 or x == nx - 1) and (z == 0 or z == nz - 1):
				continue
			var c := white
			if suit == "back" and x > 0 and x < nx - 1 and z > 0 and z < nz - 1:
				c = Color("2b3f8a") if not (x % 3 == 1 and z % 3 == 1) else Color("8fa6e8")
			g.set_v(x, 0, z, Vox.SOLID, c)
	if suit != "back":
		var ink := VrStyle.INK if suit == "spade" else Color("d9343a")
		var shape: Array = {"heart": HEART, "diamond": DIAMOND, "spade": SPADE}[suit]
		var z0 := (nz - shape.size()) / 2
		_pattern(shape, func(cx: int, cz: int) -> void: g.set_v(5 + cx, 0, z0 + cz, Vox.SOLID, ink))
		var a := [".X.", "X.X", "X.X", "XXX", "X.X"]  # (an "A")
		_pattern(a, func(cx: int, cz: int) -> void: g.set_v(1 + cx, 0, 1 + cz, Vox.SOLID, ink))
		_pattern(a, func(cx: int, cz: int) -> void: g.set_v(nx - 2 - cx, 0, nz - 2 - cz, Vox.SOLID, ink))
	return _done(g)


## Three storeys of leaning cards with flat cards across them.
static func _card_house() -> ArrayMesh:
	var g := _grid(34, 39, 9)
	var backs := [Color("2b3f8a"), Color("d9553f"), Color("2b3f8a"), Color("3e8a5c")]
	var n := [0]
	var lean := func(bx: int, y0: int, right: bool) -> void:
		var c: Color = backs[n[0] % backs.size()]
		n[0] += 1
		for y in 12:
			var x := bx + (10 - int(round(y * 5.0 / 11.0)) if right else int(round(y * 5.0 / 11.0)))
			for z in 9:
				var rim := z == 0 or z == 8 or y == 0
				for dx in 2:
					g.set_v(x + (dx if not right else -dx), y0 + y, z, Vox.SOLID, VrStyle.PAPER if rim else c)
	var flat := func(x0: int, x1: int, y: int) -> void:
		for x in range(x0, x1 + 1):
			for z in 9:
				g.set_v(x, y, z, Vox.SOLID, VrStyle.PAPER if x == x0 or x == x1 or z == 0 or z == 8 else Color("f2e9d8"))
	for k in 3:
		lean.call(k * 11, 0, false)
		lean.call(k * 11, 0, true)
	flat.call(2, 31, 12)
	for k in 2:
		lean.call(6 + k * 11, 13, false)
		lean.call(6 + k * 11, 13, true)
	flat.call(8, 26, 25)
	lean.call(11, 26, false)
	lean.call(11, 26, true)
	return _done(g)


## A pencil lying along X: eraser, metal ferrule, painted hexagonal body,
## sharpened wood and the lead (coloured pencils: no eraser, coloured lead).
static func _pencil(paint: Color, eraser: bool) -> ArrayMesh:
	var g := _grid(54, 5, 5)
	var lead := Color(0.2, 0.2, 0.22) if eraser else paint.darkened(0.15)
	for x in 54:
		for y in 5:
			for z in 5:
				var dy := absi(y - 2)
				var dz := absi(z - 2)
				if dy == 2 and dz == 2:
					continue  # (hexagon-ish)
				var c := paint
				if x <= 4 and eraser:
					c = Color("f49ab5")
				elif x <= 7 and eraser:
					c = Color(0.78, 0.79, 0.82) if x != 6 else Color(0.6, 0.61, 0.64)
				elif x >= 46:
					var rr := 2 if x <= 47 else (1 if x <= 50 else 0)
					if maxi(dy, dz) > rr:
						continue
					c = WOOD if maxi(dy, dz) > 0 or x < 50 else lead
					if x >= 51:
						c = lead
				elif dz == 2 or dy == 2:
					c = paint.darkened(0.12)
				if c == paint and y == 4:
					c = paint.lightened(0.12)
				g.set_v(x, y, z, Vox.METAL if c.s < 0.1 and c.v > 0.55 and x <= 7 else Vox.SOLID, c)
	return _done(g)


## A wax crayon lying along X: paper wrapper with two bands, a pointed tip.
static func _crayon(c: Color) -> ArrayMesh:
	var g := _grid(26, 4, 4)
	for x in 26:
		for y in 4:
			for z in 4:
				if (y == 0 or y == 3) and (z == 0 or z == 3):
					continue
				if x >= 23 and (y == 0 or y == 3 or z == 0 or z == 3):
					continue
				if x == 25 and not (y == 1 and z in [1, 2]):
					continue
				var cc := c
				if x >= 2 and x <= 19:
					cc = c.lightened(0.3)
					if x in [4, 5, 16, 17]:
						cc = c.darkened(0.35)
				g.set_v(x, y, z, Vox.SOLID, cc)
	return _done(g)


## An open box of crayons standing up, their tips poking out.
static func _crayon_box() -> ArrayMesh:
	var g := _grid(16, 18, 7)
	var box := Color("f7c531")
	_box(g, Vector3i(0, 0, 0), Vector3i(15, 13, 6), box)
	for x in 16:  # a green zigzag band round the front
		var y := 6 + absi((x % 4) - 2)
		for z in 7:
			if z == 6 or x == 0 or x == 15:
				g.set_v(x, y, z, Vox.SOLID, Color("3e9a4a"))
				g.set_v(x, y + 1, z, Vox.SOLID, Color("3e9a4a"))
	for k in 7:
		var x0 := 1 + k * 2
		var c: Color = [Color("f7c531"), Color("3f8fe0"), Color("5cb85c"), PURPLE, ORANGE, Color("f45b9b"), Color("8a5a3a")][k]
		var top := 15 + (k % 2)
		_box(g, Vector3i(x0, 12, 2), Vector3i(x0 + 1, top, 4), c)
		g.set_v(x0, top + 1, 3, Vox.SOLID, c)
	return _done(g)


## A 2 x 4 building brick (studs on top).
static func _brick(c: Color) -> ArrayMesh:
	var g := _grid(8, 6, 16)
	_box(g, Vector3i(0, 0, 0), Vector3i(7, 4, 15), c)
	_box(g, Vector3i(0, 0, 0), Vector3i(7, 0, 15), c.darkened(0.12))
	for i in 2:
		for j in 4:
			_box(g, Vector3i(i * 4 + 1, 5, j * 4 + 1), Vector3i(i * 4 + 2, 5, j * 4 + 2), c.lightened(0.12))
	return _done(g)


## A wobbly tower of 2 x 2 bricks.
static func _brick_tower() -> ArrayMesh:
	var g := _grid(12, 37, 12)
	var y := 0
	for k in 7:
		var c: Color = BRICKS[(k * 2 + 1) % BRICKS.size()]
		var ox: int = 2 + [0, 1, 0, -1, 1, 0, 1][k]
		var oz: int = 2 + [0, 0, 1, 0, -1, 1, 0][k]
		_box(g, Vector3i(ox, y, oz), Vector3i(ox + 7, y + 4, oz + 7), c)
		_box(g, Vector3i(ox, y, oz), Vector3i(ox + 7, y, oz + 7), c.darkened(0.12))
		if k == 6:
			for i in 2:
				for j in 2:
					_box(g, Vector3i(ox + i * 4 + 1, y + 5, oz + j * 4 + 1), Vector3i(ox + i * 4 + 2, y + 5, oz + j * 4 + 2), c.lightened(0.12))
		y += 5
	return _done(g)


## A tin soldier at attention on his base (or the drummer, with a drum).
static func _soldier(drummer: bool) -> ArrayMesh:
	var g := _grid(7, 21, 8)
	var coat := Color("d9453a") if drummer else Color("2f5fb0")
	var skin := Color("f2c79e")
	_box(g, Vector3i(0, 0, 0), Vector3i(6, 0, 4), Color("2f5d3a"))
	for lx in [1, 4]:
		_box(g, Vector3i(lx, 1, 1), Vector3i(lx + 1, 6, 3), Color("23305e"))
		_box(g, Vector3i(lx, 1, 1), Vector3i(lx + 1, 2, 3), Color(0.1, 0.1, 0.12))
	_box(g, Vector3i(1, 7, 1), Vector3i(5, 12, 3), coat)
	_box(g, Vector3i(1, 8, 1), Vector3i(5, 8, 3), VrStyle.PAPER)  # belt
	for by in [10, 12]:
		g.set_v(3, by, 3, Vox.METAL, VrStyle.YELLOW)
	for ax in [0, 6]:
		_box(g, Vector3i(ax, 8, 2), Vector3i(ax, 12, 2), coat)
		g.set_v(ax, 7, 2, Vox.SOLID, skin)
	_box(g, Vector3i(2, 13, 1), Vector3i(4, 15, 3), skin)
	g.set_v(2, 14, 3, Vox.SOLID, VrStyle.INK)
	g.set_v(4, 14, 3, Vox.SOLID, VrStyle.INK)
	_box(g, Vector3i(2, 16, 1), Vector3i(4, 20, 3), Color(0.1, 0.1, 0.12))  # tall hat
	g.set_v(3, 16, 4, Vox.METAL, VrStyle.YELLOW)
	if drummer:
		for y in range(6, 10):
			for z in range(4, 8):
				for x in range(1, 6):
					if Vector2(x - 3, z - 5.5).length() <= 2.3:
						var rim := y == 6 or y == 9
						var stripe := ((x + z + y) % 3) == 0
						g.set_v(x, y, z, Vox.SOLID, VrStyle.PAPER if rim else (VrStyle.YELLOW if stripe else Color("3f8fe0")))
		g.set_v(2, 10, 5, Vox.SOLID, WOOD)  # sticks
		g.set_v(4, 10, 6, Vox.SOLID, WOOD)
	return _done(g, Vector3(3.5, 0.0, 2.5))


## A standing domino (faces +Z / -Z) with its two numbers.
static func _domino(a: int, b: int) -> ArrayMesh:
	var g := _grid(7, 15, 2)
	var ivory := Color(0.96, 0.94, 0.88)
	_box(g, Vector3i(0, 0, 0), Vector3i(6, 14, 1), ivory)
	for x in range(1, 6):
		for z in 2:
			g.set_v(x, 7, z, Vox.SOLID, VrStyle.INK)
	for half in 2:
		var val: int = a if half == 0 else b
		var y0 := 9 if half == 0 else 1
		for sp in PIPS[val]:
			for z in 2:
				g.set_v(1 + sp.x * 2, y0 + 4 - sp.y * 2, z, Vox.SOLID, VrStyle.INK)
	return _done(g)


## A jigsaw piece lying flat: knobs out on two sides, sockets on the others.
static func _puzzle(c: Color) -> ArrayMesh:
	var g := _grid(19, 2, 19)
	for z in 19:
		for x in 19:
			var inside := x >= 3 and x <= 15 and z >= 3 and z <= 15
			if Vector2(x - 17.0, z - 9.0).length() <= 2.3 or Vector2(x - 9.0, z - 1.0).length() <= 2.3:
				inside = true  # knobs (+X, -Z)
			if Vector2(x - 4.5, z - 9.0).length() <= 2.3 or Vector2(x - 9.0, z - 14.5).length() <= 2.3:
				inside = false  # sockets (-X, +Z)
			if inside:
				for y in 2:
					var cc := c if y == 0 else c.lightened(0.08 + 0.08 * Vox.hash3(x / 3, 3, z / 3))
					g.set_v(x, y, z, Vox.SOLID, cc)
	return _done(g)


## A little traffic sign on a post, its face to +Z.
static func _sign(face: String) -> ArrayMesh:
	var g := _grid(9, 18, 2)
	var grey := Color(0.62, 0.63, 0.66)
	_box(g, Vector3i(4, 0, 0), Vector3i(4, 11, 0), grey, Vox.METAL)
	_box(g, Vector3i(3, 0, 0), Vector3i(5, 0, 1), Color(0.3, 0.3, 0.33))
	var put := func(x: int, y: int, c: Color) -> void:
		g.set_v(x, y, 1, Vox.SOLID, c)
		g.set_v(x, y, 0, Vox.SOLID, grey)
	var red := Color("d9343a")
	match face:
		"noentry", "arrow", "speed":
			for y in range(9, 18):
				for x in 9:
					var d := Vector2(x - 4, y - 13).length()
					if d > 4.4:
						continue
					var c := red
					if face == "arrow":
						c = Color("2f6fc0")
					elif face == "speed":
						c = red if d > 3.3 else VrStyle.PAPER
					if face == "noentry" and (y == 13 or y == 12) and x >= 2 and x <= 6:
						c = VrStyle.PAPER
					put.call(x, y, c)
			if face == "arrow":  # pointing up (straight on)
				for y in range(10, 15):
					put.call(4, y, VrStyle.PAPER)
				for x in range(2, 7):
					put.call(x, 15, VrStyle.PAPER)
				for x in range(3, 6):
					put.call(x, 16, VrStyle.PAPER)
				put.call(4, 17, VrStyle.PAPER)
			if face == "speed":
				_pattern(DIGITS["3"], func(cx: int, cy: int) -> void: put.call(1 + cx, 15 - cy, VrStyle.INK))
				_pattern(DIGITS["0"], func(cx: int, cy: int) -> void: put.call(5 + cx, 15 - cy, VrStyle.INK))
		"yield", "warn":
			for row in 9:
				var y := 17 - row if face == "yield" else 9 + row
				var half := 4 - row / 2
				for x in range(4 - half, 4 + half + 1):
					var edge := x == 4 - half or x == 4 + half or row == 0 or row == 1
					put.call(x, y, red if edge else VrStyle.PAPER)
			if face == "warn":
				for y in [11, 13, 14]:
					put.call(4, y, VrStyle.INK)
	return _done(g, Vector3(4.5, 0.0, 0.5))


## A toy rocket on its launch pad: three fins, a porthole, an orange nose.
static func _rocket() -> ArrayMesh:
	var g := _grid(19, 42, 19)
	_box(g, Vector3i(2, 0, 2), Vector3i(16, 1, 16), Color(0.55, 0.56, 0.6))
	for x in range(2, 17):
		for z in [2, 16]:
			if (x / 2) % 2 == 0:
				g.set_v(x, 1, z, Vox.SOLID, VrStyle.YELLOW)
				g.set_v(z, 1, x, Vox.SOLID, VrStyle.YELLOW)
	for y in range(2, 41):
		var r := 4.3
		var c := VrStyle.PAPER
		if y >= 31:
			r = 4.3 * (1.0 - (y - 31) / 10.0) + 0.4
			c = ORANGE
		elif y in [10, 11, 25, 26]:
			c = VrStyle.TEAL
		for z in 19:
			for x in 19:
				if Vector2(x - 9, z - 9).length() <= r:
					g.set_v(x, y, z, Vox.SOLID, c)
	for k in 3:  # fins
		var a := PI * 0.5 + k * TAU / 3.0
		var d := Vector2(cos(a), sin(a))
		for si in range(8, 18):
			var s := si * 0.5
			var top := 2 + int(11.0 - (s - 4.0) * 2.0)
			for y in range(2, top + 1):
				var p := Vector2(9, 9) + d * s
				g.set_v(int(round(p.x)), y, int(round(p.y)), Vox.SOLID, VrStyle.TEAL.darkened(0.1))
	for x in range(8, 11):  # porthole, lit at night
		for y in range(19, 22):
			var mid := x == 9 and y == 20
			g.set_v(x, y, 13, Vox.GLOW if mid else Vox.METAL, Color(0.6, 0.85, 1.0) if mid else Color(0.7, 0.72, 0.76))
	return _done(g)


## A spinning top: six coloured sectors, a handle and a metal point.
static func _top(alt: bool) -> ArrayMesh:
	var g := _grid(15, 13, 15)
	var cols := [VrStyle.YELLOW, VrStyle.TEAL, Color("f45b9b"), VrStyle.SKY, ORANGE, VrStyle.GREEN]
	if alt:
		cols = [PURPLE, VrStyle.PAPER, VrStyle.SKY, PURPLE, VrStyle.PAPER, VrStyle.SKY]
	g.set_v(7, 0, 7, Vox.METAL, Color(0.7, 0.72, 0.76))
	g.set_v(7, 1, 7, Vox.METAL, Color(0.7, 0.72, 0.76))
	var prof := [2.0, 4.0, 5.5, 6.8, 7.2, 6.2, 4.6]
	for i in prof.size():
		var y := 2 + i
		for z in 15:
			for x in 15:
				var d := Vector2(x - 7, z - 7)
				if d.length() <= prof[i]:
					var sec := int((d.angle() + PI) / (TAU / 6.0)) % 6
					var c: Color = cols[sec]
					if i == 4 and d.length() > 6.2:
						c = VrStyle.PAPER
					g.set_v(x, y, z, Vox.SOLID, c)
	for y in range(9, 13):
		for z in range(6, 9):
			for x in range(6, 9):
				if absi(x - 7) + absi(z - 7) <= 1:
					g.set_v(x, y, z, Vox.SOLID, Color("8a5a3a") if y < 12 else VrStyle.YELLOW)
	return _done(g)


## A wooden letter block: painted faces with raised letters, a wood frame.
static func _abc(top: Color, front: Color, side: Color, lt: String, lf: String, ls: String) -> ArrayMesh:
	var n := 10
	var g := _grid(n, n, n)
	for y in n:
		for z in n:
			for x in n:
				var e := int(x == 0 or x == n - 1) + int(y == 0 or y == n - 1) + int(z == 0 or z == n - 1)
				var c := WOOD
				if e == 1:
					if y == n - 1:
						c = top
					elif z == n - 1 or z == 0:
						c = front
					else:
						c = side
				g.set_v(x, y, z, Vox.SOLID, c)
	var ink := VrStyle.PAPER
	_pattern(LETTERS[lt], func(cx: int, cy: int) -> void: g.set_v(2 + cx, n - 1, 2 + cy, Vox.SOLID, ink))
	_pattern(LETTERS[lf], func(cx: int, cy: int) -> void: g.set_v(2 + cx, n - 2 - cy, n - 1, Vox.SOLID, ink))
	_pattern(LETTERS[ls], func(cx: int, cy: int) -> void: g.set_v(n - 1, n - 2 - cy, n - 3 - cx + 1, Vox.SOLID, ink))
	_pattern(LETTERS[ls], func(cx: int, cy: int) -> void: g.set_v(0, n - 2 - cy, 2 + cx, Vox.SOLID, ink))
	return _done(g)


## A wooden toy house: painted walls, a pitched roof, lit windows, a chimney.
static func _house(wall: Color, roof: Color) -> ArrayMesh:
	var g := _grid(16, 22, 14)
	_box(g, Vector3i(1, 0, 1), Vector3i(14, 11, 12), wall)
	_box(g, Vector3i(6, 0, 12), Vector3i(9, 6, 13), Color("8a5a3a"))
	g.set_v(8, 3, 13, Vox.METAL, VrStyle.YELLOW)
	var lit := Color(1.0, 0.85, 0.45)
	for wx in [2, 11]:
		_box(g, Vector3i(wx, 5, 12), Vector3i(wx + 2, 8, 13), VrStyle.PAPER)
		_box(g, Vector3i(wx, 6, 13), Vector3i(wx + 2, 7, 13), lit, Vox.GLOW)
	for wz in [4, 8]:
		_box(g, Vector3i(14, 6, wz), Vector3i(15, 7, wz + 1), lit, Vox.GLOW)
		_box(g, Vector3i(0, 6, wz), Vector3i(1, 7, wz + 1), lit, Vox.GLOW)
	for k in 8:
		var cc := roof if k % 2 == 0 else roof.darkened(0.12)
		_box(g, Vector3i(0, 12 + k, k), Vector3i(15, 12 + k, 13 - k), cc)
		if k < 7:
			_box(g, Vector3i(1, 12 + k, k + 1), Vector3i(14, 12 + k, 12 - k), wall)
	_box(g, Vector3i(11, 14, 3), Vector3i(12, 21, 4), Color("b0533a"))
	return _done(g)


## A toy castle tower: wooden blocks, glowing windows, a pointed roof and a
## little yellow flag.
static func _tower() -> ArrayMesh:
	var g := _grid(15, 40, 15)
	for y in 25:
		for z in 15:
			for x in 15:
				if Vector2(x - 7, z - 7).length() <= 6.0:
					var band := (y / 3) % 2 == 0
					g.set_v(x, y, z, Vox.SOLID, WOOD if band else WOOD.darkened(0.1))
	for x in range(6, 9):
		for y in [9, 10, 11, 17, 18, 19]:
			g.set_v(x, y, 13, Vox.GLOW, Color(1.0, 0.85, 0.45))
	_box(g, Vector3i(6, 0, 13), Vector3i(8, 4, 13), Color("8a5a3a"))
	for y in range(25, 36):
		var r := 7.2 * (1.0 - (y - 25) / 11.0) + 0.3
		for z in 15:
			for x in 15:
				if Vector2(x - 7, z - 7).length() <= r:
					g.set_v(x, y, z, Vox.SOLID, PURPLE if y % 2 == 0 else PURPLE.darkened(0.12))
	_box(g, Vector3i(7, 36, 7), Vector3i(7, 39, 7), Color(0.7, 0.72, 0.76), Vox.METAL)
	_box(g, Vector3i(8, 37, 7), Vector3i(10, 39, 7), VrStyle.YELLOW)
	return _done(g)
