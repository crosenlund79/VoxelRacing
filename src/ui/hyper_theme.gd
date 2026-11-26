class_name HyperTheme
extends RefCounted
## The shared VoxelRacing UI theme (the class keeps its inherited name so every
## screen picks it up): Pixel Operator typography (CC0), voxel-block buttons
## and panels from VrStyle, the VoxelRacing palette. Screens use the constants
## below, which now carry VoxelRacing's colours.

const UiJuice := preload("res://src/ui/ui_juice.gd")

const CREAM := VrStyle.PAPER
const CREAM_DIM := VrStyle.PAPER_DIM
const OUTLINE := VrStyle.INK
const GOLD := VrStyle.YELLOW
const RED := VrStyle.RED
const PANEL_TINT := Color(1, 1, 1, 0.95)
## Human player identity colours (HUD rows, results, car marker): Player 1 /
## the local player gold, Player 2 sky blue (matches the blue P2 car).
const P2_BLUE := VrStyle.SKY


## Colour of a human by player index (0 = Player 1 / you, 1 = Player 2).
static func player_color(index: int) -> Color:
	return P2_BLUE if index == 1 else GOLD


## Pixel Operator: bold from weight 600 up, regular below.
static func font(weight: int = 600) -> Font:
	return VrStyle.font("bold" if weight >= 600 else "regular")


static func build(_resolver: AssetResolver = null) -> Theme:
	var t := Theme.new()
	t.default_font = VrStyle.font("regular")
	t.default_font_size = 14
	for type in ["Label", "Button", "CheckButton", "LinkButton", "LineEdit"]:
		t.set_color("font_color", type, CREAM)
		t.set_color("font_outline_color", type, OUTLINE)
		t.set_constant("outline_size", type, 2)
	t.set_font("font", "Button", VrStyle.font("bold"))
	t.set_font_size("font_size", "Button", 18)
	t.set_color("font_hover_color", "Button", OUTLINE)
	t.set_color("font_focus_color", "Button", OUTLINE)
	t.set_color("font_hover_pressed_color", "Button", OUTLINE)
	t.set_color("font_pressed_color", "Button", CREAM)
	t.set_color("font_disabled_color", "Button", Color(CREAM, 0.45))
	t.set_constant("outline_size", "Button", 0)
	t.set_stylebox("normal", "Button", VrStyle.block(VrStyle.NIGHT_LIGHT))
	t.set_stylebox("hover", "Button", VrStyle.block(VrStyle.YELLOW))
	t.set_stylebox("focus", "Button", VrStyle.block(VrStyle.YELLOW))
	t.set_stylebox("pressed", "Button", VrStyle.block_pressed(VrStyle.RED))
	t.set_stylebox("hover_pressed", "Button", VrStyle.block_pressed(VrStyle.YELLOW))
	var off := VrStyle.block(VrStyle.NIGHT)
	off.modulate_color = Color(1, 1, 1, 0.5)
	t.set_stylebox("disabled", "Button", off)
	for state in ["normal", "hover", "pressed", "focus"]:
		t.set_stylebox(state, "CheckButton", StyleBoxEmpty.new())
	t.set_font("font", "CheckButton", VrStyle.font("bold"))
	t.set_font_size("font_size", "CheckButton", 18)
	t.set_stylebox("panel", "PanelContainer", VrStyle.panel())
	t.set_stylebox("panel", "Panel", VrStyle.panel())
	# sliders: an ink groove with a yellow fill and a little voxel block knob
	var groove := StyleBoxFlat.new()
	groove.bg_color = OUTLINE
	groove.border_color = VrStyle.NIGHT_LIGHT
	groove.set_border_width_all(2)
	groove.content_margin_top = 5
	groove.content_margin_bottom = 5
	t.set_stylebox("slider", "HSlider", groove)
	var fill := StyleBoxFlat.new()
	fill.bg_color = GOLD
	fill.content_margin_top = 5
	fill.content_margin_bottom = 5
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var knob := _knob(VrStyle.PAPER)
	t.set_icon("grabber", "HSlider", knob)
	t.set_icon("grabber_highlight", "HSlider", _knob(VrStyle.YELLOW))
	t.set_stylebox("scroll", "HScrollBar", _flat(Color(OUTLINE, 0.8)))
	t.set_stylebox("grabber", "HScrollBar", _flat(Color(GOLD, 0.8)))
	t.set_stylebox("grabber_highlight", "HScrollBar", _flat(GOLD))
	t.set_stylebox("grabber_pressed", "HScrollBar", _flat(GOLD))
	t.set_stylebox("scroll", "VScrollBar", _flat(Color(OUTLINE, 0.8)))
	t.set_stylebox("grabber", "VScrollBar", _flat(Color(GOLD, 0.8)))
	# text fields
	var field := StyleBoxFlat.new()
	field.bg_color = OUTLINE
	field.border_color = VrStyle.NIGHT_LIGHT
	field.set_border_width_all(3)
	field.content_margin_left = 10
	field.content_margin_right = 10
	field.content_margin_top = 6
	field.content_margin_bottom = 6
	t.set_stylebox("normal", "LineEdit", field)
	var field_focus := field.duplicate() as StyleBoxFlat
	field_focus.border_color = GOLD
	t.set_stylebox("focus", "LineEdit", field_focus)
	t.set_font_size("font_size", "LineEdit", 24)
	# progress bars: chequered fill
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = OUTLINE
	bar_bg.border_color = VrStyle.NIGHT_LIGHT
	bar_bg.set_border_width_all(2)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = GOLD
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	return t


## A small voxel-block slider knob.
static func _knob(face: Color) -> ImageTexture:
	var img := Image.create(18, 22, false, Image.FORMAT_RGBA8)
	img.fill(OUTLINE)
	img.fill_rect(Rect2i(2, 2, 14, 16), face.darkened(0.3))
	img.fill_rect(Rect2i(2, 2, 14, 12), face)
	img.fill_rect(Rect2i(2, 2, 14, 2), face.lightened(0.3))
	return ImageTexture.create_from_image(img)


static func _flat(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	return s


## Label helper: Pixel Operator at a pixel-grid size, ink outline.
static func label(text: String, size: int = 20, color: Color = CREAM, weight: int = 500) -> Label:
	var l := Label.new()
	l.text = text
	var px := VrStyle.px(size)
	l.add_theme_font_override("font", font(weight))
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", OUTLINE)
	l.add_theme_constant_override("outline_size", 3 if px >= 28 else 2)
	return l


# ------------------------------------------------- shared screen pieces
# One look for every screen: voxel-block buttons, a yellow title over a
# chequered rule, cream subtitles, and a deep ink shade behind overlays.

## The deep shade behind overlays (pause menu, ceremonies).
const SHADE := Color(0.06, 0.06, 0.16, 0.66)


## Styles a button like the main menu's: 24 px type (32 for the primary
## action), voxel-block heights, and the shared button juice (focus pop,
## pressed squash, pulsing focus edge: UiJuice).
static func style_button(b: Button, primary: bool = false, width: float = 380.0) -> Button:
	b.custom_minimum_size = Vector2(width, 64 if primary else 50)
	b.add_theme_font_size_override("font_size", 32 if primary else 24)
	if primary:
		b.add_theme_stylebox_override("normal", VrStyle.block(VrStyle.RED))
		b.add_theme_color_override("font_color", CREAM)
	UiJuice.button(b)
	return b


## A screen heading: a yellow title, an optional cream subtitle and a
## chequered rule, as one VBox (place it where the screen's title goes).
static func heading(title: String, subtitle: String = "", size: int = 46) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var t := label(title, size, GOLD, 700)
	t.name = "Title"
	box.add_child(t)
	var rule := TextureRect.new()
	rule.name = "Rule"
	rule.texture = VrStyle.checker(28, 2, 4)
	rule.custom_minimum_size = Vector2(224, 8)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(rule)
	var s := label(subtitle, 24, CREAM, 500)
	s.name = "Subtitle"
	s.visible = subtitle != ""
	box.add_child(s)
	return box


## A short fade-and-rise for a panel appearing (shared timing: 0.22 s).
static func reveal(node: CanvasItem) -> void:
	if not node.is_inside_tree():
		return
	node.modulate.a = 0.0
	var tw := node.create_tween()
	tw.tween_property(node, "modulate:a", 1.0, 0.22)
