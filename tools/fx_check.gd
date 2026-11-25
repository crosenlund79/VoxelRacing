extends SceneTree
## Developer check of the voxel race effects: a car is damaged and retired
## through the race's own DamageWorld; prints debris / settled / burn counts,
## lets the field drive through the wreck, then starts a fresh race and checks
## that the race history (debris, burn marks) is cleared. Screenshots.
## xvfb-run godot --path . -s tools/fx_check.gd -- --out=/tmp/fx [--night=1]

var _main: Node
var _f := 0
var _out := "user://fx"
var _victim := 5
var _t0 := 0
var _scattered_before := 0


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


func _shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png("%s_%s.png" % [_out, name])
	print("saved ", name)


func _counts() -> String:
	var fx: VoxelFx = _main.voxel.race_fx.fx
	return "debris %d, settled %d, burn marks %d" % [fx.debris_count(), fx.settled_count(), _main.voxel.race_fx.burn_count()]


func _physics_process(_d: float) -> bool:
	_f += 1
	if _main == null or not _main.is_inside_tree() or _main.voxel == null or not _main.voxel.ready_3d:
		return _f > 20000
	if _t0 == 0:
		_t0 = _f
		_main.set_menu_choice(2)
		_main.start_race()
		_main.follow_driver(_victim)
		_main.hud.history_panel.visible = false
	var t := _f - _t0
	var dw: DamageWorld = _main.damage
	match t:
		240:
			dw.damage(_victim, dw.rules.max_condition * 0.3)
		300:
			dw.damage(_victim, dw.rules.max_condition * 0.3)
		360:
			_shot("1_damaged")
			print("CHECK damaged car lost bodywork: ", _main.voxel.race_fx.damage[_victim].loss() > 0.1,
				" (loss %.2f)" % _main.voxel.race_fx.damage[_victim].loss())
		362:
			if dw.damage(_victim, dw.rules.max_condition):
				_main._retire(_victim)
		372:
			_shot("2_explosion")
		440:
			_shot("3_debris_burn")
			print("CHECK after explosion: ", _counts())
			_scattered_before = _main.voxel.race_fx.fx.settled_count()
		900:
			_shot("4_after_traffic")
			print("CHECK later (cars passed): ", _counts())
		902:
			_main.reset_race()
			_main.start_race()
		920:
			print("CHECK fresh race: ", _counts())
			_shot("5_fresh_race")
			return true
	return false
