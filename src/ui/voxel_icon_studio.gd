class_name VoxelIconStudio
extends SubViewport
## Renders every car's voxel model into a small picture once, at startup
## (while the title shows), seen from the race camera's angle with a studio
## light. CarArt.icon() hands these out everywhere a car is pictured
## (standings, results, garage, championship, rival pop-ups).

signal done

const SIZE := Vector2i(192, 108)
const CARS := ["cars/body_player", "cars/body_player_2", "cars/body_junker",
	"cars/body_ai_1", "cars/body_ai_2", "cars/body_ai_3", "cars/body_ai_4", "cars/body_ai_5",
	"cars/body_ai_6", "cars/body_ai_7", "cars/body_ai_8", "cars/body_ai_9"]

## body logical name -> Texture2D
static var icons: Dictionary = {}
## WeaponRules.Weapon -> Texture2D (filled in place: holders see it arrive)
static var weapons: Dictionary = {}

var _car: Node3D
var _body: MeshInstance3D
var _cam: Camera3D
var _wheels: Array[Node3D] = []


func _init() -> void:
	size = SIZE
	transparent_bg = true
	own_world_3d = true
	msaa_3d = Viewport.MSAA_4X
	render_target_update_mode = SubViewport.UPDATE_DISABLED


func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.95)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var key := DirectionalLight3D.new()
	key.basis = Basis.looking_at(Vector3(0.4, -1.0, -0.5).normalized(), Vector3.UP)
	key.light_energy = 1.2
	add_child(key)
	_car = Node3D.new()
	add_child(_car)
	_body = MeshInstance3D.new()
	_car.add_child(_body)
	var layout: WheelLayout = load("res://src/presentation/default_wheel_layout.tres")
	var at := layout.positions("")
	for ax in [at.x, at.y]:
		for az in [-at.z, at.z]:
			var w := MeshInstance3D.new()
			w.mesh = VoxelCars.wheel_mesh()
			w.position = Vector3(ax, VoxelCars.WHEEL_R * Vox.CAR_VOXEL_PX, az) * Vox.PX
			_car.add_child(w)
			_wheels.append(w)
	var cam := Camera3D.new()
	_cam = cam
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.9
	var pitch := deg_to_rad(52.0)
	cam.position = Vector3(0, sin(pitch), cos(pitch)) * 20.0 + Vector3(0, 0.45, 0)
	cam.rotation = Vector3(-pitch, 0, 0)
	add_child(cam)
	cam.make_current()


## Renders every car (a frame or two each); `done` when all are in.
func render_all(resolver: AssetResolver) -> void:
	var layout: WheelLayout = load("res://src/presentation/default_wheel_layout.tres")
	for logical in CARS:
		var tex := resolver.get_texture(logical)
		if tex == null:
			continue
		_body.mesh = VoxelCars.body_mesh(tex, layout, logical)
		render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := get_texture().get_image()
		if img != null:
			icons[logical] = ImageTexture.create_from_image(img)
	# the weapons (HUD ammunition, garage shop)
	for w in _wheels:
		w.visible = false
	_cam.size = 1.25
	for kind in ["missile", "homing", "super", "mine"]:
		_body.mesh = VoxelWeapons.mine_mesh() if kind == "mine" else VoxelWeapons.missile_mesh(kind)
		_body.set_instance_shader_parameter("lamp_glow", 1.0)
		_body.position = Vector3(0, 0.1 if kind == "mine" else 0.2, 0)
		render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := get_texture().get_image()
		if img != null:
			var t := ImageTexture.create_from_image(img)
			icons["weapon:" + kind] = t
			match kind:
				"missile":
					weapons[WeaponRules.Weapon.FRONT_MISSILE] = t
					weapons[WeaponRules.Weapon.REAR_MISSILE] = t
				"homing":
					weapons[WeaponRules.Weapon.HOMING_MISSILE] = t
				"super":
					weapons[WeaponRules.Weapon.SUPER_MISSILE] = t
				"mine":
					weapons[WeaponRules.Weapon.MINE] = t
	done.emit()
