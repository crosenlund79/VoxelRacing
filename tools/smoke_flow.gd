extends SceneTree
## Lightweight end-to-end smoke test of the real game flow with simulated
## key presses (the whole input path): title -> quick race -> start with
## Fire -> drive (hold Fire, steer) -> L night -> V camera -> G 2D / voxel ->
## Esc race menu -> leave -> title. Saves screenshots and prints CHECK lines.
##
## xvfb-run godot --path . -s tools/smoke_flow.gd -- --out=/tmp/smoke [--layout=kestrel_ridge]

var _game: Node
var _f := 0
var _out := "user://smoke"
var _start_pos := Vector2.ZERO
var _ai_start := Vector2.ZERO
var _checks: Array[String] = []


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


func _race() -> Node:
	return _game.race if _game != null else null


func _physics_process(_delta: float) -> bool:
	_f += 1
	var race := _race()
	match _f:
		90:
			_shot("01_title")
			_check("title screen up", _game.title != null and _game.race == null)
			_game.start_race(0)  # GO RACING! > quick race, Fire to accelerate
		420:
			_check("race scene running", race != null)
			_check("voxel world built", race != null and race.voxel != null and race.voxel.ready_3d,
				"(%d ms)" % race.voxel.vtrack.build_msec if race != null and race.voxel != null else "")
			_shot("02_grid")
			_start_pos = race.cars[0].global_position
			_ai_start = race.cars[1].global_position
			_tap(KEY_SPACE)  # Fire: start the race
		440:
			_key(KEY_SPACE, true)  # hold Fire: accelerate
		560:
			_key(KEY_RIGHT, true)
		575:
			_key(KEY_RIGHT, false)
		600:
			_shot("03_driving")
			var p0: Car = race.cars[0]
			_check("player car moves under control", p0.global_position.distance_to(_start_pos) > 150.0,
				"(moved %.0f px, speed %.0f px/s)" % [p0.global_position.distance_to(_start_pos), p0.model.velocity.length()])
			_check("AI opponents race", race.cars[1].global_position.distance_to(_ai_start) > 150.0,
				"(Victor moved %.0f px)" % race.cars[1].global_position.distance_to(_ai_start))
			_tap(KEY_L)
		640:
			_shot("04_night")
			_check("night toggled with L", race.lighting.enabled)
			_tap(KEY_V)
		680:
			_shot("05_camera_high")
			_check("camera cycled with V", VoxelStage.view_index == 1)
			_tap(KEY_G)
		720:
			_shot("06_original_2d")
			_check("2D view with G", not VoxelStage.voxel_mode and not race.voxel.visible)
			_tap(KEY_G)
			_tap(KEY_L)
		760:
			_check("voxel view back with G", VoxelStage.voxel_mode and race.voxel.visible)
			_key(KEY_SPACE, false)
			_tap(KEY_ESCAPE)
		790:
			_shot("07_race_menu")
			_check("race menu with Esc", race.menu_open)
			race.leave_race()
		900:
			_shot("08_back_to_title")
			_check("back to title", _game.race == null and _game.title != null)
			var fails := 0
			for c in _checks:
				if c.contains("FAIL"):
					fails += 1
			print("SMOKE DONE: %d checks, %d failed" % [_checks.size(), fails])
			return true
	return false
