extends GutTest
## The career in the real game (2026-11-22), end to end: a fresh career, a real
## opening race with prize money, the garage between rounds, save & exit and a
## resume in a new game session with the same standings / money / car / grid,
## a lost stage retried, all three stages won, the ending and the Hall of Fame,
## completion surviving a restart, racing on afterwards, leaving or closing
## the game mid-race (forfeit, Racing for Keeps), NEW CAREER touching only
## career data, a DNF with a broke garage (no dead end), and the standalone
## garage / old saves untouched.
## Saves go to scratch files (the player's own are never touched).

const GAME_SCENE := preload("res://src/main/game.tscn")
const P := RaceSession.PLAYER_ID
const DIR := "user://test_run/career_flow/"

var game: Node
var _garage_default := ""


func before_all() -> void:
	_garage_default = PlayerGarage.default_path


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	for f in ["career.cfg", "career_garage.cfg", "cars.cfg", "ach.cfg", "memory.cfg", "garage.cfg"]:
		SafeSave.remove(DIR + f)
	PlayerGarage.default_path = DIR + "garage.cfg"  # the standalone Garage Race career
	cards_seen.clear()
	await _launch()


func after_each() -> void:
	for a in [PlayerControls.FIRE, PlayerControls.CONFIRM, PlayerControls.HISTORY_VIEW]:
		Input.action_release(a)
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0
	if is_instance_valid(game):
		game.queue_free()
		await wait_physics_frames(2)


func after_all() -> void:
	PlayerGarage.default_path = _garage_default  # (the suite's own redirection)


## A game session on the scratch saves (a "restart" = launching again).
func _launch() -> void:
	if is_instance_valid(game):
		game.queue_free()
		await wait_physics_frames(2)
	game = GAME_SCENE.instantiate()
	game.career_path = DIR + "career.cfg"
	game.career_garage_path = DIR + "career_garage.cfg"
	game.cars_path = DIR + "cars.cfg"
	game.achievements_path = DIR + "ach.cfg"
	game.memory_path = DIR + "memory.cfg"
	game.greetings_enabled = false
	add_child(game)
	await wait_physics_frames(3)


func _tap(action: String) -> void:
	Input.action_press(action)
	await wait_physics_frames(2)
	Input.action_release(action)
	await wait_physics_frames(1)


## Milestone cards (stage intros, first victory, titles...): moved on at once,
## and remembered for the tests that check them.
var cards_seen: Array[String] = []


func _skip_cards() -> void:
	if is_instance_valid(game) and game.milestones != null and game.milestones.showing():
		cards_seen.append(game.milestones.current_title())
		game.milestones._age = 1.0
		game.milestones.advance()


func _wait_race() -> void:
	for i in 300:
		_skip_cards()
		if game.race != null and not game._starting:
			return
		await wait_physics_frames(1)


func _wait_standings() -> void:
	for i in 300:
		_skip_cards()
		if game.race == null and game.champ_screen.visible:
			return
		await wait_physics_frames(1)


func _order(first: int) -> Array:
	var o := [first]
	for id in range(0, 10):
		if id != first:
			o.append(id)
	return o


## The garage is open before the race: race (closes the garage, GO).
func _start_from_garage() -> Node2D:
	await _wait_race()
	var race: Node2D = game.race
	assert_true(race.garage_open, "the career garage opens before every career race")
	assert_true(game.garage_screen.visible)
	game._close_garage(true)
	await wait_physics_frames(3)
	assert_eq(race.session.state, RaceSession.State.RACING)
	return race


## A real round: the player drives every lap first (wins), the rivals are
## fast-forwarded to the flag, Enter shows the standings.
func _race_and_win() -> void:
	var race := await _start_from_garage()
	var cps: int = race.track.checkpoint_count()
	for lap in race.session.lap_count():
		for i in range(1, cps):
			race.session.checkpoint_reached(i, P)
		race.session.checkpoint_reached(0, P)
	await wait_physics_frames(3)
	if not race.session.all_finished():
		await _tap(PlayerControls.HISTORY_VIEW)
		await wait_until(func() -> bool: return race.session.all_finished(), 900.0)
		await wait_physics_frames(3)
	await _tap(PlayerControls.CONFIRM)
	await _wait_standings()


## A round decided at once (the result handed to the career as the race scene
## would at its conclusion), then Enter on the results.
func _decide(first: int, player_dnf := false) -> void:
	var race := await _start_from_garage()
	var order := _order(first)
	var dnf: Array = []
	if player_dnf:
		order.erase(P)
		order.append(P)
		race.session.racers[P].dnf = true
		dnf = [P]
	game._on_career_concluded(order)
	race.championship_round_done.emit(order, dnf)
	await _wait_standings()


func _continue_from_standings() -> void:
	assert_true(game.champ_screen.visible)
	game.champ_screen._on_continue()
	await wait_physics_frames(10)


func _play_stage(winner: int) -> void:
	var rounds: int = game.career.champ.schedule.round_count()
	for i in rounds:
		await _decide(winner)
		if i < rounds - 1:
			await _continue_from_standings()


func test_fresh_career_real_race_prize_garage_and_next_round() -> void:
	var c: Career = game.career
	assert_false(c.started)
	assert_eq((game.title._main_menu.get_child(0) as Button).text, "CAREER", "CAREER heads the main menu")
	game.open_career()
	assert_true(game.career_screen.visible)
	assert_eq(game.career_screen._main_button.text, "START: ROOKIE CUP")
	assert_true(game.career_screen._cards[1].disabled, "the Pro Series is locked")
	var standalone_money: int = game.garage.money
	var money: int = game.career_garage.money
	game.career_screen._main_button.emit_signal("pressed")
	await _race_and_win()
	assert_true(game.champ_screen.visible and game.champ_screen.career)
	assert_eq(c.champ.round_index(), 1)
	assert_eq(c.race_wins, 1)
	assert_eq(game.career_garage.money, money + 550 - 0, "first place pays the 3-lap prize")
	assert_eq(c.money_won, 550)
	assert_eq(game.garage.money, standalone_money, "the Garage Race career is untouched")
	assert_false(FileAccess.file_exists(DIR + "garage.cfg"), "nothing written to the standalone garage")
	assert_eq(game.champ_screen._abandon.text, "SAVE & EXIT")
	assert_eq(game.champ_screen._continue.text, "TO THE GARAGE")
	# the garage between rounds: buy a homing missile, then race round 2 with it
	await _continue_from_standings()
	await _wait_race()
	assert_true(game.garage_screen.visible)
	assert_eq(game.garage_screen.garage, game.career_garage, "the career's garage")
	assert_true(game.career_garage.buy(WeaponRules.Weapon.HOMING_MISSILE))
	assert_true(game.career_garage.equip(PlayerGarage.FRONT, WeaponRules.Weapon.HOMING_MISSILE))
	var race: Node2D = game.race
	game._close_garage(true)
	await wait_physics_frames(3)
	assert_eq(race.combat.weapon_of(P, CombatWorld.FRONT), WeaponRules.Weapon.HOMING_MISSILE, "races with what was bought")
	assert_true(race.weapons_enabled, "career races are armed")
	assert_eq(race.combat_style, WeaponRules.Style.CLASSIC, "the Rookie Cup's combat style")
	assert_true(c.in_race)
	assert_string_contains(race.championship_label, "ROOKIE CUP  -  ROUND 2 OF 3")


func test_save_and_exit_then_resume_in_a_new_session() -> void:
	game.open_career()
	game._enter_career_stage(0)
	await _decide(3)
	var points: Dictionary = game.career.champ.points.duplicate()
	var grid: Array = game.career.champ.next_grid()
	game.career_garage.buy(WeaponRules.Weapon.MINE, 2)
	var money: int = game.career_garage.money
	game.champ_screen._on_abandon()  # SAVE & EXIT
	await wait_physics_frames(5)
	assert_true(game.career_screen.visible, "back on the career screen")
	assert_eq(game.career_screen._main_button.text, "CONTINUE: ROUND 2 OF 3")
	await _launch()  # quit and start the game again
	assert_eq(game.title._notice.visible, false, "no forfeit notice for a normal exit between rounds")
	var c: Career = game.career
	assert_true(c.in_championship())
	assert_eq(c.champ.points, points, "same standings")
	assert_eq(game.career_garage.money, money, "same money")
	game.open_career()
	game.career_screen._main_button.emit_signal("pressed")
	var race := await _start_from_garage()
	assert_eq(race.championship_round, 1, "round 2")
	assert_eq(race.championship_grid, grid, "the reversed grid of round 1")
	assert_eq(race.layout_override.display_name, DevLayouts.display_name(c.champ.schedule.get_round(1).layout))


func test_the_whole_career_with_a_lost_stage_the_ending_and_after() -> void:
	game.open_career()
	game._enter_career_stage(0)
	var start_money: int = game.career_garage.money
	await _play_stage(P)
	assert_string_contains(game.champ_screen._reward.text, "ROOKIE CUP WON!")
	assert_string_contains(game.champ_screen._reward.text, "NEXT: THE PRO SERIES IS OPEN.")
	assert_eq(game.career_garage.money, start_money + 500, "the title bonus, once (decided rounds pay no prize)")
	assert_eq(game.cars.owned.size(), 1, "a rival's car as the championship reward")
	var last: int = game.career.champ.standings()[-1]
	assert_eq(game.cars.owned, [last] as Array[int], "the last-placed rival's car (none owned before)")
	assert_string_contains(game.champ_screen._reward.text, "YOU CLAIMED %s'S CAR!" % RivalRoster.short_name(last).to_upper())
	game.champ_screen._on_continue()  # CONTINUE after the final standings
	await wait_physics_frames(5)
	assert_true(game.career_screen.visible)
	assert_false(game.career_screen._cards[1].disabled, "the Pro Series is open")
	# the Pro Series: Rocco wins it
	game._enter_career_stage(1)
	await _play_stage(2)
	assert_string_contains(game.champ_screen._reward.text, "WINS THE PRO SERIES")
	assert_eq(game.career_garage.money, start_money + 500, "no bonus for a lost stage")
	game.champ_screen._on_continue()
	await wait_physics_frames(5)
	assert_true(game.career_screen._cards[2].disabled, "the Grand Championship is still locked")
	assert_eq(game.career_screen._main_button.text, "TRY AGAIN: PRO SERIES")
	# again, and won
	game.career_screen._main_button.emit_signal("pressed")
	await _play_stage(P)
	game.champ_screen._on_continue()
	await wait_physics_frames(5)
	# the Grand Championship and its final
	game._enter_career_stage(2)
	for i in 6:
		await _decide(P)
		if i == 4:
			assert_string_contains(game.champ_screen._continue.text, "GARAGE")
			assert_string_contains(game.champ_screen._next_title.text, "GRAND FINAL")
		if i < 5:
			await _continue_from_standings()
	assert_true(game.career.completed)
	assert_string_contains(game.champ_screen._reward.text, "YOU ARE THE HYPERCARS CHAMPION!")
	game.champ_screen._on_continue()
	await wait_physics_frames(5)
	assert_true(game.victory.showing(), "the ending")
	# the milestones along the way (2026-11-23), from what really happened
	for t in ["YOUR CAREER BEGINS", "FIRST CAREER VICTORY", "ROOKIE CUP CHAMPION", "STAGE 2 OF 3",
			"ROCCO WINS THE PRO SERIES", "PRO SERIES CHAMPION", "THE FINAL STAGE", "THE GRAND FINAL"]:
		assert_has(cards_seen, t, "milestone card: %s" % t)
	assert_eq(cards_seen.count("FIRST CAREER VICTORY"), 1, "a first victory happens once")
	assert_false(cards_seen.has("HYPERCARS GRAND CHAMPIONSHIP CHAMPION"), "the ending has its own ceremony")
	assert_eq(game.victory._podium._ids[0], P, "the player on the top step")
	await wait_seconds(VictoryScreen.INPUT_DELAY + 0.1)
	var ev := InputEventAction.new()  # (a real input event: the screens read events)
	ev.action = PlayerControls.CONFIRM
	ev.pressed = true
	Input.parse_input_event(ev)
	await wait_physics_frames(3)
	assert_false(game.victory.showing())
	assert_true(game.career_screen.showing_fame(), "then the Hall of Fame")
	assert_string_contains(game.career_screen._fame_text.text, "HYPERCARS CHAMPION")
	assert_string_contains(game.career_screen._fame_text.text, "Rivals who beat you to a title: Rocco 1")
	# a restart keeps the completion
	await _launch()
	assert_true(game.career.completed, "completion survives a restart")
	game.open_career()
	assert_eq(game.career_screen._main_button.text, "RACE THE GRAND CHAMPIONSHIP AGAIN")
	assert_string_contains(game.career_screen._title.text, "HYPERCARS CHAMPION")
	game.career_screen.close()
	# and the game goes on: a quick race
	game.start_race(0)
	await _wait_race()
	assert_not_null(game.race)
	assert_false(game.race.championship_round >= 0)
	assert_null(game.race.garage, "quick races never touch a garage")


func test_leaving_mid_race_forfeits_the_attempt_and_the_car_at_stake() -> void:
	game.cars.owned.append(4)
	game.cars.save()
	game.title.player_car = 4
	game.open_career()
	game._enter_career_stage(0)
	assert_eq(game.cars.career_stake, 4, "racing Hank's car for keeps")
	await _decide(P)
	await _continue_from_standings()
	await _start_from_garage()
	assert_string_contains(game.race.championship_label, "FOR KEEPS: HANK'S CAR")
	assert_string_contains(game.race.forfeit_warning, "forfeits this Rookie Cup attempt")
	game.back_to_title()  # LEAVE RACE
	await wait_physics_frames(30)
	assert_true(game.career_screen.visible)
	assert_string_contains(game.career_screen._notice.text, "forfeited")
	assert_false(game.career.in_championship())
	assert_false(game.cars.owns(4), "Hank took his car back")
	assert_eq(game.career.races, 1, "the finished round stays on record")
	game._enter_career_stage(0)
	await _wait_race()
	assert_eq(game.career.champ.round_index(), 0, "a new attempt from round 1")


func test_leaving_after_finishing_records_the_round() -> void:
	game.open_career()
	game._enter_career_stage(0)
	var race := await _start_from_garage()
	var cps: int = race.track.checkpoint_count()
	for lap in race.session.lap_count():
		for i in range(1, cps):
			race.session.checkpoint_reached(i, P)
		race.session.checkpoint_reached(0, P)
	await wait_physics_frames(3)
	assert_eq(race.session.state, RaceSession.State.FINISHED)
	game.back_to_title()  # leave while the rivals are still racing
	await _wait_standings()  # (via the FIRST CAREER VICTORY card)
	assert_has(cards_seen, "FIRST CAREER VICTORY")
	assert_true(game.career.in_championship(), "not forfeited: the player had finished")
	assert_eq(game.career.champ.round_index(), 1, "the round counts (running order for the rest)")
	assert_eq(game.career.champ.position_in(0, P), 1)
	assert_true(game.champ_screen.visible, "its standings")


func test_closing_the_game_mid_race_forfeits_at_the_next_start() -> void:
	game.cars.owned.append(6)
	game.cars.save()
	game.title.player_car = 6
	game._enter_career_stage(0)
	await _start_from_garage()
	assert_true(game.career.in_race)
	# the game is closed (or crashes) during the race
	game.free()
	await wait_physics_frames(2)
	await _launch()
	assert_eq(game.career.forfeited_on_load, 0)
	assert_false(game.career.in_championship(), "no quit-and-retry")
	assert_false(game.cars.owns(6), "the car at stake went back")
	assert_true(game.title._notice.visible)
	assert_string_contains(game.title._notice.text, "THE GAME CLOSED DURING A RACE")


func test_a_dnf_and_an_empty_wallet_never_end_the_career() -> void:
	game._enter_career_stage(0)
	game.career_garage.money = 0
	game.career_garage.condition = 5.0
	for w in game.career_garage.stock:
		game.career_garage.stock[w] = 0
	await _decide(1, true)
	assert_eq(game.career.champ.points[P], 0, "a DNF scores nothing")
	assert_eq(game.career.dnfs, 1)
	await _continue_from_standings()
	var race := await _start_from_garage()
	assert_eq(race.session.state, RaceSession.State.RACING, "broke and battered, still racing")
	assert_gte(race.damage.fraction(P), 0.49, "the free emergency patch-up")


func test_new_career_resets_only_the_career() -> void:
	game._enter_career_stage(0)
	await _play_stage(P)
	game.champ_screen._on_continue()
	await wait_physics_frames(5)
	var won: Array = game.cars.owned.duplicate()
	game.garage.money = 777
	game.garage.save()
	game.career_garage.add_money(1000)
	game.career_screen._on_new()
	assert_string_contains(game.career_screen._notice.text, "Kept: achievements, won rival cars")
	assert_false(game.career.stage_won[0] == false, "nothing reset before the confirmation")
	game.career_screen._on_new()
	await wait_physics_frames(2)
	assert_false(game.career.started)
	assert_false(game.career.stage_won[0])
	assert_eq(game.career_garage.money, PlayerGarage.new(game.career_garage.rules).money, "a fresh career garage")
	assert_eq(game.cars.owned, won, "won cars kept")
	assert_eq(PlayerGarage.load_or_new(game.garage.rules, DIR + "garage.cfg").money, 777, "the Garage Race career kept")


func test_old_saves_without_career_data_still_load() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("cars", "owned", [3, 5])
	cfg.set_value("cars", "championships_run", 4)
	cfg.set_value("cars", "stake", 0)
	cfg.save(DIR + "cars.cfg")
	await _launch()
	assert_eq(game.cars.owned, [3, 5] as Array[int])
	assert_eq(game.cars.career_stake, 0)
	assert_false(game.career.started, "no career yet: a fresh one")
	game.open_career()
	assert_eq(game.career_screen._main_button.text, "START: ROOKIE CUP")
	assert_true(game.career_screen._car_button.visible, "won cars can be entered")


## Back (Escape / pad B) through the career's screens (2026-11-23 regression):
## after a round the race scene is gone, and the title scene behind the career
## screens was left hidden - closing the hub then showed an empty world with no
## camera. Every Back must land on a real, visible screen with state intact.
func _back(pad := false) -> void:
	var down: InputEvent
	var up: InputEvent
	if pad:
		down = InputEventJoypadButton.new()
		down.button_index = JOY_BUTTON_B
		down.pressed = true
		up = InputEventJoypadButton.new()
		up.button_index = JOY_BUTTON_B
	else:
		down = InputEventKey.new()
		down.keycode = KEY_ESCAPE
		down.physical_keycode = KEY_ESCAPE
		down.pressed = true
		up = InputEventKey.new()
		up.keycode = KEY_ESCAPE
		up.physical_keycode = KEY_ESCAPE
	Input.parse_input_event(down)
	await wait_physics_frames(2)
	Input.parse_input_event(up)
	await wait_physics_frames(6)


## Which screen is up, as a player would see it (and the world has a camera).
func _screen() -> String:
	var t: Node = game.title
	var cam := game.get_viewport().get_camera_2d()
	assert_not_null(cam, "a camera is current (never an empty world)")
	if game.garage_screen.visible:
		return "garage"
	if game.career_screen.visible:
		return "career"
	if game.champ_screen.visible:
		return "standings"
	if game.race != null:
		return "race"
	if t._ui.visible and t._backdrop.visible and t._main_menu.visible:
		return "title"
	return "nothing"


func test_back_through_the_career_screens_keyboard_and_pad() -> void:
	for pad in [false, true]:
		await _launch()
		game.open_career()
		game._enter_career_stage(0)
		# before a career race: Back in the garage goes to the grid panel, Back there to the hub
		await _wait_race()
		assert_eq(_screen(), "garage")
		await _back(pad)
		assert_eq(_screen(), "race", "pre-race garage -> grid panel")
		assert_true(game.race.session.state == RaceSession.State.MODE_SELECT)
		await _back(pad)
		await wait_physics_frames(40)
		assert_eq(_screen(), "career", "grid panel -> the career hub (forfeit-free: not raced yet)")
		# a round raced, then the standings, SAVE & EXIT, the hub's garage
		game.career_screen._main_button.emit_signal("pressed")
		await _decide(2)
		assert_eq(_screen(), "standings")
		game.champ_screen._on_abandon()
		await wait_physics_frames(40)
		assert_eq(_screen(), "career", "SAVE & EXIT -> the hub")
		var round_index: int = game.career.champ.round_index()
		game.career_screen.garage_requested.emit()
		await wait_physics_frames(5)
		assert_eq(_screen(), "garage")
		# Back in the middle of shopping: the purchase stands, nothing else changes
		var money: int = game.career_garage.money
		assert_true(game.career_garage.buy(WeaponRules.Weapon.MINE))
		await _back(pad)
		assert_eq(_screen(), "career", "the hub's garage -> the hub")
		assert_eq(game.career_garage.money, money - game.career_garage.rules.price(WeaponRules.Weapon.MINE), "the purchase stands")
		assert_eq(game.career.champ.round_index(), round_index, "the championship is untouched")
		assert_true(game.career.in_championship())
		# and Back on the hub: the title menu, really visible
		await _back(pad)
		assert_eq(_screen(), "title", "the hub -> the title menu (pad=%s)" % pad)
		# and in again: the running championship continues
		game.open_career()
		assert_eq(_screen(), "career")
		assert_eq(game.career_screen._main_button.text, "CONTINUE: ROUND %d OF 3" % (round_index + 1))
