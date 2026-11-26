extends CanvasLayer
## VoxelRacing: the podium celebration. A short, skippable 3D interlude drawn
## over the race in its own SubViewport world: a miniature voxel podium (gold,
## silver and bronze blocks with raised voxel numerals) on a pit apron at dusk,
## the top three cars parked on their steps, a blocky voxel driver in their
## helmet colour standing beside each car, trophies, waving flags, bunting, a
## cheering voxel crowd in a grandstand (one instanced mesh, animated on the
## GPU), confetti and fireworks. The camera dollies low from third to second
## to the winner, then pulls back and orbits (about 7 s), then `finished`.
## Every rival celebrates in character (see _celebrate()); second and third
## clap and turn to the winner. Confirm / Fire / Back skips.
## Presentation only: nothing here touches the race.
##
##   var podium = preload("res://src/ui/podium_scene.gd").new()
##   add_child(podium)
##   podium.present(entries, resolver)  # entries: up to 3 Dictionaries, best first
##   await podium.finished

signal finished

const DURATION := 7.2
const INPUT_GRACE := 0.4
const FADE_IN := 0.35
const FADE_OUT := 0.3
## When the winner starts celebrating (the camera arrives on the top step).
const WINNER_CUE := 2.7

## Helmet colours by racer id (0 = the player, 1..9 the rivals).
const HELMETS := ["f7b731", "e8e8f0", "e8432e", "59c3f2", "7bc950", "f45b9b", "2ec4b6", "a37ef0", "ff8c2e", "3d4a8a"]
const PLACE_COLORS := [Color("f7b731"), Color("c9cfdc"), Color("d0884a")]
const TROPHY_COLORS := [Color("ffc93a"), Color("d9dde6"), Color("cd7f3e")]

## Steps by place index (0 = 1st): centre x and height in step voxels.
const STEP_VS := 0.2
const STEP_X := [0.0, -5.4, 5.4]
const STEP_CELLS := [15, 11, 8]
const STEP_NX := 26
const STEP_NZ := 28
## Numerals: glyph pixel size in numeral voxels, per place.
const NUM_VS := 0.07
const NUM_SCALE := [4, 3, 2]
const DIGITS := {
	1: ["..#..", ".##..", "#.#..", "..#..", "..#..", "..#..", "#####"],
	2: [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
	3: ["####.", "....#", "....#", ".###.", "....#", "....#", "####."],
}
## Layout on each step (by place index): driver, car and trophy.
const DRIVER_DX := [-0.9, 0.9, -0.9]
const DRIVER_Z := 1.6
const CAR_Z := -0.75
## Cars show their noses to the camera: outer steps point outwards.
const CAR_YAW_DEG := [-28.0, 212.0, -32.0]
const TROPHY_DX := [-1.95, 1.95, -1.95]
const TROPHY_Z := 1.75
const TROPHY_SCALE := [1.3, 1.08, 0.95]

## The driver figure, in figure voxels.
const FV := 0.066
const LEG_H := 8 * FV
const TORSO_H := 8 * FV
const HIP_X := 2.0 * FV
const SHOULDER_X := 5.5 * FV

const CONF_MAX := 520
const BAR_TOP := 78.0
const BAR_BOTTOM := 118.0
const CONFETTI := [Color("e8432e"), Color("f7b731"), Color("2ec4b6"), Color("fff4de"), Color("f45b9b"), Color("59c3f2"), Color("7bc950"), Color("a37ef0")]

## The crowd: vertex colours mark the shirt (magenta), arms down (r > b) and
## arms up (b > r); the shader paints the shirt in the instance colour and
## cheers: a wave runs along the stand (arms up, hops), on the GPU.
const CROWD_SHADER := """
shader_type spatial;
render_mode cull_back, depth_draw_opaque;
varying vec3 v_col;
varying float v_ao;
vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}
void vertex() {
	vec4 cd = INSTANCE_CUSTOM;
	float ph = cd.a * 6.2831853;
	float wave = sin(TIME * 2.6 - ph * 2.0) + 0.6 * sin(TIME * 1.3 + ph * 9.0);
	float cheer = step(0.35, wave);
	float hop = max(0.0, sin(TIME * 10.0 + ph * 23.0)) * (0.02 + 0.1 * cheer);
	vec3 c = COLOR.rgb;
	float marked = step(c.g, 0.02) * step(0.04, max(c.r, c.b));
	float ratio = c.b / max(c.r, 0.001);
	float arm_down = marked * step(ratio, 0.75);
	float arm_up = marked * step(1.5, ratio);
	float hide = max(arm_up * (1.0 - cheer), arm_down * cheer);
	VERTEX = mix(VERTEX, vec3(0.0, 0.55, 0.0), hide);
	VERTEX.y += hop;
	v_col = mix(c, cd.rgb * max(c.r, c.b), marked);
	v_ao = COLOR.a;
}
void fragment() {
	ALBEDO = to_linear(v_col);
	AO = v_ao;
	AO_LIGHT_AFFECT = 0.5;
	ROUGHNESS = 0.85;
	SPECULAR = 0.3;
}
"""

static var _meshes := {}

var _resolver: AssetResolver
var _layout: WheelLayout
var _entries: Array = []
var _time := 0.0
var _active := false
var _ui_built := false
var _rng := RandomNumberGenerator.new()
var _finn_mode := 0
var _shake := 0.0
var _cheered := false
var _fireworks: Array = []
var _cam_keys: Array = []

# the 3D world (rebuilt for every presentation, freed at the end)
var _container: SubViewportContainer
var _viewport: SubViewport
var _world: Node3D
var _cam: Camera3D
var _fx: VoxelFx
var _figs: Array = []
var _flags: Array = []
var _glints: Array = []

# confetti: flat paper flakes that tumble and flutter down (own MultiMesh)
var _conf: MultiMesh
var _c_pos := PackedVector3Array()
var _c_vel := PackedVector3Array()
var _c_rot := PackedVector3Array()
var _c_spin := PackedVector3Array()
var _c_life := PackedFloat32Array()
var _c_next := 0
var _c_rain := 0.0

# the overlay
var _root: Control
var _bar_top: ColorRect
var _bar_bottom: ColorRect
var _title_row: HBoxContainer
var _title: Label
var _hint: Label
var _fade: ColorRect
var _plates: Array = []
var _sfx: AudioStreamPlayer


func _ready() -> void:
	_build_ui()
	if not _active:
		visible = false
		set_process(false)


## Shows the podium for `entries` (up to 3 Dictionaries, best first: id, name,
## full_name, logical, tint, place, is_player). `finished` follows after about
## 7 s, or at once on skip().
func present(entries: Array, resolver: AssetResolver, title: String = "PODIUM") -> void:
	_build_ui()
	_free_world()
	_resolver = resolver if resolver != null else AssetResolver.new()
	_entries = _sorted_entries(entries)
	_rng.randomize()
	_finn_mode = _rng.randi_range(0, 2)
	_time = 0.0
	_shake = 0.0
	_cheered = false
	_c_rain = 0.0
	_fireworks = []
	for t in [3.15, 3.9, 4.6, 5.3, 6.0, 6.6]:
		_fireworks.append([t + _rng.randf_range(-0.12, 0.12), false])
	_build_world()
	_build_overlay(title)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	visible = true
	_active = true
	set_process(true)
	_update(0.0)  # everything in place for the first frame


## Ends the celebration now: `finished` (once), hidden, the 3D world freed.
func skip() -> void:
	if _active:
		_finish()


func _finish() -> void:
	_active = false
	set_process(false)
	visible = false
	_free_world()
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	finished.emit()


func _process(delta: float) -> void:
	if not _active:
		return
	delta = minf(delta, 0.1)
	_time += delta
	if _time > INPUT_GRACE and _skip_pressed():
		skip()
		return
	_update(delta)
	if _time >= DURATION:
		_finish()


func _skip_pressed() -> bool:
	for a in [PlayerControls.CONFIRM, PlayerControls.FIRE, PlayerControls.BACK]:
		if InputMap.has_action(a) and Input.is_action_just_pressed(a):
			return true
	return false


## Up to three entries, each with a distinct place 1..3 (missing places: by order).
func _sorted_entries(entries: Array) -> Array:
	var out: Array = []
	var used := {}
	for i in entries.size():
		if out.size() >= 3:
			break
		var e = entries[i]
		if not (e is Dictionary):
			continue
		var place := clampi(int((e as Dictionary).get("place", i + 1)), 1, 3)
		if used.has(place):
			for p in [1, 2, 3]:
				if not used.has(p):
					place = p
					break
		used[place] = true
		var d: Dictionary = (e as Dictionary).duplicate()
		d["place"] = place
		out.append(d)
	return out


func _update(dt: float) -> void:
	if _world == null:
		return
	_update_camera(dt)
	for f in _figs:
		_animate_figure(f, dt)
	_update_flags()
	_update_effects(dt)
	_step_confetti(dt)
	_update_overlay()


# ------------------------------------------------------------ overlay

func _build_ui() -> void:
	if _ui_built:
		return
	_ui_built = true
	layer = 55
	process_mode = Node.PROCESS_MODE_ALWAYS
	PlayerControls.ensure_actions()
	_layout = load("res://src/presentation/default_wheel_layout.tres")
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_container = SubViewportContainer.new()
	_container.stretch = true
	_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_container)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.size = Vector2i(1280, 720)
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_container.add_child(_viewport)
	# letterbox bars, each with a race-red inner edge
	_bar_top = ColorRect.new()
	_bar_top.color = VrStyle.INK
	_bar_top.size = Vector2(1280, 78)
	_bar_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bar_top)
	var edge := ColorRect.new()
	edge.color = VrStyle.RED
	edge.position = Vector2(0, 74)
	edge.size = Vector2(1280, 4)
	_bar_top.add_child(edge)
	_bar_bottom = ColorRect.new()
	_bar_bottom.color = VrStyle.INK
	_bar_bottom.size = Vector2(1280, BAR_BOTTOM)
	_bar_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bar_bottom)
	var edge2 := ColorRect.new()
	edge2.color = VrStyle.RED
	edge2.size = Vector2(1280, 4)
	_bar_bottom.add_child(edge2)
	# the title between two chequered strips
	_title_row = HBoxContainer.new()
	_title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_title_row.add_theme_constant_override("separation", 20)
	_title_row.position = Vector2(0, 12)
	_title_row.size = Vector2(1280, 52)
	_title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_title_row)
	for k in 2:
		var chk := TextureRect.new()
		chk.texture = VrStyle.checker(12, 2, 6)
		chk.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		chk.custom_minimum_size = Vector2(72, 52)
		chk.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_title_row.add_child(chk)
		if k == 0:
			_title = _label("PODIUM", "bold", 40, VrStyle.PAPER)
			_title.add_theme_constant_override("outline_size", 10)
			_title_row.add_child(_title)
	_hint = _label("", "regular", 16, VrStyle.PAPER_DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.position = Vector2(760, 692)
	_hint.size = Vector2(496, 28)
	_root.add_child(_hint)
	_fade = ColorRect.new()
	_fade.color = VrStyle.INK
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_fade)
	_sfx = AudioStreamPlayer.new()
	_sfx.bus = "Effects" if AudioServer.get_bus_index("Effects") >= 0 else "Master"
	add_child(_sfx)


func _label(text: String, kind: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", VrStyle.font(kind))
	l.add_theme_font_size_override("font_size", VrStyle.px(size))
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", VrStyle.INK)
	l.add_theme_constant_override("outline_size", 6)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_overlay(title: String) -> void:
	_title.text = title
	_hint.text = PlayerControls.fmt("{confirm} / {back}: skip")
	for p in _plates:
		(p[0] as Control).queue_free()
	_plates.clear()
	# name plates in podium order: 2nd left, 1st centre, 3rd right
	var centre_x := [640.0, 300.0, 980.0]
	var appear := [WINNER_CUE + 0.15, 1.5, 0.35]
	for e in _entries:
		var k: int = int(e.place) - 1
		var plate := _make_plate(e, k)
		_root.add_child(plate)
		_root.move_child(plate, _fade.get_index())
		plate.size = plate.get_combined_minimum_size()
		plate.position = Vector2(centre_x[k] - plate.size.x * 0.5, 720.0 - BAR_BOTTOM + 44.0 - plate.size.y * 0.5)
		plate.pivot_offset = plate.size * 0.5
		plate.scale = Vector2.ZERO
		_plates.append([plate, appear[k]])


func _make_plate(e: Dictionary, k: int) -> Control:
	var panel := PanelContainer.new()
	var sb := VrStyle.panel(0.95)
	sb.content_margin_left = 14
	sb.content_margin_right = 20
	sb.content_margin_top = 8
	sb.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(250 if k > 0 else 290, 0)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hb)
	var chip := _label("P%d" % (k + 1), "bold", 32 if k == 0 else 24, VrStyle.INK)
	chip.add_theme_constant_override("outline_size", 0)
	var cs := VrStyle.chip(PLACE_COLORS[k])
	cs.content_margin_left = 10
	cs.content_margin_right = 10
	chip.add_theme_stylebox_override("normal", cs)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(chip)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", -6)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(vb)
	var is_player := bool(e.get("is_player", int(e.get("id", -1)) == 0))
	var name := String(e.get("name", "?")).to_upper()
	vb.add_child(_label(name, "bold", 32 if k == 0 else 24, VrStyle.YELLOW if is_player else VrStyle.PAPER))
	var sub := _subtitle(e)
	if not sub.is_empty():
		vb.add_child(_label(sub, "regular", 16, VrStyle.PAPER_DIM))
	return panel


## The plate's second line: the nickname of a rival, else the full name.
static func _subtitle(e: Dictionary) -> String:
	var full := String(e.get("full_name", ""))
	var name := String(e.get("name", ""))
	var id := int(e.get("id", -1))
	if id >= 1 and id <= RivalRoster.count():
		return RivalRoster.nickname(id).to_upper()
	if full.is_empty() or full.to_upper() == name.to_upper():
		return ""
	return full


func _update_overlay() -> void:
	var a_in := _ease_out(clampf(_time / 0.45, 0.0, 1.0))
	_bar_top.position.y = lerpf(-78.0, 0.0, a_in)
	_bar_bottom.position.y = lerpf(720.0, 720.0 - BAR_BOTTOM, a_in)
	var fade_in := 1.0 - clampf(_time / FADE_IN, 0.0, 1.0)
	var fade_out := smoothstep(DURATION - FADE_OUT, DURATION, _time)
	_fade.color.a = maxf(fade_in, fade_out)
	var tk := clampf((_time - 0.15) / 0.35, 0.0, 1.0)
	_title_row.modulate.a = tk
	_title_row.position.y = lerpf(-30.0, 12.0, _ease_out(tk))
	_hint.modulate.a = clampf((_time - INPUT_GRACE) / 0.3, 0.0, 1.0)
	for p in _plates:
		var c: Control = p[0]
		var k := clampf((_time - float(p[1])) / 0.4, 0.0, 1.0)
		c.scale = Vector2.ONE * _back_out(k)
		c.modulate.a = clampf(k * 3.0, 0.0, 1.0)


static func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)


static func _back_out(x: float) -> float:
	if x <= 0.0:
		return 0.0
	var c := 2.2
	var y := x - 1.0
	return 1.0 + (c + 1.0) * y * y * y + c * y * y


# ------------------------------------------------------------ the world

func _free_world() -> void:
	if _world != null:
		_world.queue_free()
	_world = null
	_cam = null
	_fx = null
	_conf = null
	_figs.clear()
	_flags.clear()
	_glints.clear()


func _step_top(k: int) -> float:
	return STEP_CELLS[k] * STEP_VS


## Height of the stage at (x, z): a step's top or the apron (0).
func _ground_at(x: float, z: float) -> float:
	if absf(z) < STEP_NZ * STEP_VS * 0.5:
		for k in 3:
			if absf(x - STEP_X[k]) < STEP_NX * STEP_VS * 0.5:
				return _step_top(k)
	return 0.0


func _build_world() -> void:
	_world = Node3D.new()
	_viewport.add_child(_world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("1f2554")
	sm.sky_horizon_color = Color("f08a5f")
	sm.sky_curve = 0.11
	sm.ground_horizon_color = Color("4a2f66")
	sm.ground_bottom_color = VrStyle.INK
	sm.sun_angle_max = 18.0
	sm.sun_curve = 0.08
	sky.sky_material = sm
	e.sky = sky
	e.background_mode = Environment.BG_SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.64, 0.57, 0.88)
	e.ambient_light_energy = 0.62
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.02
	e.glow_enabled = true
	e.glow_intensity = 0.5
	e.glow_hdr_threshold = 1.0
	e.fog_enabled = true
	e.fog_light_color = Color("6a4a80")
	e.fog_density = 0.006
	e.fog_sky_affect = 0.0
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.12
	env.environment = e
	_world.add_child(env)
	# the key light: a warm low sun from the front left
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.8, 0.6)
	key.light_energy = 1.4
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 50.0
	key.basis = Basis.looking_at(Vector3(0.5, -0.62, -0.62).normalized(), Vector3.UP)
	_world.add_child(key)
	# the setting sun in the sky (paints the sky only)
	var sun := DirectionalLight3D.new()
	sun.sky_mode = DirectionalLight3D.SKY_MODE_SKY_ONLY
	sun.light_color = Color(1.0, 0.62, 0.4)
	sun.light_energy = 1.0
	sun.light_angular_distance = 3.5
	sun.basis = Basis.looking_at(Vector3(0.42, -0.24, 1.0).normalized(), Vector3.UP)
	_world.add_child(sun)
	_add_mesh(_floor_mesh(), Vector3.ZERO)
	_add_mesh(_stand_mesh(), Vector3.ZERO)
	_add_mesh(_bunting_mesh(), Vector3(0, 0, -10.9))
	_build_crowd()
	for k in 3:
		_add_mesh(_step_mesh(k), Vector3(STEP_X[k], 0, 0))
		var num := _numeral_mesh(k)
		var nh: float = (7 * NUM_SCALE[k] + 2) * NUM_VS
		_add_mesh(num, Vector3(STEP_X[k], (_step_top(k) - nh) * 0.5, STEP_NZ * STEP_VS * 0.5))
	_build_props()
	_fx = VoxelFx.new()
	_world.add_child(_fx)
	_fx.ground = _ground_at
	_build_confetti()
	for e2 in _entries:
		_add_racer(e2)
	_cam = Camera3D.new()
	_cam.fov = 38.0
	_cam.near = 0.1
	_cam.far = 220.0
	_world.add_child(_cam)
	_cam.make_current()
	_build_camera_keys()


func _add_mesh(mesh: Mesh, pos: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	(parent if parent != null else _world).add_child(mi)
	return mi


func _build_props() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 77
	# trees and bushes on the verges, tyre stacks at the apron's corners
	var spots := [[-18.6, -6.5, "scenery/tree_round", 0.85], [18.4, -5.8, "scenery/tree_bloom", 0.9],
		[-19.0, -12.0, "scenery/tree_bloom", 1.0], [19.4, -12.5, "scenery/tree_round", 1.0],
		[-21.5, -3.0, "scenery/tree_round", 0.9], [21.0, -2.0, "scenery/tree_bloom", 0.85],
		[-18.0, -9.5, "scenery/bush", 1.0], [18.2, -9.0, "scenery/bush", 1.0],
		[-19.2, 0.5, "scenery/tree_bloom", 0.75], [19.0, 1.2, "scenery/tree_round", 0.8],
		[-17.6, 5.5, "scenery/bush", 0.9], [17.8, 6.5, "scenery/bush", 0.9],
		[-11.0, 3.6, "scenery/tyre_stack", 0.9], [11.0, 3.6, "scenery/tyre_stack", 0.9],
		[-12.2, 2.6, "scenery/tyre_stack", 0.8], [12.2, 2.6, "scenery/tyre_stack", 0.8]]
	for s in spots:
		var logical: String = s[2]
		if not AssetCatalog.SPECS.has(logical):
			continue
		var tex := _resolver.get_texture(logical)
		if tex == null:
			continue
		var spec: Dictionary = AssetCatalog.SPECS[logical]
		var mi := _add_mesh(VoxelProps.mesh_for(logical, tex, spec.display_size), Vector3(s[0], 0, s[1]))
		mi.rotation.y = r.randf() * TAU
		mi.scale = Vector3.ONE * float(s[3])
		if logical.begins_with("scenery/tree"):
			mi.set_instance_shader_parameter("sway", 0.004)
	# floodlights at the ends of the grandstand
	for x in [-16.6, 16.6]:
		var lamp := _add_mesh(VoxelProps.lamp_mesh(true), Vector3(x, 0, -9.2))
		lamp.rotation.y = -0.5 if x < 0 else PI + 0.5  # heads towards the podium
		lamp.set_instance_shader_parameter("lamp_glow", 1.0)
	# flags: chequered at the sides, the winner's colour and race red behind
	var win_col := VrStyle.YELLOW
	for e in _entries:
		if int(e.place) == 1:
			win_col = _helmet_color(int(e.get("id", 0)))
	_add_flag(Vector3(-9.4, 0, -1.6), "checker", Color.WHITE, 5.6)
	_add_flag(Vector3(9.4, 0, -1.6), "checker", Color.WHITE, 5.6)
	_add_flag(Vector3(-2.9, 0, -3.4), "solid", win_col, 6.6)
	_add_flag(Vector3(2.9, 0, -3.4), "solid", VrStyle.RED, 6.6)


func _helmet_color(id: int) -> Color:
	if id >= 0 and id < HELMETS.size():
		return Color(HELMETS[id])
	return Color.WHITE


# ------------------------------------------------------------ racers

func _add_racer(e: Dictionary) -> void:
	var k: int = int(e.place) - 1
	var sx: float = STEP_X[k]
	var top := _step_top(k)
	var id := int(e.get("id", 0))
	# the car, parked on the step behind its driver
	var car := Node3D.new()
	car.position = Vector3(sx, top, CAR_Z)
	car.rotation.y = deg_to_rad(CAR_YAW_DEG[k])
	_world.add_child(car)
	var logical := String(e.get("logical", "cars/body_player"))
	var tex := _resolver.get_texture(logical)
	if tex != null:
		var body := _add_mesh(VoxelCars.body_mesh(tex, _layout, logical), Vector3.ZERO, car)
		var tint: Color = e.get("tint", Color.WHITE)
		body.set_instance_shader_parameter("tint", tint)
		body.set_instance_shader_parameter("head_glow", 0.45)
		body.set_instance_shader_parameter("tail_glow", 0.35)
		var at := VoxelCars.wheels_of(_layout, tex, logical)
		for ax in [at.x, at.y]:
			for az in [-at.z, at.z]:
				_add_mesh(VoxelCars.wheel_mesh(), Vector3(ax, VoxelCars.WHEEL_R * Vox.CAR_VOXEL_PX, az) * Vox.PX, car)
	# the trophy
	var trophy := _add_mesh(_trophy_mesh(k), Vector3(sx + TROPHY_DX[k], top, TROPHY_Z))
	trophy.scale = Vector3.ONE * TROPHY_SCALE[k]
	trophy.rotation.y = -0.4 if TROPHY_DX[k] > 0 else 0.4
	_glints.append([trophy, k])
	# the driver
	var f := _make_driver(id)
	f["place"] = k + 1
	f["car"] = car
	f["car_y"] = top
	f["trophy"] = trophy
	f["trophy_y"] = top
	var pos := Vector3(sx + DRIVER_DX[k], top, DRIVER_Z)
	f["base"] = pos
	f["base_yaw"] = atan2(-pos.x, 14.0) * 0.6
	f["start"] = WINNER_CUE if k == 0 else 0.15
	f["bounce"] = -10.0
	(f.root as Node3D).position = pos
	_world.add_child(f.root)
	_figs.append(f)


## A blocky voxel driver: legs, torso, arms and helmet are joints that the
## celebrations move. Returns the parts and the animation state.
func _make_driver(id: int) -> Dictionary:
	var helmet := _helmet_color(id)
	var suit := helmet.darkened(0.2)
	var root := Node3D.new()
	var core := Node3D.new()
	core.position.y = LEG_H
	root.add_child(core)
	var leg_a := _add_mesh(_leg_mesh(suit), Vector3(-HIP_X, 0, 0), core)
	var leg_b := _add_mesh(_leg_mesh(suit), Vector3(HIP_X, 0, 0), core)
	var hips := Node3D.new()
	core.add_child(hips)
	_add_mesh(_torso_mesh(suit), Vector3.ZERO, hips)
	var arm_a := _add_mesh(_arm_mesh(suit), Vector3(-SHOULDER_X, TORSO_H - 0.5 * FV, 0), hips)
	var arm_b := _add_mesh(_arm_mesh(suit), Vector3(SHOULDER_X, TORSO_H - 0.5 * FV, 0), hips)
	var head := _add_mesh(_helmet_mesh(helmet), Vector3(0, TORSO_H, 0), hips)
	return {"id": id, "root": root, "core": core, "hips": hips, "head": head,
		"arm_a": arm_a, "arm_b": arm_b, "leg_a": leg_a, "leg_b": leg_b}


static func _pose() -> Dictionary:
	return {"y": 0.0, "yaw": 0.0, "sq": 1.0, "flip": 0.0, "roll": 0.0, "lean": 0.0, "twist": 0.0, "tilt": 0.0,
		"hx": 0.0, "hy": 0.0, "hz": 0.0, "ax": 0.0, "ay": 0.0, "az": -0.08, "bx": 0.0, "by": 0.0, "bz": 0.08,
		"la": 0.0, "lb": 0.0,
		"spread": 0.0, "hide": false}


func _animate_figure(f: Dictionary, dt: float) -> void:
	var p := _pose()
	var lt: float = _time - float(f.start)
	if int(f.place) == 1:
		if lt < 0.0:
			_idle(f, p)
		else:
			_celebrate(f, p, lt, dt)
	else:
		_react(f, p, maxf(lt, 0.0), dt)
	var root: Node3D = f.root
	var base: Vector3 = f.base
	root.position = base + Vector3(0, p.y, 0)
	root.rotation = Vector3(0, float(f.base_yaw) + p.yaw, 0)
	var sq: float = p.sq
	var w := 1.0 / sqrt(sq)
	root.scale = Vector3(w, sq, w)
	root.visible = not p.hide
	(f.core as Node3D).rotation = Vector3(p.flip, 0, p.roll)
	(f.hips as Node3D).rotation = Vector3(p.lean, p.twist, p.tilt)
	(f.head as Node3D).rotation = Vector3(p.hx, p.hy, p.hz)
	(f.arm_a as Node3D).rotation = Vector3(p.ax, p.ay, p.az)
	(f.arm_b as Node3D).rotation = Vector3(p.bx, p.by, p.bz)
	(f.leg_a as Node3D).rotation = Vector3(p.la, 0, -p.spread)
	(f.leg_b as Node3D).rotation = Vector3(p.lb, 0, p.spread)
	# a thump makes everything on the step hop
	var b := _bump(_time - float(f.bounce), 0.0, 0.3)
	(f.car as Node3D).position.y = float(f.car_y) + 0.22 * b
	(f.trophy as Node3D).position.y = float(f.trophy_y) + 0.3 * b


## Before the reveal: the winner waits, bouncing on their toes, looking around.
func _idle(f: Dictionary, p: Dictionary) -> void:
	p.y = absf(sin(_time * 5.0)) * 0.05
	p.hy = 0.35 * sin(_time * 1.3 + float(f.id))
	p.az = -0.18
	p.bz = 0.18


# ------------------------------------------------------------ celebrations

static func _bump(u: float, a: float, b: float) -> float:
	if u <= a or u >= b:
		return 0.0
	return sin((u - a) / (b - a) * PI)


static func _ramp(u: float, a: float, b: float) -> float:
	return smoothstep(a, b, u)


## Whether a periodic event (at `th` within each `period`) happened this frame.
static func _crossed(lt: float, dt: float, period: float, th: float) -> bool:
	return floorf((lt - th) / period) > floorf((lt - dt - th) / period)


## A jump: crouch, flight of height h, landing. Returns the flight fraction
## 0..1, -1 while crouching, 2 after landing.
static func _jump(p: Dictionary, u: float, crouch: float, air: float, h: float) -> float:
	if u < crouch:
		p.sq = 1.0 - 0.2 * sin(u / crouch * PI * 0.5)
		return -1.0
	if u < crouch + air:
		var s := (u - crouch) / air
		p.y = 4.0 * h * s * (1.0 - s)
		p.sq = 1.0 + 0.12 * maxf(0.0, 1.0 - s * 2.5)
		return s
	var l := (u - crouch - air) / 0.2
	if l < 1.0:
		p.sq = 1.0 - 0.18 * sin(l * PI)
	return 2.0


## The winner's celebration, by personality (racer id).
func _celebrate(f: Dictionary, p: Dictionary, lt: float, dt: float) -> void:
	var at: Vector3 = (f.root as Node3D).position
	match int(f.id):
		1:  # Victor "The Professor": a calm, polite wave and a nod
			p.bz = 2.3 + 0.3 * sin(lt * 7.0)
			p.bx = -0.15
			p.ax = 0.5
			p.az = 0.1
			var nod := _bump(fposmod(lt, 2.2), 1.2, 1.9)
			p.hx = 0.35 * nod
			p.lean = 0.1 * nod
			p.yaw = 0.12 * sin(lt * 0.9)
		2:  # Rocco "Mad Dog": wild fist pumps, head-banging, stomps
			var r := lt * 5.5
			p.az = -(0.35 + 2.55 * pow(absf(sin(r)), 0.6))
			p.bz = 0.35 + 2.55 * pow(absf(sin(r + PI * 0.5)), 0.6)
			p.ax = -0.3
			p.bx = -0.3
			p.y = absf(sin(r)) * 0.16
			p.hx = -0.2 + 0.3 * sin(r * 2.0)
			p.lean = 0.14
			p.tilt = 0.12 * sin(r)
			var u := fposmod(lt, 2.4)
			if u > 1.5:
				var s := _jump(p, u - 1.5, 0.15, 0.5, 0.65)
				if s >= 0.0 and s <= 1.0:
					p.az = -2.85
					p.bz = 2.85
					p.spread = 0.3
			if _crossed(lt, dt, 2.4, 2.15):
				_dust(at, 8, 1.0)
				_shake = maxf(_shake, 0.1)
		3:  # Ellie "Sparrow": flaps her arms like wings and takes off a little
			var u := fposmod(lt, 2.6)
			var flap := sin(lt * 17.0)
			var lift := _ramp(u, 0.0, 0.45) * (1.0 - _ramp(u, 1.75, 2.15))
			if u < 2.15:
				p.az = -(1.05 + 0.8 * flap)
				p.bz = 1.05 + 0.8 * flap
			else:
				p.az = -1.5
				p.bz = 1.5
			p.y = lift * (0.6 + 0.08 * sin(lt * 17.0 + 1.3))
			p.lean = 0.22 * lift
			p.la = 0.4 * sin(lt * 9.0) * lift
			p.lb = -0.4 * sin(lt * 9.0) * lift
			p.hx = -0.15
			if lift > 0.5 and _crossed(lt, dt, 0.18, 0.0):
				_fx.spark(at + Vector3(_rng.randf_range(-0.5, 0.5), 1.2, 0.2),
					Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.5, 1.5), _rng.randf_range(-0.5, 1)),
					Color(1, 0.98, 0.92), 0.09, 1.0, 0.15, 0.08)
		4:  # Hank "The Wall": arms crossed, unmoved... then one big thump
			var cross := 1.0
			var u := fposmod(lt - 0.8, 3.4)
			if lt >= 0.8:
				var s := _jump(p, u, 0.4, 0.5, 0.7)
				if s == -1.0:
					cross = 1.0 - u / 0.4
				elif s >= 0.0 and s <= 1.0:
					cross = 0.0
				else:
					cross = _ramp(u, 1.25, 1.6)
				if s == 2.0:
					p.sq = 1.0 - 0.3 * _bump(u, 0.9, 1.15)  # a heavy landing
			p.ax = lerpf(-0.2, -1.3, cross)
			p.az = lerpf(-2.8, 0.78, cross)
			p.bx = lerpf(-0.2, -1.45, cross)
			p.bz = lerpf(2.8, -0.78, cross)
			p.hx = 0.05 * sin(lt * 1.4) + 0.25 * _bump(fposmod(lt - 0.8, 3.4), 0.9, 1.3)
			p.spread = 0.12 * cross
			if lt >= 0.8 and _crossed(lt - 0.8, dt, 3.4, 0.9):
				_dust(at, 18, 1.8)
				_shake = maxf(_shake, 0.45)
				f.bounce = _time
				for f2 in _figs:
					if f2 != f:
						f2.bounce = _time + 0.05
		5:  # Maya "Ghost": hardly moves... and is gone for a split second
			p.tilt = 0.03 * sin(lt * 1.1)
			p.hy = 0.2 * sin(lt * 0.7)
			var u := fposmod(lt - 1.1, 3.2)
			if lt >= 1.1 and u < 0.4:
				p.hide = true
			var wave := _bump(u, 0.45, 1.5) if lt >= 1.1 else 0.0
			p.bz = 0.08 + wave * (2.2 + 0.25 * sin(lt * 10.0))
			if _crossed(lt - 1.1, dt, 3.2, 0.0) or _crossed(lt - 1.1, dt, 3.2, 0.4):
				for i in 9:
					var o := Vector3(_rng.randf_range(-0.5, 0.5), _rng.randf_range(0.2, 1.7), _rng.randf_range(-0.4, 0.4))
					_fx.puff(at + o, o * 0.8 + Vector3(0, 0.5, 0), Color(0.78, 0.74, 0.9), _rng.randf_range(0.3, 0.5), 0.6, 0.7)
		6:  # Dante "Showboat": huge spinning jumps, lands in a pose, stars
			var u := fposmod(lt, 2.1)
			var s := _jump(p, u, 0.2, 0.85, 1.1)
			if s == -1.0:
				p.ax = 0.6
				p.bx = 0.6
			elif s <= 1.0:
				p.yaw = s * TAU * 2.0
				p.az = -1.55
				p.bz = 1.55
				p.hx = -0.2
			else:
				var hold := _ramp(u, 1.05, 1.25)
				p.bz = lerpf(1.55, 2.8, hold)
				p.az = -0.55
				p.ax = 0.35
				p.tilt = 0.18 * hold
				p.hx = -0.2 * hold
				p.hy = 0.25 * hold
				p.lb = -0.25 * hold
			if _crossed(lt, dt, 2.1, 1.05):
				_stars(at + Vector3(0, 1.0, 0), 7)
		7:  # Greta "Clockwork": a precise little bow, ticking like a clock
			var q := floorf(lt * 8.0) / 8.0
			var u := fposmod(q, 2.0)
			var bow := 0.0
			if u >= 0.5 and u < 0.875:
				bow = (u - 0.5) / 0.375
			elif u >= 0.875 and u < 1.375:
				bow = 1.0
			elif u >= 1.375 and u < 1.75:
				bow = 1.0 - (u - 1.375) / 0.375
			p.lean = 0.62 * bow
			p.hx = 0.12 * bow
			p.ax = -1.0
			p.az = 0.62
			p.bx = 0.45
			p.bz = 0.05
			p.hy = 0.0 if bow > 0.0 else 0.18 * signf(sin(q * PI * 2.0))
		8:  # Finn "Wildcard": something different every time
			_wildcard(f, p, lt, dt, at)
		9:  # Nina "The Hunter": "I'm watching you": hand to the visor, then points at the camera
			var to_cam := _cam.position - at
			var face := atan2(to_cam.x, to_cam.z) - float(f.base_yaw)
			var u := fposmod(lt, 2.0)
			var eyes := _ramp(u, 0.0, 0.2) * (1.0 - _ramp(u, 0.55, 0.7))
			var aim := _ramp(u, 0.55, 0.7) * (1.0 - _ramp(u, 1.75, 1.98))
			p.yaw = clampf(face, -0.8, 0.8) - 0.45 * aim
			p.hy = 0.4 * aim
			var elev := atan2(to_cam.y - 1.3, Vector2(to_cam.x, to_cam.z).length())
			var bang := _bump(u, 1.1, 1.35)
			p.bx = -2.5 * eyes + (-PI * 0.5 - elev - 0.6 * bang) * aim
			p.bz = 0.05 - 0.45 * eyes
			p.by = 0.3 * aim
			p.ax = 0.3
			p.az = -0.6
			p.hz = 0.12 * aim
			p.hx = -0.12 * eyes
			p.lean = 0.1 * aim + 0.06 * bang
			p.y = 0.03 * absf(sin(lt * 3.0))
		_:  # the player: pure joy, jumping with both arms up
			var u := fposmod(lt, 0.95)
			var s := _jump(p, u, 0.15, 0.55, 0.85)
			if s == -1.0:
				p.ax = 0.5
				p.bx = 0.5
			elif s <= 1.0:
				var up := _ramp(s, 0.0, 0.25)
				p.az = lerpf(-0.2, -2.6, up)
				p.bz = lerpf(0.2, 2.6, up)
				p.spread = 0.25 * up
				p.hx = -0.25 * up
			else:
				p.az = -2.4
				p.bz = 2.4
			if _crossed(lt, dt, 0.95, 0.42):
				_stars(at + Vector3(0, 2.2, 0), 3)


## Finn "Wildcard": a backflip, a noodle dance or a dizzy helicopter spin.
func _wildcard(_f: Dictionary, p: Dictionary, lt: float, dt: float, at: Vector3) -> void:
	match _finn_mode:
		0:  # backflip
			var u := fposmod(lt, 1.9)
			var s := _jump(p, u, 0.22, 0.8, 1.25)
			if s == -1.0:
				p.ax = 0.7
				p.bx = 0.7
			elif s <= 1.0:
				p.flip = -TAU * smoothstep(0.0, 1.0, s)
				p.az = -2.6
				p.bz = 2.6
				p.la = -0.6 * _bump(s, 0.0, 1.0)
				p.lb = p.la
			else:
				p.az = -2.2
				p.bz = 2.2
				p.lean = -0.12
			if _crossed(lt, dt, 1.9, 1.02):
				_stars(at + Vector3(0, 1.0, 0), 4)
		1:  # noodle dance
			p.az = -(1.3 + 1.0 * sin(lt * 7.3))
			p.bz = 1.3 + 1.0 * sin(lt * 6.1 + 1.0)
			p.ax = 0.6 * sin(lt * 5.2)
			p.bx = 0.6 * sin(lt * 4.4 + 2.0)
			p.tilt = 0.25 * sin(lt * 3.7)
			p.twist = 0.45 * sin(lt * 4.1)
			p.la = -0.6 * maxf(0.0, sin(lt * 6.0))
			p.lb = -0.6 * maxf(0.0, -sin(lt * 6.0))
			p.y = 0.08 * absf(sin(lt * 12.0))
			p.hz = 0.3 * sin(lt * 5.0)
		_:  # helicopter: spins up with arms out, then a dizzy wobble
			var u := fposmod(lt, 3.0)
			var spin := TAU * 3.0 * smoothstep(0.0, 2.2, u)
			p.yaw = spin
			var dizzy := _ramp(u, 2.1, 2.3) * (1.0 - _ramp(u, 2.85, 3.0))
			p.az = lerpf(-1.6, -0.5, dizzy)
			p.bz = lerpf(1.6, 0.5, dizzy)
			p.y = 0.12 * absf(sin(lt * 8.0)) * (1.0 - dizzy)
			p.roll = 0.22 * sin(lt * 9.0) * dizzy
			p.hz = 0.35 * sin(lt * 7.0 + 1.0) * dizzy
			if _crossed(lt, dt, 3.0, 2.2):
				_stars(at + Vector3(0, 2.3, 0), 4)


## Second and third: they clap (each in their own way) and turn to the winner.
func _react(f: Dictionary, p: Dictionary, lt: float, _dt: float) -> void:
	var look := _ramp(_time, WINNER_CUE, WINNER_CUE + 0.45) * (0.55 if int(f.place) == 2 else -0.55)
	p.hy = look
	p.yaw = look * 0.3
	var rate := 3.0
	var amp := 1.0
	match int(f.id):
		4:  # Hank: arms stay crossed; an approving nod
			p.ax = -1.3
			p.az = 0.78
			p.bx = -1.45
			p.bz = -0.78
			p.hx = 0.22 * _bump(fposmod(lt, 1.8), 0.3, 0.8)
			return
		5:
			rate = 1.2
			amp = 0.45
		2:
			rate = 5.0
			p.y = absf(sin(lt * 10.0)) * 0.1
		7:
			lt = floorf(lt * 12.0) / 12.0
		0:
			p.y = 0.25 * _bump(fposmod(lt, 1.3), 0.0, 0.4)
		9:
			rate = 2.0
		6:
			p.tilt = 0.08 * sin(lt * 4.0)
	var c := 0.5 + 0.5 * sin(lt * TAU * rate)
	p.ax = -1.15
	p.bx = -1.15
	p.az = 0.2 + 0.46 * c * amp + 0.46 * (1.0 - amp)
	p.bz = -p.az
	p.y = float(p.y) + 0.03 * c


# ------------------------------------------------------------ effects

## A burst of glowing sparkles (n: a few; each is a little fountain).
func _stars(at: Vector3, n: int) -> void:
	var cols := [Color(1.0, 0.86, 0.2), Color(1.0, 0.98, 0.85), VrStyle.PINK, VrStyle.SKY]
	for i in n * 5:
		var a := _rng.randf() * TAU
		_fx.spark(at + Vector3(0, 0.3, 0), Vector3(cos(a) * 2.2, _rng.randf_range(2.0, 4.5), sin(a) * 2.2 + 0.5),
			cols[i % cols.size()], _rng.randf_range(0.08, 0.13), _rng.randf_range(0.5, 0.9), 1.1, 0.25)


func _dust(at: Vector3, n: int, strength: float) -> void:
	for i in n:
		var a := TAU * i / n + _rng.randf_range(-0.2, 0.2)
		var dir := Vector3(cos(a), 0, sin(a))
		_fx.puff(at + dir * 0.35 + Vector3(0, 0.25, 0), dir * _rng.randf_range(1.5, 2.6) * strength + Vector3(0, 0.9 * strength, 0),
			Color(0.86, 0.8, 0.72), _rng.randf_range(0.28, 0.45) * minf(strength, 1.4), _rng.randf_range(0.6, 0.9), 0.65)
	# and a ring of sparks off the step
	for i in int(n * 0.8):
		var a := _rng.randf() * TAU
		_fx.spark(at + Vector3(0, 0.1, 0), Vector3(cos(a) * 4.0, _rng.randf_range(2.0, 4.5), sin(a) * 4.0) * strength * 0.7,
			Color(1.0, 0.9, 0.6), 0.08, _rng.randf_range(0.3, 0.55), 1.0, 1.0)


func _update_effects(dt: float) -> void:
	# the reveal: confetti cannons and a jingle
	if not _cheered and _time >= WINNER_CUE + 0.1:
		_cheered = true
		for side in [-1.0, 1.0]:
			var at := Vector3(8.6 * side, 0.4, 2.6)
			for i in 110:
				_confetti(at, Vector3(-side * _rng.randf_range(1.5, 5.0), _rng.randf_range(10.0, 15.0), _rng.randf_range(-2.0, 1.5)))
			for i in 6:
				_fx.puff(at + Vector3(0, 0.3, 0), Vector3(-side * 1.2, 2.0, 0) * _rng.randf_range(0.5, 1.2),
					Color(0.95, 0.92, 0.88), _rng.randf_range(0.3, 0.5), 0.8, 0.6)
		_play("ui/achievement")
	# confetti drifting down all the time (more after the reveal)
	var rate := 14.0 if _time < WINNER_CUE else 46.0
	if _time > DURATION - 0.8:
		rate = 0.0
	_c_rain += dt * rate
	while _c_rain >= 1.0:
		_c_rain -= 1.0
		var p := Vector3(_rng.randf_range(-12.0, 12.0), _rng.randf_range(6.5, 9.0), _rng.randf_range(-4.0, 7.0))
		_confetti(p, Vector3(_rng.randf_range(-0.4, 0.4), -0.5, _rng.randf_range(-0.4, 0.4)))
	# fireworks in the dusk sky behind the stand
	for fw in _fireworks:
		if not fw[1] and _time >= float(fw[0]):
			fw[1] = true
			_firework(Vector3(_rng.randf_range(-15.0, 15.0), _rng.randf_range(9.5, 13.0), _rng.randf_range(-32.0, -26.0)))
	# trophies glint now and then
	for g in _glints:
		var k: int = g[1]
		if _crossed(_time, dt, 1.6 + k * 0.4, 0.5 + k * 0.5):
			var t: Node3D = g[0]
			_fx.spark(t.position + Vector3(0.18, 0.92, 0.25) * t.scale.y, Vector3.ZERO, Color(1, 0.97, 0.85), 0.11, 0.3, 1.2, 0.0)
	# camera shake decays
	_shake *= exp(-dt * 5.0)


func _firework(at: Vector3) -> void:
	var a: Color = CONFETTI[_rng.randi_range(0, CONFETTI.size() - 1)]
	var b: Color = CONFETTI[_rng.randi_range(0, CONFETTI.size() - 1)]
	for i in 64:
		var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()
		var col := a if i % 2 == 0 else b
		_fx.spark(at, dir * _rng.randf_range(5.0, 7.0), col.lightened(0.1), 0.26, _rng.randf_range(1.0, 1.5), 1.2, 0.08)


func _play(logical: String) -> void:
	if _sfx == null or _resolver == null:
		return
	var s := _resolver.get_audio(logical)
	if s != null:
		_sfx.stream = s
		_sfx.play()


# ------------------------------------------------------------ confetti

func _build_confetti() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(0.17, 0.012, 0.11)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.45
	mat.metallic_specular = 0.6
	mat.emission_enabled = true
	mat.emission = Color(0.12, 0.1, 0.1)
	box.material = mat
	_conf = MultiMesh.new()
	_conf.transform_format = MultiMesh.TRANSFORM_3D
	_conf.use_colors = true
	_conf.mesh = box
	_conf.instance_count = CONF_MAX
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = _conf
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0
	_world.add_child(mi)
	_c_pos.resize(CONF_MAX)
	_c_vel.resize(CONF_MAX)
	_c_rot.resize(CONF_MAX)
	_c_spin.resize(CONF_MAX)
	_c_life.resize(CONF_MAX)
	_c_life.fill(0.0)
	_c_next = 0
	var hidden := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -100, 0))
	for i in CONF_MAX:
		_conf.set_instance_transform(i, hidden)
		_conf.set_instance_color(i, Color.WHITE)


func _confetti(pos: Vector3, vel: Vector3) -> void:
	if _conf == null:
		return
	var i := _c_next
	_c_next = (_c_next + 1) % CONF_MAX
	_c_pos[i] = pos
	_c_vel[i] = vel
	_c_rot[i] = Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU)
	_c_spin[i] = Vector3(_rng.randf_range(-9, 9), _rng.randf_range(-5, 5), _rng.randf_range(-9, 9))
	_c_life[i] = _rng.randf_range(4.5, 6.5)
	_conf.set_instance_color(i, CONFETTI[_rng.randi_range(0, CONFETTI.size() - 1)])


func _step_confetti(dt: float) -> void:
	if _conf == null or dt <= 0.0:
		return
	var drag := exp(-dt * 1.6)
	for i in CONF_MAX:
		var life := _c_life[i]
		if life <= 0.0:
			continue
		life -= dt
		_c_life[i] = life
		if life <= 0.0:
			_conf.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -100, 0)))
			continue
		var p := _c_pos[i]
		var v := _c_vel[i]
		var floor_y := _ground_at(p.x, p.z) + 0.02
		if p.y > floor_y:
			v.y -= 9.0 * dt
			v *= drag
			v.y = maxf(v.y, -1.7)
			p += v * dt
			# paper flutter
			p.x += sin(_time * 3.1 + i * 1.7) * 0.55 * dt
			p.z += cos(_time * 2.3 + i * 0.9) * 0.4 * dt
			_c_rot[i] += _c_spin[i] * dt
			if p.y <= floor_y:
				p.y = floor_y
				v = Vector3.ZERO
				_c_rot[i] = Vector3(0.0, _c_rot[i].y, 0.0)
		_c_pos[i] = p
		_c_vel[i] = v
		var s := minf(1.0, life * 3.0)
		_conf.set_instance_transform(i, Transform3D(Basis.from_euler(_c_rot[i]).scaled(Vector3.ONE * s), p))


# ------------------------------------------------------------ flags

func _add_flag(at: Vector3, pattern: String, col: Color, height: float) -> void:
	var pole := _add_mesh(_pole_mesh(height), at)
	var strips: Array = []
	var n := 10
	for k in n:
		var mi := _add_mesh(_flag_strip_mesh(pattern, col, k), at + Vector3(0.1 + k * 0.14, height - 0.05, 0))
		strips.append(mi)
	_flags.append({"pole": pole, "strips": strips, "at": at, "h": height, "ph": _rng.randf() * TAU})


func _update_flags() -> void:
	for fl in _flags:
		var strips: Array = fl.strips
		var at: Vector3 = fl.at
		var ph: float = fl.ph
		for k in strips.size():
			var mi: MeshInstance3D = strips[k]
			var w := float(k + 1) / strips.size()
			var wave := sin(_time * 6.5 - k * 0.75 + ph)
			mi.position = at + Vector3(0.1 + k * 0.135, float(fl.h) - 0.05 - 0.05 * w + 0.04 * wave * w, 0.22 * wave * w)
			mi.rotation.y = -0.45 * cos(_time * 6.5 - k * 0.75 + ph) * w


# ------------------------------------------------------------ camera

## The choreography: low on third, sweep across to second, rise to the winner
## (a heroic low angle), then pull back and orbit the whole podium.
func _build_camera_keys() -> void:
	var t: Array = []
	for k in 3:
		t.append(Vector3(STEP_X[k] + DRIVER_DX[k], _step_top(k) + 0.85, DRIVER_Z))
	# [time, target, yaw, distance, height above the target, fov]
	_cam_keys = [
		[0.0, t[2] + Vector3(0.9, -0.1, 0.0), 0.62, 6.0, -0.45, 40.0],
		[1.15, t[2] + Vector3(0.1, 0.0, 0.0), 0.42, 5.4, -0.35, 38.0],
		[1.7, Vector3(0.0, 2.4, 0.5), 0.0, 10.0, 0.4, 38.0],
		[2.25, t[1] + Vector3(-0.1, 0.0, 0.0), -0.42, 5.4, -0.3, 38.0],
		[3.2, t[0] + Vector3(0.3, 0.55, -0.2), -0.1, 6.6, -1.1, 40.0],
		[4.3, t[0] + Vector3(0.5, 0.35, -0.4), 0.08, 8.2, -0.5, 40.0],
		[5.9, Vector3(0.0, 2.3, -1.0), -0.06, 17.0, 2.5, 38.0],
		[7.4, Vector3(0.0, 2.3, -1.0), -0.22, 18.2, 2.8, 38.0],
	]


func _key_values(k: int) -> PackedFloat32Array:
	var key: Array = _cam_keys[clampi(k, 0, _cam_keys.size() - 1)]
	var tg: Vector3 = key[1]
	return PackedFloat32Array([tg.x, tg.y, tg.z, key[2], key[3], key[4], key[5]])


func _update_camera(_dt: float) -> void:
	if _cam == null or _cam_keys.is_empty():
		return
	var n := _cam_keys.size()
	var i := 0
	while i < n - 2 and _time >= float(_cam_keys[i + 1][0]):
		i += 1
	var t0: float = _cam_keys[i][0]
	var t1: float = _cam_keys[i + 1][0]
	var tp: float = _cam_keys[maxi(i - 1, 0)][0] if i > 0 else t0 - (t1 - t0)
	var tn: float = _cam_keys[i + 2][0] if i + 2 < n else t1 + (t1 - t0)
	var w := clampf((_time - t0) / (t1 - t0), 0.0, 1.0)
	var a := _key_values(i)
	var b := _key_values(i + 1)
	var pre := _key_values(i - 1) if i > 0 else a
	var post := _key_values(i + 2) if i + 2 < n else b
	var v := PackedFloat32Array()
	v.resize(7)
	for c in 7:
		v[c] = cubic_interpolate_in_time(a[c], b[c], pre[c], post[c], w, t1 - t0, tp - t0, tn - t0)
	var target := Vector3(v[0], v[1], v[2])
	var yaw := v[3]
	var dist := v[4]
	var pos := target + Vector3(sin(yaw) * dist, v[5], cos(yaw) * dist)
	# a little hand-held drift, and the shake of a thump
	pos += Vector3(sin(_time * 0.9) * 0.08, sin(_time * 1.3) * 0.05, 0.0)
	pos += Vector3(sin(_time * 61.0), sin(_time * 53.0), 0.0) * _shake * 0.25
	_cam.fov = v[6]
	# (the world sits at the origin: local is global, and this works before
	# the layer enters the tree)
	_cam.transform = Transform3D(Basis.looking_at(target - pos, Vector3.UP), pos)


# ------------------------------------------------------------ crowd

func _build_crowd() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 1955
	var spots: Array = []
	for k in 4:
		var z := -8.5 - k * 1.5 - 0.8
		var y := (k + 1) * 1.0
		var x := -14.6 + r.randf_range(0.0, 0.4)
		while x < 14.6:
			if r.randf() > 0.1:
				spots.append(Vector3(x + r.randf_range(-0.1, 0.1), y, z + r.randf_range(-0.12, 0.12)))
			x += r.randf_range(0.72, 0.95)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _crowd_mesh()
	mm.instance_count = spots.size()
	var shirts := [VrStyle.RED, VrStyle.YELLOW, VrStyle.TEAL, VrStyle.SKY, VrStyle.PINK, VrStyle.GREEN, VrStyle.PAPER,
		Color("ff8c2e"), Color("a37ef0")]
	for i in spots.size():
		var p: Vector3 = spots[i]
		var s := r.randf_range(0.9, 1.08)
		var b := Basis(Vector3.UP, r.randf_range(-0.35, 0.35)).scaled(Vector3.ONE * s)
		mm.set_instance_transform(i, Transform3D(b, p))
		var c: Color = shirts[r.randi_range(0, shirts.size() - 1)]
		c.a = fposmod(p.x * 0.03 + r.randf() * 0.1, 1.0)
		mm.set_instance_custom_data(i, c)
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = CROWD_SHADER
	mat.shader = sh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 4.0
	_world.add_child(mi)


# ------------------------------------------------------------ voxel models

static func _mesh(g: VoxelGrid, pivot: Vector3, jitter: float = 0.05) -> ArrayMesh:
	return VoxelMesher.build_mesh(g, VoxelCars.material(), pivot, jitter)


## The pit apron: asphalt, a red carpet to the podium, a chequered line,
## kerbs and grass verges (voxels of 0.5).
static func _floor_mesh() -> ArrayMesh:
	if _meshes.has("floor"):
		return _meshes["floor"]
	var vs := 0.5
	var nx := 88
	var nz := 52
	var g := VoxelGrid.new(Vector3i(nx, 2, nz), vs, Vector3.ZERO)
	for z in nz:
		for x in nx:
			var wx := -22.0 + (x + 0.5) * vs
			var wz := -12.0 + (z + 0.5) * vs
			var h := Vox.hash3(x, 3, z)
			var c := Color("3d3f5c").lightened(0.06 * h)
			if absf(wx) > 16.5:
				c = VrStyle.GREEN.darkened(0.25 + 0.14 * h)
			elif absf(wx) > 15.75:
				c = VrStyle.RED if posmod(int(floor(wz)), 2) == 0 else VrStyle.PAPER
			elif wz < -8.5:
				c = Color("2c2d45").lightened(0.04 * h)
			elif absf(wx) < 2.25 and wz > 2.5:
				c = VrStyle.RED_DARK.lightened(0.06 * h)
				if absf(wx) > 1.75:
					c = VrStyle.YELLOW.darkened(0.15)
			elif wz > 9.0 and wz < 10.0:
				c = VrStyle.PAPER.darkened(0.08) if posmod(x + z, 2) == 0 else VrStyle.INK
			elif absf(absf(wx) - 8.0) < 0.25 and wz > -6.0 and int(floor(wz)) % 2 == 0:
				c = VrStyle.PAPER.darkened(0.2)  # painted bay lines
			g.set_v(x, 0, z, Vox.SOLID, c.darkened(0.25))
			g.set_v(x, 1, z, Vox.SOLID, c)
	var mesh := _mesh(g, Vector3(22.0, 1.0, 12.0), 0.04)
	_meshes["floor"] = mesh
	return mesh


## A podium step (place index k): the place colour with a lit rim around a
## dark top (cars and drivers stand out on it), a dark plinth and trim.
static func _step_mesh(k: int) -> ArrayMesh:
	var key := "step%d" % k
	if _meshes.has(key):
		return _meshes[key]
	var h: int = STEP_CELLS[k]
	var g := VoxelGrid.new(Vector3i(STEP_NX, h, STEP_NZ), STEP_VS, Vector3.ZERO)
	var base: Color = PLACE_COLORS[k]
	for y in h:
		for z in STEP_NZ:
			for x in STEP_NX:
				var c := base
				if y == 0:
					c = base.darkened(0.5)
				elif y == h - 1:
					var rim := x < 2 or x >= STEP_NX - 2 or z < 2 or z >= STEP_NZ - 2
					c = base.lightened(0.22) if rim else Color("343b6e")
				elif y == h - 2:
					c = base.darkened(0.18)
				elif x == 0 or x == STEP_NX - 1:
					if z == 0 or z == STEP_NZ - 1:
						c = base.darkened(0.12)
				g.set_v(x, y, z, Vox.SOLID, c)
	var mesh := _mesh(g, Vector3(STEP_NX * 0.5, 0.0, STEP_NZ * 0.5) * STEP_VS, 0.05)
	_meshes[key] = mesh
	return mesh


## A raised voxel numeral (cream with an ink outline), back face at z = 0.
static func _numeral_mesh(k: int) -> ArrayMesh:
	var key := "num%d" % k
	if _meshes.has(key):
		return _meshes[key]
	var s: int = NUM_SCALE[k]
	var glyph: Array = DIGITS[k + 1]
	var w := 5 * s + 2
	var h := 7 * s + 2
	var g := VoxelGrid.new(Vector3i(w, h, 2), NUM_VS, Vector3.ZERO)
	var on := func(x: int, y: int) -> bool:
		if x < 1 or y < 1 or x >= w - 1 or y >= h - 1:
			return false
		var gx := (x - 1) / s
		var gy := 6 - (y - 1) / s
		return String(glyph[gy])[gx] == "#"
	for y in h:
		for x in w:
			if on.call(x, y):
				g.set_v(x, y, 0, Vox.SOLID, VrStyle.PAPER)
				g.set_v(x, y, 1, Vox.SOLID, VrStyle.PAPER)
			else:
				var near := false
				for dy in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						if on.call(x + dx, y + dy):
							near = true
				if near:
					g.set_v(x, y, 0, Vox.SOLID, VrStyle.INK)
	var mesh := _mesh(g, Vector3(w * 0.5, 0.0, 0.0) * NUM_VS, 0.03)
	_meshes[key] = mesh
	return mesh


## A trophy cup (place index k): plinth, stem, bowl with handles (glossy).
static func _trophy_mesh(k: int) -> ArrayMesh:
	var key := "trophy%d" % k
	if _meshes.has(key):
		return _meshes[key]
	var vs := 0.07
	var g := VoxelGrid.new(Vector3i(13, 15, 13), vs, Vector3.ZERO)
	var c: Color = TROPHY_COLORS[k]
	var wood := Color("3a2730")
	g.box(Vector3i(3, 0, 3), Vector3i(9, 1, 9), Vox.SOLID, wood)
	g.box(Vector3i(4, 2, 4), Vector3i(8, 2, 8), Vox.METAL, c.darkened(0.15))
	g.box(Vector3i(5, 3, 5), Vector3i(7, 3, 7), Vox.METAL, c)
	g.box(Vector3i(6, 4, 6), Vector3i(6, 5, 6), Vox.METAL, c)
	g.box(Vector3i(5, 6, 5), Vector3i(7, 6, 7), Vox.METAL, c.lightened(0.1))
	var radii := [1.6, 2.4, 3.0, 3.4, 3.7, 3.9, 4.1, 4.2]
	for i in radii.size():
		var y := 7 + i
		var r: float = radii[i]
		for z in 13:
			for x in 13:
				var d := Vector2(x - 6, z - 6).length()
				if d > r + 0.3:
					continue
				if i >= 3 and d < r - 1.1:
					if i == radii.size() - 1:
						continue  # hollow mouth
					continue
				var col := c.lightened(0.25) if i == radii.size() - 1 else c
				g.set_v(x, y, z, Vox.METAL, col)
	# the handles
	for side in [0, 12]:
		var inner := 1 if side == 0 else 11
		for y in [9, 10, 11, 12]:
			g.set_v(side, y, 6, Vox.METAL, c)
		g.set_v(inner, 13, 6, Vox.METAL, c)
		g.set_v(inner, 8, 6, Vox.METAL, c)
	var mesh := _mesh(g, Vector3(6.5, 0.0, 6.5) * vs, 0.03)
	_meshes[key] = mesh
	return mesh


static func _leg_mesh(suit: Color) -> ArrayMesh:
	var key := "leg" + suit.to_html()
	if _meshes.has(key):
		return _meshes[key]
	var g := VoxelGrid.new(Vector3i(3, 8, 4), FV, Vector3.ZERO)
	var boot := Color("24243a")
	g.box(Vector3i(0, 0, 0), Vector3i(2, 1, 3), Vox.SOLID, boot)
	g.box(Vector3i(0, 2, 0), Vector3i(2, 7, 2), Vox.SOLID, suit.darkened(0.12))
	var mesh := _mesh(g, Vector3(1.5, 8.0, 1.5) * FV, 0.04)
	_meshes[key] = mesh
	return mesh


static func _torso_mesh(suit: Color) -> ArrayMesh:
	var key := "torso" + suit.to_html()
	if _meshes.has(key):
		return _meshes[key]
	var g := VoxelGrid.new(Vector3i(8, 8, 5), FV, Vector3.ZERO)
	var stripe := VrStyle.RED if suit.get_luminance() > 0.62 else VrStyle.PAPER
	for y in 8:
		for z in 5:
			for x in 8:
				if y == 7 and (x == 0 or x == 7):
					continue  # rounded shoulders
				var c := suit
				if y == 0:
					c = Color("24243a")  # belt
				elif y == 4 or y == 5:
					c = stripe if (z == 4 or z == 0 or x == 0 or x == 7) else suit
				if y == 7 and x >= 3 and x <= 4 and z == 4:
					c = Color("24243a")  # collar
				g.set_v(x, y, z, Vox.SOLID, c)
	var mesh := _mesh(g, Vector3(4.0, 0.0, 2.5) * FV, 0.04)
	_meshes[key] = mesh
	return mesh


static func _arm_mesh(suit: Color) -> ArrayMesh:
	var key := "arm" + suit.to_html()
	if _meshes.has(key):
		return _meshes[key]
	var g := VoxelGrid.new(Vector3i(3, 8, 3), FV, Vector3.ZERO)
	g.box(Vector3i(0, 0, 0), Vector3i(2, 1, 2), Vox.SOLID, Color("f2efe6"))  # gloves
	g.box(Vector3i(0, 2, 0), Vector3i(2, 7, 2), Vox.SOLID, suit)
	var mesh := _mesh(g, Vector3(1.5, 8.0, 1.5) * FV, 0.04)
	_meshes[key] = mesh
	return mesh


## The helmet (the head): rounded, a dark glossy visor at the front (+Z) and
## a stripe over the top.
static func _helmet_mesh(col: Color) -> ArrayMesh:
	var key := "helmet" + col.to_html()
	if _meshes.has(key):
		return _meshes[key]
	var n := 8
	var g := VoxelGrid.new(Vector3i(n, n, n), FV, Vector3.ZERO)
	var stripe := VrStyle.INK if col.get_luminance() > 0.62 else VrStyle.PAPER
	for y in n:
		for z in n:
			for x in n:
				var ex := 1 if (x == 0 or x == n - 1) else 0
				var ey := 1 if y == n - 1 else 0
				var ez := 1 if (z == 0 or z == n - 1) else 0
				if ex + ey + ez >= 2:
					continue  # rounded edges
				var c := col
				var m := Vox.SOLID
				if z == n - 1 and y >= 3 and y <= 5 and x >= 1 and x <= n - 2:
					c = Color("151b2b")
					m = Vox.GLASS
				elif (x == 3 or x == 4) and (y == n - 1 or (z == 0 and y >= 2) or (y >= 6 and z <= 2)):
					c = stripe
				elif y == 0:
					c = col.darkened(0.25)
				g.set_v(x, y, z, m, c)
	var mesh := _mesh(g, Vector3(4.0, 0.0, 4.0) * FV, 0.03)
	_meshes[key] = mesh
	return mesh


## A spectator (shirt and arms in marker colours: see CROWD_SHADER).
static func _crowd_mesh() -> ArrayMesh:
	if _meshes.has("crowd"):
		return _meshes["crowd"]
	var vs := 0.1
	var g := VoxelGrid.new(Vector3i(8, 13, 4), vs, Vector3.ZERO)
	var pants := Color("2b2f45")
	var skin := Color("f2c9a0")
	var hair := Color("4a3020")
	var shirt := Color(1, 0, 1)
	var arm_down := Color(1, 0, 0.5)
	var arm_up := Color(0.5, 0, 1)
	g.box(Vector3i(2, 0, 1), Vector3i(5, 3, 2), Vox.SOLID, pants)
	g.box(Vector3i(1, 4, 0), Vector3i(6, 7, 3), Vox.SOLID, shirt)
	g.box(Vector3i(0, 4, 1), Vector3i(0, 7, 2), Vox.SOLID, arm_down)
	g.box(Vector3i(7, 4, 1), Vector3i(7, 7, 2), Vox.SOLID, arm_down)
	g.box(Vector3i(0, 8, 1), Vector3i(0, 11, 2), Vox.SOLID, arm_up)
	g.box(Vector3i(7, 8, 1), Vector3i(7, 11, 2), Vox.SOLID, arm_up)
	g.box(Vector3i(2, 8, 0), Vector3i(5, 10, 3), Vox.SOLID, skin)
	g.box(Vector3i(2, 11, 0), Vector3i(5, 11, 3), Vox.SOLID, hair)
	g.box(Vector3i(2, 8, 0), Vector3i(5, 10, 0), Vox.SOLID, hair)
	var mesh := VoxelMesher.build_mesh(g, null, Vector3(4.0, 0.0, 2.0) * vs, 0.0)
	_meshes["crowd"] = mesh
	return mesh


## The grandstand behind the podium (P005: the circuits' grandstand look -
## concrete, muted blue seats, dark steel, a neutral roof - so the red and
## white stay with the kerbs and the celebration): four tiers of seats split
## by two stair aisles, a concrete front wall, hospitality windows at the
## back, a corrugated roof with steel ribs and a dark fascia carrying two
## muted banners, on steel columns (voxels of 0.5; the crowd stands on the
## tiers at y = 1, 2, 3, 4).
static func _stand_mesh() -> ArrayMesh:
	if _meshes.has("stand"):
		return _meshes["stand"]
	var vs := 0.5
	var nx := 66
	var nz := 18
	var ny := 15
	var g := VoxelGrid.new(Vector3i(nx, ny, nz), vs, Vector3.ZERO)
	var concrete := Color(0.6, 0.59, 0.56)
	var walk := Color(0.7, 0.69, 0.65)
	var stair := Color(0.76, 0.75, 0.71)
	var seat := Color(0.33, 0.43, 0.55)
	var steel := Color(0.2, 0.22, 0.25)
	var roof := Color(0.58, 0.6, 0.62)
	var fascia := Color(0.22, 0.25, 0.29)
	for z in nz:
		var wz := -17.5 + (z + 0.5) * vs
		var d := -8.5 - wz  # depth behind the front wall
		for x in nx:
			var wx := -16.5 + (x + 0.5) * vs
			var h := Vox.hash3(x, 5, z)
			var side := absf(wx) > 15.75
			var aisle := absf(absf(wx) - 5.25) < 0.3
			var top := 0
			var k := int(d / 1.5)
			if d < 6.0:
				top = (k + 1) * 2
			else:
				top = 12
			if side:
				top = 12
			for y in top:
				var c := concrete.darkened(0.04 * h)
				if side:
					c = concrete.darkened(0.08 + 0.04 * h)
					if y == top - 1:
						c = walk
				elif d < 0.5 and y < 2:
					c = concrete.darkened(0.12 if x % 6 == 0 else 0.03)  # the front wall, its joints
				elif y == top - 1 and d < 6.0:
					var j := d - k * 1.5  # 0 .. 1.5 within the tier
					if aisle:
						c = stair.darkened(0.05 * (k % 2))
					elif j < 0.5:
						c = walk  # the walkway in front of the row
					else:
						var tone := seat.lightened(0.06) if k % 2 == 0 else seat.darkened(0.04)
						c = tone if posmod(x, 3) != 2 else tone.darkened(0.22)
				elif d >= 6.0:
					c = concrete.darkened(0.02 * h)
					if y >= 9 and y <= 10 and posmod(x, 4) != 0 and d < 6.5:
						g.set_v(x, y, z, Vox.GLASS, Color(0.16, 0.2, 0.26))  # hospitality windows
						continue
				g.set_v(x, y, z, Vox.SOLID, c)
			# the roof over the upper tiers: corrugated sheeting, a dark fascia
			# with two muted banners at the front
			if d >= 2.5:
				var rc := roof.darkened(0.06) if posmod(x, 2) == 0 else roof
				if d < 3.0:
					rc = fascia
				g.set_v(x, 13, z, Vox.SOLID, rc)
				var low := rc.darkened(0.08)
				if d < 3.0 and absf(absf(wx) - 10.25) < 4.0:
					low = Color(0.7, 0.56, 0.3) if wx < 0.0 else Color(0.24, 0.48, 0.48)
				g.set_v(x, 12, z, Vox.SOLID, low)
				# steel ribs on top over the columns
				if (absf(absf(wx) - 5.25) < 0.3 or absf(absf(wx) - 15.25) < 0.3) and d >= 3.0:
					g.set_v(x, 14, z, Vox.METAL, steel)
			# columns holding the roof
			if d >= 2.5 and d < 3.0 and (absf(absf(wx) - 5.25) < 0.3 or absf(absf(wx) - 15.25) < 0.3):
				for y in range(top, 12):
					g.set_v(x, y, z, Vox.METAL, steel)
	var mesh := _mesh(g, Vector3(16.5, 0.0, 17.5), 0.04)
	_meshes["stand"] = mesh
	return mesh


## Strings of pennants hanging between the stand's columns.
static func _bunting_mesh() -> ArrayMesh:
	if _meshes.has("bunting"):
		return _meshes["bunting"]
	var vs := 0.1
	var nx := 312
	var ny := 16
	var g := VoxelGrid.new(Vector3i(nx, ny, 1), vs, Vector3.ZERO)
	var cols := [VrStyle.RED, VrStyle.YELLOW, VrStyle.TEAL, VrStyle.PAPER, VrStyle.PINK, VrStyle.SKY]
	var spans := [-15.6, -5.2, 5.2, 15.6]
	var count := 0
	for s in 3:
		var x0: float = spans[s]
		var x1: float = spans[s + 1]
		var cx0 := int((x0 + 15.6) / vs)
		var cx1 := int((x1 + 15.6) / vs)
		for cx in range(cx0, cx1):
			var t := float(cx - cx0) / (cx1 - cx0)
			var sag := 4.0 * t * (1.0 - t) * 0.8
			var cy := ny - 1 - int(round(sag / vs))
			g.set_v(cx, cy, 0, Vox.SOLID, Color("2a2a36"))
			# a pennant every 8 voxels
			if (cx - cx0) % 8 == 2 and cx < cx1 - 4:
				var c: Color = cols[count % cols.size()]
				count += 1
				for row in 5:
					var half := 2 - row / 2
					for dx in range(-half, half + 1):
						g.set_v(cx + 2 + dx, cy - 1 - row, 0, Vox.SOLID, c)
	var mesh := _mesh(g, Vector3(15.6, -4.4, 0.05), 0.04)
	_meshes["bunting"] = mesh
	return mesh


static func _pole_mesh(height: float) -> ArrayMesh:
	var key := "pole%.1f" % height
	if _meshes.has(key):
		return _meshes[key]
	var vs := 0.1
	var n := int(height / vs)
	var g := VoxelGrid.new(Vector3i(3, n + 2, 3), vs, Vector3.ZERO)
	g.box(Vector3i(0, 0, 0), Vector3i(2, 1, 2), Vox.METAL, Color(0.3, 0.3, 0.34))
	g.box(Vector3i(1, 2, 1), Vector3i(1, n, 1), Vox.METAL, Color(0.78, 0.78, 0.82))
	g.box(Vector3i(0, n, 0), Vector3i(2, n + 1, 2), Vox.METAL, VrStyle.YELLOW)
	var mesh := _mesh(g, Vector3(1.5, 0.0, 1.5) * vs, 0.02)
	_meshes[key] = mesh
	return mesh


## One vertical strip (column k) of a flag, hanging from its top.
static func _flag_strip_mesh(pattern: String, col: Color, k: int) -> ArrayMesh:
	var key := "flag%s%s%d" % [pattern, col.to_html(), k]
	if _meshes.has(key):
		return _meshes[key]
	var vs := 0.14
	var rows := 7
	var g := VoxelGrid.new(Vector3i(1, rows, 1), vs, Vector3.ZERO)
	for y in rows:
		var c := col
		if pattern == "checker":
			c = VrStyle.PAPER if (k + y) % 2 == 0 else VrStyle.INK
		elif y == 3:
			c = VrStyle.PAPER if col.get_luminance() < 0.7 else VrStyle.RED
		g.set_v(0, y, 0, Vox.SOLID, c)
	var mesh := _mesh(g, Vector3(0.5, rows, 0.5) * vs, 0.06)
	_meshes[key] = mesh
	return mesh
