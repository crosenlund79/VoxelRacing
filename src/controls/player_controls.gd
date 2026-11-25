class_name PlayerControls
extends RefCounted
## Joystick-style controls for one player: left/right steer, one fire button,
## joystick forward / backwards fire the front / rear weapon (original manual).
## Actions are only created if the project does not already define them, so they
## can be rebound in Project Settings > Input Map.

const STEER_LEFT := "steer_left"
const STEER_RIGHT := "steer_right"
const FIRE := "fire"
## Joystick forward / backwards: front / rear weapon (M3).
const FIRE_FRONT := "fire_front"
const FIRE_REAR := "fire_rear"
## Weapon cycling (2026-11-23): the next carried type for the front / rear slot.
const CYCLE_FRONT := "cycle_front"
const CYCLE_REAR := "cycle_rear"
## Spectator mode only: switch history view, toggle simulation speed, leave.
const HISTORY_VIEW := "history_view"
const SIM_SPEED := "sim_speed"
const BACK := "back"
## Spectator: hide/show the race history panel.
const TOGGLE_PANEL := "toggle_panel"
## Lighting pilot on / off (presentation only).
const TOGGLE_LIGHTING := "toggle_lighting"
## Grid panel: Classic / Tactical combat style.
const TOGGLE_STYLE := "toggle_style"
const STICK_DEADZONE := 0.5
## Device id for a player on the keyboard (two-player assignment).
const KEYBOARD := -1
## Menu confirmation (results, standings, rewards, prompts): never the Fire
## button, so shooting can never dismiss a screen.
const CONFIRM := "confirm"
## Per-player driving actions (prefix + name) for two-player races.
const PLAYER_ACTIONS: Array[String] = [STEER_LEFT, STEER_RIGHT, FIRE, FIRE_FRONT, FIRE_REAR, CYCLE_FRONT, CYCLE_REAR, BACK, HISTORY_VIEW, TOGGLE_STYLE, CONFIRM]
## (Couch players share TOGGLE_PANEL / TOGGLE_LIGHTING / SIM_SPEED through the
## base actions: they are not per-player.)


## Prefix of player n's own actions (two-player races), e.g. "p2_".
static func player_prefix(player_number: int) -> String:
	return "p%d_" % player_number


## (Re)binds player n's driving actions to one device only: a joypad id, or
## KEYBOARD. They are copied from the current (possibly remapped) bindings:
## the keyboard player gets the keys, a pad player the pad's buttons and
## sticks with its device id, so two pads never share input.
static func ensure_player_actions(player_number: int, device: int) -> String:
	ensure_actions()
	var prefix := player_prefix(player_number)
	for a in PLAYER_ACTIONS:
		if InputMap.has_action(prefix + a):
			InputMap.erase_action(prefix + a)
		InputMap.add_action(prefix + a, STICK_DEADZONE)
		for e in InputMap.action_get_events(a):
			if device == KEYBOARD and e is InputEventKey:
				InputMap.action_add_event(prefix + a, e.duplicate())
			elif device != KEYBOARD and (e is InputEventJoypadButton or e is InputEventJoypadMotion):
				var d: InputEvent = e.duplicate()
				d.device = device
				InputMap.action_add_event(prefix + a, d)
	return prefix


## Gameplay context (a race and the screens after it): Godot's ui_accept
## (focused buttons) loses Space and the pad's A - the Fire buttons - so
## shooting never presses a button; Enter / Start still do. The title menus
## restore them.
static func set_race_context(on: bool) -> void:
	if on:
		for e in InputMap.action_get_events("ui_accept"):
			if _is_fire_event(e):
				_removed_accept.append(e)
				InputMap.action_erase_event("ui_accept", e)
		# Confirm (pad Start, remapped keys) presses focused buttons instead,
		# so a controller can still use the race menu, garage and standings.
		for e in InputMap.action_get_events(CONFIRM) if InputMap.has_action(CONFIRM) else []:
			if not _ui_has("ui_accept", e):
				InputMap.action_add_event("ui_accept", e)
				_added_accept.append(e)
	else:
		for e in _added_accept:
			InputMap.action_erase_event("ui_accept", e)
		_added_accept.clear()
		for e in _removed_accept:
			if not _ui_has("ui_accept", e):
				InputMap.action_add_event("ui_accept", e)
		_removed_accept.clear()


static func _code(k: InputEventKey) -> int:
	return k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode


## Same key / button / stick direction already in the action (any device).
static func _ui_has(action: String, e: InputEvent) -> bool:
	for f in InputMap.action_get_events(action):
		if f is InputEventKey and e is InputEventKey and _code(f) == _code(e):
			return true
		if f is InputEventJoypadButton and e is InputEventJoypadButton and f.button_index == e.button_index:
			return true
		if f is InputEventJoypadMotion and e is InputEventJoypadMotion and f.axis == e.axis and signf(f.axis_value) == signf(e.axis_value):
			return true
	return false


static var _removed_accept: Array[InputEvent] = []
static var _added_accept: Array[InputEvent] = []


## True when an event is bound to Fire (any player).
static func _is_fire_event(e: InputEvent) -> bool:
	for f in InputMap.action_get_events(FIRE):
		if f.is_match(e, true) or e.is_match(f, true):
			return true
	if e is InputEventKey and (e.physical_keycode == KEY_SPACE or e.keycode == KEY_SPACE):
		return true
	return e is InputEventJoypadButton and e.button_index == JOY_BUTTON_A


static func _bind(action: String, events: Array) -> void:
	for e in events:
		InputMap.action_add_event(action, e)


static func ensure_actions() -> void:
	_add(STEER_LEFT, [_key(KEY_LEFT), _key(KEY_A), _joy_button(JOY_BUTTON_DPAD_LEFT), _joy_axis(JOY_AXIS_LEFT_X, -1.0)])
	_add(STEER_RIGHT, [_key(KEY_RIGHT), _key(KEY_D), _joy_button(JOY_BUTTON_DPAD_RIGHT), _joy_axis(JOY_AXIS_LEFT_X, 1.0)])
	_add(FIRE, [_key(KEY_SPACE), _key(KEY_CTRL), _joy_button(JOY_BUTTON_A)])
	_add(FIRE_FRONT, [_key(KEY_UP), _key(KEY_W), _joy_button(JOY_BUTTON_DPAD_UP), _joy_axis(JOY_AXIS_LEFT_Y, -1.0)])
	_add(FIRE_REAR, [_key(KEY_DOWN), _key(KEY_S), _joy_button(JOY_BUTTON_DPAD_DOWN), _joy_axis(JOY_AXIS_LEFT_Y, 1.0)])
	_add(CYCLE_FRONT, [_key(KEY_Q), _joy_button(JOY_BUTTON_LEFT_SHOULDER)])
	_add(CYCLE_REAR, [_key(KEY_E), _joy_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)])
	_add(HISTORY_VIEW, [_key(KEY_TAB), _joy_button(JOY_BUTTON_Y)])
	_add(SIM_SPEED, [_key(KEY_F), _joy_button(JOY_BUTTON_X)])
	_add(BACK, [_key(KEY_ESCAPE), _joy_button(JOY_BUTTON_B)])
	_add(CONFIRM, [_key(KEY_ENTER), _key(KEY_KP_ENTER), _joy_button(JOY_BUTTON_START)])
	_add(TOGGLE_PANEL, [_key(KEY_H), _joy_button(JOY_BUTTON_BACK)])
	_add(TOGGLE_LIGHTING, [_key(KEY_L)])
	_add(TOGGLE_STYLE, [_key(KEY_C), _joy_button(JOY_BUTTON_RIGHT_SHOULDER)])
	# Godot's menus accept / cancel only from the keyboard by default: a
	# controller selects with A or Start and goes back with B.
	for e in [_joy_button(JOY_BUTTON_A), _joy_button(JOY_BUTTON_START)]:
		if not _ui_has("ui_accept", e):
			InputMap.action_add_event("ui_accept", e)
	if not _ui_has("ui_cancel", _joy_button(JOY_BUTTON_B)):
		InputMap.action_add_event("ui_cancel", _joy_button(JOY_BUTTON_B))


## The player's current binding for an action, for on-screen hints: the first
## keyboard key and the first controller input, e.g. "Enter / Start".
## Couch players' own actions show their own device's half.
static func key_text(action: String) -> String:
	var key := ""
	var pad := ""
	for e in InputMap.action_get_events(action) if InputMap.has_action(action) else []:
		if e is InputEventKey and key == "":
			key = OS.get_keycode_string(e.physical_keycode if e.physical_keycode != KEY_NONE else e.keycode)
		elif (e is InputEventJoypadButton or e is InputEventJoypadMotion) and pad == "":
			pad = pad_short(e)
	if key != "" and pad != "":
		return "%s / %s" % [key, pad]
	return key if key != "" else (pad if pad != "" else "?")


## "{confirm}: next race" -> "Enter / Start: next race": every {action} in the
## text becomes the player's binding (key_text).
static func fmt(text: String) -> String:
	var out := text
	for a in [STEER_LEFT, STEER_RIGHT, FIRE, FIRE_FRONT, FIRE_REAR, CYCLE_FRONT, CYCLE_REAR, HISTORY_VIEW, SIM_SPEED, BACK, TOGGLE_PANEL,
			TOGGLE_LIGHTING, TOGGLE_STYLE, CONFIRM]:
		out = out.replace("{%s}" % a, key_text(a))
	return out


## Short controller name for hints ("A", "Start", "D-pad up", "L stick").
static func pad_short(e: InputEvent) -> String:
	if e is InputEventJoypadButton:
		var names := {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
			JOY_BUTTON_START: "Start", JOY_BUTTON_BACK: "Select", JOY_BUTTON_LEFT_SHOULDER: "LB",
			JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_DPAD_UP: "D-pad up", JOY_BUTTON_DPAD_DOWN: "D-pad down",
			JOY_BUTTON_DPAD_LEFT: "D-pad left", JOY_BUTTON_DPAD_RIGHT: "D-pad right", JOY_BUTTON_LEFT_STICK: "L3",
			JOY_BUTTON_RIGHT_STICK: "R3"}
		return names.get(e.button_index, "Button %d" % e.button_index)
	if e is InputEventJoypadMotion:
		var axes := {JOY_AXIS_LEFT_X: "L stick", JOY_AXIS_LEFT_Y: "L stick", JOY_AXIS_RIGHT_X: "R stick",
			JOY_AXIS_RIGHT_Y: "R stick", JOY_AXIS_TRIGGER_LEFT: "LT", JOY_AXIS_TRIGGER_RIGHT: "RT"}
		return axes.get(e.axis, "Axis %d" % e.axis)
	return "?"


## Steering input -1 .. +1: keys and d-pad give a full -1 / 0 / +1; a stick
## is proportional (past STEER_DEADZONE, with a gentle response curve so small
## movements make small corrections and a full tilt is full lock). prefix
## selects a player's own actions ("" = the default single-player actions).
static func steer(prefix: String = "") -> float:
	return _axis(prefix + STEER_RIGHT) - _axis(prefix + STEER_LEFT)


## Stick steering below this tilt is ignored; the curve's exponent.
const STEER_DEADZONE := 0.2
const STEER_CURVE := 1.5


static func _axis(action: String) -> float:
	if not InputMap.has_action(action):
		return 0.0
	var raw := Input.get_action_raw_strength(action)
	if raw <= 0.0:
		raw = Input.get_action_strength(action)  # Input.action_press (scripts) sets only this
	if raw <= 0.0:
		return 0.0
	if raw >= 0.999:
		return 1.0  # keys, d-pad, a full tilt
	return pow(clampf((raw - STEER_DEADZONE) / (1.0 - STEER_DEADZONE), 0.0, 1.0), STEER_CURVE)


static func fire_held(prefix: String = "") -> bool:
	return Input.is_action_pressed(prefix + FIRE)


static func _add(action: String, events: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, STICK_DEADZONE)
	for event in events:
		InputMap.action_add_event(action, event)


static func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


## device: the joypad the event belongs to (-1 = any pad: the single player
## can use whichever controller is connected; couch players get their own).
static func _joy_button(button: JoyButton, device: int = -1) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.device = device
	return e


static func _joy_axis(axis: JoyAxis, value: float, device: int = -1) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	e.device = device
	return e
