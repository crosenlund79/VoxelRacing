extends GutTest
## Presentation & Personality pass (2026-11-23): the results' outcome line,
## the race introduction, the championship line from real points, the pause
## menu's race identity - all read-only on the race (it stays bit-identical).

const MAIN_SCENE := preload("res://src/main/main.tscn")
const MAIN_SCRIPT := preload("res://src/main/main.gd")
const P := RaceSession.PLAYER_ID


func _racers(times: Array, dnf: Array = []) -> Array[RacerState]:
	# racer i finishes in `times[i]` (< 0: still running)
	var out: Array[RacerState] = []
	for i in times.size():
		var r := RacerState.new(i, "R%d" % i, i == 0, 4, 3)
		if dnf.has(i):
			r.dnf = true
		elif times[i] >= 0.0:
			r.finish_position = out.size() + 1
			r.finish_time = times[i]
		out.append(r)
	return out


func test_outcome_line_says_what_the_result_means() -> void:
	var win := _racers([90.0, 91.0, 95.0])
	assert_eq(Hud.outcome(win, 0).tone, "win")
	var close: Array[RacerState] = _racers([90.4, 90.0, 95.0])
	close.sort_custom(func(a: RacerState, b: RacerState) -> bool: return a.finish_time < b.finish_time)
	var o := Hud.outcome(close, 0)
	assert_eq(o.tone, "close", "second, 0.4 s behind")
	assert_string_contains(o.text, "0.40")
	var podium: Array[RacerState] = _racers([95.0, 90.0, 91.0])
	podium.sort_custom(func(a: RacerState, b: RacerState) -> bool: return a.finish_time < b.finish_time)
	assert_eq(Hud.outcome(podium, 0).tone, "podium")
	var out := _racers([-1.0, 90.0, 91.0], [0])
	assert_eq(Hud.outcome(out, 0).tone, "dnf")
	assert_string_contains(Hud.outcome(out, 0).text, "no points")
	assert_eq(Hud.outcome(win, 7), {}, "not in the standings (spectating): no line")


func test_championship_line_from_real_points_only() -> void:
	var pts := {}
	for id in 10:
		pts[id] = 0
	assert_eq(MAIN_SCRIPT.championship_line(pts, P), "", "no points yet: nothing to say")
	pts[2] = 25
	pts[P] = 18
	assert_string_contains(MAIN_SCRIPT.championship_line(pts, P), "leads the championship  -  you are 2nd, 7 points behind")
	assert_string_contains(MAIN_SCRIPT.championship_line(pts, P), "Rocco")
	pts[P] = 40
	assert_eq(MAIN_SCRIPT.championship_line(pts, P), 'You lead the championship by 15 points from Rocco "Mad Dog"')


func test_race_introduction_and_pause_menu_name_the_race() -> void:
	var m: Node2D = MAIN_SCENE.instantiate()
	m.presentation_enabled = true
	m.night = true
	add_child_autofree(m)
	await wait_physics_frames(3)
	var intro: String = m.hud.intro_text()
	assert_string_contains(intro, "QUICK RACE")
	assert_string_contains(intro, "NIGHT")
	assert_string_contains(intro, "%d laps" % m.session.lap_count())
	m.set_lap_count(7)
	await wait_physics_frames(2)
	assert_string_contains(m.hud.intro_text(), "7 laps", "follows the grid panel's settings")
	m.start_race()
	await wait_seconds(3.5)
	assert_eq(m.hud.intro_text(), "", "gone shortly after GO!")
	m.open_race_menu()
	await wait_process_frames(2)
	assert_string_contains(m.race_menu._context.text, "NIGHT")
	assert_eq(m.race_menu._resume.custom_minimum_size.y, 58.0, "RESUME is the main menu's primary button")
	m.resume_race()


func test_garage_centrepiece_is_the_car_being_prepared() -> void:
	var game: Node = load("res://src/main/game.tscn").instantiate()
	game.cars_path = "user://test_run/pres_cars_%d.cfg" % randi()
	game.career_path = "user://test_run/pres_career_%d.cfg" % randi()
	game.career_garage_path = "user://test_run/pres_cgarage_%d.cfg" % randi()
	game.greetings_enabled = false
	add_child_autofree(game)
	await wait_physics_frames(3)
	game._show_garage_car(0)
	assert_eq(game.garage_screen.car_texture(), CarArt.icon(game.resolver, AssetCatalog.CAR_PLAYER), "the own car, as it races")
	game.cars.owned.append(4)
	game._show_garage_car(4)
	assert_eq(game.garage_screen.car_texture(), CarArt.icon(game.resolver, AssetCatalog.ai_car(4)), "Hank's car in its own colours")
	assert_eq(game.garage_screen._car_name.text, "HANK'S CAR")
	game.cars.owned.erase(4)
	game._show_garage_car(4)
	assert_eq(game.garage_screen._car_name.text, "YOUR OWN CAR", "a car no longer owned is never shown")
	# feedback: buying pulses and shows the money changing hands; the rules are the garage's
	var g: PlayerGarage = game.garage_screen.garage
	var money := g.money
	game.garage_screen.open()
	game.garage_screen._trade(WeaponRules.Weapon.MINE, true)
	assert_eq(g.money, money - g.rules.price(WeaponRules.Weapon.MINE), "price unchanged")
	await wait_process_frames(2)
	assert_true(game.garage_screen._root.get_children().any(func(n: Node) -> bool: return n is Label and n.text == "-$%d" % g.rules.price(WeaponRules.Weapon.MINE)))
	game.garage_screen.close()


func test_visible_damage_follows_condition_only() -> void:
	var m: Node2D = MAIN_SCENE.instantiate()
	m.presentation_enabled = true
	add_child_autofree(m)
	await wait_physics_frames(3)
	var dv: DamageView = m.damage_view
	var car: Car = m.cars[3]
	assert_eq((car.sprite.material as ShaderMaterial).get_shader_parameter("wear"), m.resolver.get_texture(AssetCatalog.CAR_WEAR),
		"one shared, catalogued wear drawing (replaceable like any asset)")
	await wait_process_frames(2)
	assert_eq(dv.wear_of(3), 0.0, "healthy: as painted")
	m.damage.condition[3] = 70.0
	await wait_process_frames(2)
	assert_between(dv.wear_of(3), 0.1, 0.5, "worn")
	assert_false(dv._smoke[3].emitting, "no smoke yet")
	m.damage.condition[3] = 40.0
	await wait_process_frames(2)
	assert_gt(dv.wear_of(3), 0.5, "heavy")
	assert_true(dv._smoke[3].emitting, "thin smoke")
	m.damage.condition[3] = 20.0
	await wait_process_frames(2)
	assert_eq(dv.wear_of(3), 1.0, "critical: full wear")
	assert_eq(DamageView.wear_amount(1.0), 0.0)
	assert_eq(DamageView.wear_amount(0.0), 1.0)
