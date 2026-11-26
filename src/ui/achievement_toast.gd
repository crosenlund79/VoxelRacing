class_name AchievementToast
extends CanvasLayer
## Small "Achievement unlocked" notification that slides in at the top right,
## one at a time (queued), with a jingle. Presentation only. While held (the
## championship standings are up: their title and panels fill the screen) toasts
## wait in the queue; one on screen at that moment slides out and comes back
## later, so every unlock is still shown, readably, once the screen closes.

const SHOW_TIME := 3.2
const Icons = preload("res://src/ui/achievement_icons.gd")
const UiJuice := preload("res://src/ui/ui_juice.gd")
const SoundKit := preload("res://src/audio/sound_kit.gd")

var _resolver: AssetResolver
var _panel: PanelContainer
var _name: Label
var _icon: TextureRect
var _queue: Array[String] = []
var _busy := false
var _held := false
var _current := ""
var _tween: Tween
var _sfx: AudioStreamPlayer


func setup(resolver: AssetResolver) -> void:
	_resolver = resolver
	layer = 45
	var root := Control.new()
	root.theme = HyperTheme.build(resolver)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_panel.add_child(row)
	_icon = TextureRect.new()  # the achievement's own voxel badge (set per toast)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon.custom_minimum_size = Vector2(Icons.SIZE, Icons.SIZE)
	row.add_child(_icon)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", -4)
	row.add_child(text)
	text.add_child(HyperTheme.label("ACHIEVEMENT UNLOCKED", 15, HyperTheme.GOLD, 700))
	_name = HyperTheme.label("", 23, HyperTheme.CREAM, 700)
	text.add_child(_name)
	_panel.visible = false
	_sfx = AudioStreamPlayer.new()
	_sfx.bus = "Effects"
	add_child(_sfx)


func show_unlock(id: String) -> void:
	_queue.append(id)
	if not _busy and not _held:
		_next()


## Below the kill feed's tallest stack (top right), clear of the standings (left).
const TOP := 172.0


func pending() -> int:
	return _queue.size() + (1 if _busy else 0)


func showing() -> bool:
	return _busy and _panel.visible


## Holds toasts back (true) or lets the queue play out again (false).
func set_held(on: bool) -> void:
	if on == _held:
		return
	_held = on
	if on and _busy:
		_queue.push_front(_current)  # shown again in full once released
		if _tween != null and _tween.is_valid():
			_tween.kill()
		_tween = create_tween()
		_tween.tween_property(_panel, "position:x", 1280 + 10, 0.2).set_ease(Tween.EASE_IN)
		_tween.tween_callback(_next)
	elif not on and not _busy:
		_next()


func _next() -> void:
	if _queue.is_empty() or _held:
		_busy = false
		_panel.visible = false
		return
	_busy = true
	_current = _queue.pop_front()
	var e := AchievementCatalog.entry(_current)
	_name.text = e.get("name", "?")
	_icon.texture = Icons.icon(_current, true)
	_panel.visible = true
	_panel.reset_size()
	var w := _panel.get_combined_minimum_size().x
	_panel.position = Vector2(1280 + 10, TOP)
	_sfx.stream = _resolver.get_audio("ui/achievement")
	_sfx.play()
	# the badge pops in with a little bounce (and a soft pop) as the panel lands
	UiJuice.pop_in(_icon, 0.2, 0.2, 0.42)
	var pop := create_tween()
	pop.tween_interval(0.2)
	pop.tween_callback(func() -> void: SoundKit.play(self, "pop", -9.0, 0.04))
	var tw := create_tween()
	_tween = tw
	tw.tween_property(_panel, "position:x", 1280 - w - 18, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(SHOW_TIME)
	tw.tween_property(_panel, "position:x", 1280 + 10, 0.3).set_ease(Tween.EASE_IN)
	tw.tween_callback(_next)
