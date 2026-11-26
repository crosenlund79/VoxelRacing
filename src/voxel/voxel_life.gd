class_name VoxelLife
extends Node3D
## VoxelRacing (P004): the circuit as a living place. Per-theme set dressing
## (VoxelKit) placed on open ground beside the track, never on anything
## drivable; little voxel spectators in groups along the fences (each group
## with a favourite driver, some waving flags) who watch the cars go by, turn
## their heads to follow them and jump up for overtakes, crashes, explosions
## and the finish; marshals at the corners; butterflies over the meadows and
## birds high above; windmills and fans turning, chimneys smoking, cows that
## watch the race. Presentation only: the race never sees any of it.

signal cheered(strength: float)

const SoundKit := preload("res://src/audio/sound_kit.gd")
const CROWD_SHADER := preload("res://src/voxel/shaders/voxel_crowd.gdshader")
const CRITTER_SHADER := preload("res://src/voxel/shaders/voxel_critters.gdshader")
const Grandstand := preload("res://src/voxel/voxel_grandstand.gd")
const C := VoxelKit.C
const MAX_CROWD := 460
const MAX_FLAGS := 90
## P005: spectators in the grandstands' seats (and how full the stands are).
const MAX_SEATED := 340
const SEATED_FILL := 0.72
const TICK := 0.1

## Set dressing per theme variant: [kind, how many, near the road].
const KITS := {
	1: [["barn", 1, false], ["windmill", 1, false], ["cottage", 2, false], ["tractor", 1, false], ["stall", 2, false],
		["hay", 6, false], ["cow", 5, false], ["fence", 8, true], ["flagpole", 3, true], ["bench", 3, true]],
	2: [["shed", 2, false], ["containers", 3, false], ["container", 3, false], ["scrap", 3, false], ["tow_truck", 1, false],
		["drums", 5, false], ["fire_drum", 6, true], ["tyre_wall", 5, true]],
	3: [["cabin", 3, false], ["stall", 1, false], ["snowman", 5, false], ["sledge", 4, false], ["fence", 5, true], ["flagpole", 2, true]],
	4: [["pit_garages", 1, false], ["tent", 3, false], ["screen", 2, false], ["ambulance", 1, false], ["tow_truck", 1, false],
		["stall", 2, false], ["tv_tower", 4, true], ["tyre_wall", 6, true], ["flagpole", 5, true], ["bench", 2, true]],
	5: [["duck", 1, false], ["mug", 2, false], ["blocks", 3, false], ["robot", 3, false]],
}
## Display scale per kind (cartoon proportions next to the cars).
const SCALE := {"barn": 1.6, "cottage": 1.5, "windmill": 1.7, "cabin": 1.5, "pit_garages": 1.4, "tent": 1.45,
	"shed": 1.4, "containers": 1.3, "container": 1.3, "screen": 1.5, "tv_tower": 1.45, "stall": 1.4, "tractor": 1.35,
	"duck": 2.4, "mug": 2.2, "blocks": 1.9, "robot": 2.1, "snowman": 1.7, "cow": 1.45, "hay": 1.4, "tyre_wall": 1.0,
	"fence": 1.0, "flagpole": 1.45, "bench": 1.25, "ambulance": 1.35, "tow_truck": 1.35, "sledge": 1.35, "drums": 1.35,
	"fire_drum": 1.6, "scrap": 1.5}
## Spectators are drawn a little larger than life (readable from above).
const PERSON_SCALE := 1.45

## Crowd palette: the ten drivers' colours (as their helmets), then marshal
## orange and yellow, then neutral clothes.
const PALETTE := [Color("f7b731"), Color("e8e8f0"), Color("e8432e"), Color("59c3f2"), Color("7bc950"),
	Color("f45b9b"), Color("2ec4b6"), Color("a37ef0"), Color("ff8c2e"), Color("3d4a8a"),
	Color("ff7a1a"), Color("f7d23a"), Color("5a6a8a"), Color("f2efe6"), Color("3f6b4a"), Color("8a4a3a")]

var stage: VoxelStage
var main: Node2D
var vtrack: VoxelTrack
var theme_variant := 1
var _rng := RandomNumberGenerator.new()
var _occupied: Array = []
## Grandstands: [centre px, right (unit), front (unit), half width px, half depth px, MeshInstance3D].
var _stands: Array = []
var _people: Array = []
var _mms: Dictionary = {}
var _spinners: Array = []
var _cow_heads: Array = []
var _pennants: Array = []
var _smokers: Array = []
var _pulses: Array = []
var _clock := 0.0
var _time := 0.0
var _was_racing := false
var _cars := PackedVector2Array()
var _murmur: AudioStreamPlayer
var _last_shout := -10.0


func setup(p_stage: VoxelStage) -> void:
	stage = p_stage
	main = stage.main
	vtrack = stage.vtrack
	name = "Life"
	theme_variant = main.track_theme.variant if main.get("track_theme") != null and main.track_theme != null else 1
	var lay = main.track.get("layout")
	var layout_name := String((lay as Resource).resource_path) if lay is Resource else "x"  # (the arena's layout is no Resource)
	_rng.seed = hash(layout_name) + theme_variant * 31
	_gather_occupied()
	var cl = main.track.get("centerline")
	if cl == null or (cl as PackedVector2Array).size() < 8:
		return  # (the Battle Royale arena: no circuit to dress)
	_dress()
	_spawn_crowd()
	_spawn_critters()
	if stage.recorder != null:
		stage.recorder.moment.connect(_on_moment)
	if not _people.is_empty():
		_murmur = AudioStreamPlayer.new()
		_murmur.stream = SoundKit.stream("crowd_loop")
		_murmur.bus = "Effects"
		_murmur.volume_db = -60.0
		add_child(_murmur)
		_murmur.play()


# ------------------------------------------------------------ placement

func _gather_occupied() -> void:
	var props := stage.get_node_or_null("Props")
	if props != null:
		for n in props.get_children():
			if n is Node3D:
				var p: Vector3 = (n as Node3D).position
				_occupied.append([Vector2(p.x, p.z) / Vox.PX, 34.0])
				var mi := n as MeshInstance3D
				if mi != null and mi.mesh != null and mi.mesh.has_meta("grandstand"):
					var cells: Vector2i = mi.mesh.get_meta("cells")
					var b := mi.transform.basis
					var half := Vector2(cells) * Vox.CELL_PX * 0.5 * mi.scale.x
					_stands.append([Vector2(p.x, p.z) / Vox.PX, Vector2(b.x.x, b.x.z).normalized(),
						Vector2(b.z.x, b.z.z).normalized(), half.x, half.y, mi])
	for l in stage.lamps3d:
		var q := (l as Node3D).global_position
		_occupied.append([Vector2(q.x, q.z) / Vox.PX, 16.0])


func _inside(p: Vector2, r: float) -> bool:
	var lo := vtrack.origin_px + Vector2(r, r)
	var hi := vtrack.origin_px + Vector2(vtrack.nx, vtrack.nz) * VoxelTrack.CELL - Vector2(r, r)
	return p.x > lo.x and p.y > lo.y and p.x < hi.x and p.y < hi.y


## Free open grass for something of radius r (px): nothing drivable, no
## barrier, no other scenery, fairly level ground.
func _free(p: Vector2, r: float, level := true) -> bool:
	if not _inside(p, r + 8.0):
		return false
	var h0 := vtrack.height_px_at(p)
	var spots := [p]
	for k in 8:
		spots.append(p + Vector2.from_angle(k * TAU / 8.0) * r)
		spots.append(p + Vector2.from_angle(k * TAU / 8.0 + 0.4) * r * 0.5)
	for q in spots:
		if vtrack.class_at(q) != VoxelTrack.C_GRASS or vtrack.drivable_at(q):
			return false
		if level and absf(vtrack.height_px_at(q) - h0) > VoxelTrack.CELL * 1.5:
			return false
	for o in _occupied:
		if p.distance_to(o[0]) < r + float(o[1]):
			return false
	return not _in_stand(p, r)


## Whether a circle (px) overlaps a grandstand's footprint.
func _in_stand(p: Vector2, r: float) -> bool:
	for sb in _stands:
		var q: Vector2 = p - (sb[0] as Vector2)
		if absf(q.dot(sb[1])) < float(sb[3]) + r and absf(q.dot(sb[2])) < float(sb[4]) + r:
			return true
	return false


## A spot beside the road: the centre-line sample, its tangent, the outward
## normal on `side` (+1 right, -1 left) and the road's half width there.
func _frame(k: int, side: float) -> Array:
	var cl: PackedVector2Array = main.track.centerline
	var n := cl.size()
	var a := cl[(k - 2 + n) % n]
	var b := cl[(k + 2) % n]
	var t := (b - a).normalized()
	var r := Vector2(-t.y, t.x)
	var w := 75.0
	var lw = main.track.get("left_widths")
	var rw = main.track.get("right_widths")
	if lw != null and rw != null and k < lw.size():
		w = float(rw[k]) if side > 0.0 else float(lw[k])
	return [cl[k], t, r * side, w]


static func _yaw_facing(d: Vector2) -> float:
	return atan2(d.x, d.y)  # model +Z towards d


func _dress() -> void:
	var kit: Array = KITS.get(theme_variant, KITS[1])
	var cl: PackedVector2Array = main.track.centerline
	var holder := Node3D.new()
	holder.name = "Dressing"
	add_child(holder)
	var lights := 0
	for entry in kit:
		var kind: String = entry[0]
		var want: int = entry[1]
		var near: bool = entry[2]
		var sc: float = SCALE.get(kind, 1.3)
		var r := VoxelKit.radius_px(kind) * sc
		var placed := 0
		for attempt in want * 40:
			if placed >= want:
				break
			var k := _rng.randi_range(0, cl.size() - 1)
			var side := 1.0 if _rng.randf() < 0.5 else -1.0
			var f := _frame(k, side)
			var off := _rng.randf_range(52.0, 92.0) if near else _rng.randf_range(110.0, 360.0)
			var p: Vector2 = f[0] + (f[2] as Vector2) * (float(f[3]) + off + r)
			if not _free(p, r, kind != "fence" and kind != "tyre_wall"):
				continue
			placed += 1
			_occupied.append([p, r])
			var mi := MeshInstance3D.new()
			mi.mesh = VoxelKit.mesh(kind)
			mi.set_meta("kind", kind)
			mi.position = Vox.to3(p, vtrack.height_px_at(p))
			mi.scale = Vector3.ONE * sc
			var to_road := -(f[2] as Vector2)
			var t: Vector2 = f[1]
			if kind == "fence" or kind == "tyre_wall":
				mi.rotation.y = atan2(-t.y, t.x)  # along the road
			elif kind == "cow" or kind == "hay" or kind == "sledge" or kind == "drums" or kind == "scrap":
				mi.rotation.y = _rng.randf() * TAU
			else:
				mi.rotation.y = _yaw_facing(to_road)
			var tint := 1.0 + _rng.randf_range(-0.05, 0.05)
			mi.set_instance_shader_parameter("tint", Color(tint, tint, tint))
			holder.add_child(mi)
			if VoxelKit.glows(kind):
				stage._glowing.append(mi)
				if lights < 10 and kind != "fire_drum":
					lights += 1
					var l := OmniLight3D.new()
					l.light_color = Color(1.0, 0.8, 0.5)
					l.omni_range = 5.5
					l.light_energy = 1.4
					l.visible = false
					l.position = mi.position + Vector3(0, 1.0, 0) + Vector3(to_road.x, 0, to_road.y) * r * Vox.PX * 0.9
					holder.add_child(l)
					stage.lamps3d.append(l)
			_extras(kind, mi)
			# a little herd / a few bales / drums around their first one
			if kind == "cow" or kind == "hay":
				pass


## Moving parts and smoke sources of a placed kit piece.
func _extras(kind: String, mi: MeshInstance3D) -> void:
	match kind:
		"windmill":
			var sails := MeshInstance3D.new()
			sails.mesh = VoxelKit.part("sails")
			sails.position = Vector3(0, 22.0 * C, 6.4 * C)
			mi.add_child(sails)
			_spinners.append([sails, Vector3.BACK, 0.9])
		"shed":
			var fan := MeshInstance3D.new()
			fan.mesh = VoxelKit.part("fan")
			fan.position = Vector3(5.0 * C, 14.0 * C, -2.0 * C)
			mi.add_child(fan)
			_spinners.append([fan, Vector3.UP, 7.0])
		"cow":
			var head := MeshInstance3D.new()
			head.mesh = VoxelKit.part("cow_head")
			head.position = Vector3(3.2 * C, 4.0 * C, 0.0)
			mi.add_child(head)
			_cow_heads.append([head, mi])
		"flagpole":
			var pennant := MeshInstance3D.new()
			pennant.mesh = VoxelKit.part("pennant")
			pennant.position = Vector3(0.0, 21.0 * C, 0.0)
			mi.add_child(pennant)
			_pennants.append([pennant, _rng.randf() * TAU])
		"cottage":
			_smokers.append([mi, Vector3(3.5 * C, 18.0 * C, -3.5 * C), "chimney", 0.0])
		"cabin":
			_smokers.append([mi, Vector3(-5.5 * C, 18.0 * C, -3.5 * C), "chimney", 0.0])
		"fire_drum":
			_smokers.append([mi, Vector3(0.0, 5.5 * C, 0.0), "fire", 0.0])
		"mug":
			_smokers.append([mi, Vector3(0.0, 10.0 * C, 0.0), "steam", 0.0])
		"tractor":
			_smokers.append([mi, Vector3(3.0 * C, 9.0 * C, -1.5 * C), "exhaust", 0.0])


# ------------------------------------------------------------ the crowd

func _spawn_crowd() -> void:
	var cl: PackedVector2Array = main.track.centerline
	var n := cl.size()
	var anchors: Array = []  # [k, side, rows]
	# the start / finish straight: both sides, three rows
	var start: Vector2 = main.track.checkpoint_transform(0).origin
	var k0 := 0
	var bd := INF
	for k in n:
		var d := cl[k].distance_squared_to(start)
		if d < bd:
			bd = d
			k0 = k
	for dk in [-14, -6, 2, 10]:
		anchors.append([(k0 + dk + n) % n, 1.0, 3])
		anchors.append([(k0 + dk + 4 + n) % n, -1.0, 3])
	# then round the lap, keener on the outside of corners
	var total := 0.0
	var next := 300.0
	for k in n:
		total += cl[k].distance_to(cl[(k + 1) % n])
		if total < next:
			continue
		next += _rng.randf_range(380.0, 620.0)
		if absi(k - k0) < 20 or absi(k - k0) > n - 20:
			continue
		var a := cl[(k - 6 + n) % n]
		var b := cl[k]
		var c := cl[(k + 6) % n]
		var turn := wrapf((c - b).angle() - (b - a).angle(), -PI, PI)
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		if absf(turn) > 0.35:
			side = -signf(turn)  # outside of the bend (right normal = +1)
		anchors.append([k, side, 2])
	var crowd_rows: Array = []
	var flag_rows: Array = []
	for an in anchors:
		var f := _frame(int(an[0]), float(an[1]))
		var c: Vector2 = f[0]
		var t: Vector2 = f[1]
		var out: Vector2 = f[2]
		var base := float(f[3]) + _rng.randf_range(64.0, 76.0)
		var fav := _rng.randi_range(0, 9)
		if _rng.randf() < 0.3:
			fav = 0  # the player has fans too
		var count := _rng.randi_range(5, 9)
		for row in int(an[2]):
			for j in count + row:
				var along := (j - (count + row) * 0.5) * 19.0 + _rng.randf_range(-3.0, 3.0)
				var p := c + t * along + out * (base + row * 22.0 + _rng.randf_range(-2.0, 2.0))
				if not _free(p, 8.0, false):
					continue
				var shirt := fav if _rng.randf() < 0.5 else (_rng.randi_range(0, 9) if _rng.randf() < 0.4 else _rng.randi_range(12, 15))
				var person := {"p": p, "face": -out, "phase": _rng.randf(), "ex": 0.0, "shirt": shirt, "cloth": fav, "calm": false}
				if _rng.randf() < 0.12 and flag_rows.size() < MAX_FLAGS:
					flag_rows.append(person)
				elif crowd_rows.size() < MAX_CROWD:
					crowd_rows.append(person)
				_occupied.append([p, 5.0])
	# marshals: the four sharpest bends, on the outside, near the barrier
	var bends: Array = []
	for k in range(0, n, 3):
		var a := cl[(k - 8 + n) % n]
		var b := cl[k]
		var c := cl[(k + 8) % n]
		bends.append([absf(wrapf((c - b).angle() - (b - a).angle(), -PI, PI)), k, -signf(wrapf((c - b).angle() - (b - a).angle(), -PI, PI))])
	bends.sort_custom(func(x: Array, y: Array) -> bool: return x[0] > y[0])
	var marshals: Array = []
	for bd2 in bends:
		if marshals.size() >= 4:
			break
		var f := _frame(int(bd2[1]), float(bd2[2]) if float(bd2[2]) != 0.0 else 1.0)
		var p: Vector2 = f[0] + (f[2] as Vector2) * (float(f[3]) + 46.0)
		var ok := _free(p, 7.0, false)
		for m in marshals:
			if (m.p as Vector2).distance_to(p) < 400.0:
				ok = false
		if ok:
			marshals.append({"p": p, "face": -(f[2] as Vector2), "phase": _rng.randf(), "ex": 0.0, "shirt": 10, "cloth": 11, "calm": true})
			_occupied.append([p, 6.0])
	# warm light over a few of the stands at night
	var lit := 0
	for an in anchors:
		if lit >= 7 or _rng.randf() < 0.4:
			continue
		var f := _frame(int(an[0]), float(an[1]))
		var p: Vector2 = f[0] + (f[2] as Vector2) * (float(f[3]) + 80.0)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.84, 0.6)
		l.omni_range = 6.5
		l.light_energy = 1.3
		l.visible = false
		l.position = Vox.to3(p, vtrack.height_px_at(p)) + Vector3(0, 3.0, 0)
		add_child(l)
		stage.lamps3d.append(l)
		lit += 1
	var seated: Array = []
	var seated_flags: Array = []
	_seat_stands(seated, seated_flags)
	_make_people("crowd", crowd_rows, false, false)
	_make_people("flags", flag_rows, true, false)
	_make_people("marshals", marshals, true, true)
	_make_people("stand_crowd", seated, false, false)
	_make_people("stand_flags", seated_flags, true, false)


## P005: the grandstands take this theme's finish (seat colour, snow on the
## roof) and fill up: animated spectators sit in their seats, facing the
## track, their legs out of sight in the seat row (the hop of a cheer lifts
## them out of their seats). Their roof lamps glow at night.
func _seat_stands(seated: Array, seated_flags: Array) -> void:
	for n in _stands.size():
		var sb: Array = _stands[n]
		var mi: MeshInstance3D = sb[5]
		var cells: Vector2i = mi.mesh.get_meta("cells")
		mi.mesh = Grandstand.mesh(cells.x, cells.y, theme_variant, false, n)
		stage._glowing.append(mi)
		var xf := mi.transform
		var face: Vector2 = sb[2]
		var fav := _rng.randi_range(0, 9)
		if _rng.randf() < 0.3:
			fav = 0
		var seats: PackedVector3Array = mi.mesh.get_meta("seats")
		for s: Vector3 in seats:
			if _rng.randf() > SEATED_FILL or seated.size() + seated_flags.size() >= MAX_SEATED:
				continue
			var w: Vector3 = xf * s
			var shirt: int = fav if _rng.randf() < 0.4 else (_rng.randi_range(0, 9) if _rng.randf() < 0.45 else _rng.randi_range(12, 15))
			var person := {"p": Vector2(w.x, w.z) / Vox.PX, "face": face, "phase": _rng.randf(), "ex": 0.0,
				"shirt": shirt, "cloth": fav, "calm": false, "seat": w.y / Vox.PX}
			if _rng.randf() < 0.08:
				seated_flags.append(person)
			else:
				seated.append(person)
		# warm light under the roof at night
		for side in [-1.0, 1.0]:
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.86, 0.64)
			l.omni_range = 6.5
			l.light_energy = 1.0
			l.visible = false
			l.position = xf * Vector3(4.6 * side, 4.4, 0.2)
			add_child(l)
			stage.lamps3d.append(l)


func _make_people(key: String, list: Array, flag: bool, calm: bool) -> void:
	if list.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = VoxelLife.person_mesh(flag)
	mm.instance_count = list.size()
	var mat := ShaderMaterial.new()
	mat.shader = CROWD_SHADER
	var pal := PackedVector3Array()
	for col in PALETTE:
		var lc := (col as Color).srgb_to_linear()
		pal.append(Vector3(lc.r, lc.g, lc.b))
	mat.set_shader_parameter("palette", pal)
	mat.set_shader_parameter("flags", 1.0 if flag else 0.0)
	mat.set_shader_parameter("calm", 1.0 if calm else 0.0)
	var mi := MultiMeshInstance3D.new()
	mi.name = key.capitalize()
	mi.multimesh = mm
	mi.material_override = mat
	mi.extra_cull_margin = 4096.0
	add_child(mi)
	for i in list.size():
		var person: Dictionary = list[i]
		var p: Vector2 = person.p
		var s := _rng.randf_range(0.92, 1.08) * PERSON_SCALE
		# (seated: the hips on the seat, the legs hidden in the seat row)
		var h: float = float(person.seat) - 0.42 * s / Vox.PX if person.has("seat") else vtrack.height_px_at(p)
		var xf := Transform3D(Basis(Vector3.UP, _yaw_facing(person.face)).scaled(Vector3.ONE * s), Vox.to3(p, h))
		mm.set_instance_transform(i, xf)
		person["mm"] = mm
		person["i"] = i
		person["idx"] = (int(person.shirt) + 16 * int(person.cloth)) / 255.0
		_people.append(person)
		mm.set_instance_custom_data(i, Color(person.phase, 0.0, 0.5, person.idx))
	_mms[key] = mm


## A little spectator (about 1.2 units tall, facing +Z), parts in UV2.x.
static var _person_meshes: Dictionary = {}


static func person_mesh(flag: bool) -> ArrayMesh:
	if _person_meshes.has(flag):
		return _person_meshes[flag]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var denim := Color(0.16, 0.18, 0.28).srgb_to_linear()
	_cube(st, Vector3(-0.17, 0.0, -0.08), Vector3(-0.03, 0.42, 0.08), denim, 0.0)
	_cube(st, Vector3(0.03, 0.0, -0.08), Vector3(0.17, 0.42, 0.08), denim, 0.0)
	_cube(st, Vector3(-0.2, 0.42, -0.12), Vector3(0.2, 0.86, 0.12), Color.WHITE, 1.0)
	_cube(st, Vector3(-0.14, 0.88, -0.13), Vector3(0.14, 1.15, 0.13), Color.WHITE, 2.0)
	_cube(st, Vector3(-0.15, 1.12, -0.14), Vector3(0.15, 1.21, 0.18), Color.WHITE, 6.0)
	for side in [-1.0, 1.0]:
		var part := 3.0 if side < 0.0 else 4.0
		_cube(st, Vector3(0.2 * side if side > 0.0 else -0.32, 0.5, -0.06), Vector3(0.32 if side > 0.0 else -0.2, 0.84, 0.06), Color.WHITE, part)
		_cube(st, Vector3(0.21 if side > 0.0 else -0.31, 0.42, -0.05), Vector3(0.31 if side > 0.0 else -0.21, 0.5, 0.05), Color.WHITE, part, 1.0)
	if flag:
		_cube(st, Vector3(0.245, -0.36, -0.015), Vector3(0.275, 0.44, 0.015), Color(0.85, 0.8, 0.7).srgb_to_linear(), 5.0)
		_cube(st, Vector3(0.275, -0.36, -0.012), Vector3(0.62, -0.12, 0.012), Color.WHITE, 7.0)
	var mesh := st.commit()
	_person_meshes[flag] = mesh
	return mesh


static func _cube(st: SurfaceTool, a: Vector3, b: Vector3, col: Color, part: float, sub: float = 0.0) -> void:
	var faces := [
		[Vector3(1, 0, 0), [Vector3(b.x, a.y, a.z), Vector3(b.x, b.y, a.z), Vector3(b.x, b.y, b.z), Vector3(b.x, a.y, b.z)]],
		[Vector3(-1, 0, 0), [Vector3(a.x, a.y, b.z), Vector3(a.x, b.y, b.z), Vector3(a.x, b.y, a.z), Vector3(a.x, a.y, a.z)]],
		[Vector3(0, 1, 0), [Vector3(a.x, b.y, a.z), Vector3(a.x, b.y, b.z), Vector3(b.x, b.y, b.z), Vector3(b.x, b.y, a.z)]],
		[Vector3(0, -1, 0), [Vector3(a.x, a.y, b.z), Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, a.y, b.z)]],
		[Vector3(0, 0, 1), [Vector3(b.x, a.y, b.z), Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z), Vector3(a.x, a.y, b.z)]],
		[Vector3(0, 0, -1), [Vector3(a.x, a.y, a.z), Vector3(a.x, b.y, a.z), Vector3(b.x, b.y, a.z), Vector3(b.x, a.y, a.z)]],
	]
	for f in faces:
		var nrm: Vector3 = f[0]
		var q: Array = f[1]
		var shade := 1.0 if nrm.y > 0.5 else (0.82 if nrm.y < -0.5 else 0.92)
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(nrm)
			st.set_color(Color(col.r * shade, col.g * shade, col.b * shade))
			st.set_uv2(Vector2(part, sub))
			st.add_vertex(q[idx])


# ------------------------------------------------------------ critters

func _spawn_critters() -> void:
	var cl: PackedVector2Array = main.track.centerline
	if theme_variant == 1 or theme_variant == 4:
		var spots: Array = []
		for attempt in 400:
			if spots.size() >= 40:
				break
			var k := _rng.randi_range(0, cl.size() - 1)
			var f := _frame(k, 1.0 if _rng.randf() < 0.5 else -1.0)
			var p: Vector2 = f[0] + (f[2] as Vector2) * (float(f[3]) + _rng.randf_range(90.0, 300.0))
			if _free(p, 10.0, false):
				spots.append(p)
		_critter_mm("Butterflies", spots, false)
	var birds: Array = []
	for b in 7:
		birds.append(cl[_rng.randi_range(0, cl.size() - 1)] + Vector2(_rng.randf_range(-300, 300), _rng.randf_range(-300, 300)))
	_critter_mm("Birds", birds, true)


func _critter_mm(key: String, spots: Array, bird: bool) -> void:
	if spots.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var s := 3.2 if bird else 1.0
	_cube(st, Vector3(-0.1, -0.02, -0.025) * s, Vector3(0.1, 0.02, 0.025) * s, Color.WHITE * 0.6, 2.0)
	_cube(st, Vector3(-0.07, -0.005, 0.025) * s, Vector3(0.07, 0.005, 0.24) * s, Color.WHITE, 0.0)
	_cube(st, Vector3(-0.07, -0.005, -0.24) * s, Vector3(0.07, 0.005, -0.025) * s, Color.WHITE, 1.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = st.commit()
	mm.instance_count = spots.size()
	var mat := ShaderMaterial.new()
	mat.shader = CRITTER_SHADER
	if bird:
		mat.set_shader_parameter("radius", 7.0)
		mat.set_shader_parameter("height", 11.0)
		mat.set_shader_parameter("bob", 1.0)
		mat.set_shader_parameter("speed", 0.22)
		mat.set_shader_parameter("flap_speed", 7.0)
		mat.set_shader_parameter("flap", 0.7)
	var pastel := [Color("fff4de"), Color("f7b731"), Color("f45b9b"), Color("59c3f2"), Color("ff8c2e"), Color("a37ef0")]
	for i in spots.size():
		var p: Vector2 = spots[i]
		mm.set_instance_transform(i, Transform3D(Basis(), Vox.to3(p, vtrack.height_px_at(p))))
		mm.set_instance_color(i, Color(0.13, 0.13, 0.16) if bird else pastel[i % pastel.size()])
		mm.set_instance_custom_data(i, Color(_rng.randf(), 0, 0, 0))
	var mi := MultiMeshInstance3D.new()
	mi.name = key
	mi.multimesh = mm
	mi.material_override = mat
	mi.extra_cull_margin = 4096.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if not bird else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)


# ------------------------------------------------------------ reactions

## Excitement around a 2D point (px): radius, strength 0..1.
func pulse(at: Vector2, radius: float, strength: float) -> void:
	_pulses.append([at, radius, strength, _time])
	while _pulses.size() > 24:
		_pulses.pop_front()


func _on_moment(e: Dictionary) -> void:
	var p: Vector2 = e.get("pos", Vector2.ZERO)
	match String(e.kind):
		"overtake":
			pulse(p, 420.0, 0.6 if not bool(e.get("final", false)) else 1.0)
			_shout("cheer", p, -14.0)
		"crash":
			if float(e.get("speed", 0.0)) > 260.0:
				pulse(p, 320.0, 0.55)
				_shout("gasp", p, -12.0)
		"destroyed", "wreck", "pileup":
			pulse(p, 700.0, 1.0)
			cheered.emit(1.0)
			_shout("gasp", p, -8.0)
			get_tree().create_timer(0.7).timeout.connect(func() -> void: _shout("cheer", p, -8.0, true))
		"finish":
			pulse(p, 900.0, 1.0)
			_shout("applause", p, -6.0, true)
		"taunt":
			pulse(p, 320.0, 0.7)
		"air":
			pulse(p, 450.0, 0.8)
			_shout("cheer", p, -12.0)
		"hit", "mine_blast":
			pulse(p, 450.0, 0.7)


## A crowd reaction near p, if there are people near it and near the view.
func _shout(name: String, p: Vector2, db: float, force := false) -> void:
	if _people.is_empty() or (not force and _time - _last_shout < 1.2):
		return
	if main.get("race_audio") != null and main.race_audio != null and main.race_audio.fast:
		return
	var cam2: Camera2D = main.camera
	var d := p.distance_to(cam2.get_screen_center_position())
	if d > 1100.0:
		return
	_last_shout = _time
	SoundKit.play(self, name, db - d / 1100.0 * 10.0, 0.06)


func _process__perf(delta: float) -> void:
	if not stage.ready_3d:
		return
	_time += delta
	for s in _spinners:
		(s[0] as Node3D).rotate_object_local(s[1], float(s[2]) * delta)
	for pn in _pennants:
		(pn[0] as Node3D).rotation.y = sin(_time * 2.3 + float(pn[1])) * 0.35
	_smoke(delta)
	_clock += delta
	if _clock < TICK:
		return
	var dt := _clock
	_clock = 0.0
	_cars.clear()
	for c in main.cars:
		if (c as Car).visible:
			_cars.append((c as Car).global_position)
	# the start: everybody up
	var racing: bool = main.get("session") != null and main.session.state == RaceSession.State.RACING
	if racing and not _was_racing:
		for person in _people:
			person.ex = 1.0
		cheered.emit(0.8)
		_shout("cheer", main.camera.get_screen_center_position(), -6.0, true)
	_was_racing = racing
	_update_people(dt)
	_update_cows(dt)
	if _murmur != null:
		var cam2: Camera2D = main.camera
		var ex := excitement_near(cam2.get_screen_center_position(), 750.0)
		var quiet: bool = main.get("race_audio") != null and main.race_audio != null and main.race_audio.fast
		var want := -60.0 if quiet else lerpf(-30.0, -11.0, clampf(ex * 1.4, 0.0, 1.0))
		_murmur.volume_db = lerpf(_murmur.volume_db, want, 1.0 - exp(-dt * 3.0))


func _update_people__perf(dt: float) -> void:
	var live: Array = []
	for pl in _pulses:
		var age := _time - float(pl[3])
		if age < 3.5:
			live.append([pl[0], pl[1], float(pl[2]) * exp(-age * 0.9)])
	_pulses = _pulses.filter(func(pl: Array) -> bool: return _time - float(pl[3]) < 3.5)
	for person in _people:
		var p: Vector2 = person.p
		var best := INF
		var to := Vector2.ZERO
		for c in _cars:
			var d := p.distance_squared_to(c)
			if d < best:
				best = d
				to = c - p
		best = sqrt(best)
		var target := 0.08 + 0.5 * (1.0 - smoothstep(90.0, 360.0, best))
		for pl in live:
			var d := p.distance_to(pl[0])
			if d < float(pl[1]):
				target += float(pl[2]) * (1.0 - d / float(pl[1]))
		if bool(person.calm):
			target *= 0.6
		target = clampf(target, 0.0, 1.0)
		var ex: float = person.ex
		ex = lerpf(ex, target, 1.0 - exp(-dt * (6.0 if target > ex else 1.3)))
		person.ex = ex
		var look := 0.0
		if best < 700.0:
			look = clampf(wrapf(to.angle() - (person.face as Vector2).angle(), -PI, PI), -1.35, 1.35)
		else:
			look = sin(_time * 0.4 + float(person.phase) * 20.0) * 0.5
		(person.mm as MultiMesh).set_instance_custom_data(int(person.i), Color(person.phase, ex, 0.5 + look / 3.0, person.idx))


func _update_cows(dt: float) -> void:
	for ch in _cow_heads:
		var head: Node3D = ch[0]
		var cow: Node3D = ch[1]
		var p := Vector2(cow.global_position.x, cow.global_position.z) / Vox.PX
		var best := INF
		var to := Vector2.ZERO
		for c in _cars:
			var d := p.distance_squared_to(c)
			if d < best:
				best = d
				to = c - p
		var want := 0.0
		if best < 500.0 * 500.0:
			# the cow's nose (+X) towards the car: world yaw of +X is -rot.y
			var world := -to.angle()
			want = clampf(wrapf(world - cow.rotation.y, -PI, PI), -1.1, 1.1)
		head.rotation.y = lerp_angle(head.rotation.y, want, 1.0 - exp(-dt * 2.5))


func _smoke(delta: float) -> void:
	var fx: VoxelFx = stage.race_fx.fx if stage.race_fx != null else null
	if fx == null:
		return
	for s in _smokers:
		s[3] = float(s[3]) + delta
		var rate := {"chimney": 0.7, "fire": 0.12, "steam": 0.5, "exhaust": 1.6}.get(String(s[2]), 1.0) as float
		if float(s[3]) < rate:
			continue
		s[3] = 0.0
		var at: Vector3 = (s[0] as Node3D).global_transform * (s[1] as Vector3)
		match String(s[2]):
			"chimney":
				var g := _rng.randf_range(0.7, 0.82)
				fx.puff(at, Vector3(0.25, 0.7, 0.12), Color(g, g, g * 1.02), _rng.randf_range(0.35, 0.5), _rng.randf_range(2.6, 3.4), 0.45)
			"steam":
				fx.puff(at, Vector3(0.05, 0.6, 0.02), Color(0.97, 0.97, 0.97), 0.3, 2.0, 0.35)
			"fire":
				fx.spark(at, Vector3(_rng.randf_range(-0.2, 0.2), 1.4, _rng.randf_range(-0.2, 0.2)), Color(1.0, 0.55, 0.15), 0.08, 0.6, 1.2, -0.2)
				if _rng.randf() < 0.15:
					fx.puff(at, Vector3(0.1, 0.8, 0.0), Color(0.25, 0.24, 0.24), 0.3, 1.8, 0.4)
			"exhaust":
				fx.puff(at, Vector3(0.0, 0.5, 0.0), Color(0.5, 0.5, 0.5), 0.2, 1.2, 0.35)


## How excited the crowd near a point is (0..1), e.g. for crowd sound.
func excitement_near(at: Vector2, radius: float = 600.0) -> float:
	var sum := 0.0
	var n := 0
	for person in _people:
		if (person.p as Vector2).distance_to(at) < radius:
			sum += float(person.ex)
			n += 1
	return sum / n if n > 0 else 0.0


func crowd_size() -> int:
	return _people.size()


## DIAGNOSTIC probe (Performance Investigation 001)
func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process__perf(delta)
	PerfProbe.add(&"pres.life", __t)


## DIAGNOSTIC probe (Performance Investigation 001)
func _update_people(dt: float) -> void:
	var __t := Time.get_ticks_usec()
	_update_people__perf(dt)
	PerfProbe.add(&"pres.life_people", __t)
