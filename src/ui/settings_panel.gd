class_name SettingsPanel
extends PanelContainer
## Settings: Master, Music, Engine, Effects and Voice volume with mute toggles,
## DYNAMIC VEHICLE LIGHTS ON / OFF (night races; off = cheap glow sprites),
## the player's HEADLIGHTS colour (Left / Right or press to change) and
## the Artwork Mode (original template artwork only; applies after a restart).
## Changes apply immediately and are saved.

signal closed

var settings: AudioSettings
var _sliders: Dictionary = {}
var _mutes: Dictionary = {}
var _back: Button
var _lights: CheckButton
var _headlights: Button
var _artwork: CheckButton


func setup(p_settings: AudioSettings) -> void:
	settings = p_settings
	custom_minimum_size = Vector2(720, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	var title := HyperTheme.label("SETTINGS", 34, HyperTheme.GOLD, 700)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(grid)
	for bus in AudioSettings.BUSES:
		var name := HyperTheme.label(bus.to_upper(), 22, HyperTheme.CREAM, 600)
		name.custom_minimum_size = Vector2(120, 0)
		grid.add_child(name)
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 5
		slider.custom_minimum_size = Vector2(260, 28)
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.value = settings.volume[bus] * 100.0
		grid.add_child(slider)
		var value := HyperTheme.label("%d%%" % int(slider.value), 20, HyperTheme.CREAM_DIM, 500)
		value.custom_minimum_size = Vector2(60, 0)
		grid.add_child(value)
		var mute := CheckButton.new()
		mute.text = "Mute"
		mute.custom_minimum_size = Vector2(110, 0)
		mute.button_pressed = settings.muted[bus]
		grid.add_child(mute)
		slider.value_changed.connect(func(v: float) -> void:
			value.text = "%d%%" % int(v)
			settings.set_volume(bus, v / 100.0)
			settings.save_settings())
		mute.toggled.connect(func(on: bool) -> void:
			settings.set_muted(bus, on)
			settings.save_settings())
		_sliders[bus] = slider
		_mutes[bus] = mute
	_lights = CheckButton.new()
	_lights.text = "DYNAMIC VEHICLE LIGHTS"
	_lights.tooltip_text = "Night races: real headlights, brake lights and high beams. Off = simple glows (faster)."
	_lights.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_lights.button_pressed = settings.vehicle_lights
	_lights.toggled.connect(func(on: bool) -> void:
		settings.vehicle_lights = on
		settings.save_settings())
	box.add_child(_lights)
	_headlights = Button.new()
	_headlights.tooltip_text = "Night races: the colour of your own headlights (a subtle tint; rivals keep the standard colour, rear lights stay red)."
	_headlights.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_headlights.set_meta("cycle", func(step: int) -> void: _cycle_headlights(step))
	_headlights.pressed.connect(func() -> void: _cycle_headlights(1))
	_show_headlights()
	box.add_child(_headlights)
	_artwork = CheckButton.new()
	_artwork.text = "ORIGINAL TEMPLATE ARTWORK (after restart)"
	_artwork.tooltip_text = "Off (Custom): your own drawings where you have made them. On: only the original template graphics."
	_artwork.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_artwork.button_pressed = settings.original_artwork
	_artwork.toggled.connect(func(on: bool) -> void:
		settings.original_artwork = on
		settings.save_settings())
	box.add_child(_artwork)
	var hint := HyperTheme.label("Left / Right adjust the focused slider. Settings are saved automatically.", 16, HyperTheme.CREAM_DIM, 500)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	_back = Button.new()
	_back.text = "BACK"
	_back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_back.pressed.connect(func() -> void: closed.emit())
	box.add_child(_back)


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _headlights == null or not _headlights.has_focus():
		return
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		_cycle_headlights(-1 if event.is_action_pressed("ui_left") else 1)
		get_viewport().set_input_as_handled()


func _cycle_headlights(step: int) -> void:
	settings.headlight_color = posmod(settings.headlight_color + step, LightingPilot.HEADLIGHT_PALETTE.size())
	settings.save_settings()
	_show_headlights()


func _show_headlights() -> void:
	_headlights.text = "HEADLIGHTS: < %s >" % LightingPilot.headlight_name(settings.headlight_color)
	_headlights.add_theme_color_override("font_color", LightingPilot.headlight_color(settings.headlight_color))


func headlights_button() -> Button:
	return _headlights


func focus_first() -> void:
	_sliders["Master"].grab_focus()


func slider(bus: String) -> HSlider:
	return _sliders[bus]


func artwork_toggle() -> CheckButton:
	return _artwork


func lights_toggle() -> CheckButton:
	return _lights


func mute_toggle(bus: String) -> CheckButton:
	return _mutes[bus]
