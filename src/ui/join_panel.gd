class_name JoinPanel
extends PanelContainer
## Two-player controller assignment: "press a button to join". The first
## device to press its Fire or Confirm binding (pad A / Start, keyboard Space /
## Enter by default; remapped bindings count) becomes Player 1, the next
## different device Player 2. Back (pad B, Esc) removes a joined player, or
## leaves when nobody has joined. With both joined, either player presses Fire
## again to start. A joined controller that disconnects leaves its slot.

signal confirmed(devices: Array[int])
signal closed

var devices: Array[int] = []
## Listening only between open() and confirmation: the panel keeps visible=true
## while the whole title layer is hidden, so visibility alone is not enough.
var _active := false
var _slots: Array[Label] = []
var _hint: Label


const VrWidgets := preload("res://src/ui/vr_widgets.gd")


func setup() -> void:
	custom_minimum_size = Vector2(600, 0)
	add_theme_stylebox_override("panel", VrWidgets.panel(0.92))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	add_child(box)
	var title := HyperTheme.label("Split screen", 24, HyperTheme.GOLD, 700)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	for n in 2:
		var l := HyperTheme.label("", 18, HyperTheme.CREAM, 600)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(l)
		_slots.append(l)
	_hint = HyperTheme.label("", 14, HyperTheme.CREAM_DIM, 500)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_hint)
	Input.joy_connection_changed.connect(_on_joy_connection)


func _on_joy_connection(device: int, connected: bool) -> void:
	if not connected and devices.has(device):
		devices.erase(device)
		if _active:
			_refresh()


func open() -> void:
	devices.clear()
	_active = true
	_refresh()


func _input(event: InputEvent) -> void:
	if not _active or not is_visible_in_tree():
		return
	var device := -2
	var cancel := false
	var jb := event as InputEventJoypadButton
	var key := event as InputEventKey
	var pressed := (jb != null and jb.pressed) or (key != null and key.pressed and not key.echo)
	if not pressed:
		return
	var from := jb.device if jb != null else PlayerControls.KEYBOARD
	if InputMap.event_is_action(event, PlayerControls.BACK, true):
		cancel = true
		device = from
	elif InputMap.event_is_action(event, PlayerControls.FIRE, true) or InputMap.event_is_action(event, PlayerControls.CONFIRM, true):
		device = from
	if device == -2:
		return
	get_viewport().set_input_as_handled()
	press(device, cancel)


## One press from a device (also used by tests).
func press(device: int, cancel: bool = false) -> void:
	if not _active:
		return
	if cancel:
		if devices.has(device):
			devices.erase(device)
		elif devices.is_empty():
			_active = false
			closed.emit()
			return
	elif devices.has(device):
		if devices.size() == 2:
			_active = false  # exactly one start per deliberate confirmation
			confirmed.emit(devices.duplicate())
			return
	elif devices.size() < 2:
		devices.append(device)
	_refresh()


## Joining is about every device (each player presses on their own), so this
## prompt names the keyboard key and the gamepad button together.
static func _both_keys(action: String) -> String:
	var keep := PlayerControls.device_kind
	PlayerControls.device_kind = ""
	var t := PlayerControls.key_text(action)
	PlayerControls.device_kind = keep
	return t


static func device_name(device: int) -> String:
	if device == PlayerControls.KEYBOARD:
		return "Keyboard"
	var n := Input.get_joy_name(device)
	return "%s (pad %d)" % [n if not n.is_empty() else "Controller", device]


func _refresh() -> void:
	for n in 2:
		var joined := n < devices.size()
		_slots[n].text = "Player %d:  %s" % [n + 1, device_name(devices[n]) if joined else "%s to join" % _both_keys(PlayerControls.FIRE)]
		_slots[n].add_theme_color_override("font_color", HyperTheme.GOLD if joined else HyperTheme.CREAM_DIM)
	_hint.text = PlayerControls.fmt("Both ready: press {fire} again to continue    {back}: leave") if devices.size() == 2 \
		else PlayerControls.fmt("{fire}: join (keyboard: one player)    {back}: back")
