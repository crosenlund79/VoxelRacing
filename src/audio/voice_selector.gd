class_name VoiceSelector
extends RefCounted
## Decides what (if anything) is said for this moment's race events, with a
## short per-race memory. Pure logic with an injected clock and random
## generator, so it is fully testable. Only one line at a time: while a line
## plays, or within min_gap after it, new events are discarded (never queued).

var params: VoiceParams
var rng: RandomNumberGenerator
## Optional Callable(line: Dictionary) -> bool: whether a line's recording is
## available (missing recordings are simply never chosen).
var available: Callable

var _quiet_until := -INF
var _speaking_until := -INF
var _last_line := ""
var _speaker_last := {}
var _interactions := {}
var _spoken_at: Array[float] = []


func _init(p_params: VoiceParams, p_rng: RandomNumberGenerator = null) -> void:
	params = p_params
	rng = p_rng if p_rng != null else RandomNumberGenerator.new()
	if p_rng == null:
		rng.randomize()


## New race: forget everything said and seen.
func reset() -> void:
	_quiet_until = -INF
	_speaking_until = -INF
	_last_line = ""
	_speaker_last.clear()
	_interactions.clear()
	_spoken_at.clear()


## No new line may start (one is playing, or the short gap after it).
func busy(now: float) -> bool:
	return now < _quiet_until


## How often this interaction (event + speaker) happened this race.
func interaction_count(event: int, speaker: int) -> int:
	return _interactions.get(Vector2i(event, speaker), {}).get("count", 0)


## events: [{"event": VoiceCatalog.Event, "speaker": rival id or ANNOUNCER}],
## everything that happened at this moment. Returns the line to say, or {}
## (silence: busy, nothing fits, or quiet by choice). Every event is remembered.
func choose(now: float, events: Array) -> Dictionary:
	var pool: Array = []
	var silence := 0.0
	var announcement := false
	for e in events:
		if VoiceCatalog.ANNOUNCEMENTS.has(e.event):
			announcement = true
		var key := Vector2i(e.event, e.speaker)
		var memory: Dictionary = _interactions.get(key, {"count": 0, "last": -INF})
		var count: int = memory.count + 1
		var repeated: bool = now - memory.last < params.repeat_window
		silence = maxf(silence, _silence_for(e.event))
		var speakers := [e.speaker] if e.speaker == VoiceCatalog.ANNOUNCER else [e.speaker, VoiceCatalog.ANNOUNCER]
		for speaker in speakers:
			for line in VoiceCatalog.lines_for(e.event, speaker):
				if count < line.get("min_count", 0) or (available.is_valid() and not available.call(line)):
					continue
				var w: float = line.get("weight", 1.0)
				if VoiceCatalog.is_rival(speaker):
					w *= params.rival_preference
				if now - _speaker_last.get(speaker, -INF) < params.speaker_cooldown:
					w *= params.speaker_cooldown_factor
				if repeated:
					w *= params.repeat_factor
				if line.id == _last_line:
					w *= params.same_line_factor
				pool.append([line, w])
		_interactions[key] = {"count": count, "last": now}
	if pool.is_empty():
		return {}
	if announcement:  # an official race announcement: said unless a line is still playing
		if now < _speaking_until:
			return {}
		for p in pool:
			if VoiceCatalog.ANNOUNCEMENTS.has(p[0].event):
				return p[0]
	if busy(now):
		return {}
	var recent := 0
	for t in _spoken_at:
		if now - t < 60.0:
			recent += 1
	silence += params.chatter_silence * recent
	var total := silence
	for p in pool:
		total += p[1]
	var roll := rng.randf() * total
	for p in pool:
		roll -= p[1]
		if roll < 0.0:
			return p[0]
	return {}


## A line started playing now and lasts `duration` seconds.
func spoke(line: Dictionary, now: float, duration: float) -> void:
	_quiet_until = now + duration + params.min_gap
	_speaking_until = now + duration
	_last_line = line.id
	_speaker_last[line.speaker] = now
	_spoken_at.append(now)
	while _spoken_at.size() > 8:
		_spoken_at.pop_front()


func _silence_for(event: int) -> float:
	match event:
		VoiceCatalog.Event.PLAYER_DESTROYED: return params.silence_destroyed
		VoiceCatalog.Event.RIVAL_OVERTOOK_PLAYER: return params.silence_overtake
		VoiceCatalog.Event.PLAYER_HIT_WALL: return params.silence_wall
		VoiceCatalog.Event.WEAPONS_HOT: return 0.0
		VoiceCatalog.Event.PIT_VIOLATION: return params.silence_pit_violation
	return 1.0
