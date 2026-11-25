class_name WeatherView
extends CanvasLayer
## Biome weather (presentation only): light rain streaks (Wasteland) or soft
## falling snow (Winter) over the whole screen, below the HUD. A single
## lightweight particle emitter; it never hides the road (thin, translucent)
## and never touches the race.

var kind := ""
var particles: CPUParticles2D


func setup(p_kind: String, night: bool = false) -> void:
	kind = p_kind
	layer = 2  # above the race (and split views), below every HUD
	particles = CPUParticles2D.new()
	particles.position = Vector2(640, -20)
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = Vector2(760, 10)
	particles.local_coords = false
	if kind == "rain":
		particles.amount = 140
		particles.lifetime = 0.9
		particles.direction = Vector2(-0.18, 1.0)
		particles.spread = 3.0
		particles.gravity = Vector2.ZERO
		particles.initial_velocity_min = 820.0
		particles.initial_velocity_max = 980.0
		particles.texture = _streak()
		particles.color = Color(0.78, 0.84, 0.95, 0.28 if night else 0.33)
	else:
		particles.amount = 120
		particles.lifetime = 5.5
		particles.direction = Vector2(0.15, 1.0)
		particles.spread = 25.0
		particles.gravity = Vector2(0, 8)
		particles.initial_velocity_min = 70.0
		particles.initial_velocity_max = 140.0
		particles.scale_amount_min = 0.5
		particles.scale_amount_max = 1.3
		particles.texture = _flake()
		particles.color = Color(1, 1, 1, 0.8 if night else 0.65)
	particles.preprocess = particles.lifetime
	add_child(particles)
	particles.emitting = true


static func _streak() -> Texture2D:
	var img := Image.create(2, 18, false, Image.FORMAT_RGBA8)
	for y in 18:
		for x in 2:
			img.set_pixel(x, y, Color(1, 1, 1, float(y) / 17.0))
	return ImageTexture.create_from_image(img)


static func _flake() -> Texture2D:
	var img := Image.create(7, 7, false, Image.FORMAT_RGBA8)
	for y in 7:
		for x in 7:
			var d := Vector2(x - 3, y - 3).length()
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d / 3.4, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)
