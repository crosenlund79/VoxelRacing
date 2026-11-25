extends SceneTree
## Developer screenshots of Prototype 003's racing touches: the burnout start
## (wheelspin smoke), a soda-can taunt (forced: two rivals close together,
## the one ahead leans out and throws), weight transfer and the night lamps.
## xvfb-run godot --path . -s tools/p003_showcase.gd -- --out=/tmp/sc [--night=1] [--layout=kestrel_ridge]

var _main: Node
var _f := 0
var _t0 := 0
var _out := "user://sc"
var _taunt_at := -1
var _thrower := -1
var _shots := 0
var _launch := -1


func _initialize() -> void:
	var night := false
	var layout := "kestrel_ridge"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a == "--night=1":
			night = true
		elif a.begins_with("--layout="):
			layout = a.substr(9)
	_main = load("res://src/main/main.tscn").instantiate()
	_main.use_command_line_layout = false
	_main.layout_override = DevLayouts.load_layout(layout)
	_main.night = night
	_main.voice_enabled = false
	root.add_child.call_deferred(_main)


func _shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png("%s_%s.png" % [_out, name])
	print("saved ", name)


func _physics_process(_d: float) -> bool:
	_f += 1
	if _main == null or not _main.is_inside_tree() or _main.voxel == null or not _main.voxel.ready_3d:
		return _f > 20000
	if _t0 == 0:
		_t0 = _f
		_main.set_menu_choice(2)
		_main.start_race()
		_main.hud.history_panel.visible = false
		_main.follow_driver(9)
	var t := _f - _t0
	# the launch: shots just after the followed car pulls away
	var lead: Car = _main.cars[9]
	if _launch < 0 and lead.model != null and lead.model.velocity.length() > 25.0:
		_launch = t
	if _launch > 0 and t - _launch in [4, 12, 24]:
		_shot("start_%d" % (t - _launch))
	if t == 400:
		_shot("racing")
	# a taunt: the first rival with another close behind it
	if t > 600 and _taunt_at < 0:
		var st: Array = _main.session.standings()
		for k in range(1, st.size()):
			var a: int = st[k - 1].id
			var b: int = st[k].id
			var ca: Car = _main.cars[a]
			var cb: Car = _main.cars[b]
			if ca.visible and cb.visible and ca.global_position.distance_to(cb.global_position) < 140.0:
				_thrower = a
				_main.follow_driver(a)
				_main.voxel.race_fx._taunt_last = -100.0
				_main.voxel.race_fx._taunt_cool[a] = -100.0
				# (on_overtake's chance roll is skipped: straight to the taunt)
				var local := (cb.global_position - ca.global_position).rotated(-ca.global_rotation)
				_main.voxel.cars3d[a].head_side = 1.0 if local.y >= 0.0 else -1.0
				_main.voxel.race_fx._taunts.append({"car": a, "victim": b, "t": 0.0, "thrown": false})
				_taunt_at = t
				print("taunt: %d throws at %d" % [a, b])
				break
	if _taunt_at > 0 and t > _taunt_at + 20 and t <= _taunt_at + 110 and (t - _taunt_at) % 10 == 0:
		_shots += 1
		_shot("taunt_%02d" % _shots)
	if _taunt_at > 0 and t > _taunt_at + 120:
		print("cans on the road: ", _main.voxel.race_fx.cans.size())
		return true
	return t > 6000
