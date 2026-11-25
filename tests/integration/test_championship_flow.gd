extends GutTest
## The championship in the full game: three rounds on the schedule's circuits,
## biomes and times, reversed grids between rounds, standings after each round,
## the reward (a real ownership change: the rival then races the junker, the
## player can pick the car), abandoning, and the rival defeat popup.

const GAME_SCENE := preload("res://src/main/game.tscn")
const CARS := "user://test_champ_cars.cfg"

var game: Node


func before_each() -> void:
	CarCollection.new(CARS).clear()
	game = GAME_SCENE.instantiate()
	game.achievements_path = "user://test_champ_ach.cfg"
	game.cars_path = CARS
	add_child_autofree(game)
	await wait_physics_frames(3)
	game.title.championship_rounds = 3  # the short version keeps these flows quick


func after_each() -> void:
	Input.action_release(PlayerControls.FIRE)
	Input.action_release(PlayerControls.CONFIRM)
	Input.action_release(PlayerControls.HISTORY_VIEW)
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CARS))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_champ_ach.cfg"))


func _tap(action: String) -> void:
	Input.action_press(action)
	await wait_physics_frames(2)
	Input.action_release(action)
	await wait_physics_frames(1)


func _wait_race() -> void:
	for i in 300:
		if game.race != null and not game._starting:
			return
		await wait_physics_frames(1)


## Drives the player's laps (checkpoints in order) so they win the round.
func _win_round() -> void:
	var race: Node2D = game.race
	race.start_race()
	await wait_physics_frames(5)
	var cps: int = race.track.checkpoint_count()
	for lap in race.session.lap_count():
		for i in range(1, cps):
			race.session.checkpoint_reached(i, 0)
		race.session.checkpoint_reached(0, 0)
	await wait_physics_frames(3)
	assert_eq(race.session.state, RaceSession.State.FINISHED)
	if not race.session.all_finished():  # the rivals race on: skip to the results (fast-forward)
		await _tap(PlayerControls.HISTORY_VIEW)
		await wait_until(func() -> bool: return race.session.all_finished(), 600.0)
		await wait_physics_frames(3)
	await _tap(PlayerControls.CONFIRM)
	for i in 120:
		if game.race == null and game.champ_screen.visible:
			break
		await wait_physics_frames(1)


func test_three_rounds_follow_the_schedule_and_reward_the_champion() -> void:
	var schedule: ChampionshipSchedule = game.title.championship.with_length(3)
	game.start_championship(0)
	for k in 3:
		await _wait_race()
		var race: Node2D = game.race
		var r := schedule.get_round(k)
		assert_eq(DevLayouts.id_of(race.layout_override), r.layout, "round %d circuit" % (k + 1))
		assert_eq(race.track_variant, r.variant, "round %d biome" % (k + 1))
		assert_eq(race.night, r.night, "round %d time of day" % (k + 1))
		assert_eq(race.session.lap_count(), r.laps)
		assert_eq(race.championship_round, k)
		if k == 0:  # round 1: the rivals shuffled (race variety), the player last
			var sorted: Array[int] = race.grid_order.duplicate()
			sorted.sort()
			assert_eq(sorted, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9] as Array[int], "every car once")
		else:
			assert_eq(race.grid_order, game.champ.next_grid(), "the championship's reversed grid")
		if k == 0:
			assert_eq(race.grid_order[-1], 0, "round 1: the player starts last")
		else:
			assert_eq(race.grid_order[-1], 0, "the previous winner (the player) starts last")
		await _win_round()
		assert_true(game.champ_screen.visible, "standings after round %d" % (k + 1))
		assert_eq(game.champ.results.size(), k + 1)
		if k < 2:
			game._next_round()
	assert_true(game.champ.finished())
	assert_eq(game.champ.champion(), 0)
	assert_eq(game.champ.points[0], 75)
	var won: int = game.last_reward
	assert_between(won, 1, 9, "a rival car unlocked")
	assert_eq(won, game.champ.standings()[-1], "the car of the last-placed rival in the final standings")
	assert_string_contains(game.champ_screen._reward.text,
		"YOU CLAIMED %s'S CAR" % RivalRoster.short_name(won).to_upper())
	assert_true(CarCollection.new(CARS).owns(won), "ownership saved")
	var mem: Dictionary = game.memory.events[-1]
	assert_eq([mem.kind, mem.rival], [RivalMemory.WON_MY_CAR, won], "the rival remembers losing its car")
	assert_ne(game.title.championship.resource_path, schedule.resource_path, "the next championship differs")
	# the next race: the rival drives the junker; the player can take the car
	game.abandon_championship()
	await wait_physics_frames(60)
	game.title.player_car = won
	game.start_race(0)
	await _wait_race()
	var race: Node2D = game.race
	assert_eq(race.player_car, won)
	assert_eq(race._car_looks[won].body_logical, AssetCatalog.body_of(AssetCatalog.CAR_JUNKER), "the displaced rival races the junker")
	assert_eq(race._car_looks[0].body_logical, AssetCatalog.body_of(AssetCatalog.ai_car(won)), "the player drives the won car")
	assert_eq(race.drivers[won].params.resource_path, RivalRoster.params_path(won), "same personality")
	assert_eq(race.cars[won].model.params, race.cars[0].model.params, "identical performance")
	game.title.player_car = 0
	race.leave_race()
	await wait_physics_frames(40)
	game.start_race(0)
	await _wait_race()
	assert_eq(game.race._car_looks[won].body_logical, AssetCatalog.body_of(AssetCatalog.CAR_JUNKER),
		"still displaced when the player picks another car")


func test_leaving_a_round_abandons_the_championship() -> void:
	game.start_championship(1)
	await _wait_race()
	assert_not_null(game.champ)
	assert_eq(game.race.race_menu._leave.text, "ABANDON CHAMPIONSHIP")
	game.race.leave_race()
	await wait_physics_frames(60)
	assert_null(game.champ)
	assert_null(game.race)
	assert_eq(CarCollection.new(CARS).owned.size(), 0, "nothing won")


## The full season: six rounds, the last one billed as the grand final.
func test_six_round_season_ends_with_the_grand_final() -> void:
	game.title.championship_rounds = 6
	var schedule: ChampionshipSchedule = game.title.championship
	game.start_championship(0)
	await _wait_race()
	assert_eq(game.champ.schedule.round_count(), 6)
	assert_string_contains(game.race.championship_label, "ROUND 1 OF 6")
	for k in 4:
		game.champ.record([1, 2, 3, 4, 5, 6, 7, 8, 9, 0], [])
	game.race.championship_round_done.emit([1, 2, 3, 4, 5, 6, 7, 8, 9, 0], [])
	await wait_physics_frames(30)
	assert_true(game.champ_screen.visible)
	assert_string_contains(game.champ_screen._next_title.text, "GRAND FINAL")
	assert_eq(game.champ_screen._continue.text, "START THE FINAL")
	game._next_round()
	await _wait_race()
	var r := schedule.get_round(5)
	assert_eq(DevLayouts.id_of(game.race.layout_override), r.layout, "the final's circuit")
	assert_eq(game.race.track_variant, r.variant)
	assert_eq(game.race.night, r.night)
	assert_string_contains(game.race.championship_label, "GRAND FINAL")


func test_rounds_option_is_saved() -> void:
	game.title._open_setup("championship")
	assert_true(game.title._rounds_button.visible)
	var before: int = game.title.championship_rounds
	game.title._cycle_rounds()
	assert_ne(game.title.championship_rounds, before)
	assert_string_contains(game.title._setup_note.text, "FINAL %d:" % game.title.championship_rounds)
	var cfg := ConfigFile.new()
	cfg.load(game.title.settings.path)
	assert_eq(int(cfg.get_value("game", "championship_rounds", 0)), game.title.championship_rounds)
	game.title._cycle_rounds()


func test_a_lost_championship_gives_nothing() -> void:
	game.start_championship(0)
	await _wait_race()
	game.champ.record([1, 2, 3, 4, 5, 6, 7, 8, 9, 0], [])
	game.champ.record([1, 2, 3, 4, 5, 6, 7, 8, 9, 0], [])
	game.race.championship_round_done.emit([1, 2, 3, 4, 5, 6, 7, 8, 9, 0], [0])
	await wait_physics_frames(60)
	assert_true(game.champ.finished())
	assert_eq(game.champ.champion(), 1)
	assert_eq(game.last_reward, -1)
	assert_eq(CarCollection.new(CARS).owned.size(), 0)


func test_reward_texts() -> void:
	assert_string_contains(game.reward_text(6, false), "YOU CLAIMED DANTE'S CAR!")
	assert_string_contains(game.reward_text(6, false), 'Dante "Showboat"')
	assert_string_contains(game.reward_text(9, true), "ALL NINE RIVAL CARS COLLECTED")
	assert_string_contains(game.reward_text(-1, true), "collection is complete")


func test_defeat_popup_credits_the_attacker_once() -> void:
	game.start_race(0)
	await _wait_race()
	var race: Node2D = game.race
	race.set_weapons_enabled(true)
	race.start_race()
	await wait_physics_frames(5)
	var popup: DefeatPopup = race.defeat_popup
	var seen: Array = []
	popup.shown.connect(func(rival: int, text: String) -> void: seen.append([rival, text]))
	race.combat.events.append({"kind": "destroyed", "type": 0, "pos": Vector2.ZERO, "car": 0, "owner": 9})
	race.combat.events.append({"kind": "destroyed", "type": 0, "pos": Vector2.ZERO, "car": 0, "owner": 2})
	await wait_physics_frames(3)
	assert_eq(seen.size(), 1, "one card at a time (minimum gap)")
	assert_eq(seen[0][0], 9, "the actual attacker")
	assert_eq(seen[0][1], RivalTaunts.line(9, 0))
	race.combat.events.append({"kind": "destroyed", "type": 0, "pos": Vector2.ZERO, "car": 3, "owner": 9})
	race.combat.events.append({"kind": "destroyed", "type": 0, "pos": Vector2.ZERO, "car": 0, "owner": 0})
	popup.time += DefeatPopup.MIN_GAP
	await wait_physics_frames(3)
	assert_eq(seen.size(), 1, "rivals hitting rivals, or your own mine: no card")
	race.combat.events.append({"kind": "destroyed", "type": 0, "pos": Vector2.ZERO, "car": 0, "owner": 9})
	await wait_physics_frames(3)
	assert_eq(seen.size(), 2)
	assert_eq(seen[1][1], RivalTaunts.line(9, 1), "the next line, not a repeat")
	assert_false(popup.has_node("AudioStreamPlayer"), "silent: the Voice Director stays the only voice")


# --- Racing for Keeps ---

func _own(ids: Array) -> void:
	game.cars.owned.clear()
	for id in ids:
		game.cars.owned.append(id)
	game.cars.save()
	game.title.player_car = ids[0] if not ids.is_empty() else 0


## A whole championship decided at once (round results recorded directly).
func _decide(player_wins: bool) -> void:
	var order: Array = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9] if player_wins else [1, 2, 3, 4, 5, 6, 7, 8, 9, 0]
	game.champ.record(order, [])
	game.champ.record(order, [])
	game.race.championship_round_done.emit(order, [])
	await wait_physics_frames(60)


func test_winning_with_a_won_car_keeps_it_and_adds_a_new_one() -> void:
	_own([2])
	assert_string_contains(game.title.keeps_text(), "OR LOSE ROCCO'S CAR", "the stake is shown before the start")
	game.start_championship(0)
	await _wait_race()
	var cfg := ConfigFile.new()
	cfg.load(CARS)
	assert_eq(int(cfg.get_value("cars", "stake", 0)), 2, "the stake is saved at the start")
	assert_eq(game.cars.stake, 2)
	assert_string_contains(game.race.championship_label, "FOR KEEPS")
	await _decide(true)
	var saved := CarCollection.new(CARS)
	assert_true(saved.owns(2), "the car entered with stays")
	assert_eq(saved.owned.size(), 2, "plus the normal reward")
	assert_eq(saved.stake, 0)


func test_losing_with_a_won_car_returns_it_to_its_rival() -> void:
	_own([2, 9])
	game.start_championship(0)
	await _wait_race()
	await _decide(false)
	assert_eq(game.last_lost, 2)
	var saved := CarCollection.new(CARS)
	assert_false(saved.owns(2), "Rocco's car goes back")
	assert_false(saved.displaced(2), "Rocco drives his own car again")
	assert_true(saved.owns(9), "other won cars stay")
	assert_eq(game.title.player_car, 0, "the player falls back to the own car")
	assert_string_contains(game.lost_text(2), "ROCCO RECLAIMS THE CAR!")
	var back: Dictionary = game.memory.events[-1]
	assert_eq([back.kind, back.rival], [RivalMemory.TOOK_CAR_BACK, 2], "Rocco remembers taking it back")
	# it can be won again later
	game.abandon_championship()
	await wait_physics_frames(60)
	assert_eq(game.cars.claim_lowest([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]), 8, "Rocco's car can be won back later (9 still owned)")


func test_the_own_car_is_never_at_stake() -> void:
	_own([5])
	game.title.player_car = 0
	assert_eq(game.title.keeps_text(), "", "no warning with the own car")
	game.start_championship(0)
	await _wait_race()
	assert_eq(game.cars.stake, 0)
	await _decide(false)
	assert_eq(game.last_lost, 0)
	assert_true(CarCollection.new(CARS).owns(5), "nothing lost")


func test_forfeiting_asks_first_and_loses_the_car() -> void:
	_own([4])
	game.start_championship(0)
	await _wait_race()
	var menu: RaceMenu = game.race.race_menu
	assert_ne(menu.warning, "", "the race menu warns about the stake")
	menu.open(false)
	menu._on_leave()
	assert_true(game.race != null, "the first press only warns")
	assert_eq(menu._leave.text, "CONFIRM: FORFEIT")
	menu.close()
	game.race.leave_race()
	await wait_physics_frames(60)
	assert_null(game.champ)
	assert_false(CarCollection.new(CARS).owns(4), "forfeited: Hank takes the car back")
	assert_string_contains(game.title._notice.text, "FORFEITED")


func test_quitting_the_game_does_not_escape_the_stake() -> void:
	var cars := CarCollection.new(CARS)
	cars.clear()
	cars.owned.append(7)
	cars.save()
	cars.put_at_stake(7)  # a championship for keeps was running when the game closed
	var next_start := CarCollection.new(CARS)
	assert_eq(next_start.forfeited_on_load, 7)
	assert_false(next_start.owns(7), "forfeited on the next start")
	assert_eq(CarCollection.new(CARS).stake, 0, "and settled once")


func test_consecutive_championships_change_ownership() -> void:
	_own([])
	game.title.player_car = 0
	game.start_championship(0)
	await _wait_race()
	await _decide(true)
	var won: int = game.last_reward
	assert_between(won, 1, 9)
	game.abandon_championship()
	await wait_physics_frames(60)
	game.title.player_car = won
	game.start_championship(0)
	await _wait_race()
	assert_eq(game.race.player_car, won, "racing the won car")
	assert_eq(game.race._car_looks[0].body, CarArt.look(game.resolver, AssetCatalog.ai_car(won)).body,
		"in the rival's original colours (no repaint)")
	await _decide(false)
	assert_false(CarCollection.new(CARS).owns(won), "lost again")
	assert_eq(CarCollection.new(CARS).owned.size(), 0)

