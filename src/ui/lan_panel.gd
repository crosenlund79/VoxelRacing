class_name LanPanel
extends PanelContainer
## Title-screen LAN panel (M5.1): host a game, or join one by IP address;
## shows connection progress and clear messages. UI only: it asks the game
## root to host / join / cancel and displays the status it is given.

signal host_requested
signal join_requested(address: String)
signal cancel_requested
signal closed

var _address: LineEdit
var _status: Label
var _host_button: Button
var _join_button: Button
var _back_button: Button
var _busy := false


func setup(saved_address: String) -> void:
	custom_minimum_size = Vector2(760, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	var title := HyperTheme.label("NETWORK RACE - LAN OR INTERNET", 30, HyperTheme.GOLD, 700)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	row.add_child(HyperTheme.label("Host address:", 20, HyperTheme.CREAM, 600))
	_address = LineEdit.new()
	_address.text = saved_address
	_address.placeholder_text = "192.168.1.20 or 203.0.113.7"
	_address.custom_minimum_size = Vector2(260, 40)
	_address.add_theme_font_size_override("font_size", 20)
	row.add_child(_address)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	_host_button = _button("HOST GAME", func() -> void: host_requested.emit())
	_join_button = _button("JOIN GAME", func() -> void: join_requested.emit(address()))
	_back_button = _button("BACK", _back)
	for b in [_host_button, _join_button, _back_button]:
		buttons.add_child(b)
	_status = HyperTheme.label("", 18, HyperTheme.CREAM, 500)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(700, 60)
	box.add_child(_status)
	visibility_changed.connect(func() -> void:
		if not visible and _busy:
			_busy = false
			cancel_requested.emit())


func address() -> String:
	return _address.text.strip_edges()


func open() -> void:
	set_busy(false)
	show_status("Host: HOST GAME and share your address (internet: your public IP + UDP port 24680 forwarded).  Join: type the host's address, then JOIN GAME.")
	_host_button.grab_focus()


## Waiting for the other player / connecting: only BACK (cancel) is active.
func set_busy(on: bool) -> void:
	_busy = on
	_host_button.disabled = on
	_join_button.disabled = on
	_address.editable = not on
	_back_button.text = "CANCEL" if on else "BACK"


func show_status(text: String, error: bool = false) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", HyperTheme.RED if error else HyperTheme.CREAM)


func focus_first() -> void:
	_host_button.grab_focus()


func _back() -> void:
	if _busy:
		set_busy(false)
		cancel_requested.emit()
		show_status("Cancelled.")
	else:
		closed.emit()


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(200, 46)
	b.pressed.connect(action)
	return b
