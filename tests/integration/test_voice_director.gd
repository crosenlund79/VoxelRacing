extends GutTest
## The Voice Director in real races: the player's car destroyed, a hard barrier
## hit and each named rival passing the player trigger their recordings; one
## line at a time; nothing for spectators; couch and network safety; pause and
## leaving; volume and playback speed; and commentary never changes a race.

const MAIN_SCENE := preload("res://src/main/main.tscn")
const P := RaceSession.PLAYER_ID
const P2 := RaceSession.PLAYER_2_ID

var _main: Node2D
var _lines: Array = []


class Drive extends DriverInput:
	var throttle := true
	func _init(p_throttle: bool) -> void:
		throttle = p_throttle
	func drive(_race: Node, _step: float) -> Dictionary:
		return {"steer": 0.0, "fire": throttle}


class Speeder extends DriverInput:
	func drive(_race: Node, _step: float) -> Dictionary:
		return {"steer": 0.0, "fire": true, "pit_override": true}


func after_each() -> void:
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0
	Engine.max_physics_steps_per_frame = 8
	_lines.clear()


## A race scene with commentary; talkative = no random silence (deterministic tests).
func _make(talkative := true, humans := 1, spectate := false, layout := "") -> void:
	_main = MAIN_SCENE.instantiate()
	if layout != "":
		_main.use_command_line_layout = false
		_main.layout_override = DevLayouts.load_layout(layout)
	var p: VoiceParams = (load("res://src/audio/default_voice_params.tres") as VoiceParams).duplicate()
	if talkative:
		p.silence_destroyed = 0.0
		p.silence_overtake = 0.0
		p.silence_wall = 0.0
		p.silence_pit_violation = 0.0
		p.chatter_silence = 0.0
		p.speaker_cooldown_factor = 1.0
		p.repeat_factor = 1.0
		p.min_gap = 0.5
	_main.voice_params = p
	_main.weapons_lock_enabled = false  # the "Weapons hot" call: test_weapons_hot.gd
	if humans == 2:
		_main.human_count = 2
		_main.player_devices = [3, 4] as Array[int]
	add_child_autofree(_main)
	await wait_physics_frames(2)
	_main.voice.line_started.connect(func(id: String) -> void: _lines.append(id))
	if spectate:
		_main.set_menu_choice(2)
	_main.set_weapons_enabled(true)
	_main.start_race()
	await wait_physics_frames(2)


func _park_rivals(except: Array = []) -> void:
	for id in range(1, 10):
		if except.has(id):
			continue
		_main.cars[id].active = false
		_main.cars[id].place(Transform2D(0.0, Vector2(-9000 - id * 300, -9000)))
		_main.progress[id].reset(_main.cars[id].global_position)


func _place(id: int, s: float, speed: float, lateral := 0.0, input: DriverInput = null) -> void:
	var path: ClosedPath = _main.track.path
	var tan := path.tangent_at(s)
	var c: Car = _main.cars[id]
	c.place(Transform2D(tan.angle(), path.point_at(s) + tan.orthogonal() * -lateral))
	c.model.velocity = tan * speed
	c.active = true
	_main.progress[id].reset(c.global_position)
	if input != null:
		_main.inputs[id] = input


func _mine_on(id: int) -> void:
	_main.combat.mines.append({"owner": 5, "pos": _main.cars[id].global_position, "age": _main.combat.rules.mine_fuse - 0.01})


## Rival `rival` drives past the stopped player on the main straight.
func _overtake(rival: int) -> void:
	_park_rivals([rival])
	await wait_physics_frames(2)  # parked bodies leave the road before anyone is placed
	_place(P, 900.0, 0.0, -40.0, Drive.new(false))
	_place(rival, 650.0, 260.0, 40.0, Drive.new(true))
	await wait_seconds(2.5)


func _wait_out_start() -> void:
	await wait_seconds(_main.voice_params.start_quiet + 0.2)


# --- the five recordings ---

func test_player_destroyed_says_smoked_you() -> void:
	await _make()
	_mine_on(P)
	await wait_physics_frames(3)
	await wait_process_frames(2)
	assert_eq(_lines, ["announcer_smoked_you"])
	assert_true(_main.voice.speaking())


func test_hard_barrier_hit_says_bumper_cars_and_a_scrape_does_not() -> void:
	await _make()
	_park_rivals()
	_place(P, 700.0, 100.0, 40.0, Drive.new(false))
	var path: ClosedPath = _main.track.path
	_main.cars[P].global_rotation = path.tangent_at(700.0).angle() + PI / 2.0
	_main.cars[P].model.heading = _main.cars[P].global_rotation
	_main.cars[P].model.velocity = path.tangent_at(700.0).rotated(PI / 2.0) * 100.0
	await wait_seconds(1.0)
	assert_eq(_lines, [], "a gentle touch is not commented on")
	_place(P, 700.0, 0.0, 0.0, Drive.new(false))
	_main.cars[P].global_rotation = path.tangent_at(700.0).angle() + PI / 2.0
	_main.cars[P].model.heading = _main.cars[P].global_rotation
	_main.cars[P].model.velocity = path.tangent_at(700.0).rotated(PI / 2.0) * 420.0
	await wait_seconds(0.6)
	assert_eq(_lines, ["announcer_bumper_cars"])


func test_each_named_rival_taunts_when_passing_the_player() -> void:
	for pair in [[2, "rocco_laughing"], [9, "nina_thank_you"], [1, "victor_clean"]]:
		await _make()
		await _wait_out_start()
		await _overtake(pair[0])
		assert_gt(_main.session.racers[pair[0]].progress, _main.session.racers[P].progress, "%d passed the player" % pair[0])
		assert_eq(_lines, [pair[1]], RivalRoster.short_name(pair[0]))
		_main.queue_free()
		await wait_physics_frames(2)
		_lines.clear()


func test_other_rivals_passing_say_nothing_and_the_player_passing_a_rival_is_silent() -> void:
	await _make()
	await _wait_out_start()
	await _overtake(4)  # Hank: no recording
	assert_eq(_lines, [])
	_park_rivals()
	_place(2, 900.0, 0.0, 40.0, Drive.new(false))  # Rocco parked
	_place(P, 650.0, 260.0, -40.0, Drive.new(true))  # the player passes him
	await wait_seconds(2.5)
	assert_eq(_lines, [], "only being passed BY a rival counts")


func test_no_overtake_lines_from_the_start_or_a_whole_ai_race_order_shuffle_without_passes() -> void:
	await _make()
	await wait_seconds(2.0)  # the field drives away from the player on the grid
	assert_false(_lines.has("rocco_laughing") or _lines.has("nina_thank_you") or _lines.has("victor_clean"),
		"rivals starting ahead are not passes: %s" % [_lines])


# --- one voice, memory, silence ---

## A rival overrides the limiter (free: nothing said), then rams a car stopped
## in the pit lane: one collision ticket, the announcer's "Pit lane
## violation" once (the recording names no offence, so it fits collisions).
func test_pit_collision_ticket_says_pit_lane_violation_once() -> void:
	await _make(true, 1, false, "kestrel_ridge")
	await _wait_out_start()
	_park_rivals([3, 5])
	await wait_physics_frames(2)
	var layout: TrackLayout = _main.track.layout
	var b: Dictionary = layout.branches[layout.pit_branch()]
	var s := float(b.box) - 260.0
	var bd := layout.route_bounds(s, _main.track.path.length, 1)
	var lat := (bd.x + bd.y) * 0.5
	_place(5, s + 260.0, 0.0, lat, Drive.new(false))
	_place(3, s, 150.0, lat, Speeder.new())
	await wait_physics_frames(20)
	assert_true(_main.pits.overridden[3] == 1, "the limiter overridden")
	assert_eq(_lines, [], "speeding alone: no ticket, nothing said")
	await wait_seconds(1.5)
	assert_eq(_main.pits.tickets[3], 1, "one collision ticket")
	assert_eq(_main.pits.tickets[5], 0, "not the stopped car")
	assert_eq(_lines, ["announcer_pit_violation"], "the announcer, once")


func test_one_line_at_a_time_and_nothing_queued() -> void:
	await _make()
	await _wait_out_start()
	_mine_on(P)
	await wait_physics_frames(3)
	await wait_process_frames(1)
	assert_eq(_lines, ["announcer_smoked_you"])
	await _overtake(2)  # Rocco passes the wrecked player while the announcer speaks
	var after_line: float = _main.voice.time
	assert_eq(_lines, ["announcer_smoked_you"], "dropped, not queued")
	await wait_seconds(3.0)
	assert_eq(_lines, ["announcer_smoked_you"], "and never played later")
	assert_lt(after_line, _main.voice.time)


func test_repeated_passes_are_often_met_with_silence() -> void:
	await _make(false)
	var sel: VoiceSelector = _main.voice.selector
	var said := 0
	for i in 40:
		sel.reset()
		sel.rng.seed = i
		var first := sel.choose(10.0, [{"event": VoiceCatalog.Event.RIVAL_OVERTOOK_PLAYER, "speaker": 9}])
		if not first.is_empty():
			sel.spoke(first, 10.0, 0.8)
		if not sel.choose(20.0, [{"event": VoiceCatalog.Event.RIVAL_OVERTOOK_PLAYER, "speaker": 9}]).is_empty():
			said += 1
	assert_lt(said, 20, "Nina again ten seconds later: mostly silent (%d / 40)" % said)


# --- modes ---

func test_spectating_never_treats_the_followed_car_as_the_player() -> void:
	await _make(true, 1, true)
	assert_eq(_main.voice.humans(), [] as Array[int])
	_mine_on(_main.director.target_id)
	await wait_physics_frames(3)
	await wait_process_frames(2)
	assert_eq(_lines, [], "no 'smoked you' for the followed rival")


func test_couch_race_covers_both_players_with_one_voice() -> void:
	await _make(true, 2)
	assert_eq(_main.voice.humans(), [P, P2] as Array[int])
	_mine_on(P)
	_mine_on(P2)
	await wait_physics_frames(3)
	await wait_process_frames(2)
	assert_eq(_lines, ["announcer_smoked_you"], "both destroyed together: one line")


func test_network_races_only_comment_on_this_computers_player() -> void:
	var link := NetLink.new()
	add_child_autofree(link)
	link.host(24771)
	_main = MAIN_SCENE.instantiate()
	_main.human_count = 2
	_main.net = NetRace.new(link, NetRace.Role.HOST)
	add_child_autofree(_main)
	await wait_physics_frames(2)
	assert_eq(_main.voice.humans(), [P] as Array[int], "the host speaks for its own player only")
	link.close()


# --- pause, leave, settings ---

func test_pause_holds_the_line_and_leaving_cleans_up() -> void:
	await _make()
	_mine_on(P)
	await wait_physics_frames(3)
	await wait_process_frames(1)
	var music := AudioServer.get_bus_index("Music")
	var effects_with := AudioServer.get_bus_effect_count(music)
	_main.open_race_menu()
	await wait_process_frames(3)
	var t: float = _main.voice.time
	assert_true(_main.voice.player.stream_paused, "the line waits in the menu")
	await wait_process_frames(10)
	assert_eq(_main.voice.time, t, "voice time stops while paused")
	_main.resume_race()
	await wait_process_frames(2)
	assert_false(_main.voice.player.stream_paused)
	_main.free()
	await wait_process_frames(1)
	assert_eq(AudioServer.get_bus_effect_count(music), effects_with - 1, "ducking removed from the music bus")


func test_voice_volume_and_playback_speed_settings() -> void:
	var s := AudioSettings.new("user://test_voice_settings.cfg")
	assert_true(AudioSettings.BUSES.has("Voice"))
	s.set_volume("Voice", 0.5)
	assert_almost_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Voice")), linear_to_db(0.5), 0.01)
	s.set_muted("Voice", true)
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index("Voice")))
	s.set_muted("Voice", false)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_voice_settings.cfg"))
	await _make()
	await _wait_out_start()
	await _overtake(9)
	assert_eq(_lines, ["nina_thank_you"])
	assert_almost_eq(_main.voice.player.pitch_scale, 1.10, 0.001, "rivals a little faster")
	assert_eq(_main.voice.player.bus, "Voice")
	var pitch := VoiceDirector._bus_effect("Voice", "AudioEffectPitchShift") as AudioEffectPitchShift
	assert_almost_eq(pitch.pitch_scale, 1.0 / 1.10, 0.001, "natural pitch kept")
	assert_eq(_main.voice.speed_for(VoiceCatalog.line("announcer_smoked_you")), 1.0)


func test_commentary_never_changes_the_race() -> void:
	# fresh processes; presentation (with the Voice Director) on and off
	for args in [["mode=race", "ticks=1500", "weapons=1"], ["mode=spectate", "ticks=1500", "weapons=1"]]:
		var on := ProbeRunner.run(PackedStringArray(args + ["presentation=1"]))
		var off := ProbeRunner.run(PackedStringArray(args + ["presentation=0"]))
		assert_ne(on, "")
		assert_eq(on, off, str(args))
