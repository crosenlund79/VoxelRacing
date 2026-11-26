extends SceneTree
## Developer harness (P005): the title screen's menu diorama only (main menu
## and the race modes menu), a few shots as the camera drifts - to judge the
## grandstand on the island.
## xvfb-run godot --path . -s tools/diorama_check.gd -- --out=/tmp/dc

var _game: Node
var _f := 0
var _out := "user://dc"


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


func _physics_process(_d: float) -> bool:
	_f += 1
	var t = _game.title if _game != null else null
	if t == null:
		return _f > 600
	match _f:
		60:
			PlayerControls.set_device(PlayerControls.DEVICE_KEYBOARD)
			t._show_main()
		120:
			_shot("main_a")
		300:
			_shot("main_b")
		320:
			t._open_modes()
		360:
			_shot("modes_a")
		600:
			_shot("modes_b")
	return _f > 620
