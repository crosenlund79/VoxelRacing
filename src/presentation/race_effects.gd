class_name RaceEffects
extends Node2D
## Visual feedback for driving: tyre marks and smoke when sliding or braking
## hard, dust when launching, sparks on impacts, confetti at the finish.
## Read-only: it observes car state and the cars' hit signals and never writes
## to cars, models or the race. Disabled (cleared) in fast simulation.

const MAX_MARKS := 1600
const MARK_LIFETIME := 9.0
## Sideways speed (px/s) above which tyres leave marks and smoke.
const SLIDE_THRESHOLD := 70.0
const MARK_SPACING := 9.0

var enabled := true
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
var _smoke: Array[CPUParticles2D] = []
var _dust: Array[CPUParticles2D] = []
var _resolver: AssetResolver
var _confetti_colors := [Color("b23a22"), Color("e2b23c"), Color("3f9c96"), Color("f3e8cf"), Color("cf5f8a"), Color("5b7b92")]


## mark_layer sits under the cars (on the road); the rest draws above.
func setup(cars: Array[Car], resolver: AssetResolver, mark_layer: Node2D, dust_color: Color = Color(0.75, 0.66, 0.5, 0.7)) -> void:
	_cars = cars
	_resolver = resolver
	_marks = _new_marks(resolver)
	mark_layer.add_child(_marks)
	_mark_upper.resize(MAX_MARKS)
	_mark_age.resize(MAX_MARKS)
	_mark_age.fill(MARK_LIFETIME)
	_mark_strength.resize(MAX_MARKS)
	_mark_strength.fill(0.0)
	for c in cars:
		_last_mark_pos.append(c.global_position)
		_smoke.append(_emitter(resolver.get_texture(AssetCatalog.SMOKE), Color(0.92, 0.9, 0.86, 0.75), 18, 0.9))
		_dust.append(_emitter(resolver.get_texture(AssetCatalog.DUST), dust_color, 10, 0.6))
		c.wall_hit.connect(_on_hit.bind(c))
		c.car_hit.connect(func(_other: Car, speed: float) -> void: _on_hit(Vector2.ZERO, speed, c))


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


## Elevated layouts: a second mark layer on the bridge deck, and road levels
## for draw order (smoke, dust, sparks follow their car's level).
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
		for p in _smoke + _dust:
			p.emitting = false


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


func _process(delta: float) -> void:
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
		var level := _level(c)
		_smoke[i].z_index = Track.UPPER_Z_OFFSET * level
		_dust[i].z_index = _smoke[i].z_index
		_smoke[i].global_position = rear
		_smoke[i].emitting = sliding and slide > SLIDE_THRESHOLD * 1.4
		_dust[i].global_position = rear
		_dust[i].emitting = on_track and c.active and c.model.is_accelerating(c.fire) and speed < 140.0 and speed > 5.0
		if sliding and rear.distance_to(_last_mark_pos[i]) >= MARK_SPACING:
			var strength := clampf((slide - SLIDE_THRESHOLD) / 200.0 + (0.5 if braking else 0.25), 0.2, 0.9)
			_stamp(rear, c.global_rotation, strength, level)
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


func _on_hit(_normal: Vector2, speed: float, c: Car) -> void:
	if not enabled or speed < 70.0 or not c.visible:
		return
	var burst := _emitter(_resolver.get_texture(AssetCatalog.SPARK), Color(1, 0.95, 0.8), int(clampf(speed / 25.0, 4, 16)), 0.35)
	burst.global_position = c.global_position + Vector2.from_angle(c.global_rotation) * 26.0
	burst.z_index = Track.UPPER_Z_OFFSET * _level(c)
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.initial_velocity_min = 60.0
	burst.initial_velocity_max = 160.0
	burst.spread = 180.0
	burst.emitting = true
	burst.finished.connect(burst.queue_free)


## Confetti burst (e.g. at the finish line).
func celebrate(at: Vector2) -> void:
	if not enabled:
		return
	for k in 3:
		var p := _emitter(_resolver.get_texture(AssetCatalog.CONFETTI), _confetti_colors[k * 2 % _confetti_colors.size()], 40, 2.2)
		p.global_position = at
		p.one_shot = true
		p.explosiveness = 0.85
		p.spread = 180.0
		p.initial_velocity_min = 120.0
		p.initial_velocity_max = 320.0
		p.damping_min = 80.0
		p.damping_max = 140.0
		p.angular_velocity_min = -360.0
		p.angular_velocity_max = 360.0
		var ramp := Gradient.new()
		ramp.set_color(0, _confetti_colors[(k * 2) % _confetti_colors.size()])
		ramp.set_color(1, _confetti_colors[(k * 2 + 1) % _confetti_colors.size()])
		p.color_initial_ramp = ramp
		p.emitting = true
		p.finished.connect(p.queue_free)


func _emitter(tex: Texture2D, tint: Color, amount: int, lifetime: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = tex
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.emitting = false
	p.color = tint
	p.direction = Vector2.ZERO
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 30.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.1
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(1, 1.4))
	p.scale_amount_curve = curve
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	add_child(p)
	return p
