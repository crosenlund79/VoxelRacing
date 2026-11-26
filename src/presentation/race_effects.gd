class_name RaceEffects
extends Node2D
## Driving feedback rules: tyre marks when sliding or braking hard (ground
## decals, projected onto the voxel road), and which cars smoke their tyres
## or kick up dust right now (`smoking`, `dusting`: VoxelRaceFx draws them as
## voxel puffs). The finish confetti is a signal (VoxelStage throws voxel
## confetti). Read-only: it observes car state and never writes to cars,
## models or the race. Disabled (cleared) in fast simulation.

signal celebrated(at: Vector2)

const MAX_MARKS := 1600
const MARK_LIFETIME := 9.0
## Sideways speed (px/s) above which tyres leave marks and smoke.
const SLIDE_THRESHOLD := 70.0
const MARK_SPACING := 9.0

var enabled := true
## Per car: 1 while its tyres smoke (hard slide) / it kicks up dust (launch).
var smoking := PackedByteArray()
var dusting := PackedByteArray()
var _cars: Array[Car] = []
var _marks: MultiMeshInstance2D
## J2 (elevated layouts): marks left on the bridge draw on the deck, in their
## own layer; each mark slot belongs to one of the two layers.
var _marks_upper: MultiMeshInstance2D = null
var _mark_upper := PackedByteArray()
## Road level of a racer (Callable(int) -> int); unset = everything on the ground.
var level_of: Callable
var _mark_age := PackedFloat32Array()
var _mark_strength := PackedFloat32Array()
var _mark_next := 0
var _last_mark_pos: Array[Vector2] = []
var _resolver: AssetResolver


## mark_layer sits under the cars (on the road).
func setup(cars: Array[Car], resolver: AssetResolver, mark_layer: Node2D, _dust_color: Color = Color.WHITE) -> void:
	_cars = cars
	_resolver = resolver
	_marks = _new_marks(resolver)
	mark_layer.add_child(_marks)
	_mark_upper.resize(MAX_MARKS)
	_mark_age.resize(MAX_MARKS)
	_mark_age.fill(MARK_LIFETIME)
	_mark_strength.resize(MAX_MARKS)
	_mark_strength.fill(0.0)
	smoking.resize(cars.size())
	dusting.resize(cars.size())
	for c in cars:
		_last_mark_pos.append(c.global_position)


func _new_marks(resolver: AssetResolver) -> MultiMeshInstance2D:
	var marks := MultiMeshInstance2D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	var quad := QuadMesh.new()
	quad.size = AssetCatalog.SPECS[AssetCatalog.TIRE_MARK].display_size
	mm.mesh = quad
	mm.instance_count = MAX_MARKS
	mm.visible_instance_count = MAX_MARKS
	for i in MAX_MARKS:
		mm.set_instance_transform_2d(i, Transform2D(0.0, Vector2(-1e6, -1e6)))
		mm.set_instance_color(i, Color(1, 1, 1, 0))
	marks.multimesh = mm
	marks.texture = resolver.get_texture(AssetCatalog.TIRE_MARK)
	return marks


## Elevated layouts: a second mark layer on the bridge deck.
func setup_levels(p_level_of: Callable, mark_layer: Node2D) -> void:
	level_of = p_level_of
	_marks_upper = _new_marks(_resolver)
	_marks_upper.name = "MarksUpper"
	_marks_upper.z_index = Track.BRIDGE_DECK_Z
	mark_layer.add_child(_marks_upper)


func _level(c: Car) -> int:
	return level_of.call(c.racer_id) if level_of.is_valid() else 0


func _mm(slot: int) -> MultiMesh:
	return _marks_upper.multimesh if _mark_upper[slot] == 1 else _marks.multimesh


func set_enabled(on: bool) -> void:
	enabled = on
	visible = on
	_marks.visible = on
	if _marks_upper != null:
		_marks_upper.visible = on
	if not on:
		smoking.fill(0)
		dusting.fill(0)


func clear_marks() -> void:
	_mark_age.fill(MARK_LIFETIME)
	for i in MAX_MARKS:
		_marks.multimesh.set_instance_color(i, Color(1, 1, 1, 0))
		if _marks_upper != null:
			_marks_upper.multimesh.set_instance_color(i, Color(1, 1, 1, 0))
	for i in _cars.size():
		_last_mark_pos[i] = _cars[i].global_position


func mark_count() -> int:
	var live := 0
	for a in _mark_age:
		if a < MARK_LIFETIME:
			live += 1
	return live


func _process__perf(delta: float) -> void:
	if not enabled:
		return
	for i in _cars.size():
		var c := _cars[i]
		var on_track := c.visible and c.model != null
		var slide := absf(c.model.lateral_speed()) if on_track else 0.0
		var speed := c.model.forward_speed() if on_track else 0.0
		var braking := on_track and c.active and not c.model.is_accelerating(c.fire) and speed > 300.0 \
			and c.model.braking_deceleration() >= c.model.params.brake_deceleration
		var sliding := on_track and c.active and (slide > SLIDE_THRESHOLD or braking)
		var rear := c.global_position - Vector2.from_angle(c.global_rotation) * 22.0
		smoking[i] = 1 if sliding and slide > SLIDE_THRESHOLD * 1.4 else 0
		dusting[i] = 1 if on_track and c.active and c.model.is_accelerating(c.fire) and speed < 140.0 and speed > 5.0 else 0
		if sliding and rear.distance_to(_last_mark_pos[i]) >= MARK_SPACING:
			var strength := clampf((slide - SLIDE_THRESHOLD) / 200.0 + (0.5 if braking else 0.25), 0.2, 0.9)
			_stamp(rear, c.global_rotation, strength, _level(c))
			_last_mark_pos[i] = rear
		elif not sliding:
			_last_mark_pos[i] = rear
	for m in MAX_MARKS:
		if _mark_age[m] < MARK_LIFETIME:
			_mark_age[m] += delta
			var a := _mark_strength[m] * clampf(1.0 - _mark_age[m] / MARK_LIFETIME, 0.0, 1.0)
			_mm(m).set_instance_color(m, Color(1, 1, 1, a))


func _stamp(pos: Vector2, rot: float, strength: float, level: int = 0) -> void:
	if _marks_upper != null:
		_mm(_mark_next).set_instance_color(_mark_next, Color(1, 1, 1, 0))  # leave the slot's old layer
		_mark_upper[_mark_next] = 1 if level == 1 else 0
	_mm(_mark_next).set_instance_transform_2d(_mark_next, Transform2D(rot + PI * 0.5, pos))
	_mm(_mark_next).set_instance_color(_mark_next, Color(1, 1, 1, strength))
	_mark_age[_mark_next] = 0.0
	_mark_strength[_mark_next] = strength
	_mark_next = (_mark_next + 1) % MAX_MARKS


## Confetti at the finish (VoxelStage throws voxel confetti).
func celebrate(at: Vector2) -> void:
	if enabled:
		celebrated.emit(at)


## DIAGNOSTIC probe (Performance Investigation 001)
func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process__perf(delta)
	PerfProbe.add(&"legacy2d.race_effects", __t)
