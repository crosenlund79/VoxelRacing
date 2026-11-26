extends SceneTree
## Developer harness (P005): presents one podium (no race needed) and saves
## screenshots at a few scene times, to judge the grandstand behind it.
## xvfb-run godot --path . -s tools/podium_stand_check.gd -- --out=/tmp/ps [--times=1.8,4.4,6.6]

var _scene: CanvasLayer
var _out := "user://ps"
var _times: Array = [1.8, 4.4, 6.6]
var _k := 0
var _f := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--times="):
			_times = []
			for t in a.substr(8).split(","):
				_times.append(float(t))
	_scene = load("res://src/ui/podium_scene.gd").new()
	root.add_child.call_deferred(_scene)


func _entry(id: int, place: int) -> Dictionary:
	return {"id": id, "name": "YOU" if id == 0 else RivalRoster.short_name(id).to_upper(),
		"full_name": "You" if id == 0 else RivalRoster.full_name(id),
		"logical": "cars/body_player" if id == 0 else "cars/body_ai_%d" % id,
		"tint": Color.WHITE, "place": place, "is_player": id == 0}


func _process(_d: float) -> bool:
	_f += 1
	if _f == 4:
		_scene.present([_entry(4, 1), _entry(0, 2), _entry(7, 3)], AssetResolver.new())
	if _f < 5:
		return false
	if _k >= _times.size():
		return true
	if float(_scene.get("_time")) >= float(_times[_k]):
		root.get_viewport().get_texture().get_image().save_png("%s_t%.1f.png" % [_out, float(_times[_k])])
		print("saved t=", _times[_k])
		_k += 1
	return _f > 3000
