extends SceneTree
## Developer harness (Prototype 005): the title's pages only (no race), one
## screenshot each: device choice, main menu, the setups, settings, controls,
## achievements, with a tooltip shown on a focused icon.
## xvfb-run godot --path . -s tools/menu_tour.gd -- --out=/tmp/menu

var _game: Node
var _f := 0
var _out := "user://menu"
var _step := 0
var _mark := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	_game = load("res://src/main/game.tscn").instantiate()
	_game.greetings_enabled = false
	root.add_child.call_deferred(_game)


func _shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png("%s_%s.png" % [_out, name])
	print("saved ", name)


func _key(code: Key) -> void:
	for p in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = code
		e.keycode = code
		e.pressed = p
		Input.parse_input_event(e)


func _physics_process(_d: float) -> bool:
	_f += 1
	if _f < _mark:
		return false
	var t = _game.title
	_step += 1
	_mark = _f + 50
	match _step:
		2:
			_shot("00_device")
			PlayerControls.set_device(PlayerControls.DEVICE_KEYBOARD)
			t._show_main()
		3:
			_key(KEY_DOWN)  # (keyboard focus: the tooltip system follows it)
		4:
			_shot("01_main")
			t._open_setup("quick")
			t._icon_row.get_child(0).grab_focus()
			_mark = _f + 110
		5:
			_shot("02_setup_quick")
			t._cycle_time()
			t._cycle_layout(1)
			_mark = _f + 110
		6:
			_shot("03_setup_night")
			t._cycle_time()
			t._open_setup("championship")
			_mark = _f + 110
		7:
			_shot("04_setup_champ")
			t._open_setup("battle")
			_mark = _f + 110
		8:
			_shot("05_setup_battle")
			t._open_setup("multi")
			_mark = _f + 110
		9:
			_shot("06_setup_multi")
			t._open_settings()
		10:
			_shot("07_settings")
			t._open_controls()
		11:
			_shot("08_controls")
			t._open_achievements()
		12:
			_shot("09_achievements")
			t._open_device_picker(true)
		13:
			_shot("10_device_from_settings")
			return true
	return false
