class_name VoxelCarDamage
extends RefCounted
## VoxelRacing: a car coming apart, component by component (P006).
##
## The race's own damage state (DamageWorld condition) sets how much damage
## the car shows. Each loss of condition is shared out over the car's
## components, most of it to those on the side that was hit (wall normal,
## the other car, the weapon blast; +X nose, +Z right): a component takes
## the knocks until it looks battered, and a detachable one breaks away
## whole once it has taken its toughness (a light knock never takes a door
## off). Inner parts (radiator, exhaust, tank) only go when the car is badly
## hurt; the crash cell never goes. Lamps go with their light assemblies (the
## car's lights follow). An explosion throws everything still attached
## except the cell and the engine block, which stay as a charred wreck.
##
## Nothing is re-meshed: the shared vehicle mesh shows or hides components
## through instance masks. Repairs / respawns restore the model.
## Presentation only: it never changes the race's damage.

## Damage starts to show below this condition share.
const SHOW_FROM := 0.97
## Component damage handed out per unit of condition lost, as a share of
## the car's total toughness (at zero condition about half the bodywork is
## gone; the cell and the car's shape stay).
const SPREAD := 1.15
## A component looks battered from this share of its toughness.
const HURT_AT := 0.32
## How strongly the hit side is favoured (higher: more focused).
const FOCUS := 4.0
## Inner components only take damage below this condition (heavy damage).
const INNER_FROM := 0.5

var model: VoxelVehicle.Model
var mesh_instance: MeshInstance3D
var hits := PackedFloat32Array()
var gone := PackedByteArray()
var hurt := PackedByteArray()
var total := 0  ## detachable components
var removed := 0  ## components gone
var applied := 0.0  ## condition loss shown (0..1)
var dirty := false
var wrecked := false
## Set by restore(true): the next damage is applied without debris (a
## respawned or repaired car simply shows what it still carries).
var quiet := false
## Lamps left, per side (front-left, front-right, rear-left, rear-right).
var lamps := PackedInt32Array([1, 1, 1, 1])
var _rng := RandomNumberGenerator.new()
var _seed := 0
var _tough_sum := 0.0


func _init(p_model: VoxelVehicle.Model, p_mesh_instance: MeshInstance3D, seed_value: int) -> void:
	model = p_model
	mesh_instance = p_mesh_instance
	_seed = seed_value
	_rng.seed = seed_value
	var n := model.parts.size()
	hits.resize(n)
	gone.resize(n)
	hurt.resize(n)
	total = 0
	for k in n:
		if model.parts[k].detach and int(model.parts[k].n) > 0:
			total += 1
			_tough_sum += float(model.parts[k].tough)
	restore()


## Back to the undamaged car.
func restore(p_quiet := false) -> void:
	hits.fill(0.0)
	gone.fill(0)
	hurt.fill(0)
	removed = 0
	applied = 0.0
	wrecked = false
	quiet = p_quiet
	_count_lamps()
	dirty = true
	_apply()


func loss() -> float:
	return applied


## Damage to show for a condition share (1 = healthy): 0 .. 1.
static func target_loss(condition_share: float) -> float:
	if condition_share >= SHOW_FROM:
		return 0.0
	return clampf((SHOW_FROM - condition_share) / SHOW_FROM, 0.0, 1.0)


## Shows damage up to `target` (target_loss), mostly on the side `toward`
## (model space, unit; zero: anywhere). Returns the ids of the components
## that broke away (VoxelVehicle.part_mesh for their meshes); none when
## `quiet` (they just are not there).
func break_to(target: float, toward: Vector3) -> Array:
	var out: Array = []
	var dd := target - applied
	if dd <= 0.0005 or wrecked:
		return out
	applied = target
	var dir := toward.normalized() if toward.length() > 0.01 else Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.0, 0.5), _rng.randf_range(-1, 1)).normalized()
	var budget := dd * SPREAD * _tough_sum
	var n := model.parts.size()
	var w := PackedFloat32Array()
	w.resize(n)
	var sum := 0.0
	for k in range(1, n):
		var p: Dictionary = model.parts[k]
		if gone[k] == 1 or int(p.n) == 0:
			continue
		var layer: int = p.layer
		if layer == VoxelVehicle.INNER and applied < INNER_FROM:
			continue
		var c: Vector3 = p.centre
		var rel := Vector3(c.x / 2.0, (c.y - 0.45) * 0.8, c.z / 1.1)
		var facing := rel.normalized().dot(dir) * 0.5 + 0.5 if rel.length() > 0.05 else 0.5
		# bigger, tougher panels catch more of a knock (they all wear at a
		# similar pace; small lamps and mirrors do not all go first)
		var wk := (pow(facing, FOCUS) * _rng.randf_range(0.55, 1.45) + 0.015) * float(p.tough) * sqrt(clampf(float(p.n) / 60.0, 0.5, 1.6))
		if layer == VoxelVehicle.INNER:
			wk *= 0.45
		w[k] = wk
		sum += wk
	if sum <= 0.0:
		return out
	for k in range(1, n):
		if w[k] <= 0.0:
			continue
		var p: Dictionary = model.parts[k]
		hits[k] += budget * w[k] / sum
		var tough: float = p.tough
		if hits[k] >= tough * HURT_AT:
			hurt[k] = 1
		if p.detach and hits[k] >= tough and gone[k] == 0:
			gone[k] = 1
			removed += 1
			out.append(k)
	_fittings(out)
	_count_lamps()
	dirty = true
	_apply()
	if quiet:
		quiet = false
		return []
	return out


## The car's damage for a condition, the same every time for this seed and
## a subset of any worse condition's (the garage's car).
func preset(target: float) -> void:
	restore()
	applied = target
	for k in range(1, model.parts.size()):
		var p: Dictionary = model.parts[k]
		if int(p.n) == 0:
			continue
		var r := float(absi(hash(_seed * 7919 + k * 104729)) % 1000) / 1000.0
		var at: float = clampf(float(p.tough) / 2.4 * (0.45 + r), 0.06, 1.5)
		if int(p.layer) == VoxelVehicle.INNER:
			at += 0.45
		if target >= at * 0.4:
			hurt[k] = 1
		if p.detach and target >= at:
			gone[k] = 1
			removed += 1
	_fittings([])
	_count_lamps()
	dirty = true
	_apply()


## Fittings go with what they are mounted on (VoxelVehicle: part.on);
## newly gone ones are added to `out`.
func _fittings(out: Array) -> void:
	var changed := true
	while changed:
		changed = false
		for k in range(1, model.parts.size()):
			var on: int = model.parts[k].get("on", -1)
			if gone[k] == 0 and on >= 0 and gone[on] == 1:
				gone[k] = 1
				removed += 1
				out.append(k)
				changed = true


## Everything still attached that a blast takes flies apart (destruction).
## Returns the ids of those components.
func explode() -> Array:
	var out: Array = []
	for k in range(1, model.parts.size()):
		var p: Dictionary = model.parts[k]
		if gone[k] == 0 and p.blast and int(p.n) > 0:
			gone[k] = 1
			removed += 1
			out.append(k)
	wrecked = true
	_count_lamps()
	dirty = true
	_apply()
	return out


## Applies the masks if the state changed (cheap: a few instance values).
func rebuild() -> void:
	if not dirty:
		return
	dirty = false
	_apply()


## Shows the state on the car's mesh instance.
func _apply() -> void:
	if mesh_instance == null or not is_instance_valid(mesh_instance):
		return
	mesh_instance.set_instance_shader_parameter("parts_gone", mask(gone))
	mesh_instance.set_instance_shader_parameter("parts_hurt", mask(hurt))
	mesh_instance.set_instance_shader_parameter("charred", 1.0 if wrecked else 0.0)
	# the wreck sits down on its floor pan (the wheels are gone)
	mesh_instance.position.y = -model.floor_y if wrecked else 0.0


## Component bits as the shader's mask (20 components per channel).
static func mask(bits: PackedByteArray) -> Vector4:
	var words := [0, 0, 0, 0]
	for k in mini(bits.size(), 80):
		if bits[k] != 0:
			words[k / 20] = int(words[k / 20]) | (1 << (k % 20))
	return Vector4(words[0], words[1], words[2], words[3])


func _count_lamps() -> void:
	for l in 4:
		lamps[l] = 0
	var any := false
	for k in model.parts.size():
		var lamp: int = model.parts[k].lamp
		if lamp >= 0 and int(model.parts[k].n) > 0:
			any = true
			if gone[k] == 0:
				lamps[lamp] += 1
	if not any:
		lamps = PackedInt32Array([1, 1, 1, 1])
