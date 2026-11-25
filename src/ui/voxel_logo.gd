class_name VoxelLogo
extends SubViewportContainer
## The VoxelRacing logo, a real voxel model rendered live: chunky pixel
## letters (VOXEL in race red over RACING in yellow) in stepped motorsport
## italics, on a dark ink backing plate, with a chequered strip between the
## rows that one of the game's own voxel cars races along. It sways gently.
## tools/make_branding.gd bakes it to PNG (window icon, README).

const GLYPHS := {
	"V": ["11..11", "11..11", "11..11", "11..11", ".1111.", ".1111.", "..11.."],
	"O": [".1111.", "11..11", "11..11", "11..11", "11..11", "11..11", ".1111."],
	"X": ["11..11", "11..11", ".1111.", "..11..", ".1111.", "11..11", "11..11"],
	"E": ["111111", "11....", "11....", "11111.", "11....", "11....", "111111"],
	"L": ["11....", "11....", "11....", "11....", "11....", "11....", "111111"],
	"R": ["11111.", "11..11", "11..11", "11111.", "11.11.", "11..11", "11..11"],
	"A": [".1111.", "11..11", "11..11", "111111", "11..11", "11..11", "11..11"],
	"C": [".11111", "11....", "11....", "11....", "11....", "11....", ".11111"],
	"I": ["1111", ".11.", ".11.", ".11.", ".11.", ".11.", "1111"],
	"N": ["11..11", "111.11", "111111", "11.111", "11..11", "11..11", "11..11"],
	"G": [".11111", "11....", "11....", "11.111", "11..11", "11..11", ".11111"],
}
const VS := 0.25

var viewport: SubViewport
var model: Node3D
var _car: Node3D
var _time := 0.0
var animate := true

static var _logo_mesh: ArrayMesh


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	viewport = SubViewport.new()
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.72, 0.95)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.3
	env.environment = e
	viewport.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-38), deg_to_rad(-28), 0)
	key.light_energy = 1.25
	key.shadow_enabled = true
	viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation = Vector3(deg_to_rad(-20), deg_to_rad(150), 0)
	rim.light_energy = 0.5
	rim.light_color = Color(0.5, 0.7, 1.0)
	viewport.add_child(rim)
	model = Node3D.new()
	viewport.add_child(model)
	var mi := MeshInstance3D.new()
	mi.mesh = logo_mesh()
	mi.basis = Basis(Vector3(1, 0, 0), Vector3(0.2, 1, 0), Vector3(0, 0, 1))  # motorsport italics
	model.add_child(mi)
	_car = Node3D.new()
	model.add_child(_car)
	var resolver := AssetResolver.new()
	var tex := resolver.get_texture("cars/body_player")
	var layout: WheelLayout = load("res://src/presentation/default_wheel_layout.tres")
	var body := MeshInstance3D.new()
	body.mesh = VoxelCars.body_mesh(tex, layout, "cars/body_player")
	body.set_instance_shader_parameter("head_glow", 0.4)
	_car.add_child(body)
	var at := layout.positions("cars/body_player")
	for ax in [at.x, at.y]:
		for az in [-at.z, at.z]:
			var w := MeshInstance3D.new()
			w.mesh = VoxelCars.wheel_mesh()
			w.position = Vector3(ax, VoxelCars.WHEEL_R * Vox.CAR_VOXEL_PX, az) * Vox.PX
			_car.add_child(w)
	_car.scale = Vector3.ONE * 0.95
	var cam := Camera3D.new()
	cam.fov = 17.0
	cam.position = Vector3(0, 1.2, 30.0)
	cam.look_at_from_position(cam.position, Vector3(0, -0.2, 0), Vector3.UP)
	viewport.add_child(cam)
	cam.make_current()


## Holds the logo at a moment of its animation (baked pictures).
func freeze(t: float) -> void:
	_time = t
	animate = true
	_process(0.0)
	animate = false


func _process(delta: float) -> void:
	if not animate or model == null:
		return
	_time += delta
	model.rotation = Vector3(sin(_time * 0.7) * 0.05, sin(_time * 0.45) * 0.16, 0.0)
	# the little car laps along the chequered strip
	var span := 11.0
	var t := fposmod(_time * 0.22, 1.0)
	var x := lerpf(-span, span, smoothstep(0.0, 1.0, t))
	_car.position = Vector3(x, -0.2, 1.4)
	_car.rotation = Vector3(0, 0, 0)
	_car.visible = t < 0.97


## The logo model (shared): letters, plate and strip, centred.
static func logo_mesh() -> ArrayMesh:
	if _logo_mesh != null:
		return _logo_mesh
	var rows := [["VOXEL", VrStyle.RED], ["RACING", VrStyle.YELLOW]]
	# letter pixels of each row (x, y) with the colour, in a 2D plan
	var cells := {}
	var row_w: Array[int] = []
	for r in rows:
		var w := 0
		for ch in String(r[0]):
			w += (GLYPHS[ch][0] as String).length() + 1
		row_w.append(w - 1)
	var width := maxi(row_w[0], row_w[1]) + 4
	var top_y := 0
	var strip_y := 8
	var bottom_y := 11
	for k in rows.size():
		var text: String = rows[k][0]
		var col: Color = rows[k][1]
		var x0: int = (width - row_w[k]) / 2
		var y0 := top_y if k == 0 else bottom_y
		for ch in text:
			var g: Array = GLYPHS[ch]
			for gy in 7:
				var line: String = g[gy]
				for gx in line.length():
					if line[gx] == "1":
						cells[Vector2i(x0 + gx, y0 + gy)] = col
			x0 += (g[0] as String).length() + 1
	var h := bottom_y + 7
	var g := VoxelGrid.new(Vector3i(width + 6, h + 6, 6), VS, Vector3.ZERO)
	# the ink plate: every letter pixel grown by one, plus the strip band
	var plate := {}
	for c in cells:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				plate[Vector2i(c.x + dx, c.y + dy)] = true
	for x in range(1, width - 1):
		for y in range(strip_y - 1, strip_y + 2):
			plate[Vector2i(x, y)] = true
	var rim := {}
	for p in plate:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				rim[Vector2i(p.x + dx, p.y + dy)] = true
	for p in rim:  # a cream rim: the badge reads on any background
		g.set_v(p.x + 2, h + 2 - p.y, 0, Vox.SOLID, VrStyle.PAPER)
	for p in plate:
		var gy: int = h + 2 - p.y
		for z in range(1, 3):
			g.set_v(p.x + 2, gy, z, Vox.SOLID, VrStyle.INK)
	# chequered strip
	for x in range(1, width - 1):
		for y in 2:
			var col := VrStyle.PAPER if (x + y) % 2 == 0 else Color(0.08, 0.08, 0.12)
			g.set_v(x + 2, h + 2 - (strip_y + y), 3, Vox.SOLID, col)
	# letters stand proud of the plate, the top row lit a touch brighter
	for c in cells:
		var gy: int = h + 2 - c.y
		var col: Color = cells[c]
		for z in range(3, 6):
			var shade := col if z == 5 else col.darkened(0.25)
			if z == 5 and (c.y == top_y or c.y == bottom_y):
				shade = col.lightened(0.18)
			g.set_v(c.x + 2, gy, z, Vox.SOLID, shade)
	var size := g.size()
	_logo_mesh = VoxelMesher.build_mesh(g, VoxelCars.material(), Vector3(size.x * 0.5, size.y * 0.5, 3.0) * VS, 0.03)
	return _logo_mesh
