class_name RaceAudio
extends Node
## Race soundscape: engines, tyre squeal from sliding, impact sounds, race start
## and finish cues, trackside ambience and menu/race music. Read-only: it
## observes car state and hit signals and never changes the race.
##
## Engines (P2): per car a deep foundation loop plus a load layer that fades in
## while the car accelerates and goes quiet when cruising; pitch follows speed
## on a flattening curve within a narrow range, rises a little under load and
## dips when braking, all smoothed. Load and braking are estimated from the
## car's own speed changes, so it works the same for the host, network clients,
## AI and humans. Only the nearest few rival engines play (plus your own car).

const SLIDE_SQUEAL := 80.0
const MAX_DISTANCE := 1600.0

var _cars: Array[Car] = []
var _engines: Array[AudioStreamPlayer2D] = []
var _loads: Array[AudioStreamPlayer2D] = []
## Per-car smoothed engine state: speed last frame, load / brake estimates,
## pitch, voice weight (0..1, fades with the nearest-voices choice).
var _last_speed := PackedFloat32Array()
var _load := PackedFloat32Array()
var _brake := PackedFloat32Array()
var _pitch := PackedFloat32Array()
var _voice := PackedFloat32Array()
var _clock := 0.0
## Engine tuning (default_engine_sound.tres).
var engine_params: EngineSoundParams = preload("res://src/audio/default_engine_sound.tres")
## Racer ids driven on this computer: always audible, at full engine volume.
var local_ids: Array[int] = [RaceSession.PLAYER_ID]
var _squeals: Array[AudioStreamPlayer2D] = []
var _impacts: Array[AudioStreamPlayer2D] = []
var _next_impact := 0
## The game's music (handed over by the scene, so it never restarts between
## menus and races); a bare race scene gets its own.
var music: MusicPlayer
var _own_music := false
var _ambience: AudioStreamPlayer
var _cue: AudioStreamPlayer
var _resolver: AssetResolver
## Own generator: presentation never touches the global or race random state.
var _rng := RandomNumberGenerator.new()
## Fast simulation: engines and squeal are turned down (sounds are not sped up).
var fast := false


func setup(cars: Array[Car], resolver: AssetResolver, sound_parent: Node2D) -> void:
	AudioSettings.ensure_buses()
	_cars = cars
	_resolver = resolver
	for i in cars.size():
		# each car keeps its own engine recording for the race (loop n with
		# load n: a matched pair), by racer id so a driver always sounds alike;
		# a tyre squeal variation per car
		var v := engine_variant(cars[i].racer_id)
		var engine := resolver.get_audio_variant("vehicles/engine_loop", v, true)
		var load := resolver.get_audio_variant("vehicles/engine_load", v, true)
		var squeal := resolver.get_audio("vehicles/tire_squeal", true)
		_engines.append(_player2d(sound_parent, engine, "Engine", -80.0))
		_loads.append(_player2d(sound_parent, load, "Engine", -80.0))
		_squeals.append(_player2d(sound_parent, squeal, "Effects", -80.0))
	_last_speed.resize(cars.size())
	_load.resize(cars.size())
	_brake.resize(cars.size())
	_pitch.resize(cars.size())
	_pitch.fill(engine_params.pitch_idle)
	_voice.resize(cars.size())
	for k in 10:
		_impacts.append(_player2d(sound_parent, null, "Effects", 0.0))
	for c in cars:
		c.wall_hit.connect(func(_n: Vector2, speed: float) -> void: _impact(c, speed, "vehicles/impact_wall"))
		c.car_hit.connect(func(_o: Car, speed: float) -> void: _impact(c, speed, "vehicles/impact_car"))
	var shared: Variant = sound_parent.get("music")
	if shared is MusicPlayer:
		music = shared
	else:
		music = MusicPlayer.new()
		music.name = "Music"
		add_child(music)
		_own_music = true
	music.resolver = resolver
	_ambience = _player(resolver, "ambience/ambience", "Effects", -10.0)
	_cue = _player(resolver, "", "Effects", -2.0)
	_ambience.play()


## Base pitch per sound where two sounds share recordings: the supplied
## homing launch recordings are the missile launch ones, so the homing
## missile is played a little higher to keep the two apart.
const PITCH := {"weapons/homing_launch": 1.12}


## Which engine recording a racer drives with (Audio Integration 001): the
## same for a racer in every race and in the replays (wraps round however
## many recordings there are).
static func engine_variant(racer_id: int) -> int:
	return [0, 2, 1, 3, 0, 1, 2, 3, 1, 2][posmod(racer_id, 10)]


## "menu", "race" or "battle" (fades over; the same piece keeps playing).
func play_music(mood: String) -> void:
	music.play("music/music_" + mood)


func play_cue(logical: String) -> void:
	_cue.stream = _resolver.get_audio(logical)
	_cue.play()


func _process(delta: float) -> void:
	_clock += delta
	var voiced := _voiced_cars()
	for i in _cars.size():
		var c := _cars[i]
		var engine := _engines[i]
		var squeal := _squeals[i]
		var running := c.visible and c.model != null and (c.active or c.model.velocity.length() > 1.0)
		if not running or fast:
			if engine.playing and (not c.visible or fast):
				_stop_engine(i)
			if squeal.playing:
				squeal.stop()
			if not running or not c.visible:
				continue
		if fast:
			continue
		engine.global_position = c.global_position
		_loads[i].global_position = c.global_position
		squeal.global_position = c.global_position
		var speed := absf(c.model.forward_speed())
		_update_engine(i, c, speed, voiced.has(i), delta)
		var slide := absf(c.model.lateral_speed())
		if c.active and slide > SLIDE_SQUEAL:
			squeal.volume_db = lerpf(-20.0, -6.0, clampf((slide - SLIDE_SQUEAL) / 220.0, 0.0, 1.0))
			squeal.pitch_scale = 0.9 + clampf(speed / 600.0, 0.0, 0.3)
			if not squeal.playing:
				squeal.play()
		elif squeal.playing:
			squeal.stop()


## Stop everything on exit so no playback outlives the scene.
func _exit_tree() -> void:
	for p in _engines + _loads + _squeals + _impacts:
		p.stop()
		p.stream = null
	if _own_music and music != null:
		music.stop(0.0)
	for p in [_ambience, _cue]:
		if p != null:
			p.stop()
			p.stream = null


## One-shot positional sound (weapons); skipped in fast simulation.
func play_at(logical: String, pos: Vector2) -> void:
	if fast:
		return
	var p := _impacts[_next_impact]
	_next_impact = (_next_impact + 1) % _impacts.size()
	p.stream = _resolver.get_audio(logical)
	p.global_position = pos
	p.volume_db = -2.0
	p.pitch_scale = _rng.randf_range(0.95, 1.05) * float(PITCH.get(logical, 1.0))
	p.play()


func stop_cars() -> void:
	for p in _engines + _loads + _squeals:
		p.stop()


## Pitch and volumes of one engine for its state (pure; also used by tests).
## speed_ratio: forward speed / max speed. load: 0..1 how hard the engine
## works (accelerating). brake: 0..1 braking. time: seconds, for the drift.
## Returns {pitch, base_db, load_db}.
static func engine_targets(p: EngineSoundParams, speed_ratio: float, load: float, brake: float, time: float,
		phase: float = 0.0) -> Dictionary:
	var r := clampf(speed_ratio, 0.0, 1.0)
	var pitch := lerpf(p.pitch_idle, p.pitch_top, pow(r, p.pitch_curve))
	pitch += p.load_pitch * clampf(load, 0.0, 1.0) + p.brake_pitch * clampf(brake, 0.0, 1.0)
	pitch *= 1.0 + p.drift_amount * sin(TAU * p.drift_hz * time + phase)
	var base_db := lerpf(p.volume_idle_db, p.volume_top_db, r) - 2.0 * clampf(brake, 0.0, 1.0)
	var l := clampf(load, 0.0, 1.0)
	var load_db := p.load_volume_db + linear_to_db(maxf(l, 0.001))
	return {"pitch": pitch, "base_db": base_db, "load_db": load_db}


func _update_engine(i: int, c: Car, speed: float, voiced: bool, delta: float) -> void:
	var p := engine_params
	var dt := maxf(delta, 0.0001)
	var accel := (speed - _last_speed[i]) / dt
	_last_speed[i] = speed
	var max_speed := c.model.params.max_speed
	# How hard the engine works: actual acceleration, or a held throttle below
	# top speed where the input is known (simulated cars). Clamp spikes from
	# collisions and network snapshots.
	var effort := accel / maxf(1.0, c.model.params.acceleration)
	var want_load := clampf((effort - p.load_deadzone) / (1.0 - p.load_deadzone), 0.0, 1.0)
	if c.active and c.model.is_accelerating(c.fire):
		# held throttle: full effort low down, fading out towards top speed
		want_load = maxf(want_load, 0.85 * clampf((0.97 - speed / max_speed) / 0.3, 0.0, 1.0))
	# near top speed the frequent small recoveries after each turn only add a
	# little life (cruise_load), so long fast stretches stay calm
	var headroom := clampf((1.0 - speed / max_speed) / 0.1, 0.0, 1.0)
	want_load *= lerpf(p.cruise_load, 1.0, headroom)
	var want_brake := clampf(-accel / maxf(1.0, c.model.params.brake_deceleration), 0.0, 1.0)
	var k_load := 1.0 - exp(-dt / p.load_smoothing)
	_load[i] = lerpf(_load[i], want_load, k_load)
	_brake[i] = lerpf(_brake[i], want_brake, k_load)
	var target := engine_targets(p, speed / max_speed, _load[i], _brake[i], _clock, float(i) * 1.7)
	_pitch[i] = lerpf(_pitch[i], target.pitch, 1.0 - exp(-dt / p.pitch_smoothing))
	_voice[i] = move_toward(_voice[i], 1.0 if voiced else 0.0, dt / maxf(0.01, p.voice_fade))
	var engine := _engines[i]
	var load := _loads[i]
	if _voice[i] <= 0.0:
		if engine.playing:
			_stop_engine(i)
		return
	var gain := linear_to_db(_voice[i]) + (0.0 if local_ids.has(c.racer_id) else p.rival_offset_db)
	var k_vol := 1.0 - exp(-dt / p.volume_smoothing)
	engine.pitch_scale = _pitch[i]
	load.pitch_scale = _pitch[i]
	engine.volume_db = lerpf(engine.volume_db, target.base_db + gain, k_vol) if engine.playing else target.base_db + gain
	load.volume_db = lerpf(load.volume_db, target.load_db + gain, k_vol) if load.playing else target.load_db + gain
	if not engine.playing:
		var offset := _rng.randf() * 0.9
		engine.play(offset)
		if load.stream != null:
			load.play(offset)


func _stop_engine(i: int) -> void:
	_engines[i].stop()
	_loads[i].stop()


## Engines heard this frame: the local car(s) and the nearest rivals.
func _voiced_cars() -> Dictionary:
	var out := {}
	var ear := _ear()
	var rivals: Array = []
	for i in _cars.size():
		var c := _cars[i]
		if not c.visible:
			continue
		if local_ids.has(c.racer_id):
			out[i] = true
		else:
			rivals.append([c.global_position.distance_squared_to(ear), i])
	rivals.sort()
	for k in mini(engine_params.max_rival_voices, rivals.size()):
		out[rivals[k][1]] = true
	return out


## Where the listener is: the current 2D listener (split-screen), else the camera.
func _ear() -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return Vector2.ZERO
	var listener := vp.get_audio_listener_2d()
	if listener != null:
		return listener.global_position
	var cam := vp.get_camera_2d()
	return cam.get_screen_center_position() if cam != null else Vector2.ZERO


func _impact(c: Car, speed: float, logical: String) -> void:
	if fast or speed < 60.0 or not c.visible:
		return
	var p := _impacts[_next_impact]
	_next_impact = (_next_impact + 1) % _impacts.size()
	p.stream = _resolver.get_audio(logical)
	p.global_position = c.global_position
	p.volume_db = lerpf(-14.0, 0.0, clampf(speed / 400.0, 0.0, 1.0))
	p.pitch_scale = _rng.randf_range(0.9, 1.1)
	p.play()


func _player2d(parent: Node2D, stream: AudioStream, bus: String, volume: float) -> AudioStreamPlayer2D:
	var p := AudioStreamPlayer2D.new()
	p.stream = stream
	p.bus = bus
	p.volume_db = volume
	p.max_distance = MAX_DISTANCE
	p.attenuation = 1.6
	parent.add_child(p)
	return p


func _player(resolver: AssetResolver, logical: String, bus: String, volume: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	if not logical.is_empty():
		p.stream = resolver.get_audio(logical, AssetCatalog.AUDIO[logical].loop)
	p.bus = bus
	p.volume_db = volume
	add_child(p)
	return p
