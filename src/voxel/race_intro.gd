class_name RaceIntro
extends Node3D
## VoxelRacing (P004): a short, skippable cinematic before the start, shot
## in the race's own voxel world with the real grid: a crane shot over the
## grid with the circuit's title, a low dolly along the cars naming each
## driver, a hero shot of your car (the pole sitter when spectating) and a
## look up at the start lights. About seven seconds; any of Confirm / Fire /
## Back skips it. The race waits on the grid as before (nothing is started
## or changed by the intro).

signal finished

const LENGTH := 7.0
const LETTERBOX := 56

var stage: VoxelStage
var main: Node2D
var cam: Camera3D
var playing := false
var _t := 0.0
var _grace := 0.0
var _grid: Array = []  # [id, pos3, fwd3]
var _line := Vector3.ZERO
var _t3 := Vector3.FORWARD
var _r3 := Vector3.RIGHT
var _hero := 0
var _saved_env := {}
var _ui: CanvasLayer
var _title: Label
var _sub: Label
var _lower: Label
var _lower_sub: Label
var _hint: Label


func setup(p_stage: VoxelStage) -> void:
	stage = p_stage
	main = stage.main
	name = "RaceIntro"
	cam = Camera3D.new()
	cam.name = "IntroCamera"
	cam.near = 0.1
	cam.far = 260.0
	add_child(cam)
	_build_ui()


func play() -> void:
	if playing:
		return
	_collect()
	if _grid.is_empty():
		return
	playing = true
	_t = 0.0
	_grace = 0.35
	_shoot()  # placed before its first frame
	cam.make_current()
	_env(true)
	_ui.visible = true
	if main.get("hud") != null and main.hud != null:
		main.hud.visible = false
	var track_name := "THE CIRCUIT"
	if main.track.get("layout") != null and main.track.layout != null and String(main.track.layout.display_name) != "":
		track_name = String(main.track.layout.display_name)
	_title.text = track_name.to_upper()
	var theme_name: String = main.track_theme.display_name if main.get("track_theme") != null and main.track_theme != null else ""
	var night: bool = main.lighting != null and main.lighting.enabled
	_sub.text = "%s  -  %s  -  %d LAPS  -  %d CARS" % [theme_name.to_upper(), "NIGHT" if night else "DAY",
		int(main.session.lap_count()), _grid.size()]
	if stage.life != null:
		stage.life.pulse(Vector2(_line.x, _line.z) / Vox.PX, 1400.0, 0.7)
	await finished


func skip() -> void:
	if playing:
		_end()


func _collect() -> void:
	_grid.clear()
	var order: Array = main.get("grid_order") if main.get("grid_order") != null else []
	for id in order:
		var c: Car = main.cars[id]
		if not c.visible:
			continue
		var root: Node3D = stage.cars3d[id].root
		_grid.append([id, root.global_position, Vector3(cos(c.global_rotation), 0.0, sin(c.global_rotation))])
	if _grid.is_empty():
		return
	var start: Vector2 = main.track.checkpoint_transform(0).origin
	var g0: Vector3 = _grid[0][1]
	_t3 = _grid[0][2]
	_r3 = Vector3(-_t3.z, 0.0, _t3.x)
	_line = Vox.to3(start, 0.0)
	_line.y = g0.y
	var session: RaceSession = main.session
	_hero = int(_grid[0][0])
	if not session.spectator:
		_hero = session.human_ids[0] if not session.human_ids.is_empty() else _hero


func _process(delta: float) -> void:
	if not playing:
		return
	_t += delta
	_grace -= delta
	if _grace <= 0.0 and (Input.is_action_just_pressed(PlayerControls.CONFIRM) or Input.is_action_just_pressed(PlayerControls.FIRE)
			or Input.is_action_just_pressed(PlayerControls.BACK) or Input.is_action_just_pressed("ui_accept")):
		get_viewport().set_input_as_handled()
		_end()
		return
	if _t >= LENGTH:
		_end()
		return
	_shoot()
	_overlay()


func _end() -> void:
	playing = false
	_ui.visible = false
	_env(false)
	if stage.camera != null:
		stage.camera.make_current()
	if main.get("hud") != null and main.hud != null:
		main.hud.visible = true
	finished.emit()


func _grid_pos(k: int) -> Vector3:
	return _grid[clampi(k, 0, _grid.size() - 1)][1]


func _shoot() -> void:
	var back := _grid_pos(_grid.size() - 1)
	var front := _grid_pos(0)
	var mid := (back + front) * 0.5
	var pos := Vector3.ZERO
	var look := Vector3.ZERO
	var fov := 55.0
	if _t < 2.2:  # crane: high behind the grid, sweeping forward and down
		var k := smoothstep(0.0, 2.2, _t)
		pos = (back - _t3 * 8.0 + Vector3.UP * 15.0).lerp(mid + _r3 * 7.0 + Vector3.UP * 6.0, k)
		look = mid.lerp(front + _t3 * 3.0, k)
		fov = 50.0
	elif _t < 4.8:  # dolly along the grid, low beside the cars (clear of both columns)
		var k := smoothstep(2.2, 4.8, _t)
		var centre := Vector3.ZERO
		var lo := INF
		var hi := -INF
		for g in _grid:
			centre += g[1]
			var a := (g[1] as Vector3).dot(_t3)
			lo = minf(lo, a)
			hi = maxf(hi, a)
		centre /= _grid.size()
		var c0 := centre + _t3 * (lo - centre.dot(_t3))
		var c1 := centre + _t3 * (hi - centre.dot(_t3))
		var side := _r3 * 9.5
		pos = (c0 - _t3 * 3.0).lerp(c1 + _t3 * 2.0, k) + side + Vector3.UP * 1.5
		look = pos - side + _t3 * 2.5 + Vector3.UP * 0.2
		fov = 46.0
	elif _t < 6.0:  # the hero: low front three-quarter, slowly turning
		var k := (_t - 4.8) / 1.2
		var hp: Vector3 = stage.cars3d[_hero].root.global_position
		var a := 0.55 + k * 0.45
		pos = hp + (_t3 * cos(a) + _r3 * sin(a)) * 4.2 + Vector3.UP * 0.9
		look = hp + Vector3.UP * 0.45
		fov = 45.0
	else:  # the start lights from the front of the grid
		var k := smoothstep(6.0, 7.0, _t)
		pos = front - _t3 * 1.5 + _r3 * 1.6 + Vector3.UP * (0.6 + k * 0.3)
		look = _line + Vector3.UP * 3.0
		fov = 58.0
	var g := stage.vtrack.height_px_at(Vector2(pos.x, pos.z) / Vox.PX) * Vox.PX if stage.vtrack != null else 0.0
	pos.y = maxf(pos.y, g + 0.4)
	cam.position = pos
	if pos.distance_to(look) > 0.01:
		cam.look_at(look, Vector3.UP)
	cam.fov = fov


func _overlay() -> void:
	var title_a := clampf(2.4 - _t, 0.0, 1.0) * clampf(_t * 3.0, 0.0, 1.0)
	_title.modulate.a = title_a
	_sub.modulate.a = title_a
	var lower := ""
	var lower_sub := ""
	if _t >= 2.2 and _t < 4.8:
		# the car the camera is passing
		var best := 0
		var bd := INF
		for k in _grid.size():
			var d := cam.global_position.distance_to(_grid[k][1])
			if d < bd:
				bd = d
				best = k
		var id: int = _grid[best][0]
		lower = "P%d   %s" % [best + 1, _name(id)]
		lower_sub = _nick(id)
	elif _t >= 4.8 and _t < 6.0:
		var place := 0
		for k in _grid.size():
			if int(_grid[k][0]) == _hero:
				place = k + 1
		lower = "P%d   %s" % [place, _name(_hero)]
		lower_sub = "ON THE GRID" if _hero == 0 else _nick(_hero)
	_lower.text = lower
	_lower_sub.text = lower_sub
	var la := 1.0 if lower != "" else 0.0
	_lower.modulate.a = la
	_lower_sub.modulate.a = la


func _name(id: int) -> String:
	var session: RaceSession = main.session
	if session.human_ids.has(id) and not session.spectator:
		return "YOU"
	return RivalRoster.short_name(id).to_upper() if id > 0 else "YOU"


func _nick(id: int) -> String:
	if id <= 0:
		return "YOUR OWN CAR"
	return '"%s"' % RivalRoster.nickname(id).to_upper()


func _env(on: bool) -> void:
	var e: Environment = stage.world_env.environment
	if on:
		_saved_env = {"bg": e.background_color, "fog": e.fog_enabled}
		var night: bool = main.lighting != null and main.lighting.enabled
		var haze := Color(0.04, 0.05, 0.09) if night else Color(0.62, 0.74, 0.86)
		e.background_color = haze
		e.fog_enabled = true
		e.fog_mode = Environment.FOG_MODE_DEPTH
		e.fog_light_color = haze
		e.fog_density = 1.0
		e.fog_depth_begin = 55.0
		e.fog_depth_end = 150.0
	elif not _saved_env.is_empty():
		e.background_color = _saved_env.bg
		e.fog_enabled = _saved_env.fog


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 58
	_ui.visible = false
	add_child(_ui)
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = VrStyle.INK
		bar.size = Vector2(1280, LETTERBOX)
		bar.position = Vector2(0, 0 if top else 720 - LETTERBOX)
		_ui.add_child(bar)
	_title = _label(48, VrStyle.YELLOW, "bold")
	_title.position = Vector2(0, 250)
	_title.size = Vector2(1280, 60)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub = _label(16, VrStyle.PAPER, "bold")
	_sub.position = Vector2(0, 318)
	_sub.size = Vector2(1280, 24)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lower = _label(32, VrStyle.PAPER, "bold")
	_lower.position = Vector2(56, 720 - LETTERBOX - 92)
	_lower_sub = _label(16, VrStyle.YELLOW, "bold")
	_lower_sub.position = Vector2(60, 720 - LETTERBOX - 50)
	_hint = _label(16, VrStyle.PAPER_DIM, "regular")
	_hint.position = Vector2(0, 720 - LETTERBOX + 18)
	_hint.size = Vector2(1240, 24)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.text = PlayerControls.fmt("{confirm} / {fire}: skip")
	for l in [_title, _sub, _lower, _lower_sub, _hint]:
		_ui.add_child(l)


func _label(size: int, color: Color, kind: String) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", VrStyle.font(kind))
	l.add_theme_font_size_override("font_size", VrStyle.px(size))
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", VrStyle.INK)
	l.add_theme_constant_override("outline_size", 8)
	return l
