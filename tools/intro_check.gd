extends SceneTree
## Developer check of the race intro (P004): from the title, start a quick
## race; screenshots during the cinematic, on the grid afterwards (start
## lights, idling cars), at the start (green) and a little later.
## xvfb-run godot --path . -s tools/intro_check.gd -- --out=/tmp/ic [--night=1]

var _game: Node
var _f := 0
var _out := "user://ic"
var _step := 0
var _mark := 0
var _shots := 0
var _seen := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	_game = load("res://src/main/game.tscn").instantiate()
	root.add_child.call_deferred(_game)


func _shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png("%s_%s.png" % [_out, name])
	print("saved ", name)


func _process(_d: float) -> bool:
	_f += 1
	var race = _game.get("race")
	match _step:
		0:
			if _f > 90:
				if OS.get_cmdline_user_args().has("--night=1"):
					_game.title.night = true
				_game.start_race(0)
				_step = 1
		1:
			if race != null and race.voxel != null and race.voxel.intro != null and race.voxel.intro.playing:
				if not _seen:
					_seen = true
					_mark = _f
					print("CHECK PASS: intro playing")
				if (_f - _mark) % 14 == 0 and _shots < 10:
					_shots += 1
					_shot("intro_%02d_%.1fs" % [_shots, race.voxel.intro._t])
			elif _seen and race != null and not race.voxel.intro.playing:
				print("CHECK PASS: intro ended, back to the race camera: ", race.voxel.camera.current)
				_step = 2
				_mark = _f
			elif _f > 20000:
				print("CHECK FAIL: no intro")
				return true
		2:
			if _f == _mark + 60:
				_shot("grid_lights")
				print("CHECK grid state: ", race.session.state, " (0 = waiting on the grid)")
				race.start_race()
			if _f == _mark + 66:
				_shot("go")
			if _f == _mark + 150:
				_shot("racing")
				print("CHECK PASS: racing: ", race.session.state)
				return true
	return false
