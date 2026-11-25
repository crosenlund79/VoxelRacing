extends GutTest
## Racing modes: finishing early and watching the rest live (celebration,
## spectating, provisional championship standings, skip), the kill feed and
## K / D / tombstones in a race, and Knockout (last place out every lap).

const MAIN_SCENE := preload("res://src/main/main.tscn")
const W := WeaponRules.Weapon

var _main: Node2D


func after_each() -> void:
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0
	Engine.max_physics_steps_per_frame = 8
	for a in [PlayerControls.FIRE, PlayerControls.CONFIRM, PlayerControls.HISTORY_VIEW, PlayerControls.STEER_RIGHT]:
		Input.action_release(a)


func _make(watch := true, presentation := false, mode := "race", layout := "larkspur_ring") -> void:
	_main = MAIN_SCENE.instantiate()
	_main.presentation_enabled = presentation
	_main.watch_enabled = watch
	_main.race_mode = mode
	_main.weapons_lock_enabled = false
	_main.use_command_line_layout = false
	_main.layout_override = load(DevLayouts.LAYOUTS[layout])
	add_child_autofree(_main)
	await wait_physics_frames(2)


func _tap(action: String) -> void:
	Input.action_press(action)
	await wait_physics_frames(2)
	Input.action_release(action)
	await wait_physics_frames(1)


## The player's laps driven to the flag (checkpoints in order).
func _finish_player() -> void:
	var cps: int = _main.track.checkpoint_count()
	for lap in _main.session.lap_count():
		for i in range(1, cps):
			_main.session.checkpoint_reached(i, 0)
		_main.session.checkpoint_reached(0, 0)
	await wait_physics_frames(3)


func _running_rival_progress() -> float:
	var total := 0.0
	for r in _main.session.racers:
		if r.id > 0 and not r.is_done():
			total += r.progress
	return total


func test_finishing_first_celebrates_then_watches_the_rivals_live() -> void:
	await _make()
	_main.set_lap_count(1)
	_main.start_race()
	await wait_physics_frames(30)
	await _finish_player()
	assert_eq(_main.session.racers[0].finish_position, 1, "position confirmed at once")
	assert_eq(_main.session.state, RaceSession.State.FINISHED)
	assert_false(_main.session.all_finished())
	assert_string_contains(_main.hud.caption_text(), "1ST PLACE - YOU FINISHED!")
	assert_string_contains(_main.hud.caption_text(), "RACE CONTINUES - WATCH YOUR RIVALS!")
	assert_false(_main.hud.results_up(), "no results while the rivals still race")
	var before := _running_rival_progress()
	await wait_physics_frames(120)
	assert_gt(_running_rival_progress(), before + 500.0, "the rivals keep racing after the player finished")
	assert_false(_main.watching, "still celebrating")
	await wait_physics_frames(int(Main_CELEBRATION() * 60.0))
	assert_true(_main.watching, "live spectating after the celebration")
	assert_ne(_main.camera.target, _main.cars[0], "the camera follows a rival")
	assert_string_contains(_main.hud.watch_hint(), "switch car")
	var first: int = _main.director.target_id
	await _tap(PlayerControls.STEER_RIGHT)
	await wait_physics_frames(2)
	assert_ne(_main.director.target_id, first, "Right: another car still racing")
	assert_false(_main.session.racers[_main.director.target_id].is_done())


static func Main_CELEBRATION() -> float:
	return 5.2


func test_skip_fast_forwards_the_real_race_to_the_results() -> void:
	await _make()
	_main.set_lap_count(1)
	_main.start_race()
	await wait_physics_frames(30)
	await _finish_player()
	await _tap(PlayerControls.HISTORY_VIEW)
	assert_eq(_main.sim_speed, _main.SKIP_SPEED, "the real simulation runs faster")
	await wait_until(func() -> bool: return _main.session.all_finished(), 60.0)
	await wait_physics_frames(3)
	assert_true(_main.session.all_finished(), "every rival really finished (or retired)")
	assert_eq(_main.sim_speed, 1, "back to normal speed")
	assert_false(_main.watching)
	for r in _main.session.racers:
		assert_true(r.dnf or r.finish_time > 0.0, "%s has a real finish time, not an invented position" % r.display_name)
	await wait_physics_frames(5)
	assert_true(_main.hud.results_up(), "then the results")


func test_a_dnf_player_watches_too() -> void:
	await _make()
	_main.set_lap_count(1)
	_main.start_race()
	await wait_physics_frames(30)
	_main.damage.damage(0, 1000.0)
	_main._retire(0)
	await wait_physics_frames(3)
	assert_string_contains(_main.hud.caption_text(), "OUT - DNF!")
	assert_string_contains(_main.hud.caption_text(), "WATCH YOUR RIVALS")
	await _tap(PlayerControls.FIRE)
	assert_false(_main.watching, "Fire (shooting) does nothing here")
	await _tap(PlayerControls.CONFIRM)
	assert_true(_main.watching, "Enter: watch at once")


func test_provisional_championship_standings_while_watching() -> void:
	_main = MAIN_SCENE.instantiate()
	_main.presentation_enabled = false
	_main.watch_enabled = true
	_main.weapons_lock_enabled = false
	_main.championship_round = 1
	_main.championship_points = {0: 18, 1: 25, 2: 15, 3: 12, 4: 10, 5: 8, 6: 6, 7: 4, 8: 2, 9: 1}
	_main.championship_scoring = PackedInt32Array([25, 18, 15, 12, 10, 8, 6, 4, 2, 1])
	_main.use_command_line_layout = false
	_main.layout_override = load(DevLayouts.LAYOUTS["larkspur_ring"])
	add_child_autofree(_main)
	await wait_physics_frames(2)
	_main.set_lap_count(1)
	_main.start_race()
	await wait_physics_frames(30)
	await _finish_player()
	await _tap(PlayerControls.CONFIRM)  # watch now
	await wait_physics_frames(5)
	var panel: ProvisionalPanel = _main.provisional_panel
	assert_not_null(panel)
	assert_true(panel.visible)
	var lines := panel.refresh(_main.championship_points, _main.championship_scoring, _main.session.standings(), _main.feed_names(), 0)
	var mine: Array = lines.filter(func(l: Array) -> bool: return l[0] == 0)[0]
	assert_eq(mine[1], 18 + 25, "the player's total with the win counted")
	assert_true(mine[3], "the player's points are final")
	var running: Array = lines.filter(func(l: Array) -> bool: return not l[3])
	assert_gt(running.size(), 0, "rivals still running are provisional")
	for k in lines.size() - 1:
		assert_true(lines[k][1] >= lines[k + 1][1], "sorted by total")


func test_kill_feed_credits_the_attacker_and_tombstones() -> void:
	await _make(false, true)
	_main.set_weapons_enabled(true)
	_main.start_race()
	for id in range(1, 10):
		_main.inputs[id] = DriverInput.new()  # (the base input: stays put, never fires)
	await wait_physics_frames(30)
	var feed: KillFeed = _main.kill_feed
	# Nina's mine under Hank (AI against AI)
	_main.combat.mines.append({"owner": 9, "pos": _main.cars[4].global_position, "age": _main.combat.rules.mine_fuse - 0.01})
	await wait_physics_frames(3)
	assert_eq(_main.stats.line(9), [0, 1, 0], "Nina: one kill")
	assert_eq(_main.stats.line(4)[2], 1, "Hank: one death")
	assert_string_contains(" | ".join(feed.lines()), "Nina [mines] Hank")
	# a final destruction: the car had almost nothing left
	await wait_physics_frames(200)  # Hank back on the road
	_main.damage.condition[5] = 1.0
	_main.combat.mines.append({"owner": 2, "pos": _main.cars[5].global_position, "age": _main.combat.rules.mine_fuse - 0.01})
	await wait_physics_frames(3)
	assert_true(_main.session.racers[5].dnf, "Maya out for good")
	assert_eq(_main.stats.line(2), [1, 1, 0], "Rocco: kill and tombstone")
	assert_string_contains(" | ".join(feed.lines()), "Rocco [mines] [tombstone] Maya")
	_main.hud.show_results(_main.session.standings())
	assert_eq(_main.hud.stats, _main.stats, "the results show TOMBSTONE | K | D")


func test_knockout_eliminates_last_place_every_lap_until_one_is_left() -> void:
	await _make(false, false, "knockout")
	_main.set_weapons_enabled(false)
	_main.set_menu_choice(2)  # nine rivals: eight eliminations
	_main.set_lap_count(9)
	_main.set_sim_speed(8)
	_main.start_race()
	var order: Array = []
	await wait_until(func() -> bool:
		for r in _main.session.racers:
			if r.knockout_lap > 0 and not order.has(r.id):
				order.append(r.id)
		return _main.session.state == RaceSession.State.FINISHED and _main.session.all_finished(), 900.0)
	assert_true(_main.session.all_finished())
	assert_eq(order.size(), 8, "one elimination per lap until one is left")
	for k in order.size():
		var r: RacerState = _main.session.racers[order[k]]
		assert_eq(r.knockout_lap, k + 1, "one per lap, in lap order")
		assert_false(_main.cars[r.id].active, "an eliminated car is out of the race")
		assert_true(_main.damage.is_retired(r.id), "and never comes back")
	var standings: Array[RacerState] = _main.session.standings()
	assert_eq(standings[0].finish_position, 1)
	assert_eq(standings[0].knockout_lap, 0, "the last one standing wins")
	for k in range(1, standings.size()):
		assert_true(standings[k].knockout_lap >= standings[k + 1].knockout_lap if k + 1 < standings.size() else true,
			"later eliminated = ranked higher")
	for id in 10:
		assert_eq(_main.stats.tombstones[id], 0, "eliminations by position give no tombstones")
	assert_string_contains(_main.knockout_text(), "WINNER")


## Knockout's nine laps are a rule: the grid panel shows them as fixed and
## the laps key does not change them (championship rounds alike).
func test_knockout_laps_are_fixed_on_the_grid() -> void:
	await _make(true, false, "knockout")
	_main.set_lap_count(9)
	await wait_physics_frames(10)
	await _tap(PlayerControls.HISTORY_VIEW)
	assert_eq(_main.lap_count(), 9, "the laps key changes nothing")
	assert_true(_main.laps_fixed())
	var texts := []
	for l in _main.hud._message_box.find_children("*", "Label", true, false):
		texts.append(l.text)
	var all := " | ".join(texts)
	assert_string_contains(all, "9 LAPS (FIXED)")
	assert_false(all.contains(PlayerControls.key_text(PlayerControls.HISTORY_VIEW) + ": laps"), "no laps hint")


func test_knockout_player_eliminated_watches() -> void:
	await _make(true, false, "knockout")
	_main.set_weapons_enabled(false)
	_main.set_lap_count(9)
	_main.start_race()  # the player never drives: last after the first lap
	await wait_physics_frames(240)
	assert_eq(_main.knockout_danger(), 0, "the parked player is in the drop zone")
	assert_string_contains(_main.knockout_text(), "YOU ARE IN THE DROP ZONE!")
	assert_eq(_main.hud.danger_id, 0)
	await wait_until(func() -> bool: return _main.session.racers[0].knockout_lap > 0, 120.0)
	await wait_physics_frames(3)
	assert_eq(_main.session.racers[0].knockout_lap, 1)
	assert_string_contains(_main.hud.caption_text(), "ELIMINATED AFTER LAP 1!")
	assert_string_contains(_main.knockout_text(), "9 LEFT", "the player out: nine left")
	assert_false(_main.knockout_text().contains("YOU ARE IN THE DROP ZONE"), "no longer in danger once out")
