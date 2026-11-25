extends GutTest
## Championship rules (points, DNF, ties, grids, schedules) and the car
## collection (unlocks, persistence, no duplicates, completion).

const CUP := preload("res://src/championship/hypercars_cup.tres")
const PATH := "user://test_car_collection.cfg"


func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func _order(first: Array) -> Array:
	var out := first.duplicate()
	for id in range(0, 10):
		if not out.has(id):
			out.append(id)
	return out


func test_points_accumulate_by_position() -> void:
	var c := Championship.new(CUP)
	c.record(_order([3, 0, 5]), [])
	assert_eq(c.points[3], 25)
	assert_eq(c.points[0], 18)
	assert_eq(c.points[5], 15)
	c.record(_order([0, 3]), [])
	assert_eq(c.points[0], 43)
	assert_eq(c.points[3], 43)
	assert_eq(c.standings()[0], 0, "tied on points, one win and one second each: the last round decides")


func test_dnf_scores_nothing_and_ranks_last_in_round() -> void:
	var c := Championship.new(CUP)
	var order := _order([1, 2, 3, 4, 5, 6, 7, 8, 9, 0])
	c.record(order, [0])
	assert_eq(c.points[0], 0, "a DNF scores nothing even in a points position")
	assert_eq(c.position_in(0, 0), 0)
	c.record(_order([2, 1]), [9])
	assert_eq(c.points[9], 2, "the first round's 9th place only")


func test_countback_breaks_ties() -> void:
	var c := Championship.new(CUP)
	c.record(_order([7, 8]), [])                          # 7: 25, 8: 18
	c.record(_order([8, 9, 1, 2, 3, 4, 5, 6, 0, 7]), [7])  # 8: 43, 7 retired
	c.points[7] = 43  # force a points tie
	assert_eq(c.standings()[0], 8, "equal points and one win each: 8 also has a second place")
	var ids := c.standings()
	for k in ids.size() - 1:
		assert_true(c.points[ids[k]] >= c.points[ids[k + 1]], "sorted by points")


func test_grids_reverse_the_last_result() -> void:
	var c := Championship.new(CUP)
	assert_eq(c.next_grid(), [1, 2, 3, 4, 5, 6, 7, 8, 9, 0] as Array[int], "round 1: player last")
	var order := _order([5, 0, 2])
	c.record(order, [])
	var grid := c.next_grid()
	assert_eq(grid[-1], 5, "the winner starts last")
	assert_eq(grid[0], order[-1])


func test_finishes_after_the_last_round() -> void:
	for rounds in ChampionshipSchedule.LENGTHS:
		var sched := CUP.with_length(rounds)
		var c := Championship.new(sched)
		for k in rounds:
			assert_false(c.finished())
			assert_eq(c.next_round().layout, sched.layouts[k])
			c.record(_order([0]), [])
		assert_true(c.finished())
		assert_eq(c.champion(), 0)
		c.record(_order([1]), [])
		assert_eq(c.results.size(), rounds, "no extra round")


func test_schedules_rotate_and_cover_all_circuits() -> void:
	var a := ChampionshipSchedule.for_run(0)
	var b := ChampionshipSchedule.for_run(1)
	assert_ne(a.resource_path, b.resource_path, "the next championship races other combinations")
	assert_eq(ChampionshipSchedule.for_run(2).resource_path, a.resource_path)
	for s: ChampionshipSchedule in [a, b]:
		assert_eq(s.round_count(), 6, "a six-round season")
		var circuits := {}
		var environments := {}
		var nights := 0
		for i in 6:
			var r: Dictionary = s.get_round(i)
			circuits[r.layout] = true
			environments[r.variant] = true
			nights += 1 if r.night else 0
			assert_true(DevLayouts.PLAYER_LAYOUTS.has(r.layout))
			assert_true(r.variant >= 1 and r.variant <= TrackTheme.VARIANT_COUNT)
			assert_eq(r.final, i == 5, "only the last round is the final")
		assert_eq(circuits.size(), DevLayouts.PLAYER_LAYOUTS.size(), "every original circuit")
		assert_eq(environments.size(), TrackTheme.VARIANT_COUNT, "all five environments")
		assert_true(nights > 0 and nights < 6, "day and night rounds")
		assert_gt(s.get_round(5).laps, s.get_round(0).laps, "a longer final")
		# the three-round version: three distinct circuits, ending with the same final
		var short := s.with_length(3)
		assert_eq(short.round_count(), 3)
		var short_circuits := {}
		for i in 3:
			short_circuits[short.get_round(i).layout] = true
		assert_eq(short_circuits.size(), 3, "%s short: one round per circuit" % s.title)
		assert_eq(short.get_round(2), s.get_round(5), "the short version ends with the final")
		assert_eq(s.with_length(6), s)
		assert_string_contains(s.describe(), "FINAL 6:")


func test_collection_unlocks_each_rival_once_and_persists() -> void:
	var cars := CarCollection.new(PATH)
	cars.clear()
	var got := {}
	for k in 9:
		var id := cars.claim_lowest([0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
		assert_true(id >= 1 and id <= 9)
		assert_false(got.has(id), "never a duplicate")
		got[id] = true
	assert_true(cars.all_owned())
	assert_eq(cars.claim_lowest([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]), -1, "nothing left to win")
	var again := CarCollection.new(PATH)
	assert_eq(again.owned.size(), 9, "saved between sessions")
	assert_true(again.displaced(4))
	assert_eq(again.choices().size(), 10)
	assert_eq(again.choices()[0], CarCollection.OWN_CAR)


func test_collection_counts_championships() -> void:
	var cars := CarCollection.new(PATH)
	cars.clear()
	cars.count_championship()
	cars.count_championship()
	assert_eq(CarCollection.new(PATH).championships_run, 2)


func test_every_rival_has_taunts() -> void:
	for id in range(1, 10):
		assert_eq(RivalTaunts.count(id), 3)
		assert_ne(RivalTaunts.line(id, 0), RivalTaunts.line(id, 1))


## The reward is the car of the lowest-ranked rival in the final standings
## whose car is not owned yet (2026-11-23): deterministic, owned cars skipped.
func test_reward_is_the_lowest_ranked_unowned_rival() -> void:
	var cars := CarCollection.new(PATH)
	cars.clear()
	var standings := [0, 3, 7, 1, 9, 2, 5, 8, 4, 6]  # Dante (6) last of all
	assert_eq(cars.claim_lowest(standings), 6, "the last-placed rival's car")
	assert_eq(cars.claim_lowest(standings), 4, "next time: the next one up (6 owned)")
	cars.owned.append(8)
	assert_eq(cars.claim_lowest(standings), 5, "owned cars are skipped")
	assert_eq(cars.claim_lowest([1, 0, 2, 3, 4, 5, 6, 7, 8, 9]), 9, "the player's own place does not matter")
	var again := CarCollection.new(PATH)
	assert_true(again.owns(6) and again.owns(4) and again.owns(5) and again.owns(9), "saved")
	cars.clear()
	assert_eq(cars.claim_lowest([0, 1, 2, 3, 4, 5, 6, 7, 8]), 9, "a rival not in the standings counts as last")
	cars.clear()
