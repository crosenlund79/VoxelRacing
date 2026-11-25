class_name JumpView
extends Node2D
## J3 presentation of jumps (read-only; procedural, existing effect textures
## and sounds only): a flying car grows with its height and casts a shadow that
## separates from it; a landing kicks up dust with a thud; a fall into the gap
## sinks and darkens the car with smoke and a crash. Reads JumpWorld state and
## never changes the race.

## Display scale per pixel of height, and shadow offset per pixel of height
## (light from the top left, like the bridge shadow).
const SCALE_PER_HEIGHT := 0.012
const SHADOW_PER_HEIGHT := Vector2(1.1, 1.5)
const SHADOW_COLOR := Color(0.02, 0.02, 0.05, 0.5)
const FALLEN_SCALE := 0.72
const FALLEN_TINT := Color(0.3, 0.27, 0.27)

var enabled := true
var _jumps: JumpWorld
var _cars: Array[Car] = []
var _audio: RaceAudio
var _resolver: AssetResolver
var _shadows: Array[Sprite2D] = []
var _base_scale: Array[Vector2] = []
var _was_air := PackedByteArray()
var _was_down := PackedByteArray()


func setup(jumps: JumpWorld, cars: Array[Car], resolver: AssetResolver, audio: RaceAudio) -> void:
	_jumps = jumps
	_cars = cars
	_resolver = resolver
	_audio = audio
	_was_air.resize(cars.size())
	_was_down.resize(cars.size())
	for c in cars:
		var sh := Sprite2D.new()
		sh.name = "JumpShadow"
		sh.texture = c.sprite.texture
		sh.scale = c.sprite.scale
		sh.modulate = SHADOW_COLOR
		sh.z_index = -1  # under its own car, over the road
		sh.visible = false
		c.add_child(sh)
		_shadows.append(sh)
		_base_scale.append(c.sprite.scale)


func _process(_delta: float) -> void:
	for i in _cars.size():
		var c := _cars[i]
		var h := _jumps.height(i)
		var air := _jumps.is_airborne(i)
		var down := _jumps.is_down(i)
		var grow := 1.0 + h * SCALE_PER_HEIGHT
		var look := FALLEN_SCALE if down else grow
		c.sprite.scale = _base_scale[i] * look
		var wheels := c.get_node_or_null("Wheels") as Node2D
		if wheels != null:
			wheels.scale = Vector2.ONE * look
		c.sprite.self_modulate = FALLEN_TINT if down else Color.WHITE
		if wheels != null:
			wheels.modulate = FALLEN_TINT if down else Color.WHITE
		var sh := _shadows[i]
		sh.visible = air and c.visible
		if sh.visible:
			sh.texture = c.sprite.texture
			sh.global_position = c.global_position + SHADOW_PER_HEIGHT * h
			sh.global_rotation = c.global_rotation
			sh.scale = _base_scale[i] * (1.0 - h * SCALE_PER_HEIGHT * 0.3)
		if air and _was_air[i] == 0:
			_burst(c, AssetCatalog.DUST, Color(0.85, 0.78, 0.62, 0.7), 8, 60.0)
		elif not air and _was_air[i] == 1 and not down:
			_burst(c, AssetCatalog.DUST, Color(0.85, 0.78, 0.62, 0.85), 22, 150.0)
			if _audio != null:
				_audio.play_at("vehicles/impact_wall", c.global_position)
		if down and _was_down[i] == 0:
			_burst(c, AssetCatalog.SMOKE, Color(0.25, 0.22, 0.22, 0.85), 26, 70.0)
			_burst(c, AssetCatalog.SPARK, Color(1, 0.8, 0.5), 14, 170.0)
			if _audio != null:
				_audio.play_at("weapons/explosion", c.global_position)
		_was_air[i] = 1 if air else 0
		_was_down[i] = 1 if down else 0


func _burst(c: Car, logical: String, tint: Color, amount: int, speed: float) -> void:
	if not enabled or not c.visible:
		return
	var p := CPUParticles2D.new()
	p.texture = _resolver.get_texture(logical)
	p.amount = amount
	p.lifetime = 0.7
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.color = tint
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = speed * 0.35
	p.initial_velocity_max = speed
	p.damping_min = speed * 0.8
	p.damping_max = speed * 1.4
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	p.global_position = c.global_position
	p.z_index = c.z_index + 1
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
