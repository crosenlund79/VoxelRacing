extends SceneTree
## Developer check of Prototype 003's Championship with the garage: start a
## championship from the game, end round 1 at once (the player first, then the
## rest in grid order, so nothing has to be raced), confirm the results, see the
## standings, continue into the garage, start round 2 from the garage, and
## check that the round's prize money reached the garage.
## xvfb-run godot --path . -s tools/champ_flow.gd -- --out=/tmp/cf

var _game: Node
var _f := 0
var _out := "user://cf"
var _step := 0
var _mark := 0
var _money0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	_game = load("res://src/main/game.tscn").instantiate()
	root.add_child.call_deferred(_game)


func _shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png("%s_%s.png" % [_out, name])


func _check(what: String, ok: bool, extra: String = "") -> void:
	print("CHECK %s: %s %s" % ["PASS" if ok else "FAIL", what, extra])


func _press(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	var r := InputEventAction.new()
	r.action = action
	r.pressed = false
	Input.parse_input_event.call_deferred(r)


func _process(_d: float) -> bool:
	_f += 1
	var race = _game.get("race")
	match _step:
		0:
			if _f > 90:
				_money0 = _game.garage.money
				_game.start_championship(0)
				_step = 1
		1:  # round 1 is built; end it at once
			if race != null and race.voxel != null and race.voxel.ready_3d and not _game._starting and _f > _mark + 60:
				if _game.garage_screen.visible:  # the shop before round 1: RACE!
					_shot("0_garage_round1")
					_check("round 1 races with the garage", race.garage == _game.garage)
					_game.garage_screen.race_requested.emit()
					_mark = _f
					return false
				if race.session.state == RaceSession.State.MODE_SELECT:
					race.start_race()  # (the grid panel's Fire)
					_mark = _f
					return false
				var s: RaceSession = race.session
				s.finish_now(RaceSession.PLAYER_ID)  # a win: prize money
				for id in race.grid_order:
					s.finish_now(id)
				_step = 2
				_mark = _f
		2:
			if _f == _mark + 90:
				_shot("1_results")
				_press(PlayerControls.CONFIRM)
				_step = 3
				_mark = _f
		3:
			if race == null and _f > _mark + 60:
				_shot("2_standings")
				_check("standings after the round", _game.champ_screen.visible)
				_check("prize money paid into the garage", _game.garage.money > _money0, "($%d -> $%d)" % [_money0, _game.garage.money])
				_game.champ_screen._on_continue()
				_step = 4
				_mark = _f
		4:
			if _f == _mark + 30:
				_shot("3_garage")
				_check("garage opens between rounds", _game.garage_screen.visible)
				_game.garage_screen.race_requested.emit()
				_step = 5
				_mark = _f
		5:
			if race != null and race.voxel != null and race.voxel.ready_3d and not _game._starting:
				_check("round 2 starts from the garage", _game.champ.round_index() == 1, "(round %d)" % (_game.champ.round_index() + 1))
				_check("no second garage on round 2's grid", not _game.garage_screen.visible)
				_shot("4_round2")
				return true
			if _f > _mark + 4000:
				_check("round 2 starts from the garage", false, "(timeout)")
				return true
	return _f > 20000
