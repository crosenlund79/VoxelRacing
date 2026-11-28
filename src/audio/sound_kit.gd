extends RefCounted
## VoxelRacing's procedural sound kit: short, mellow mono sounds synthesised in
## code (no asset files) for the crowd, the pit workshop and the interface.
## Each sound is generated on first use (16-bit PCM, 22050 Hz, fixed random
## seeds so it never changes between runs, normalised a little below full
## scale) and cached for the rest of the session.
##
##   const SoundKit := preload("res://src/audio/sound_kit.gd")
##   SoundKit.play(self, "cheer", -4.0)              # one-shot; frees itself
##   player.stream = SoundKit.stream("crowd_loop")   # a seamless ~4 s loop
##
## Names: crowd_loop, cheer, applause, gasp, tool_clink, ratchet, air_wrench,
## debris_rattle, whoosh, pop, tick, stinger. warm_up() makes them all at once
## (e.g. behind a loading screen). Presentation only.

const RATE := 22050
const NAMES: Array[String] = ["crowd_loop", "cheer", "applause", "gasp", "tool_clink", "ratchet",
	"air_wrench", "debris_rattle", "whoosh", "pop", "tick", "stinger"]
## Peak level (linear, 1.0 = full scale). The crowd bed sits lower so it stays
## underneath everything else at the same player volume.
const PEAK := 0.85
const PEAK_BED := 0.6

static var _cache := {}
## Pitch jitter for play(): its own generator, so playing a sound never
## touches the global random sequence the race may be seeded with.
static var _jitter := RandomNumberGenerator.new()


## Audio Integration 001: the logical sound each kit name stands for. When a
## recording exists for it (the user's custom/audio/ override, else the
## packaged ElevenLabs recordings: AssetResolver.get_audio_variants), that is
## played - a random variation per call - and the synthesised sound below is
## only the placeholder for sounds still without a recording.
const LOGICAL := {
	"crowd_loop": "crowd/crowd_loop", "cheer": "crowd/cheer", "applause": "crowd/applause", "gasp": "crowd/gasp",
	"tool_clink": "garage/tool_clink", "ratchet": "garage/ratchet", "air_wrench": "garage/air_wrench",
	"debris_rattle": "vehicles/debris_rattle", "whoosh": "ui/whoosh", "pop": "ui/pop", "tick": "ui/tick",
	"stinger": "ui/stinger", "backfire": "vehicles/backfire", "turbo_spit": "vehicles/turbo_spit",
}
## Kit names without a synthesised version of their own: the placeholder used.
const STAND_IN := {"backfire": "pop", "turbo_spit": "pop"}


## The named sound: a recording when one exists (a random variation, looping
## for crowd_loop), else the synthesised placeholder (generated once, then
## cached); null for an unknown name.
static func stream(name: String) -> AudioStream:
	var logical := String(LOGICAL.get(name, ""))
	if not logical.is_empty():
		var res := AssetResolver.shared()
		if res.has_audio(logical):
			return res.get_audio(logical, name == "crowd_loop")
	if STAND_IN.has(name):
		name = STAND_IN[name]
	return _synth(name)


## True when the named sound is played from a recording (not synthesised).
static func is_recorded(name: String) -> bool:
	var logical := String(LOGICAL.get(name, ""))
	return not logical.is_empty() and AssetResolver.shared().has_audio(logical)


static func _synth(name: String) -> AudioStreamWAV:
	if _cache.has(name):
		return _cache[name]
	var s: PackedFloat32Array
	match name:
		"crowd_loop": s = _crowd_loop()
		"cheer": s = _cheer()
		"applause": s = _applause()
		"gasp": s = _gasp()
		"tool_clink": s = _tool_clink()
		"ratchet": s = _ratchet()
		"air_wrench": s = _air_wrench()
		"debris_rattle": s = _debris_rattle()
		"whoosh": s = _whoosh()
		"pop": s = _pop()
		"tick": s = _tick()
		"stinger": s = _stinger()
		_:
			push_warning("SoundKit: no sound named '%s'" % name)
			return null
	var loop := name == "crowd_loop"
	var wav := _to_wav(s, PEAK_BED if loop else PEAK, loop)
	_cache[name] = wav
	return wav


## Generates every sound now, so a first play never waits for synthesis.
static func warm_up() -> void:
	for n in NAMES:
		_synth(n)


## Plays a sound once on a new AudioStreamPlayer under `parent` (on `bus`,
## "Effects" by default: the game's effects volume), with a slight random
## pitch, and frees the player when it finishes. Returns the player (null if
## nothing could play). A looping sound keeps playing until its player is freed.
static func play(parent: Node, name: String, volume_db: float = 0.0, pitch_jitter: float = 0.05,
		bus: String = "Effects") -> AudioStreamPlayer:
	if parent == null or not is_instance_valid(parent):
		return null
	var s := stream(name)
	if s == null:
		return null
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = volume_db
	p.bus = bus if AudioServer.get_bus_index(bus) != -1 else "Master"
	p.pitch_scale = maxf(0.1, 1.0 + _jitter.randf_range(-pitch_jitter, pitch_jitter))
	p.finished.connect(p.queue_free)
	parent.add_child(p)
	if p.is_inside_tree():
		p.play()
	else:
		p.autoplay = true
	return p


# ------------------------------------------------------------------ crowd

## A soft, distant crowd murmur: a breathy band of noise under a babble of
## voices (soft buzzes gated into syllables, through two vowel formants), low
## passed for distance, with a small stadium echo. Seamless: the tail is
## cross-faded into the head.
static func _crowd_loop() -> PackedFloat32Array:
	var n := 4 * RATE
	var fade := RATE / 2
	var total := n + fade
	var rng := _rng(1101)
	var bed := _noise(total, 1102)
	_biquad(bed, "bp", 520.0, 0.7)
	_biquad(bed, "lp", 1400.0)
	var voices := _buf(total)
	for v in 10:
		_babble(voices, rng, 0, total, rng.randf_range(100.0, 235.0), rng.randf_range(0.5, 1.0))
	var f2 := voices.duplicate()
	_biquad(voices, "bp", 560.0, 1.6)
	_biquad(f2, "bp", 1250.0, 2.4)
	var out := _buf(total)
	for i in total:
		# a slow swell, periodic with the loop, so the murmur breathes
		var swell := 0.86 + 0.14 * sin(TAU * float(i) / n)
		out[i] = (bed[i] * 0.55 + voices[i] * 1.1 + f2[i] * 0.45) * swell
	_biquad(out, "lp", 1700.0)
	_echo(out, 0.053, 0.22)
	_echo(out, 0.097, 0.16)
	var loop := _buf(n)
	for i in n:
		if i < fade:
			var w := float(i) / fade
			loop[i] = out[i] * sqrt(w) + out[n + i] * sqrt(1.0 - w)
		else:
			loop[i] = out[i]
	return loop


## One talker into `out` from sample `from` to `to`: syllables of a soft buzz
## at a speaking pitch with a little intonation.
static func _babble(out: PackedFloat32Array, rng: RandomNumberGenerator, from: int, to: int, f0: float, gain: float) -> void:
	var at := from + int(rng.randf_range(0.0, 0.3) * RATE)
	while at < to:
		var length := int(rng.randf_range(0.08, 0.22) * RATE)
		var amp := gain * rng.randf_range(0.35, 1.0)
		var inc := f0 * rng.randf_range(0.88, 1.15) / RATE
		var glide := 1.0 + rng.randf_range(-0.15, 0.12) / length
		var phase := rng.randf()
		var end := mini(at + length, to)
		for i in range(at, end):
			var x := float(i - at) / length
			var w := 4.0 * x * (1.0 - x)
			phase += inc
			inc *= glide
			if phase >= 1.0:
				phase -= 1.0
			out[i] += (2.0 * phase - 1.0) * w * w * amp
		at = end + int(rng.randf_range(0.03, 0.28) * RATE)


## A crowd cheer: a rising swell of "whoo"s (voices gliding up, with vibrato)
## over a bright breath of noise and a scatter of claps; ~1.8 s.
static func _cheer() -> PackedFloat32Array:
	var dur := 1.8
	var n := int(dur * RATE)
	var rng := _rng(2201)
	var air := _noise(n, 2202)
	_biquad(air, "bp", 1100.0, 0.6)
	_biquad(air, "lp", 3600.0)
	var voices := _buf(n)
	for v in 12:
		var start := int(rng.randf_range(0.0, 0.2) * RATE)
		var stop := n - int(rng.randf_range(0.0, 0.35) * RATE)
		var f0 := rng.randf_range(210.0, 430.0)
		var rise := rng.randf_range(0.15, 0.4)
		var vib := rng.randf_range(4.5, 6.5)
		var gain := rng.randf_range(0.5, 1.0)
		var phase := rng.randf()
		var span := float(stop - start) / RATE
		for i in range(start, stop):
			var t := float(i - start) / RATE
			var glide := 1.0 + rise * minf(t / 0.45, 1.0) - 0.1 * maxf(t - 0.9, 0.0)
			phase += f0 * glide * (1.0 + 0.02 * sin(TAU * vib * t)) / RATE
			if phase >= 1.0:
				phase -= 1.0
			voices[i] += (2.0 * phase - 1.0) * gain * _swell(t, 0.3, span * 0.55, span)
	var f2 := voices.duplicate()
	_biquad(voices, "bp", 900.0, 1.3)
	_biquad(f2, "bp", 2000.0, 2.0)
	var claps := _buf(n)
	_scatter_claps(claps, _clap_grains(2203, 8), rng, 0.25, dur - 0.1, 110, 0.25, dur * 0.6, dur - 0.1)
	var out := _buf(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = air[i] * 0.5 * _swell(t, 0.35, 0.95, dur) + voices[i] * 1.2 + f2[i] * 0.4 + claps[i] * 0.35
	_biquad(out, "lp", 4200.0)
	_echo(out, 0.061, 0.2)
	return out


## ~2.5 s of applause: hundreds of short band-passed noise claps scattered in
## time, thinning out at the end, over a faint wash.
static func _applause() -> PackedFloat32Array:
	var dur := 2.5
	var n := int(dur * RATE)
	var rng := _rng(3301)
	var out := _buf(n)
	_scatter_claps(out, _clap_grains(3302, 12), rng, 0.0, dur - 0.05, 360, 0.12, 1.25, dur - 0.05)
	var wash := _noise(n, 3303)
	_biquad(wash, "bp", 1800.0, 0.5)
	for i in n:
		var t := float(i) / RATE
		out[i] += wash[i] * 0.12 * _swell(t, 0.12, 1.25, dur)
	_biquad(out, "lp", 6500.0)
	_biquad(out, "hp", 250.0)
	_echo(out, 0.043, 0.18)
	return out


## A crowd "oooh" for crashes: many voices on an "oo" vowel, rising a little
## then falling away, with a breath of air; ~1 s.
static func _gasp() -> PackedFloat32Array:
	var dur := 1.05
	var n := int(dur * RATE)
	var rng := _rng(4401)
	var voices := _buf(n)
	for v in 12:
		var start := int(rng.randf_range(0.0, 0.06) * RATE)
		var f0 := rng.randf_range(115.0, 270.0)
		var gain := rng.randf_range(0.5, 1.0)
		var phase := rng.randf()
		var vib := rng.randf_range(4.0, 6.0)
		for i in range(start, n):
			var t := float(i - start) / RATE
			var glide := 1.0 + 0.1 * minf(t / 0.2, 1.0) - 0.2 * maxf(t - 0.2, 0.0) / 0.85
			phase += f0 * glide * (1.0 + 0.012 * sin(TAU * vib * t)) / RATE
			if phase >= 1.0:
				phase -= 1.0
			voices[i] += (2.0 * phase - 1.0) * gain
	var f2 := voices.duplicate()
	_biquad(voices, "bp", 330.0, 2.5)
	_biquad(f2, "bp", 820.0, 3.0)
	var breath := _noise(n, 4402)
	_biquad(breath, "bp", 700.0, 1.0)
	var out := _buf(n)
	for i in n:
		var t := float(i) / RATE
		var e := _swell(t, 0.09, 0.26, dur)
		out[i] = (voices[i] * 1.3 + f2[i] * 0.5 + breath[i] * 0.3) * e
	_biquad(out, "lp", 2600.0)
	_echo(out, 0.071, 0.2)
	return out


## Clap "grains": short noise bursts with a fast decay, each through its own
## band-pass (hand resonance), ready to be scattered.
static func _clap_grains(seed: int, count: int) -> Array[PackedFloat32Array]:
	var rng := _rng(seed)
	var grains: Array[PackedFloat32Array] = []
	for g in count:
		var length := int(0.03 * RATE)
		var a := _noise(length, seed * 31 + g)
		var tau := rng.randf_range(0.0035, 0.0065) * RATE
		for i in length:
			a[i] *= minf(float(i) / 6.0, 1.0) * exp(-float(i) / tau)
		_biquad(a, "bp", rng.randf_range(900.0, 2400.0), rng.randf_range(1.0, 2.2))
		grains.append(a)
	return grains


## `count` claps between t0 and t1 seconds, shaped by an envelope (attack,
## hold until `hold_end`, fade out until `end`): fewer and softer as it fades.
static func _scatter_claps(out: PackedFloat32Array, grains: Array[PackedFloat32Array], rng: RandomNumberGenerator,
		t0: float, t1: float, count: int, attack: float, hold_end: float, end: float) -> void:
	for k in count:
		var t := rng.randf_range(t0, t1)
		var e := _swell(t - t0, attack, hold_end - t0, end - t0)
		if rng.randf() > e:  # thinning out
			continue
		var g: PackedFloat32Array = grains[rng.randi_range(0, grains.size() - 1)]
		var amp := e * rng.randf_range(0.3, 1.0)
		var at := int(t * RATE)
		for i in mini(g.size(), out.size() - at):
			out[at + i] += g[i] * amp


# ---------------------------------------------------------------- workshop

## A wrench set down on metal: a few decaying inharmonic partials (each with a
## slightly detuned twin for a metallic beat) and a quieter rebound.
static func _tool_clink() -> PackedFloat32Array:
	var n := int(0.7 * RATE)
	var out := _buf(n)
	_strike(out, 0, 1.0, 1650.0, 5501)
	_strike(out, int(0.085 * RATE), 0.3, 1672.0, 5502)
	_biquad(out, "lp", 7000.0)
	_biquad(out, "hp", 200.0)
	return out


static func _strike(out: PackedFloat32Array, at: int, amp: float, f: float, seed: int) -> void:
	var ratios := [1.0, 1.59, 2.71, 3.98, 5.2]
	var decays := [0.3, 0.19, 0.11, 0.07, 0.045]
	var gains := [1.0, 0.55, 0.42, 0.28, 0.18]
	for p in ratios.size():
		var fp: float = f * ratios[p]
		var tau: float = decays[p]
		var g: float = gains[p] * amp
		var length := mini(int(tau * 6.0 * RATE), out.size() - at)
		for i in length:
			var t := float(i) / RATE
			out[at + i] += (sin(TAU * fp * t) + 0.5 * sin(TAU * fp * 1.004 * t)) * exp(-t / tau) * g
	var click := _noise(int(0.004 * RATE), seed)
	_biquad(click, "hp", 3000.0)
	for i in mini(click.size(), out.size() - at):
		out[at + i] += click[i] * amp * 0.6 * (1.0 - float(i) / click.size())


## A quick socket ratchet: eight clicks, each a tick of noise with a small
## resonant ping and a woody knock.
static func _ratchet() -> PackedFloat32Array:
	var n := int(0.36 * RATE)
	var rng := _rng(6601)
	var out := _buf(n)
	var t := 0.01
	var k := 0
	while t < 0.31:
		var at := int(t * RATE)
		var amp := (0.72 if k % 2 == 0 else 1.0) * rng.randf_range(0.85, 1.0)
		var ping := rng.randf_range(3000.0, 3300.0)
		for i in mini(int(0.03 * RATE), n - at):
			var tt := float(i) / RATE
			var v := (rng.randf() * 2.0 - 1.0) * exp(-tt / 0.0012) * 0.8
			v += sin(TAU * ping * tt) * exp(-tt / 0.007) * 0.5
			v += sin(TAU * 1150.0 * tt) * exp(-tt / 0.005) * 0.55
			out[at + i] += v * amp
		t += rng.randf_range(0.034, 0.042)
		k += 1
	_biquad(out, "hp", 300.0)
	_biquad(out, "lp", 7500.0)
	return out


## A short pneumatic "brrrt": a hiss of air chopped by the hammer's impacts as
## the wrench spins up, a low rattle and a motor hum, then a quick spin-down.
static func _air_wrench() -> PackedFloat32Array:
	var n := int(0.6 * RATE)
	var hiss := _noise(n, 7701)
	_biquad(hiss, "bp", 2100.0, 0.9)
	var body := _noise(n, 7702)
	_biquad(body, "lp", 900.0)
	var out := _buf(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := smoothstep(0.0, 0.015, t) * (1.0 - smoothstep(0.42, 0.58, t))
		var rate := lerpf(38.0, 62.0, smoothstep(0.0, 0.18, t)) * (1.0 - 0.35 * smoothstep(0.42, 0.58, t))
		ph += rate / RATE
		if ph >= 1.0:
			ph -= 1.0
		var hit := exp(-ph * 9.0)
		out[i] = env * (hiss[i] * (0.35 + 0.65 * hit) * 0.9 + body[i] * hit * 1.4 + sin(TAU * ph * 4.0) * 0.12)
	_biquad(out, "hp", 70.0)
	_biquad(out, "lp", 4800.0)
	return out


## Small plastic and metal pieces clattering down: a burst of impacts, dense
## at first and settling, each a click with one or two short partials; ~0.5 s.
static func _debris_rattle() -> PackedFloat32Array:
	var n := int(0.55 * RATE)
	var rng := _rng(8801)
	var out := _buf(n)
	for k in 26:
		var t := 0.46 * pow(rng.randf(), 1.8)
		var amp := exp(-t * 4.0) * rng.randf_range(0.35, 1.0)
		var metal := rng.randf() < 0.45
		var f := rng.randf_range(2400.0, 4600.0) if metal else rng.randf_range(850.0, 2100.0)
		var tau := rng.randf_range(0.035, 0.07) if metal else rng.randf_range(0.01, 0.022)
		var ratio := rng.randf_range(1.38, 1.62)
		var at := int(t * RATE)
		for i in mini(int(tau * 5.0 * RATE), n - at):
			var tt := float(i) / RATE
			var e := exp(-tt / tau)
			var v := (sin(TAU * f * tt) + 0.5 * sin(TAU * f * ratio * tt) * e) * e
			if i < 30:
				v += (rng.randf() * 2.0 - 1.0) * (1.0 - i / 30.0) * 0.8
			out[at + i] += v * amp
	_biquad(out, "hp", 150.0)
	_biquad(out, "lp", 6000.0)
	return out


# --------------------------------------------------------------- interface

## A soft swoosh: noise through a resonant band-pass that sweeps up and back
## down, inside a smooth swell; ~0.5 s.
static func _whoosh() -> PackedFloat32Array:
	var n := int(0.5 * RATE)
	var src := _noise(n, 9901)
	var out := _buf(n)
	var low := 0.0
	var band := 0.0
	for i in n:
		var x := float(i) / n
		var bell := sin(PI * pow(x, 0.8))
		bell *= bell
		var fc := 320.0 + 1500.0 * pow(sin(PI * minf(x * 1.1, 1.0)), 1.5)
		var f := 2.0 * sin(PI * fc / RATE)
		low += f * band
		var high := src[i] - low - 0.4 * band
		band += f * high
		out[i] = (band * 0.8 + low * 0.2) * bell
	_biquad(out, "lp", 2800.0)
	return out


## A soft interface pop: a sine dropping quickly in pitch with a fast decay.
static func _pop() -> PackedFloat32Array:
	var n := int(0.14 * RATE)
	var out := _buf(n)
	var ph := 0.0
	var click := _noise(int(0.002 * RATE), 1201)
	_biquad(click, "lp", 3000.0)
	for i in n:
		var t := float(i) / RATE
		ph += (340.0 + 520.0 * exp(-t / 0.018)) / RATE
		var env := minf(t / 0.0015, 1.0) * exp(-t / 0.03)
		out[i] = (sin(TAU * ph) + 0.18 * sin(2.0 * TAU * ph)) * env
		if i < click.size():
			out[i] += click[i] * 0.15
	return out


## A tiny interface tick.
static func _tick() -> PackedFloat32Array:
	var n := int(0.05 * RATE)
	var out := _buf(n)
	for i in n:
		var t := float(i) / RATE
		var env := minf(t / 0.0004, 1.0) * exp(-t / 0.0055)
		out[i] = (sin(TAU * 2200.0 * t) + 0.45 * sin(TAU * 3470.0 * t)) * env
	_biquad(out, "lp", 7000.0)
	return out


## A bright chiptune jingle for celebrations: E5 G5 C6 on a band-limited 25 %
## pulse over a triangle an octave down, the last note held with vibrato and
## a little sparkle, and an echo.
static func _stinger() -> PackedFloat32Array:
	var n := int(1.2 * RATE)
	var out := _buf(n)
	var notes := [[659.26, 0.0, 0.1], [783.99, 0.095, 0.1], [1046.5, 0.19, 0.62]]
	for k in notes.size():
		var f: float = notes[k][0]
		var start := int(float(notes[k][1]) * RATE)
		var length := int(float(notes[k][2]) * RATE)
		var last := k == notes.size() - 1
		var harmonics := int(8500.0 / f)
		var coef := PackedFloat32Array()
		for h in range(1, harmonics + 1):
			coef.append(sin(PI * h * 0.25) / h)
		var ph := 0.0
		for i in length:
			var t := float(i) / RATE
			var vib := 1.0 + (0.006 * sin(TAU * 5.5 * t) * smoothstep(0.08, 0.2, t) if last else 0.0)
			ph += f * vib / RATE
			var pulse := 0.0
			for h in harmonics:
				pulse += sin(TAU * (h + 1) * ph) * coef[h]
			var tph := TAU * ph * 0.5
			var tri := sin(tph) - sin(3.0 * tph) / 9.0 + sin(5.0 * tph) / 25.0
			var env := minf(t / 0.003, 1.0) * (0.65 + 0.35 * exp(-t / 0.05))
			if last:
				env *= exp(-maxf(t - 0.06, 0.0) / 0.35)
			env *= minf(float(length - i) / (0.015 * RATE), 1.0)
			var v := (pulse * 0.55 + tri * 0.45) * env
			if last:
				v += sin(TAU * 2093.0 * t) * exp(-t / 0.25) * 0.18 * minf(t / 0.002, 1.0)
			out[start + i] += v
	_echo(out, 0.13, 0.3)
	_biquad(out, "lp", 6500.0)
	return out


# ----------------------------------------------------------------- helpers

static func _rng(seed: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	return r


static func _buf(n: int) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(n)
	a.fill(0.0)
	return a


static func _noise(n: int, seed: int) -> PackedFloat32Array:
	var r := _rng(seed)
	var a := PackedFloat32Array()
	a.resize(n)
	for i in n:
		a[i] = r.randf() * 2.0 - 1.0
	return a


## A swell: smooth rise over `attack` s, held until `hold_end`, then an eased
## fall to silence at `end`.
static func _swell(t: float, attack: float, hold_end: float, end: float) -> float:
	if t <= 0.0 or t >= end:
		return 0.0
	if t < attack:
		return smoothstep(0.0, attack, t)
	if t < hold_end:
		return 1.0
	var x := 1.0 - (t - hold_end) / maxf(end - hold_end, 0.001)
	return x * x


## RBJ biquad in place: "lp" low-pass, "hp" high-pass, "bp" band-pass (0 dB peak).
static func _biquad(a: PackedFloat32Array, kind: String, freq: float, q: float = 0.707) -> void:
	var w := TAU * freq / RATE
	var cw := cos(w)
	var alpha := sin(w) / (2.0 * q)
	var b0: float
	var b1: float
	var b2: float
	match kind:
		"lp":
			b0 = (1.0 - cw) * 0.5
			b1 = 1.0 - cw
			b2 = b0
		"hp":
			b0 = (1.0 + cw) * 0.5
			b1 = -(1.0 + cw)
			b2 = b0
		_:
			b0 = alpha
			b1 = 0.0
			b2 = -alpha
	var a0 := 1.0 + alpha
	var a1 := -2.0 * cw / a0
	var a2 := (1.0 - alpha) / a0
	b0 /= a0
	b1 /= a0
	b2 /= a0
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in a.size():
		var x := a[i]
		var y := b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		a[i] = y


## A feedback echo in place (`delay` s, `gain` per repeat): a little room.
static func _echo(a: PackedFloat32Array, delay: float, gain: float) -> void:
	var d := int(delay * RATE)
	for i in range(d, a.size()):
		a[i] += a[i - d] * gain


## Normalised to `peak`, short edge fades (one-shots), 16-bit mono PCM.
static func _to_wav(s: PackedFloat32Array, peak: float, loop: bool) -> AudioStreamWAV:
	var n := s.size()
	var m := 0.0
	for v in s:
		m = maxf(m, absf(v))
	var g := peak / m if m > 0.0 else 0.0
	var edge := int(0.002 * RATE)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var v := s[i] * g
		if not loop:
			v *= minf(float(n - 1 - i) / edge, 1.0)
		bytes.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = n
	return wav
