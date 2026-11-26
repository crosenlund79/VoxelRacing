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
var _leave_text := "Leave race"
const VrWidgets := preload("res://src/ui/vr_widgets.gd")


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
	_panel.add_theme_stylebox_override("panel", VrWidgets.panel(0.92))
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 10)
	head.add_child(VrWidgets.icon("pause", 26))
	_title = VrWidgets.text("Paused", 24, HyperTheme.GOLD)
	head.add_child(_title)
	box.add_child(head)
	_context = VrWidgets.text("", 14, HyperTheme.CREAM)
	_context.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_context.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_context.custom_minimum_size = Vector2(340, 0)
	box.add_child(_context)
	_note = VrWidgets.text("", 13, HyperTheme.CREAM_DIM)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(340, 0)
	box.add_child(_note)
	_resume = VrWidgets.icon_button("start", "", 46, "  Resume", 18)
	VrWidgets.style_button(_resume, Color("2f7d4a"))
	_resume.add_theme_font_size_override("font_size", 18)
	_resume.pressed.connect(func() -> void: resume_requested.emit())
	_leave = VrWidgets.icon_button("quit", "", 38, "  " + _leave_text, 15)
	_leave.pressed.connect(_on_leave)
	box.add_child(_resume)
	box.add_child(_leave)
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
	_leave.text = "  " + _leave_text
	_note.remove_theme_color_override("font_color")
	_title.text = "Race menu" if network else "Paused"
	_note.text = "The race goes on: your car brakes" if network else ""
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
	_leave.text = "  " + text


func _on_leave() -> void:
	if warning != "" and not _confirming:
		_confirming = true
		_note.text = warning
		_note.add_theme_color_override("font_color", Color("ff8a6a"))
		_leave.text = "  Confirm: forfeit"
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
