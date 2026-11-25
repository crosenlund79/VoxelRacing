class_name NemesisWelcome
extends CanvasLayer
## Nemesis Welcome (2026-11-17): a rival greets the player at the title with a
## short taunt about something that really happened (RivalMemory). No
## portraits: the car is the character, drawn in its current look (its own
## colours, or the shared junker while the player owns its car; art overrides
## apply). Compact, slides in at the bottom left, never blocks the menus: any
## key, button or click dismisses it (the input still reaches the menu), and
## it leaves by itself after SHOW_TIME. A recorded laugh / line plays when the
## rival has a fitting one (NemesisLines.SMUG_CLIPS); otherwise it is text only.

signal dismissed

const SHOW_TIME := 9.0
const LEFT := 24.0
const BOTTOM := 24.0
## Music dip while the rival's clip plays (dB), like the voice director's ducking.
const DUCK_DB := -7.0

var greeting: Dictionary = {}
var _panel: PanelContainer
var _car: TextureRect
var _title: Label
var _opener: Label
var _reaction: Label
var _taunt: Label
var _voice: AudioStreamPlayer
var _tween: Tween
var _shown := false
var _duck: AudioEffectAmplify = null


func setup(resolver: AssetResolver, p_greeting: Dictionary, car_texture: Texture2D) -> void:
	greeting = p_greeting
	layer = 44
	var root := Control.new()
	root.theme = HyperTheme.build(resolver)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			dismiss())
	root.add_child(_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_panel.add_child(row)
	_car = TextureRect.new()
	_car.texture = car_texture
	_car.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_car.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_car.custom_minimum_size = Vector2(112, 63)
	_car.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_car)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	row.add_child(text)
	_title = HyperTheme.label(greeting.get("title", ""), 15, HyperTheme.GOLD, 700)
	text.add_child(_title)
	_opener = HyperTheme.label('"%s"' % greeting.get("opener", ""), 21, HyperTheme.CREAM, 700)
	text.add_child(_opener)
	_reaction = HyperTheme.label(greeting.get("reaction", ""), 15, HyperTheme.CREAM_DIM, 500)
	text.add_child(_reaction)
	_taunt = HyperTheme.label('"%s"' % greeting.get("taunt", ""), 19, HyperTheme.CREAM, 600)
	_taunt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_taunt.custom_minimum_size = Vector2(430, 0)
	text.add_child(_taunt)
	var hint := HyperTheme.label("any key or click to dismiss", 12, HyperTheme.CREAM_DIM, 500)
	text.add_child(hint)
	_voice = AudioStreamPlayer.new()
	_voice.bus = "Voice"
	add_child(_voice)
	var clip: String = greeting.get("clip", "")
	if clip != "":
		_voice.stream = resolver.get_voice(clip)  # (null when missing: the greeting stays text only)
	_voice.finished.connect(_unduck)
	_panel.visible = false


func show_greeting() -> void:
	_shown = true
	_panel.visible = true
	_panel.reset_size()
	var h := _panel.get_combined_minimum_size().y
	_panel.position = Vector2(-_panel.get_combined_minimum_size().x - 20.0, 720.0 - h - BOTTOM)
	_tween = create_tween()
	_tween.tween_property(_panel, "position:x", LEFT, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_interval(SHOW_TIME)
	_tween.tween_callback(dismiss)
	if _voice.stream != null:
		_duck_music()
		_voice.play()


func showing() -> bool:
	return _shown and _panel.visible


func text_lines() -> PackedStringArray:
	return PackedStringArray([_title.text, _opener.text, _reaction.text, _taunt.text])


## Any key, controller button or click dismisses it (the input is not
## consumed: the menus still get it).
func _input(event: InputEvent) -> void:
	if not showing():
		return
	if (event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton) and event.is_pressed():
		dismiss()


func dismiss() -> void:
	if not showing():
		return
	_shown = false
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var tw := create_tween()
	tw.tween_property(_panel, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func() -> void:
		_panel.visible = false
		_panel.modulate.a = 1.0)
	_voice.stop()
	_unduck()
	dismissed.emit()


func _duck_music() -> void:
	var bus := AudioServer.get_bus_index("Music")
	if bus < 0 or _duck != null:
		return
	_duck = AudioEffectAmplify.new()
	_duck.volume_db = DUCK_DB
	AudioServer.add_bus_effect(bus, _duck)


func _unduck() -> void:
	if _duck == null:
		return
	var bus := AudioServer.get_bus_index("Music")
	for k in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, k) == _duck:
			AudioServer.remove_bus_effect(bus, k)
			break
	_duck = null


func _exit_tree() -> void:
	_unduck()
