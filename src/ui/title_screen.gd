class_name TitleScreen
extends Node
## Title screen: the circuit with its scenery and the ten cars parked on the
## grid as a slowly panning painted backdrop, the logo, and the menus
## (Race / Spectate / Settings / Controls / Quit). Presentation only.

## choice: 0 Fire to Accelerate, 1 Fire to Brake, 2 Spectate; garage: garage race.
signal start_requested(choice: int, garage: bool)
## GO RACING! > CHAMPIONSHIP > START (choice: 0 Fire to Accelerate, 1 Fire to Brake).
signal championship_requested(choice: int)
## GO RACING! > KNOCKOUT / BATTLE ROYALE (mode "knockout" / "battle").
signal mode_requested(mode: String, choice: int)
## Two-player split-screen with the joined devices (Player 1 first).
signal two_player_requested(devices: Array[int])
## LAN race (M5.1): the game root hosts / joins / cancels and reports status.
signal lan_host_requested
signal lan_join_requested(address: String)
signal lan_cancel_requested
## Weapons ON / No Guns preference for both racing and spectating (saved).
var weapons_on := true
var _weapons_button: Button
## Race length preference (laps) for racing and spectating (saved).
var laps := 3
var _laps_button: Button
## Track theme variant for racing and spectating (saved); the backdrop shows it.
var track_variant := 1
var _track_button: Button
## Track layout id (DevLayouts). Not saved: a launch starts on Kestrel Ridge
## (DevLayouts.DEFAULT) unless the developer "--layout=<id>" argument is given.
var layout_id: String = DevLayouts.initial_id()
var _layout_button: Button
## Combat style preference (WeaponRules.Style) for racing and spectating (saved).
var combat_style := 0
var _style_button: Button
## TIME: DAY / NIGHT (saved), the control mode (saved) and the player's car
## (0 = own car, else a won rival car; saved).
var night := false
var _time_button: Button
var control_choice := 0
var _control_button: Button
var player_car := 0
var _car_button: Button
var _rounds_button: Button
var _garage_button: Button
var _garage_confirming := false
## The saved garage career (set by the game), for the GARAGE row.
var garage: PlayerGarage
## The car collection (won rival cars); set by the game before setup.
var cars: CarCollection
## GO RACING!: the modes, and the shared race setup (mode: "quick",
## "garage", "spectate", "multi", "championship").
var _mode_menu: VBoxContainer
var _setup: PanelContainer
var _setup_title: Label
var _setup_note: Label
var _setup_rows: VBoxContainer
var _preview: CircuitPreview
var setup_mode := "quick"
## Championship schedule shown on the setup screen (set by the game).
var championship: ChampionshipSchedule
## Championship length: 6 rounds (the whole schedule) or the 3-round version (saved).
var championship_rounds := 6
signal quit_requested
## CAREER (the game root opens the career screen) and CREDITS.
signal career_requested
signal credits_requested

const LAYOUT := preload("res://src/track/circuit_01.tres")
const UiJuice := preload("res://src/ui/ui_juice.gd")

var resolver: AssetResolver
var settings: AudioSettings
var _backdrop: MenuDiorama
## The player's parked car on the backdrop (the last grid slot).
var _ui: CanvasLayer
var _logo: VoxelLogo
## A notice over the title (e.g. a car lost in a forfeited championship).
var _notice: Label
var _notice_tween: Tween
var _main_menu: VBoxContainer
var _race_menu: VBoxContainer
var _settings_panel: SettingsPanel
var _controls_panel: ControlsPanel
var _achievements_panel: AchievementsPanel
var _join_panel: JoinPanel
var lan_panel: LanPanel
## Achievement store shown by the ACHIEVEMENTS panel (set before setup; may be null).
var achievements: AchievementStore
## The game's music (set by the game root; a title on its own makes its own).
var music: MusicPlayer
var _own_music := false
var _sfx: AudioStreamPlayer
var _time := 0.0


func setup(p_resolver: AssetResolver, p_settings: AudioSettings) -> void:
	resolver = p_resolver
	settings = p_settings
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
	_ui.add_child(root)
	var shade := TextureRect.new()  # a soft dusk vignette behind the menu column
	var sg := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.set_color(0, Color(VrStyle.INK, 0.78))
	gr.set_color(1, Color(VrStyle.INK, 0.0))
	sg.gradient = gr
	sg.fill_from = Vector2(0, 0)
	sg.fill_to = Vector2(1, 0)
	shade.texture = sg
	shade.size = Vector2(760, 720)
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	_logo = VoxelLogo.new()
	_logo.size = Vector2(560, 236)
	_logo.position = Vector2(20, 4)
	root.add_child(_logo)
	_notice = HyperTheme.label("", 30, HyperTheme.RED, 700)
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.size = Vector2(1280, 120)
	_notice.position = Vector2(0, 590)
	_notice.visible = false
	root.add_child(_notice)

	_load_weapons_pref()
	_main_menu = _menu(root, [["CAREER", func() -> void:
			_sfx_play("ui/ui_select")
			career_requested.emit()],
		["GO RACING!", _open_modes], ["ACHIEVEMENTS", _open_achievements],
		["SETTINGS", _open_settings], ["CONTROLS", _open_controls],
		["CREDITS", func() -> void:
			_sfx_play("ui/ui_select")
			credits_requested.emit()],
		["QUIT", func() -> void: quit_requested.emit()]],
		380, 40, 6)
	(_main_menu.get_child(0) as Button).add_theme_font_size_override("font_size", 28)
	(_main_menu.get_child(0) as Button).custom_minimum_size.y = 58
	_mode_menu = _menu(root, [["QUICK RACE", func() -> void: _open_setup("quick")],
		["CHAMPIONSHIP", func() -> void: _open_setup("championship")],
		["KNOCKOUT", func() -> void: _open_setup("knockout")],
		["BATTLE ROYALE", func() -> void: _open_setup("battle")],
		["SPECTATE", func() -> void: _open_setup("spectate")],
		["MULTIPLAYER", func() -> void: _open_setup("multi")],
		["BACK", _show_main]], 420, 40, 5)
	_build_setup(root)
	_update_track_button()
	_update_layout_button()
	_update_weapons_button()
	_update_style_button()
	_update_laps_button()
	_update_time_button()
	_update_control_button()
	_update_car_button()
	_race_menu = _menu(root, [["TWO PLAYERS: SPLIT SCREEN", _open_join],
		["TWO PLAYERS: LAN / ONLINE", _open_lan],
		["BACK", func() -> void: _open_setup("multi")]], 520)
	var race_title := HyperTheme.label("MULTIPLAYER: two players on one screen, or two computers", 18, HyperTheme.GOLD, 600)
	race_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_race_menu.add_child(race_title)
	_race_menu.move_child(race_title, 0)

	_settings_panel = SettingsPanel.new()
	root.add_child(_settings_panel)
	_settings_panel.setup(settings)
	_settings_panel.closed.connect(_show_main)
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
	for panel in [_settings_panel, _controls_panel]:
		panel.reset_size()
		panel.position = Vector2((1280 - panel.size.x) * 0.5, 250 if panel == _settings_panel else (720 - panel.size.y) * 0.5 - 10)
	for panel in [_settings_panel, _controls_panel, _achievements_panel, _join_panel, lan_panel]:
		UiJuice.tree(panel)  # the same button feel on every page
	footer = HyperTheme.label("", 15, HyperTheme.CREAM_DIM, 500)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.size = Vector2(1280, 24)
	footer.position = Vector2(0, 686)
	root.add_child(footer)

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


## Shows the title (backdrop, menus, music) and focuses the first button.
func show_title() -> void:
	_backdrop.set_active(true)
	_ui.visible = true
	set_process(true)
	music.play("music/music_menu")  # (keeps playing when it already is)
	PlayerControls.set_race_context(false)  # Space / pad A select in the title menus again
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
	if _setup.visible and (event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right")):
		var focused := get_viewport().gui_get_focus_owner()
		if focused is Button and focused.has_meta("cycle"):
			(focused.get_meta("cycle") as Callable).call(-1 if event.is_action_pressed("ui_left") else 1)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("ui_cancel") and not _main_menu.visible:
		_sfx_play("ui/ui_back")
		if _setup.visible or _race_menu.visible:
			_open_modes()
		else:
			_show_main()
		get_viewport().set_input_as_handled()


# ------------------------------------------------- GO RACING! and race setup

func _open_modes() -> void:
	_sfx_play("ui/ui_select")
	_show_only(_mode_menu)
	(_mode_menu.get_child(0) as Button).grab_focus()


func _build_setup(root: Control) -> void:
	_setup = PanelContainer.new()
	_setup.position = Vector2(40, 40)
	_setup.custom_minimum_size = Vector2(1200, 600)
	root.add_child(_setup)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 26)
	_setup.add_child(h)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	h.add_child(left)
	_setup_title = HyperTheme.label("QUICK RACE", 30, HyperTheme.GOLD, 700)
	_setup_title.custom_minimum_size = Vector2(520, 52)
	left.add_child(_setup_title)
	_setup_rows = VBoxContainer.new()
	_setup_rows.add_theme_constant_override("separation", 6)
	left.add_child(_setup_rows)
	_layout_button = _setup_row("CIRCUIT", _cycle_layout)
	_track_button = _setup_row("ENVIRONMENT", _cycle_track)
	_time_button = _setup_row("TIME", _cycle_time)
	_laps_button = _setup_row("LAPS", _cycle_laps)
	_weapons_button = _setup_row("WEAPONS", func(_d: int = 1) -> void: _toggle_weapons())
	_style_button = _setup_row("COMBAT", func(_d: int = 1) -> void: _toggle_style())
	_control_button = _setup_row("CONTROL", _cycle_control)
	_car_button = _setup_row("CAR", _cycle_car)
	_rounds_button = _setup_row("ROUNDS", _cycle_rounds)
	_garage_button = _setup_row("GARAGE", func(_d: int = 1) -> void: _new_garage())
	var go := Button.new()
	go.text = "START"
	go.custom_minimum_size = Vector2(520, 46)
	go.add_theme_font_size_override("font_size", 24)
	go.pressed.connect(_setup_start)
	go.focus_entered.connect(func() -> void: _sfx_play("ui/ui_move"))
	_setup_rows.add_child(UiJuice.button(go))
	var back := Button.new()
	back.text = "BACK"
	back.custom_minimum_size = Vector2(520, 38)
	back.pressed.connect(_open_modes)
	_setup_rows.add_child(UiJuice.button(back))
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	h.add_child(right)
	_preview = CircuitPreview.new()
	_preview.custom_minimum_size = Vector2(600, 440)
	right.add_child(_preview)
	_setup_note = HyperTheme.label("", 19, HyperTheme.CREAM, 600)
	_setup_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_setup_note.custom_minimum_size = Vector2(600, 0)
	right.add_child(_setup_note)
	_setup.visible = false


## One setup row: a button that cycles its value (Enter: next; Left / Right: either way).
func _setup_row(_tag: String, cycle: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(520, 42)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 19)
	b.set_meta("cycle", cycle)
	b.pressed.connect(func() -> void: cycle.call(1))
	b.focus_entered.connect(func() -> void: _sfx_play("ui/ui_move"))
	b.mouse_entered.connect(b.grab_focus)
	UiJuice.button(b)
	_setup_rows.add_child(b)
	return b


func _open_setup(mode: String) -> void:
	_sfx_play("ui/ui_select")
	setup_mode = mode
	var titles := {"quick": "QUICK RACE  -  standard weapons", "garage": "GARAGE RACE  -  prize money, your own weapons",
		"spectate": "SPECTATE  -  the nine rivals race", "multi": "MULTIPLAYER  -  two players",
		"championship": "CHAMPIONSHIP  -  your garage, prize money, points", "knockout": "KNOCKOUT  -  last place out every lap",
		"battle": "BATTLE ROYALE  -  last car standing"}
	_setup_title.text = titles.get(mode, mode.to_upper())
	var champ := mode == "championship"
	var battle := mode == "battle"
	for b in [_layout_button, _track_button, _time_button, _laps_button]:
		b.visible = not champ
	_laps_button.visible = not champ and mode != "knockout" and not battle
	_layout_button.visible = not champ and not battle
	_weapons_button.visible = not battle  # the arena is always armed (cooldown weapons)
	_style_button.visible = not battle
	_control_button.visible = mode != "spectate"
	_car_button.visible = mode != "spectate" and mode != "multi"
	_rounds_button.visible = champ
	_garage_button.visible = (mode == "garage" or mode == "championship") and garage != null
	_garage_confirming = false
	_update_garage_button()
	_update_rounds_button()
	_refresh_preview()
	_show_only(_setup)
	_setup.reset_size()
	(_weapons_button if champ else (_track_button if battle else _layout_button)).grab_focus()


func _setup_start() -> void:
	match setup_mode:
		"quick": _start(control_choice)
		"garage": _start(control_choice, true)
		"spectate": _start(2)
		"multi": _open_race()
		"championship":
			_sfx_play("ui/ui_select")
			championship_requested.emit(control_choice)
		"knockout", "battle":
			_sfx_play("ui/ui_select")
			mode_requested.emit(setup_mode, control_choice)


func _refresh_preview() -> void:
	if _preview == null:
		return
	_setup_note.remove_theme_color_override("font_color")
	_preview.visible = true  # (Battle Royale: the Scrapyard diorama)
	if setup_mode == "championship" and championship != null:
		var sched := championship.with_length(championship_rounds)
		var r := sched.get_round(0)
		_preview.show_circuit(DevLayouts.load_layout(r.layout), r.variant, r.night)
		_setup_note.text = sched.describe()
		var keeps := keeps_text()
		if keeps != "":
			_setup_note.text = keeps + "\n\n" + _setup_note.text
			_setup_note.add_theme_color_override("font_color", Color("ff8a6a"))
		return
	if setup_mode == "battle":
		_preview.show_arena(ArenaLayout.new(), track_variant, night)
		_setup_note.text = "THE SCRAPYARD  -  %s, %s\nTen cars, one arena, no respawns: the last car standing wins.\nUnlimited missiles and mines on cooldowns (no homing or super missiles).\nAfter a while the safe zone shrinks." % [
			TrackTheme.load_variant(track_variant).display_name, "night" if night else "day"]
		return
	var chosen := DevLayouts.load_layout(layout_id)
	_preview.show_circuit(chosen if chosen != null else LAYOUT, track_variant, night)
	if setup_mode == "knockout":
		_setup_note.text = "%s  -  %s, %s\nTen cars, nine laps: each time the leader completes a lap, the last car still in is out.\nThe last one standing wins." % [
			DevLayouts.display_name(layout_id), TrackTheme.load_variant(track_variant).display_name, "night" if night else "day"]
		return
	var theme := TrackTheme.load_variant(track_variant)
	var feel := {1: "Baseline grip, clear skies.", 2: "Rain: wet road, a little less grip and response.",
		3: "Snow: lower grip, longer braking, more sliding.",
		4: "Professional circuit: a little more grip and top speed.",
		5: "Toy cars on a desk: much quicker acceleration."}
	_setup_note.text = "%s  -  %s, %s\n%s" % [DevLayouts.display_name(layout_id), theme.display_name,
		"night" if night else "day", feel.get(track_variant, "")]


## Racing for Keeps: the warning when the chosen car is a won rival car.
func keeps_text() -> String:
	if player_car <= 0 or cars == null or not cars.owns(player_car):
		return ""
	return "RACING FOR KEEPS!\nWIN THE CHAMPIONSHIP - OR LOSE %s'S CAR." % RivalRoster.short_name(player_car).to_upper()


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


func _cycle_time(_dir: int = 1) -> void:
	_sfx_play("ui/ui_select")
	night = not night
	_update_time_button()
	_save_pref("night", night)
	_refresh_preview()


func _update_time_button() -> void:
	_time_button.text = "TIME:  %s" % ("NIGHT" if night else "DAY")


func _cycle_control(_dir: int = 1) -> void:
	_sfx_play("ui/ui_select")
	control_choice = 1 - control_choice
	_update_control_button()
	_save_pref("control", control_choice)


func _update_control_button() -> void:
	_control_button.text = "CONTROL:  %s" % ("FIRE TO BRAKE" if control_choice == 1 else "FIRE TO ACCELERATE")


func _cycle_car(dir: int = 1) -> void:
	_sfx_play("ui/ui_select")
	var options: Array[int] = cars.choices() if cars != null else [CarCollection.OWN_CAR] as Array[int]
	player_car = options[posmod(options.find(player_car) + dir, options.size())]
	_update_car_button()
	_refresh_preview()  # the Racing for Keeps warning follows the car
	_save_pref("player_car", player_car)


## After a championship reward: the CAR option and the next schedule.
func refresh_car_choice() -> void:
	_update_car_button()
	_refresh_preview()
	_build_backdrop()  # the newly displaced rival parks the junker


## The car the player races with, as every other screen draws it: their own
## car, or the chosen won rival car in its original colours (CarArt: body +
## shared wheels, overrides and Artwork Mode apply).
func _player_car_name() -> String:
	if player_car > 0 and cars != null and cars.owns(player_car):
		return AssetCatalog.ai_car(player_car)
	return AssetCatalog.CAR_PLAYER


## The player's parked car on the backdrop follows the CAR choice at once.
func _refresh_backdrop_player() -> void:
	if _backdrop != null:
		_backdrop.set_player_car(_player_car_name())


func _update_car_button() -> void:
	if cars != null and not cars.owns(player_car):
		player_car = CarCollection.OWN_CAR
	_refresh_backdrop_player()
	var owned := cars.owned.size() if cars != null else 0
	_car_button.text = "CAR:  %s  (%d of 9 rival cars won)" % ["YOUR OWN" if player_car == CarCollection.OWN_CAR
		else RivalRoster.short_name(player_car).to_upper() + "'S", owned]


func _save_pref(key: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(settings.path)
	cfg.set_value("game", key, value)
	cfg.save(settings.path)


func _toggle_weapons() -> void:
	_sfx_play("ui/ui_select")
	weapons_on = not weapons_on
	_update_weapons_button()
	var cfg := ConfigFile.new()
	cfg.load(settings.path)
	cfg.set_value("game", "weapons", weapons_on)
	cfg.save(settings.path)


func _cycle_laps(dir: int = 1) -> void:
	_sfx_play("ui/ui_select")
	var options: Array[int] = [3, 7, 20, 50]
	laps = options[posmod(options.find(laps) + dir, options.size())]
	_update_laps_button()
	var cfg := ConfigFile.new()
	cfg.load(settings.path)
	cfg.set_value("game", "laps", laps)
	cfg.save(settings.path)


func _toggle_style() -> void:
	_sfx_play("ui/ui_select")
	combat_style = WeaponRules.Style.TACTICAL if combat_style == WeaponRules.Style.CLASSIC else WeaponRules.Style.CLASSIC
	_update_style_button()
	var cfg := ConfigFile.new()
	cfg.load(settings.path)
	cfg.set_value("game", "combat_style", combat_style)
	cfg.save(settings.path)


func _update_style_button() -> void:
	_style_button.text = "COMBAT:  %s" % WeaponRules.style_name(combat_style)


func _cycle_rounds(_dir: int = 1) -> void:
	_sfx_play("ui/ui_select")
	championship_rounds = 3 if championship_rounds == 6 else 6
	_update_rounds_button()
	_refresh_preview()
	var cfg := ConfigFile.new()
	cfg.load(settings.path)
	cfg.set_value("game", "championship_rounds", championship_rounds)
	cfg.save(settings.path)


## Garage career row: what is saved; pressing twice starts over.
func _update_garage_button() -> void:
	if _garage_button == null or garage == null:
		return
	_garage_button.text = "CONFIRM: NEW GARAGE (money, weapons and car reset)" if _garage_confirming \
		else "GARAGE:  $%d, %d races  -  NEW GARAGE" % [garage.money, garage.races_settled]


func _new_garage() -> void:
	if garage == null:
		return
	_sfx_play("ui/ui_select")
	if not _garage_confirming:
		_garage_confirming = true
	else:
		_garage_confirming = false
		garage.reset()
	_update_garage_button()


func _update_rounds_button() -> void:
	if _rounds_button != null:
		_rounds_button.text = "ROUNDS:  %d%s" % [championship_rounds, "  (FULL SEASON)" if championship_rounds == 6 else "  (SHORT)"]


func _cycle_track(dir: int = 1) -> void:
	_sfx_play("ui/ui_select")
	track_variant = posmod(track_variant - 1 + dir, TrackTheme.VARIANT_COUNT) + 1
	_update_track_button()
	var cfg := ConfigFile.new()
	cfg.load(settings.path)
	cfg.set_value("game", "track_variant", track_variant)
	cfg.save(settings.path)
	_refresh_preview()


## The player layouts in turn (not saved).
func _cycle_layout(dir: int = 1) -> void:
	_sfx_play("ui/ui_select")
	var ids := DevLayouts.ids(layout_id)
	layout_id = ids[posmod(ids.find(layout_id) + dir, ids.size())]
	_update_layout_button()
	_refresh_preview()


func _update_layout_button() -> void:
	_layout_button.text = "CIRCUIT:  %s" % DevLayouts.display_name(layout_id).to_upper()


func _update_track_button() -> void:
	_track_button.text = "ENVIRONMENT:  %s" % TrackTheme.load_variant(track_variant).display_name.to_upper()


func _update_laps_button() -> void:
	_laps_button.text = "LAPS:  %d" % laps


func _update_weapons_button() -> void:
	_weapons_button.text = "WEAPONS:  ON" if weapons_on else "WEAPONS:  NO GUNS"


func _load_weapons_pref() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(settings.path) == OK:
		weapons_on = bool(cfg.get_value("game", "weapons", true))
		var saved := int(cfg.get_value("game", "laps", 3))
		laps = saved if [3, 7, 20, 50].has(saved) else 3
		combat_style = clampi(int(cfg.get_value("game", "combat_style", 0)), 0, 1)
		championship_rounds = 3 if int(cfg.get_value("game", "championship_rounds", 6)) == 3 else 6
		night = bool(cfg.get_value("game", "night", false))
		control_choice = clampi(int(cfg.get_value("game", "control", 0)), 0, 1)
		player_car = clampi(int(cfg.get_value("game", "player_car", 0)), 0, 9)


func _start(choice: int, garage: bool = false) -> void:
	_sfx_play("ui/ui_select")
	start_requested.emit(choice, garage)


## MULTIPLAYER > START: split screen or two computers.
func _open_race() -> void:
	_sfx_play("ui/ui_select")
	_show_only(_race_menu)
	(_race_menu.get_child(1) as Button).grab_focus()


func _open_settings() -> void:
	_sfx_play("ui/ui_select")
	_show_only(_settings_panel)
	_settings_panel.focus_first()


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


## Back on the main menu (the career and credits screens close over it).
func focus_main() -> void:
	_show_main()


func _show_main() -> void:
	_show_only(_main_menu)
	(_main_menu.get_child(0) as Button).grab_focus()


## Bottom hint line (rebuilt from the bindings whenever a page opens).
var footer: Label


func _show_only(node: Control) -> void:
	if footer != null:
		footer.text = PlayerControls.fmt("{back}: back    Enter / Space / A: select")
	for n in [_main_menu, _mode_menu, _setup, _race_menu, _settings_panel, _controls_panel, _achievements_panel, _join_panel, lan_panel]:
		n.visible = n == node
	_logo.visible = node != _controls_panel and node != _achievements_panel and node != _setup
	_page_in(node)


## The page transition: the page fades in while sliding a few pixels into
## place; a button menu's buttons follow one after another.
var _page_tween: Tween
var _paged: Control
var _paged_home := Vector2.ZERO


func _page_in(node: Control) -> void:
	if _page_tween != null and _page_tween.is_valid():
		_page_tween.kill()
	if _paged != null and is_instance_valid(_paged):  # a transition cut short lands where it belongs
		_paged.position = _paged_home
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
	if node in [_main_menu, _mode_menu, _race_menu]:
		var k := 0
		for c in node.get_children():
			if c is Control and c.visible:
				c.modulate.a = 0.0
				tw.tween_property(c, "modulate:a", 1.0, 0.14).set_delay(0.03 * k)
				k += 1


func _menu(root: Control, items: Array, width: int = 380, button_height: int = 38, gap: int = 4) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", gap)
	box.custom_minimum_size = Vector2(width, 0)
	root.add_child(box)
	for item in items:
		var b := Button.new()
		b.text = item[0]
		b.custom_minimum_size = Vector2(width, maxi(button_height, 48))
		b.add_theme_font_size_override("font_size", 24)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(item[1])
		b.focus_entered.connect(func() -> void: _sfx_play("ui/ui_move"))
		b.mouse_entered.connect(b.grab_focus)
		box.add_child(UiJuice.button(b))
	box.reset_size()
	box.position = Vector2(64, 262)
	return box


func _sfx_play(logical: String) -> void:
	if _sfx == null:
		return
	_sfx.stream = resolver.get_audio(logical)
	_sfx.play()


func _build_backdrop() -> void:
	_backdrop = MenuDiorama.new()
	_backdrop.name = "Diorama"
	add_child(_backdrop)
