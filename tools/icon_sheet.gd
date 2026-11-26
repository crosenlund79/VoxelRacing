extends SceneTree
## Developer harness: renders every VrIcons icon (src/ui/vr_icons.gd) on a
## night panel, each at a few sizes in its normal / dim / disabled states with
## its name under it, and saves one PNG. Also prints how long making every
## icon takes. Run under Xvfb:
## xvfb-run godot --path . -s tools/icon_sheet.gd -- --out=/tmp/icons.png
##   [--sizes=24,48] [--states=normal,dim,disabled] [--only=car,laps,...]
##   [--cols=5] [--zoom=2] [--buttons=1]  (buttons: also on red/yellow/teal faces)

const VrIcons := preload("res://src/ui/vr_icons.gd")

var _f := 0
var _out := "user://icon_sheet.png"
var _zoom := 1
var _vp: SubViewport


func _initialize() -> void:
	var sizes: Array[int] = [24, 48]
	var states := PackedStringArray(["normal", "dim", "disabled"])
	var only := PackedStringArray()
	var cols := 5
	var buttons := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--sizes="):
			sizes.clear()
			for s in a.substr(8).split(","):
				sizes.append(int(s))
		elif a.begins_with("--states="):
			states = a.substr(9).split(",")
		elif a.begins_with("--only="):
			only = a.substr(7).split(",")
		elif a.begins_with("--cols="):
			cols = int(a.substr(7))
		elif a.begins_with("--zoom="):
			_zoom = maxi(1, int(a.substr(7)))
		elif a == "--buttons=1":
			buttons = true
	_timing()
	var names := only if not only.is_empty() else VrIcons.names()
	var faces: Array[Color] = [VrStyle.NIGHT]
	if buttons:
		faces = [VrStyle.NIGHT, VrStyle.RED, VrStyle.YELLOW, VrStyle.TEAL]
	var gap := 4
	var cell_w := 0
	for s in sizes:
		cell_w += (s + gap) * states.size() * faces.size() + 10
	cell_w = maxi(cell_w, 120)
	var icon_h: int = sizes.max() if not sizes.is_empty() else 24
	var cell_h := icon_h + 22
	var rows := ceili(float(names.size()) / cols)
	_vp = SubViewport.new()
	_vp.size = Vector2i(cols * cell_w + 16, rows * cell_h + 16)
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	var bg := ColorRect.new()
	bg.color = VrStyle.NIGHT
	bg.size = Vector2(_vp.size)
	_vp.add_child(bg)
	for i in names.size():
		var at := Vector2(8 + (i % cols) * cell_w, 8 + (i / cols) * cell_h)
		var x := at.x
		for s in sizes:
			for face in faces:
				for st in states:
					if face != VrStyle.NIGHT:
						var chip := ColorRect.new()
						chip.color = face
						chip.position = Vector2(x - 2, at.y + icon_h - s - 2)
						chip.size = Vector2(s + 4, s + 4)
						_vp.add_child(chip)
					var r := TextureRect.new()
					r.texture = VrIcons.tex(names[i], s, st)
					r.stretch_mode = TextureRect.STRETCH_KEEP
					r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
					r.position = Vector2(x, at.y + icon_h - s)
					r.size = Vector2(s, s)
					_vp.add_child(r)
					x += s + gap
			x += 10
		var l := Label.new()
		l.text = names[i]
		l.add_theme_font_size_override("font_size", 11)
		l.add_theme_color_override("font_color", VrStyle.PAPER_DIM)
		l.position = Vector2(at.x, at.y + icon_h + 2)
		_vp.add_child(l)
	print("icons: ", names.size())


## Prints how long making every icon (uncached) takes at a few sizes.
func _timing() -> void:
	for s in [18, 24, 48, 64]:
		var t0 := Time.get_ticks_usec()
		for n in VrIcons.names():
			ImageTexture.create_from_image(VrIcons.image(n, s))
		print("timing: all %d icons at %d px: %.1f ms" % [VrIcons.names().size(), s, (Time.get_ticks_usec() - t0) / 1000.0])
	var t1 := Time.get_ticks_usec()
	VrIcons.tex("no_such_icon", 24)
	VrIcons.tex("no_such_icon", 24)
	print("fallback ok: ", VrIcons.tex("no_such_icon", 24) != null, " (%.1f ms)" % ((Time.get_ticks_usec() - t1) / 1000.0))


func _process(_d: float) -> bool:
	_f += 1
	if _f == 6:
		var img := _vp.get_texture().get_image()
		if _zoom > 1:
			img.resize(img.get_width() * _zoom, img.get_height() * _zoom, Image.INTERPOLATE_NEAREST)
		img.save_png(_out)
		print("saved ", _out)
		return true
	return false
