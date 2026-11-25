extends GutTest
## Remappable controls: assign, clashes refused (Fire never becomes Confirm),
## reserved Enter / Esc, save / load, restore defaults, couch copies.

const PATH := "user://test_controls.cfg"


var _saved_path := ""


func before_each() -> void:
	_saved_path = ControlBindings.path
	ControlBindings.path = PATH
	ControlBindings.restore_defaults()


func after_each() -> void:
	ControlBindings.restore_defaults()
	ControlBindings.path = _saved_path
	for n in [1, 2]:
		for a in PlayerControls.PLAYER_ACTIONS:
			if InputMap.has_action(PlayerControls.player_prefix(n) + a):
				InputMap.erase_action(PlayerControls.player_prefix(n) + a)


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	return e


func _pad(button: JoyButton, device := 3) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.device = device
	e.pressed = true
	return e


func test_defaults_are_listed() -> void:
	assert_string_contains(ControlBindings.describe(PlayerControls.FIRE, ControlBindings.KEYBOARD), "Space")
	assert_string_contains(ControlBindings.describe(PlayerControls.FIRE, ControlBindings.PAD), "Pad A")
	assert_string_contains(PlayerControls.key_text(PlayerControls.CONFIRM), "Enter", "Enter is fixed on Confirm")


func test_assign_replaces_one_slot_only() -> void:
	assert_eq(ControlBindings.assign(PlayerControls.FIRE, _key(KEY_J)), "")
	assert_eq(ControlBindings.describe(PlayerControls.FIRE, ControlBindings.KEYBOARD), "J / Ctrl", "the second Fire key stays")
	assert_true(InputMap.event_is_action(_key(KEY_J), PlayerControls.FIRE))
	assert_false(InputMap.event_is_action(_key(KEY_SPACE), PlayerControls.FIRE))
	assert_true(InputMap.event_is_action(_pad(JOY_BUTTON_A, 0), PlayerControls.FIRE), "pad binding kept")
	assert_eq(ControlBindings.assign(PlayerControls.FIRE, _key(KEY_K), 1), "")
	assert_eq(ControlBindings.describe(PlayerControls.FIRE, ControlBindings.KEYBOARD), "J / K", "slot 2 replaced in place")
	assert_eq(ControlBindings.assign(PlayerControls.FIRE, _pad(JOY_BUTTON_RIGHT_STICK), 1), "")
	assert_eq(ControlBindings.describe(PlayerControls.FIRE, ControlBindings.PAD), "Pad A / Cross / R3", "a second pad input")
	assert_eq(ControlBindings.events(PlayerControls.FIRE, ControlBindings.PAD)[1].device, -1, "stored for any controller")


func test_any_controller_drives_the_single_player() -> void:
	for device in [0, 1, 3]:
		assert_true(InputMap.event_is_action(_pad(JOY_BUTTON_A, device), PlayerControls.FIRE), "pad %d" % device)


func test_clear_a_slot_but_never_the_last_input() -> void:
	assert_eq(ControlBindings.clear(PlayerControls.FIRE, ControlBindings.KEYBOARD, 1), "")
	assert_eq(ControlBindings.describe(PlayerControls.FIRE, ControlBindings.KEYBOARD), "Space")
	var err := ControlBindings.clear(PlayerControls.TOGGLE_LIGHTING, ControlBindings.KEYBOARD, 0)
	assert_string_contains(err, "needs at least one input")


func test_every_player_action_is_remappable() -> void:
	for a in [PlayerControls.STEER_LEFT, PlayerControls.STEER_RIGHT, PlayerControls.FIRE, PlayerControls.FIRE_FRONT,
			PlayerControls.FIRE_REAR, PlayerControls.CONFIRM, PlayerControls.BACK, PlayerControls.HISTORY_VIEW,
			PlayerControls.SIM_SPEED, PlayerControls.TOGGLE_PANEL, PlayerControls.TOGGLE_STYLE, PlayerControls.TOGGLE_LIGHTING]:
		assert_true(ControlBindings.is_remappable(a), a)
	assert_eq(ControlBindings.assign(PlayerControls.TOGGLE_PANEL, _key(KEY_P)), "")
	assert_true(InputMap.event_is_action(_key(KEY_P), PlayerControls.TOGGLE_PANEL))


func test_hints_show_the_current_bindings() -> void:
	assert_eq(PlayerControls.key_text(PlayerControls.CONFIRM), "Enter / Start")
	ControlBindings.assign(PlayerControls.HISTORY_VIEW, _key(KEY_G))
	assert_eq(PlayerControls.fmt("{history_view}: skip"), "G / Y: skip")
	assert_eq(PlayerControls.fmt("{fire}: start"), "Space / A: start")


func test_race_context_lets_confirm_press_buttons_but_never_fire() -> void:
	assert_true(InputMap.event_is_action(_pad(JOY_BUTTON_A, 2), "ui_accept"), "menus: pad A selects")
	assert_true(InputMap.event_is_action(_pad(JOY_BUTTON_B, 2), "ui_cancel"), "menus: pad B goes back")
	var before := InputMap.action_get_events("ui_accept").size()
	PlayerControls.set_race_context(true)
	assert_true(InputMap.event_is_action(_pad(JOY_BUTTON_START, 2), "ui_accept"), "pad Start selects in race menus")
	assert_false(InputMap.event_is_action(_pad(JOY_BUTTON_A, 2), "ui_accept"), "pad A (Fire) does not")
	assert_false(InputMap.event_is_action(_key(KEY_SPACE), "ui_accept"), "Space (Fire) does not")
	assert_true(InputMap.event_is_action(_key(KEY_ENTER), "ui_accept"))
	PlayerControls.set_race_context(false)
	assert_eq(InputMap.action_get_events("ui_accept").size(), before, "restored")
	assert_true(InputMap.event_is_action(_key(KEY_SPACE), "ui_accept"), "restored")


func test_join_panel_follows_the_bindings_and_drops_unplugged_pads() -> void:
	ControlBindings.assign(PlayerControls.FIRE, _pad(JOY_BUTTON_RIGHT_STICK), 1)
	var j := JoinPanel.new()
	add_child_autofree(j)
	j.setup()
	j.open()
	j._input(_pad(JOY_BUTTON_RIGHT_STICK, 2))
	assert_eq(j.devices, [2] as Array[int], "a remapped Fire joins")
	j._input(_key(KEY_SPACE))
	assert_eq(j.devices, [2, PlayerControls.KEYBOARD] as Array[int])
	j._on_joy_connection(2, false)
	assert_eq(j.devices, [PlayerControls.KEYBOARD] as Array[int], "unplugged pad leaves its slot")


func test_clashes_are_refused_and_fire_never_confirms() -> void:
	var err := ControlBindings.assign(PlayerControls.CONFIRM, _key(KEY_SPACE))
	assert_string_contains(err, "already used for Fire")
	assert_false(InputMap.event_is_action(_key(KEY_SPACE), PlayerControls.CONFIRM))
	assert_ne(ControlBindings.assign(PlayerControls.CONFIRM, _pad(JOY_BUTTON_A)), "", "pad Fire cannot confirm either")
	assert_string_contains(ControlBindings.assign(PlayerControls.FIRE, _key(KEY_ENTER)), "reserved for Confirm")
	assert_string_contains(ControlBindings.assign(PlayerControls.STEER_LEFT, _key(KEY_ESCAPE)), "reserved for Back")


func test_confirm_and_back_keep_enter_and_escape() -> void:
	assert_eq(ControlBindings.assign(PlayerControls.CONFIRM, _key(KEY_Y)), "")
	assert_true(InputMap.event_is_action(_key(KEY_Y), PlayerControls.CONFIRM))
	assert_true(InputMap.event_is_action(_key(KEY_ENTER), PlayerControls.CONFIRM), "Enter always confirms")
	assert_eq(ControlBindings.assign(PlayerControls.BACK, _key(KEY_Z)), "")
	assert_true(InputMap.event_is_action(_key(KEY_ESCAPE), PlayerControls.BACK), "Esc always goes back")


func test_saved_bindings_load_and_defaults_restore() -> void:
	ControlBindings.assign(PlayerControls.FIRE, _key(KEY_J))
	ControlBindings.assign(PlayerControls.STEER_LEFT, _pad(JOY_BUTTON_RIGHT_STICK))
	ControlBindings.save()
	ControlBindings.restore_defaults()  # also deletes the file...
	assert_true(InputMap.event_is_action(_key(KEY_SPACE), PlayerControls.FIRE), "defaults back")
	ControlBindings.assign(PlayerControls.FIRE, _key(KEY_J))
	ControlBindings.assign(PlayerControls.STEER_LEFT, _pad(JOY_BUTTON_RIGHT_STICK))
	ControlBindings.save()
	for a in ControlBindings.ACTIONS:  # ...so simulate a fresh start
		InputMap.erase_action(a[0])
	ControlBindings.load_saved()
	assert_true(InputMap.event_is_action(_key(KEY_J), PlayerControls.FIRE))
	assert_false(InputMap.event_is_action(_key(KEY_SPACE), PlayerControls.FIRE))
	assert_true(InputMap.event_is_action(_pad(JOY_BUTTON_RIGHT_STICK, 0), PlayerControls.STEER_LEFT))
	assert_true(InputMap.event_is_action(_key(KEY_ENTER), PlayerControls.CONFIRM))


func test_couch_players_copy_the_remapped_bindings_on_their_own_device() -> void:
	ControlBindings.assign(PlayerControls.FIRE, _pad(JOY_BUTTON_RIGHT_STICK))
	ControlBindings.assign(PlayerControls.FIRE, _key(KEY_J))
	var p1 := PlayerControls.ensure_player_actions(1, PlayerControls.KEYBOARD)
	var p2 := PlayerControls.ensure_player_actions(2, 3)
	assert_true(InputMap.event_is_action(_key(KEY_J), p1 + PlayerControls.FIRE))
	assert_false(InputMap.event_is_action(_pad(JOY_BUTTON_RIGHT_STICK, 3), p1 + PlayerControls.FIRE))
	assert_true(InputMap.event_is_action(_pad(JOY_BUTTON_RIGHT_STICK, 3), p2 + PlayerControls.FIRE))
	assert_false(InputMap.event_is_action(_pad(JOY_BUTTON_RIGHT_STICK, 1), p2 + PlayerControls.FIRE), "only its own pad")
	assert_false(InputMap.event_is_action(_key(KEY_J), p2 + PlayerControls.FIRE))


func test_controls_screen_remaps_with_a_key_press() -> void:
	var panel := ControlsPanel.new()
	add_child_autofree(panel)
	panel.setup()
	panel._listen(PlayerControls.FIRE_FRONT, ControlBindings.KEYBOARD)
	panel._input(_key(KEY_I))
	assert_eq(ControlBindings.describe(PlayerControls.FIRE_FRONT, ControlBindings.KEYBOARD), "I / W")
	assert_eq(panel._slots[[PlayerControls.FIRE_FRONT, ControlBindings.KEYBOARD, 0]].text, "I")
	panel._listen(PlayerControls.FIRE_FRONT, ControlBindings.KEYBOARD, 1)
	panel._input(_key(KEY_DELETE))
	assert_eq(ControlBindings.describe(PlayerControls.FIRE_FRONT, ControlBindings.KEYBOARD), "I", "Delete empties a slot")
	panel._listen(PlayerControls.FIRE_REAR, ControlBindings.KEYBOARD)
	panel._input(_key(KEY_I))
	assert_string_contains(panel._status.text, "already used for Front weapon")
	panel._listen(PlayerControls.FIRE_REAR, ControlBindings.KEYBOARD)
	panel._input(_key(KEY_ESCAPE))
	assert_true(panel.waiting.is_empty(), "Esc cancels")
	assert_string_contains(ControlBindings.describe(PlayerControls.FIRE_REAR, ControlBindings.KEYBOARD), "Down")
	assert_string_contains(panel._help[1].text, "Hold Space / A", "help uses the bindings")
	panel.restore_defaults()
	assert_string_contains(ControlBindings.describe(PlayerControls.FIRE_FRONT, ControlBindings.KEYBOARD), "Up")
