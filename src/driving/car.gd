class_name Car
extends CharacterBody2D
## Scene wrapper for CarModel: applies input each physics tick, moves the body
## with continuous collision, and feeds wall contacts back into the model.
## Input is set from outside (steer/fire) by the player, the AI or tests.
## Car-to-car contacts are resolved symmetrically through CarModel.

signal wall_hit(normal: Vector2, impact_speed: float)
signal car_hit(other: Car, impact_speed: float)

const MAX_SLIDES := 4
## Simulation step used for all driving maths, independent of engine timing, so
## normal and accelerated simulation perform identical calculations. Matches
## the project's 60 physics ticks per second at normal speed.
const FIXED_STEP := 1.0 / 60.0

var model: CarModel
var steer := 0.0
var fire := false
var active := false
## J3 (experimental jumps): flying off a ramp. In the air the car keeps the
## velocity it took off with (no steering, throttle or grip); it still meets
## barriers. Never set on ordinary road.
var airborne := false
## Identifies the racer in the race session (0 = player).
var racer_id := 0

@onready var sprite: Sprite2D = $Sprite


func setup(params: DrivingParams, mode: CarModel.ControlMode, texture: Texture2D) -> void:
	model = CarModel.new(params, mode)
	model.position = global_position
	model.heading = global_rotation
	if texture != null:
		sprite.texture = texture
		sprite.scale = AssetCatalog.scale_for(texture, AssetCatalog.SPECS[AssetCatalog.CAR_PLAYER].display_size)


## Places the car at rest at the given transform.
func place(at: Transform2D) -> void:
	global_position = at.origin
	global_rotation = at.get_rotation()
	steer = 0.0
	fire = false
	if model != null:
		model.position = global_position
		model.heading = global_rotation
		model.velocity = Vector2.ZERO
		model.yaw_rate = 0.0


func _physics_process(_delta: float) -> void:
	if model == null or not active:
		if model != null:
			model.yaw_rate = 0.0  # a stopped (wrecked, parked) car does not keep a knock for later
		return
	if not airborne:
		model.update(FIXED_STEP, steer, fire)
	global_rotation = model.heading
	var motion := model.velocity * FIXED_STEP
	for i in MAX_SLIDES:
		var collision := move_and_collide(motion)
		if collision == null:
			break
		var normal := collision.get_normal()
		var other := collision.get_collider() as Car
		if other != null and other.model != null:
			var closing := -(model.velocity - other.model.velocity).dot(normal)
			CarModel.resolve_car_collision(model, other.model, normal, collision.get_position(), global_position, other.global_position)
			if closing > 0.0:
				car_hit.emit(other, closing)
			motion = collision.get_remainder().slide(normal)
		else:
			var impact := -model.velocity.dot(normal)
			model.apply_wall_collision(normal)
			if impact > 0.0:
				wall_hit.emit(normal, impact)
			motion = collision.get_remainder().slide(normal) * model.params.wall_tangent_retention
		if motion.length_squared() < 0.0001:
			break
	model.position = global_position
