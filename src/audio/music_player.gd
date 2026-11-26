class_name MusicPlayer
extends Node
## The game's music: one player for the whole session (the game root owns
## it, so menus and races hand the music over without restarting it), two
## AudioStreamPlayers on the Music bus for crossfades.
##   play("music/music_menu") / play("music/music_race"): the same piece keeps
##   playing; another one fades in while the old one fades out (FADE).
##   Looping: a piece plays to its musical end and its start comes in under the
##   last moments (a short crossfade), so nothing of the composition is cut and
##   there is no gap. The packaged tracks have measured loop points (LOOPS);
##   a user's override loops with DEFAULT_LOOP.
## Keeps playing while the game is paused (pause menus), through destructions,
## commentary (the Voice Director only ducks the Music bus) and camera changes.

## Seconds of the fade between two pieces.
const FADE := 1.2
## Packaged tracks: where the music ends (seconds before the end of the file;
## the rest is silence or a reverb tail) and the crossfade into the restart.
## Measured from the official recordings (docs/MUSIC.md).
const LOOPS := {
	"music/music_menu": {"end_trim": 0.92, "crossfade": 0.08},
	"music/music_race": {"end_trim": 1.25, "crossfade": 0.35},
	# Battle Royale: 0.84 s of silence before the music and 0.59 s after it; the
	# restart begins where the music does (start), so the loop has no gap.
	"music/music_battle": {"end_trim": 0.59, "crossfade": 0.2, "start": 0.83},
}
const DEFAULT_LOOP := {"end_trim": 0.0, "crossfade": 0.25}
const SILENT_DB := -60.0
## Level of the music under the Music bus volume (headroom for engines,
## weapons and voices).
const BASE_DB := -3.0

var resolver: AssetResolver
## The piece playing ("" none) and how many times it has looped (tests).
var current := ""
var loops := 0
var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _loop := DEFAULT_LOOP
var _tweens := [null, null]
var _starts := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # on through pause menus
	AudioSettings.ensure_buses()
	for k in 2:
		var p := AudioStreamPlayer.new()
		p.name = "Music%d" % k
		p.bus = "Music"
		p.volume_db = SILENT_DB
		add_child(p)
		_players.append(p)


## Plays a piece (logical name), fading over from whatever plays now. The
## same piece is never restarted. fade 0: at once.
func play(logical: String, fade: float = FADE) -> void:
	if logical == current and playing():
		return
	if resolver == null:
		resolver = AssetResolver.new()
	var stream := resolver.get_audio(logical)
	if stream == null:
		return
	_unloop(stream)
	current = logical
	loops = 0
	_loop = DEFAULT_LOOP if resolver.has_audio_override(logical) else LOOPS.get(logical, DEFAULT_LOOP)
	var old := _active
	_active = 1 - _active
	_fade(old, SILENT_DB, fade, true)
	_start(_active, stream, fade, float(_loop.get("start", 0.0)))
	_starts += 1


## Fades the music out (and stops it).
func stop(fade: float = FADE) -> void:
	current = ""
	for k in 2:
		_fade(k, SILENT_DB, fade, true)


func playing() -> bool:
	return _players.size() == 2 and (_players[0].playing or _players[1].playing)


## How many times a piece was (re)started by play() (tests: a destruction or a
## lap never restarts the music).
func starts() -> int:
	return _starts


func position() -> float:
	return _players[_active].get_playback_position() if _players[_active].playing else 0.0


func _process__perf(_delta: float) -> void:
	var p := _players[_active]
	if current == "" or not p.playing or p.stream == null:
		return
	if MusicPlayer.loop_due(p.get_playback_position(), p.stream.get_length(), _loop):
		# the start comes in under the last moments of the piece
		var old := _active
		_active = 1 - _active
		_fade(old, SILENT_DB, _loop.crossfade, true)
		_start(_active, p.stream, _loop.crossfade, float(_loop.get("start", 0.0)))
		loops += 1


## The moment the restart comes in: the piece's musical end less the crossfade.
static func loop_due(position: float, length: float, loop: Dictionary) -> bool:
	return position >= length - float(loop.end_trim) - float(loop.crossfade)


## from: where in the piece to begin (skips leading silence).
func _start(k: int, stream: AudioStream, fade: float, from: float = 0.0) -> void:
	var p := _players[k]
	p.stream = stream
	p.volume_db = SILENT_DB if fade > 0.0 else BASE_DB
	p.play(from)
	_fade(k, BASE_DB, fade, false)


func _fade(k: int, to_db: float, time: float, stop_after: bool) -> void:
	if _tweens[k] != null and _tweens[k].is_valid():
		_tweens[k].kill()
	var p := _players[k]
	if not p.playing:
		return
	if time <= 0.0:
		p.volume_db = to_db
		if stop_after:
			p.stop()
		return
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	# equal-loudness-ish: fade in fast at first, fade out late (linear in amplitude)
	tw.tween_method(func(a: float) -> void: p.volume_db = linear_to_db(maxf(a, 0.001)),
		db_to_linear(p.volume_db), db_to_linear(to_db), time)
	if stop_after:
		tw.tween_callback(p.stop)
	_tweens[k] = tw


## The players loop by hand (crossfade), never by the stream's own loop.
static func _unloop(stream: AudioStream) -> void:
	if stream is AudioStreamMP3 or stream is AudioStreamOggVorbis:
		stream.loop = false
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_DISABLED


## DIAGNOSTIC probe (Performance Investigation 001)
func _process(_delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process__perf(_delta)
	PerfProbe.add(&"audio.music", __t)
