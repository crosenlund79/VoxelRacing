extends SceneTree
## Developer check of the action replays: a short spectated race with weapons;
## a car is wrecked through DamageWorld and a mine is laid in front of another
## (so the destruction and mine cameras have something to show), then the race
## ends and the highlights play. Prints the moments and saves screenshots of
## the replay and the results.
## xvfb-run godot --path . -s tools/replay_check.gd -- --out=/tmp/rp [--night=1] [--laps=1]

var _main: Node
var _f := 0
var _out := "user://rp"
var _t0 := 0
var _shots := 0
var _seen_replay := false
var _done_at := -1
var _last_clip := -1
var _mined := false
var _laps := 1


func _initialize() -> void:
	var night := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a == "--night=1":
			night = true
		elif a.begins_with("--laps="):
			_laps = int(a.substr(7))
	_main = load("res://src/main/main.tscn").instantiate()
	_main.use_command_line_layout = false
	_main.layout_override = DevLayouts.load_layout("kestrel_ridge")
	_main.night = night
	_main.voice_enabled = false
	_main.weapons_lock_enabled = false
	root.add_child.call_deferred(_main)


func _shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png("%s_%s.png" % [_out, name])


func _physics_process(_d: float) -> bool:
	_f += 1
	if _main == null or not _main.is_inside_tree() or _main.voxel == null or not _main.voxel.ready_3d:
		return _f > 20000
	var rp: ReplayTheater = _main.voxel.replay
	if _t0 == 0:
		_t0 = _f
		_main.set_menu_choice(2)  # spectate
		_main.set_weapons_enabled(true)
		_main.set_lap_count(_laps)
		_main.start_race()
		_main.set_sim_speed(2)
		_main.hud.history_panel.visible = false
	var t := _f - _t0
	var session: RaceSession = _main.session
	if t == 420:
		# a wreck for the destruction camera
		var dw: DamageWorld = _main.damage
		if dw.damage(4, dw.rules.max_condition):
			_main._retire(4)
		print("forced wreck of car 4")
	if t > 700 and not _mined and session.state == RaceSession.State.RACING:
		# a mine laid on the road ahead of the leader (owner: the car behind)
		var st := session.standings()
		var lead: int = st[0].id
		var c: Car = _main.cars[lead]
		var fwd := Vector2.from_angle(c.global_rotation)
		_main.combat.mines.append({"owner": st[1].id, "pos": c.global_position + fwd * 260.0, "age": 0.0, "level": 0})
		_mined = true
		print("mine laid in front of ", lead)
	if rp != null and rp.playing:
		if not _seen_replay:
			_seen_replay = true
			_main.set_sim_speed(1)
			print("REPLAY started: %d moments" % rp.clips.size())
			for c in rp.clips:
				var tt := ReplayTheater.moment_titles(c.key, rp.recorder.names)
				print("  moment: %s (%s) score %.1f, %.1f s, %d events, start %.1f key %.1f rid %s launch %s" % [tt[0], c.key.kind, c.score,
					float(c.samples[-1][0]) - float(c.samples[0][0]), (c.events as Array).size(), float(c.samples[0][0]),
					float(c.key.t), str(c.key.get("rid", "-")), str(c.key.get("launch_t", "-"))])
			print("  launches recorded: ", rp.recorder._launches.size(), " captures: ", rp.recorder.captures.size())
		if rp._clip != _last_clip:
			_last_clip = rp._clip
			print("clip %d: shots %s" % [rp._clip, str(rp._shots.map(func(s: Array) -> String: return s[0]))])
		if t % 40 == 0 and _shots < 40:
			_shots += 1
			_shot("r%02d_c%d_%s" % [_shots, rp._clip, rp._cam_label.text.replace(" ", "_")])
	elif _seen_replay and _done_at < 0:
		_done_at = t
		print("REPLAY finished; captures: %d" % rp.recorder.captures.size())
	if _done_at > 0 and t == _done_at + 30:
		_shot("z_results")
		print("CHECK replay played and returned: ", _seen_replay)
		return true
	if t > 30000:
		print("CHECK timeout; state ", session.state, " captures ", rp.recorder.captures.size() if rp != null else -1)
		return true
	return false
