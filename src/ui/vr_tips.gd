extends CanvasLayer
## Short, optional tooltips (Prototype 005): two or three words next to a
## highlighted icon or control ("Night race", "3 laps", "Repair car").
## A control gets one with VrTips.tip(control, "Night race") (or a Callable
## returning the text, for values that change). The tip appears after `delay`
## seconds of the control being hovered with the mouse or focused with the
## keyboard / a controller, stays `duration` seconds, and disappears when the
## highlight moves on. Preferences (on / off, delay, duration) live in Settings
## and are saved in user://settings.cfg [ui]. One tooltip layer for the whole
## game, created on first use. Loaded with preload (no class_name).

const SETTINGS_PATH := "user://settings.cfg"
const DELAY_OPTIONS: Array[float] = [0.2, 0.5, 1.0, 1.5]
const DURATION_OPTIONS: Array[float] = [1.0, 2.0, 3.0, 5.0]

static var enabled := true
static var delay := 0.5
static var duration := 2.0
static var _layer: CanvasLayer
static var _loaded := false

var _panel: PanelContainer
var _label: Label
var _target: Control
var _t := 0.0
var _mouse := false
var _shown := false
var _tween: Tween


## Gives a control a tooltip: a short String, or a Callable returning one.
## Returns the control (for chaining while building a screen).
static func tip(c: Control, text: Variant) -> Control:
	c.set_meta("vr_tip", text)
	_ensure()
	return c


static func load_prefs(path: String = SETTINGS_PATH) -> void:
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	enabled = bool(cfg.get_value("ui", "tooltips", true))
	delay = clampf(float(cfg.get_value("ui", "tooltip_delay", 0.5)), 0.0, 5.0)
	duration = clampf(float(cfg.get_value("ui", "tooltip_duration", 2.0)), 0.5, 30.0)


static func save_prefs(path: String = SETTINGS_PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value("ui", "tooltips", enabled)
	cfg.set_value("ui", "tooltip_delay", delay)
	cfg.set_value("ui", "tooltip_duration", duration)
	cfg.save(path)


static func _ensure() -> void:
	if not _loaded:
		load_prefs()
	if _layer != null and is_instance_valid(_layer):
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	_layer = load("res://src/ui/vr_tips.gd").new()
	tree.root.add_child.call_deferred(_layer)


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(VrStyle.INK, 0.94)
	sb.border_color = Color(VrStyle.PAPER, 0.22)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 4
	sb.content_margin_bottom = 5
	sb.shadow_color = Color(0, 0, 0, 0.3)
	sb.shadow_size = 3
	sb.shadow_offset = Vector2(0, 2)
	_panel.add_theme_stylebox_override("panel", sb)
	_label = Label.new()
	_label.add_theme_font_override("font", VrStyle.font("regular"))
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", VrStyle.PAPER)
	_panel.add_child(_label)
	_panel.visible = false
	add_child(_panel)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > 0.5:
		_mouse = true
	elif event is InputEventKey or event is InputEventJoypadButton \
			or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5):
		_mouse = false


## The control with a tooltip under the highlight (itself or a near parent).
func _tipped(c: Control) -> Control:
	var n: Node = c
	for k in 3:
		if n == null or not (n is Control):
			return null
		if n.has_meta("vr_tip"):
			return n as Control
		n = n.get_parent()
	return null


func _process(delta: float) -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var c: Control = vp.gui_get_hovered_control() if _mouse else vp.gui_get_focus_owner()
	var target := _tipped(c) if c != null else null
	if target != _target:
		_target = target
		_t = 0.0
		_hide()
	if _target == null or not is_instance_valid(_target) or not _target.is_visible_in_tree() or not enabled:
		_hide()
		return
	_t += delta
	if _t >= delay and _t < delay + duration:
		if not _shown:
			_show()
	elif _shown:
		_hide()


func _text() -> String:
	var v: Variant = _target.get_meta("vr_tip", "")
	if v is Callable:
		v = (v as Callable).call()
	return str(v)


func _show() -> void:
	var text := _text()
	if text.is_empty():
		return
	_label.text = text
	_panel.reset_size()
	var s := _panel.get_combined_minimum_size()
	_panel.size = s
	var r := _target.get_global_rect()
	var xf := _target.get_viewport_transform() if _target.get_viewport() != get_viewport() else Transform2D.IDENTITY
	r = xf * r
	var screen := Vector2(1280, 720)
	var pos := Vector2(r.position.x + (r.size.x - s.x) * 0.5, r.end.y + 6.0)
	if pos.y + s.y > screen.y - 4.0:  # no room below: above it
		pos.y = r.position.y - s.y - 6.0
	pos.x = clampf(pos.x, 4.0, screen.x - s.x - 4.0)
	pos.y = clampf(pos.y, 4.0, screen.y - s.y - 4.0)
	_panel.position = pos
	_panel.visible = true
	_shown = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_panel.modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(_panel, "modulate:a", 1.0, 0.12)


func _hide() -> void:
	if not _shown:
		return
	_shown = false
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_panel.visible = false
