class_name SettingsPanel
extends PanelContainer
## Settings (Prototype 005, compact and icon-first): the five volumes (an icon,
## a slider, the value and a mute toggle each), then one row of small icon
## toggles: dynamic vehicle lights, the player's headlight colour, original
## template artwork (after a restart), tooltips on / off with their delay and
## duration, and the input device. Short tooltips explain each icon. Changes
## apply immediately and are saved.

signal closed
## The input device row was pressed (the title opens the device picker).
signal device_requested

const VrWidgets := preload("res://src/ui/vr_widgets.gd")
const VrTips := preload("res://src/ui/vr_tips.gd")

const BUS_ICONS := {"Master": "master", "Music": "music", "Engine": "engine", "Effects": "effects", "Voice": "voice"}

var settings: AudioSettings
var _sliders: Dictionary = {}
var _mutes: Dictionary = {}
var _back: Button
var _lights: Button
var _headlights: Button
var _artwork: Button
var _tips: Button
var _delay: Button
var _duration: Button
var _device: Button


func setup(p_settings: AudioSettings) -> void:
	settings = p_settings
	VrTips.load_prefs(settings.path)
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
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	_lights = VrWidgets.icon_button("lights", func() -> String:
		return "Vehicle lights on" if settings.vehicle_lights else "Vehicle lights off", 44)
	_lights.toggle_mode = true
	_lights.button_pressed = settings.vehicle_lights
	_lights.toggled.connect(func(on: bool) -> void:
		settings.vehicle_lights = on
		settings.save_settings()
		_toggle_look(_lights, on))
	_toggle_look(_lights, settings.vehicle_lights)
	row.add_child(_lights)
	_headlights = VrWidgets.icon_button("lights", "Headlight colour", 44, "", 14)
	_headlights.set_meta("cycle", func(step: int) -> void: _cycle_headlights(step))
	_headlights.pressed.connect(func() -> void: _cycle_headlights(1))
	_headlights.gui_input.connect(func(e: InputEvent) -> void:
		if e.is_action_pressed("ui_left") or e.is_action_pressed("ui_right"):
			_cycle_headlights(-1 if e.is_action_pressed("ui_left") else 1)
			_headlights.accept_event())
	_show_headlights()
	row.add_child(_headlights)
	_artwork = VrWidgets.icon_button("artwork", func() -> String:
		return "Original artwork (restart)" if settings.original_artwork else "Custom artwork", 44)
	_artwork.toggle_mode = true
	_artwork.button_pressed = settings.original_artwork
	_artwork.toggled.connect(func(on: bool) -> void:
		settings.original_artwork = on
		settings.save_settings()
		_toggle_look(_artwork, on))
	_toggle_look(_artwork, settings.original_artwork)
	row.add_child(_artwork)
	row.add_child(_gap())
	_tips = VrWidgets.icon_button("tooltip", func() -> String: return "Tooltips on" if VrTips.enabled else "Tooltips off", 44)
	_tips.toggle_mode = true
	_tips.button_pressed = VrTips.enabled
	_tips.toggled.connect(func(on: bool) -> void:
		VrTips.enabled = on
		VrTips.save_prefs(settings.path)
		_toggle_look(_tips, on)
		_delay.disabled = not on
		_duration.disabled = not on)
	_toggle_look(_tips, VrTips.enabled)
	row.add_child(_tips)
	_delay = VrWidgets.icon_button("delay", "Tooltip delay", 44, "", 14)
	_delay.pressed.connect(func() -> void: _cycle_delay(1))
	_delay.gui_input.connect(func(e: InputEvent) -> void:
		if e.is_action_pressed("ui_left") or e.is_action_pressed("ui_right"):
			_cycle_delay(-1 if e.is_action_pressed("ui_left") else 1)
			_delay.accept_event())
	row.add_child(_delay)
	_duration = VrWidgets.icon_button("duration", "Tooltip duration", 44, "", 14)
	_duration.pressed.connect(func() -> void: _cycle_duration(1))
	_duration.gui_input.connect(func(e: InputEvent) -> void:
		if e.is_action_pressed("ui_left") or e.is_action_pressed("ui_right"):
			_cycle_duration(-1 if e.is_action_pressed("ui_left") else 1)
			_duration.accept_event())
	row.add_child(_duration)
	_delay.disabled = not VrTips.enabled
	_duration.disabled = not VrTips.enabled
	_show_tip_times()
	row.add_child(_gap())
	_device = VrWidgets.icon_button("keyboard", "Input device", 44, "", 14)
	_device.pressed.connect(func() -> void: device_requested.emit())
	row.add_child(_device)
	refresh_device()


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


func headlights_button() -> Button:
	return _headlights


func focus_first() -> void:
	_sliders["Master"].grab_focus()


func slider(bus: String) -> HSlider:
	return _sliders[bus]


func artwork_toggle() -> Button:
	return _artwork


func lights_toggle() -> Button:
	return _lights


func mute_toggle(bus: String) -> Button:
	return _mutes[bus]
