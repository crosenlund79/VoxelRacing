extends GutTest
## Nemesis Welcome in the real game: a race that ends is remembered from its own
## statistics (a rival's mine causing the player's DNF), a spectator race or a
## race left early is not; the greeting shows the rival's actual car (the
## junker while the player owns its car), name and taunt, never blocks the
## title, and goes on any key, a click or by itself; a missing recording
## leaves it text only.

const MAIN_SCENE := preload("res://src/main/main.tscn")
const GAME_SCENE := preload("res://src/main/game.tscn")
const CARS := "user://test_run/nemesis_cars.cfg"
const P := RaceSession.PLAYER_ID

var _path := ""


func before_each() -> void:
	_path = "user://test_run/nemesis_%d.cfg" % randi()


func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CARS))


func _race(spectate := false) -> Node2D:
	var m: Node2D = MAIN_SCENE.instantiate()
	m.presentation_enabled = false
	m.weapons_lock_enabled = false
	m.use_command_line_layout = false
	m.layout_override = DevLayouts.load_layout("kestrel_ridge")
	m.rival_memory = RivalMemory.new(_path)
	add_child_autofree(m)
	await wait_physics_frames(2)
	if spectate:
		m.set_menu_choice(2)
	m.set_weapons_enabled(true)
	m.start_race()
	await wait_physics_frames(3)
	return m


## Rival `owner`'s mine goes off under the player's car, which is nearly worn out: a DNF.
func _mine_dnf(m: Node2D, owner: int) -> void:
	m.damage.condition[P] = 3.0
	m.combat.mines.append({"owner": owner, "pos": m.cars[P].global_position, "age": m.combat.rules.mine_fuse - 0.01})
	await wait_physics_frames(6)


func test_a_rivals_mine_that_ends_the_players_race_is_remembered() -> void:
	var m := await _race()
	await _mine_dnf(m, 4)
	assert_true(m.session.racers[P].dnf, "the player is out")
	m._remember_race()  # (what the race does when it concludes)
	var mem: RivalMemory = m.rival_memory
	assert_eq(mem.events.size(), 1)
	var e: Dictionary = mem.events[0]
	assert_eq([e.kind, e.rival, e.weapon, e.lap, e.circuit], [RivalMemory.TOOK_YOU_OUT, 4, WeaponRules.Weapon.MINE, 1, "Kestrel Ridge"])
	var saved := RivalMemory.new(_path)
	saved.load_from_disk()
	assert_eq(saved.events.size(), 1, "saved")
	assert_eq(NemesisLines.taunt(e), "Still remember those mines?")


func test_spectating_and_races_left_early_remember_nothing() -> void:
	var s := await _race(true)
	await _mine_dnf(s, 4)
	s._remember_race()
	assert_eq(s.rival_memory.events.size(), 0, "no player in a spectator race")
	s.queue_free()
	await wait_physics_frames(2)
	var m := await _race()
	await _mine_dnf(m, 4)
	m.leave_race()  # never concluded: nothing remembered
	await wait_physics_frames(10)
	var saved := RivalMemory.new(_path)
	saved.load_from_disk()
	assert_eq(saved.events.size(), 0)


func _game(owned: Array = []) -> Node:
	var cars := CarCollection.new(CARS)
	cars.clear()
	for c in owned:
		cars.owned.append(c)
	cars.save()
	var g: Node = GAME_SCENE.instantiate()
	g.cars_path = CARS
	g.memory_path = _path
	g.greetings_enabled = false
	add_child_autofree(g)
	await wait_physics_frames(3)
	return g


func test_greeting_shows_the_rivals_real_car_name_and_taunt_and_dismisses() -> void:
	var g := await _game()
	var e: Dictionary = g.memory.add(RivalMemory.TOOK_YOU_OUT, 4, {"weapon": WeaponRules.Weapon.REAR_MISSILE, "lap": 19,
		"circuit": "Kestrel Ridge", "laps": 20}, true)  # (test data)
	var w: NemesisWelcome = g.show_greeting(e, RandomNumberGenerator.new())
	await wait_process_frames(3)
	assert_true(w.showing())
	var lines := w.text_lines()
	assert_eq(lines[0], "HANK - THE WALL")
	assert_eq(lines[3], '"Still remember those rear rockets?"')
	assert_eq(w._car.texture, CarArt.icon(g.resolver, AssetCatalog.ai_car(4)), "Hank's own car, in its colours")
	assert_null(w._voice.stream, "no Hank recording: text only")
	assert_lt(w._panel.size.x, 720.0, "compact: a corner of the screen, the title stays usable")
	var ev := InputEventKey.new()
	ev.keycode = KEY_DOWN
	ev.pressed = true
	Input.parse_input_event(ev)
	await wait_process_frames(3)
	assert_false(w.showing(), "any key dismisses it")


func test_a_displaced_rival_greets_from_the_junker_and_rocco_laughs() -> void:
	var g := await _game([2])  # the player owns Rocco's car: Rocco races the junker
	var e: Dictionary = g.memory.add(RivalMemory.BEAT_YOU_CLOSE, 2, {"gap": 0.3, "circuit": "Larkspur Ring"}, true)
	var w: NemesisWelcome = g.show_greeting(e, RandomNumberGenerator.new())
	await wait_process_frames(2)
	assert_eq(w._car.texture, CarArt.icon(g.resolver, AssetCatalog.CAR_JUNKER), "the junker it really drives now")
	assert_not_null(w._voice.stream, "Rocco's own laugh (the user's recording)")
	assert_true(w._voice.playing)
	w.dismiss()
	assert_false(w.showing())
	assert_false(w._voice.playing, "dismissing stops the laugh")


func test_greeting_leaves_by_itself() -> void:
	var g := await _game()
	var e: Dictionary = g.memory.add(RivalMemory.WON_MY_CAR, 7, {}, true)
	var w: NemesisWelcome = g.show_greeting(e, RandomNumberGenerator.new())
	await wait_seconds(NemesisWelcome.SHOW_TIME + 1.5)
	assert_false(w.showing(), "gone without any input")
