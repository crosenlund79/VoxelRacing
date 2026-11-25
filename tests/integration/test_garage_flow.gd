extends GutTest
## M3.5 Stage 2 in the full scene: garage races use the player's own weapons and
## pay prize money exactly once; Race -> Results -> Garage -> Next race, and
## skipping the garage; quick races and spectating never touch the garage;
## rivals carry their Tactical loadouts.

const MAIN_SCENE := preload("res://src/main/main.tscn")
const GAME_SCENE := preload("res://src/main/game.tscn")
const W := WeaponRules.Weapon

var _main: Node2D


func _make(garage: PlayerGarage = null) -> void:
	_main = MAIN_SCENE.instantiate()
	_main.weapons_lock_enabled = false  # fires at once (the start lock: test_weapons_hot.gd)
	_main.presentation_enabled = false
	_main.garage = garage
	add_child_autofree(_main)
	await wait_physics_frames(2)


func after_each() -> void:
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0
	Engine.max_physics_steps_per_frame = 8
	for a in [PlayerControls.FIRE, PlayerControls.FIRE_FRONT, PlayerControls.FIRE_REAR, PlayerControls.HISTORY_VIEW,
			PlayerControls.CYCLE_FRONT, PlayerControls.CYCLE_REAR]:
		Input.action_release(a)


func _new_garage() -> PlayerGarage:
	return PlayerGarage.new(load("res://src/garage/default_garage_rules.tres"))


func _tap(action: String) -> void:
	Input.action_press(action)
	await wait_physics_frames(2)
	Input.action_release(action)
	await wait_physics_frames(1)


## Drives the player's lap counter to the flag (checkpoints in order).
func _finish_player() -> void:
	var cps: int = _main.track.checkpoint_count()
	for lap in _main.session.lap_count():
		for i in range(1, cps):
			_main.session.checkpoint_reached(i, 0)
		_main.session.checkpoint_reached(0, 0)
	await wait_physics_frames(3)


func test_garage_loadout_is_what_the_player_carries() -> void:
	var g := _new_garage()
	g.buy(W.HOMING_MISSILE, 3)
	g.equip(PlayerGarage.FRONT, W.HOMING_MISSILE)
	await _make(g)
	assert_eq(_main.combat.loadout[0], [W.HOMING_MISSILE, W.MINE])
	assert_eq(_main.combat.ammo[0], [3, 5])


func test_garage_race_pays_once_and_keeps_unused_rounds() -> void:
	var g := _new_garage()
	await _make(g)
	_main.set_weapons_enabled(true)
	await _tap(PlayerControls.FIRE)
	assert_true(g.race_pending())
	await _tap(PlayerControls.FIRE_FRONT)
	assert_eq(_main.combat.ammo[0][0], 4)
	await _finish_player()
	assert_eq(_main.session.state, RaceSession.State.FINISHED)
	var pos: int = _main.session.racers[0].finish_position
	assert_eq(g.races_settled, 1)
	assert_eq(g.money, g.rules.start_money + g.rules.prize_for(pos))
	assert_eq(g.count(W.FRONT_MISSILE), 4, "the fired round is gone, the rest carry over")
	await wait_physics_frames(30)
	assert_eq(g.races_settled, 1, "paid exactly once")
	assert_eq(g.money, g.rules.start_money + g.rules.prize_for(pos))


func test_results_then_garage_then_next_race() -> void:
	var g := _new_garage()
	await _make(g)
	watch_signals(_main)
	await _tap(PlayerControls.FIRE)
	await _finish_player()
	await _tap(PlayerControls.FIRE)
	assert_signal_not_emitted(_main, "garage_requested", "Fire does not leave the results")
	await _tap(PlayerControls.CONFIRM)
	assert_signal_emitted(_main, "garage_requested")
	assert_true(_main.garage_open)
	assert_eq(_main.session.state, RaceSession.State.MODE_SELECT)
	await _tap(PlayerControls.FIRE)
	assert_eq(_main.session.state, RaceSession.State.MODE_SELECT, "grid input paused while the garage is open")
	g.buy(W.SUPER_MISSILE)
	g.equip(PlayerGarage.FRONT, W.SUPER_MISSILE)
	_main.close_garage(true)
	assert_eq(_main.session.state, RaceSession.State.RACING)
	assert_eq(_main.combat.loadout[0][0], W.SUPER_MISSILE, "new purchase loaded")
	assert_eq(_main.grid_order[-1], 0, "reversed grid: the winner starts last")


func test_skip_shopping_goes_straight_to_the_next_race() -> void:
	var g := _new_garage()
	await _make(g)
	watch_signals(_main)
	await _tap(PlayerControls.FIRE)
	await _finish_player()
	await _tap(PlayerControls.HISTORY_VIEW)
	assert_signal_not_emitted(_main, "garage_requested")
	assert_eq(_main.session.state, RaceSession.State.RACING)
	assert_eq(g.races_settled, 1)


func test_closing_the_garage_to_the_grid_ignores_the_closing_key() -> void:
	var g := _new_garage()
	await _make(g)
	_main.open_garage()
	Input.action_press(PlayerControls.FIRE)
	_main.close_garage(false)
	await wait_physics_frames(2)
	Input.action_release(PlayerControls.FIRE)
	assert_eq(_main.session.state, RaceSession.State.MODE_SELECT)


func test_quick_race_ignores_any_garage_inventory() -> void:
	await _make(null)
	assert_eq(_main.combat.loadout[0], [W.FRONT_MISSILE, W.MINE])
	assert_eq(_main.combat.ammo[0], [_main.weapon_rules.front_ammo, _main.weapon_rules.rear_ammo])
	_main.set_combat_style(WeaponRules.Style.TACTICAL)
	assert_eq(_main.combat.ammo[0], [RivalArmoury.QUICK_RACE_PLAYER[1], RivalArmoury.QUICK_RACE_PLAYER[3]])


func test_spectating_never_touches_the_garage() -> void:
	var g := _new_garage()
	await _make(g)
	_main.set_menu_choice(2)
	_main.set_sim_speed(8)
	_main.start_race()
	assert_false(g.race_pending())
	await wait_until(func() -> bool: return _main.history.race_count() >= 1, 150.0)
	assert_eq(g.races_settled, 0)
	assert_eq(g.money, g.rules.start_money)


func test_rivals_carry_their_tactical_loadouts_and_classic_ones_otherwise() -> void:
	await _make(null)
	for id in range(1, 10):
		assert_eq(_main.combat.loadout[id], [W.FRONT_MISSILE, W.MINE], "Classic: M3 loadout")
	_main.set_combat_style(WeaponRules.Style.TACTICAL)
	for id in range(1, 10):
		var l := RivalArmoury.loadout(id)
		assert_eq(_main.combat.loadout[id], [l[0], l[2]])
		assert_eq(_main.combat.ammo[id], [l[1], l[3]])


func test_tactical_spectating_with_rival_loadouts_completes() -> void:
	await _make(null)
	_main.set_menu_choice(2)
	_main.set_weapons_enabled(true)
	_main.set_combat_style(WeaponRules.Style.TACTICAL)
	_main.set_sim_speed(8)
	_main.start_race()
	await wait_until(func() -> bool: return _main.history.race_count() >= 1, 200.0)
	assert_eq(_main.history.results[0].size(), 9)
	var types := {}
	for e in _main.combat.events:
		if e.kind == "fire":
			types[e.type] = true
	assert_gt(types.size(), 2, "several weapon types used: %s" % str(types.keys()))


func test_game_opens_the_garage_before_the_first_garage_race() -> void:
	var game := GAME_SCENE.instantiate()
	game.achievements_path = "user://test_game_achievements.cfg"
	add_child_autofree(game)
	await wait_physics_frames(3)
	await game.start_race(0, true)
	assert_true(game.garage_screen.visible)
	assert_true(game.race.garage_open)
	assert_eq(game.race.garage, game.garage)
	game._close_garage(true)
	assert_false(game.garage_screen.visible)
	assert_eq(game.race.session.state, RaceSession.State.RACING)
	await game.back_to_title()
	await game.start_race(0)
	assert_null(game.race.garage, "a quick race does not use the garage")
	game.title.stop_audio()


## The title's GARAGE row shows the saved career and starts over after a
## second, confirming press.
func test_new_garage_needs_confirmation() -> void:
	var game := GAME_SCENE.instantiate()
	add_child_autofree(game)
	await wait_physics_frames(3)
	game.garage.money = 1234
	game.title._open_setup("garage")
	assert_true(game.title._garage_button.visible)
	assert_string_contains(game.title._garage_button.text, "$1234")
	game.title._new_garage()
	assert_eq(game.garage.money, 1234, "first press only asks")
	assert_string_contains(game.title._garage_button.text, "CONFIRM")
	game.title._new_garage()
	assert_eq(game.garage.money, game.garage.rules.start_money, "second press resets")
	game.title._open_setup("quick")
	assert_false(game.title._garage_button.visible, "only for garage races")
	game.title.stop_audio()


## Weapon cycling in a real garage race: the player carries every owned type,
## cycles with the remappable key, fires the new type, and the garage keeps
## exactly the rounds left of each type afterwards.
func test_cycling_in_a_garage_race_and_settling_every_type() -> void:
	var g := _new_garage()
	g.buy(W.HOMING_MISSILE, 2)
	await _make(g)
	_main.set_weapons_enabled(true)
	await _tap(PlayerControls.FIRE)
	assert_eq(_main.combat.slot_types(0, CombatWorld.FRONT), [[W.FRONT_MISSILE, 5, true], [W.HOMING_MISSILE, 2, false]])
	await _tap(PlayerControls.CYCLE_FRONT)
	assert_eq(_main.combat.weapon_of(0, CombatWorld.FRONT), W.HOMING_MISSILE, "the cycle key switched the front slot")
	assert_string_contains(_main.hud._front_more.text, "FRONT 5", "the HUD lists the other carried type")
	await _tap(PlayerControls.FIRE_FRONT)
	assert_eq(_main.combat.ammo[0][0], 1, "a homing missile fired")
	await _finish_player()
	assert_eq(g.count(W.HOMING_MISSILE), 1)
	assert_eq(g.count(W.FRONT_MISSILE), 5, "the unused type keeps its rounds")
	assert_eq(g.equipped[PlayerGarage.FRONT], W.FRONT_MISSILE, "the equipped choice stays the garage's")


func test_equipped_only_keeps_the_single_weapon_loadout() -> void:
	var g := _new_garage()
	g.buy(W.HOMING_MISSILE, 2)
	g.set_carry_all(false)
	await _make(g)
	_main.set_weapons_enabled(true)
	await _tap(PlayerControls.FIRE)
	await _tap(PlayerControls.CYCLE_FRONT)
	assert_eq(_main.combat.weapon_of(0, CombatWorld.FRONT), W.FRONT_MISSILE, "nothing else carried")
	assert_false(_main.hud._front_more.visible)


func test_quick_races_carry_the_standard_loadout_only() -> void:
	await _make(null)
	_main.set_weapons_enabled(true)
	await _tap(PlayerControls.FIRE)
	await _tap(PlayerControls.CYCLE_FRONT)
	assert_eq(_main.combat.carried[0], [{}, {}])
	assert_eq(_main.combat.weapon_of(0, CombatWorld.FRONT), W.FRONT_MISSILE)


## Vehicle upgrades in the race: only the garage player's car, on top of the
## environment's handling; rivals, quick races and spectating stay stock; a
## purchase between races is raced with at once.
func test_upgrades_drive_the_garage_players_car_only() -> void:
	var g := _new_garage()
	g.money = 5000
	g.buy_upgrade("engine")
	g.buy_upgrade("steering")
	await _make(g)
	var base: DrivingParams = _main.driving_params
	var mine: DrivingParams = _main.cars[0].model.params
	assert_almost_eq(mine.acceleration, base.acceleration * 1.04, 0.001)
	assert_almost_eq(mine.turn_rate_degrees, base.turn_rate_degrees * 1.03, 0.001)
	for id in range(1, _main.cars.size()):
		assert_same(_main.cars[id].model.params, base, "rival %d: stock" % id)
	await _tap(PlayerControls.FIRE)
	await _finish_player()
	await _tap(PlayerControls.CONFIRM)  # to the garage
	assert_true(_main.garage_open)
	g.buy_upgrade("brakes")
	_main.close_garage(false)
	assert_almost_eq(_main.cars[0].model.params.brake_deceleration, base.brake_deceleration * 1.08, 0.001, "raced at once")
	_main.set_menu_choice(_main.Choice.SPECTATE)
	assert_same(_main.cars[0].model.params, base, "spectating: stock")


func test_quick_races_are_stock() -> void:
	await _make(null)
	assert_same(_main.cars[0].model.params, _main.driving_params)
