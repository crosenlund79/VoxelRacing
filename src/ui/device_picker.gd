extends PanelContainer
## Input device selection (Prototype 005): the player picks the device they
## play with - the keyboard or a connected gamepad - once; it is remembered
## (PlayerControls.set_device) and can be changed later from Settings. Shown at
## the first launch, and again when the remembered gamepad is not connected.
## Pressing any key highlights the keyboard, any gamepad button that gamepad;
## Confirm (or a click) chooses it. Loaded with preload (no class_name).

signal chosen(kind: String, pad_name: String)
signal closed

const VrWidgets := preload("res://src/ui/vr_widgets.gd")

var _row: HBoxContainer
var _cards: Array[Button] = []
## Whether Back may close it without choosing (from Settings: yes; first launch: no).
var can_cancel := false


func _ready() -> void:
	add_theme_stylebox_override("panel", VrWidgets.panel(0.92))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 10)
	head.add_child(VrWidgets.icon("controls", 30))
	head.add_child(VrWidgets.text("Play with", 22, VrStyle.YELLOW))
	box.add_child(head)
	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 12)
	box.add_child(_row)
	Input.joy_connection_changed.connect(func(_d: int, _c: bool) -> void:
		if is_inside_tree() and visible:
			_rebuild())
	_rebuild()
	visible = false


func open(cancel_allowed: bool = false) -> void:
	can_cancel = cancel_allowed
	_rebuild()
	visible = true
	reset_size()
	position = (Vector2(1280, 720) - get_combined_minimum_size()) * 0.5
	_focus_current()


func _rebuild() -> void:
	for c in _cards:
		c.queue_free()
	_cards.clear()
	_cards.append(_card("keyboard", "Keyboard", PlayerControls.DEVICE_KEYBOARD, "", -1))
	for d in Input.get_connected_joypads():
		var n := Input.get_joy_name(d)
		_cards.append(_card("gamepad", _short(n), PlayerControls.DEVICE_GAMEPAD, n, d))
	for k in _cards.size():
		var b := _cards[k]
		b.focus_neighbor_left = b.get_path_to(_cards[posmod(k - 1, _cards.size())])
		b.focus_neighbor_right = b.get_path_to(_cards[posmod(k + 1, _cards.size())])
		b.focus_neighbor_top = b.get_path()
		b.focus_neighbor_bottom = b.get_path()


func _short(n: String) -> String:
	n = n.strip_edges()
	if n == "":
		return "Gamepad"
	return n.substr(0, 18) + ("..." if n.length() > 18 else "")


func _card(icon: String, label: String, kind: String, pad_name: String, device: int) -> Button:
	var b := VrWidgets.icon_button(icon, "", 120, "", 16)
	b.custom_minimum_size = Vector2(150, 120)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.text = label
	b.set_meta("kind", kind)
	b.set_meta("device", device)
	b.pressed.connect(func() -> void:
		PlayerControls.set_device(kind, pad_name)
		visible = false
		chosen.emit(kind, pad_name))
	_row.add_child(b)
	return b


func _focus_current() -> void:
	if _cards.is_empty():
		return
	var pick := _cards[0]
	for b in _cards:
		if PlayerControls.device_kind == PlayerControls.DEVICE_GAMEPAD and str(b.get_meta("kind")) == PlayerControls.DEVICE_GAMEPAD:
			pick = b
			break
	pick.grab_focus.call_deferred()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	# any key highlights the keyboard, any gamepad button its gamepad
	if event is InputEventKey and event.pressed and not event.is_echo() and not _cards.is_empty():
		var k := event as InputEventKey
		if k.keycode not in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_TAB, KEY_ESCAPE]:
			_cards[0].grab_focus()
	elif event is InputEventJoypadButton and event.pressed:
		var jb := event as InputEventJoypadButton
		for b in _cards:
			if int(b.get_meta("device")) == jb.device:
				var f := get_viewport().gui_get_focus_owner()
				if f == null or int(f.get_meta("device", -2)) != jb.device:
					b.grab_focus()
					get_viewport().set_input_as_handled()  # (first press: picks the pad; the next one confirms)
				break
	if can_cancel and event.is_action_pressed("ui_cancel"):
		visible = false
		get_viewport().set_input_as_handled()
		closed.emit()
