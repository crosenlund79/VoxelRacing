class_name PhotoMode
extends Node3D
## VoxelRacing (P004): photography mode. P (pad: L3) freezes the race (the
## whole scene tree pauses, so nothing moves on) and hands you a free orbit
## camera around a point of interest; the HUD hides. Leave with Esc / P and
## everything carries on exactly where it was. Single-screen races, spectating
## and replays only (never a network race).
##   mouse drag / right stick: orbit     WASD / arrows / left stick: move
##   Q / E (LB / RB): lower / raise      wheel, + / - (triggers): zoom
##   Tab (Y): next car                   H (Select): hide these hints
##   Enter / F12 (A): save a screenshot  Esc / P (B): back to the race

const SHOT_DIR := "user://screenshots"

var stage: VoxelStage
var main: Node2D
var cam: Camera3D
var active := false
var _focus := Vector3.ZERO
var _yaw := 0.6
var _pitch := 0.45
var _dist := 14.0
var _height := 0.0
var _car := -1
var _prev_camera: Camera3D
var _hidden: Array = []
var _ui: CanvasLayer
var _hints: Label
var _flash: ColorRect
var _toast: Label
var _toast_left := 0.0
var _show_hints := true
var _dragging := false
var _saving := false


func setup(p_stage: VoxelStage) -> void:
	stage = p_stage
	main = stage.main
	name = "PhotoMode"
	process_mode = Node.PROCESS_MODE_ALWAYS
	cam = Camera3D.new()
	cam.name = "PhotoCamera"
	cam.near = 0.1
	cam.far = 300.0
	cam.fov = 50.0
	add_child(cam)
	_build_ui()


func allowed() -> bool:
	if not stage.ready_3d or main.get("session") == null:
		return false
	if main.get("net") != null or (main.has_method("is_two_player") and main.is_two_player()) or main.get("player_views") != null:
		return false
	if main.get("menu_open") == true:
		return false
	if stage.intro != null and stage.intro.playing:
		return false
	return true


func _process__perf(delta: float) -> void:
	if not active:
		if Input.is_action_just_pressed(PlayerControls.PHOTO) and allowed() and not get_tree().paused:
			_enter()
		return
	_toast_left -= delta
	_toast.visible = _toast_left > 0.0
	if _saving:
		return
	if Input.is_action_just_pressed(PlayerControls.PHOTO) or Input.is_action_just_pressed("ui_cancel"):
		_exit()
		return
	if Input.is_key_pressed(KEY_F12) and not _f12_down or Input.is_action_just_pressed("ui_accept"):
		_save()
	_f12_down = Input.is_key_pressed(KEY_F12)
	if Input.is_action_just_pressed("ui_focus_next") or Input.is_action_just_pressed(PlayerControls.HISTORY_VIEW):
		_next_car()
	if Input.is_key_pressed(KEY_H) and not _h_down or Input.is_action_just_pressed(PlayerControls.TOGGLE_PANEL):
		_show_hints = not _show_hints
		_hints.visible = _show_hints
	_h_down = Input.is_key_pressed(KEY_H)
	_move(delta)
	_place()


var _f12_down := false
var _h_down := false


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_dist = maxf(2.0, _dist * 0.9)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_dist = minf(90.0, _dist * 1.1)
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.006
		_pitch = clampf(_pitch + mm.relative.y * 0.005, -0.1, 1.45)


func _move(delta: float) -> void:
	var dt := minf(delta, 0.05)
	var mv := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		mv.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		mv.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		mv.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		mv.x += 1.0
	var pads := Input.get_connected_joypads()
	var orbit := Vector2.ZERO
	var zoom := 0.0
	var lift := 0.0
	if not pads.is_empty():
		var p: int = pads[0]
		var ls := Vector2(Input.get_joy_axis(p, JOY_AXIS_LEFT_X), Input.get_joy_axis(p, JOY_AXIS_LEFT_Y))
		if ls.length() > 0.2:
			mv += ls
		var rs := Vector2(Input.get_joy_axis(p, JOY_AXIS_RIGHT_X), Input.get_joy_axis(p, JOY_AXIS_RIGHT_Y))
		if rs.length() > 0.2:
			orbit = rs
		zoom = Input.get_joy_axis(p, JOY_AXIS_TRIGGER_RIGHT) - Input.get_joy_axis(p, JOY_AXIS_TRIGGER_LEFT)
		if Input.is_joy_button_pressed(p, JOY_BUTTON_RIGHT_SHOULDER):
			lift += 1.0
		if Input.is_joy_button_pressed(p, JOY_BUTTON_LEFT_SHOULDER):
			lift -= 1.0
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_PAGEUP):
		lift += 1.0
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_PAGEDOWN):
		lift -= 1.0
	if Input.is_key_pressed(KEY_EQUAL) or Input.is_key_pressed(KEY_KP_ADD):
		zoom += 1.0
	if Input.is_key_pressed(KEY_MINUS) or Input.is_key_pressed(KEY_KP_SUBTRACT):
		zoom -= 1.0
	if mv.length() > 0.0:
		_car = -1  # moving frees the camera from the car
		var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
		var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
		_focus += (right * mv.x - fwd * mv.y) * dt * (6.0 + _dist * 0.8)
	_yaw -= orbit.x * dt * 2.2
	_pitch = clampf(_pitch + orbit.y * dt * 1.6, -0.1, 1.45)
	_dist = clampf(_dist * exp(-zoom * dt * 1.5), 2.0, 90.0)
	_height = clampf(_height + lift * dt * 4.0, -2.0, 30.0)


func _place() -> void:
	if _car >= 0 and _car < stage.cars3d.size():
		_focus = (stage.cars3d[_car].root as Node3D).global_position
	var target := _focus + Vector3.UP * (0.6 + _height)
	var off := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _dist
	var pos := target + off
	var g := stage.vtrack.height_px_at(Vector2(pos.x, pos.z) / Vox.PX) * Vox.PX if stage.vtrack != null else 0.0
	pos.y = maxf(pos.y, g + 0.3)
	cam.position = pos
	cam.look_at(target, Vector3.UP)


func _enter() -> void:
	active = true
	_prev_camera = get_viewport().get_camera_3d()
	# start from what is on screen: its focus, from a pleasant angle
	if stage.replay != null and stage.replay.playing:
		_focus = Vox.to3(stage.replay.focus_2d(), 0.0)
	else:
		var cam2: Camera2D = main.camera
		_focus = Vox.to3(cam2.get_screen_center_position(), 0.0)
	_car = _nearest_car(_focus)
	_dist = 14.0
	_height = 0.0
	_pitch = 0.5
	_yaw = 0.5
	get_tree().paused = true
	_hide_ui(true)
	_ui.visible = true
	_hints.visible = _show_hints
	_place()
	cam.make_current()


func _exit() -> void:
	active = false
	_ui.visible = false
	_hide_ui(false)
	if _prev_camera != null and is_instance_valid(_prev_camera):
		_prev_camera.make_current()
	get_tree().set_deferred("paused", false)  # after this frame: the key that left does nothing else


func _nearest_car(p: Vector3) -> int:
	var best := -1
	var bd := INF
	for i in stage.cars3d.size():
		var root: Node3D = stage.cars3d[i].root
		if not root.is_visible_in_tree() and not (stage.replay != null and stage.replay.playing):
			continue
		var d := root.global_position.distance_to(p)
		if d < bd:
			bd = d
			best = i
	if stage.replay != null and stage.replay.playing:
		return -1  # (the replay's own cars stand elsewhere: keep the free focus)
	return best


func _next_car() -> void:
	var n := stage.cars3d.size()
	for k in n:
		var i := (_car + 1 + k) % n if _car >= 0 else k
		if (stage.cars3d[i].root as Node3D).is_visible_in_tree():
			_car = i
			return


func _hide_ui(on: bool) -> void:
	if on:
		_hidden.clear()
		for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
			var layer := n as CanvasLayer
			if layer != _ui and layer.visible:
				_hidden.append(layer)
				layer.visible = false
	else:
		for layer in _hidden:
			if is_instance_valid(layer):
				(layer as CanvasLayer).visible = true
		_hidden.clear()


func _save() -> void:
	_saving = true
	_ui.visible = false
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path := "%s/VoxelRacing_%s.png" % [SHOT_DIR, stamp]
	var err := img.save_png(path)
	_ui.visible = true
	_flash.modulate.a = 0.9
	create_tween().tween_property(_flash, "modulate:a", 0.0, 0.35)
	_toast.text = ("Saved  %s" % ProjectSettings.globalize_path(path)) if err == OK else "Could not save the picture"
	_toast_left = 3.0
	_saving = false


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 90
	_ui.visible = false
	_ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_ui)
	_flash = ColorRect.new()
	_flash.color = Color.WHITE
	_flash.size = Vector2(1280, 720)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.modulate.a = 0.0
	_ui.add_child(_flash)
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", VrStyle.chip(Color(VrStyle.INK, 0.86)))
	bar.position = Vector2(16, 16)
	_ui.add_child(bar)
	_hints = Label.new()
	_hints.add_theme_font_override("font", VrStyle.font("regular"))
	_hints.add_theme_font_size_override("font_size", VrStyle.px(16))
	_hints.add_theme_color_override("font_color", VrStyle.PAPER)
	# (only the chosen input device's controls: Prototype 005)
	if PlayerControls.uses_gamepad():
		_hints.text = "Photo mode\nR stick: orbit    L stick: move    LB / RB: height    Triggers: zoom\nY: next car    Select: hide    A: save picture    B: back"
	else:
		_hints.text = "Photo mode\nMouse drag: orbit    WASD: move    Q / E: height    Wheel: zoom\nTab: next car    H: hide    Enter: save picture    P: back"
	bar.add_child(_hints)
	_toast = Label.new()
	_toast.add_theme_font_override("font", VrStyle.font("bold"))
	_toast.add_theme_font_size_override("font_size", VrStyle.px(16))
	_toast.add_theme_color_override("font_color", VrStyle.YELLOW)
	_toast.add_theme_color_override("font_outline_color", VrStyle.INK)
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.position = Vector2(16, 680)
	_toast.visible = false
	_ui.add_child(_toast)


## DIAGNOSTIC probe (Performance Investigation 001)
func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process__perf(delta)
	PerfProbe.add(&"pres.photo_mode", __t)
