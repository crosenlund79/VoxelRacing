extends GutTest
## Nemesis Welcome, pure parts: only real events are remembered (from the race's
## own statistics and finishing times), with the right rival, weapon and lap;
## the memory is bounded and survives saving; old or broken saves load as an
## empty memory; greetings are occasional, never two launches running, never
## the same event again soon, and favour memorable recent events; every taunt
## fills in from the facts only.

const W := WeaponRules.Weapon
const P := RaceSession.PLAYER_ID

var _path := ""


func before_each() -> void:
	_path = "user://test_run/rival_memory_%d.cfg" % randi()


func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))


func _ctx() -> Dictionary:
	return {"circuit": "Kestrel Ridge", "laps": 20, "mode": "quick"}


func test_dnfs_are_remembered_with_rival_weapon_and_lap() -> void:
	var m := RivalMemory.new(_path)
	var feed := [
		{"attacker": 4, "victim": P, "weapon": W.REAR_MISSILE, "tombstone": true, "time": 600.0},  # Hank took the player out
		{"attacker": P, "victim": 2, "weapon": W.FRONT_MISSILE, "tombstone": true, "time": 300.0},  # the player took Rocco out
		{"attacker": 3, "victim": P, "weapon": W.MINE, "tombstone": false, "time": 100.0},  # destroyed, respawned: not a DNF
		{"attacker": 5, "victim": 6, "weapon": W.MINE, "tombstone": true, "time": 200.0},  # rival vs rival: not the player's story
		{"attacker": -1, "victim": 7, "weapon": CombatStats.RETIRED, "tombstone": true, "time": 250.0},  # worn out: nobody's doing
	]
	var added := m.record_race(feed, [], {P: 18, 2: 9}, P, _ctx())
	assert_eq(added.size(), 2, "only the player's own DNF stories")
	var hank: Dictionary = m.events[0]
	assert_eq([hank.kind, hank.rival, hank.weapon, hank.lap, hank.circuit, hank.laps],
		[RivalMemory.TOOK_YOU_OUT, 4, W.REAR_MISSILE, 19, "Kestrel Ridge", 20], "Hank, rear rockets, lap 19 of 20")
	var rocco: Dictionary = m.events[1]
	assert_eq([rocco.kind, rocco.rival, rocco.weapon, rocco.lap], [RivalMemory.YOU_TOOK_ME_OUT, 2, W.FRONT_MISSILE, 10])
	assert_false(hank.has("test"), "real events are never marked as test data")


func test_only_a_close_first_and_second_counts_as_a_memorable_finish() -> void:
	var m := RivalMemory.new(_path)
	m.record_race([], [[9, 512.3, true, false], [P, 512.7, true, false], [1, 520.0, true, false]], {}, P, _ctx())
	assert_eq(m.events.size(), 1)
	assert_eq([m.events[0].kind, m.events[0].rival, m.events[0].gap], [RivalMemory.BEAT_YOU_CLOSE, 9, 0.4])
	m.record_race([], [[P, 400.0, true, false], [6, 400.8, true, false]], {}, P, _ctx())
	assert_eq([m.events[1].kind, m.events[1].rival], [RivalMemory.YOU_BEAT_ME_CLOSE, 6])
	var n := RivalMemory.new(_path)
	n.record_race([], [[9, 500.0, true, false], [P, 501.5, true, false]], {}, P, _ctx())
	n.record_race([], [[9, 500.0, true, false], [2, 500.2, true, false], [P, 500.4, true, false]], {}, P, _ctx())
	n.record_race([], [[P, 500.0, true, false], [3, -1.0, false, true]], {}, P, _ctx())
	assert_eq(n.events.size(), 0, "1.5 s, third place, or a DNF second: nothing to tease about")


func test_bounded_saved_and_tolerant_of_old_or_broken_saves() -> void:
	var m := RivalMemory.new(_path)
	for i in RivalMemory.MAX_EVENTS + 10:
		m.add(RivalMemory.TOOK_YOU_OUT, 1 + i % 9, {"weapon": W.MINE, "lap": i})
	assert_eq(m.events.size(), RivalMemory.MAX_EVENTS, "bounded")
	assert_eq(int(m.events[0].lap), 10, "the oldest went first")
	assert_eq(m.save(), OK)
	var back := RivalMemory.new(_path)
	back.load_from_disk()
	assert_eq(back.events.size(), RivalMemory.MAX_EVENTS)
	assert_eq(back.events[-1].lap, m.events[-1].lap)
	# no file at all (every save from before this feature): an empty memory
	var none := RivalMemory.new("user://test_run/never_written_%d.cfg" % randi())
	none.load_from_disk()
	assert_eq(none.events.size(), 0)
	assert_eq(none.pick_greeting(RandomNumberGenerator.new()), {}, "nothing remembered: nothing to say")
	# broken / foreign entries are dropped, never turned into greetings
	var cfg := ConfigFile.new()
	cfg.set_value("memory", "events", [{"kind": "made_up", "rival": 3}, {"kind": RivalMemory.TOOK_YOU_OUT, "rival": 42}, "junk",
		{"id": 7, "kind": RivalMemory.WON_MY_CAR, "rival": 5}])
	cfg.save(_path)
	var odd := RivalMemory.new(_path)
	odd.load_from_disk()
	assert_eq(odd.events.size(), 1, "only the valid event")
	assert_eq(odd.add(RivalMemory.TOOK_CAR_BACK, 5).id, 8, "ids continue after the saved ones")
	assert_eq(m.add("invented", 1), {}, "unknown kinds are refused")
	assert_eq(m.add(RivalMemory.TOOK_YOU_OUT, 0), {}, "the player is no rival")


func test_greetings_are_occasional_and_never_two_launches_running() -> void:
	var m := RivalMemory.new(_path)
	for k in RivalMemory.KINDS:
		m.add(k, 4)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1991
	var greets := 0
	var last := false
	for launch in 1000:
		var g := m.pick_greeting(rng)
		var now := not g.is_empty()
		assert_false(now and last, "never on two launches in a row")
		last = now
		greets += int(now)
	assert_between(greets, 150, 330, "occasional: about one launch in four (%d of 1000)" % greets)


func test_greetings_avoid_repeats_and_favour_memorable_recent_events() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var counts := {}
	var recent: Array = []
	var m := RivalMemory.new(_path)
	for i in 6:
		m.add(RivalMemory.BEAT_YOU_CLOSE, 1 + i, {"gap": 0.5})
	m.add(RivalMemory.TOOK_YOU_OUT, 4, {"weapon": W.REAR_MISSILE, "lap": 19})  # newest and memorable
	for launch in 3000:
		m.greeted_last_launch = false  # (every launch eligible, for the statistics)
		var g := m.pick_greeting(rng)
		if g.is_empty():
			continue
		assert_false(recent.has(g.id), "not one of the last %d greetings" % RivalMemory.NO_REPEAT)
		recent.append(g.id)
		if recent.size() > RivalMemory.NO_REPEAT:
			recent.pop_front()
		counts[g.id] = counts.get(g.id, 0) + 1
	var newest: int = m.events[-1].id
	var oldest: int = m.events[0].id
	assert_gt(counts.get(newest, 0), counts.get(oldest, 0) * 2, "recent and memorable comes up more often")
	assert_eq(counts.size(), 7, "but everything real gets its turn")


func test_taunts_fill_in_the_facts() -> void:
	var rng := RandomNumberGenerator.new()
	var hank := {"kind": RivalMemory.TOOK_YOU_OUT, "rival": 4, "weapon": W.REAR_MISSILE, "lap": 19, "circuit": "Kestrel Ridge"}
	assert_eq(NemesisLines.taunt(hank), "Still remember those rear rockets?", "the playtest moment")
	var g := NemesisLines.greeting(hank, rng)
	assert_eq(g.title, "HANK - THE WALL")
	assert_true(NemesisLines.OPENERS_SMUG.has(g.opener), "a smug opener for a smug memory")
	assert_eq(g.reaction, "(a deep, satisfied laugh)")
	assert_eq(g.clip, "", "no recording of Hank yet: text only")
	var rocco := {"kind": RivalMemory.TOOK_YOU_OUT, "rival": 2, "weapon": W.MINE, "lap": 4, "circuit": "Ravenhook"}
	assert_eq(NemesisLines.taunt(rocco), "Lap 4, my mines, and BOOM! Still makes me laugh.")
	assert_eq(NemesisLines.greeting(rocco, rng).clip, "voice/rocco_laughing", "Rocco's own laugh")
	var sore := NemesisLines.greeting({"kind": RivalMemory.YOU_BEAT_ME_CLOSE, "rival": 2, "gap": 0.3, "circuit": "Larkspur Ring"}, rng)
	assert_true(NemesisLines.OPENERS_SORE.has(sore.opener))
	assert_eq(sore.clip, "", "no laughing when sore")
	# every rival, every kind, any weapon: complete sentences, no placeholders left
	for kind in RivalMemory.KINDS:
		for rival in range(1, 10):
			for weapon in [W.FRONT_MISSILE, W.REAR_MISSILE, W.HOMING_MISSILE, W.SUPER_MISSILE, W.MINE, CombatStats.COLLISION]:
				var t := NemesisLines.taunt({"kind": kind, "rival": rival, "weapon": weapon, "lap": 7, "circuit": "Ravenhook", "gap": 0.6})
				assert_false(t.contains("{") or t.contains("}"), "%s / %d: %s" % [kind, rival, t])
				assert_lt(t.length(), 80, "short: %s" % t)
