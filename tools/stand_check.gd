extends SceneTree
## Developer harness (P005): the procedural grandstand on its own, lit like a
## race by day (or night), without building a track. Three stands on a meadow
## beside a strip of red / white kerb: one facing the camera with animated
## spectators in its free seats (as VoxelLife seats them on the circuits),
## one facing away (the roof and the back), one side on; the menu / arena
## version with static spectators. Saves the race camera (58 degrees, the
## MINIATURE preset), a closer view and a low perspective shot.
## xvfb-run godot --path . -s tools/stand_check.gd -- --out=/tmp/sc [--variant=1] [--night=1]

const Grandstand := preload("res://src/voxel/voxel_grandstand.gd")
const CROWD_SHADER := preload("res://src/voxel/shaders/voxel_crowd.gdshader")

var _out := "user://sc"
var _variant := 1
var _night := false
var _f := 0
var _cam: Camera3D
var _shots: Array = []
var _k := 0
var _world: Node3D
var _glowing: Array = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--variant="):
			_variant = int(a.substr(10))
		elif a.begins_with("--night="):
			_night = a.substr(8) == "1"
	_world = Node3D.new()
	root.add_child.call_deferred(_world)
	_build.call_deferred()


func _build() -> void:
	var env := WorldEnvironment.new()
	env.environment = VoxelStage.make_environment()
	var e := env.environment
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.0
	if _night:
		e.background_color = Color(0.015, 0.018, 0.035)
		e.ambient_light_color = Color(0.36, 0.41, 0.65)
		e.ambient_light_energy = 0.3
		e.glow_intensity = 1.0
		e.glow_hdr_threshold = 0.8
		e.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
		sun.light_color = Color(0.55, 0.65, 1.0)
		sun.light_energy = 0.25
		sun.basis = Basis.looking_at(Vector3(-0.35, -1.0, -0.45).normalized(), Vector3.UP)
	else:
		e.ambient_light_color = Color(0.62, 0.68, 0.84)
		e.ambient_light_energy = 0.42
		e.glow_intensity = 0.3
		e.adjustment_saturation = 1.18
		e.tonemap_exposure = 0.92
		sun.light_color = Color(1.0, 0.95, 0.86)
		sun.light_energy = 0.95
		sun.basis = Basis.looking_at(Vector3(0.52, -1.15, -0.62).normalized(), Vector3.UP)
	_world.add_child(env)
	_world.add_child(sun)
	# the meadow, a road and a kerb strip (for the colour comparison)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(160, 160)
	ground.mesh = pm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.36, 0.62, 0.26) if _variant != 3 else Color(0.9, 0.92, 0.96)
	if _variant == 2:
		gmat.albedo_color = Color(0.55, 0.5, 0.4)
	ground.mesh.surface_set_material(0, gmat)
	_world.add_child(ground)
	var road := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(160, 0.05, 9.0)
	road.mesh = rm
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.3, 0.3, 0.33)
	road.material_override = rmat
	road.position = Vector3(0, 0.02, 9.0)
	_world.add_child(road)
	for i in 64:
		var kb := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.0, 0.5, 0.5)
		kb.mesh = bm
		var km := StandardMaterial3D.new()
		km.albedo_color = Color("e8432e") if i % 2 == 0 else Color("f2efe6")
		kb.material_override = km
		kb.position = Vector3(-32.0 + i * 1.0, 0.25, 4.3)
		_world.add_child(kb)
	var t0 := Time.get_ticks_usec()
	Grandstand.mesh(72, 30, 9, true)
	print("one stand mesh: %.0f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	# stand A: facing the camera (+Z), the race variant + animated sitters
	var a := _stand(Grandstand.mesh(72, 30, _variant, false, 0), Vector3(-10, 0, 0), 0.0)
	_seat_people(a)
	# stand B: facing away (roof, back wall, columns)
	_stand(Grandstand.mesh(72, 30, _variant, false, 1), Vector3(10, 0, -12), PI)
	# stand C: side on, the menu / arena version (static spectators)
	_stand(Grandstand.mesh(72, 30, 0, true), Vector3(-26, 0, -14), PI * 0.5)
	# stand D: the menu / arena version facing the camera
	_stand(Grandstand.mesh(72, 30, 0, true, 2), Vector3(10, 0, 0), 0.0)
	for mi in _glowing:
		(mi as GeometryInstance3D).set_instance_shader_parameter("lamp_glow", 1.0 if _night else 0.0)
	_cam = Camera3D.new()
	_world.add_child(_cam)
	_cam.make_current()
	# [name, ortho?, size / fov, target, pitch deg, yaw deg]
	_shots = [
		["race", true, 720.0 * Vox.PX / 1.22, Vector3(0, 0, -4), 58.0, 0.0],
		["close", true, 14.0, Vector3(-10, 2, 0), 58.0, 0.0],
		["close_menu", true, 14.0, Vector3(10, 2, 0), 58.0, 0.0],
		["back", true, 14.0, Vector3(10, 2, -12), 58.0, 0.0],
		["low", false, 40.0, Vector3(-10, 2.5, 0), 16.0, 25.0],
		["side", false, 40.0, Vector3(-26, 2.5, -14), 22.0, -35.0],
	]


func _stand(mesh: ArrayMesh, at: Vector3, yaw: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at
	mi.rotation.y = yaw
	_world.add_child(mi)
	_glowing.append(mi)
	return mi


## The animated crowd in the free seats (as VoxelLife does on the circuits).
func _seat_people(mi: MeshInstance3D) -> void:
	var seats: PackedVector3Array = mi.mesh.get_meta("seats")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var list: Array = []
	for s in seats:
		if rng.randf() < 0.72:
			list.append(s)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = VoxelLife.person_mesh(false)
	mm.instance_count = list.size()
	var mat := ShaderMaterial.new()
	mat.shader = CROWD_SHADER
	var pal := PackedVector3Array()
	for col in VoxelLife.PALETTE:
		var lc := (col as Color).srgb_to_linear()
		pal.append(Vector3(lc.r, lc.g, lc.b))
	mat.set_shader_parameter("palette", pal)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	_world.add_child(mmi)
	for i in list.size():
		var s := rng.randf_range(0.92, 1.08) * VoxelLife.PERSON_SCALE
		var local: Vector3 = list[i]
		var w := mi.transform * local
		w.y -= 0.42 * s
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, mi.rotation.y).scaled(Vector3.ONE * s), w))
		var idx := (rng.randi_range(0, 15) + 16 * rng.randi_range(0, 9)) / 255.0
		mm.set_instance_custom_data(i, Color(rng.randf(), 0.35 if i % 5 == 0 else 0.0, 0.5, idx))


func _process(_d: float) -> bool:
	_f += 1
	if _cam == null:
		return false
	if _k >= _shots.size():
		return true
	var sh: Array = _shots[_k]
	var target: Vector3 = sh[3]
	var pitch := deg_to_rad(float(sh[4]))
	var yaw := deg_to_rad(float(sh[5]))
	if bool(sh[1]):
		_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		_cam.size = float(sh[2])
		_cam.near = 1.0
		_cam.far = 200.0
		_cam.position = target + Vector3(0.0, sin(pitch), cos(pitch)) * 48.0
		_cam.rotation = Vector3(-pitch, 0.0, 0.0)
	else:
		_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		_cam.fov = float(sh[2])
		_cam.near = 0.1
		_cam.far = 200.0
		var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
		_cam.position = target + dir * 22.0
		_cam.look_at(target, Vector3.UP)
	if _f % 12 == 0:
		root.get_viewport().get_texture().get_image().save_png("%s_%s.png" % [_out, sh[0]])
		print("saved ", sh[0])
		_k += 1
	return false
