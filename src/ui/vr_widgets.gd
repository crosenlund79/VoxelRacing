extends RefCounted
## Compact interface pieces for Prototype 005 ("Less Is More"): small icon
## buttons, value cyclers where the value itself is the control, a clean
## translucent panel and plain text without heavy outlines. Everything uses
## the VoxelRacing palette (VrStyle), Kenney Future and the voxel icons
## (VrIcons); every icon button can carry a short tooltip (VrTips).
## Loaded with preload (no class_name):
##   const VrWidgets := preload("res://src/ui/vr_widgets.gd")

const VrIcons := preload("res://src/ui/vr_icons.gd")
const VrTips := preload("res://src/ui/vr_tips.gd")
const UiJuice := preload("res://src/ui/ui_juice.gd")

const FACE := Color("2e3466")
const FACE_HOVER := Color("454d8f")
const FACE_ON := Color("f7b731")


## A small chip box: a dark face, an ink rim and a slightly deeper bottom edge
## (the voxel brick, quietly). focus: the yellow highlight ring.
static func chip(face: Color = FACE, focus: bool = false, alpha: float = 0.92) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(face, alpha)
	s.border_color = VrStyle.YELLOW if focus else Color(VrStyle.INK, 0.9)
	s.set_border_width_all(2)
	s.border_width_bottom = 4
	s.set_corner_radius_all(4)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 4
	s.content_margin_bottom = 6
	return s


## A clean translucent panel (the compact replacement of the big voxel slab).
static func panel(alpha: float = 0.86) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(VrStyle.NIGHT, alpha)
	s.border_color = Color(VrStyle.INK, 0.95)
	s.set_border_width_all(2)
	s.border_width_bottom = 5
	s.set_corner_radius_all(6)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 10
	s.content_margin_bottom = 12
	s.shadow_color = Color(0, 0, 0, 0.25)
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 3)
	return s


## Applies the chip look to a button (normal / hover / focus / pressed / disabled).
static func style_button(b: Button, face: Color = FACE) -> Button:
	b.add_theme_stylebox_override("normal", chip(face))
	b.add_theme_stylebox_override("hover", chip(face.lerp(FACE_HOVER, 0.6), true))
	b.add_theme_stylebox_override("focus", chip(face.lerp(FACE_HOVER, 0.6), true))
	b.add_theme_stylebox_override("hover_pressed", chip(face.darkened(0.15), true))
	b.add_theme_stylebox_override("pressed", chip(face.darkened(0.15), true))
	var off := chip(VrStyle.NIGHT, false, 0.55)
	b.add_theme_stylebox_override("disabled", off)
	b.add_theme_color_override("font_color", VrStyle.PAPER)
	b.add_theme_color_override("font_hover_color", VrStyle.PAPER)
	b.add_theme_color_override("font_focus_color", VrStyle.PAPER)
	b.add_theme_color_override("font_pressed_color", VrStyle.YELLOW)
	b.add_theme_color_override("font_hover_pressed_color", VrStyle.YELLOW)
	b.add_theme_color_override("font_disabled_color", Color(VrStyle.PAPER, 0.4))
	b.add_theme_constant_override("outline_size", 0)
	b.add_theme_constant_override("h_separation", 8)
	b.add_theme_font_override("font", VrStyle.font("regular"))
	return b


## A compact button with a voxel icon (and optionally a short text after it).
## tip: the short tooltip ("" for none). size: the button's height (and the
## width of an icon-only button).
static func icon_button(icon: String, tip: Variant = "", size: int = 44, text: String = "", font_size: int = 16) -> Button:
	var b := Button.new()
	b.text = text
	b.icon = VrIcons.tex(icon, _icon_px(size))
	b.custom_minimum_size = Vector2(size if text == "" else 0, size)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER if text == "" else HORIZONTAL_ALIGNMENT_LEFT
	b.expand_icon = false
	b.focus_mode = Control.FOCUS_ALL
	style_button(b)
	b.add_theme_font_size_override("font_size", font_size)
	b.set_meta("vr_icon", icon)
	if not (tip is String and (tip as String).is_empty()):
		VrTips.tip(b, tip)
	b.mouse_entered.connect(func() -> void:
		if b.focus_mode != Control.FOCUS_NONE and not b.disabled:
			b.grab_focus())
	UiJuice.button(b)
	return b


## The icon size that fits a button of this height (crisp voxel steps).
static func _icon_px(size: int) -> int:
	if size >= 56:
		return 48
	if size >= 44:
		return 32
	if size >= 34:
		return 24
	return 18


## Changes a button's icon (e.g. sun <-> moon); state "normal" / "dim" / "disabled".
static func set_icon(b: Button, icon: String, state: String = "normal") -> void:
	var size := int(b.custom_minimum_size.y) if b.custom_minimum_size.y > 0 else 44
	b.icon = VrIcons.tex(icon, _icon_px(size), state)
	b.set_meta("vr_icon", icon)


## Plain interface text: Kenney Future, no heavy outline.
static func text(t: String, size: int = 16, color: Color = VrStyle.PAPER, kind: String = "regular", outline: int = 0) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", VrStyle.font(kind))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_color_override("font_outline_color", VrStyle.INK)
		l.add_theme_constant_override("outline_size", outline)
	else:
		l.add_theme_constant_override("outline_size", 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A voxel icon as a TextureRect (for headers, popups, HUD rows).
static func icon(name: String, size: int = 24, state: String = "normal") -> TextureRect:
	var r := TextureRect.new()
	r.texture = VrIcons.tex(name, size, state)
	r.custom_minimum_size = Vector2(size, size)
	r.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return r


## An icon followed by a short value ("[sun]", "[flag] 3"), for read-only rows.
static func icon_value(name: String, value: String = "", size: int = 24, color: Color = VrStyle.PAPER, tip: String = "") -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	h.add_child(icon(name, size))
	if value != "":
		var l := text(value, int(size * 0.72), color)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(l)
	if tip != "":
		h.mouse_filter = Control.MOUSE_FILTER_PASS
		VrTips.tip(h, tip)
	return h


## A device-aware key prompt: a small key cap with the player's binding for
## the action on their chosen input device, and a short word ("Race").
static func prompt(action: String, word: String, size: int = 14) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var cap := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(VrStyle.PAPER, 0.92)
	s.set_corner_radius_all(3)
	s.content_margin_left = 6
	s.content_margin_right = 6
	s.content_margin_top = 1
	s.content_margin_bottom = 2
	cap.add_theme_stylebox_override("panel", s)
	cap.add_child(text(PlayerControls.key_text(action), size, VrStyle.INK))
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(cap)
	if word != "":
		var l := text(word, size, VrStyle.PAPER_DIM)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(l)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


## A value cycler where the value itself is the control: "<  Kestrel Ridge  >".
## Left / Right (keys, d-pad) cycle it while it has focus; the small arrows and
## a click on the value cycle it with the mouse. on_cycle(dir: int) changes the
## value and the caller sets the text with set_value().
class Cycler extends HBoxContainer:
	var value: Button
	var _prev: Button
	var _next: Button
	var _cycle: Callable

	func _init(on_cycle: Callable, width: int = 360, font_size: int = 22, tip: Variant = "") -> void:
		_cycle = on_cycle
		add_theme_constant_override("separation", 2)
		alignment = BoxContainer.ALIGNMENT_CENTER
		_prev = _arrow("prev", -1, font_size)
		value = Button.new()
		value.flat = true
		value.custom_minimum_size = Vector2(width, font_size + 18)
		value.add_theme_font_override("font", VrStyle.font("regular"))
		value.add_theme_font_size_override("font_size", font_size)
		for k in ["font_color", "font_pressed_color", "font_hover_pressed_color"]:
			value.add_theme_color_override(k, VrStyle.PAPER)
		for k in ["font_hover_color", "font_focus_color"]:
			value.add_theme_color_override(k, VrStyle.YELLOW)
		var under := StyleBoxFlat.new()  # focus: a yellow underline
		under.bg_color = Color(0, 0, 0, 0)
		under.border_color = VrStyle.YELLOW
		under.border_width_bottom = 3
		under.content_margin_bottom = 3
		var none := StyleBoxEmpty.new()
		none.content_margin_bottom = 3
		value.add_theme_stylebox_override("focus", under)
		value.add_theme_stylebox_override("hover", under)
		value.add_theme_stylebox_override("normal", none)
		value.add_theme_stylebox_override("pressed", under)
		value.add_theme_stylebox_override("hover_pressed", under)
		value.add_theme_constant_override("outline_size", 0)
		value.clip_text = true
		value.set_meta("cycle", on_cycle)
		value.pressed.connect(func() -> void: _cycle.call(1))
		value.gui_input.connect(_on_input)
		value.mouse_entered.connect(value.grab_focus)
		value.focus_entered.connect(_show_arrows.bind(true))
		value.focus_exited.connect(_show_arrows.bind(false))
		if not (tip is String and (tip as String).is_empty()):
			VrTips.tip(value, tip)
		add_child(_prev)
		add_child(value)
		add_child(_next if _next != null else _arrow("next", 1, font_size))
		_show_arrows(false)

	func _arrow(name: String, dir: int, font_size: int) -> Button:
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.icon = VrIcons.tex(name, 18 if font_size < 20 else 24)
		b.custom_minimum_size = Vector2(28, font_size + 18)
		b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		b.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		b.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.pressed.connect(func() -> void:
			value.grab_focus()
			_cycle.call(dir))
		if dir > 0:
			_next = b
		return b

	func _show_arrows(on: bool) -> void:
		for a in [_prev, _next]:
			if a != null:
				a.modulate.a = 1.0 if on else 0.35

	func _on_input(event: InputEvent) -> void:
		if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
			_cycle.call(-1 if event.is_action_pressed("ui_left") else 1)
			value.accept_event()

	func set_value(t: String, color: Color = VrStyle.PAPER) -> void:
		value.text = t
		for k in ["font_color", "font_pressed_color", "font_hover_pressed_color"]:
			value.add_theme_color_override(k, color)
