extends SceneTree
## Developer harness: every car drawing as a voxel model, lit, from the race
## camera angle. xvfb-run godot --path . -s tools/car_showroom.gd -- --out=/tmp/cars.png [--pitch=58] [--zoom=3]

var _frames := 0
var _out := "user://showroom.png"


func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
	_out = args.get("out", _out)
	var pitch := deg_to_rad(float(args.get("pitch", "58")))
	var zoom := float(args.get("zoom", "3.0"))
	var resolver := AssetResolver.new()
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = VoxelStage.make_environment()
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-52), deg_to_rad(-140), 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.25
	stage.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.36, 0.38)
	ground.material_override = gm
	stage.add_child(ground)
	var names := ["cars/body_player", "cars/body_player_2", "cars/body_junker"]
	for i in range(1, 10):
		names.append("cars/body_ai_%d" % i)
	var layout: WheelLayout = load("res://src/presentation/default_wheel_layout.tres")
	for k in names.size():
		var tex := resolver.get_texture(names[k])
		var car := Node3D.new()
		var col := k % 4
		var row := k / 4
		car.position = Vox.to3(Vector2(-150 + col * 100, -70 + row * 70))
		car.rotation.y = Vox.yaw(-0.35 if row == 1 else 0.0)
		stage.add_child(car)
		var body := MeshInstance3D.new()
		body.mesh = VoxelCars.body_mesh(tex, layout, names[k])
		car.add_child(body)
		var at := layout.positions(names[k])
		for ax in [at.x, at.y]:
			for az in [-at.z, at.z]:
				var w := MeshInstance3D.new()
				w.mesh = VoxelCars.wheel_mesh()
				w.position = Vector3(ax, VoxelCars.WHEEL_R * Vox.CAR_VOXEL_PX, az) * Vox.PX
				car.add_child(w)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 720.0 * Vox.PX / zoom
	cam.rotation.x = -pitch
	cam.position = Vector3(0, sin(pitch), cos(pitch)) * 60.0
	stage.add_child(cam)
	cam.make_current()


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 8:
		root.get_viewport().get_texture().get_image().save_png(_out)
		print("saved ", _out)
		return true
	return false
