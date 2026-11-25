class_name HyperTheme
extends RefCounted
## The shared HyperCars UI theme: Fredoka (SIL OFL 1.1) typography, painted
## nine-patch buttons and panels from replaceable textures, warm cream text.

const FONT_PATH := "res://assets/fonts/Fredoka.ttf"
const CREAM := Color("f3e8cf")
const CREAM_DIM := Color("f3e8cf", 0.6)
const OUTLINE := Color("2a2220")
const GOLD := Color("e2b23c")
const RED := Color("b23a22")
const PANEL_TINT := Color(1, 1, 1, 0.96)
## Human player identity colours (HUD rows, results, car marker): Player 1 /
## the local player gold, Player 2 sky blue (matches the blue P2 car).
const P2_BLUE := Color("74bdf2")


## Colour of a human by player index (0 = Player 1 / you, 1 = Player 2).
static func player_color(index: int) -> Color:
	return P2_BLUE if index == 1 else GOLD

## Fredoka at a weight (300 light .. 700 bold). The font file itself is cached
## by the resource loader; the small variation wrapper is created per use.
static func font(weight: int = 600) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = load(FONT_PATH)
	f.variation_opentype = {"wght": weight}
	return f


static func build(resolver: AssetResolver) -> Theme:
	var t := Theme.new()
	t.default_font = font(500)
	t.default_font_size = 20
	for type in ["Label", "Button", "CheckButton", "LinkButton"]:
		t.set_color("font_color", type, CREAM)
		t.set_color("font_outline_color", type, OUTLINE)
		t.set_constant("outline_size", type, 6)
	t.set_font("font", "Button", font(600))
	t.set_font_size("font_size", "Button", 24)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", GOLD)
	var button_tex := resolver.get_texture(AssetCatalog.BUTTON)
	var margin := int(AssetCatalog.SPECS[AssetCatalog.BUTTON].patch_margin * button_tex.get_width() / 96.0)
	t.set_stylebox("normal", "Button", _button_box(button_tex, margin, Color(1, 1, 1, 0.92)))
	t.set_stylebox("hover", "Button", _button_box(button_tex, margin, Color(1.25, 1.18, 1.1)))
	t.set_stylebox("pressed", "Button", _button_box(button_tex, margin, Color(0.8, 0.75, 0.72)))
	var focus := _button_box(button_tex, margin, Color(1.35, 1.2, 0.85))
	t.set_stylebox("focus", "Button", focus)
	t.set_stylebox("disabled", "Button", _button_box(button_tex, margin, Color(1, 1, 1, 0.4)))
	t.set_stylebox("normal", "CheckButton", StyleBoxEmpty.new())
	var panel_tex := resolver.get_texture(AssetCatalog.HUD_PANEL)
	var panel := StyleBoxTexture.new()
	panel.texture = panel_tex
	var pm := int(AssetCatalog.SPECS[AssetCatalog.HUD_PANEL].patch_margin * panel_tex.get_width() / 96.0)
	panel.set_texture_margin_all(pm)
	panel.set_content_margin_all(22)
	panel.modulate_color = PANEL_TINT
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	var slider := StyleBoxFlat.new()
	slider.bg_color = Color("3a302a")
	slider.set_corner_radius_all(6)
	slider.content_margin_top = 4
	slider.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", slider)
	var fill := StyleBoxFlat.new()
	fill.bg_color = GOLD
	fill.set_corner_radius_all(6)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var bar := StyleBoxFlat.new()
	bar.bg_color = Color(GOLD, 0.7)
	bar.set_corner_radius_all(4)
	t.set_stylebox("scroll", "HScrollBar", _flat(Color("3a302a", 0.8)))
	t.set_stylebox("grabber", "HScrollBar", bar)
	t.set_stylebox("grabber_highlight", "HScrollBar", _flat(GOLD))
	t.set_stylebox("grabber_pressed", "HScrollBar", _flat(GOLD))
	return t


static func _button_box(tex: Texture2D, margin: int, tint: Color) -> StyleBoxTexture:
	var b := StyleBoxTexture.new()
	b.texture = tex
	b.set_texture_margin_all(margin)
	b.content_margin_left = 28
	b.content_margin_right = 28
	b.content_margin_top = 8
	b.content_margin_bottom = 10
	b.modulate_color = tint
	return b


static func _flat(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(4)
	return s


## Label helper with the theme font and an optional size/colour.
static func label(text: String, size: int = 20, color: Color = CREAM, weight: int = 500) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", OUTLINE)
	l.add_theme_constant_override("outline_size", maxi(4, size / 4))
	return l


# ------------------------------------------------- shared screen pieces (2026-11-23)
# One look for every screen, taken from the main menu: wooden buttons with the
# main menu's margins and type sizes, a gold title with a thin gold rule under
# it, cream subtitles, and the dark warm shade behind overlays.

## The dark warm shade behind overlays (pause menu, ceremonies).
const SHADE := Color(0.11, 0.09, 0.08, 0.62)


## Styles a button like the main menu's: 20 px type (28 for the primary
## action), the main menu's content margins and height.
static func style_button(b: Button, primary: bool = false, width: float = 380.0) -> Button:
	b.custom_minimum_size = Vector2(width, 58 if primary else 40)
	b.add_theme_font_size_override("font_size", 28 if primary else 20)
	var theme := b.theme if b.theme != null else null
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb: StyleBox = b.get_theme_stylebox(state, "Button")
		if sb == null and theme != null:
			sb = theme.get_stylebox(state, "Button")
		if sb != null:
			sb = sb.duplicate()
			sb.content_margin_top = 4
			sb.content_margin_bottom = 6
			b.add_theme_stylebox_override(state, sb)
	return b


## A screen heading: a gold title, an optional cream subtitle and a thin gold
## rule, as one VBox (place it where the screen's title goes).
static func heading(title: String, subtitle: String = "", size: int = 46) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var t := label(title, size, GOLD, 700)
	t.name = "Title"
	box.add_child(t)
	var rule := ColorRect.new()
	rule.name = "Rule"
	rule.color = Color(GOLD, 0.7)
	rule.custom_minimum_size = Vector2(220, 3)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(rule)
	var s := label(subtitle, 20, CREAM, 600)
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
