class_name SettingsPanel
extends PanelContainer
## Settings (Prototype 005, compact and icon-first): the five volumes (an icon,
## a slider, the value and a mute toggle each); a graphics & display row: the
## quality preset, the window resolution and the display mode (GraphicsSettings),
## then dynamic vehicle lights and the player's headlight colour; and a row for
## tooltips (on / off, delay, duration) and the input device. Value buttons
## show their icon and value and cycle with a press or Left / Right. Short
## tooltips explain each icon. Changes apply immediately and are saved.

signal closed
## The input device row was pressed (the title opens the device picker).
signal device_requested

const VrWidgets := preload("res://src/ui/vr_widgets.gd")
const VrTips := preload("res://src/ui/vr_tips.gd")

## The font size of the values on the value buttons.
const VALUE_FONT := 14
const BUS_ICONS := {"Master": "master", "Music": "music", "Engine": "engine", "Effects": "effects", "Voice": "voice"}

var settings: AudioSettings
var _sliders: Dictionary = {}
var _mutes: Dictionary = {}
var _back: Button
var _lights: Button
var _headlights: Button
var _quality: Button
var _resolution: Button
var _mode: Button
var _tips: Button
var _delay: Button
var _duration: Button
var _device: Button


func setup(p_settings: AudioSettings) -> void:
	settings = p_settings
	VrTips.load_prefs(settings.path)
	GraphicsSettings.load_prefs(settings.path)
	add_theme_stylebox_override("panel", VrWidgets.panel(0.9))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	_back = VrWidgets.icon_button("back", "Back", 34)
	_back.pressed.connect(func() -> void: closed.emit())
	head.add_child(_back)
	head.add_child(VrWidgets.icon("settings", 24))
	head.add_child(VrWidgets.text("Settings", 20, VrStyle.YELLOW))
	box.add_child(head)
	var grid := GridContainer.new()
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	for bus in AudioSettings.BUSES:
		var ic := VrWidgets.icon(BUS_ICONS.get(bus, "effects"), 24)
		ic.mouse_filter = Control.MOUSE_FILTER_PASS
		VrTips.tip(ic, "%s volume" % bus)
		grid.add_child(ic)
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 5
		slider.custom_minimum_size = Vector2(240, 24)
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.value = settings.volume[bus] * 100.0
		VrTips.tip(slider, "%s volume" % bus)
		grid.add_child(slider)
		var value := VrWidgets.text("%d" % int(slider.value), 15, VrStyle.PAPER_DIM)
		value.custom_minimum_size = Vector2(36, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(value)
		var mute := VrWidgets.icon_button("mute" if settings.muted[bus] else BUS_ICONS.get(bus, "effects"), "Mute", 34)
		mute.toggle_mode = true
		mute.button_pressed = settings.muted[bus]
		_mute_look(mute, bus)
		grid.add_child(mute)
		slider.value_changed.connect(func(v: float) -> void:
			value.text = "%d" % int(v)
			settings.set_volume(bus, v / 100.0)
			settings.save_settings())
		mute.toggled.connect(func(on: bool) -> void:
			settings.set_muted(bus, on)
			settings.save_settings()
			_mute_look(mute, bus))
		_sliders[bus] = slider
		_mutes[bus] = mute
	# graphics & display: quality, resolution, display mode | the vehicle lights
	var video := _row(box)
	_quality = _value_button("quality", "Graphics quality", _preset_names())
	_on_cycle(_quality, func(step: int) -> void: _cycle_quality(step))
	video.add_child(_quality)
	_resolution = _value_button("display", func() -> String:
		return "Screen size" if GraphicsSettings.fullscreen() else "Window size", _resolution_names())
	_on_cycle(_resolution, func(step: int) -> void: _cycle_resolution(step))
	video.add_child(_resolution)
	_mode = _value_button("windowed", "Display mode", GraphicsSettings.MODE_NAMES.values())
	_on_cycle(_mode, func(step: int) -> void: _cycle_mode(step))
	video.add_child(_mode)
	_show_display()
	video.add_child(_gap())
	_lights = VrWidgets.icon_button("lights", func() -> String:
		return "Vehicle lights on" if settings.vehicle_lights else "Vehicle lights off", 44)
	_lights.toggle_mode = true
	_lights.button_pressed = settings.vehicle_lights
	_lights.toggled.connect(func(on: bool) -> void:
		settings.vehicle_lights = on
		settings.save_settings()
		_toggle_look(_lights, on))
	_toggle_look(_lights, settings.vehicle_lights)
	video.add_child(_lights)
	var names: Array = []
	for c in LightingPilot.HEADLIGHT_PALETTE:
		names.append(c[0])
	_headlights = _value_button("lights", "Headlight colour", names)
	_on_cycle(_headlights, func(step: int) -> void: _cycle_headlights(step))
	_show_headlights()
	video.add_child(_headlights)
	# tooltips: on / off, delay, duration | the input device
	var row := _row(box)
	_tips = VrWidgets.icon_button("tooltip", func() -> String: return "Tooltips on" if VrTips.enabled else "Tooltips off", 44)
	_tips.toggle_mode = true
	_tips.button_pressed = VrTips.enabled
	_tips.toggled.connect(func(on: bool) -> void:
		VrTips.enabled = on
		VrTips.save_prefs(settings.path)
		_toggle_look(_tips, on)
		_tip_times_look())
	_toggle_look(_tips, VrTips.enabled)
	row.add_child(_tips)
	_delay = _value_button("delay", "Tooltip delay", _times(VrTips.DELAY_OPTIONS))
	_on_cycle(_delay, func(step: int) -> void: _cycle_delay(step))
	row.add_child(_delay)
	_duration = _value_button("duration", "Tooltip duration", _times(VrTips.DURATION_OPTIONS))
	_on_cycle(_duration, func(step: int) -> void: _cycle_duration(step))
	row.add_child(_duration)
	_tip_times_look()
	_show_tip_times()
	row.add_child(_gap())
	_device = _value_button("keyboard", "Input device", ["Keyboard", "Gamepad"])
	_device.pressed.connect(func() -> void: device_requested.emit())
	row.add_child(_device)
	refresh_device()


func _row(box: VBoxContainer) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	return row


## A compact value button: its icon, then the value, wide enough for the
## longest of its values (so nothing is clipped and it never changes size).
func _value_button(icon: String, tip: Variant, values: Array) -> Button:
	var b := VrWidgets.icon_button(icon, tip, 44, "", VALUE_FONT)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	var font := VrStyle.font("regular")
	var w := 0.0
	for v in values:
		w = maxf(w, font.get_string_size(str(v).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, VALUE_FONT).x)
	# chip margins (8 + 8), the 32 px icon, the icon-text gap (8), a little air
	b.custom_minimum_size = Vector2(ceilf(8 + 32 + 8 + w + 8 + 6), 44)
	return b


## A value button cycles forwards when pressed, both ways with Left / Right.
func _on_cycle(b: Button, cycle: Callable) -> void:
	b.set_meta("cycle", cycle)
	b.pressed.connect(func() -> void: cycle.call(1))
	b.gui_input.connect(func(e: InputEvent) -> void:
		if e.is_action_pressed("ui_left") or e.is_action_pressed("ui_right"):
			if not b.disabled:
				cycle.call(-1 if e.is_action_pressed("ui_left") else 1)
			b.accept_event())


func _gap() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(10, 0)
	return c


## A toggle's look: full colour when on, dimmed when off.
func _toggle_look(b: Button, on: bool) -> void:
	VrWidgets.set_icon(b, str(b.get_meta("vr_icon")), "normal" if on else "dim")
	b.modulate = Color.WHITE if on else Color(1, 1, 1, 0.75)


func _mute_look(b: Button, bus: String) -> void:
	VrWidgets.set_icon(b, "mute" if b.button_pressed else BUS_ICONS.get(bus, "effects"), "normal")


## The input device row shows the chosen device's icon and name.
func refresh_device() -> void:
	if _device == null:
		return
	var pad := PlayerControls.device_kind == PlayerControls.DEVICE_GAMEPAD
	VrWidgets.set_icon(_device, "gamepad" if pad else "keyboard")
	_device.text = "Gamepad" if pad else "Keyboard"


func _cycle_delay(step: int) -> void:
	var opts := VrTips.DELAY_OPTIONS
	var i := opts.find(VrTips.delay)
	VrTips.delay = opts[posmod((i if i >= 0 else 1) + step, opts.size())]
	VrTips.save_prefs(settings.path)
	_show_tip_times()


func _cycle_duration(step: int) -> void:
	var opts := VrTips.DURATION_OPTIONS
	var i := opts.find(VrTips.duration)
	VrTips.duration = opts[posmod((i if i >= 0 else 1) + step, opts.size())]
	VrTips.save_prefs(settings.path)
	_show_tip_times()


func _show_tip_times() -> void:
	_delay.text = "%ss" % _num(VrTips.delay)
	_duration.text = "%ss" % _num(VrTips.duration)


## The delay and duration only matter while tooltips are on: greyed out when off.
func _tip_times_look() -> void:
	for b in [_delay, _duration]:
		(b as Button).disabled = not VrTips.enabled
		VrWidgets.set_icon(b, str(b.get_meta("vr_icon")), "normal" if VrTips.enabled else "disabled")


static func _num(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, round(v)) else "%.1f" % v


func _cycle_headlights(step: int) -> void:
	settings.headlight_color = posmod(settings.headlight_color + step, LightingPilot.HEADLIGHT_PALETTE.size())
	settings.save_settings()
	_show_headlights()


func _show_headlights() -> void:
	_headlights.text = LightingPilot.headlight_name(settings.headlight_color)
	var c := LightingPilot.headlight_color(settings.headlight_color)
	for k in ["font_color", "font_hover_color", "font_focus_color"]:
		_headlights.add_theme_color_override(k, c)


# ------------------------------------------------------------ graphics & display

static func _preset_names() -> Array:
	var out: Array = []
	for p in GraphicsSettings.PRESETS:
		out.append(GraphicsSettings.PRESET_NAMES[p])
	return out


static func _resolution_names() -> Array:
	var out: Array = [GraphicsSettings.size_text(GraphicsSettings.screen_size())]
	for r in GraphicsSettings.resolutions():
		out.append(GraphicsSettings.size_text(r))
	return out


static func _times(opts: Array[float]) -> Array:
	var out: Array = []
	for v in opts:
		out.append("%ss" % _num(v))
	return out


func _cycle_quality(step: int) -> void:
	var opts := GraphicsSettings.PRESETS
	var i := opts.find(GraphicsSettings.quality)
	GraphicsSettings.quality = opts[posmod((i if i >= 0 else opts.size() - 1) + step, opts.size())]
	GraphicsSettings.save_prefs(settings.path)
	GraphicsSettings.apply_quality()
	_show_display()


## Windowed: the window size. Fullscreen: the screen's own size (the picture
## scales to it), so the button only shows it.
func _cycle_resolution(step: int) -> void:
	if GraphicsSettings.fullscreen():
		return
	var opts := GraphicsSettings.resolutions()
	var i := opts.find(GraphicsSettings.window_size())
	if i < 0:  # an unlisted size: start from the nearest smaller one
		i = 0
		for k in opts.size():
			if opts[k].x * opts[k].y <= GraphicsSettings.window_size().x * GraphicsSettings.window_size().y:
				i = k
	GraphicsSettings.resolution = opts[posmod(i + step, opts.size())]
	GraphicsSettings.save_prefs(settings.path)
	GraphicsSettings.apply_display()
	_show_display()


func _cycle_mode(step: int) -> void:
	var opts := GraphicsSettings.MODES
	var i := opts.find(GraphicsSettings.mode)
	GraphicsSettings.mode = opts[posmod((i if i >= 0 else 0) + step, opts.size())]
	GraphicsSettings.save_prefs(settings.path)
	GraphicsSettings.apply_display()
	_show_display()


func _show_display() -> void:
	_quality.text = GraphicsSettings.PRESET_NAMES.get(GraphicsSettings.quality, "Ultra")
	var full := GraphicsSettings.fullscreen()
	_resolution.text = GraphicsSettings.size_text(GraphicsSettings.screen_size() if full else GraphicsSettings.window_size())
	_resolution.disabled = full
	VrWidgets.set_icon(_resolution, "display", "disabled" if full else "normal")
	_mode.text = GraphicsSettings.MODE_NAMES.get(GraphicsSettings.mode, "Windowed")
	VrWidgets.set_icon(_mode, GraphicsSettings.MODE_ICONS.get(GraphicsSettings.mode, "windowed"))


func headlights_button() -> Button:
	return _headlights


func focus_first() -> void:
	_sliders["Master"].grab_focus()


func slider(bus: String) -> HSlider:
	return _sliders[bus]


func lights_toggle() -> Button:
	return _lights


func mute_toggle(bus: String) -> Button:
	return _mutes[bus]
