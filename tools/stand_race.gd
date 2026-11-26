extends SceneTree
## Developer harness (P005): the grandstands on a real circuit. Builds a race
## (layout, theme variant, day / night), starts it, prints the stands and how
## many spectators sit in them, then parks the race camera over the stands
## (and a little along the straight) and saves screenshots.
## xvfb-run godot --path . -s tools/stand_race.gd -- --layout=kestrel_ridge --variant=1 [--night=1] [--view=0] --out=/tmp/sr

var _main: Node
var _f := 0
var _t0 := 0
var _out := "user://sr"
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
	VoxelStage.view_index = int(args.get("view", "0"))
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
		var stands: Array = life._stands
		var seated := 0
		for key in ["stand_crowd", "stand_flags"]:
			if life._mms.has(key):
				seated += (life._mms[key] as MultiMesh).instance_count
		var inside := 0
		for person in life._people:
			if not person.has("seat") and life._in_stand(person.p, 0.0):
				inside += 1
		print("stands: %d   seated spectators: %d   all spectators: %d   trackside people inside a stand: %d" % [
			stands.size(), seated, life.crowd_size(), inside])
		if stands.is_empty():
			print("no grandstands on this theme")
			return true
		var c := Vector2.ZERO
		for sb in stands:
			c += sb[0] as Vector2
		c /= stands.size()
		var front: Vector2 = stands[0][2]
		_spots.append(["stands", c - front * 60.0])
		_spots.append(["stand_end", (stands[0][0] as Vector2) - front * 40.0])
	var t := _f - _t0
	if t > 240:  # (the race is running: cars about)
		if _hold <= 0:
			_k += 1
			if _k >= _spots.size():
				return true
			_hold = 45
		_main.camera.global_position = _spots[_k][1]
		_hold -= 1
		if _hold == 1:
			root.get_viewport().get_texture().get_image().save_png("%s_%s.png" % [_out, _spots[_k][0]])
			print("saved ", _spots[_k][0])
	return t > 20000
