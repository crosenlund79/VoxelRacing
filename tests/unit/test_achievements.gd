extends GutTest
## M3.5 Stage 4: the achievement catalogue, persistence (unlock once, survive a
## restart, confirmed reset) and every unlock rule evaluated from race
## summaries, plus the rivals' career statistics (Living Legends).

const PATH := "user://test_achievements_unit.cfg"
const W := WeaponRules.Weapon
const ROCCO := 2

var _store: AchievementStore


func before_each() -> void:
	_store = AchievementStore.new(PATH)


func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


## A summary of a 10-car race (player = 0) in finishing order `order`, grid reversed.
func _race(order: Array, extra := {}) -> Dictionary:
	var grid := order.duplicate()
	grid.reverse()
	var times := {}
	for i in order.size():
		times[order[i]] = 60.0 + i * 1.0
	var s := {"spectator": false, "control_mode": CarModel.ControlMode.FIRE_TO_ACCELERATE, "weapons": false, "laps": 3,
		"grid": grid, "order": order, "finish_time": times, "lap_times": {}, "walls": {0: 1}, "contacts": {0: 2},
		"lead_changes": 0, "kills": {}, "kill_types": {}, "player_shots": 0, "player_destroyed": 0, "player_empty": 0,
		"own_mine": false, "mine_multi": 0, "defends": {}, "flusters": {}}
	s.merge(extra, true)
	return s


func _spectate(order: Array, extra := {}) -> Dictionary:
	var s := _race(order, extra)
	s.spectator = true
	return s


func _ids(s: Dictionary) -> Array[String]:
	return AchievementTracker.evaluate(s, _store)


const MID := [3, 4, 5, 6, 7, 8, 9, 1, 2, 0]  # player last, nobody special first


func test_catalogue_has_thirty_unique_achievements() -> void:
	var ids := AchievementCatalog.ids()
	assert_eq(ids.size(), 30)
	var seen := {}
	for id in ids:
		assert_false(seen.has(id), id)
		seen[id] = true
	assert_true(seen.has("eternal_contender"))
	assert_true(seen.has("curse_is_broken"))
	var hidden := AchievementCatalog.ENTRIES.filter(func(e: Dictionary) -> bool: return e.hidden).size()
	assert_eq(hidden, 6)


func test_unlock_once_and_persist() -> void:
	watch_signals(_store)
	assert_true(_store.unlock("first_flag"))
	assert_false(_store.unlock("first_flag"), "only once")
	assert_false(_store.unlock("no_such_thing"))
	assert_signal_emit_count(_store, "unlocked", 1)
	_store.set_progress("spectator_races", 4)
	_store.rivals[ROCCO].wins = 3
	_store.save()
	var again := AchievementStore.new(PATH)
	again.load_store()
	assert_true(again.is_unlocked("first_flag"))
	assert_eq(again.get_progress("spectator_races"), 4)
	assert_eq(again.rivals[ROCCO].wins, 3)
	assert_eq(again.rivals[ROCCO].positions.size(), 10)


func test_reset_erases_everything() -> void:
	_store.unlock("first_flag")
	_store.set_progress("spectator_races", 9)
	_store.rivals[1].races = 5
	_store.save()
	_store.reset()
	var again := AchievementStore.new(PATH)
	again.load_store()
	assert_eq(again.unlocked_count(), 0)
	assert_eq(again.get_progress("spectator_races"), 0)
	assert_eq(again.rivals[1].races, 0)


func test_player_win_from_the_back_with_rocco_second() -> void:
	var ids := _ids(_race([0, 2, 1, 3, 4, 5, 6, 7, 8, 9], {"grid": [1, 3, 4, 5, 6, 7, 8, 9, 2, 0]}))
	for id in ["first_flag", "back_row_hero", "so_close_mad_dog"]:
		assert_has(ids, id)
	assert_does_not_have(ids, "upside_down_grid", "first win")
	assert_does_not_have(ids, "pacifist", "no weapons")
	ids = _ids(_race([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]))
	assert_has(ids, "upside_down_grid")
	_ids(_race(MID))
	assert_eq(_store.get_progress("player_win_streak"), 0)


func test_both_control_modes() -> void:
	assert_does_not_have(_ids(_race([0, 1, 2, 3, 4, 5, 6, 7, 8, 9])), "both_hands")
	assert_has(_ids(_race([0, 1, 2, 3, 4, 5, 6, 7, 8, 9], {"control_mode": CarModel.ControlMode.FIRE_TO_BRAKE})), "both_hands")


func test_clean_photo_finish() -> void:
	var order := [1, 0, 2, 3, 4, 5, 6, 7, 8, 9]
	var ids := _ids(_race(order, {"walls": {}, "contacts": {}, "finish_time": {1: 60.0, 0: 60.08, 2: 61.0}}))
	assert_has(ids, "not_a_scratch")
	assert_has(ids, "photo_finish")
	ids = _ids(_race(order, {"finish_time": {1: 60.0, 0: 60.3, 2: 61.0}}))
	assert_does_not_have(ids, "not_a_scratch", "touched a car")
	assert_does_not_have(ids, "photo_finish")


func test_combat_achievements() -> void:
	var ids := _ids(_race([0, 1, 2, 3, 4, 5, 6, 7, 8, 9], {"weapons": true, "player_destroyed": 2,
		"kill_types": {0: {W.FRONT_MISSILE: 1, W.MINE: 2}}, "mine_multi": 2, "own_mine": true, "player_empty": 5, "player_shots": 4}))
	for id in ["phoenix", "opening_salvo", "rear_view_diplomacy", "two_for_one", "own_goal", "click_click"]:
		assert_has(ids, id)
	assert_does_not_have(ids, "pacifist", "fired shots")
	assert_has(_ids(_race([0, 1, 2, 3, 4, 5, 6, 7, 8, 9], {"weapons": true})), "pacifist")
	var none := _ids(_race(MID, {"weapons": true, "player_empty": 4, "mine_multi": 1, "kill_types": {1: {W.MINE: 3}}}))
	for id in ["click_click", "two_for_one", "rear_view_diplomacy", "opening_salvo"]:
		assert_does_not_have(none, id)


func test_endurance() -> void:
	var ids := _ids(_race(MID, {"laps": 50, "weapons": true}))
	assert_has(ids, "marathon")
	assert_has(ids, "iron_will")
	assert_does_not_have(_ids(_race(MID, {"laps": 20, "weapons": true, "player_destroyed": 1})), "iron_will")
	assert_does_not_have(_ids(_race(MID, {"laps": 20, "weapons": false})), "iron_will")
	var podium := [1, 2, 0, 3, 4, 5, 6, 7, 8, 9]
	for laps in [3, 7, 20]:
		assert_does_not_have(_ids(_race(podium, {"laps": laps})), "all_distances")
	assert_has(_ids(_race(podium, {"laps": 50})), "all_distances")


func test_rocco_streaks_and_his_day() -> void:
	var second := [1, 2, 3, 4, 5, 6, 7, 8, 9]
	assert_does_not_have(_ids(_spectate(second)), "always_bridesmaid")
	assert_does_not_have(_ids(_race([1, 2, 0, 3, 4, 5, 6, 7, 8, 9])), "always_bridesmaid")
	assert_has(_ids(_spectate(second)), "always_bridesmaid", "three in a row, racing or watching")
	_store = AchievementStore.new(PATH)
	_ids(_spectate(second))
	_ids(_spectate(second))
	_ids(_spectate([2, 1, 3, 4, 5, 6, 7, 8, 9]))
	assert_does_not_have(_ids(_spectate(second)), "always_bridesmaid", "streak broken")
	assert_has(_ids(_spectate([2, 1, 3, 4, 5, 6, 7, 8, 9])), "dog_has_its_day")


func test_rival_personality_feats() -> void:
	assert_has(_ids(_spectate([5, 1, 2, 3, 4, 6, 7, 8, 9], {"contacts": {}})), "ghost_line")
	assert_does_not_have(_ids(_spectate([5, 1, 2, 3, 4, 6, 7, 8, 9], {"contacts": {5: 1}})), "ghost_line")
	assert_has(_ids(_spectate([1, 2, 4, 3, 5, 6, 7, 8, 9], {"defends": {4: 20}})), "the_wall_holds")
	assert_does_not_have(_ids(_spectate([1, 2, 3, 5, 4, 6, 7, 8, 9], {"defends": {4: 40}})), "the_wall_holds", "not on the podium")
	assert_has(_ids(_spectate([8, 1, 2, 3, 4, 5, 6, 7, 9], {"grid": [1, 2, 3, 4, 5, 6, 7, 9, 8]})), "wildcard_played")
	assert_has(_ids(_spectate([9, 1, 2, 3, 4, 5, 6, 7, 8], {"grid": [1, 2, 3, 4, 5, 9, 6, 7, 8]})), "the_hunt")
	assert_does_not_have(_ids(_spectate([9, 1, 2, 3, 4, 5, 6, 7, 8], {"grid": [1, 2, 3, 4, 9, 5, 6, 7, 8]})), "the_hunt", "only four places")
	assert_has(_ids(_spectate([3, 1, 2, 4, 5, 6, 7, 8, 9], {"flusters": {3: 3}})), "sparrow_under_fire")
	assert_has(_ids(_spectate([1, 2, 3, 4, 5, 6, 7, 8, 9], {"kills": {6: 3}})), "showtime")
	assert_has(_ids(_spectate([1, 2, 3, 4, 5, 6, 7, 8, 9], {"lead_changes": 12})), "lead_carousel")


func test_like_clockwork() -> void:
	var steady := {7: [14.2, 12.50, 12.55, 12.62, 12.48, 12.58, 12.51]}
	var order := [1, 2, 3, 4, 5, 6, 7, 8, 9]
	assert_has(_ids(_spectate(order, {"laps": 7, "lap_times": steady})), "like_clockwork")
	assert_does_not_have(_ids(_spectate(order, {"laps": 3, "lap_times": steady})), "like_clockwork", "short race")
	assert_does_not_have(_ids(_spectate(order, {"laps": 7, "weapons": true, "lap_times": steady})), "like_clockwork", "guns")
	var ragged := {7: [14.2, 12.50, 12.80, 12.62, 12.48, 12.58, 12.51]}
	assert_does_not_have(_ids(_spectate(order, {"laps": 7, "lap_times": ragged})), "like_clockwork")


func test_spectator_races_count_but_never_give_player_achievements() -> void:
	var ids: Array[String] = []
	for i in 10:
		ids = _ids(_spectate([1, 2, 3, 4, 5, 6, 7, 8, 9], {"weapons": true, "laps": 50}))
		assert_does_not_have(ids, "first_flag")
		assert_does_not_have(ids, "marathon")
	assert_has(ids, "armchair_expert")
	assert_eq(_store.get_progress("spectator_races"), 10)
	assert_does_not_have(_ids(_race([0, 1, 2, 3, 4, 5, 6, 7, 8, 9])), "armchair_expert", "racing does not count as watching")


func test_rival_careers() -> void:
	_ids(_spectate([1, 2, 3, 4, 5, 6, 7, 8, 9]))
	_ids(_race([2, 0, 1, 3, 4, 5, 6, 7, 8, 9]))
	var victor: Dictionary = _store.rivals[1]
	assert_eq(victor.races, 2)
	assert_eq(victor.wins, 1)
	assert_eq(victor.podiums, 2)
	assert_eq(victor.positions.slice(0, 3), [1, 0, 1])
	assert_eq(victor.winless_streak, 1)
	var rocco: Dictionary = _store.rivals[ROCCO]
	assert_eq(rocco.wins, 1)
	assert_eq(rocco.winless_streak, 0)
	assert_eq(_store.rivals[9].positions[9], 1, "10th in the 10-car race")


func test_eternal_contender_needs_25_podiums_without_a_win() -> void:
	var third := [1, 3, 4, 5, 6, 7, 8, 9, 2]
	var podium := [1, 3, 2, 4, 5, 6, 7, 8, 9]
	for i in 24:
		assert_does_not_have(_ids(_spectate(podium)), "eternal_contender")
	_ids(_spectate(third))
	assert_has(_ids(_spectate(podium)), "eternal_contender", "25th podium without a win")
	_store = AchievementStore.new(PATH)
	for i in 20:
		_ids(_spectate(podium))
	_ids(_spectate([2, 1, 3, 4, 5, 6, 7, 8, 9]))
	for i in 10:
		# Ellie wins these (resetting her own count); Rocco stays third.
		assert_does_not_have(_ids(_spectate([3, 1, 2, 4, 5, 6, 7, 8, 9])), "eternal_contender", "a win resets the count")
	assert_eq(_store.rivals[ROCCO].podiums_since_win, 10)


func test_curse_is_broken_after_fifty_winless_races() -> void:
	var lose := [1, 3, 4, 5, 6, 7, 8, 9, 2]
	for i in 49:
		_ids(_spectate(lose))
	assert_does_not_have(_ids(_spectate([2, 1, 3, 4, 5, 6, 7, 8, 9])), "curse_is_broken", "49 is not enough")
	for i in 50:
		_ids(_spectate(lose))
	assert_eq(_store.rivals[ROCCO].winless_streak, 50)
	assert_has(_ids(_spectate([2, 1, 3, 4, 5, 6, 7, 8, 9])), "curse_is_broken")
	assert_eq(_store.rivals[ROCCO].longest_winless, 50)
