extends GutTest
## M3.5 Stage 4 in the full scene: achievement tracking never changes a race
## (fresh-process probes), completed races are counted exactly once in normal
## and spectator mode (also at fast speed), unlocks come from real combat
## events, persist, show a toast, and the title catalogue resets only after
## confirmation.

const MAIN_SCENE := preload("res://src/main/main.tscn")
const GAME_SCENE := preload("res://src/main/game.tscn")
const PATH := "user://test_achievement_tracking.cfg"

var _main: Node2D
var _store: AchievementStore


func before_each() -> void:
	_store = AchievementStore.new(PATH)
	_main = MAIN_SCENE.instantiate()
	_main.weapons_lock_enabled = false  # fires at once (the start lock: test_weapons_hot.gd)
	_main.presentation_enabled = false
	_main.achievements = _store
	add_child_autofree(_main)
	await wait_physics_frames(2)


func after_each() -> void:
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0
	Engine.max_physics_steps_per_frame = 8
	for a in [PlayerControls.FIRE, PlayerControls.FIRE_REAR, PlayerControls.CONFIRM]:
		Input.action_release(a)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func _tap(action: String) -> void:
	Input.action_press(action)
	await wait_physics_frames(2)
	Input.action_release(action)
	await wait_physics_frames(1)


func _finish_player() -> void:
	var cps: int = _main.track.checkpoint_count()
	for lap in _main.session.lap_count():
		for i in range(1, cps):
			_main.session.checkpoint_reached(i, 0)
		_main.session.checkpoint_reached(0, 0)
	await wait_physics_frames(3)


func _rival_races() -> int:
	var n := 0
	for rid in AchievementStore.RIVAL_IDS:
		n += _store.rivals[rid].races
	return n


func test_tracking_does_not_change_races() -> void:
	for args in [["mode=spectate", "ticks=5400", "weapons=1", "style=1"], ["mode=race", "ticks=2400", "weapons=1"]]:
		var off := ProbeRunner.run(PackedStringArray(args + ["achievements=0"]))
		var on := ProbeRunner.run(PackedStringArray(args + ["achievements=1"]))
		assert_eq(off.length(), 32, off)
		assert_eq(on, off, str(args))


func test_spectator_races_count_once_each_at_fast_speed() -> void:
	_main.set_menu_choice(2)
	_main.set_sim_speed(8)
	_main.start_race()
	await wait_until(func() -> bool: return _main.history.race_count() >= 1, 150.0)
	assert_eq(_rival_races(), 9, "one race, nine rivals")
	assert_eq(_store.get_progress("spectator_races"), 1)
	await wait_until(func() -> bool: return _main.history.race_count() >= 2, 150.0)
	await wait_physics_frames(400)
	assert_eq(_rival_races(), 18, "the result screen and the restart do not count again")
	assert_eq(_store.get_progress("spectator_races"), 2)
	var winner: int = _main.history.results[0][0]
	assert_gte(_store.rivals[winner].wins, 1)
	var saved := AchievementStore.new(PATH)
	saved.load_store()
	assert_eq(saved.get_progress("spectator_races"), 2, "saved after each race")


func test_normal_race_counts_once_when_left_after_the_flag() -> void:
	await _tap(PlayerControls.FIRE)
	await _finish_player()
	assert_eq(_rival_races(), 0, "rivals still racing: not final yet")
	await _tap(PlayerControls.CONFIRM)  # leave the results: the running order becomes final
	assert_eq(_rival_races(), 9)
	assert_true(_store.is_unlocked("first_flag"))
	await wait_physics_frames(30)
	_main.reset_race()
	assert_eq(_rival_races(), 9, "no double counting across transitions")


func test_unfinished_race_is_not_counted() -> void:
	await _tap(PlayerControls.FIRE)
	await wait_physics_frames(60)
	_main.set_menu_choice(2)  # ignored while racing
	_main._exit_tree()
	assert_eq(_rival_races(), 0)
	assert_eq(_store.unlocked_count(), 0)


func test_own_goal_from_real_combat_events() -> void:
	_main.set_weapons_enabled(true)
	_main.start_race()  # without pressing Fire the player's car stays on the grid
	await wait_physics_frames(2)
	await _tap(PlayerControls.FIRE_REAR)
	await wait_until(func() -> bool: return _main.combat.destroyed_count[0] > 0, 6.0)
	var own := false
	for e in _main.combat.events:
		own = own or (e.kind == "destroyed" and e.car == 0 and e.owner == 0)
	assert_true(own, "destroyed by its own mine")
	await _finish_player()
	await _tap(PlayerControls.CONFIRM)
	assert_true(_store.is_unlocked("own_goal"))
	assert_false(_store.is_unlocked("rear_view_diplomacy"), "destroying yourself is not a kill")


func test_toast_and_catalogue_with_confirmed_reset() -> void:
	var game := GAME_SCENE.instantiate()
	game.achievements_path = PATH
	add_child_autofree(game)
	await wait_physics_frames(3)
	game.achievements.unlock("first_flag")
	assert_eq(game.toast.pending(), 1)
	var panel: AchievementsPanel = game.title._achievements_panel
	game.title._open_achievements()
	assert_true(panel.visible)
	assert_string_contains(panel._count.text, "1 / 30")
	var hidden_rows := 0
	for row in panel._list.get_children():
		var name: Label = row.get_child(1).get_child(0)
		if name.text == "???":
			hidden_rows += 1
	assert_eq(hidden_rows, 6, "hidden achievements stay secret")
	panel._ask_reset()
	assert_true(panel._confirm_row.visible)
	assert_eq(game.achievements.unlocked_count(), 1, "nothing erased before confirming")
	panel._do_reset()
	assert_eq(game.achievements.unlocked_count(), 0)
	game.title.stop_audio()
