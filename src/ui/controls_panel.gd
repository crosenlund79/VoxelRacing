class_name ControlsPanel
extends PanelContainer
## Remappable controls (ControlBindings): two keyboard and two controller
## slots for every player action, plus short how-to-play help written with the
## current bindings, grouped in tabs (Driving, Weapons & combat, Camera &
## replays, Menus & race, Multiplayer, Spectator). Choose a slot, then press
## the new key or controller input; Esc cancels, Delete / Backspace empties
## the slot. Clashes are refused with a message.
## Tabs: click them, move along the tab row (left / right), or Q / E and the
## controller's shoulder buttons from anywhere on the screen.
## Prototype 005: compact, with icon tabs; only the chosen input device's
## bindings are shown (a small switch shows the other device's).

signal closed

## The tabs: [title, actions]. Remappable actions get their four slots; any
## other existing action (camera view, replay) is shown with its fixed inputs.
## A remappable action missing here lands on the "menus" tab, so every action
## in ControlBindings.ACTIONS always has its slots somewhere.
const TABS := [
	["Driving", [PlayerControls.STEER_LEFT, PlayerControls.STEER_RIGHT, PlayerControls.FIRE]],
	["Weapons", [PlayerControls.FIRE_FRONT, PlayerControls.FIRE_REAR, PlayerControls.CYCLE_FRONT,
		PlayerControls.CYCLE_REAR]],
	["Camera", ["camera_view", "replay", "photo_mode", PlayerControls.TOGGLE_LIGHTING]],
	["Menus", [PlayerControls.CONFIRM, PlayerControls.BACK, PlayerControls.HISTORY_VIEW]],
	["Multiplayer", []],
	["Spectator", [PlayerControls.SIM_SPEED, PlayerControls.TOGGLE_PANEL]],
]
const TAB_ICONS := ["car", "weapons_on", "camera", "menu", "multiplayer", "spectate"]
const VrWidgets := preload("res://src/ui/vr_widgets.gd")
const MENUS_TAB := 3
const UiJuice := preload("res://src/ui/ui_juice.gd")
## Names for the fixed (not remappable) actions.
const FIXED_LABELS := {"camera_view": "Camera view", "replay": "Watch the replay", "photo_mode": "Photo mode"}

## Help rows: [tab, title, text]; an empty text makes a heading. {action}
## placeholders become the player's bindings.
const ROWS := [
	[0, "CONTROL MODE", ""],
	[0, "Fire to Accelerate", "Hold {fire} to accelerate, release to brake"],
	[0, "Fire to Brake", "Accelerates by itself, hold {fire} to brake hard"],
	[0, "THE RACE", ""],
	[0, "Laps", "Count only when every checkpoint is passed in order"],
	[0, "Grid", "The next race starts from the reversed result: the winner starts last"],
	[1, "Weapons", "{fire_front} fires the front weapon, {fire_rear} the rear one"],
	[1, "Weapon types", "{cycle_front} / {cycle_rear} switch to the next type you carry (championship and career)"],
	[1, "Weapons hot", "Weapons unlock once the whole field has crossed the start line"],
	[2, "Camera view", "{camera_view} cycles the voxel camera preset during a race"],
	[2, "Lights", "{toggle_lighting} switches the lights on or off"],
	[2, "ACTION REPLAY", ""],
	[2, "Watch again", "{replay} on the results screen shows the race highlights again"],
	[2, "Next highlight", "{confirm} or {fire} skips to the next highlight"],
	[2, "Skip all", "{back} skips all the highlights"],
	[2, "PHOTO MODE", ""],
	[2, "Freeze and look", "{photo_mode} pauses the race (or replay) with a free camera; again or Esc to return"],
	[2, "Camera", "Mouse drag / right stick orbit, WASD / left stick move, Q / E height, wheel zoom, Tab next car"],
	[2, "Pictures", "Enter / F12 saves a screenshot (user data folder, screenshots); H hides the hints"],
	[3, "Race menu", "{back} pauses (resume or leave)"],
	[3, "Results / standings", "{confirm} continues; Fire never does"],
	[3, "Grid", "{steer_left} / {steer_right} control mode, {fire_front} / {fire_rear} weapons, {history_view} laps, {fire} start"],
	[3, "Championship", "Results: {confirm} = standings, then the garage before the next round"],
	[3, "Always", "Enter always confirms, Esc always goes back"],
	[4, "TWO PLAYERS", ""],
	[4, "Join", "Each player presses Fire on their own controller (or the keyboard)"],
	[4, "Drive", "Each player uses these bindings on their own controller"],
	[4, "Shared", "{toggle_panel}, {toggle_lighting} and {sim_speed} work for both players"],
	[4, "LAN / ONLINE", ""],
	[4, "Two computers", "Host shares its address; see docs/NETWORK_PLAY.md"],
	[5, "Follow a driver", "Click a name in the standings, or the < > arrows"],
	[5, "History / counts", "{history_view}"],
	[5, "Panel / speed", "{toggle_panel} hides the panel, {sim_speed} changes the speed"],
]

## The page area's fixed height: every tab gives the panel the same size.
const PAGE_HEIGHT := 250
const SLOT_SIZE := Vector2(104, 32)

var _back: Button
var _defaults: Button
var _status: Label
## [action, kind, slot] -> its button.
var _slots := {}
## [action, kind, slot] -> the label of a fixed (not remappable) input.
var _fixed := {}
var _help: Array[Label] = []
var _tabs: Array[Button] = []
var _pages: Array[Control] = []
## Each page's slot buttons, row by row (for focus wiring).
var _page_rows: Array = []
var tab := 0
## Which device's bindings are shown: ControlBindings.KEYBOARD, PAD, or "" (both).
var view_kind := ""
var _view_button: Button
var _device_button: Button
var _grids: Array[GridContainer] = []
var _headers: Array = []  # [label, kind]
var _fixed_note: Array[Label] = []
## The slot waiting for a new input ([action, kind, slot]), empty when none.
var waiting: Array = []


func setup() -> void:
	custom_minimum_size = Vector2(1040, 0)
	add_theme_stylebox_override("panel", VrWidgets.panel(0.92))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	box.add_child(head)
	_back = VrWidgets.icon_button("back", "Back", 34)
	_back.pressed.connect(func() -> void: closed.emit())
	head.add_child(_back)
	head.add_child(VrWidgets.icon("controls", 24))
	var heading := VrWidgets.text("Controls", 20, VrStyle.YELLOW)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(heading)
	_view_button = VrWidgets.icon_button("keyboard", func() -> String:
		return "Showing keyboard" if view_kind == ControlBindings.KEYBOARD else ("Showing gamepad" if view_kind == ControlBindings.PAD else "Showing both"), 34)
	_view_button.pressed.connect(_toggle_view)
	head.add_child(_view_button)
	_defaults = VrWidgets.icon_button("restart", "Restore defaults", 34)
	_defaults.pressed.connect(restore_defaults)
	head.add_child(_defaults)
	_help.resize(ROWS.size())
	box.add_child(_build_tab_row())
	var pages := Control.new()
	pages.custom_minimum_size = Vector2(0, PAGE_HEIGHT)
	box.add_child(pages)
	var placed := {}
	for t in TABS:
		for a in t[1]:
			placed[a] = true
	for i in TABS.size():
		var actions: Array = (TABS[i][1] as Array).duplicate()
		if i == MENUS_TAB:
			for a in ControlBindings.ACTIONS:
				if not placed.has(a[0]):
					actions.append(a[0])
		var page := _build_page(i, actions)
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		pages.add_child(page)
		_pages.append(page)
	_status = VrWidgets.text("", 13, HyperTheme.CREAM_DIM)
	_status.custom_minimum_size = Vector2(1000, 20)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	_set_view({PlayerControls.DEVICE_KEYBOARD: ControlBindings.KEYBOARD, PlayerControls.DEVICE_GAMEPAD: ControlBindings.PAD}.get(PlayerControls.device_kind, ""))
	select_tab(0)
	refresh()
	UiJuice.tree(self)  # tabs, slots and buttons: the shared focus pop / press squash
	_wire_focus.call_deferred()


## The tab row: small icon tabs with their names.
func _build_tab_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for i in TABS.size():
		var b := VrWidgets.icon_button(TAB_ICONS[i], "", 34, " " + TABS[i][0], 14)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(select_tab.bind(i))
		b.focus_entered.connect(select_tab.bind(i))
		row.add_child(b)
		_tabs.append(b)
	return row


## Shows one device's bindings (or both): the grids drop the other columns.
func _set_view(kind: String) -> void:
	view_kind = kind
	for g in _grids:
		g.columns = 1 + ControlBindings.SLOTS * (1 if kind != "" else 2)
	for h in _headers:
		(h[0] as Control).visible = kind == "" or h[1] == kind
	for key in _slots:
		(_slots[key] as Control).visible = kind == "" or key[1] == kind
	for key in _fixed:
		((_fixed[key] as Label).get_parent() as Control).visible = kind == "" or key[1] == kind
	if _view_button != null:
		VrWidgets.set_icon(_view_button, "gamepad" if kind == ControlBindings.PAD else "keyboard")
	if is_inside_tree():
		_wire_focus()


func _toggle_view() -> void:
	_set_view(ControlBindings.PAD if view_kind == ControlBindings.KEYBOARD else ControlBindings.KEYBOARD)


func _key_chip(text: String) -> PanelContainer:
	var chip := PanelContainer.new()
	var sb := VrStyle.chip(VrStyle.INK, VrStyle.NIGHT_LIGHT)
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	chip.add_theme_stylebox_override("panel", sb)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := HyperTheme.label(text, 16, HyperTheme.GOLD, 700)
	chip.add_child(l)
	return chip


## One tab's page: the bindings grid on the left (when it has actions), the
## help rows in an inset card on the right (full width without bindings).
func _build_page(index: int, actions: Array) -> Control:
	var page := HBoxContainer.new()
	page.add_theme_constant_override("separation", 26)
	var rows: Array = []
	var remap: Array = []
	var fixed: Array = []
	for a in actions:
		if ControlBindings.is_remappable(a):
			remap.append(a)
		elif InputMap.has_action(a):
			fixed.append(a)
	var wide := remap.is_empty() and fixed.is_empty()
	if not wide:
		var left := VBoxContainer.new()
		left.add_theme_constant_override("separation", 10)
		page.add_child(left)
		var map := GridContainer.new()
		map.columns = 1 + 2 * ControlBindings.SLOTS
		map.add_theme_constant_override("h_separation", 6)
		map.add_theme_constant_override("v_separation", 4)
		left.add_child(map)
		_grids.append(map)
		map.add_child(VrWidgets.text("", 13))
		for h in [["keyboard", ControlBindings.KEYBOARD], ["keyboard", ControlBindings.KEYBOARD], ["gamepad", ControlBindings.PAD], ["gamepad", ControlBindings.PAD]]:
			var ic := VrWidgets.icon(h[0], 24)
			ic.custom_minimum_size = Vector2(SLOT_SIZE.x, 26)
			map.add_child(ic)
			_headers.append([ic, h[1]])
		for a in remap + fixed:
			var is_fixed: bool = a in fixed
			var lbl := VrWidgets.text(FIXED_LABELS.get(a, a) if is_fixed else ControlBindings.label_of(a), 14, HyperTheme.CREAM)
			lbl.custom_minimum_size = Vector2(200, 0)
			map.add_child(lbl)
			var row: Array[Button] = []
			for kind in [ControlBindings.KEYBOARD, ControlBindings.PAD]:
				for slot in ControlBindings.SLOTS:
					if is_fixed:
						map.add_child(_fixed_chip(a, kind, slot))
						continue
					var b := Button.new()
					b.custom_minimum_size = SLOT_SIZE
					b.clip_text = true
					_slot_style(b, kind)
					b.add_theme_font_size_override("font_size", 13)
					b.pressed.connect(_listen.bind(a, kind, slot))
					map.add_child(b)
					_slots[[a, kind, slot]] = b
					row.append(b)
			if not row.is_empty():
				rows.append(row)
		if not fixed.is_empty():
			left.add_child(VrWidgets.text("Fixed inputs", 12, HyperTheme.CREAM_DIM))
	_page_rows.append(rows)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style())
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	page.add_child(card)
	# the help: one column beside the bindings; without bindings, a column per heading
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 40)
	card.add_child(columns)
	var list: VBoxContainer = null
	for i in ROWS.size():
		var r: Array = ROWS[i]
		if r[0] != index:
			continue
		var heading: bool = String(r[2]).is_empty()
		if list == null or (wide and heading):
			list = VBoxContainer.new()
			list.add_theme_constant_override("separation", 8)
			list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			columns.add_child(list)
		var item := VBoxContainer.new()
		item.add_theme_constant_override("separation", 0)
		item.add_child(VrWidgets.text(r[1], 14, HyperTheme.GOLD if heading else HyperTheme.CREAM))
		var t := VrWidgets.text("", 13, Color(HyperTheme.CREAM, 0.75))
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.custom_minimum_size = Vector2(440 if wide else 330, 0)
		t.visible = not heading
		item.add_child(t)
		_help[i] = t
		list.add_child(item)
	if wide:  # the two player colours
		var players := HBoxContainer.new()
		players.add_theme_constant_override("separation", 12)
		for p in 2:
			var chip := PanelContainer.new()
			chip.add_theme_stylebox_override("panel", VrStyle.chip(HyperTheme.player_color(p)))
			var l := VrWidgets.text("Player %d" % (p + 1), 14, VrStyle.INK)
			l.add_theme_constant_override("outline_size", 0)
			chip.add_child(l)
			players.add_child(chip)
		(columns.get_child(0) as VBoxContainer).add_child(players)
	return page


## A fixed input, shown like a slot that cannot be chosen.
func _fixed_chip(action: String, kind: String, slot: int) -> PanelContainer:
	var chip := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(VrStyle.INK, 0.7)
	sb.border_color = VrStyle.NIGHT_LIGHT
	sb.set_border_width_all(2)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	chip.add_theme_stylebox_override("panel", sb)
	chip.custom_minimum_size = Vector2(SLOT_SIZE.x, SLOT_SIZE.y - 4)
	chip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var l := HyperTheme.label("", 16, HyperTheme.CREAM_DIM, 500)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.clip_text = true
	chip.add_child(l)
	_fixed[[action, kind, slot]] = l
	return chip


## Compact slots: keyboard slots night blue, controller slots a touch of teal;
## yellow ring when focused, as everywhere.
func _slot_style(b: Button, kind: String) -> void:
	VrWidgets.style_button(b, VrWidgets.FACE if kind == ControlBindings.KEYBOARD else Color("2f5468"))


func _card_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(VrStyle.INK, 0.55)
	sb.border_color = VrStyle.NIGHT_LIGHT
	sb.set_border_width_all(2)
	sb.border_width_bottom = 4
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 14
	return sb


## Shows one tab (its page, its tab in race red).
func select_tab(index: int) -> void:
	tab = posmod(index, TABS.size())
	for i in _pages.size():
		_pages[i].visible = i == tab
	for i in _tabs.size():
		_tabs[i].add_theme_stylebox_override("normal", VrWidgets.chip(VrStyle.RED if i == tab else VrWidgets.FACE))


## Controller paths the layout cannot guess: up from a page's first row goes
## to its own tab (not the nearest one), down from a tab into its page, and
## the tab row wraps around.
func _wire_focus() -> void:
	if not is_inside_tree():
		return
	for i in _tabs.size():
		var rows: Array = _page_rows[i]
		var first: Control = _back
		if not rows.is_empty():
			for b in rows[0]:
				if (b as Control).visible:
					first = b
					break
		_tabs[i].focus_neighbor_bottom = _tabs[i].get_path_to(first)
		if not rows.is_empty():
			for b in rows[0]:
				b.focus_neighbor_top = b.get_path_to(_tabs[i])
	_tabs[0].focus_neighbor_left = _tabs[0].get_path_to(_tabs[-1])
	_tabs[-1].focus_neighbor_right = _tabs[-1].get_path_to(_tabs[0])
	select_tab(tab)


func focus_first() -> void:
	refresh()
	_set_view({PlayerControls.DEVICE_KEYBOARD: ControlBindings.KEYBOARD, PlayerControls.DEVICE_GAMEPAD: ControlBindings.PAD}.get(PlayerControls.device_kind, ""))
	_tabs[tab].grab_focus()


func refresh() -> void:
	for key in _slots:
		_slots[key].text = ControlBindings.slot_name(key[0], key[1], key[2])
	for key in _fixed:
		_fixed[key].text = ControlBindings.slot_name(key[0], key[1], key[2]) if InputMap.has_action(key[0]) else "-"
	for i in ROWS.size():
		_help[i].text = PlayerControls.fmt(ROWS[i][2])
	if waiting.is_empty():
		_status.text = "Choose a slot, then press the new input (Delete empties it)"
		_status.add_theme_color_override("font_color", HyperTheme.CREAM_DIM)


## Q / E and the shoulder buttons switch tabs from anywhere on the screen
## (not while a slot is waiting for its new input).
func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not waiting.is_empty():
		return
	var step := 0
	if event is InputEventKey and event.pressed and not event.echo:
		step = {KEY_Q: -1, KEY_E: 1}.get(event.physical_keycode, 0)
	elif event is InputEventJoypadButton and event.pressed:
		step = {JOY_BUTTON_LEFT_SHOULDER: -1, JOY_BUTTON_RIGHT_SHOULDER: 1}.get(event.button_index, 0)
	if step == 0:
		return
	get_viewport().set_input_as_handled()
	select_tab(tab + step)
	_tabs[tab].grab_focus()


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
