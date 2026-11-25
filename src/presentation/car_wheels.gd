class_name CarWheels
extends Node2D
## Four instances of the shared wheel under a car's body (P2). The front wheels
## turn with the steering (up to WheelLayout.max_steer_degrees), the rear wheels
## shift a pixel or two sideways under cornering load; both ease back to
## neutral. 2026-11-22: the tread rolls with the distance driven (a shader
## scrolls the wheel image inside its own outline; WheelLayout.roll_*).
## Read-only presentation: it follows the car's visible state (the steering
## command when the car is simulated here, otherwise its turning rate, e.g. a
## network client's interpolated car) and never changes the car or the race.

var car: Car
var layout: WheelLayout
var _front: Array[Sprite2D] = []
var _rear: Array[Sprite2D] = []
var _half_track := 0.0
var _steer := 0.0
var _shift := 0.0
var _last_rotation := 0.0
var _last_position := Vector2.ZERO
var _primed := false
## The rolling tread: one material shared by the car's four wheels.
var _roll_material: ShaderMaterial
var roll := 0.0

const ROLL_SHADER := preload("res://src/presentation/wheel_roll.gdshader")


## Builds the wheels as the car's first child, so the body sprite draws over them.
func setup(p_car: Car, wheel: Texture2D, p_layout: WheelLayout, body_logical: String) -> void:
	car = p_car
	layout = p_layout
	name = "Wheels"
	var at := layout.positions(body_logical)
	_half_track = at.z
	var scale_to := AssetCatalog.scale_for(wheel, AssetCatalog.SPECS[AssetCatalog.WHEEL].display_size)
	if layout.roll_animation:
		_roll_material = ShaderMaterial.new()
		_roll_material.shader = ROLL_SHADER
	for side in [-1.0, 1.0]:
		_front.append(_wheel(wheel, scale_to, Vector2(at.x, side * at.z)))
		_rear.append(_wheel(wheel, scale_to, Vector2(at.y, side * at.z)))
	car.add_child(self)
	car.move_child(self, 0)


func _wheel(texture: Texture2D, scale_to: Vector2, at: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = texture
	s.scale = scale_to
	s.position = at
	s.material = _roll_material
	add_child(s)
	return s


## How far the tread scrolls (texture widths) for `px` display px driven
## forward (backward: negative), capped per frame against strobing.
static func roll_step(p_layout: WheelLayout, px: float) -> float:
	var cap := p_layout.max_roll_per_frame
	return clampf(-px / maxf(p_layout.roll_px, 0.001), -cap, cap)


## Front wheel angle (radians) for a smoothed steering value -1..1.
static func steer_angle(p_layout: WheelLayout, steer: float) -> float:
	return deg_to_rad(p_layout.max_steer_degrees) * clampf(steer, -1.0, 1.0)


## Rear wheels' sideways shift (display px, + = towards the car's right) for a
## cornering load -1..1 (+ = turning right): they move to the outside of the turn.
static func rear_shift(p_layout: WheelLayout, corner: float) -> float:
	return -p_layout.rear_shift_px * clampf(corner, -1.0, 1.0)


func _process(delta: float) -> void:
	if car == null or car.model == null or delta <= 0.0 or not is_visible_in_tree():
		_primed = false
		return
	var rot := car.global_rotation
	var pos := car.global_position
	var yaw := 0.0
	var speed := 0.0
	var forward_px := 0.0
	if _primed:
		yaw = wrapf(rot - _last_rotation, -PI, PI) / delta
		speed = pos.distance_to(_last_position) / delta
		forward_px = (pos - _last_position).dot(Vector2.from_angle(rot))
	_last_rotation = rot
	_last_position = pos
	_primed = true
	var params := car.model.params
	if speed > params.max_speed * 3.0:
		return  # placed on the grid / respawned: not motion
	if _roll_material != null and forward_px != 0.0:
		roll = fposmod(roll + roll_step(layout, forward_px), 1.0)
		_roll_material.set_shader_parameter("roll", roll)
	var turn_rate := deg_to_rad(params.turn_rate_degrees)
	var target := clampf(car.steer, -1.0, 1.0) if car.active else clampf(yaw / turn_rate, -1.0, 1.0)
	_steer = lerpf(_steer, target, 1.0 - exp(-delta / layout.steer_smoothing))
	var corner := clampf(yaw * speed / (turn_rate * params.max_speed), -1.0, 1.0)
	_shift = lerpf(_shift, rear_shift(layout, corner), 1.0 - exp(-delta / layout.rear_smoothing))
	for w in _front:
		w.rotation = steer_angle(layout, _steer)
	for k in _rear.size():
		_rear[k].position.y = (-_half_track if k == 0 else _half_track) + _shift
