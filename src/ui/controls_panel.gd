class_name ControlsPanel
extends PanelContainer
## Remappable controls (ControlBindings): two keyboard and two controller
## slots for every player action, plus short how-to-play help written with the
## current bindings. Choose a slot, then press the new key or controller input;
## Esc cancels, Delete / Backspace empties the slot. Clashes are refused with a
## message.

signal closed

## Help rows: {action} placeholders become the player's bindings.
const ROWS := [
	["RACING", ""],
	["Fire to Accelerate", "Hold {fire} to accelerate, release to brake"],
	["Fire to Brake", "Accelerates by itself, hold {fire} to brake hard"],
	["Grid panel", "{steer_left} / {steer_right} control mode, {fire_front} / {fire_rear} weapons, {toggle_style} combat style, {history_view} laps, {fire} start"],
	["Weapon types", "{cycle_front} / {cycle_rear} switch to the next owned type you carry (garage races)"],
	["Race menu", "{back} pauses (resume or leave)"],
	["Results / standings", "{confirm} continues; Fire never does"],
	["Lights", "{toggle_lighting} switches the lights on or off"],
	["TWO PLAYERS", ""],
	["Join", "Each player presses Fire on their own controller (or the keyboard)"],
	["Drive", "Each player uses these bindings on their own controller"],
	["LAN / online", "Host shares its address; see docs/NETWORK_PLAY.md"],
	["SPECTATING", ""],
	["Follow a driver", "Click a name in the standings, or the < > arrows"],
	["History / counts", "{history_view}"],
	["Panel / speed", "{toggle_panel} hides the panel, {sim_speed} changes the speed"],
	["THE RACE", ""],
	["Laps", "Count only when every checkpoint is passed in order"],
	["Grid", "The next race starts from the reversed result: the winner starts last"],
	["Garage race", "Results: {confirm} = garage, {history_view} = skip shopping"],
]

var _back: Button
var _defaults: Button
var _status: Label
## [action, kind, slot] -> its button.
var _slots := {}
var _help: Array[Label] = []
## The slot waiting for a new input ([action, kind, slot]), empty when none.
var waiting: Array = []


func setup() -> void:
	custom_minimum_size = Vector2(1220, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var title := HyperTheme.label("CONTROLS & HELP", 30, HyperTheme.GOLD, 700)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	box.add_child(cols)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	cols.add_child(left)
	var map := GridContainer.new()
	map.columns = 1 + 2 * ControlBindings.SLOTS
	map.add_theme_constant_override("h_separation", 6)
	map.add_theme_constant_override("v_separation", 2)
	left.add_child(map)
	for h in ["ACTION", "KEY 1", "KEY 2", "CONTROLLER 1", "CONTROLLER 2"]:
		map.add_child(HyperTheme.label(h, 14, HyperTheme.GOLD, 700))
	for a in ControlBindings.ACTIONS:
		map.add_child(HyperTheme.label(a[1], 14, HyperTheme.CREAM, 600))
		for kind in [ControlBindings.KEYBOARD, ControlBindings.PAD]:
			for slot in ControlBindings.SLOTS:
				var b := Button.new()
				b.custom_minimum_size = Vector2(130, 27)
				b.add_theme_font_size_override("font_size", 12)
				b.clip_text = true
				b.pressed.connect(_listen.bind(a[0], kind, slot))
				map.add_child(b)
				_slots[[a[0], kind, slot]] = b
	_status = HyperTheme.label("", 14, HyperTheme.CREAM_DIM, 500)
	_status.custom_minimum_size = Vector2(640, 40)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_status)
	_defaults = Button.new()
	_defaults.text = "RESTORE DEFAULTS"
	_defaults.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_defaults.pressed.connect(restore_defaults)
	left.add_child(_defaults)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 0)
	cols.add_child(grid)
	for row in ROWS:
		var heading: bool = String(row[1]).is_empty()
		grid.add_child(HyperTheme.label(row[0], 13, HyperTheme.GOLD if heading else HyperTheme.CREAM, 700 if heading else 600))
		var t := HyperTheme.label("", 13, HyperTheme.CREAM, 500)
		t.custom_minimum_size = Vector2(330, 0)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		grid.add_child(t)
		_help.append(t)
	_back = Button.new()
	_back.text = "BACK"
	_back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_back.pressed.connect(func() -> void: closed.emit())
	box.add_child(_back)
	refresh()


func focus_first() -> void:
	refresh()
	_back.grab_focus()


func refresh() -> void:
	for key in _slots:
		_slots[key].text = ControlBindings.slot_name(key[0], key[1], key[2])
	for i in ROWS.size():
		_help[i].text = PlayerControls.fmt(ROWS[i][1])
	if waiting.is_empty():
		_status.text = "Choose a slot and press the new key or controller input (Delete empties a slot). Enter always confirms, Esc always goes back."
		_status.add_theme_color_override("font_color", HyperTheme.CREAM_DIM)


## Waits for the next input for one slot.
func _listen(action: String, kind: String, slot: int = 0) -> void:
	waiting = [action, kind, slot]
	_slots[waiting].text = "press..."
	_status.text = "%s: press the new %s (Esc cancels, Delete empties the slot)." % [ControlBindings.label_of(action),
		"key" if kind == ControlBindings.KEYBOARD else "controller button or stick direction"]
	_status.add_theme_color_override("font_color", HyperTheme.GOLD)


func _input(event: InputEvent) -> void:
	if waiting.is_empty() or not visible:
		return
	var kind := ""
	if event is InputEventKey and event.pressed and not event.echo:
		kind = ControlBindings.KEYBOARD
	elif event is InputEventJoypadButton and event.pressed:
		kind = ControlBindings.PAD
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.6:
		kind = ControlBindings.PAD
	if kind == "":
		return
	get_viewport().set_input_as_handled()
	var slot: Array = waiting
	waiting = []
	var err := ""
	if event is InputEventKey and event.physical_keycode == KEY_ESCAPE:
		refresh()
		_slots[slot].grab_focus()
		return
	if event is InputEventKey and event.physical_keycode in [KEY_DELETE, KEY_BACKSPACE]:
		err = ControlBindings.clear(slot[0], slot[1], slot[2])
	elif kind != slot[1]:
		err = "That was a %s input; this slot needs a %s." % [
			"keyboard" if kind == ControlBindings.KEYBOARD else "controller", "key" if slot[1] == ControlBindings.KEYBOARD else "controller input"]
	else:
		err = ControlBindings.assign(slot[0], event, slot[2])
	refresh()
	if err != "":
		_status.text = err
		_status.add_theme_color_override("font_color", Color("ff8a6a"))
	else:
		ControlBindings.save()
		_status.text = "%s: %s." % [ControlBindings.label_of(slot[0]), ControlBindings.describe(slot[0], slot[1])]
		_status.add_theme_color_override("font_color", HyperTheme.GOLD)
	_slots[slot].grab_focus()


func restore_defaults() -> void:
	waiting = []
	ControlBindings.restore_defaults()
	refresh()
	_status.text = "Default controls restored."
	_status.add_theme_color_override("font_color", HyperTheme.GOLD)
