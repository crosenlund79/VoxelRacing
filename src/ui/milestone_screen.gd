class_name MilestoneScreen
extends CanvasLayer
## Career milestones (2026-11-23): short, skippable cards between screens -
## a stage beginning, the Grand Final ahead, a first career victory, a title
## won and the promotion it brings, a rival's car won, a stage lost. One card
## after another (Confirm or Back moves on after a short moment), then
## `finished`. Each card: a big title in the stage's accent, a subtitle, a
## line of detail and the car that matters (the player's chosen car, or a
## rival's in its own colours / the junker), drawn by CarArt so user artwork
## applies. No portraits, no voice. Presentation only.

signal finished

## Ignore input this long after a card appears (the key that led here).
const INPUT_DELAY := 0.45

var _root: Control
var _card: PanelContainer
var _title: Label
var _rule: ColorRect
var _subtitle: Label
var _detail: Label
var _car: TextureRect
var _hint: Label
var _queue: Array = []
var _age := 0.0
var _current: Dictionary = {}


func setup(resolver: AssetResolver) -> void:
	layer = 28
	_root = Control.new()
	_root.theme = HyperTheme.build(resolver)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = Color(0.11, 0.09, 0.08, 0.94)
	shade.size = Vector2(1280, 720)
	_root.add_child(shade)
	_card = PanelContainer.new()
	_root.add_child(_card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_card.add_child(box)
	_title = HyperTheme.label("", 52, HyperTheme.GOLD, 700)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.custom_minimum_size = Vector2(900, 0)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_title)
	_rule = ColorRect.new()
	_rule.custom_minimum_size = Vector2(320, 4)
	_rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_rule)
	_subtitle = HyperTheme.label("", 26, HyperTheme.CREAM, 700)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.custom_minimum_size = Vector2(900, 0)
	box.add_child(_subtitle)
	_car = TextureRect.new()
	_car.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_car.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_car.custom_minimum_size = Vector2(900, 190)
	box.add_child(_car)
	_detail = HyperTheme.label("", 20, HyperTheme.CREAM, 600)
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(900, 0)
	box.add_child(_detail)
	_hint = HyperTheme.label("", 16, HyperTheme.CREAM_DIM, 600)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_hint)
	visible = false


## Shows the cards in turn ({title, subtitle, detail, car (Texture2D or
## null), accent (Color)}). An empty queue finishes at once.
func show_queue(cards: Array) -> void:
	_queue = cards.duplicate()
	if _queue.is_empty():
		visible = false
		finished.emit.call_deferred()
		return
	visible = true
	_next()


func showing() -> bool:
	return visible


func current_title() -> String:
	return _current.get("title", "")


func _next() -> void:
	if _queue.is_empty():
		visible = false
		_current = {}
		finished.emit()
		return
	_current = _queue.pop_front()
	var accent: Color = _current.get("accent", HyperTheme.GOLD)
	_title.text = _current.get("title", "")
	_title.add_theme_color_override("font_color", accent)
	_rule.color = Color(accent, 0.85)
	_subtitle.text = _current.get("subtitle", "")
	_subtitle.visible = _subtitle.text != ""
	_detail.text = _current.get("detail", "")
	_detail.visible = _detail.text != ""
	_car.texture = _current.get("car", null)
	_car.visible = _car.texture != null
	_hint.text = PlayerControls.fmt("{confirm}: continue" if not _queue.is_empty() else "{confirm}: continue")
	_card.reset_size()
	var size := _card.get_combined_minimum_size()
	_card.position = (Vector2(1280, 720) - size) * 0.5
	_card.modulate.a = 0.0
	_card.position.y += 24.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_card, "modulate:a", 1.0, 0.25)
	tw.tween_property(_card, "position:y", (720.0 - size.y) * 0.5, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_age = 0.0


## Moves on (Confirm / Back, or a test).
func advance() -> void:
	if visible and _age >= INPUT_DELAY:
		_next()


func _process(delta: float) -> void:
	if visible:
		_age += delta


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(PlayerControls.CONFIRM) or event.is_action_pressed(PlayerControls.BACK):
		get_viewport().set_input_as_handled()
		advance()
