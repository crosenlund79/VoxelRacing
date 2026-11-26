extends Node3D
## VoxelRacing: the garage's mechanic, a blocky voxel figure (boots, teal
## overalls, a red cap, a moustache and a spanner) who potters about the
## workshop: tinkers at the bench, rummages in the tool chest, polishes the
## car, glances at the camera. When the player repairs the car he rushes in,
## hammers away and gives a thumbs-up. Presentation only (GarageWorkshop
## drives him). Loaded with preload (no class_name).

## Each hammer blow on the car (or the bench): the spanner's tip, in world space.
signal struck(at: Vector3)

const Prop := preload("res://src/ui/garage_workshop_props.gd")
const VS := 0.1
const OVERALLS := Color("1f8f86")
const OVERALLS_DARK := Color("17665f")
const BOOT := Color(0.16, 0.11, 0.08)
const SHIRT := Color("fff4de")
const CAP := Color("e8432e")

## Where he likes to be: {pos: Vector3, face: Vector3 (point to look at),
## act: "tinker" | "polish" | "rummage" | "look", time: float}.
var spots: Array = []
var camera_hint := Vector3(0, 2, 10)

var _body: Node3D
var _hips: Node3D
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _head: Node3D
var _tool: MeshInstance3D
var _rng := RandomNumberGenerator.new()
var _queue: Array = []
var _task: Dictionary = {}
var _t := 0.0
var _phase := 0.0
var _yaw_target := 0.0
var _spot := -1
var _last_strike := 0


func _ready() -> void:
	_rng.seed = 1979
	_build()


func _build() -> void:
	_body = Node3D.new()
	add_child(_body)
	_hips = Node3D.new()
	_hips.position = Vector3(0, 6 * VS, 0)
	_body.add_child(_hips)
	for side in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		leg.mesh = _leg_mesh()
		leg.position = Vector3(0, 0, side * VS)
		_hips.add_child(leg)
		_legs.append(leg)
	var torso := MeshInstance3D.new()
	torso.mesh = _torso_mesh()
	_hips.add_child(torso)
	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(0, 4.6 * VS, side * 3.0 * VS)
		_hips.add_child(arm)
		var am := MeshInstance3D.new()
		am.mesh = _arm_mesh()
		arm.add_child(am)
		_arms.append(arm)
	# the spanner in his right hand (arm 1 is +Z: his right when facing +X)
	_tool = MeshInstance3D.new()
	_tool.mesh = _spanner_mesh()
	_tool.position = Vector3(0.05, -5.0 * VS, 0)
	_arms[1].add_child(_tool)
	_head = Node3D.new()
	_head.position = Vector3(0, 5.0 * VS, 0)
	_hips.add_child(_head)
	var hm := MeshInstance3D.new()
	hm.mesh = _head_mesh()
	_head.add_child(hm)


# ------------------------------------------------------------ models

static func _grid(size: Vector3i) -> VoxelGrid:
	return VoxelGrid.new(size, VS, Vector3.ZERO)


static func _mesh(g: VoxelGrid, pivot: Vector3) -> ArrayMesh:
	return VoxelMesher.build_mesh(g, VoxelCars.material(), pivot * VS, 0.04)


## A leg with its boot, hanging from the hip (pivot at the top).
static func _leg_mesh() -> ArrayMesh:
	var g := _grid(Vector3i(3, 6, 2))
	g.box(Vector3i(0, 2, 0), Vector3i(1, 5, 1), Vox.SOLID, OVERALLS)
	g.box(Vector3i(0, 2, 0), Vector3i(1, 2, 1), Vox.SOLID, OVERALLS_DARK)
	g.box(Vector3i(0, 0, 0), Vector3i(2, 1, 1), Vox.SOLID, BOOT)
	return _mesh(g, Vector3(1.0, 6.0, 1.0))


## The torso: shirt sleeves' shoulders, the overalls' bib with a pocket and a
## badge, a belt. Pivot at the hips (bottom centre).
static func _torso_mesh() -> ArrayMesh:
	var g := _grid(Vector3i(3, 5, 4))
	g.box(Vector3i(0, 0, 0), Vector3i(2, 4, 3), Vox.SOLID, OVERALLS)
	g.box(Vector3i(0, 4, 0), Vector3i(2, 4, 3), Vox.SOLID, SHIRT)
	g.box(Vector3i(0, 3, 0), Vector3i(2, 3, 0), Vox.SOLID, SHIRT)
	g.box(Vector3i(0, 3, 3), Vector3i(2, 3, 3), Vox.SOLID, SHIRT)
	g.box(Vector3i(0, 0, 0), Vector3i(2, 0, 3), Vox.SOLID, Color(0.2, 0.14, 0.1))  # belt
	g.set_v(2, 0, 1, Vox.METAL, Color(0.85, 0.75, 0.4))  # buckle
	g.set_v(2, 2, 1, Vox.SOLID, OVERALLS_DARK)  # pocket
	g.set_v(2, 2, 2, Vox.SOLID, VrStyle.YELLOW)  # badge
	return _mesh(g, Vector3(1.5, 0.0, 2.0))


## An arm: overalls at the shoulder, a rolled-up shirt sleeve and a hand.
## Hangs from the shoulder (pivot at the top).
static func _arm_mesh() -> ArrayMesh:
	var g := _grid(Vector3i(2, 5, 2))
	g.box(Vector3i(0, 1, 0), Vector3i(1, 4, 1), Vox.SOLID, SHIRT)
	g.box(Vector3i(0, 3, 0), Vector3i(1, 4, 1), Vox.SOLID, OVERALLS)
	g.box(Vector3i(0, 0, 0), Vector3i(1, 0, 1), Vox.SOLID, Prop.SKIN)
	return _mesh(g, Vector3(1.0, 5.0, 1.0))


## The head (face towards +X): eyes, a big moustache, hair at the back, ears,
## the red cap with its peak. Pivot at the neck (bottom centre).
static func _head_mesh() -> ArrayMesh:
	var g := _grid(Vector3i(6, 6, 4))
	g.box(Vector3i(0, 0, 0), Vector3i(3, 3, 3), Vox.SOLID, Prop.SKIN)
	g.box(Vector3i(0, 1, 0), Vector3i(0, 3, 3), Vox.SOLID, Color(0.3, 0.18, 0.1))  # hair
	g.set_v(3, 2, 1, Vox.SOLID, Color(0.08, 0.08, 0.12))
	g.set_v(3, 2, 2, Vox.SOLID, Color(0.08, 0.08, 0.12))
	g.box(Vector3i(3, 1, 0), Vector3i(3, 1, 3), Vox.SOLID, Color(0.32, 0.18, 0.1))  # moustache
	g.set_v(4, 1, 1, Vox.SOLID, Prop.SKIN.darkened(0.1))  # nose
	g.set_v(4, 1, 2, Vox.SOLID, Prop.SKIN.darkened(0.1))
	g.box(Vector3i(0, 4, 0), Vector3i(3, 4, 3), Vox.SOLID, CAP)
	g.box(Vector3i(1, 5, 1), Vector3i(2, 5, 2), Vox.SOLID, CAP)
	g.box(Vector3i(4, 4, 0), Vector3i(5, 4, 3), Vox.SOLID, CAP.darkened(0.25))  # the peak
	g.set_v(3, 4, 1, Vox.SOLID, VrStyle.YELLOW)
	g.set_v(3, 4, 2, Vox.SOLID, VrStyle.YELLOW)
	return _mesh(g, Vector3(2.0, 0.0, 2.0))


## A spanner held pointing forward (+X) from the hand.
static func _spanner_mesh() -> ArrayMesh:
	var g := _grid(Vector3i(5, 1, 3))
	g.box(Vector3i(0, 0, 1), Vector3i(3, 0, 1), Vox.METAL, Prop.STEEL)
	g.set_v(4, 0, 0, Vox.METAL, Prop.STEEL)
	g.set_v(4, 0, 2, Vox.METAL, Prop.STEEL)
	return _mesh(g, Vector3(0.5, 0.5, 1.5))



# ------------------------------------------------------------ behaviour

## Rushes to `at`, faces `look`, hammers for `work` seconds, then a thumbs-up.
func rush_to(at: Vector3, look: Vector3, work: float) -> void:
	_queue = [
		{"kind": "walk", "to": at, "speed": 4.2},
		{"kind": "act", "act": "repair", "time": work, "face": look},
		{"kind": "act", "act": "cheer", "time": 1.1, "face": camera_hint},
		{"kind": "act", "act": "look", "time": 0.8, "face": look},
	]
	_next_task()


## Stands at `at` facing `look` (no walking): a place to start from.
func place(at: Vector3, look: Vector3) -> void:
	position = at
	_face_now(look)
	_queue.clear()
	_task = {}


func is_busy_repairing() -> bool:
	return _task.get("act", "") == "repair"


## The tip of the spanner (world space).
func tool_tip() -> Vector3:
	return _tool.global_transform * Vector3(0.45, 0, 0)


func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	_t += delta
	if _task.is_empty():
		_next_task()
	var kind: String = _task.get("kind", "")
	if kind == "walk":
		_walk(delta)
	else:
		_act(delta)
	rotation.y = lerp_angle(rotation.y, _yaw_target, minf(1.0, delta * 9.0))


func _next_task() -> void:
	if _queue.is_empty():
		_queue = _idle_plan()
	_task = _queue.pop_front()
	_task["t"] = 0.0
	_last_strike = 0
	if _task.has("face"):
		_yaw_target = _yaw_to(_task.face)


## The next errand: another of his spots (never the same twice in a row).
func _idle_plan() -> Array:
	if spots.is_empty():
		return [{"kind": "act", "act": "look", "time": 2.0, "face": camera_hint}]
	var k := _rng.randi_range(0, spots.size() - 1)
	if k == _spot:
		k = (k + 1) % spots.size()
	_spot = k
	var s: Dictionary = spots[k]
	var face: Vector3 = camera_hint if s.act == "look" else s.face
	return [
		{"kind": "walk", "to": s.pos, "speed": 1.5},
		{"kind": "act", "act": s.act, "time": float(s.time) * _rng.randf_range(0.8, 1.25), "face": face},
	]


func _walk(delta: float) -> void:
	var to: Vector3 = _task.to
	var speed: float = _task.speed
	var d := Vector3(to.x - position.x, 0, to.z - position.z)
	var dist := d.length()
	if dist < 0.05:
		position = Vector3(to.x, position.y, to.z)
		_task = {}
		_pose_rest(delta)
		return
	_yaw_target = atan2(-d.z, d.x)
	var step := minf(dist, speed * delta)
	position += d / dist * step
	var run := clampf(speed / 4.0, 0.35, 1.0)
	_phase += step * (5.5 if run < 0.6 else 3.4)
	var s := sin(_phase)
	_legs[0].rotation.z = s * (0.55 + run * 0.25)
	_legs[1].rotation.z = -s * (0.55 + run * 0.25)
	_arms[0].rotation.z = -s * (0.5 + run * 0.4)
	_arms[1].rotation.z = s * (0.5 + run * 0.4)
	_arms[0].rotation.x = 0.0
	_arms[1].rotation.x = 0.0
	_body.position.y = absf(cos(_phase)) * 0.05 * (1.0 + run)
	_body.rotation.z = -0.08 * run
	_head.rotation = Vector3(0, 0, 0)


func _act(delta: float) -> void:
	_task.t = float(_task.get("t", 0.0)) + delta
	var t: float = _task.t
	var act: String = _task.get("act", "look")
	_legs[0].rotation.z = lerpf(_legs[0].rotation.z, 0.0, delta * 10.0)
	_legs[1].rotation.z = lerpf(_legs[1].rotation.z, 0.0, delta * 10.0)
	_body.rotation.z = lerpf(_body.rotation.z, 0.0, delta * 8.0)
	var breathe := sin(_t * 2.2) * 0.012
	match act:
		"tinker":  # slow, careful blows at the bench, head down
			_arms[1].rotation.z = 1.2 + 0.8 * _blow(fposmod(t * 1.3, 1.0), 0.7)
			_arms[0].rotation.z = lerpf(_arms[0].rotation.z, 0.9, delta * 6.0)
			_head.rotation.z = lerpf(_head.rotation.z, -0.35, delta * 5.0)
			_body.position.y = breathe
			_strike_on(int(t * 1.3 + 0.88 - 0.7))
		"repair":  # quick blows on the car
			_arms[1].rotation.z = 1.0 + 1.2 * _blow(fposmod(t * 3.6, 1.0), 0.55)
			_arms[0].rotation.z = lerpf(_arms[0].rotation.z, 1.0, delta * 8.0)
			_head.rotation.z = lerpf(_head.rotation.z, -0.3, delta * 8.0)
			_body.position.y = -0.04 + absf(sin(t * 11.3)) * 0.015
			_body.rotation.z = 0.12
			_strike_on(int(t * 3.6 + 0.88 - 0.55))
		"polish":  # circles with the rag hand
			_arms[0].rotation.z = 1.25 + sin(t * 5.0) * 0.25
			_arms[0].rotation.x = cos(t * 5.0) * 0.25
			_arms[1].rotation.z = lerpf(_arms[1].rotation.z, 0.2, delta * 6.0)
			_head.rotation.z = lerpf(_head.rotation.z, -0.2, delta * 5.0)
			_body.position.y = breathe + sin(t * 5.0) * 0.01
		"rummage":  # bent over the tool chest
			_arms[0].rotation.z = 0.9 + sin(t * 6.0) * 0.3
			_arms[1].rotation.z = 0.9 + sin(t * 6.0 + 2.0) * 0.3
			_body.rotation.z = lerpf(_body.rotation.z, -0.25, delta * 6.0)
			_head.rotation.z = lerpf(_head.rotation.z, -0.3, delta * 5.0)
			_body.position.y = breathe
		"cheer":  # a hop and a thumbs-up
			_arms[1].rotation.z = lerpf(_arms[1].rotation.z, PI * 0.92, delta * 14.0)
			_arms[0].rotation.z = lerpf(_arms[0].rotation.z, -0.3, delta * 10.0)
			_head.rotation.z = lerpf(_head.rotation.z, 0.15, delta * 8.0)
			_body.position.y = maxf(0.0, sin(minf(t, 0.45) / 0.45 * PI)) * 0.22
		_:  # "look": stands easy, looks around, scratches his head now and then
			var scratch := fposmod(t, 6.0) > 4.4
			_pose_rest(delta, not scratch)
			_head.rotation.y = sin(t * 0.9) * 0.45
			_body.position.y = breathe
			if scratch:
				_arms[1].rotation.z = lerpf(_arms[1].rotation.z, 2.6, delta * 8.0)
				_arms[1].rotation.x = lerpf(_arms[1].rotation.x, -0.35, delta * 8.0)
	if t >= float(_task.get("time", 1.0)):
		_task = {}


## Arms down, head straight (the right arm too unless `right_arm` is false).
func _pose_rest(delta: float, right_arm: bool = true) -> void:
	for k in _arms.size():
		if k == 1 and not right_arm:
			continue
		_arms[k].rotation.z = lerpf(_arms[k].rotation.z, 0.08, delta * 7.0)
		_arms[k].rotation.x = lerpf(_arms[k].rotation.x, 0.0, delta * 7.0)
	_head.rotation.z = lerpf(_head.rotation.z, 0.0, delta * 6.0)
	_head.rotation.y = lerpf(_head.rotation.y, 0.0, delta * 6.0)
	_body.position.y = lerpf(_body.position.y, 0.0, delta * 8.0)


## A hammer blow over one cycle 0..1: raised slowly until `up`, then
## brought down fast (the blow lands at up + 0.12). 1 = raised.
static func _blow(cyc: float, up: float) -> float:
	if cyc < up:
		return smoothstep(0.0, up, cyc)
	return 1.0 - clampf((cyc - up) / 0.12, 0.0, 1.0)


func _strike_on(n: int) -> void:
	if n > _last_strike:
		_last_strike = n
		struck.emit(tool_tip())


func _face_now(look: Vector3) -> void:
	_yaw_target = _yaw_to(look)
	rotation.y = _yaw_target


func _yaw_to(look: Vector3) -> float:
	var d := Vector3(look.x - position.x, 0, look.z - position.z)
	if d.length() < 0.01:
		return rotation.y
	return atan2(-d.z, d.x)
