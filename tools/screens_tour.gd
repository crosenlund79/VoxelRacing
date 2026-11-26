extends SceneTree
## Developer harness: visits the main screens and saves a screenshot of each.
## xvfb-run godot --path . -s tools/screens_tour.gd -- --out=/tmp/tour

var _game: Node
var _f := 0
var _out := "user://tour"
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


func _wait(n: int) -> void:
	_mark = _f + n
	_step += 1


func _physics_process(_d: float) -> bool:
	_f += 1
	if _f < _mark:
		return false
	var t = _game.title
	match _step:
		0:
			if _f > 60:
				_shot("00_device")
				PlayerControls.set_device(PlayerControls.DEVICE_KEYBOARD)
				t._show_main()
				_wait(40)
		1:
			_shot("01_main")
			t._open_setup("quick")
			_wait(90)
		2:
			_shot("02_setup")
			t._open_setup("championship")
			_wait(90)
		3:
			_shot("02b_setup_champ")
			t._open_setup("battle")
			_wait(90)
		4:
			_shot("02c_setup_battle")
			t._open_settings()
			_wait(30)
		5:
			_shot("03_settings")
			t._open_controls()
			_wait(30)
		6:
			_shot("04_controls")
			t._open_achievements()
			_wait(30)
		7:
			_shot("05_achievements")
			t._show_main()
			_game.title.night = true
			_game.start_race(2)  # spectate: results come by themselves
			_wait(60)
		8:
			var race = _game.race
			if race != null and race.voxel != null and race.voxel.ready_3d and not _game._starting:
				race.set_sim_speed(8)
				_wait(200)
		9:
			_shot("06_spectate_hud")
			_game.race.open_race_menu()
			_wait(20)
		10:
			_shot("07_pause")
			_game.race.resume_race()
			_wait(10)
		11:
			var race = _game.race
			if race.session.state == RaceSession.State.FINISHED:
				_wait(30)
			elif _f > 20000:
				return true
		12:
			_shot("08_results")
			return true
	return false
