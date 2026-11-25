class_name RaceMenu
extends CanvasLayer
## The in-race Esc menu: RESUME RACE / LEAVE RACE. Keeps working while the game
## is paused (process mode Always). The race scene decides what pausing means
## (single-player, spectator and couch pause; a network race goes on).
## 2026-11-23: the main menu's look - the race dimmed behind (still visible),
## a gold heading with the race's identity (circuit, environment, round), a
## large RESUME and a smaller, clearly separate LEAVE.

signal resume_requested
signal leave_requested

var _panel: PanelContainer
var _title: Label
var _note: Label
var _context: Label
var _resume: Button
var _leave: Button
var _opened_frame := -1
## Racing for Keeps: leaving costs a car, so the first press only warns.
var warning := ""
var _confirming := false
var _leave_text := "LEAVE RACE"


func setup(theme: Theme) -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	var shade := ColorRect.new()
	shade.color = HyperTheme.SHADE
	shade.size = Vector2(1280, 720)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	_panel = PanelContainer.new()
	_panel.theme = theme
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_panel.add_child(box)
	_title = HyperTheme.label("RACE PAUSED", 40, HyperTheme.GOLD, 700)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	var rule := ColorRect.new()
	rule.color = Color(HyperTheme.GOLD, 0.7)
	rule.custom_minimum_size = Vector2(220, 3)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(rule)
	_context = HyperTheme.label("", 18, HyperTheme.CREAM, 600)
	_context.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_context.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_context.custom_minimum_size = Vector2(420, 0)
	box.add_child(_context)
	_note = HyperTheme.label("", 17, HyperTheme.CREAM_DIM, 500)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(420, 0)
	box.add_child(_note)
	_resume = _button("RESUME RACE", func() -> void: resume_requested.emit())
	HyperTheme.style_button(_resume, true, 420)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	_leave = _button("LEAVE RACE", _on_leave)
	HyperTheme.style_button(_leave, false, 420)
	box.add_child(_resume)
	box.add_child(gap)
	box.add_child(_leave)
	var hint := HyperTheme.label(PlayerControls.fmt("Up / Down: choose    {confirm}: select    {back}: resume"), 15, HyperTheme.CREAM_DIM, 500)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	visible = false


## The race's identity under the title ("KESTREL RIDGE - Winter - NIGHT - 3 laps").
func set_context(text: String) -> void:
	_context.text = text
	_context.visible = text != ""


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	b.mouse_entered.connect(b.grab_focus)
	return b


## network: the race goes on for the other player while the menu is open.
func open(network: bool) -> void:
	_confirming = false
	_leave.text = _leave_text
	_note.remove_theme_color_override("font_color")
	_title.text = "RACE MENU" if network else "RACE PAUSED"
	_note.text = "The race goes on for the other player: your car brakes." if network else "The race is paused."
	visible = true
	_panel.reset_size()
	_panel.position = (Vector2(1280, 720) - _panel.get_combined_minimum_size()) * 0.5
	HyperTheme.reveal(_panel)
	_resume.grab_focus()
	_opened_frame = Engine.get_process_frames()


## A message in place of the usual note (e.g. a controller disconnected).
func set_note(text: String, alert := false) -> void:
	_note.text = text
	if alert:
		_note.add_theme_color_override("font_color", Color("ff8a6a"))
	_panel.reset_size()
	_panel.position = (Vector2(1280, 720) - _panel.get_combined_minimum_size()) * 0.5


## The leave button's label (a championship round abandons the championship).
func set_leave_text(text: String) -> void:
	_leave_text = text
	_leave.text = text


func _on_leave() -> void:
	if warning != "" and not _confirming:
		_confirming = true
		_note.text = warning
		_note.add_theme_color_override("font_color", Color("ff8a6a"))
		_leave.text = "CONFIRM: FORFEIT"
		_panel.reset_size()
		_panel.position = (Vector2(1280, 720) - _panel.get_combined_minimum_size()) * 0.5
		return
	leave_requested.emit()


func close() -> void:
	visible = false
	for b in [_resume, _leave]:
		if b.has_focus():
			b.release_focus()


func is_open() -> bool:
	return visible


func _process(_delta: float) -> void:
	# Esc (any player's Back) resumes; not in the frame that opened the menu
	if visible and Engine.get_process_frames() != _opened_frame and _back_pressed():
		resume_requested.emit()


static func _back_pressed() -> bool:
	for action in [PlayerControls.BACK, "p1_" + PlayerControls.BACK, "p2_" + PlayerControls.BACK]:
		if InputMap.has_action(action) and Input.is_action_just_pressed(action):
			return true
	return false
