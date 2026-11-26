extends SceneTree
## Developer harness: the race setup screen's voxel CircuitPreview at its
## real size (700 x 460) over a dark backdrop. Shows a set of circuits x
## environments x day / night plus the Scrapyard arena, saves a PNG of each
## and prints the rebuild time of every show_* call (cold build, then cached).
## xvfb-run godot --path . -s tools/preview_check.gd -- --out=/tmp/preview/pv [--only=3] [--w=520 --h=300]

const SHOTS := [
	["kestrel_ridge", 1, false], ["kestrel_ridge", 1, true], ["larkspur_ring", 2, false], ["ravenhook", 3, false],
	["ravenhook", 3, true], ["kestrel_ridge", 4, false], ["larkspur_ring", 4, true], ["ravenhook", 5, false],
	["kestrel_ridge", 5, true], ["exp_figure8_01", 1, false], ["larkspur_ring", 1, false], ["classic_01", 2, true],
	["arena", 1, false], ["arena", 2, true], ["arena", 3, false],
]
const WAIT := 8

var _out := "user://preview"
var _preview: CircuitPreview
var _f := 0
var _shot := -1
var _mark := 0
var _only := -1
var _times: Array[String] = []
var _size := Vector2(700, 460)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--only="):
			_only = int(a.substr(7))
		elif a.begins_with("--w="):
			_size.x = float(a.substr(4))
		elif a.begins_with("--h="):
			_size.y = float(a.substr(4))
	root.size = Vector2i(_size) + Vector2i(60, 60)
	var bg := ColorRect.new()
	bg.color = Color("1e2040")
	bg.size = _size + Vector2(60, 60)
	root.add_child(bg)
	_preview = CircuitPreview.new()
	_preview.custom_minimum_size = _size
	_preview.position = Vector2(30, 30)
	_preview.size = _size
	root.add_child(_preview)


func _show(k: int) -> void:
	var s: Array = SHOTS[k]
	var id: String = s[0]
	var v: int = s[1]
	var n: bool = s[2]
	if id == "arena":
		_preview.show_arena(ArenaLayout.new(), v, n)
	else:
		_preview.show_circuit(DevLayouts.load_layout(id), v, n)
	var line := "%-16s v%d %-5s  %6.1f ms%s  %s" % [id, v, "night" if n else "day", _preview.last_build_ms,
		" (cached)" if _preview.last_build_cached else "", "" if _preview.last_build_cached else str(CircuitPreview.timings)]
	print(line)
	_times.append(line)


func _process(_d: float) -> bool:
	_f += 1
	if _f < _mark:
		return false
	if _shot >= 0:
		var s: Array = SHOTS[_shot]
		var path := "%s_%02d_%s_v%d_%s.png" % [_out, _shot, s[0], s[1], "night" if s[2] else "day"]
		root.get_viewport().get_texture().get_image().get_region(Rect2i(Vector2i.ZERO, Vector2i(_size) + Vector2i(60, 60))).save_png(path)
		print("saved ", path)
	_shot += 1
	if _only >= 0:
		if _shot > _only:
			_finish()
			return true
		_shot = _only
	if _shot >= SHOTS.size():
		_finish()
		return true
	_show(_shot)
	_mark = _f + WAIT
	return false


func _finish() -> void:
	# cold rebuilds without the caches (the props' meshes stay built): best of 3
	print("--- cold rebuilds, best of 3 (layout raster + diorama) ---")
	for spec: Array in [["kestrel_ridge", 1], ["larkspur_ring", 2], ["ravenhook", 4], ["kestrel_ridge", 5], ["exp_figure8_01", 3], ["arena", 1]]:
		var best := INF
		var phases := {}
		for rep in 3:
			CircuitPreview._dioramas.clear()
			CircuitPreview._rasters.clear()
			CircuitPreview._order.clear()
			if spec[0] == "arena":
				_preview.show_arena(ArenaLayout.new(), spec[1], false)
			else:
				_preview.show_circuit(DevLayouts.load_layout(spec[0]), spec[1], false)
			if _preview.last_build_ms < best:
				best = _preview.last_build_ms
				phases = CircuitPreview.timings.duplicate()
		print("%-16s v%d  %6.1f ms  %s" % [spec[0], spec[1], best, phases])
	# a couple of warm (cached) rebuilds: day / night toggles and revisits
	_preview.show_circuit(DevLayouts.load_layout("kestrel_ridge"), 1, true)
	print("revisit kestrel v1 night: %.1f ms cached=%s" % [_preview.last_build_ms, _preview.last_build_cached])
	_preview.show_circuit(DevLayouts.load_layout("kestrel_ridge"), 1, false)
	print("revisit kestrel v1 day:   %.1f ms cached=%s" % [_preview.last_build_ms, _preview.last_build_cached])
	print("--- rebuild times ---")
	for t in _times:
		print(t)
