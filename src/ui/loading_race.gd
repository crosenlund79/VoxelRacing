class_name LoadingRace
extends CanvasLayer
## "The Little Race": VoxelRacing's track loading screen. While a circuit's
## voxel world is being built, five little voxel cars race along a strip of
## track from a start gantry on the left to a chequered finish on the right.
## The leader follows the real build progress (never ahead of it): it only
## crosses the line once the world is ready, then the screen hands over to
## the race. Fast loads cross fast; nothing waits on purpose.

signal finished

const START_X := -10.5
const FINISH_X := 10.5
const LANES := [-2.5, -1.25, 0.0, 1.25, 2.5]
const CARS := ["cars/body_player", "cars/body_ai_2", "cars/body_ai_4", "cars/body_ai_9", "cars/body_ai_6"]
const TIPS := [
	"{camera_view} cycles the camera: miniature, high, low and top-down.",
	"{toggle_lighting} switches the night lights on and off.",
	"Wrecks leave their bits on the road. Drive through them!",
	"Every car breaks apart voxel by voxel. Mind the walls.",
	"Brake lights glow when a rival slows down. Watch them at night.",
	"{back} pauses the race.",
	"{photo_mode} freezes the race for a photo.",
	"Hover or highlight an icon to see what it means.",
]

var progress_source: Callable
var _viewport: SubViewport
var _world: Node3D
var _fx: VoxelFx
var _cars: Array[Node3D] = []
var _wheels: Array = []
var _offset_phase := PackedFloat32Array()
var _x := PackedFloat32Array()
var _shown := 0.0
var _done := false
var _finishing := false
var _finish_time := 0.0
var _time := 0.0
var _active := false
var _title: Label
var _sub: Label
var _pct: Label
var _tip: Label
var _bar: ProgressBar
var _logo: VoxelLogo
var _root: Control
var _puff_clock := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	layer = 45
	visible = false
	_rng.seed = 12
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var bg := TextureRect.new()
	var grad := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.set_color(0, VrStyle.INK)
	gr.set_color(1, Color("3b2f5c"))
	grad.gradient = gr
	grad.fill_from = Vector2(0, 0)
	grad.fill_to = Vector2(0, 1)
	bg.texture = grad
	bg.size = Vector2(1280, 720)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	_root.add_child(bg)
	var container := SubViewportContainer.new()
	container.stretch = true
	container.position = Vector2(0, 200)
	container.size = Vector2(1280, 360)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(container)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	container.add_child(_viewport)
	_logo = VoxelLogo.new()
	_logo.position = Vector2(340, 6)
	_logo.size = Vector2(600, 230)
	_root.add_child(_logo)
	_title = _label("", 30, VrStyle.PAPER, "bold")
	_title.position = Vector2(0, 560)
	_title.size = Vector2(1280, 48)
	_root.add_child(_title)
	_sub = _label("", 18, VrStyle.YELLOW, "regular")
	_sub.position = Vector2(0, 604)
	_sub.size = Vector2(1280, 32)
	_root.add_child(_sub)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.position = Vector2(390, 646)
	_bar.size = Vector2(500, 18)
	_bar.max_value = 1.0
	var under := StyleBoxFlat.new()
	under.bg_color = VrStyle.INK
	under.border_color = VrStyle.PAPER
	under.set_border_width_all(2)
	var fill := StyleBoxTexture.new()
	fill.texture = VrStyle.checker(16, 2, 4)
	fill.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	fill.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	_bar.add_theme_stylebox_override("background", under)
	_bar.add_theme_stylebox_override("fill", fill)
	_root.add_child(_bar)
	_pct = _label("0%", 18, VrStyle.PAPER, "bold")
	_pct.position = Vector2(900, 638)
	_pct.size = Vector2(120, 32)
	_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_root.add_child(_pct)
	_tip = _label("", 14, VrStyle.PAPER_DIM, "regular")
	_tip.position = Vector2(0, 684)
	_tip.size = Vector2(1280, 24)
	_root.add_child(_tip)
	_build_world()


func _label(text: String, size: int, color: Color, kind: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", VrStyle.font(kind))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", VrStyle.INK)
	l.add_theme_constant_override("outline_size", 3)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Starts the little race (title: the circuit, sub: environment / mode).
func begin(title: String, sub: String, source: Callable = Callable()) -> void:
	_title.text = title
	_sub.text = sub
	_tip.text = PlayerControls.fmt(TIPS[_rng.randi_range(0, TIPS.size() - 1)])
	progress_source = source
	_shown = 0.0
	_done = false
	_finishing = false
	_time = 0.0
	_fx.clear()
	for k in _cars.size():
		_x[k] = START_X - 0.2 - k * 0.15
	_active = true
	visible = true
	_logo.animate = true


func end() -> void:
	_active = false
	visible = false
	_logo.animate = false


## The world is ready: the leader may cross the line.
func complete() -> void:
	_done = true


func _process(delta: float) -> void:
	if not _active:
		return
	delta = minf(delta, 0.1)
	_time += delta
	var real := 0.0
	if progress_source.is_valid():
		real = clampf(float(progress_source.call()), 0.0, 1.0)
	if _done:
		real = 1.0
	# the shown progress chases the real one (never ahead; fast when it's done)
	var cap := real if _done else minf(real, 0.96)
	_shown = minf(cap, _shown + delta * (1.4 if _done else 0.55))
	_bar.value = _shown
	_pct.text = "%d%%" % int(round(_shown * 100.0))
	var lead_x := lerpf(START_X, FINISH_X, _shown)
	if _done and _shown >= 0.999:
		if not _finishing:
			_finishing = true
			_finish_time = _time
			_celebrate()
		lead_x = FINISH_X + (_time - _finish_time) * 16.0
	for k in _cars.size():
		# personalities: each car surges and drops back on its own rhythm (overtakes)
		var off := -1.6 - 1.4 * sin(_time * (1.1 + k * 0.37) + _offset_phase[k])
		if k == 0:
			off = -0.9 - 1.2 * sin(_time * 0.8 + 1.3)
		var target := lead_x + off
		if not _finishing:
			target = minf(target, lead_x)
		var nx := lerpf(_x[k], target, 1.0 - exp(-delta * 2.2))
		var moved := nx - _x[k]
		_x[k] = nx
		var car := _cars[k]
		car.position = Vector3(nx, absf(sin(_time * 14.0 + k)) * 0.03, LANES[k])
		car.rotation.y = sin(_time * (2.0 + k * 0.5)) * 0.04
		for w in (_wheels[k] as Array):
			(w as Node3D).rotation.z -= moved / (VoxelCars.WHEEL_R * Vox.CAR_VOXEL_PX * Vox.PX)
	_puff_clock += delta
	if _puff_clock > 0.07:
		_puff_clock = 0.0
		for k in _cars.size():
			var back := _cars[k].global_position + Vector3(-2.1, 0.25, _rng.randf_range(-0.3, 0.3))
			_fx.puff(back, Vector3(-1.5, 0.6, 0), Color(0.9, 0.86, 0.8), _rng.randf_range(0.18, 0.3), 0.5, 0.5)
	if _finishing and _time - _finish_time > 0.9:
		_active = false
		finished.emit()


func _celebrate() -> void:
	var cols := [VrStyle.RED, VrStyle.YELLOW, VrStyle.TEAL, VrStyle.PAPER, VrStyle.PINK, VrStyle.SKY]
	for k in 70:
		var v := Vector3(_rng.randf_range(-2, 4), _rng.randf_range(5, 10), _rng.randf_range(-3, 3))
		_fx.spark(Vector3(FINISH_X, 3.2, 0), v, cols[k % cols.size()], _rng.randf_range(0.09, 0.15), _rng.randf_range(1.2, 2.0), 0.3, 0.4)


# ------------------------------------------------------------ the little world

func _build_world() -> void:
	_world = Node3D.new()
	_viewport.add_child(_world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.68, 0.7, 0.95)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.4
	e.ssao_enabled = true
	env.environment = e
	_world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-48), deg_to_rad(-35), 0)
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.92, 0.82)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	_world.add_child(sun)
	var strip := MeshInstance3D.new()
	strip.mesh = _strip_mesh()
	strip.set_instance_shader_parameter("lamp_glow", 0.7)
	_world.add_child(strip)
	_fx = VoxelFx.new()
	_world.add_child(_fx)
	_fx.ground = func(_x: float, _z: float) -> float: return 0.05
	var resolver := AssetResolver.new()
	var layout: WheelLayout = load("res://src/presentation/default_wheel_layout.tres")
	for k in CARS.size():
		var root := Node3D.new()
		var body := MeshInstance3D.new()
		body.mesh = VoxelCars.body_mesh(resolver.get_texture(CARS[k]), layout, CARS[k])
		root.add_child(body)
		var at := VoxelCars.wheels_of(layout, resolver.get_texture(CARS[k]), CARS[k])
		var ws: Array = []
		for ax in [at.x, at.y]:
			for az in [-at.z, at.z]:
				var w := MeshInstance3D.new()
				w.mesh = VoxelCars.wheel_mesh()
				w.position = Vector3(ax, VoxelCars.WHEEL_R * Vox.CAR_VOXEL_PX, az) * Vox.PX
				root.add_child(w)
				ws.append(w)
		root.scale = Vector3.ONE * 1.05
		_world.add_child(root)
		_cars.append(root)
		_wheels.append(ws)
		_offset_phase.append(k * 1.7)
		_x.append(START_X)
	# props: trees and flags along the verges
	for k in 7:
		var tree := MeshInstance3D.new()
		var logical := "scenery/tree_round" if k % 2 == 0 else "scenery/tree_bloom"
		var spec: Dictionary = AssetCatalog.SPECS[logical]
		tree.mesh = VoxelProps.mesh_for(logical, resolver.get_texture(logical), spec.display_size)
		tree.position = Vector3(-13.0 + k * 4.3 + _rng.randf_range(-0.6, 0.6), 0, -6.2 - _rng.randf_range(0.0, 1.2))
		tree.scale = Vector3.ONE * _rng.randf_range(0.6, 0.85)
		tree.set_instance_shader_parameter("sway", 0.004)
		_world.add_child(tree)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0, 10.5, 19.0)
	cam.look_at_from_position(cam.position, Vector3(0, 0.2, -0.6), Vector3.UP)
	_world.add_child(cam)
	cam.make_current()


## The strip: grass, kerbs, asphalt with a dashed line, the start line and a
## gantry with lights on the left, the chequered finish and its arch on the
## right (voxels of 0.25 units).
static func _strip_mesh() -> ArrayMesh:
	var vs := 0.25
	var nx := 112
	var nz := 48
	var g := VoxelGrid.new(Vector3i(nx, 22, nz), vs, Vector3.ZERO)
	var road0 := 9
	var road1 := 39
	for z in nz:
		for x in nx:
			var h := Vox.hash3(x, 1, z)
			var grass := VrStyle.GREEN.darkened(0.15 + 0.1 * h)
			if z < road0 - 1 or z > road1:
				g.set_v(x, 0, z, Vox.SOLID, grass)
				g.set_v(x, 1, z, Vox.SOLID, grass)
				if h > 0.93:
					g.set_v(x, 2, z, Vox.SOLID, [VrStyle.YELLOW, VrStyle.PINK, Color.WHITE][int(h * 1000) % 3])
			elif z == road0 - 1 or z == road1:
				var kerb := VrStyle.RED if (x / 3) % 2 == 0 else VrStyle.PAPER
				g.set_v(x, 0, z, Vox.SOLID, kerb)
				g.set_v(x, 1, z, Vox.SOLID, kerb)
				g.set_v(x, 2, z, Vox.SOLID, kerb)
			else:
				var asphalt := Color(0.25, 0.26, 0.3).lightened(0.05 * h)
				g.set_v(x, 0, z, Vox.SOLID, asphalt)
				if z == (road0 + road1) / 2 and (x / 4) % 2 == 0:
					asphalt = VrStyle.PAPER.darkened(0.1)
				g.set_v(x, 1, z, Vox.SOLID, asphalt)
	# start line (left) with a gantry of red lights
	var sx := 12
	for z in range(road0, road1):
		g.set_v(sx, 1, z, Vox.SOLID, VrStyle.PAPER)
	for y in range(1, 16):
		for z in [road0 - 2, road1 + 1]:
			g.set_v(sx, y, z, Vox.METAL, Color(0.3, 0.3, 0.34))
	for z in range(road0 - 2, road1 + 2):
		g.set_v(sx, 16, z, Vox.METAL, Color(0.18, 0.18, 0.2))
		g.set_v(sx, 17, z, Vox.METAL, Color(0.18, 0.18, 0.2))
	for k in 5:
		g.set_v(sx + 1, 16, road0 + 2 + k * 3, Vox.GLOW, Color(1.0, 0.2, 0.12))
	# finish line (right): chequered band and an arch with a chequered banner
	var fx := nx - 16
	for z in range(road0, road1):
		for dx in 2:
			g.set_v(fx + dx, 1, z, Vox.SOLID, VrStyle.PAPER if (z + dx) % 2 == 0 else VrStyle.INK)
	for y in range(1, 18):
		for z in [road0 - 2, road1 + 1]:
			g.set_v(fx, y, z, Vox.SOLID, VrStyle.RED if (y / 2) % 2 == 0 else VrStyle.PAPER)
	for z in range(road0 - 2, road1 + 2):
		for y in range(17, 21):
			g.set_v(fx, y, z, Vox.SOLID, VrStyle.PAPER if (z + y) % 2 == 0 else VrStyle.INK)
	return VoxelMesher.build_mesh(g, VoxelCars.material(), Vector3(nx * 0.5, 2.0, nz * 0.5) * vs, 0.05)
