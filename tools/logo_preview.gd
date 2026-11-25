extends SceneTree
## Developer harness: renders the VoxelLogo to a PNG.
## xvfb-run godot --path . -s tools/logo_preview.gd -- --out=/tmp/logo.png [--w=1024 --h=480]

var _f := 0
var _out := "user://logo.png"
var _logo: VoxelLogo


func _initialize() -> void:
	var w := 1024
	var h := 480
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--w="):
			w = int(a.substr(4))
		elif a.begins_with("--h="):
			h = int(a.substr(4))
	root.size = Vector2i(w, h)
	var bg := ColorRect.new()
	bg.color = VrStyle.NIGHT
	bg.size = Vector2(w, h)
	root.add_child(bg)
	_logo = VoxelLogo.new()
	_logo.size = Vector2(w, h)
	root.add_child(_logo)


func _process(_d: float) -> bool:
	_f += 1
	if _f == 20:
		_logo.animate = false
	if _f == 24:
		root.get_viewport().get_texture().get_image().save_png(_out)
		print("saved ", _out)
		return true
	return false
