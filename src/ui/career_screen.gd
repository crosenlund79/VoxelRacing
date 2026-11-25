class_name CareerScreen
extends CanvasLayer
## CAREER (2026-11-22): the career hub. Three stage cards (Rookie Cup, Pro
## Series, HyperCars Grand Championship) with their state - won, in progress
## (round n of m), open or locked - and what each one asks; the player's car,
## money and condition from the career garage; CONTINUE / ENTER, GARAGE,
## STANDINGS, HALL OF FAME, NEW CAREER (asks twice and says what it resets)
## and BACK. The Hall of Fame shows only recorded results. Presentation only:
## Career holds the progress, the game root the flow.

signal stage_requested(stage: int)
signal garage_requested
signal standings_requested
signal new_career_confirmed
signal car_cycle_requested
signal back_requested

const CARD_W := 740.0

var career: Career
var garage: PlayerGarage
var cars: CarCollection
var achievements_unlocked := 0
var achievements_total := 0
## The car a new stage would be entered with (0 = the own car).
var chosen_car := 0
var _resolver: AssetResolver
var _root: Control
var _title: Label
var _sub: Label
var _cards: Array[Button] = []
var _car_icon: TextureRect
var _car_label: Label
var _car_button: Button
var _status: Label
var _main_button: Button
var _garage_button: Button
var _standings_button: Button
var _fame_button: Button
var _new_button: Button
var _back_button: Button
var _hint: Label
var _notice: Label
var _fame: PanelContainer
var _fame_bg: ColorRect
var _fame_text: Label
var _fame_cars: HBoxContainer
var _confirm_new := false


func setup(resolver: AssetResolver) -> void:
	_resolver = resolver
	layer = 20
	_root = Control.new()
	_root.theme = HyperTheme.build(resolver)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var bg := TextureRect.new()
	bg.texture = VrStyle.backdrop()
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.size = Vector2(1280, 720)
	_root.add_child(bg)
	_title = HyperTheme.label("CAREER", 46, HyperTheme.GOLD, 700)
	_title.position = Vector2(40, 24)
	_root.add_child(_title)
	_sub = HyperTheme.label("", 20, HyperTheme.CREAM, 600)
	_sub.position = Vector2(42, 84)
	_root.add_child(_sub)
	var stages := VBoxContainer.new()
	stages.position = Vector2(30, 122)
	stages.add_theme_constant_override("separation", 10)
	_root.add_child(stages)
	for i in Career.STAGES.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(CARD_W, 152)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 17)
		b.add_theme_color_override("font_disabled_color", Color(HyperTheme.CREAM, 0.72))  # (won / locked cards stay readable)
		var stage := i
		b.pressed.connect(func() -> void: stage_requested.emit(stage))
		b.mouse_entered.connect(b.grab_focus)
		stages.add_child(b)
		_cards.append(b)

	var side := PanelContainer.new()
	side.position = Vector2(790, 122)
	side.custom_minimum_size = Vector2(460, 476)
	_root.add_child(side)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	side.add_child(box)
	box.add_child(HyperTheme.label("YOUR CAR", 17, HyperTheme.GOLD, 700))
	_car_icon = TextureRect.new()
	_car_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_car_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_car_icon.custom_minimum_size = Vector2(420, 92)
	box.add_child(_car_icon)
	_car_label = HyperTheme.label("", 18, HyperTheme.CREAM, 600)
	_car_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_car_label)
	_status = HyperTheme.label("", 18, HyperTheme.CREAM, 600)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(420, 0)
	box.add_child(_status)
	_main_button = _button("CONTINUE", func() -> void: stage_requested.emit(_main_stage()))
	_car_button = _button("CAR", func() -> void: car_cycle_requested.emit())
	_garage_button = _button("GARAGE", func() -> void: garage_requested.emit())
	_standings_button = _button("STANDINGS", func() -> void: standings_requested.emit())
	_fame_button = _button("HALL OF FAME", _toggle_fame)
	_new_button = _button("NEW CAREER", _on_new)
	_back_button = _button("BACK", func() -> void: back_requested.emit())
	for b in [_main_button, _car_button, _garage_button, _standings_button, _fame_button, _new_button, _back_button]:
		box.add_child(b)
	_notice = HyperTheme.label("", 18, Color("ff8a6a"), 700)
	_notice.position = Vector2(34, 604)
	_notice.size = Vector2(1210, 30)
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root.add_child(_notice)
	_hint = HyperTheme.label("", 16, HyperTheme.CREAM, 600)
	_hint.add_theme_constant_override("outline_size", 6)
	_hint.add_theme_color_override("font_outline_color", HyperTheme.OUTLINE)
	_hint.position = Vector2(34, 680)
	_root.add_child(_hint)

	_fame_bg = ColorRect.new()  # (the hub behind the Hall of Fame is dimmed away)
	_fame_bg.color = Color(0.11, 0.09, 0.08, 0.92)
	_fame_bg.size = Vector2(1280, 720)
	_fame_bg.visible = false
	_root.add_child(_fame_bg)
	_fame = PanelContainer.new()
	_fame.position = Vector2(90, 70)
	_fame.custom_minimum_size = Vector2(1100, 580)
	_fame.visible = false
	_root.add_child(_fame)
	var fbox := VBoxContainer.new()
	fbox.add_theme_constant_override("separation", 8)
	_fame.add_child(fbox)
	fbox.add_child(HyperTheme.label("HALL OF FAME", 40, HyperTheme.GOLD, 700))
	_fame_text = HyperTheme.label("", 19, HyperTheme.CREAM, 600)
	_fame_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fame_text.custom_minimum_size = Vector2(1060, 0)
	fbox.add_child(_fame_text)
	_fame_cars = HBoxContainer.new()
	_fame_cars.add_theme_constant_override("separation", 8)
	fbox.add_child(_fame_cars)
	visible = false


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.theme = _root.theme
	HyperTheme.style_button(b, false, 420)  # (the main menu's buttons)
	b.custom_minimum_size.y = 36
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(action)
	b.mouse_entered.connect(b.grab_focus)
	return b


## Opens the hub (notice: a line in red, e.g. a forfeited attempt).
func open(notice: String = "") -> void:
	_confirm_new = false
	_fame.visible = false
	_fame_bg.visible = false
	_notice.text = notice
	refresh()
	visible = true
	_main_button.grab_focus()


func close() -> void:
	visible = false
	var f := _root.get_viewport().gui_get_focus_owner() if _root.is_inside_tree() else null
	if f != null and _root.is_ancestor_of(f):
		f.release_focus()


func showing_fame() -> bool:
	return visible and _fame.visible


## The stage the main button enters: the running championship, else the
## current stage (the first not yet won).
func _main_stage() -> int:
	if career.in_championship():
		return career.active_stage
	return career.current_stage()


func refresh() -> void:
	var running := career.in_championship()
	if career.completed:
		_title.text = "CAREER  -  HYPERCARS CHAMPION"
		_sub.text = "Career complete (%s). Race any championship again, collect the rest of the cars, or start a new career." % career.completed_on
	elif not career.started:
		_title.text = "CAREER"
		_sub.text = "An unknown racer against nine established rivals. Win three championships to become the HyperCars Champion."
	else:
		_title.text = "CAREER  -  STAGE %d OF 3" % (_main_stage() + 1)
		_sub.text = Career.stage_title(_main_stage()).to_upper() + (
			("  -  after round %d of %d" % [career.champ.round_index(), career.champ.schedule.round_count()]) if running else "")
	for i in _cards.size():
		_cards[i].text = card_text(i)
		_cards[i].disabled = not career.unlocked(i) or (running and career.active_stage != i)
	var car := career.player_car if running else chosen_car
	_car_icon.texture = CarArt.icon(_resolver, AssetCatalog.ai_car(car) if car > 0 else AssetCatalog.CAR_PLAYER)
	_car_label.text = ("YOUR OWN CAR" if car <= 0 else "%s'S CAR (won)" % RivalRoster.short_name(car).to_upper()) + (
		"  -  FOR KEEPS" if car > 0 else "")
	_car_button.visible = not running and cars != null and cars.owned.size() > 0
	_car_button.text = "CHANGE CAR"
	_status.text = "Money $%d     Car %d%%     Armour %s\nWeapons: %s" % [garage.money, roundi(garage.condition), garage.armour_name(),
		_loadout_text()]
	var stage := _main_stage()
	if running:
		_main_button.text = ("START THE GRAND FINAL" if career.champ.next_round().get("final", false)
			else "CONTINUE: ROUND %d OF %d" % [career.champ.round_index() + 1, career.champ.schedule.round_count()])
	elif career.completed:
		_main_button.text = "RACE THE GRAND CHAMPIONSHIP AGAIN"
	else:
		_main_button.text = ("START: %s" if career.attempts[stage] == 0 else "TRY AGAIN: %s") % Career.stage_title(stage).to_upper()
	_standings_button.visible = running and career.champ.round_index() > 0
	_new_button.text = "NEW CAREER"
	_new_button.visible = career.started
	_fame_button.visible = true
	_hint.text = PlayerControls.fmt("Arrows: move    {confirm}: choose    {back}: back    Stage cards: enter a stage you have unlocked")


func _loadout_text() -> String:
	var parts := PackedStringArray()
	for slot in 2:
		var w := garage.equipped[slot]
		if w != WeaponRules.Weapon.NONE:
			parts.append("%s x%d" % [WeaponRules.weapon_name(w), garage.count(w)])
	return ", ".join(parts) if not parts.is_empty() else "none equipped"


## One stage card: name and state, what it is, its rounds and reward.
func card_text(i: int) -> String:
	var s := Career.schedule(i)
	var state := ""
	if career.in_championship() and career.active_stage == i:
		state = "IN PROGRESS  -  round %d of %d" % [career.champ.round_index() + 1, s.round_count()]
	elif career.stage_won[i]:
		state = "WON" + ("  x%d" % career.titles[i] if career.titles[i] > 1 else "")
	elif career.unlocked(i):
		state = "OPEN" + ("  -  attempt %d" % (career.attempts[i] + 1) if career.attempts[i] > 0 else "")
	else:
		state = "LOCKED  -  win the %s to enter" % Career.stage_title(i - 1)
	var night := s.nights.count(true)
	var long_races := 0
	for l in s.laps:
		long_races += int(l > 3)
	var style := "Classic" if s.career_style == WeaponRules.Style.CLASSIC else "Tactical"
	return "%d.  %s  -  %s      %s\n%s\n%d rounds%s%s  -  %s combat  -  title bonus $%d + a rival's car" % [i + 1, s.title.to_upper(),
		s.career_tagline.to_upper(), state,
		s.blurb, s.round_count(), ("  -  %d at night" % night) if night > 0 else "",
		("  -  %d of 7 laps" % long_races) if long_races > 0 else "", style, s.career_bonus]


## Opens the Hall of Fame (after the ending).
func show_fame() -> void:
	if not _fame.visible:
		_toggle_fame()


func _toggle_fame() -> void:
	_fame.visible = not _fame.visible
	_fame_bg.visible = _fame.visible
	if _fame.visible:
		_fame_text.text = fame_text()
		for c in _fame_cars.get_children():
			c.queue_free()
		if cars != null:
			for id in cars.owned:
				var t := TextureRect.new()
				t.texture = CarArt.icon(_resolver, AssetCatalog.ai_car(id))
				t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				t.custom_minimum_size = Vector2(110, 62)
				t.tooltip_text = RivalRoster.full_name(id)
				_fame_cars.add_child(t)
	_fame_button.grab_focus()


## The Hall of Fame: only what the game has recorded.
func fame_text() -> String:
	var lines := PackedStringArray()
	if career.completed:
		lines.append("HYPERCARS CHAMPION  -  career completed on %s." % career.completed_on)
		if career.final_standings.size() >= 3:
			lines.append("Final Grand Championship podium: 1. %s   2. %s   3. %s" % [_name(career.final_standings[0]),
				_name(career.final_standings[1]), _name(career.final_standings[2])])
	elif career.started:
		lines.append("Career in progress: stage %d of 3, %s." % [career.current_stage() + 1, Career.stage_title(career.current_stage())])
	else:
		lines.append("No career started yet.")
	if career.careers_completed > 0:
		lines.append("Careers completed: %d (first on %s)." % [career.careers_completed, career.first_completed_on])
	var titles := PackedStringArray()
	for i in Career.STAGES.size():
		titles.append("%s %d" % [Career.stage_title(i), career.titles[i]])
	lines.append("Championships won this career: " + ",  ".join(titles))
	lines.append("Career races %d   -   wins %d   -   podiums %d   -   DNFs %d   -   money won $%d" % [career.races,
		career.race_wins, career.podiums, career.dnfs, career.money_won])
	var rival := career.top_rival()
	if rival > 0:
		lines.append("Most career race wins by a rival: %s, %d." % [RivalRoster.full_name(rival), int(career.rival_wins[rival])])
	var champs := PackedStringArray()
	for id in career.rival_titles:
		champs.append("%s %d" % [RivalRoster.short_name(id), int(career.rival_titles[id])])
	if not champs.is_empty():
		lines.append("Rivals who beat you to a title: " + ", ".join(champs))
	if achievements_total > 0:
		lines.append("Achievements: %d of %d unlocked." % [achievements_unlocked, achievements_total])
	lines.append("Rival cars owned: %d of 9." % (cars.owned.size() if cars != null else 0))
	return "\n".join(lines)


func _name(id: int) -> String:
	return "YOU" if id == RaceSession.PLAYER_ID else RivalRoster.full_name(id)


func _on_new() -> void:
	if not _confirm_new:
		_confirm_new = true
		_new_button.text = "CONFIRM: START OVER"
		_notice.text = "NEW CAREER resets the career's progress, records and garage (money, weapons, armour) to the start. " \
			+ "Kept: achievements, won rival cars, the Garage Race career and the Hall of Fame's career titles."
		_new_button.grab_focus()
		return
	_confirm_new = false
	new_career_confirmed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(PlayerControls.BACK):
		get_viewport().set_input_as_handled()
		if _fame.visible:
			_toggle_fame()
		elif _confirm_new:
			_confirm_new = false
			_notice.text = ""
			_new_button.text = "NEW CAREER"
		else:
			back_requested.emit()
