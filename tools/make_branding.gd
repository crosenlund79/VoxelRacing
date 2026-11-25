extends SceneTree
## Bakes VoxelRacing's branding pictures from the live voxel models:
##   assets/branding/voxelracing_logo.png  (boot splash, README)
##   assets/branding/icon.png              (window / application icon)
## xvfb-run godot --path . -s tools/make_branding.gd

var _f := 0
var _logo: VoxelLogo
var _icon_vp: SubViewport


func _initialize() -> void:
	root.size = Vector2i(1200, 560)
	_logo = VoxelLogo.new()
	_logo.size = Vector2(1200, 560)
	root.add_child(_logo)
	_icon_vp = SubViewport.new()
	_icon_vp.size = Vector2i(256, 256)
	_icon_vp.transparent_bg = true
	_icon_vp.own_world_3d = true
	_icon_vp.msaa_3d = Viewport.MSAA_4X
	_icon_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_icon_vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.95)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	_icon_vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.basis = Basis.looking_at(Vector3(0.4, -1.0, -0.5).normalized(), Vector3.UP)
	key.light_energy = 1.25
	_icon_vp.add_child(key)
	var resolver := AssetResolver.new()
	var layout: WheelLayout = load("res://src/presentation/default_wheel_layout.tres")
	var car := Node3D.new()
	var body := MeshInstance3D.new()
	body.mesh = VoxelCars.body_mesh(resolver.get_texture("cars/body_player"), layout, "cars/body_player")
	body.set_instance_shader_parameter("head_glow", 0.5)
	car.add_child(body)
	var at := layout.positions("cars/body_player")
	for ax in [at.x, at.y]:
		for az in [-at.z, at.z]:
			var w := MeshInstance3D.new()
			w.mesh = VoxelCars.wheel_mesh()
			w.position = Vector3(ax, VoxelCars.WHEEL_R * Vox.CAR_VOXEL_PX, az) * Vox.PX
			car.add_child(w)
	car.rotation.y = deg_to_rad(28.0)
	_icon_vp.add_child(car)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 5.4
	var pitch := deg_to_rad(40.0)
	cam.position = Vector3(0, sin(pitch), cos(pitch)) * 20.0 + Vector3(0, 0.55, 0)
	cam.rotation = Vector3(-pitch, 0, 0)
	_icon_vp.add_child(cam)
	cam.make_current()


func _process(_d: float) -> bool:
	_f += 1
	if _f == 6:
		_logo.freeze(2.05)
	if _f == 12:
		var img := _logo.viewport.get_texture().get_image()
		img.save_png("res://assets/branding/voxelracing_logo.png")
		var car := _icon_vp.get_texture().get_image()
		car.convert(Image.FORMAT_RGBA8)
		var icon := Image.create(256, 256, false, Image.FORMAT_RGBA8)
		icon.fill(Color(0, 0, 0, 0))
		# a voxel badge: cream rim, ink plate, red top, chequered band
		icon.fill_rect(Rect2i(8, 8, 240, 240), VrStyle.PAPER)
		icon.fill_rect(Rect2i(16, 16, 224, 224), VrStyle.INK)
		icon.fill_rect(Rect2i(16, 16, 224, 92), VrStyle.YELLOW)
		icon.fill_rect(Rect2i(16, 16, 224, 10), VrStyle.YELLOW.lightened(0.3))
		for x in 14:
			for y in 2:
				icon.fill_rect(Rect2i(16 + x * 16, 108 + y * 16, 16, 16), VrStyle.PAPER if (x + y) % 2 == 0 else VrStyle.INK)
		icon.blend_rect(car, Rect2i(0, 0, 256, 256), Vector2i(0, 26))
		icon.save_png("res://assets/branding/icon.png")
		print("saved branding")
		return true
	return false
