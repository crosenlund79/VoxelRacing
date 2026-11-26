class_name TitleScreen
extends Node
## Title screen (Prototype 005, "Less Is More"): the menu diorama behind, the
## logo with its two little display cars, and a compact, icon-first menu:
## the three racing choices (Quick Race, Championship, Career) first, the other
## modes (Knockout, Battle Royale, Spectate, Multiplayer) in a small grid, and
## a row of icon buttons (achievements, settings, controls, credits, quit).
## The race setup is a voxel miniature of the circuit with the circuit and
## environment names as the selectors and a row of icons for the rest. Short
## tooltips explain every icon. Presentation only.

## choice: 0 Fire to Accelerate, 1 Fire to Brake, 2 Spectate; garage: (no
## longer used: the garage is part of Championship and Career).
signal start_requested(choice: int, garage: bool)
## CHAMPIONSHIP > START (choice: 0 Fire to Accelerate, 1 Fire to Brake).
signal championship_requested(choice: int)
## KNOCKOUT / BATTLE ROYALE (mode "knockout" / "battle").
signal mode_requested(mode: String, choice: int)
## Two-player split-screen with the joined devices (Player 1 first).
signal two_player_requested(devices: Array[int])
## LAN race (M5.1): the game root hosts / joins / cancels and reports status.
signal lan_host_requested
signal lan_join_requested(address: String)
signal lan_cancel_requested
signal quit_requested
## CAREER (the game root opens the career screen) and CREDITS.
signal career_requested
signal credits_requested

const LAYOUT := preload("res://src/track/circuit_01.tres")
const UiJuice := preload("res://src/ui/ui_juice.gd")
const VrWidgets := preload("res://src/ui/vr_widgets.gd")
const VrTips := preload("res://src/ui/vr_tips.gd")
const DevicePicker := preload("res://src/ui/device_picker.gd")
const LAP_OPTIONS: Array[int] = [3, 7, 20, 50]

## Weapons on / off preference for racing and spectating (saved).
var weapons_on := true
## Race length preference (laps) for racing and spectating (saved).
var laps := 3
## Track theme variant for racing and spectating (saved).
var track_variant := 1
## Track layout id (DevLayouts). Not saved: a launch starts on Kestrel Ridge
## (DevLayouts.DEFAULT) unless the developer "--layout=<id>" argument is given.
var layout_id: String = DevLayouts.initial_id()
## Kept for old saved settings only: every race uses the one combat system.
var combat_style := WeaponRules.UNIFIED
## Day / night (saved), the control mode (saved) and the player's car
## (0 = own car, else a won rival car; saved).
var night := false
var control_choice := 0
var player_car := 0
## The saved championship garage (set by the game), for the garage row.
var garage: PlayerGarage
## The car collection (won rival cars); set by the game before setup.
var cars: CarCollection
## The setup's mode: "quick", "spectate", "multi", "championship", "knockout", "battle".
var setup_mode := "quick"
## Championship schedule shown on the setup screen (set by the game).
var championship: ChampionshipSchedule
## Championship length: 6 rounds (the whole schedule) or the 3-round version (saved).
var championship_rounds := 6
## Achievement store shown by the ACHIEVEMENTS panel (set before setup; may be null).
var achievements: AchievementStore
## The game's music (set by the game root; a title on its own makes its own).
var music: MusicPlayer
var resolver: AssetResolver
var settings: AudioSettings
var lan_panel: LanPanel

var _own_music := false
var _sfx: AudioStreamPlayer
var _time := 0.0
var _backdrop: MenuDiorama
var _ui: CanvasLayer
var _logo: VoxelLogo
var _shade: TextureRect
## A notice over the title (e.g. a car lost in a forfeited championship).
var _notice: Label
var _notice_tween: Tween
var _main_menu: VBoxContainer
var _settings_panel: SettingsPanel
var _controls_panel: ControlsPanel
var _achievements_panel: AchievementsPanel
var _join_panel: JoinPanel
var _device_picker: PanelContainer

# ---- the race setup
var _setup: Control
var _setup_dim: ColorRect
var _setup_icon: TextureRect
var _setup_title: Label
var _setup_sub: Label
var _preview: CircuitPreview
var _circuit: VrWidgets.Cycler
var _environment: VrWidgets.Cycler
var _round_label: Label
var _keeps_label: Label
var _icon_row: HBoxContainer
var _time_button: Button
var _laps_button: Button
var _weapons_button: Button
var _control_button: Button
var _car_button: Button
var _rounds_button: Button
var _garage_button: Button
var _money_label: Label
var _start_button: Button
var _split_button: Button
var _lan_button: Button
var _setup_back: Button
var _garage_confirming := false

const MODES := {
	"quick": ["quick_race", "Quick Race", ""],
	"championship": ["championship", "Championship", ""],
	"knockout": ["knockout", "Knockout", "Last car out every lap"],
	"battle": ["battle", "Battle Royale", "Last car standing"],
	"spectate": ["spectate", "Spectate", ""],
	"multi": ["multiplayer", "Multiplayer", "Two players"],
}


func setup(p_resolver: AssetResolver, p_settings: AudioSettings) -> void:
	resolver = p_resolver
	settings = p_settings
	VrTips.load_prefs(settings.path)
	var pref := ConfigFile.new()
	if pref.load(settings.path) == OK:
		track_variant = clampi(int(pref.get_value("game", "track_variant", 1)), 1, TrackTheme.VARIANT_COUNT)
	_build_backdrop()
	_ui = CanvasLayer.new()
	_ui.layer = 5
	add_child(_ui)
	var root := Control.new()
	root.theme = HyperTheme.build(resolver)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)
	_shade = TextureRect.new()  # a soft dusk vignette behind the menu column
	var sg := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.set_color(0, Color(VrStyle.INK, 0.7))
	gr.set_color(1, Color(VrStyle.INK, 0.0))
	sg.gradient = gr
	sg.fill_from = Vector2(0, 0)
	sg.fill_to = Vector2(1, 0)
	_shade.texture = sg
	_shade.size = Vector2(620, 720)
	_shade.stretch_mode = TextureRect.STRETCH_SCALE
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_shade)
	_logo = VoxelLogo.new()
	_logo.size = Vector2(520, 220)
	_logo.position = Vector2(30, 8)
	root.add_child(_logo)
	_notice = VrWidgets.text("", 22, HyperTheme.RED, "bold", 3)
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.size = Vector2(1280, 100)
	_notice.position = Vector2(0, 600)
	_notice.visible = false
	root.add_child(_notice)

	_load_prefs()
	_build_main_menu(root)
	_build_setup(root)
	_refresh_values()

	_settings_panel = SettingsPanel.new()
	root.add_child(_settings_panel)
	_settings_panel.setup(settings)
	_settings_panel.closed.connect(_show_main)
	_settings_panel.device_requested.connect(func() -> void: _open_device_picker(true))
	_controls_panel = ControlsPanel.new()
	root.add_child(_controls_panel)
	_controls_panel.setup()
	_controls_panel.closed.connect(_show_main)
	_join_panel = JoinPanel.new()
	root.add_child(_join_panel)
	_join_panel.setup()
	_join_panel.closed.connect(_open_race)
	_join_panel.confirmed.connect(func(devices: Array[int]) -> void:
		_sfx_play("ui/ui_select")
		two_player_requested.emit(devices))
	_join_panel.reset_size()
	_join_panel.position = Vector2((1280 - _join_panel.size.x) * 0.5, 300)
	lan_panel = LanPanel.new()
	root.add_child(lan_panel)
	var saved := ConfigFile.new()
	saved.load(settings.path)
	lan_panel.setup(str(saved.get_value("game", "lan_address", "")))
	lan_panel.host_requested.connect(func() -> void:
		_sfx_play("ui/ui_select")
		lan_host_requested.emit())
	lan_panel.join_requested.connect(func(address: String) -> void:
		_sfx_play("ui/ui_select")
		var cfg := ConfigFile.new()
		cfg.load(settings.path)
		cfg.set_value("game", "lan_address", address)
		cfg.save(settings.path)
		lan_join_requested.emit(address))
	lan_panel.cancel_requested.connect(func() -> void: lan_cancel_requested.emit())
	lan_panel.closed.connect(_open_race)
	lan_panel.reset_size()
	lan_panel.position = Vector2((1280 - lan_panel.size.x) * 0.5, 290)
	_achievements_panel = AchievementsPanel.new()
	root.add_child(_achievements_panel)
	_achievements_panel.setup(achievements if achievements != null else AchievementStore.new("user://unused_achievements.cfg"), resolver)
	_achievements_panel.closed.connect(_show_main)
	_achievements_panel.refresh()
	_achievements_panel.reset_size()
	_achievements_panel.position = (Vector2(1280, 720) - _achievements_panel.size) * 0.5
	_device_picker = DevicePicker.new()
	root.add_child(_device_picker)
	_device_picker.chosen.connect(func(_k: String, _n: String) -> void:
		_sfx_play("ui/ui_select")
		_settings_panel.refresh_device()
		if _device_picker.can_cancel:
			_open_settings()
		else:
			_show_main())
	_device_picker.closed.connect(_open_settings)
	for panel in [_settings_panel, _controls_panel]:
		panel.reset_size()
		panel.position = Vector2((1280 - panel.size.x) * 0.5, maxf(16.0, (720 - panel.size.y) * 0.5 - 10))
	for panel in [_settings_panel, _controls_panel, _achievements_panel, _join_panel, lan_panel]:
		UiJuice.tree(panel)  # the same button feel on every page

	if music == null:
		music = MusicPlayer.new()
		music.name = "Music"
		add_child(music)
		_own_music = true
	music.resolver = resolver
	_sfx = AudioStreamPlayer.new()
	_sfx.bus = "Effects"
	add_child(_sfx)
	show_title()


## Shows the title (backdrop, menus, music) and focuses the first button; at
## the first launch (or when the remembered gamepad is gone) the input device
## choice comes first.
func show_title() -> void:
	_backdrop.set_active(true)
	_ui.visible = true
	set_process(true)
	music.play("music/music_menu")  # (keeps playing when it already is)
	PlayerControls.set_race_context(false)  # Space / pad A select in the title menus again
	if _logo != null:
		_logo.pick_cars()  # a new pair of display cars each time the menu opens
	if PlayerControls.device_needs_choice():
		_open_device_picker(false)
	else:
		_show_main()


## Hides everything while a race runs (keeps the scene for a quick return).
func hide_title() -> void:
	_ui.visible = false
	_backdrop.set_active(false)
	set_process(false)  # (the music carries on: the race scene takes it over)


func stop_audio() -> void:
	music.stop(0.0)
	_sfx.stop()
	_sfx.stream = null


func _process(delta: float) -> void:
	_time += delta


func _unhandled_input(event: InputEvent) -> void:
	if not _ui.visible:
		return
	if event.is_action_pressed("ui_cancel") and not _main_menu.visible and not _device_picker.visible:
		_sfx_play("ui/ui_back")
		if _join_panel.visible or lan_panel.visible:
			_open_race()
		else:
			_show_main()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------- main menu

func _build_main_menu(root: Control) -> void:
	_main_menu = VBoxContainer.new()
	_main_menu.add_theme_constant_override("separation", 6)
	_main_menu.position = Vector2(64, 236)
	root.add_child(_main_menu)
	for item in [["quick_race", "Quick Race", func() -> void: _open_setup("quick")],
			["championship", "Championship", func() -> void: _open_setup("championship")],
			["career", "Career", func() -> void:
				_sfx_play("ui/ui_select")
				career_requested.emit()]]:
		var b := VrWidgets.icon_button(item[0], "", 48, "  " + item[1], 20)
		b.custom_minimum_size = Vector2(300, 48)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(item[2])
		b.focus_entered.connect(func() -> void: _sfx_play("ui/ui_move"))
		_main_menu.add_child(b)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	_main_menu.add_child(gap)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	_main_menu.add_child(grid)
	for item in [["knockout", "Knockout", "knockout"], ["battle", "Battle Royale", "battle"],
			["spectate", "Spectate", "spectate"], ["multiplayer", "Multiplayer", "multi"]]:
		var mode: String = item[2]
		var b := VrWidgets.icon_button(item[0], MODES[mode][2], 36, " " + item[1], 15)
		b.custom_minimum_size = Vector2(147, 36)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func() -> void: _open_setup(mode))
		b.focus_entered.connect(func() -> void: _sfx_play("ui/ui_move"))
		grid.add_child(b)
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 8)
	_main_menu.add_child(gap2)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_main_menu.add_child(row)
	for item in [["achievements", "Achievements", _open_achievements], ["settings", "Settings", _open_settings],
			["controls", "Controls", _open_controls],
			["credits", "Credits", func() -> void:
				_sfx_play("ui/ui_select")
				credits_requested.emit()],
			["quit", "Quit", func() -> void: quit_requested.emit()]]:
		var b := VrWidgets.icon_button(item[0], item[1], 44)
		b.custom_minimum_size = Vector2(56, 44)
		b.pressed.connect(item[2])
		b.focus_entered.connect(func() -> void: _sfx_play("ui/ui_move"))
		row.add_child(b)


func _first_main_button() -> Button:
	return _main_menu.get_child(0) as Button


func focus_main() -> void:
	_show_main()


func _show_main() -> void:
	_show_only(_main_menu)
	_first_main_button().grab_focus()


## (Kept for developer tools: the modes are on the main menu now.)
func _open_modes() -> void:
	_show_main()


# ------------------------------------------------------------- race setup

func _build_setup(root: Control) -> void:
	_setup = Control.new()
	_setup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_setup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_setup)
	_setup_dim = ColorRect.new()
	_setup_dim.color = Color(VrStyle.INK, 0.7)
	_setup_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_setup_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_setup.add_child(_setup_dim)
	# header: back, the mode's icon and name (and a few words for the unusual modes)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.position = Vector2(36, 24)
	_setup.add_child(head)
	_setup_back = VrWidgets.icon_button("back", "Back", 38)
	_setup_back.pressed.connect(func() -> void:
		_sfx_play("ui/ui_back")
		_show_main())
	head.add_child(_setup_back)
	_setup_icon = VrWidgets.icon("quick_race", 30)
	head.add_child(_setup_icon)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", -2)
	head.add_child(titles)
	_setup_title = VrWidgets.text("Quick Race", 24, VrStyle.YELLOW)
	titles.add_child(_setup_title)
	_setup_sub = VrWidgets.text("", 13, VrStyle.PAPER_DIM)
	titles.add_child(_setup_sub)
	# the voxel miniature of the circuit: the centrepiece
	_preview = CircuitPreview.new()
	_preview.custom_minimum_size = Vector2(900, 452)
	_preview.size = Vector2(900, 452)
	_preview.position = Vector2(190, 70)
	_setup.add_child(_preview)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.position = Vector2(0, 520)
	column.custom_minimum_size = Vector2(1280, 0)
	_setup.add_child(column)
	_circuit = VrWidgets.Cycler.new(_cycle_layout, 420, 24)
	column.add_child(_circuit)
	_round_label = VrWidgets.text("", 22, VrStyle.PAPER)
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round_label.custom_minimum_size = Vector2(1280, 42)
	_round_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	column.add_child(_round_label)
	_environment = VrWidgets.Cycler.new(_cycle_track, 340, 17)
	column.add_child(_environment)
	_keeps_label = VrWidgets.text("", 14, Color("ff8a6a"))
	_keeps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_keeps_label)
	_icon_row = HBoxContainer.new()
	_icon_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_icon_row.add_theme_constant_override("separation", 8)
	column.add_child(_icon_row)
	_time_button = _setting_icon("time_day", func() -> String: return "Night race" if night else "Day race", _cycle_time)
	_laps_button = _setting_icon("laps", func() -> String: return "%d laps" % laps, _cycle_laps)
	_weapons_button = _setting_icon("weapons_on", func() -> String: return "Weapons on" if weapons_on else "Weapons off",
		func(_d: int = 1) -> void: _toggle_weapons())
	_control_button = _setting_icon("accel_fire", func() -> String:
		return "Fire to brake" if control_choice == 1 else "Fire to accelerate", _cycle_control)
	_car_button = _setting_icon("car", _car_tip, _cycle_car)
	_car_button.expand_icon = true
	_car_button.custom_minimum_size = Vector2(76, 48)
	_rounds_button = _setting_icon("rounds", func() -> String: return "%d rounds" % championship_rounds, _cycle_rounds)
	_garage_button = _setting_icon("new_garage", func() -> String:
		return "Press again to reset" if _garage_confirming else "New garage", func(_d: int = 1) -> void: _new_garage())
	_money_label = VrWidgets.text("", 15, VrStyle.YELLOW)
	_money_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon_row.add_child(_money_label)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(14, 0)
	_icon_row.add_child(spacer)
	_start_button = VrWidgets.icon_button("start", "Start race", 48, " Race", 20)
	VrWidgets.style_button(_start_button, Color("2f7d4a"))
	_start_button.add_theme_font_size_override("font_size", 20)
	_start_button.custom_minimum_size = Vector2(124, 48)
	_start_button.pressed.connect(_setup_start)
	_start_button.focus_entered.connect(func() -> void: _sfx_play("ui/ui_move"))
	_icon_row.add_child(_start_button)
	_split_button = VrWidgets.icon_button("split_screen", "Two players, one screen", 48, " Split", 18)
	VrWidgets.style_button(_split_button, Color("2f7d4a"))
	_split_button.add_theme_font_size_override("font_size", 18)
	_split_button.pressed.connect(_open_join)
	_icon_row.add_child(_split_button)
	_lan_button = VrWidgets.icon_button("lan", "Two computers", 48, " LAN", 18)
	VrWidgets.style_button(_lan_button, Color("2f7d4a"))
	_lan_button.add_theme_font_size_override("font_size", 18)
	_lan_button.pressed.connect(_open_lan)
	_icon_row.add_child(_lan_button)
	_setup.visible = false


## One setting as a small icon button: the icon shows the value, the tooltip
## says it in two or three words, Confirm / a click cycles it.
func _setting_icon(icon: String, tip: Callable, cycle: Callable) -> Button:
	var b := VrWidgets.icon_button(icon, tip, 48, "", 18)
	b.set_meta("cycle", cycle)
	b.pressed.connect(func() -> void: cycle.call(1))
	b.focus_entered.connect(func() -> void: _sfx_play("ui/ui_move"))
	_icon_row.add_child(b)
	return b


func _open_setup(mode: String) -> void:
	_sfx_play("ui/ui_select")
	setup_mode = mode
	var spec: Array = MODES.get(mode, MODES["quick"])
	_setup_icon.texture = VrWidgets.VrIcons.tex(spec[0], 30)
	_setup_title.text = spec[1]
	_setup_sub.text = spec[2]
	var champ := mode == "championship"
	var battle := mode == "battle"
	_circuit.visible = not champ and not battle
	_environment.visible = not champ
	_round_label.visible = champ or battle
	_time_button.visible = not champ
	_laps_button.visible = not champ and mode != "knockout" and not battle
	_weapons_button.visible = not battle and not champ  # (the arena and championships are always armed)
	_control_button.visible = mode != "spectate"
	_car_button.visible = mode != "spectate" and mode != "multi" and cars != null and cars.owned.size() > 0
	_rounds_button.visible = champ
	_garage_button.visible = champ and garage != null
	_money_label.visible = champ and garage != null
	_start_button.visible = mode != "multi"
	_split_button.visible = mode == "multi"
	_lan_button.visible = mode == "multi"
	_garage_confirming = false
	_refresh_values()
	_show_only(_setup)
	if _circuit.visible:
		_circuit.value.grab_focus()
	elif _environment.visible:
		_environment.value.grab_focus()
	else:
		_start_button.grab_focus()


func _setup_start() -> void:
	match setup_mode:
		"quick": _start(control_choice)
		"spectate": _start(2)
		"multi": _open_join()
		"championship":
			_sfx_play("ui/ui_select")
			championship_requested.emit(control_choice)
		"knockout", "battle":
			_sfx_play("ui/ui_select")
			mode_requested.emit(setup_mode, control_choice)


## Every value on the setup screen (selectors, icons, preview).
func _refresh_values() -> void:
	if _circuit == null:
		return
	_circuit.set_value(DevLayouts.display_name(layout_id))
	_environment.set_value(TrackTheme.load_variant(track_variant).display_name, VrStyle.PAPER_DIM.lerp(VrStyle.PAPER, 0.5))
	VrWidgets.set_icon(_time_button, "time_night" if night else "time_day")
	_laps_button.text = str(laps)
	VrWidgets.set_icon(_weapons_button, "weapons_on" if weapons_on else "weapons_off")
	VrWidgets.set_icon(_control_button, "accel_brake" if control_choice == 1 else "accel_fire")
	_rounds_button.text = str(championship_rounds)
	_update_car_button()
	if garage != null:
		_money_label.text = "$%d" % garage.money
	_garage_button.modulate = Color(1.0, 0.55, 0.45) if _garage_confirming else Color.WHITE
	_refresh_preview()


func _refresh_preview() -> void:
	if _preview == null:
		return
	_keeps_label.text = ""
	_keeps_label.visible = false
	if setup_mode == "championship" and championship != null:
		var sched := championship.with_length(championship_rounds)
		var r := sched.get_round(0)
		_preview.show_circuit(DevLayouts.load_layout(r.layout), r.variant, r.night)
		_round_label.text = "%s  -  %s" % [sched.title, DevLayouts.display_name(r.layout)]
		var keeps := keeps_text()
		_keeps_label.text = keeps
		_keeps_label.visible = keeps != ""
		return
	if setup_mode == "battle":
		_preview.show_arena(ArenaLayout.new(), track_variant, night)
		_round_label.text = "The Scrapyard"
		return
	var chosen := DevLayouts.load_layout(layout_id)
	_preview.show_circuit(chosen if chosen != null else LAYOUT, track_variant, night)


## Racing for Keeps: the warning when the chosen car is a won rival car.
func keeps_text() -> String:
	if player_car <= 0 or cars == null or not cars.owns(player_car):
		return ""
	return "Racing for keeps: win the championship or lose %s's car" % RivalRoster.short_name(player_car)


## A notice over the title for a few seconds (e.g. a forfeited car).
func show_notice(text: String) -> void:
	if _notice == null:
		return
	_notice.text = text
	_notice.visible = true
	_notice.modulate.a = 1.0
	if _notice_tween != null:
		_notice_tween.kill()
	_notice_tween = create_tween()
	_notice_tween.tween_interval(7.0)
	_notice_tween.tween_property(_notice, "modulate:a", 0.0, 1.0)
	_notice_tween.tween_callback(func() -> void: _notice.visible = false)


func _save_pref(key: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(settings.path)
	cfg.set_value("game", key, value)
	cfg.save(settings.path)


func _cycle_time(_dir: int = 1) -> void:
	_sfx_play("ui/ui_select")
	night = not night
	_save_pref("night", night)
	_refresh_values()


func _cycle_control(_dir: int = 1) -> void:
	_sfx_play("ui/ui_select")
	control_choice = 1 - control_choice
	_save_pref("control", control_choice)
	_refresh_values()


func _cycle_car(dir: int = 1) -> void:
	_sfx_play("ui/ui_select")
	var options: Array[int] = cars.choices() if cars != null else [CarCollection.OWN_CAR] as Array[int]
	player_car = options[posmod(options.find(player_car) + dir, options.size())]
	_save_pref("player_car", player_car)
	_refresh_values()  # (the Racing for Keeps warning follows the car)


func _car_tip() -> String:
	if player_car > 0 and cars != null and cars.owns(player_car):
		return "%s's car" % RivalRoster.short_name(player_car)
	return "Your car"


## After a championship reward: the car choice and the next schedule.
func refresh_car_choice() -> void:
	_refresh_values()
	_build_backdrop()  # the newly displaced rival parks the junker


## The car the player races with, as every other screen draws it.
func _player_car_name() -> String:
	if player_car > 0 and cars != null and cars.owns(player_car):
		return AssetCatalog.ai_car(player_car)
	return AssetCatalog.CAR_PLAYER


func _update_car_button() -> void:
	if cars != null and not cars.owns(player_car):
		player_car = CarCollection.OWN_CAR
	if _backdrop != null:
		_backdrop.set_player_car(_player_car_name())
	if _car_button != null and resolver != null:
		_car_button.icon = CarArt.icon(resolver, _player_car_name())


func _toggle_weapons() -> void:
	_sfx_play("ui/ui_select")
	weapons_on = not weapons_on
	_save_pref("weapons", weapons_on)
	_refresh_values()


func _cycle_laps(dir: int = 1) -> void:
	_sfx_play("ui/ui_select")
	laps = LAP_OPTIONS[posmod(LAP_OPTIONS.find(laps) + dir, LAP_OPTIONS.size())]
	_save_pref("laps", laps)
	_refresh_values()


func _cycle_rounds(_dir: int = 1) -> void:
	_sfx_play("ui/ui_select")
	championship_rounds = 3 if championship_rounds == 6 else 6
	_save_pref("championship_rounds", championship_rounds)
	_refresh_values()


## The championship garage: pressing twice starts over (money, weapons and car reset).
func _new_garage() -> void:
	if garage == null:
		return
	_sfx_play("ui/ui_select")
	if not _garage_confirming:
		_garage_confirming = true
	else:
		_garage_confirming = false
		garage.reset()
	_refresh_values()


func _cycle_track(dir: int = 1) -> void:
	_sfx_play("ui/ui_select")
	track_variant = posmod(track_variant - 1 + dir, TrackTheme.VARIANT_COUNT) + 1
	_save_pref("track_variant", track_variant)
	_refresh_values()


## The player layouts in turn (not saved).
func _cycle_layout(dir: int = 1) -> void:
	_sfx_play("ui/ui_select")
	var ids := DevLayouts.ids(layout_id)
	layout_id = ids[posmod(ids.find(layout_id) + dir, ids.size())]
	_refresh_values()


func _load_prefs() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(settings.path) == OK:
		weapons_on = bool(cfg.get_value("game", "weapons", true))
		var saved := int(cfg.get_value("game", "laps", 3))
		laps = saved if LAP_OPTIONS.has(saved) else 3
		championship_rounds = 3 if int(cfg.get_value("game", "championship_rounds", 6)) == 3 else 6
		night = bool(cfg.get_value("game", "night", false))
		control_choice = clampi(int(cfg.get_value("game", "control", 0)), 0, 1)
		player_car = clampi(int(cfg.get_value("game", "player_car", 0)), 0, 9)


func _start(choice: int, _garage: bool = false) -> void:
	_sfx_play("ui/ui_select")
	start_requested.emit(choice, false)


## Multiplayer: back to its setup (from the split-screen join or LAN pages).
func _open_race() -> void:
	_open_setup("multi")


# ------------------------------------------------------------- other pages

func _open_settings() -> void:
	_sfx_play("ui/ui_select")
	_settings_panel.refresh_device()
	_show_only(_settings_panel)
	_settings_panel.focus_first()


func _open_device_picker(from_settings: bool) -> void:
	_show_only(_device_picker)
	_device_picker.open(from_settings)


func _open_lan() -> void:
	_sfx_play("ui/ui_select")
	_show_only(lan_panel)
	lan_panel.open()


func _open_join() -> void:
	_sfx_play("ui/ui_select")
	_join_panel.open()
	_show_only(_join_panel)
	_join_panel.reset_size()


func _open_achievements() -> void:
	_sfx_play("ui/ui_select")
	_achievements_panel.refresh()
	_show_only(_achievements_panel)
	_achievements_panel.focus_first()


func _open_controls() -> void:
	_sfx_play("ui/ui_select")
	_show_only(_controls_panel)
	_controls_panel.focus_first()


func _show_only(node: Control) -> void:
	for n in [_main_menu, _setup, _settings_panel, _controls_panel, _achievements_panel, _join_panel, lan_panel, _device_picker]:
		if n != null:
			n.visible = n == node
	if _preview != null:
		_preview.visible = node == _setup
	var on_main := node == _main_menu or node == _device_picker
	_logo.visible = on_main
	_shade.visible = on_main
	_page_in(node)


## The page transition: the page fades in while sliding a few pixels into
## place; the main menu's buttons follow one after another.
var _page_tween: Tween
var _paged: Control
var _paged_home := Vector2.ZERO


func _page_in(node: Control) -> void:
	if _page_tween != null and _page_tween.is_valid():
		_page_tween.kill()
	if _paged != null and is_instance_valid(_paged):  # a transition cut short lands where it belongs
		_paged.position = _paged_home
		_paged.modulate.a = 1.0
		for c in _paged.get_children():
			if c is Control:
				c.modulate.a = 1.0
	_paged = node
	_paged_home = node.position
	node.modulate.a = 0.0
	node.position.x = _paged_home.x + 18.0
	var tw := create_tween().set_parallel(true)
	_page_tween = tw
	tw.tween_property(node, "modulate:a", 1.0, 0.18)
	tw.tween_property(node, "position:x", _paged_home.x, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if node == _main_menu:
		var k := 0
		for c in node.get_children():
			if c is Control and c.visible:
				c.modulate.a = 0.0
				tw.tween_property(c, "modulate:a", 1.0, 0.14).set_delay(0.04 * k)
				k += 1


func _sfx_play(logical: String) -> void:
	if _sfx == null:
		return
	_sfx.stream = resolver.get_audio(logical)
	_sfx.play()


func _build_backdrop() -> void:
	if _backdrop != null and is_instance_valid(_backdrop):
		_backdrop.queue_free()
	_backdrop = MenuDiorama.new()
	_backdrop.name = "Diorama"
	add_child(_backdrop)
