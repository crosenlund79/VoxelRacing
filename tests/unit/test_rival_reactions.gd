extends GutTest
## Rival reactions (2026-11-23): only real facts of the round speak, at most
## one rival, the most significant fact first, nobody twice in a row, an
## ordinary round says nothing, and every line is complete for every rival.

const P := RaceSession.PLAYER_ID
var R = RivalReactions


func _facts(order: Array, extra: Dictionary = {}) -> Dictionary:
	var f := {"order": order, "dnf": [], "times": {}, "feed": [], "before": {}, "after": {}, "history": [],
		"final": false, "champion": -1, "me": P}
	f.merge(extra, true)
	return f


func _points(lead: int, second: int, a: int, b: int) -> Dictionary:
	var p := {}
	for id in range(0, 10):
		p[id] = 0
	p[lead] = a
	p[second] = b
	return p


func test_an_ordinary_round_says_nothing() -> void:
	var f := _facts([3, 5, P, 1, 2, 4, 6, 7, 8, 9], {"times": {3: 100.0, 5: 103.0, P: 104.0}})
	assert_eq(R.pick(f), {}, "no close finish, no lead change, no grudge: silence")


func test_a_close_finish_names_the_right_rival() -> void:
	var f := _facts([2, P, 1, 3, 4, 5, 6, 7, 8, 9], {"times": {2: 100.0, P: 100.31}})
	var r := R.pick(f)
	assert_eq([r.rival, r.kind], [2, R.BEAT_CLOSE])
	assert_string_contains(r.text, "0.31")
	f = _facts([P, 9, 1, 2, 3, 4, 5, 6, 7, 8], {"times": {P: 100.0, 9: 100.2}})
	assert_eq([R.pick(f).rival, R.pick(f).kind], [9, R.LOST_CLOSE])


func test_destructions_count_only_weapon_kills_between_player_and_rival() -> void:
	var feed := [
		{"attacker": 4, "victim": P, "weapon": 0, "tombstone": false},
		{"attacker": 4, "victim": P, "weapon": 4, "tombstone": false},
		{"attacker": 5, "victim": P, "weapon": CombatStats.COLLISION, "tombstone": true},  # a collision retirement: not a weapon kill
		{"attacker": 4, "victim": 6, "weapon": 0, "tombstone": false},  # rival vs rival: not the player's story
	]
	var r := R.pick(_facts([1, 2, 3, P, 4, 5, 6, 7, 8, 9], {"feed": feed}))
	assert_eq([r.rival, r.kind], [4, R.DESTROYED_YOU])
	assert_string_contains(r.text, "2")


func test_lead_changes_and_titles_outrank_everything() -> void:
	var before := _points(P, 2, 40, 35)
	var after := _points(2, P, 60, 52)
	var f := _facts([2, 5, P, 1, 3, 4, 6, 7, 8, 9], {"before": before, "after": after, "times": {2: 100.0, 5: 100.1}})
	assert_eq([R.pick(f).rival, R.pick(f).kind], [2, R.TOOK_LEAD], "Rocco took the lead")
	var won := _facts([P, 3, 1, 2, 4, 5, 6, 7, 8, 9], {"before": before, "after": _points(P, 7, 90, 80), "final": true, "champion": P})
	assert_eq([R.pick(won).rival, R.pick(won).kind], [7, R.TITLE_LOST], "the runner-up reacts to the player's title")
	var lost := _facts([1, P, 2, 3, 4, 5, 6, 7, 8, 9], {"after": _points(9, P, 90, 80), "final": true, "champion": 9})
	assert_eq([R.pick(lost).rival, R.pick(lost).kind], [9, R.TITLE_WON])


func test_surprises_and_patterns_need_real_history() -> void:
	var f := _facts([6, 1, P, 2, 3, 4, 5, 7, 8, 9], {"history": [[1, 2, 3, 4, 5, P, 7, 8, 9, 6]]})
	assert_eq([R.pick(f).rival, R.pick(f).kind], [6, R.COMEBACK], "Dante from last to first")
	var slump := _facts([1, 2, 3, 4, 5, P, 7, 8, 3, 9].slice(0, 0) + [1, 2, 3, 4, 5, P, 7, 8, 9, 6],
		{"history": [[9, 1, 2, 3, 4, 5, P, 6, 7, 8]]})
	assert_eq([R.pick(slump).rival, R.pick(slump).kind], [9, R.SLUMP], "last round's winner fell to 9th")
	var hist := [[P, 3, 1, 2, 4, 5, 6, 7, 8, 9], [1, P, 3, 2, 4, 5, 6, 7, 8, 9]]
	var behind := _facts([2, P, 3, 1, 4, 5, 6, 7, 8, 9], {"history": hist, "after": _points(P, 3, 50, 30)})
	var r := R.pick(behind)
	assert_eq([r.rival, r.kind], [3, R.ALWAYS_BEHIND], "Ellie behind the player in all three rounds")
	assert_string_contains(r.text, "3")


func test_nobody_reacts_twice_in_a_row() -> void:
	var f := _facts([2, P, 1, 3, 4, 5, 6, 7, 8, 9], {"times": {2: 100.0, P: 100.3}})
	assert_eq(R.pick(f, 2), {}, "Rocco spoke last time and nothing else happened: silence")


func test_every_rival_has_every_line_filled_in() -> void:
	for kind in R.KINDS:
		for rival in range(1, 10):
			var t: String = R._make(kind, rival, {"gap": "0.42", "n": "3"}).text
			assert_ne(t, "", "%s / %d" % [kind, rival])
			assert_false(t.contains("{"), "%s / %d: %s" % [kind, rival, t])
			assert_lt(t.length(), 90, "short: %s" % t)
