extends GutTest
## The title screen's LAYOUT selector, independent of the TRACK theme, applied
## to every kind of race, never saved, shown before racing. Since the first
## original circuit, players get Kestrel Ridge (the default and only player
## layout); the legacy Classic Circuit and Figure Eight stay loadable by id
## (developer argument, tests) and are unchanged.

const GAME_SCENE := preload("res://src/main/game.tscn")
const CLASSIC := "res://src/track/circuit_01.tres"
const FIGURE8 := "exp_figure8_01"
const KESTREL := "kestrel_ridge"

var _game: Node


func before_each() -> void:
	_game = GAME_SCENE.instantiate()
	_game.achievements_path = "user://test_layout_selection_ach.cfg"
	add_child_autofree(_game)
	await wait_physics_frames(3)


func after_each() -> void:
	if is_instance_valid(_game):
		_game.title.stop_audio()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_layout_selection_ach.cfg"))


func _start(choice: int, with_garage := false, devices: Array[int] = []) -> Node2D:
	_game.start_race(choice, with_garage, devices)
	await wait_physics_frames(30)
	return _game.race


func _back() -> void:
	_game.back_to_title()
	await wait_physics_frames(30)


func test_selector_defaults_to_kestrel_ridge_and_offers_no_legacy_layout() -> void:
	var t: TitleScreen = _game.title
	assert_eq(t.layout_id, KESTREL, "fresh launch: Kestrel Ridge")
	assert_eq(t._layout_button.text, "CIRCUIT:  KESTREL RIDGE")
	t._cycle_layout()
	assert_eq(t.layout_id, "larkspur_ring")
	assert_eq(t._layout_button.text, "CIRCUIT:  LARKSPUR RING")
	t._cycle_layout()
	assert_eq(t.layout_id, "ravenhook")
	t._cycle_layout()
	assert_eq(t.layout_id, KESTREL, "round again")
	assert_eq(DevLayouts.ids(), [KESTREL, "larkspur_ring", "ravenhook"] as Array[String], "legacy layouts are not offered")
	var cfg := ConfigFile.new()
	cfg.load(t.settings.path)
	assert_false(cfg.has_section_key("game", "layout"), "never saved")
	# a developer-preselected legacy layout stays reachable and cycles back
	t.layout_id = FIGURE8
	t._cycle_layout()
	assert_eq(t.layout_id, KESTREL, "after the legacy layout: back to the first player layout")
	assert_eq(DevLayouts.ids(FIGURE8), [KESTREL, "larkspur_ring", "ravenhook", FIGURE8] as Array[String])
	assert_eq(DevLayouts.initial_id(PackedStringArray(["--layout=exp_figure8_01"])), FIGURE8)
	assert_eq(DevLayouts.initial_id(PackedStringArray()), KESTREL)


func test_title_menu_fits_at_1280x720() -> void:
	var menu: Control = _game.title._main_menu
	await wait_physics_frames(2)
	var r := Rect2(menu.global_position, menu.size)
	assert_true(Rect2(0, 0, 1280, 720).encloses(r), "menu %s on screen" % r)
	assert_lt(r.end.y, 686.0, "clear of the controls hint at the bottom")
	_game.title._open_setup("quick")
	await wait_physics_frames(12)
	assert_true(_game.title._layout_button.is_visible_in_tree(), "the circuit is chosen on the setup screen")
	var setup: Control = _game.title._setup
	var sr := Rect2(setup.global_position, setup.size)
	assert_true(Rect2(0, 0, 1280, 720).encloses(sr), "setup screen %s on screen" % sr)


func test_title_races_start_on_kestrel_ridge() -> void:
	var race := await _start(0)
	assert_eq(DevLayouts.id_of(race.track.layout), KESTREL)
	assert_true(race.track.layout.has_elevation())
	assert_true(race.track.layout.has_jumps())
	assert_not_null(race.jumps, "the jump is on in local races")
	assert_string_contains(race.hud_track_name, "Kestrel Ridge", "shown on the grid panel")


func test_legacy_classic_circuit_is_unchanged() -> void:
	_game.title.layout_id = "classic_01"
	var race := await _start(0)
	assert_eq(race.track.layout.resource_path, CLASSIC)
	assert_false(race.track.layout.has_elevation())
	assert_string_contains(race.hud_track_name, "Classic Circuit")


func test_layout_applies_to_every_kind_of_race_with_any_theme() -> void:
	_game.title.layout_id = FIGURE8
	var cases := [[0, false, [] as Array[int], "quick race"], [2, false, [] as Array[int], "spectating"],
		[0, true, [] as Array[int], "garage race"], [0, false, [3, 4] as Array[int], "couch two players"]]
	var variant := 1
	for c in cases:
		_game.title.track_variant = variant
		var race := await _start(c[0], c[1], c[2])
		assert_not_null(race, c[3])
		if race == null:
			continue
		assert_eq(DevLayouts.id_of(race.track.layout), FIGURE8, c[3])
		assert_eq(race.track.theme.variant, variant, c[3] + ": theme independent")
		assert_string_contains(race.hud_track_name, "Figure Eight (Experimental)", c[3] + ": shown before racing")
		variant = variant % 3 + 1
		await _back()


func test_menu_choice_wins_over_the_command_line_inside_the_game() -> void:
	# the developer argument only preselects the title button; the race uses the button
	_game.title.layout_id = DevLayouts.CLASSIC
	var race := await _start(0)
	assert_false(race.use_command_line_layout)
	assert_eq(race.track.layout.resource_path, CLASSIC)
	assert_eq(DevLayouts.load_layout(DevLayouts.CLASSIC), null)
	assert_eq(DevLayouts.ids()[0], KESTREL)
