extends GutTest
## Rival racecraft: race-length ammunition, personality ammo pacing, Micro
## Nemesis, own racing lines and the personality differences behind them.

var _line: RacingLine


func before_all() -> void:
	var layout: TrackLayout = load("res://src/track/circuit_01.tres")
	_line = RacingLine.new(ClosedPath.new(layout.sample_centerline()), layout.road_width,
		load("res://src/driving/default_driving_params.tres"), load("res://src/ai/default_ai_params.tres"))


func _driver(id: int) -> AiDriver:
	var d := AiDriver.new(_line, load(RivalRoster.params_path(id)))
	d.begin_race(1234)
	return d


func test_ammo_scales_with_race_length() -> void:
	var rules: WeaponRules = load("res://src/combat/default_weapon_rules.tres")
	assert_eq(rules.ammo_scale(3), 1.0)
	assert_eq(rules.ammo_scale(7), 2.0)
	assert_eq(rules.ammo_scale(20), 5.0, "20 laps carry five times the 3-lap rounds")
	assert_eq(rules.ammo_scale(50), 10.0)
	var w := CombatWorld.new(rules, 3)
	var base: int = w.ammo[1][0]
	w.scale_ammo(5.0, [1])
	assert_eq(w.ammo[1][0], base * 5)
	assert_eq(w.start_ammo[1][0], base * 5)
	assert_eq(w.ammo[0][0], base, "only the listed cars")
	w.scale_ammo(50.0, [2])
	assert_eq(w.ammo[2][0], WeaponRules.MAX_ROUNDS, "capped")


func test_disciplined_drivers_save_ammo_when_ahead_of_budget() -> void:
	var ctx := {"lap_count": 20, "laps_left": 15}  # a quarter of the race done
	var victor := _driver(1)
	var rocco := _driver(2)
	# 70 % of the rounds already gone
	assert_gt(victor.spend_penalty(15, 50, ctx), rocco.spend_penalty(15, 50, ctx), "Victor gets pickier than Rocco")
	assert_gt(victor.spend_penalty(15, 50, ctx), 0.3)
	assert_almost_eq(victor.spend_penalty(45, 50, {"lap_count": 20, "laps_left": 15}), 0.0, 0.001, "on budget: no penalty")
	assert_lt(victor.spend_penalty(48, 50, {"lap_count": 20, "laps_left": 5}), 0.0, "well under budget: keener")
	assert_lt(victor.spend_penalty(2, 50, {"lap_count": 20, "laps_left": 1}), 0.0, "last lap: nothing saved")


func test_personality_traits_are_ordered_as_described() -> void:
	var p := {}
	for id in range(1, 10):
		p[id] = load(RivalRoster.params_path(id))
	assert_lt(p[2].ammo_discipline, p[1].ammo_discipline, "Rocco impulsive, Victor calculated")
	assert_lt(p[2].ammo_discipline, p[9].ammo_discipline, "Nina calculated")
	assert_gt(p[1].hazard_lookahead, p[2].hazard_lookahead, "Victor anticipates wrecks, Rocco late")
	assert_lt(p[9].hazard_reaction, p[2].hazard_reaction, "Nina reacts precisely")
	assert_gt(p[8].line_wander, p[1].line_wander, "Finn unpredictable")
	assert_eq(p[7].line_wander, 0.0, "Greta on the line")
	assert_gt(p[2].grudge_bonus, p[1].grudge_bonus, "Rocco holds grudges")


func test_micro_nemesis_favours_the_offender_and_fades() -> void:
	var rocco := _driver(2)
	var t_offender := {"id": 5}
	var t_other := {"id": 6}
	assert_eq(rocco._with_grudge(0.5, t_offender), 0.5, "no grudge yet")
	rocco.on_destroyed_by(5, 2)
	assert_gt(rocco._with_grudge(0.5, t_offender), 0.5, "the offender looks like a better shot")
	assert_eq(rocco._with_grudge(0.5, t_other), 0.5, "nobody else")
	assert_eq(rocco._with_grudge(0.0, t_offender), 0.0, "no chase: only a real chance is improved")
	var early := rocco._with_grudge(0.5, t_offender)
	rocco.grudge_left = rocco.params.grudge_time * 0.25
	assert_lt(rocco._with_grudge(0.5, t_offender), early, "fades")
	rocco.on_destroyed_by(2, 2)
	assert_eq(rocco.grudge_id, 5, "own mine: no grudge against oneself")
	rocco.begin_race(9)
	assert_eq(rocco._with_grudge(0.5, t_offender), 0.5, "a new race forgets")


func test_own_lines_stay_on_the_road_and_differ() -> void:
	var finn := _driver(8)
	var greta := _driver(7)
	var diff := 0.0
	for k in 200:
		finn._time = k * 0.1
		greta._time = k * 0.1
		var s := float(k) * 37.0
		var limit := _line.half_width_at(s)
		assert_true(absf(finn.own_line(s)) <= limit, "inside the road")
		assert_eq(greta.own_line(s), _line.offset_at(s), "Greta drives the shared line")
		diff = maxf(diff, absf(finn.own_line(s) - _line.offset_at(s)))
	assert_gt(diff, 10.0, "Finn wanders off the shared line")


## Ammunition pacing (2026-11-23): each personality's spending schedule over
## the race, continuous progress, longer races kept closer to it, valuable
## weapons kept for better chances, impulsive bursts, no absolute holds.
func test_spending_schedules_follow_the_personalities() -> void:
	var victor := _driver(1)
	var rocco := _driver(2)
	var greta := _driver(7)
	var finn := _driver(8)
	assert_gt(rocco.spend_target(0.3), greta.spend_target(0.3), "Rocco spends early")
	assert_gt(greta.spend_target(0.3), victor.spend_target(0.3), "Victor saves for later")
	assert_gt(finn.spend_target(0.3), greta.spend_target(0.3), "Finn is quick on the trigger")
	assert_almost_eq(greta.spend_target(0.5), 0.95 * 0.5, 0.001, "Greta: an even schedule")
	for d in [victor, rocco, greta, finn]:
		assert_gt(d.spend_target(1.0), 0.85, "everyone means to use the rounds by the flag")


func test_pacing_uses_continuous_progress_and_race_length() -> void:
	var greta := _driver(7)
	var a := {"lap_count": 3, "laps_left": 3, "progress": 0.05}
	var b := {"lap_count": 3, "laps_left": 3, "progress": 0.6}
	assert_gt(greta.spend_penalty(2, 10, a), greta.spend_penalty(2, 10, b), "the same lap, later in it: keener")
	var short := {"lap_count": 3, "laps_left": 2, "progress": 0.5}
	var long := {"lap_count": 50, "laps_left": 25, "progress": 0.5}
	assert_gt(greta.spend_penalty(20, 100, long), greta.spend_penalty(2, 10, short), "long races keep closer to the schedule")


func test_behind_schedule_late_means_spending() -> void:
	var victor := _driver(1)
	var ctx := {"lap_count": 20, "laps_left": 4, "progress": 0.82}
	assert_lt(victor.spend_penalty(45, 50, ctx), -0.15, "lots left late in the race: shots come easier")
	assert_lt(victor.spend_penalty(45, 50, ctx), victor.spend_penalty(45, 50, {"lap_count": 20, "laps_left": 12, "progress": 0.42}))


func test_valuable_weapons_wait_for_better_chances() -> void:
	var v := _driver(1)
	var ctx := {"lap_count": 7, "laps_left": 4, "progress": 0.45}
	var plain := v.spend_penalty(4, 8, ctx, WeaponRules.Weapon.FRONT_MISSILE)
	assert_gt(v.spend_penalty(4, 8, ctx, WeaponRules.Weapon.HOMING_MISSILE), plain)
	assert_gt(v.spend_penalty(4, 8, ctx, WeaponRules.Weapon.SUPER_MISSILE), v.spend_penalty(4, 8, ctx, WeaponRules.Weapon.HOMING_MISSILE))


func test_finn_has_impulsive_spells() -> void:
	var finn := _driver(8)
	finn.begin_race(5)
	var spells := 0
	for i in 60 * 120:
		if finn._impulse(1.0 / 60.0) > 0.0 and finn._burst_left >= finn.params.impulse_time - 0.02:
			spells += 1
	assert_gt(spells, 2, "a few trigger-happy spells in two minutes")
	var greta := _driver(7)
	assert_eq(greta._impulse(1.0), 0.0, "Greta never")
