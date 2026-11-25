extends GutTest
## Voice Director building blocks: the recording registry and asset lookup,
## the weighted selector with its per-race memory, and confirmed overtakes.

const E := VoiceCatalog.Event
const INBOX := "res://assets/audio/_inbox/"

var _root := ""


func before_each() -> void:
	_root = OS.get_cache_dir().path_join("hypercars_voice_test")
	DirAccess.make_dir_recursive_absolute(_root.path_join("audio/voice"))


func after_each() -> void:
	for f in DirAccess.get_files_at(_root.path_join("audio/voice")):
		DirAccess.remove_absolute(_root.path_join("audio/voice").path_join(f))


func _params() -> VoiceParams:
	return (load("res://src/audio/default_voice_params.tres") as VoiceParams).duplicate()


func _rng(seed_value := 7) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


# --- registry and recordings ---

func test_every_supplied_recording_is_mapped_to_its_event_and_speaker() -> void:
	var expected := {
		"Announcer - Smoked you (on player killed).mp3": [E.PLAYER_DESTROYED, VoiceCatalog.ANNOUNCER],
		"Announcer - U playing bumper cars (sometimes when player hits the walls).mp3": [E.PLAYER_HIT_WALL, VoiceCatalog.ANNOUNCER],
		"Rocco - Laughing (if overtaken by Rocco).mp3": [E.RIVAL_OVERTOOK_PLAYER, 2],
		"the Hunter - Thank you (if overtaken by The Hunter).mp3": [E.RIVAL_OVERTOOK_PLAYER, 9],
		"The Professor - Clean (if overtaken by The Professor).mp3": [E.RIVAL_OVERTOOK_PLAYER, 1],
		"Announcer - Weapons Hot (When all drivers have passed the starting line - and weapons are unlocked).mp3": [E.WEAPONS_HOT, VoiceCatalog.ANNOUNCER],
		"Announcer - Pit lane violation (When a car speeds in the pit lane).mp3": [E.PIT_VIOLATION, VoiceCatalog.ANNOUNCER],
	}
	assert_eq(VoiceCatalog.LINES.size(), expected.size())
	var r := AssetResolver.new(_root)
	for line in VoiceCatalog.LINES:
		assert_true(expected.has(line.source), line.id)
		assert_eq([line.event, line.speaker], expected[line.source], line.id)
		var packaged := FileAccess.get_file_as_bytes("res://assets/audio/%s.mp3" % line.logical)
		var original := FileAccess.get_file_as_bytes(INBOX + line.source)
		assert_gt(original.size(), 1000, "the original is still in the inbox: " + line.source)
		assert_eq(packaged, original, "packaged recording is the user's file, unchanged: " + line.id)
		var stream := r.get_voice(line.logical)
		assert_not_null(stream, line.id)
		if stream != null:
			assert_gt(stream.get_length(), 0.3, line.id)


func test_rival_speakers_are_the_roster_identities() -> void:
	assert_eq(RivalRoster.short_name(VoiceCatalog.VICTOR), "Victor")
	assert_eq(RivalRoster.short_name(VoiceCatalog.ROCCO), "Rocco")
	assert_eq(RivalRoster.short_name(VoiceCatalog.NINA), "Nina")
	assert_string_contains(RivalRoster.full_name(VoiceCatalog.NINA), "The Hunter")
	assert_string_contains(RivalRoster.full_name(VoiceCatalog.VICTOR), "The Professor")


func test_a_user_override_replaces_one_recording_and_missing_ones_are_silent() -> void:
	var mp3 := FileAccess.get_file_as_bytes("res://assets/audio/voice/victor_clean.mp3")
	var f := FileAccess.open(_root.path_join("audio/voice/rocco_laughing.mp3"), FileAccess.WRITE)
	f.store_buffer(mp3)
	f.close()
	var r := AssetResolver.new(_root)
	var stream := r.get_voice("voice/rocco_laughing")
	assert_not_null(stream)
	assert_almost_eq(stream.get_length(), (load("res://assets/audio/voice/victor_clean.mp3") as AudioStream).get_length(), 0.05,
		"the override is used")
	assert_null(r.get_voice("voice/nobody_recorded_this"), "missing: null, no error")
	var bad := FileAccess.open(_root.path_join("audio/voice/nina_thank_you.mp3"), FileAccess.WRITE)
	bad.store_string("not audio")
	bad.close()
	assert_not_null(AssetResolver.new(_root).get_voice("voice/nina_thank_you"), "a broken override falls back to the packaged line")


# --- selection ---

func _quiet_params() -> VoiceParams:
	var p := _params()
	p.silence_destroyed = 0.0
	p.silence_overtake = 0.0
	p.silence_wall = 0.0
	p.chatter_silence = 0.0
	return p


func test_one_line_at_a_time_and_events_during_it_are_dropped() -> void:
	var s := VoiceSelector.new(_quiet_params(), _rng())
	var line := s.choose(10.0, [{"event": E.PLAYER_DESTROYED, "speaker": VoiceCatalog.ANNOUNCER}])
	assert_eq(line.id, "announcer_smoked_you")
	s.spoke(line, 10.0, 1.5)
	assert_true(s.busy(11.0))
	assert_eq(s.choose(11.0, [{"event": E.RIVAL_OVERTOOK_PLAYER, "speaker": 2}]), {}, "dropped while speaking")
	assert_eq(s.choose(10.0 + 1.5 + s.params.min_gap - 0.1, [{"event": E.RIVAL_OVERTOOK_PLAYER, "speaker": 2}]), {}, "and in the short gap")
	assert_false(s.busy(10.0 + 1.5 + s.params.min_gap + 0.1))
	var later := s.choose(30.0, [{"event": E.RIVAL_OVERTOOK_PLAYER, "speaker": 2}])
	assert_eq(later.id, "rocco_laughing", "nothing was queued: the next line is for the new event")


func test_simultaneous_events_give_at_most_one_line() -> void:
	var s := VoiceSelector.new(_quiet_params(), _rng())
	var picks := {}
	for i in 200:
		s.reset()
		var line := s.choose(5.0, [{"event": E.PLAYER_DESTROYED, "speaker": VoiceCatalog.ANNOUNCER},
			{"event": E.RIVAL_OVERTOOK_PLAYER, "speaker": 9}])
		picks[line.get("id", "")] = picks.get(line.get("id", ""), 0) + 1
	assert_true(picks.has("nina_thank_you") and picks.has("announcer_smoked_you"), "sometimes the rival, sometimes the announcer: %s" % picks)
	assert_gt(picks["nina_thank_you"], picks["announcer_smoked_you"], "the rival's reaction is preferred, not always")


func test_silence_is_a_real_choice() -> void:
	var s := VoiceSelector.new(_params(), _rng(3))
	var said := 0
	var silent := 0
	for i in 400:
		s.reset()
		if s.choose(5.0, [{"event": E.PLAYER_HIT_WALL, "speaker": VoiceCatalog.ANNOUNCER}]).is_empty():
			silent += 1
		else:
			said += 1
	assert_gt(silent, said, "barrier hits are commented on only sometimes")
	assert_gt(said, 40)


func test_repeats_and_cooldowns_make_a_line_less_likely() -> void:
	var p := _params()
	var fresh := 0
	var repeat := 0
	for i in 600:
		var a := VoiceSelector.new(p, _rng(i))
		if not a.choose(100.0, [{"event": E.RIVAL_OVERTOOK_PLAYER, "speaker": 9}]).is_empty():
			fresh += 1
		var b := VoiceSelector.new(p, _rng(i))
		b.choose(80.0, [{"event": E.RIVAL_OVERTOOK_PLAYER, "speaker": 9}])  # silent or not: remembered
		b.spoke(VoiceCatalog.line("nina_thank_you"), 88.0, 1.0)
		if not b.choose(100.0, [{"event": E.RIVAL_OVERTOOK_PLAYER, "speaker": 9}]).is_empty():
			repeat += 1
	assert_gt(fresh, repeat * 3, "Nina again ten seconds later is mostly silent (%d vs %d)" % [fresh, repeat])
	assert_gt(repeat, 0, "but not impossible")
	var s := VoiceSelector.new(p, _rng())
	s.choose(1.0, [{"event": E.RIVAL_OVERTOOK_PLAYER, "speaker": 2}])
	s.choose(9.0, [{"event": E.RIVAL_OVERTOOK_PLAYER, "speaker": 2}])
	assert_eq(s.interaction_count(E.RIVAL_OVERTOOK_PLAYER, 2), 2, "per-race memory")
	s.reset()
	assert_eq(s.interaction_count(E.RIVAL_OVERTOOK_PLAYER, 2), 0)


func test_unavailable_recordings_are_never_chosen() -> void:
	var s := VoiceSelector.new(_quiet_params(), _rng())
	s.available = func(line: Dictionary) -> bool: return line.id != "victor_clean"
	for i in 50:
		s.reset()
		assert_eq(s.choose(5.0, [{"event": E.RIVAL_OVERTOOK_PLAYER, "speaker": 1}]), {})


func test_rivals_without_recordings_say_nothing() -> void:
	var s := VoiceSelector.new(_quiet_params(), _rng())
	for id in [3, 4, 5, 6, 7, 8]:
		assert_eq(s.choose(5.0, [{"event": E.RIVAL_OVERTOOK_PLAYER, "speaker": id}]), {}, "rival %d" % id)


# --- overtakes ---

func _feed(w: OvertakeWatch, t0: float, seconds: float, d: Callable, quiet := false) -> Array:
	var out := []
	var t := t0
	while t < t0 + seconds:
		out.append_array(w.update(t, [0], [2], {0: 1000.0, 2: d.call(t)}, quiet))
		t += 1.0 / 60.0
	return out


func test_a_confirmed_pass_is_reported_once() -> void:
	var w := OvertakeWatch.new()
	var ev := _feed(w, 0.0, 1.0, func(_t: float) -> float: return 900.0)  # behind
	ev.append_array(_feed(w, 1.0, 3.0, func(t: float) -> float: return 900.0 + (t - 1.0) * 120.0))  # drives past
	assert_eq(ev, [{"human": 0, "rival": 2}])
	assert_eq(_feed(w, 4.0, 2.0, func(_t: float) -> float: return 1300.0), [], "stays ahead: no repeat")


func test_jitter_and_side_by_side_are_not_passes() -> void:
	var w := OvertakeWatch.new()
	var ev := _feed(w, 0.0, 1.0, func(_t: float) -> float: return 960.0)
	ev.append_array(_feed(w, 1.0, 4.0, func(t: float) -> float: return 1000.0 + 40.0 * sin(t * 9.0)))  # nose to nose
	assert_eq(ev, [], "brief swaps are never confirmed")
	ev = _feed(w, 5.0, 0.4, func(_t: float) -> float: return 1080.0)  # ahead, but only briefly
	ev.append_array(_feed(w, 5.4, 1.0, func(_t: float) -> float: return 960.0))
	assert_eq(ev, [])


func test_starting_grid_and_quiet_start_report_nothing() -> void:
	var w := OvertakeWatch.new()
	assert_eq(_feed(w, 0.0, 1.0, func(_t: float) -> float: return 1100.0), [], "a rival ahead on the grid")
	var w2 := OvertakeWatch.new()
	var ev := _feed(w2, 0.0, 0.8, func(_t: float) -> float: return 900.0, true)
	ev.append_array(_feed(w2, 0.8, 1.5, func(_t: float) -> float: return 1100.0, true))
	assert_eq(ev, [], "the field sorting itself out at the start")


func test_teleports_restart_without_an_event() -> void:
	var w := OvertakeWatch.new()
	var ev := _feed(w, 0.0, 1.0, func(_t: float) -> float: return 900.0)
	ev.append_array(_feed(w, 1.0, 2.0, func(_t: float) -> float: return 1250.0))  # set back past a jump gap
	assert_eq(ev, [], "a jump recovery is not an overtake")


func test_finished_retired_or_absent_cars_are_forgotten() -> void:
	var w := OvertakeWatch.new()
	var ev := []
	var t := 0.0
	while t < 1.0:
		ev.append_array(w.update(t, [0], [2], {0: 1000.0, 2: 900.0}))
		t += 1.0 / 60.0
	while t < 3.0:  # the rival is no longer eligible (e.g. DNF) while "ahead" in the classification
		ev.append_array(w.update(t, [0], [2], {0: 1000.0}))
		t += 1.0 / 60.0
	while t < 5.0:
		ev.append_array(w.update(t, [0], [2], {0: 1000.0, 2: 1300.0}))
		t += 1.0 / 60.0
	assert_eq(ev, [], "no pass from a classification change")


func test_lap_distance_includes_laps() -> void:
	var w := OvertakeWatch.new()
	# the human starts lap 2 (distance keeps growing across the line): the rival far behind stays behind
	var ev := _feed(w, 0.0, 2.0, func(t: float) -> float: return 1000.0 - 13000.0 + t)
	assert_eq(ev, [])
