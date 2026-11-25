extends GutTest
## Career core (2026-11-22): stage order and unlocking, championship progress
## saved between rounds and restored exactly, the quit-mid-race rule (the
## attempt is forfeited at the next start), rewards decided once, records from
## real results only, NEW CAREER keeping the lifetime titles, broken or missing
## saves, and the atomic save's fallback.

const P := RaceSession.PLAYER_ID

var _path := ""


func before_each() -> void:
	_path = "user://test_run/career_%d.cfg" % randi()


func after_each() -> void:
	SafeSave.remove(_path)


## A round's order: `first` wins, then the others in id order.
func _order(first: int) -> Array:
	var o := [first]
	for id in range(0, 10):
		if id != first:
			o.append(id)
	return o


func _win_stage(c: Career, stage: int) -> Dictionary:
	assert_true(c.start_stage(stage), "stage %d can start" % stage)
	var out := {}
	for i in Career.schedule(stage).round_count():
		out = c.record_round(_order(P), [])
	return out


func test_stages_unlock_in_order_and_the_last_completes_the_career() -> void:
	var c := Career.new(_path)
	assert_true(c.unlocked(0))
	assert_false(c.unlocked(1), "Pro Series locked at first")
	assert_false(c.start_stage(2), "the Grand Championship cannot be entered yet")
	assert_eq(Career.schedule(0).round_count(), 3, "Rookie Cup: three rounds")
	assert_eq(Career.schedule(1).round_count(), 6, "Pro Series: six rounds")
	assert_eq(Career.schedule(2).round_count(), 6)
	assert_true(Career.schedule(2).get_round(5).final, "the Grand Championship ends with the Grand Final")
	assert_eq(int(Career.schedule(2).get_round(5).laps), 7, "a seven-lap final")
	assert_false(Career.schedule(0).get_round(2).final, "the Rookie Cup has no grand final")
	var r := _win_stage(c, 0)
	assert_true(r.won and r.finished)
	assert_eq(r.bonus, Career.schedule(0).career_bonus)
	assert_false(r.completed_now)
	assert_true(c.unlocked(1), "Rookie Cup won: Pro Series open")
	assert_eq(c.current_stage(), 1)
	_win_stage(c, 1)
	r = _win_stage(c, 2)
	assert_true(r.completed_now, "the Grand Championship completes the career")
	assert_true(c.completed)
	assert_ne(c.completed_on, "")
	assert_eq(c.careers_completed, 1)
	assert_eq(c.final_standings[0], P)
	assert_eq(c.current_stage(), Career.FINAL_STAGE)


func test_every_circuit_environment_and_night_in_the_career() -> void:
	var layouts := {}
	var variants := {}
	var nights := {}
	for stage in 3:
		var s := Career.schedule(stage)
		for i in s.round_count():
			var r := s.get_round(i)
			layouts[r.layout] = true
			variants[r.variant] = true
			nights[r.night] = true
			assert_true(DevLayouts.PLAYER_LAYOUTS.has(r.layout), "a player circuit: %s" % r.layout)
	assert_eq(layouts.size(), 3, "all three circuits")
	assert_eq(variants.size(), 5, "all five environments")
	assert_eq(nights.size(), 2, "day and night")
	var rookie := Career.schedule(0)
	assert_eq(rookie.get_round(0).layout, "kestrel_ridge")
	assert_eq(rookie.nights.count(true), 0, "the Rookie Cup is raced in daylight")


func test_losing_a_stage_keeps_progress_and_allows_a_retry() -> void:
	var c := Career.new(_path)
	_win_stage(c, 0)
	assert_true(c.start_stage(1))
	var r := {}
	for i in 6:
		r = c.record_round(_order(2), [])  # Rocco wins every round
	assert_true(r.finished)
	assert_false(r.won)
	assert_eq(r.champion, 2)
	assert_eq(r.bonus, 0, "no bonus for losing")
	assert_false(c.unlocked(2), "the Grand Championship stays locked")
	assert_eq(c.rival_titles.get(2, 0), 1, "Rocco's title is on record")
	assert_eq(c.rival_wins.get(2, 0), 6)
	assert_eq(c.top_rival(), 2)
	assert_true(c.start_stage(1), "try the Pro Series again")
	assert_eq(c.attempts[1], 2)
	assert_eq(c.champ.round_index(), 0, "from round 1")


func test_rounds_are_saved_and_restored_exactly() -> void:
	var c := Career.new(_path)
	c.start_stage(0, 4)
	c.record_round(_order(3), [5])
	c.begin_race()
	c.in_race = false  # (the next race has not started yet)
	c.save()
	var back := Career.new(_path)
	back.load_from_disk()
	assert_true(back.started)
	assert_true(back.in_championship())
	assert_eq(back.active_stage, 0)
	assert_eq(back.player_car, 4, "the car entered with")
	assert_eq(back.champ.round_index(), 1)
	assert_eq(back.champ.points, c.champ.points, "same points")
	assert_eq(back.champ.standings(), c.champ.standings(), "same standings")
	assert_eq(back.champ.next_grid(), c.champ.next_grid(), "same next grid (reversed result)")
	assert_eq(back.champ.position_in(0, 5), 0, "the DNF is kept")
	assert_eq(back.forfeited_on_load, -1, "a normal exit between rounds costs nothing")


func test_closing_the_game_during_a_career_race_forfeits_the_attempt() -> void:
	var c := Career.new(_path)
	c.start_stage(0)
	c.record_round(_order(P), [])
	c.begin_race()  # round 2 under way... and the game closes
	var back := Career.new(_path)
	back.load_from_disk()
	assert_eq(back.forfeited_on_load, 0, "the Rookie Cup attempt is forfeited")
	assert_false(back.in_championship(), "no championship to resume: no quit-and-retry")
	assert_true(back.unlocked(0), "the stage can simply be entered again")
	assert_eq(back.races, 1, "the finished round stays on record")
	var again := Career.new(_path)
	again.load_from_disk()
	assert_eq(again.forfeited_on_load, -1, "forfeited once, not at every start")


func test_rewards_are_decided_once() -> void:
	var c := Career.new(_path)
	var r := _win_stage(c, 0)
	assert_eq(r.bonus, 500)
	var late := c.record_round(_order(P), [])
	assert_false(late.recorded, "a decided championship records nothing more")
	assert_eq(late.bonus, 0)
	assert_eq(c.titles[0], 1)
	c.close_championship()
	var back := Career.new(_path)
	back.load_from_disk()
	assert_false(back.in_championship(), "a decided championship is not resumed")
	assert_eq(back.titles[0], 1)
	assert_true(back.stage_won[0])


func test_records_come_from_real_results() -> void:
	var c := Career.new(_path)
	c.start_stage(0)
	c.record_round(_order(P), [])        # win
	c.record_round(_order(7), [P])       # DNF
	c.record_round([1, P, 2, 3, 4, 5, 6, 7, 8, 9], [])  # second: a podium
	assert_eq(c.races, 3)
	assert_eq(c.race_wins, 1)
	assert_eq(c.podiums, 2)
	assert_eq(c.dnfs, 1)
	assert_eq(c.rival_wins, {7: 1, 1: 1})
	assert_false(c.completed)
	assert_eq(c.final_standings, [] as Array[int], "no invented final")


func test_new_career_keeps_lifetime_titles() -> void:
	var c := Career.new(_path)
	for s in 3:
		_win_stage(c, s)
	assert_true(c.completed)
	var date := c.completed_on
	c.reset()
	assert_false(c.started)
	assert_false(c.completed, "the new career starts from the Rookie Cup")
	assert_false(c.unlocked(1))
	assert_eq(c.races, 0)
	assert_eq(c.careers_completed, 1, "the lifetime record stays")
	assert_eq(c.first_completed_on, date)
	var back := Career.new(_path)
	back.load_from_disk()
	assert_eq(back.careers_completed, 1)
	assert_false(back.completed)


func test_replaying_after_completion_keeps_the_career_complete() -> void:
	var c := Career.new(_path)
	for s in 3:
		_win_stage(c, s)
	assert_true(c.start_stage(0), "replay the Rookie Cup")
	for i in 3:
		c.record_round(_order(1), [])
	assert_true(c.completed, "losing a replay never undoes the career")
	var r := _win_stage(c, 2)
	assert_true(r.won)
	assert_false(r.completed_now, "completed once")
	assert_eq(c.careers_completed, 1)
	assert_eq(c.titles[2], 2)


func test_missing_and_broken_saves_load_as_a_fresh_career() -> void:
	var none := Career.new("user://test_run/never_%d.cfg" % randi())
	none.load_from_disk()
	assert_false(none.started)
	var cfg := ConfigFile.new()
	cfg.set_value("career", "started", true)
	cfg.set_value("career", "stage_won", [true, "x"])
	cfg.set_value("career", "active_stage", 2)  # not unlocked: ignored
	cfg.set_value("championship", "orders", [[0, 0, 0]])
	cfg.set_value("records", "rival_wins", {42: 3, 4: -2, 5: 1})
	cfg.save(_path)
	var odd := Career.new(_path)
	odd.load_from_disk()
	assert_true(odd.started)
	assert_eq(odd.stage_won, [true, false, false] as Array[bool])
	assert_false(odd.in_championship(), "a locked or broken championship is dropped")
	assert_eq(odd.rival_wins, {4: 0, 5: 1}, "only real rivals, never negative")
	# a broken running championship for an unlocked stage is dropped too
	cfg.set_value("career", "active_stage", 1)
	cfg.set_value("championship", "orders", [[0, 1, 2, 3, 4, 5, 6, 7, 8, 8]])
	cfg.set_value("championship", "dnfs", [[]])
	cfg.save(_path)
	odd.load_from_disk()
	assert_false(odd.in_championship())


func test_atomic_save_survives_an_interrupted_write() -> void:
	var c := Career.new(_path)
	c.start_stage(0)
	c.record_round(_order(P), [])
	assert_false(FileAccess.file_exists(_path + ".tmp"), "no leftover temporary file")
	# a crash between writing the new file and renaming it: only the .tmp exists
	DirAccess.rename_absolute(ProjectSettings.globalize_path(_path), ProjectSettings.globalize_path(_path + ".tmp"))
	var back := Career.new(_path)
	back.load_from_disk()
	assert_true(back.in_championship(), "recovered from the temporary file")
	assert_eq(back.races, 1)
