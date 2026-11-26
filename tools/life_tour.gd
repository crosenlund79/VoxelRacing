extends SceneTree
## Developer tour of a circuit's living details (P004): lists the set
## dressing and the crowd, then parks the camera over a few pieces and a
## crowd group (with the race running) and saves screenshots.
## xvfb-run godot --path . -s tools/life_tour.gd -- --layout=kestrel_ridge --variant=1 [--night=1] --out=/tmp/lt

var _main: Node
var _f := 0
var _t0 := 0
var _out := "user://lt"
var _spots: Array = []
var _k := -1
var _hold := 0


func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
	_out = args.get("out", _out)
	_main = load("res://src/main/main.tscn").instantiate()
	_main.use_command_line_layout = false
	_main.layout_override = DevLayouts.load_layout(args.get("layout", "kestrel_ridge"))
	_main.track_variant = int(args.get("variant", "1"))
	_main.night = args.get("night", "0") == "1"
	_main.voice_enabled = false
	root.add_child.call_deferred(_main)


func _physics_process(_d: float) -> bool:
	_f += 1
	if _main == null or not _main.is_inside_tree() or _main.voxel == null or not _main.voxel.ready_3d:
		return _f > 20000
	var life: VoxelLife = _main.voxel.life
	if _t0 == 0:
		_t0 = _f
		_main.set_menu_choice(2)
		_main.start_race()
		_main.hud.visible = false
		var counts := {}
		var dressing := life.get_node_or_null("Dressing")
		if dressing != null:
			for n in dressing.get_children():
				if n.has_meta("kind"):
					counts[n.get_meta("kind")] = int(counts.get(n.get_meta("kind"), 0)) + 1
					if _spots.size() < 5 and not (n.get_meta("kind") in ["fence", "hay", "cow", "flagpole", "bench", "tyre_wall"]):
						_spots.append([n.get_meta("kind"), Vector2(n.position.x, n.position.z) / Vox.PX])
		print("dressing: ", counts, "   spectators: ", life.crowd_size())
		var p: Array = life._people
		if p.size() > 0:
			_spots.append(["crowd", p[0].p])
			_spots.append(["crowd2", p[p.size() / 2].p])
	var t := _f - _t0
	if t > 300:  # (the race is running: cars about)
		if _hold <= 0:
			_k += 1
			if _k >= _spots.size():
				return true
			_hold = 45
		_main.camera.global_position = _spots[_k][1]
		_hold -= 1
		if _hold == 1:
			root.get_viewport().get_texture().get_image().save_png("%s_%d_%s.png" % [_out, _k, _spots[_k][0]])
			print("saved ", _spots[_k][0])
	return t > 20000
