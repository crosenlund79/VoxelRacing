extends SceneTree
## Lightweight end-to-end smoke test of the real game flow with simulated
## key presses: title -> quick race -> the loading race -> start with Fire ->
## drive (hold Fire, steer) -> L night -> V camera -> Esc race menu -> leave
## -> title. Saves screenshots and prints CHECK lines.
##
## xvfb-run godot --path . -s tools/smoke_flow.gd -- --out=/tmp/smoke

var _game: Node
var _f := 0
var _out := "user://smoke"
var _start_pos := Vector2.ZERO
var _ai_start := Vector2.ZERO
var _checks: Array[String] = []
var _step := 0
var _mark := 0
var _loading_seen := false
var _loading_shots := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	_game = load("res://src/main/game.tscn").instantiate()
	_game.greetings_enabled = false
	root.add_child.call_deferred(_game)


func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


func _tap(code: Key) -> void:
	_key(code, true)
	_key.call_deferred(code, false)


func _shot(name: String) -> void:
	var path := "%s_%s.png" % [_out, name]
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)


func _check(name: String, ok: bool, detail: String = "") -> void:
	var line := "CHECK %s: %s %s" % ["PASS" if ok else "FAIL", name, detail]
	_checks.append(line)
	print(line)


func _next(after: int = 0) -> void:
	_step += 1
	_mark = _f + after


func _physics_process(_delta: float) -> bool:
	_f += 1
	if _f < _mark:
		return false
	var race: Node = _game.race if _game != null else null
	match _step:
		0:
			if _f >= 90:
				_shot("01_title")
				_check("title screen up", _game.title != null and _game.race == null)
				_game.start_race(0)
				_next(30)
		1:  # the loading race shows and animates while the world builds
			if _game.loading.visible:
				_loading_seen = true
				if _loading_shots < 2 and _f % 45 == 0:
					_loading_shots += 1
					_shot("02_loading_%d" % _loading_shots)
			if race != null and race.voxel != null and race.voxel.ready_3d and not _game.loading.visible and not _game._starting:
				_check("loading race shown", _loading_seen)
				_check("voxel world built", true, "(%d ms)" % race.voxel.build_msec)
				_step = 11
				_mark = _f + 40
			elif _f > 6000:
				_check("voxel world built", false, "(timeout)")
				return true
		11:
			_shot("03_grid")
			_start_pos = race.cars[0].global_position
			_ai_start = race.cars[1].global_position
			_tap(KEY_SPACE)
			_step = 2
			_mark = _f + 20
		2:
			_key(KEY_SPACE, true)  # hold Fire: accelerate
			_next(120)
		3:
			_key(KEY_RIGHT, true)
			_next(15)
		4:
			_key(KEY_RIGHT, false)
			_next(25)
		5:
			_shot("04_driving")
			var p0: Car = race.cars[0]
			_check("player car moves under control", p0.global_position.distance_to(_start_pos) > 150.0,
				"(moved %.0f px)" % p0.global_position.distance_to(_start_pos))
			_check("AI opponents race", race.cars[1].global_position.distance_to(_ai_start) > 150.0)
			_tap(KEY_L)
			_next(40)
		6:
			_shot("05_night")
			_check("night toggled with L", race.lighting.enabled)
			_tap(KEY_V)
			_next(40)
		7:
			_shot("06_camera_high")
			_check("camera cycled with V", VoxelStage.view_index == 1)
			_tap(KEY_V)
			_tap(KEY_L)
			_key(KEY_SPACE, false)
			_next(20)
		8:
			_tap(KEY_ESCAPE)
			_next(30)
		9:
			_shot("07_race_menu")
			_check("race menu with Esc", race.menu_open)
			race.leave_race()
			_next(120)
		10:
			_shot("08_back_to_title")
			_check("back to title", _game.race == null and _game.title != null)
			var fails := 0
			for c in _checks:
				if c.contains("FAIL"):
					fails += 1
			print("SMOKE DONE: %d checks, %d failed" % [_checks.size(), fails])
			return true
	return false
