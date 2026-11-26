extends SceneTree
## Developer check of photography mode (P004): a spectated night race; press
## the photo key, orbit, save a picture (and screenshot what the player
## sees), leave, and check the race carries on from the same moment.
## xvfb-run godot --path . -s tools/photo_check.gd -- --out=/tmp/pc [--night=1]

var _main: Node
var _f := 0
var _t0 := 0
var _out := "user://pc"
var _elapsed := 0.0


func _initialize() -> void:
	var night := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a == "--night=1":
			night = true
	_main = load("res://src/main/main.tscn").instantiate()
	_main.use_command_line_layout = false
	_main.layout_override = DevLayouts.load_layout("kestrel_ridge")
	_main.night = night
	_main.voice_enabled = false
	root.add_child.call_deferred(_main)


func _press(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	var r := InputEventAction.new()
	r.action = action
	r.pressed = false
	Input.parse_input_event.call_deferred(r)


func _shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png("%s_%s.png" % [_out, name])
	print("saved ", name)


func _process(_d: float) -> bool:
	_f += 1
	if _main == null or not _main.is_inside_tree() or _main.voxel == null or not _main.voxel.ready_3d:
		return _f > 20000
	var photo: PhotoMode = _main.voxel.photo
	if _t0 == 0:
		_t0 = _f
		_main.set_menu_choice(2)
		_main.start_race()
	var t := _f - _t0
	match t:
		200:
			_shot("before")
			_press(PlayerControls.PHOTO)
		206:
			print("CHECK photo mode on: ", photo.active, ", tree paused: ", paused)
			_elapsed = _main.session.elapsed
			photo._yaw = 2.2
			photo._pitch = 0.25
			photo._dist = 7.0
		220:
			_shot("photo_low")
			photo._yaw = 0.9
			photo._pitch = 0.9
			photo._dist = 22.0
		236:
			_shot("photo_high")
			photo._save()
		252:
			print("CHECK race frozen while in photo mode: ", absf(_main.session.elapsed - _elapsed) < 0.001)
			var dir := DirAccess.open(PhotoMode.SHOT_DIR)
			var n := 0
			if dir != null:
				for f in dir.get_files():
					if f.ends_with(".png"):
						n += 1
			print("CHECK pictures saved in ", ProjectSettings.globalize_path(PhotoMode.SHOT_DIR), ": ", n)
			_press(PlayerControls.PHOTO)
		262:
			print("CHECK photo mode off: ", not photo.active, ", unpaused: ", not paused)
		330:
			print("CHECK race carries on: ", _main.session.elapsed > _elapsed + 0.5)
			_shot("after")
			return true
	return false
