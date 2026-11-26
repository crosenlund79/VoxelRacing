extends SceneTree
## Developer check of the opening combat (Prototype 005): one spectated race
## with weapons, counting shots fired and cars wrecked in 5 s windows after the
## weapons go hot. A quick sanity check of the pacing, not a balance study.
## xvfb-run godot --path . -s tools/opening_check.gd -- [--laps=3] [--seconds=60]

var _main: Node
var _f := 0
var _t0 := 0
var _hot_f := -1
var _hot_at := 0.0
var _laps := 3
var _seconds := 60
var _bins: Array[int] = []
var _wreck_bins: Array[int] = []
var _last_shots := 0
var _last_wrecks := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--laps="):
			_laps = int(a.substr(7))
		elif a.begins_with("--seconds="):
			_seconds = int(a.substr(10))
	_main = load("res://src/main/main.tscn").instantiate()
	_main.use_command_line_layout = false
	_main.layout_override = DevLayouts.load_layout("kestrel_ridge")
	_main.voice_enabled = false
	root.add_child.call_deferred(_main)


func _total(arr) -> int:
	var n := 0
	for v in arr:
		n += int(v)
	return n


func _physics_process(_d: float) -> bool:
	_f += 1
	if _main == null or not _main.is_inside_tree() or _main.voxel == null or not _main.voxel.ready_3d:
		return _f > 20000
	if _t0 == 0:
		_t0 = _f
		_main.set_menu_choice(2)  # spectate: ten rivals
		_main.set_weapons_enabled(true)
		_main.set_lap_count(_laps)
		_main.start_race()
		_main.set_sim_speed(2)
		return false
	var combat: CombatWorld = _main.combat
	if _hot_f < 0:
		if not combat.locked and _main.session.state == RaceSession.State.RACING:
			_hot_f = _f
			_hot_at = _main.session.elapsed
			_last_shots = _total(combat.shots_fired)
			_last_wrecks = _total(combat.destroyed_count)
			print("weapons hot at %.1f s of racing" % _main.session.elapsed)
		return _f > 20000
	var t: float = _main.session.elapsed - _hot_at
	var bin := int(t / 5.0)
	while _bins.size() <= bin:
		_bins.append(0)
		_wreck_bins.append(0)
	var shots := _total(combat.shots_fired)
	var wrecks := _total(combat.destroyed_count)
	_bins[bin] += shots - _last_shots
	_wreck_bins[bin] += wrecks - _last_wrecks
	_last_shots = shots
	_last_wrecks = wrecks
	if t >= _seconds or _main.session.state == RaceSession.State.FINISHED:
		var line := ""
		for k in _bins.size():
			line += "%d-%ds: %d shots %d wrecks | " % [k * 5, k * 5 + 5, _bins[k], _wreck_bins[k]]
		print("OPENING ", line)
		var first := 0
		for k in mini(2, _bins.size()):
			first += _bins[k]
		print("CHECK opening: %d shots in the first 10 s, %d in the first %d s" % [first, _total(_bins), _seconds])
		return true
	return false
