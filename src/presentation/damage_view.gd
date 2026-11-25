class_name DamageView
extends Node2D
## M6 presentation of vehicle condition (read-only; existing smoke / spark
## textures and sounds only): a car in critical condition trails grey smoke, a
## retired car (DNF) is a darkened, smoking wreck with a crash and sparks,
## until it is taken off the road. Reads DamageWorld; never changes the race.
## Runs after CombatView (added later), so a retired wreck stays dark.
## 2026-11-23, visible wear by condition (still read-only, no physics):
##   healthy (above 85 %): as painted;
##   worn (85-50 %): the shared wear drawing (fx/car_wear) fades in on the body;
##   heavy (below 50 %): stronger wear and thin grey smoke;
##   critical (25 % and below): full wear and the dense smoke;
##   retired: the darkened, smoking wreck as before.
## One shared, replaceable wear image for every car (masked by each body).

const RETIRED_TINT := Color(0.3, 0.27, 0.26)
const WEAR_SHADER := preload("res://src/presentation/car_wear.gdshader")
## Wear starts below this share of full condition and is complete at WEAR_FULL.
const WEAR_START := 0.85
const WEAR_FULL := 0.25
## Below this share: thin smoke (heavy damage).
const HEAVY := 0.5

var enabled := true
var _damage: DamageWorld
var _cars: Array[Car] = []
var _resolver: AssetResolver
var _audio: RaceAudio
var _smoke: Array[CPUParticles2D] = []
var _was_retired := PackedByteArray()
var _tinted := PackedByteArray()
var _wear: Array[ShaderMaterial] = []
var _wear_amount := PackedFloat32Array()


func setup(damage: DamageWorld, cars: Array[Car], resolver: AssetResolver, audio: RaceAudio) -> void:
	_damage = damage
	_cars = cars
	_resolver = resolver
	_audio = audio
	_was_retired.resize(cars.size())
	_tinted.resize(cars.size())
	_wear_amount.resize(cars.size())
	var wear_tex := resolver.get_texture(AssetCatalog.CAR_WEAR)
	for c in cars:
		var m := ShaderMaterial.new()
		m.shader = WEAR_SHADER
		m.set_shader_parameter("wear", wear_tex)
		if c.sprite != null and c.sprite.material == null:
			c.sprite.material = m
		_wear.append(m)
		var p := CPUParticles2D.new()
		p.texture = resolver.get_texture(AssetCatalog.SMOKE)
		p.amount = 14
		p.lifetime = 1.1
		p.local_coords = false
		p.emitting = false
		p.spread = 180.0
		p.gravity = Vector2.ZERO
		p.initial_velocity_min = 6.0
		p.initial_velocity_max = 24.0
		p.scale_amount_min = 0.5
		p.scale_amount_max = 1.2
		var fade := Gradient.new()
		fade.set_color(0, Color(1, 1, 1, 0.8))
		fade.set_color(1, Color(1, 1, 1, 0.0))
		p.color_ramp = fade
		add_child(p)
		_smoke.append(p)


func _process(_delta: float) -> void:
	for i in _cars.size():
		var c := _cars[i]
		var retired := _damage.is_retired(i)
		var critical := _damage.is_critical(i)
		var share := _damage.fraction(i)
		var heavy := share < HEAVY
		var smoke := _smoke[i]
		smoke.global_position = c.global_position
		smoke.z_index = c.z_index + 1
		smoke.emitting = enabled and c.visible and (retired or critical or heavy)
		smoke.color = Color(0.16, 0.14, 0.14) if retired else (Color(0.5, 0.48, 0.47) if critical else Color(0.6, 0.58, 0.56, 0.6))
		var amount := wear_amount(share) if enabled else 0.0
		if absf(amount - _wear_amount[i]) > 0.01:
			_wear_amount[i] = amount
			_wear[i].set_shader_parameter("amount", amount)
		smoke.amount = 14
		if retired and c.visible:
			c.modulate = RETIRED_TINT
			_tinted[i] = 1
		elif _tinted[i] == 1:
			c.modulate = Color.WHITE
			_tinted[i] = 0
		if retired and _was_retired[i] == 0 and c.visible:
			_burst(c)
			if _audio != null:
				_audio.play_at("weapons/explosion", c.global_position)
		_was_retired[i] = 1 if retired else 0


## How much wear shows (0..1) at a share of full condition.
static func wear_amount(share: float) -> float:
	return clampf((WEAR_START - share) / (WEAR_START - WEAR_FULL), 0.0, 1.0)


func wear_of(i: int) -> float:
	return _wear_amount[i]


func _burst(c: Car) -> void:
	if not enabled:
		return
	var p := CPUParticles2D.new()
	p.texture = _resolver.get_texture(AssetCatalog.SPARK)
	p.amount = 18
	p.lifetime = 0.5
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.color = Color(1, 0.8, 0.5)
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 60.0
	p.initial_velocity_max = 190.0
	p.global_position = c.global_position
	p.z_index = c.z_index + 2
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
