class_name VoiceDirector
extends Node
## Race commentary and rival taunts (presentation only, read-only on the race):
## watches the race for the events the recordings exist for (the local
## player's car destroyed, a hard barrier hit, a rival confirmed passing the
## player), lets the VoiceSelector pick at most one line (or silence), and
## plays it on the Voice bus. Only one line ever plays; events while it plays
## are dropped. Spectating: nobody is "the player", so nothing is said.

signal line_started(id: String)

var race: Node
var params: VoiceParams
var selector: VoiceSelector
var watch := OvertakeWatch.new()
var player: AudioStreamPlayer
## Seconds of race presentation (stops while the game is paused).
var time := 0.0
var _resolver: AssetResolver
var _pending: Array = []
var _event_index := 0
var _race_number := -1
var _race_start := 0.0
var _speaking_until := -INF
var _ducks: Array = []
var _duck_db := 0.0
var _pitch: AudioEffectPitchShift


func setup(p_race: Node, resolver: AssetResolver, p_params: VoiceParams, rng: RandomNumberGenerator = null) -> void:
	race = p_race
	_resolver = resolver
	params = p_params
	selector = VoiceSelector.new(params, rng)
	selector.available = func(line: Dictionary) -> bool: return _resolver.get_voice(line.logical) != null
	watch.margin = params.overtake_margin
	watch.confirm = params.overtake_confirm
	AudioSettings.ensure_buses()
	player = AudioStreamPlayer.new()
	player.name = "Voice"
	player.bus = "Voice"
	add_child(player)
	_pitch = _bus_effect("Voice", "AudioEffectPitchShift") as AudioEffectPitchShift
	for bus in ["Music", "Engine"]:
		var amp := AudioEffectAmplify.new()
		AudioServer.add_bus_effect(AudioServer.get_bus_index(bus), amp)
		_ducks.append([bus, amp])
	for c in race.cars:
		c.wall_hit.connect(func(_n: Vector2, speed: float) -> void: _on_wall(c.racer_id, speed))


func _exit_tree() -> void:
	for d in _ducks:  # leave the buses as they were
		var bus := AudioServer.get_bus_index(d[0])
		for i in AudioServer.get_bus_effect_count(bus):
			if AudioServer.get_bus_effect(bus, i) == d[1]:
				AudioServer.remove_bus_effect(bus, i)
				break
	_ducks.clear()


func _notification(what: int) -> void:
	if player == null:
		return
	if what == NOTIFICATION_PAUSED:
		player.stream_paused = true  # the game menu: the line waits
	elif what == NOTIFICATION_UNPAUSED:
		player.stream_paused = false


## The humans voices react to on this computer (none when spectating; in a
## network race only this computer's player).
func humans() -> Array[int]:
	var session: RaceSession = race.session
	var out: Array[int] = []
	if session.spectator:
		return out
	if race.net != null:
		out.append(race.local_player_id)
		return out
	for id in session.human_ids:
		if session.is_participating(id):
			out.append(id)
	return out


func speaking() -> bool:
	return time < _speaking_until


func _process(delta: float) -> void:
	time += delta
	_update_duck(delta)
	var session: RaceSession = race.session
	if race.races_started != _race_number:
		_race_number = race.races_started
		_race_start = time
		selector.reset()
		watch.reset()
		_event_index = 0
		_pending.clear()
	if session.state != RaceSession.State.RACING:
		_pending.clear()
		return
	_collect_destructions()
	_collect_overtakes()
	if not _pending.is_empty():
		var line := selector.choose(time, _pending)
		_pending.clear()
		if not line.is_empty():
			_play(line)


func _on_wall(id: int, speed: float) -> void:
	if speed < params.wall_min_speed or not _racing(id) or not humans().has(id):
		return
	_pending.append({"event": VoiceCatalog.Event.PLAYER_HIT_WALL, "speaker": VoiceCatalog.ANNOUNCER})


## The player's car destroyed by a weapon (a combat "destroyed" event; a DNF
## without a destruction is not one).
func _collect_destructions() -> void:
	var events: Array = race.combat.events
	if events.size() < _event_index:
		_event_index = 0
	var mine := humans()
	for k in range(_event_index, events.size()):
		var e: Dictionary = events[k]
		if e.kind == "destroyed" and mine.has(e.car):
			_pending.append({"event": VoiceCatalog.Event.PLAYER_DESTROYED, "speaker": VoiceCatalog.ANNOUNCER})
		elif e.kind == "unlock":  # Weapons Hot (also when spectating: a race announcement)
			_pending.append({"event": VoiceCatalog.Event.WEAPONS_HOT, "speaker": VoiceCatalog.ANNOUNCER})
		elif e.kind == "ticket":  # a pit-lane collision ticket (anyone's: once per ticket)
			_pending.append({"event": VoiceCatalog.Event.PIT_VIOLATION, "speaker": VoiceCatalog.ANNOUNCER})
	_event_index = events.size()


func _collect_overtakes() -> void:
	var mine := humans()
	if mine.is_empty():
		return
	var session: RaceSession = race.session
	var rivals: Array[int] = []
	var distances := {}
	for r in session.participants():
		if _racing(r.id):
			distances[r.id] = r.progress
			if not session.human_ids.has(r.id):
				rivals.append(r.id)
	var quiet := time - _race_start < params.start_quiet
	for o in watch.update(time, mine, rivals, distances, quiet):
		_pending.append({"event": VoiceCatalog.Event.RIVAL_OVERTOOK_PLAYER, "speaker": o.rival})


## Still racing: in the race, not finished, not out.
func _racing(id: int) -> bool:
	var session: RaceSession = race.session
	return session.state == RaceSession.State.RACING and session.is_participating(id) \
		and not session.racers[id].is_done()


func _play(line: Dictionary) -> void:
	var stream := _resolver.get_voice(line.logical)
	if stream == null:
		return
	var speed := speed_for(line)
	player.stream = stream
	player.pitch_scale = speed
	if _pitch != null:
		_pitch.pitch_scale = 1.0 / speed if params.preserve_pitch else 1.0
	player.play()
	var duration := stream.get_length() / speed
	_speaking_until = time + duration
	selector.spoke(line, time, duration)
	line_started.emit(line.id)


## Playback speed of a line (per-line override, else rival / announcer speed).
func speed_for(line: Dictionary) -> float:
	if params.line_speed.has(line.id):
		return float(params.line_speed[line.id])
	return params.rival_speed if VoiceCatalog.is_rival(line.speaker) else params.announcer_speed


## Music and engines a little quieter while someone speaks (smooth fade).
func _update_duck(delta: float) -> void:
	var target := params.duck_db if speaking() else 0.0
	var rate := absf(params.duck_db) / maxf(params.duck_fade, 0.01)
	_duck_db = move_toward(_duck_db, target, rate * delta)
	for d in _ducks:
		d[1].volume_db = _duck_db


static func _bus_effect(bus_name: String, type: String) -> AudioEffect:
	var bus := AudioServer.get_bus_index(bus_name)
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i).is_class(type):
			return AudioServer.get_bus_effect(bus, i)
	var effect := AudioEffectPitchShift.new()
	effect.oversampling = 8
	AudioServer.add_bus_effect(bus, effect)
	return effect
