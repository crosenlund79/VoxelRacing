extends SceneTree
## Developer screenshot harness: starts a race scene directly (no title) and
## saves screenshots after a number of physics frames.
##
## xvfb-run -s "-screen 0 1280x720x24" godot --path . -s tools/capture_race.gd -- \
##   --layout=kestrel_ridge --variant=1 --night=0 --mode=spectate --shots=120,600 --out=/tmp/shot
##
## --mode=spectate | drive (drive: the player's car is driven by an AI so it moves)
## --speed=N   simulation multiplier while waiting between shots (spectate only)
## --follow=N  spectate: follow racer N

var _main: Node
var _shots: Array[int] = [180]
var _out := "user://shot"
var _frame := 0
var _mode := "spectate"
var _speed := 1
var _follow := -1
var _drive_ai: AiDriver = null
## --at=S: park the camera over the centreline at arc distance S (px).
var _at := -1.0
var _marker: Node2D


func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
	_mode = args.get("mode", "spectate")
	_out = args.get("out", _out)
	_speed = int(args.get("speed", "1"))
	_follow = int(args.get("follow", "-1"))
	_at = float(args.get("at", "-1"))
	if args.has("shots"):
		_shots.clear()
		for s in String(args.shots).split(","):
			_shots.append(int(s))
	var main: Node = load("res://src/main/main.tscn").instantiate()
	main.use_command_line_layout = false
	main.layout_override = DevLayouts.load_layout(args.get("layout", "kestrel_ridge"))
	main.track_variant = int(args.get("variant", "1"))
	main.night = args.get("night", "0") == "1"
	main.voice_enabled = false
	if args.get("two", "0") == "1":
		main.human_count = 2
	_main = main
	_args = args
	root.add_child.call_deferred(main)


var _args := {}
var _started := false


func _start() -> void:
	var main := _main
	var args := _args
	main.camera.make_current()
	if _mode == "spectate":
		main.set_menu_choice(2)
		main.start_race()
		if _follow >= 0:
			main.follow_driver(_follow)
		if _speed > 1:
			main.set_sim_speed(_speed)
	else:
		main.set_menu_choice(0)
		main.set_weapons_enabled(args.get("weapons", "0") == "1")
		main.start_race()
		# the player's car gets an AI driver so the screenshot shows real driving
		_drive_ai = AiDriver.new(main.racing_line, main.ai_params)
		main.inputs[0] = AiDriverInput.new(0, _drive_ai)
		main.inputs[0].begin_race(7)


func _physics_process(_delta: float) -> bool:
	if not _started:
		if _main.is_inside_tree():
			_started = true
			_start()
		return false
	_frame += 1
	if _at >= 0.0:
		if _marker == null:
			_marker = Node2D.new()
			_main.add_child(_marker)
			_marker.position = _main.track.path.point_at(_at)
		_main.camera.set_physics_process(false)
		_main.camera.global_position = _marker.position
	if _args.has("view"):
		VoxelStage.view_index = int(_args.view)
	if _args.get("clean", "0") == "1" and _main.hud.history_panel != null:
		_main.hud.history_panel.visible = false
	if _args.has("hurt") and _follow >= 0:  # --hurt=F1,F2,F3: damage, more damage, retire
		var fr := String(_args.hurt).split(",")
		var dw: DamageWorld = _main.damage
		var maxc: float = dw.rules.max_condition
		if _frame == int(fr[0]):
			dw.damage(_follow, maxc * 0.35)
		if fr.size() > 1 and _frame == int(fr[1]):
			dw.damage(_follow, maxc * 0.3)
		if fr.size() > 2 and _frame == int(fr[2]):
			if dw.damage(_follow, maxc):
				_main._retire(_follow)
	if _shots.has(_frame):
		var img := root.get_viewport().get_texture().get_image()
		var path := "%s_%05d.png" % [_out, _frame]
		img.save_png(path)
		print("saved ", path)
		if _args.has("debug_car") and _main.voxel != null:
			var k := int(_args.debug_car)
			var d: Dictionary = _main.voxel.cars3d[k]
			var c: Car = _main.cars[k]
			print("DEBUG car ", k, " 2d ", c.global_position, " vis ", c.visible, " root ", (d.root as Node3D).global_position, " rootvis ", (d.root as Node3D).visible,
				" bodyvis ", (d.body as Node3D).visible, " aabb ", (d.body as MeshInstance3D).get_aabb(), " cam ", _main.camera.get_screen_center_position(),
				" loss ", _main.voxel.race_fx.damage[k].loss(), " tint ", c.sprite.modulate)
		if _args.has("decal_dump") and _main.voxel != null:
			_main.voxel.decal_vp.get_texture().get_image().save_png("%s_%05d_decals.png" % [_out, _frame])
	return _frame > _shots.max() + 1
