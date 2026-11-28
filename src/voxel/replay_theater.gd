class_name ReplayTheater
extends Node3D
## VoxelRacing action replays, part 2: the show. Plays the recorder's best
## moments with its own voxel cars, its own debris and effects and a
## perspective camera, inside the same voxel world - the live race (hidden
## meanwhile) is never touched. A small director cuts between shots chosen
## for each moment: chase, missile-mounted, mine, trackside, sweeping
## overtake, side-on and an orbiting destruction camera, with a little slow
## motion where it pays off. Confirm / Fire: next moment; Back: skip all.
## A clear view (P007): every camera position is checked against the voxel
## scenery (replay_framing.gd). Fixed cameras pick a spot that sees the whole
## moment, moving cameras slide in closer or rise over anything big in the
## way, small clutter in front of the lens is tidied away for the shot, and
## impacts are framed with the cars involved. The race HUD stays hidden.

signal finished

const W := WeaponRules.Weapon
const LETTERBOX := 64
const TITLE_HOLD := 3.2
const Framing := preload("res://src/voxel/replay_framing.gd")
## Seconds between sight-line checks of a running shot.
const PROBE_EVERY := 0.12

var stage: VoxelStage
var main: Node2D
var recorder: ReplayRecorder
var fx: VoxelFx
var cam: Camera3D
var playing := false
var clips: Array = []
var _clip := -1
var _tau := 0.0
var _prev_tau := 0.0
var _rate := 1.0
var _cars: Array[Dictionary] = []
var _damage: Array[VoxelCarDamage] = []
var _holder: Node3D
var _missiles: Array[MeshInstance3D] = []
var _mines: Array[MeshInstance3D] = []
var _cans: Array = []
var _burns: Node2D
var _scorch: Texture2D
var _shots: Array = []
var _shot := -1
var _shot_clock := 0.0
var _cam_pos := Vector3.ZERO
var _cam_look := Vector3.ZERO
var _cam_fov := 60.0
var _cut := true
var _slow: Array = []
var _event_cursor := 0
var _was_wrecked := PackedByteArray()
var _last_dir: Array[Vector3] = []
var _spin := PackedFloat32Array()
var _prev_pos: Array[Vector3] = []
var _rng := RandomNumberGenerator.new()
var _sounds: Array[AudioStreamPlayer] = []
var _next_sound := 0
var _engine: AudioStreamPlayer
var _focus := Vector2.ZERO
var _saved_env := {}
var _input_grace := 0.0
# a clear view (P007)
var _view: Framing
var _dodge := Vector3.ZERO
var _dodge_want := Vector3.ZERO
var _probe_left := 0.0
var _clear_for := 0.0
var _overlays: Array = []
# overlay
var _ui: CanvasLayer
var _title: Label
var _sub: Label
var _cam_label: Label
var _count: Label
var _rec: ColorRect
var _wipe: ColorRect
const SoundKit := preload("res://src/audio/sound_kit.gd")
var _slowmo: Label
var _hints: Label
var _bars: Array[ColorRect] = []
var _ui_time := 0.0


func setup(p_stage: VoxelStage, p_recorder: ReplayRecorder) -> void:
	stage = p_stage
	main = stage.main
	recorder = p_recorder
	name = "ReplayTheater"
	_rng.seed = 5150
	visible = false
	_view = Framing.new()
	_view.setup(stage)
	fx = VoxelFx.new()
	fx.name = "ReplayFx"
	add_child(fx)
	fx.ground = func(x: float, z: float) -> float:
		return stage.vtrack.height_px_at(Vector2(x, z) / Vox.PX) * Vox.PX if stage.vtrack != null and stage.vtrack.nx > 0 else 0.0
	_holder = Node3D.new()
	_holder.name = "ReplayCars"
	add_child(_holder)
	for i in main.cars.size():
		var d := stage.make_car(i, _holder)
		var dmg := VoxelCarDamage.new(d.model, d.body, 4000 + i)
		_cars.append(d)
		_damage.append(dmg)
		_last_dir.append(Vector3.ZERO)
		_prev_pos.append(Vector3.ZERO)
	_was_wrecked.resize(_cars.size())
	_spin.resize(_cars.size())
	cam = Camera3D.new()
	cam.name = "ReplayCamera"
	cam.near = 0.1
	cam.far = 260.0
	add_child(cam)
	_burns = Node2D.new()
	_burns.name = "ReplayBurns"
	_burns.visibility_layer = VoxelStage.DECAL_LAYER
	_burns.visible = false
	var decals := main.get_node_or_null("Decals") as Node2D
	if decals != null:
		decals.add_child(_burns)
		decals.move_child(_burns, 0)
	_scorch = VoxelRaceFx._make_scorch()
	for k in 6:
		var p := AudioStreamPlayer.new()
		p.bus = "Effects"
		add_child(p)
		_sounds.append(p)
	_engine = AudioStreamPlayer.new()
	_engine.bus = "Effects"
	_engine.volume_db = -12.0
	add_child(_engine)
	_build_ui()


func has_highlights() -> bool:
	return not recorder.highlights(6, 60.0, 4.5).is_empty()


## Moments for the "watch again" list: a little more generous than the
## automatic selection.
func play_highlights(again: bool = false) -> bool:
	var list := recorder.highlights(6 if again else 5, 60.0 if again else 52.0, 4.5 if again else 5.0)
	if list.is_empty():
		return false
	clips = list
	_begin()
	return true


func focus_2d() -> Vector2:
	return _focus


# ------------------------------------------------------------ flow

func _begin() -> void:
	playing = true
	visible = true
	_ui.visible = true
	_input_grace = 0.35
	cam.make_current()
	_env_on(true)
	_view.build()
	_overlays_on(false)
	if main.get("race_audio") != null and main.race_audio != null:
		main.race_audio.fast = true  # the live race goes quiet behind the replay
	_burns.visible = true
	# P004: the replay arrives with a little ceremony - bars slide in, a
	# flash, a whoosh and the jingle
	for k in _bars.size():
		var bar: ColorRect = _bars[k]
		bar.size.y = 0.0
		bar.position.y = 0.0 if k == 0 else 720.0
		var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(bar, "size:y", float(LETTERBOX), 0.35)
		if k == 1:
			create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).tween_property(bar, "position:y", 720.0 - LETTERBOX, 0.35)
	SoundKit.play(self, "stinger", -8.0, 0.0)
	_clip = -1
	_next_clip()


func _next_clip() -> void:
	_clip += 1
	if _clip >= clips.size():
		stop()
		return
	var c: Dictionary = clips[_clip]
	var samples: Array = c.samples
	_tau = float(samples[0][0])
	_prev_tau = _tau
	_event_cursor = 0
	fx.clear()
	_view.restore_all()
	for b in _burns.get_children():
		b.queue_free()
	for can in _cans:
		(can.node as Node3D).queue_free()
	_cans.clear()
	# the cars as they were when the moment began
	for i in _cars.size():
		var dmg := _damage[i]
		dmg.restore(true)
		_set_wheels(i, true)
		var o := i * ReplayRecorder.K
		var cars: PackedFloat32Array = samples[0][1]
		var wrecked := (int(cars[o + 9]) & ReplayRecorder.F_WRECKED) != 0
		_was_wrecked[i] = 1 if wrecked else 0
		var target := VoxelCarDamage.target_loss(cars[o + 8])
		if target > 0.0:
			dmg.break_to(target, Vector3.ZERO)
		if wrecked:
			dmg.explode()
			_set_wheels(i, false)
		_prev_pos[i] = Vector3(cars[o], cars[o + 1], cars[o + 2])
		_last_dir[i] = Vector3.ZERO
	_plan(c)
	_shot = -1
	_cut = true
	_show_titles(c)


func stop() -> void:
	if not playing:
		return
	playing = false
	visible = false
	_ui.visible = false
	_engine.stop()
	fx.clear()
	_burns.visible = false
	for can in _cans:
		(can.node as Node3D).queue_free()
	_cans.clear()
	_env_on(false)
	_view.restore_all()
	_overlays_on(true)
	if stage.camera != null:
		stage.camera.make_current()
	if main.get("race_audio") != null and main.race_audio != null:
		main.race_audio.fast = int(main.get("sim_speed")) > 1 if main.get("sim_speed") != null else false
	finished.emit()


func _process(delta: float) -> void:
	if not playing:
		return
	_ui_time += delta
	_input_grace -= delta
	if _input_grace <= 0.0:
		if Input.is_action_just_pressed(PlayerControls.BACK):
			get_viewport().set_input_as_handled()
			stop()
			return
		if Input.is_action_just_pressed(PlayerControls.CONFIRM) or Input.is_action_just_pressed(PlayerControls.FIRE) \
				or Input.is_action_just_pressed("ui_accept"):
			_next_clip()
			if not playing:
				return
	var c: Dictionary = clips[_clip]
	var samples: Array = c.samples
	_rate = _slow_rate(_tau)
	_prev_tau = _tau
	_tau += delta * _rate
	var end_t := float(samples[-1][0])
	if _tau >= end_t:
		_next_clip()
		return
	_apply(c, delta)
	_update_ui(delta)


# ------------------------------------------------------------ playback

## Index of the sample at or before time t (binary search).
func _index(samples: Array, t: float) -> int:
	var lo := 0
	var hi := samples.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if float(samples[mid][0]) <= t:
			lo = mid
		else:
			hi = mid - 1
	return lo


func _apply(c: Dictionary, delta: float) -> void:
	var samples: Array = c.samples
	var ia := _index(samples, _tau)
	var ib := mini(ia + 1, samples.size() - 1)
	var sa: Array = samples[ia]
	var sb: Array = samples[ib]
	var ta := float(sa[0])
	var tb := float(sb[0])
	var u := clampf((_tau - ta) / (tb - ta), 0.0, 1.0) if tb > ta else 0.0
	var ca: PackedFloat32Array = sa[1]
	var cb: PackedFloat32Array = sb[1]
	var night: bool = main.lighting != null and main.lighting.enabled
	var focus_car := _focus_car()
	for i in _cars.size():
		var d: Dictionary = _cars[i]
		var o := i * ReplayRecorder.K
		var flags := int(ca[o + 9])
		var root: Node3D = d.root
		root.visible = (flags & ReplayRecorder.F_VISIBLE) != 0
		if not root.visible:
			continue
		var pa := Vector3(ca[o], ca[o + 1], ca[o + 2])
		var pb := Vector3(cb[o], cb[o + 1], cb[o + 2])
		var jump := pa.distance_to(pb) > 4.0  # respawned between the samples
		var p := pa if jump else pa.lerp(pb, u)
		root.position = p
		root.rotation = Vector3(0.0, lerp_angle(ca[o + 3], cb[o + 3], u), lerpf(ca[o + 12], cb[o + 12], u))
		(d.tilt as Node3D).rotation = Vector3(lerpf(ca[o + 4], cb[o + 4], u), 0.0, lerpf(ca[o + 5], cb[o + 5], u))
		var steer := lerpf(ca[o + 6], cb[o + 6], u)
		var brake := lerpf(ca[o + 7], cb[o + 7], u)
		var share := lerpf(ca[o + 8], cb[o + 8], u)
		# wheels
		var fwd := Vector3(cos(-root.rotation.y), 0.0, sin(-root.rotation.y))
		var moved := (p - _prev_pos[i])
		_prev_pos[i] = p
		if moved.length() < 3.0:
			_spin[i] = fposmod(_spin[i] - moved.dot(fwd) / (VoxelCars.WHEEL_R * Vox.CAR_VOXEL_PX * Vox.PX), TAU)
		var steer_angle := deg_to_rad(main.wheel_layout.max_steer_degrees) * clampf(steer, -1.0, 1.0)
		for w in 4:
			((d.wheels as Array)[w] as Node3D).rotation.y = -steer_angle if w < 2 else 0.0
			((d.spins as Array)[w] as Node3D).rotation.z = _spin[i]
		var body: MeshInstance3D = d.body
		body.visible = true  # (the respawn blink is a gameplay signal: not in replays)
		var c2: Car = main.cars[i]
		body.set_instance_shader_parameter("tint", c2.sprite.modulate)
		body.set_instance_shader_parameter("head_glow", 0.6 if night else 0.0)
		body.set_instance_shader_parameter("tail_glow", (0.3 + 0.7 * brake) if night else 0.7 * brake)
		var dmg := _damage[i]
		var lights: Array = d.lights
		(lights[0] as Light3D).visible = night and not dmg.wrecked and dmg.lamps[0] > 0
		(lights[1] as Light3D).visible = night and not dmg.wrecked and dmg.lamps[1] > 0
		(lights[2] as Light3D).visible = night and not dmg.wrecked and dmg.lamps[2] + dmg.lamps[3] > 0
		if d.has("head_node"):
			var hv := ca[o + 11] if signf(ca[o + 11]) != signf(cb[o + 11]) else lerpf(ca[o + 11], cb[o + 11], u)
			if absf(hv) > 0.0:
				d.head_side = signf(hv)
			stage.pose_head(d, absf(hv))
		# damage and wrecks, as they happened
		var wrecked := (flags & ReplayRecorder.F_WRECKED) != 0
		if wrecked and _was_wrecked[i] == 0:
			_explode(i, p, (pb - pa) / maxf(tb - ta, 0.001))
		elif not wrecked and _was_wrecked[i] == 1:
			dmg.restore(true)
			_set_wheels(i, true)
		_was_wrecked[i] = 1 if wrecked else 0
		if not wrecked:
			var target := VoxelCarDamage.target_loss(share)
			if target > dmg.loss() + 0.003:
				var pieces := dmg.break_to(target, _last_dir[i])
				_bits(i, pieces, (pb - pa) / maxf(tb - ta, 0.001))
		if dmg.dirty:
			dmg.rebuild()
		# smoke from wrecks and badly damaged cars
		var rate := 9.0 if wrecked else (lerpf(1.5, 6.0, clampf((0.5 - share) / 0.4, 0.0, 1.0)) if share < 0.5 else 0.0)
		if rate > 0.0 and _rng.randf() < delta * rate * _rate:
			var g := _rng.randf_range(0.12, 0.25)
			fx.puff(p + Vector3(_rng.randf_range(-0.5, 0.5), 0.8, _rng.randf_range(-0.5, 0.5)), Vector3(0, 1.3, 0),
				Color(g, g, g), _rng.randf_range(0.35, 0.6), _rng.randf_range(1.0, 1.7), 0.6)
		# the cars still kick the debris about
		if not wrecked and moved.length() < 3.0 and delta > 0.0:
			fx.scatter_near(p, moved / maxf(delta, 0.001), 1.9)
		if i == focus_car:
			var spd := lerpf(ca[o + 10], cb[o + 10], u)
			_engine_sound(spd, i)
	_apply_weapons(sa, sb, u, delta)
	_apply_events(c)
	_update_cans(delta * _rate)
	fx.speed = _rate
	_direct(c, delta)


func _set_wheels(i: int, on: bool) -> void:
	for w in (_cars[i].wheels as Array):
		(w as Node3D).visible = on and _cars[i].show_wheels


func _bits(i: int, pieces: Array, carv: Vector3) -> void:
	if pieces.is_empty():
		return
	var d: Dictionary = _cars[i]
	var xf: Transform3D = (d.body as MeshInstance3D).global_transform
	var root: Node3D = d.root
	var out_dir := (xf.basis.orthonormalized() * _last_dir[i]).normalized() if _last_dir[i].length() > 0.01 else Vector3.ZERO
	fx.throw_parts(d.model, pieces, xf, carv, out_dir, root.position.y if root.position.y > 0.2 else -INF, false)


func _explode(i: int, at: Vector3, carv: Vector3) -> void:
	var d: Dictionary = _cars[i]
	var dmg := _damage[i]
	var xf: Transform3D = (d.body as MeshInstance3D).global_transform
	var centre := at + Vector3(0, 0.5, 0)
	var floor_y := at.y if at.y > 0.2 else -INF
	fx.throw_parts(d.model, dmg.explode(), xf, carv, Vector3.ZERO, floor_y, true)
	fx.throw_wheels(d.wheels, centre, carv, floor_y)
	_set_wheels(i, false)
	fx.explosion(centre, 1.0)
	_burn(Vector2(at.x, at.z) / Vox.PX, 1.0)
	_sound("weapons/explosion", at, 2.0)


func _burn(p: Vector2, scale: float) -> void:
	var s := Sprite2D.new()
	s.texture = _scorch
	s.position = p
	s.rotation = _rng.randf() * TAU
	s.scale = Vector2.ONE * VoxelRaceFx.SCORCH_SIZE * scale * _rng.randf_range(0.9, 1.15) / _scorch.get_width()
	s.visibility_layer = VoxelStage.DECAL_LAYER
	_burns.add_child(s)


func _ground3(p: Vector2, level: int = 0) -> Vector3:
	var h := stage.vtrack.height_px_at(p) if stage.vtrack != null else 0.0
	if level == 1:
		h = maxf(h, VoxelTrack.DECK_H_PX)
	return Vox.to3(p, h)


func _apply_weapons(sa: Array, sb: Array, u: float, _delta: float) -> void:
	var ma: PackedFloat32Array = sa[2]
	var mb: PackedFloat32Array = sb[2]
	var n := ma.size() / 6
	while _missiles.size() < n:
		var m := MeshInstance3D.new()
		m.mesh = VoxelWeapons.missile_mesh()
		m.set_instance_shader_parameter("lamp_glow", 1.0)
		add_child(m)
		_missiles.append(m)
	for k in _missiles.size():
		var mi := _missiles[k]
		mi.visible = k < n
		if not mi.visible:
			continue
		var o := k * 6
		var pos := Vector2(ma[o + 2], ma[o + 3])
		var ang := ma[o + 4]
		for q in mb.size() / 6:  # the same round in the next sample
			if mb[q * 6] == ma[o]:
				pos = pos.lerp(Vector2(mb[q * 6 + 2], mb[q * 6 + 3]), u)
				ang = lerp_angle(ang, mb[q * 6 + 4], u)
				break
		var h := 10.0 + (VoxelTrack.DECK_H_PX if int(ma[o + 5]) == 1 else 0.0)
		mi.position = Vox.to3(pos, h)
		mi.rotation = Vector3(0, Vox.yaw(ang), 0)
		var type := int(ma[o + 1])
		var kind := "super" if type == W.SUPER_MISSILE else ("homing" if type == W.HOMING_MISSILE else "missile")
		if mi.get_meta("kind", "") != kind:
			mi.mesh = VoxelWeapons.missile_mesh(kind)
			mi.set_meta("kind", kind)
		mi.scale = Vector3.ONE * (1.35 if type == W.SUPER_MISSILE else 1.0)
		if _rng.randf() < 0.6 * _rate:
			var back: Vector3 = mi.global_transform * Vector3(-0.7, 0, 0)
			fx.puff(back, Vector3(0, 0.3, 0), Color(0.95, 0.9, 0.8), 0.22, 0.6, 0.6)
			fx.spark(back, Vector3(_rng.randf_range(-0.5, 0.5), 0.5, _rng.randf_range(-0.5, 0.5)), Color(1, 0.6, 0.2), 0.1, 0.15, 1.2, 0.0)
	var na: PackedFloat32Array = sa[3]
	var nm := na.size() / 4
	while _mines.size() < nm:
		var mm := MeshInstance3D.new()
		mm.mesh = VoxelWeapons.mine_mesh()
		add_child(mm)
		_mines.append(mm)
	for k in _mines.size():
		_mines[k].visible = k < nm
		if k >= nm:
			continue
		var o := k * 4
		_mines[k].position = Vox.to3(Vector2(na[o], na[o + 1]), VoxelTrack.DECK_H_PX if int(na[o + 3]) == 1 else 0.0)
		var blink := 0.5 + 0.5 * sin((na[o + 2] + _ui_time) * TAU * 1.5)
		_mines[k].set_instance_shader_parameter("lamp_glow", 0.2 + blink)


## Effects and sounds of the moment's events as the replay reaches them.
func _apply_events(c: Dictionary) -> void:
	var events: Array = c.events
	if _event_cursor == 0 and not events.is_empty():
		events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.t) < float(b.t))
	while _event_cursor < events.size() and float(events[_event_cursor].t) <= _tau:
		var e: Dictionary = events[_event_cursor]
		_event_cursor += 1
		if float(e.t) < _prev_tau - 0.05:
			continue  # before the replay's start
		var p: Vector2 = e.pos
		match String(e.kind):
			"crash", "pileup":
				var a := int(e.car)
				var at := _ground3(p) + Vector3(0, 0.5, 0)
				var sev := clampf((float(e.get("speed", 300.0)) - 70.0) / 260.0, 0.2, 1.0)
				fx.impact(at, Vector3(0, 0.6, 0), sev)
				if a >= 0:
					var root: Node3D = _cars[a].root
					var toward := (at - root.position)
					toward.y = 0.0
					_last_dir[a] = (root.global_transform.basis.inverse() * toward.normalized()) if toward.length() > 0.01 else Vector3.ZERO
				_sound("vehicles/impact_car" if int(e.by) >= 0 else "vehicles/impact_wall", at, 0.0)
			"fire":
				_sound(CombatView.LAUNCH_SOUNDS.get(int(e.type), "weapons/missile_launch"), _ground3(p), -2.0)
			"hit", "blast":
				var at := _ground3(p) + Vector3(0, 0.4, 0)
				fx.explosion(at, 0.5)
				_burn(p, 0.4)
				_sound("weapons/explosion", at, 0.0)
				var v := int(e.car)
				if v >= 0:
					var root: Node3D = _cars[v].root
					var toward := at - root.position
					toward.y = 0.0
					_last_dir[v] = root.global_transform.basis.inverse() * toward.normalized()
			"mine_blast":
				var at := _ground3(p) + Vector3(0, 0.4, 0)
				fx.explosion(at, 0.75)
				_burn(p, 0.55)
				_sound("weapons/explosion", at, 2.0)
			"finish":
				_sound("race/finish", _ground3(p), -4.0)
			"taunt":
				_throw_can(e)


func _sound(logical: String, at: Vector3, gain_db: float) -> void:
	var res: AssetResolver = main.resolver
	if res == null:
		return
	var stream := res.get_audio(logical)
	if stream == null:
		return
	var p := _sounds[_next_sound]
	_next_sound = (_next_sound + 1) % _sounds.size()
	p.stream = stream
	var dist := cam.global_position.distance_to(at)
	p.volume_db = gain_db - clampf((dist - 6.0) * 0.35, 0.0, 18.0)
	p.pitch_scale = clampf(lerpf(0.75, 1.0, _rate), 0.6, 1.05) * _rng.randf_range(0.95, 1.05) * float(RaceAudio.PITCH.get(logical, 1.0))
	p.play()


var _engine_rid := -1


func _engine_sound(speed: float, car: int) -> void:
	# the focus car's own engine recording (as in the race)
	var rid: int = main.cars[car].racer_id if car >= 0 and car < main.cars.size() else 0
	if (_engine.stream == null or rid != _engine_rid) and main.resolver != null:
		_engine_rid = rid
		var s: AudioStream = main.resolver.get_audio_variant("vehicles/engine_loop", RaceAudio.engine_variant(rid), true)
		if s != _engine.stream:
			_engine.stream = s
	if _engine.stream == null:
		return
	if not _engine.playing:
		_engine.play()
	_engine.pitch_scale = clampf((0.7 + speed / 520.0) * lerpf(0.7, 1.0, _rate), 0.5, 2.0)


# ------------------------------------------------------------ soda cans

func _throw_can(e: Dictionary) -> void:
	var node := MeshInstance3D.new()
	node.mesh = VoxelWeapons.can_mesh()
	add_child(node)
	node.position = e.can_pos
	_cans.append({"node": node, "vel": e.can_vel, "spin": e.get("can_spin", Vector3(7, 3, 5)), "rest": false, "life": 12.0})


func _update_cans(dt: float) -> void:
	VoxelRaceFx.step_cans(_cans, dt, fx.ground)


# ------------------------------------------------------------ slow motion

func _slow_rate(t: float) -> float:
	var r := 1.0
	for w in _slow:
		var a := float(w[0])
		var b := float(w[1])
		var target := float(w[2])
		var ramp := 0.18
		var k := 0.0
		if t >= a and t <= b:
			k = 1.0
		elif t > a - ramp and t < a:
			k = (t - (a - ramp)) / ramp
		elif t > b and t < b + ramp:
			k = 1.0 - (t - b) / ramp
		r = minf(r, lerpf(1.0, target, k))
	return r


# ------------------------------------------------------------ the director

## Shots for a moment: [type, from, to, params].
func _plan(c: Dictionary) -> void:
	_shots.clear()
	_slow.clear()
	var samples: Array = c.samples
	var cs := float(samples[0][0])
	var ce := float(samples[-1][0])
	var e: Dictionary = c.key
	var tk := float(e.t)
	var victim := int(e.get("car", -1))
	var by := int(e.get("by", -1))
	var pos: Vector2 = e.pos
	var rival := _others([by], victim)  # the other car in the moment, framed with the victim
	match String(e.kind):
		"destroyed", "hit":
			var type := int(e.get("type", -1))
			var launch := float(e.get("launch_t", -1.0))
			var rid := int(e.get("rid", -1))
			if type == W.MINE:
				var mine_from := maxf(cs, tk - 2.6)
				_add_shot("chase", cs, mine_from, {"car": victim})
				_add_shot("mine", mine_from, tk + 1.0, {"car": victim, "pos": pos})
				_add_shot("destruction", tk + 1.0, ce, {"car": victim, "pos": pos, "others": rival})
				_slow.append([tk - 0.15, tk + 0.9, 0.3])
			elif rid >= 0 and launch >= cs and by >= 0 and by != victim:
				var lt := launch + 0.05
				_add_shot("chase", cs, lt, {"car": by})
				_add_shot("missile", lt, tk + 0.25, {"rid": rid, "car": victim})
				_add_shot("destruction", tk + 0.25, ce, {"car": victim, "pos": pos, "others": rival})
				_slow.append([lt, tk + 1.3, 0.26])  # the flight and the hit, slowly
			else:
				var watcher := by if by >= 0 and by != victim else victim
				_add_shot("chase", cs, tk - 0.7, {"car": watcher})
				_add_shot("trackside", tk - 0.7, tk + 1.4, {"car": victim, "pos": pos, "others": rival, "key": tk})
				_add_shot("destruction", tk + 1.4, ce, {"car": victim, "pos": pos, "others": rival})
				_slow.append([tk - 0.2, tk + 1.0, 0.32])
		"wreck":
			_add_shot("chase", cs, tk - 0.8, {"car": victim})
			_add_shot("trackside", tk - 0.8, tk + 1.3, {"car": victim, "pos": pos, "key": tk})
			_add_shot("destruction", tk + 1.3, ce, {"car": victim, "pos": pos})
			_slow.append([tk - 0.2, tk + 1.0, 0.32])
		"pileup":
			_add_shot("chase", cs, tk - 1.4, {"car": victim})
			var pile := _others(e.get("cars", []) as Array, victim)
			_add_shot("trackside", tk - 1.4, tk + 1.6, {"car": victim, "pos": pos, "others": pile, "key": tk})
			_add_shot("destruction", tk + 1.6, ce, {"car": victim, "pos": pos, "others": pile})
			_slow.append([tk - 0.4, tk + 0.8, 0.4])
		"overtake":
			if bool(e.get("final", false)):
				_add_shot("chase", cs, tk - 1.1, {"car": by})
				_add_shot("trackside", tk - 1.1, ce, {"car": by, "pos": pos, "low": true, "ahead": 1.0, "others": _others([victim], by), "key": tk})
				_slow.append([tk - 0.3, tk + 0.5, 0.45])
			elif bool(e.get("corner", false)):
				_add_shot("chase", cs, tk - 1.0, {"car": victim})
				_add_shot("sweep", tk - 1.0, ce, {"car": by, "other": victim})
			else:
				_add_shot("chase", cs, tk - 0.6, {"car": victim})
				_add_shot("trackside", tk - 0.6, ce, {"car": by, "pos": pos, "others": _others([victim], by), "key": tk})
		"finish":
			var line: Vector2 = main.track.checkpoint_transform(0).origin if main.get("track") != null else pos
			_add_shot("chase", cs, tk - 1.3, {"car": victim})
			_add_shot("trackside", tk - 1.3, ce, {"car": victim, "pos": line, "low": true, "fixed_look": true, "key": tk})
			_slow.append([tk - 0.45, tk + 0.35, 0.22])
		"taunt":
			_add_shot("chase", cs, tk - 0.5, {"car": victim})
			_add_shot("side", tk - 0.5, tk + 1.1, {"car": by})
			_add_shot("chase", tk + 1.1, ce, {"car": victim, "low": true})
			_slow.append([tk - 0.1, tk + 0.9, 0.5])
		"air":
			var dur := float(e.get("dur", 0.8))
			_add_shot("chase", cs, tk - dur - 0.4, {"car": victim})
			_add_shot("trackside", tk - dur - 0.4, ce, {"car": victim, "pos": pos, "low": true, "key": tk - dur * 0.5})
			_slow.append([tk - dur, tk - 0.1, 0.45])
		_:
			_add_shot("chase", cs, tk - 0.5, {"car": maxi(victim, 0)})
			_add_shot("trackside", tk - 0.5, ce, {"car": maxi(victim, 0), "pos": pos, "others": _others([by], maxi(victim, 0)), "key": tk})


## Valid car ids from `ids`, without `except`.
func _others(ids: Array, except: int) -> Array:
	var out: Array = []
	for v in ids:
		var i := int(v)
		if i >= 0 and i < _cars.size() and i != except and not out.has(i):
			out.append(i)
	return out


func _add_shot(type: String, from: float, to: float, params: Dictionary) -> void:
	if to - from < 0.35 and not _shots.is_empty() and type != "missile" and type != "mine":
		_shots[-1][2] = to  # too short to cut to: the previous shot runs on
		return
	_shots.append([type, from, to, params])


func _focus_car() -> int:
	if _shot >= 0 and _shot < _shots.size():
		return int(_shots[_shot][3].get("car", -1))
	return -1


func _car_pos(i: int) -> Vector3:
	return (_cars[i].root as Node3D).position if i >= 0 and i < _cars.size() else Vector3.ZERO


func _car_fwd(i: int) -> Vector3:
	var yaw := (_cars[i].root as Node3D).rotation.y if i >= 0 and i < _cars.size() else 0.0
	return Vector3(cos(-yaw), 0.0, sin(-yaw))


func _missile_at(rid: int) -> Array:
	var c: Dictionary = clips[_clip]
	var samples: Array = c.samples
	var ia := _index(samples, _tau)
	var ma: PackedFloat32Array = samples[ia][2]
	for q in ma.size() / 6:
		if int(ma[q * 6]) == rid:
			var pos := Vector2(ma[q * 6 + 2], ma[q * 6 + 3])
			for k in _missiles.size():
				if _missiles[k].visible and Vector2(_missiles[k].position.x, _missiles[k].position.z).distance_to(pos * Vox.PX) < 1.2:
					return [_missiles[k].position, Vector3(cos(ma[q * 6 + 4]), 0.0, sin(ma[q * 6 + 4]))]
			return [Vox.to3(pos, 10.0), Vector3(cos(ma[q * 6 + 4]), 0.0, sin(ma[q * 6 + 4]))]
	return []


## The track's direction near a 2D point (from the centreline).
func _track_dir(p: Vector2) -> Vector2:
	var cl: PackedVector2Array = main.track.centerline if main.get("track") != null else PackedVector2Array()
	if cl.size() < 3:
		return Vector2.RIGHT
	var best := 0
	var bd := INF
	for k in cl.size():
		var d2 := p.distance_squared_to(cl[k])
		if d2 < bd:
			bd = d2
			best = k
	return (cl[(best + 2) % cl.size()] - cl[(best - 2 + cl.size()) % cl.size()]).normalized()


func _direct(c: Dictionary, delta: float) -> void:
	var s := _shot
	while _shot + 1 < _shots.size() and _tau >= float(_shots[_shot + 1][1]):
		_shot += 1
	if _shot < 0:
		_shot = 0
	if _shot != s:
		_cut = true
		_shot_clock = 0.0
		_cam_label.text = _cam_name(String(_shots[_shot][0]))
	if _cut:
		_view.restore_all()  # the last shot's tidying comes back
		_probe_left = 0.0
		_clear_for = 0.0
		_dodge_want = Vector3.ZERO
	_shot_clock += delta
	var shot: Array = _shots[_shot]
	var type := String(shot[0])
	var prm: Dictionary = shot[3]
	var car := int(prm.get("car", -1))
	var want_pos := _cam_pos
	var want_look := _cam_look
	var fov := 60.0
	var smooth := 7.0
	match type:
		"chase":
			var p := _car_pos(car)
			var f := _car_fwd(car)
			var low := bool(prm.get("low", false))
			want_pos = p - f * (4.6 if low else 5.6) + Vector3(0, 1.2 if low else 2.1, 0)
			want_look = p + f * 4.0 + Vector3(0, 0.3, 0)
			fov = 58.0
			smooth = 5.0
		"missile":
			var m := _missile_at(int(prm.rid))
			if not m.is_empty():
				var mp: Vector3 = m[0]
				var md: Vector3 = m[1]
				want_pos = mp - md * 1.5 + Vector3(0, 0.42, 0)
				want_look = mp + md * 8.0 - Vector3(0, 0.25, 0)
				smooth = 30.0
				# P007: close to its target the lens peels off to one side and
				# watches the hit (instead of flying on into the car's bodywork)
				if car >= 0 and car < _cars.size() and not prm.has("watch"):
					var vp := _car_pos(car) + Vector3(0, 0.5 * _car_scale(car), 0)
					if want_pos.distance_to(vp) < _car_r(car) + 3.2:
						var side := Vector3(-md.z, 0.0, md.x)
						prm["watch"] = mp.lerp(vp, 0.5) - md * 1.2 + side * (_car_r(car) + 2.6) + Vector3(0, 1.5, 0)
			else:
				want_look = _car_pos(car) + Vector3(0, 0.4, 0)
			if prm.has("watch"):
				want_pos = prm.watch
				want_look = _car_pos(car) + Vector3(0, 0.45 * _car_scale(car), 0)
				smooth = 10.0
			fov = 70.0
		"mine":
			var mp := _ground3(prm.pos)
			if _cut:
				prm["cam"] = _mine_spot(prm, shot)
			want_pos = prm.cam
			want_look = mp.lerp(_car_pos(car), 0.55) + Vector3(0, 0.35, 0)
			fov = 62.0
			smooth = 9.0
		"trackside":
			if _cut:
				_trackside_spot(prm, shot)
			want_pos = prm.cam
			if bool(prm.get("fixed_look", false)):
				want_look = (prm.anchor3 as Vector3).lerp(_car_pos(car) + Vector3(0, 0.4, 0), 0.35)
			else:
				want_look = _car_pos(car) + Vector3(0, 0.4, 0)
			fov = 42.0
			smooth = 8.0
		"sweep":
			var a := _car_pos(car)
			var b := _car_pos(int(prm.get("other", car)))
			var mid := (a + b) * 0.5
			var f := _car_fwd(car)
			var side := Vector3(-f.z, 0, f.x)
			var dur := maxf(0.5, float(shot[2]) - float(shot[1]))
			var k := clampf((_tau - float(shot[1])) / dur, 0.0, 1.0)
			var ang := lerpf(PI * 0.92, PI * 0.42, smoothstep(0.0, 1.0, k))
			want_pos = mid + (f * cos(ang) + side * sin(ang)) * 6.2 + Vector3(0, 1.9, 0)
			want_look = mid + f * 1.0 + Vector3(0, 0.4, 0)
			fov = 55.0
			smooth = 6.0
		"side":
			var p := _car_pos(car)
			var f := _car_fwd(car)
			var right := Vector3(-f.z, 0, f.x)
			var sgn := 1.0 if int(prm.get("sgn", 1)) > 0 else -1.0
			want_pos = p + right * 4.2 * sgn + f * 1.6 + Vector3(0, 1.4, 0)
			want_look = p + f * 0.2 + Vector3(0, 0.6, 0)
			fov = 50.0
			smooth = 9.0
		"destruction":
			var centre: Vector3
			if _cut:
				_destruction_spot(prm, shot)
			centre = prm.centre
			var a := float(prm.a0) + _shot_clock * 0.32
			want_pos = centre + Vector3(cos(a), 0, sin(a)) * float(prm.rad) + Vector3(0, float(prm.h), 0)
			want_look = centre
			fov = 50.0
			smooth = 4.0
	# keep the camera above the ground
	var g := stage.vtrack.height_px_at(Vector2(want_pos.x, want_pos.z) / Vox.PX) * Vox.PX if stage.vtrack != null else 0.0
	want_pos.y = maxf(want_pos.y, g + 0.35)
	# P007: nothing between the lens and the moment, the cars involved in frame
	var subj := _subjects(type, prm)
	var movers := _movers(car, -1.0)
	want_pos = _clear_view(want_pos, want_look, fov, subj, movers, delta, type != "missile" or prm.has("watch"))
	var fit := _frame(type, prm, want_pos, want_look, fov)
	want_look = fit[0]
	fov = fit[1]
	if _cut:
		_cam_pos = want_pos
		_cam_look = want_look
		_cam_fov = fov
		_cut = false
	else:
		var k := 1.0 - exp(-delta * smooth)
		_cam_pos = _cam_pos.lerp(want_pos, k)
		_cam_look = _cam_look.lerp(want_look, 1.0 - exp(-delta * smooth * 1.6))
		_cam_fov = lerpf(_cam_fov, fov, k)
	cam.position = _cam_pos
	if _cam_pos.distance_to(_cam_look) > 0.01:
		cam.look_at(_cam_look, Vector3.UP)
	cam.fov = _cam_fov
	_focus = Vector2(_cam_look.x, _cam_look.z) / Vox.PX


# ------------------------------------------------------------ a clear view (P007)

## Where a car was at replay time t (from the recorded samples), and its
## heading; [] while it was not on the track.
func _car_at(i: int, t: float) -> Array:
	if i < 0 or i >= _cars.size() or _clip < 0:
		return []
	var samples: Array = clips[_clip].samples
	var ia := _index(samples, t)
	var ib := mini(ia + 1, samples.size() - 1)
	var ta := float(samples[ia][0])
	var tb := float(samples[ib][0])
	var u := clampf((t - ta) / (tb - ta), 0.0, 1.0) if tb > ta else 0.0
	var ca: PackedFloat32Array = samples[ia][1]
	var cb: PackedFloat32Array = samples[ib][1]
	var o := i * ReplayRecorder.K
	if (int(ca[o + 9]) & ReplayRecorder.F_VISIBLE) == 0:
		return []
	var pa := Vector3(ca[o], ca[o + 1], ca[o + 2])
	var pb := Vector3(cb[o], cb[o + 1], cb[o + 2])
	var yaw := lerp_angle(ca[o + 3], cb[o + 3], u)
	return [pa if pa.distance_to(pb) > 4.0 else pa.lerp(pb, u), Vector3(cos(-yaw), 0.0, sin(-yaw))]


## [box, id] round every car but the shot's own (live, or at replay time
## t >= 0): they block the view like a wall, so the camera moves round them.
## (The other car of the moment too - but never the view of itself.)
func _movers(skip: int, t: float) -> Array:
	var out: Array = []
	for i in _cars.size():
		if i == skip:
			continue
		var p: Vector3
		if t < 0.0:
			if not (_cars[i].root as Node3D).visible:
				continue
			p = _car_pos(i)
		else:
			var at := _car_at(i, t)
			if at.is_empty():
				continue
			p = at[0]
		var s := _car_scale(i)
		var body: MeshInstance3D = _cars[i].body
		var h := (body.mesh.get_aabb().size.y if body.mesh != null else 1.0) * s
		var r := _car_r(i) * 0.7
		out.append([AABB(p - Vector3(r, 0.0, r), Vector3(r * 2.0, h, r * 2.0)), i])
	return out


func _car_scale(i: int) -> float:
	return maxf((_cars[i].root as Node3D).scale.x, 0.2) if i >= 0 and i < _cars.size() else 1.0


## Rough radius of a car (half its length).
func _car_r(i: int) -> float:
	if i < 0 or i >= _cars.size():
		return 1.0
	var body: MeshInstance3D = _cars[i].body
	var r := body.mesh.get_aabb().size.x * 0.5 if body.mesh != null else 1.2
	return clampf(r, 0.6, 2.5) * _car_scale(i)


## Sight-line targets on a car: [point, weight] (its middle, roof, nose, tail).
func _car_pts(i: int, p: Vector3, fwd: Vector3, w: float, out: Array) -> void:
	if i < 0 or i >= _cars.size():
		return
	var s := _car_scale(i)
	var half := _car_r(i) * 0.8
	out.append([p + Vector3(0, 0.45 * s, 0), w, i])
	out.append([p + Vector3(0, 0.85 * s, 0), w * 0.5, i])
	out.append([p + fwd * half + Vector3(0, 0.4 * s, 0), w * 0.2, i])
	out.append([p - fwd * half + Vector3(0, 0.4 * s, 0), w * 0.2, i])


func _live_car_pts(i: int, w: float, out: Array) -> void:
	if i >= 0 and i < _cars.size() and (_cars[i].root as Node3D).visible:
		_car_pts(i, _car_pos(i), _car_fwd(i), w, out)


## What the running shot must see: [point, weight], the main subject first.
func _subjects(type: String, prm: Dictionary) -> Array:
	var out: Array = []
	var car := int(prm.get("car", -1))
	match type:
		"missile":
			var m := _missile_at(int(prm.get("rid", -1)))
			if not m.is_empty():
				out.append([m[0], 1.0])
			_live_car_pts(car, 0.5, out)
		"mine":
			out.append([_ground3(prm.pos) + Vector3(0, 0.15, 0), 1.0])
			_live_car_pts(car, 1.0, out)
		"destruction":
			out.append([prm.centre, 1.0])
			_live_car_pts(car, 0.7, out)
			for o in prm.get("others", []):
				if _car_pos(int(o)).distance_to(prm.centre) < 10.0:
					_live_car_pts(int(o), 0.35, out)
		"sweep":
			_live_car_pts(car, 1.0, out)
			_live_car_pts(int(prm.get("other", car)), 0.8, out)
		_:
			_live_car_pts(car, 1.0, out)
			for o in prm.get("others", []):
				if _car_pos(int(o)).distance_to(_car_pos(car)) < 14.0:
					_live_car_pts(int(o), 0.4, out)
	return out


## The camera position with any dodge round big obstacles (smoothed), and
## the small clutter in the way tidied away. Re-checked every PROBE_EVERY.
func _clear_view(base: Vector3, look: Vector3, fov: float, subj: Array, movers: Array, delta: float, may_move: bool) -> Vector3:
	_probe_left -= delta
	if (_probe_left <= 0.0 or _cut) and not subj.is_empty():
		_probe_left = PROBE_EVERY
		if may_move:
			var here: Dictionary = _view.probe(base, subj, look, fov, false, movers)
			if float(here.cost) < 0.5:
				_clear_for += PROBE_EVERY
				if _clear_for > 0.45 or _cut:
					_dodge_want = Vector3.ZERO  # clear again: ease back to the shot's own spot
			else:
				_clear_for = 0.0
				var keep := _dodge_want != Vector3.ZERO \
					and float(_view.probe(base + _dodge_want, subj, look, fov, false, movers).cost) < 0.5
				if not keep:
					_dodge_want = _best_dodge(base, look, fov, subj, movers, float(here.cost))
		var eye := base + (_dodge_want if _cut else _dodge)
		_view.hide_items(_view.probe(eye, subj, look, fov, true).small)
	if _cut:
		_dodge = _dodge_want
	else:
		_dodge = _dodge.lerp(_dodge_want, 1.0 - exp(-delta * 3.0))
	return base + _dodge


## A nearby camera position that sees past something big: in closer, a
## little higher, or both (as low and close to the shot's own as works).
func _best_dodge(base: Vector3, look: Vector3, fov: float, subj: Array, movers: Array, base_cost: float) -> Vector3:
	var c: Vector3 = subj[0][0]
	var back := base - c
	var best := Vector3.ZERO
	var best_cost := base_cost
	for o in [[back * 0.62, 0.15], [back + Vector3(0, 1.2, 0), 0.2], [back * 0.62 + Vector3(0, 0.9, 0), 0.25],
			[back * 0.42 + Vector3(0, 0.6, 0), 0.35], [back + Vector3(0, 2.6, 0), 0.4], [back * 0.8 + Vector3(0, 4.2, 0), 0.6]]:
		var p: Vector3 = c + (o[0] as Vector3)
		if p.distance_to(c) < 1.8:
			continue
		p.y = maxf(p.y, _ground_y(p) + 0.35)
		var cost := float(_view.probe(p, subj, look, fov, false, movers).cost) + float(o[1])
		if cost < best_cost:
			best_cost = cost
			best = p - base
	return best


func _ground_y(p: Vector3) -> float:
	return stage.vtrack.height_px_at(Vector2(p.x, p.z) / Vox.PX) * Vox.PX if stage.vtrack != null else 0.0


## The subjects of a fixed camera at a few moments of its shot, from the
## recording: [[[point, weight], ...], moment weight].
func _moments(car: int, others: Array, from: float, to: float, key: float, extra: Array = []) -> Array:
	var times: Array = []
	if key > from and key < to:
		times = [[from + (key - from) * 0.25, 0.4], [key - 0.3, 0.8], [key, 1.0], [key + 0.35, 0.8], [to - 0.1, 0.4]]
	else:
		var d := to - from
		times = [[from + d * 0.15, 0.5], [from + d * 0.4, 1.0], [from + d * 0.65, 1.0], [from + d * 0.9, 0.6]]
	var out: Array = []
	for tw in times:
		var t := clampf(float(tw[0]), from, to)
		var pts: Array = extra.duplicate()
		var at := _car_at(car, t)
		if not at.is_empty():
			_car_pts(car, at[0], at[1], 1.0, pts)
			for o in others:
				var ot := _car_at(int(o), t)
				if not ot.is_empty() and (ot[0] as Vector3).distance_to(at[0]) < 14.0:
					_car_pts(int(o), ot[0], ot[1], 0.4, pts)
		if not pts.is_empty():
			out.append([pts, float(tw[1]), t])
	return out


## The best of some fixed camera positions ([eye, penalty], the shot's own
## first) for the whole of a shot; its clutter is tidied away at once.
func _pick(cands: Array, moments: Array, fov: float, car: int) -> Vector3:
	cands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) < float(b[1]))
	var movers: Array = []
	for m in moments:
		movers.append(_movers(car, float(m[2])))
	var best: Vector3 = cands[0][0]
	var best_total := INF
	var best_small: Array = []
	for cd in cands:
		if float(cd[1]) >= best_total:
			break  # (sorted: nothing further can do better)
		var eye: Vector3 = cd[0]
		eye.y = maxf(eye.y, _ground_y(eye) + 0.35)
		var total := float(cd[1])
		var small: Array = []
		for k in moments.size():
			var m: Array = moments[k]
			var pts: Array = m[0]
			var r: Dictionary = _view.probe(eye, pts, pts[0][0], fov, true, movers[k])
			# (all that clutter to tidy away: a spot with a natural clear view is better)
			total += (float(r.cost) + 0.02 * (r.small as Array).size()) * float(m[1])
			small.append_array(r.small)
			if total >= best_total:
				break
		if total < best_total:
			best_total = total
			best = eye
			best_small = small
	_view.hide_items(best_small)
	return best


## Trackside: a spot beside the road that sees the cars come past and the
## moment itself; low where it can be.
func _trackside_spot(prm: Dictionary, shot: Array) -> void:
	var anchor: Vector2 = prm.pos
	var tdir := _track_dir(anchor)
	var side := Vector2(-tdir.y, tdir.x)
	var car := int(prm.get("car", -1))
	var cp := _car_pos(car)
	if side.dot(Vector2(cp.x, cp.z) / Vox.PX - anchor) > 0.0:
		side = -side  # stand on the far side from the car: see it come past
	var ahead := float(prm.get("ahead", 0.5))
	var low := bool(prm.get("low", false))
	var dist := 150.0 if low else 210.0
	var h := 0.9 if low else 2.2
	var cands: Array = []
	# [distance scale, extra height, extra ahead, penalty]
	for v in [[1.0, 0.0, 0.0, 0.0], [0.72, 0.0, 0.0, 0.12], [1.0, 0.6, 0.0, 0.15], [1.0, 0.0, 0.6, 0.15],
			[1.0, 0.0, -0.6, 0.2], [0.72, 0.6, 0.0, 0.25], [0.55, 1.0, 0.0, 0.35], [1.0, 1.5, 0.0, 0.4],
			[1.35, 0.7, 0.0, 0.3], [0.8, 1.2, 0.7, 0.45], [1.25, 2.6, 0.0, 0.6], [0.8, 3.4, 0.4, 0.8]]:
		for sg in [1.0, -1.0]:
			var spot: Vector2 = anchor + side * sg * dist * float(v[0]) + tdir * 120.0 * (ahead + float(v[2]))
			cands.append([_ground3(spot) + Vector3(0, h + float(v[1]), 0), float(v[3]) + (0.0 if sg > 0.0 else 0.3)])
	var key := float(prm.get("key", -1.0))
	prm["cam"] = _pick(cands, _moments(car, prm.get("others", []), float(shot[1]), float(shot[2]), key), 42.0, car)
	prm["anchor3"] = _ground3(anchor) + Vector3(0, 0.4, 0)


## Destruction: where the orbit starts, how far out and how high, so the
## wreck stays in view for the whole orbit.
func _destruction_spot(prm: Dictionary, shot: Array) -> void:
	var car := int(prm.get("car", -1))
	var centre := _car_pos(car) + Vector3(0, 0.5, 0)
	prm["centre"] = centre
	var f := _car_fwd(car)
	var a0 := atan2(f.z, f.x) + PI * 0.55
	var from := float(shot[1])
	var to := float(shot[2])
	var spin := clampf(to - from, 1.0, 5.0) * 1.3 * 0.32  # (how far it turns in the shot)
	var best := [a0, 7.2, 3.0]
	var best_total := INF
	var best_small: Array = []
	var cands: Array = []
	for da in [[0.0, 0.0], [0.55, 0.1], [-0.55, 0.1], [1.1, 0.2], [-1.1, 0.2], [1.8, 0.3], [-1.8, 0.3], [PI, 0.35]]:
		for rh in [[7.2, 3.0, 0.0], [5.6, 2.6, 0.12], [7.2, 4.6, 0.45], [5.0, 5.2, 0.7]]:
			cands.append([a0 + float(da[0]), float(rh[0]), float(rh[1]), float(da[1]) + float(rh[2])])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[3]) < float(b[3]))
	var movers: Array = []
	for k in 3:
		movers.append(_movers(car, lerpf(from, to, k * 0.5)))
	for cd in cands:
		if float(cd[3]) >= best_total:
			break
		var total := float(cd[3])
		var small: Array = []
		for k in 3:
			var a := float(cd[0]) + spin * k * 0.5
			var eye := centre + Vector3(cos(a), 0, sin(a)) * float(cd[1]) + Vector3(0, float(cd[2]), 0)
			eye.y = maxf(eye.y, _ground_y(eye) + 0.35)
			var pts: Array = [[centre, 1.0]]
			var at := _car_at(car, lerpf(from, to, k * 0.5))
			if not at.is_empty():
				_car_pts(car, at[0], at[1], 0.6, pts)
			var r: Dictionary = _view.probe(eye, pts, centre, 50.0, false, movers[k])
			total += float(r.cost) * (1.0 if k == 0 else 0.7)
			small.append_array(r.small)
			if total >= best_total:
				break
		if total < best_total:
			best_total = total
			best = [cd[0], cd[1], cd[2]]
			best_small = small
	prm["a0"] = best[0]
	prm["rad"] = best[1]
	prm["h"] = best[2]
	_view.hide_items(best_small)


## Mine: low beside the mine, looking back at the car that will find it.
func _mine_spot(prm: Dictionary, shot: Array) -> Vector3:
	var car := int(prm.get("car", -1))
	var mp := _ground3(prm.pos)
	var approach: Vector3 = mp - _car_pos(car)
	approach.y = 0.0
	approach = approach.normalized() if approach.length() > 0.1 else Vector3.RIGHT
	var cands: Array = []
	for rot in [[0.0, 0.0], [0.45, 0.15], [-0.45, 0.15], [0.9, 0.3], [-0.9, 0.3]]:
		var ap := approach.rotated(Vector3.UP, float(rot[0]))
		var side := Vector3(-ap.z, 0, ap.x)
		for sd in [[0.7, 0.0], [-0.7, 0.1]]:
			for hh in [[2.6, 0.45, 0.0], [2.0, 0.8, 0.15], [2.6, 1.3, 0.3]]:
				cands.append([mp + ap * float(hh[0]) + side * float(sd[0]) + Vector3(0, float(hh[1]), 0),
					float(rot[1]) + float(sd[1]) + float(hh[2])])
	var from := float(shot[1])
	var to := float(shot[2])
	var key := to - 1.0  # (the shot runs a second past the blast)
	return _pick(cands, _moments(car, [], from, to, key, [[mp + Vector3(0, 0.15, 0), 1.0]]), 62.0, car)


## Look and field of view that keep the moment in frame with a margin (inside
## the letterbox): the main subject always, the other car where it fits.
func _frame(type: String, prm: Dictionary, eye: Vector3, look: Vector3, fov: float) -> Array:
	var car := int(prm.get("car", -1))
	var prim: Array = []
	var sec: Array = []
	var max_fov := fov
	var near := 14.0
	match type:
		"trackside":
			max_fov = 60.0
		"destruction":
			prim.append([prm.centre, 1.3])
			max_fov = 68.0
			near = 9.0
		"mine":
			prim.append([_ground3(prm.pos) + Vector3(0, 0.15, 0), 0.5])
			max_fov = 74.0
		"sweep":
			var o := int(prm.get("other", car))
			if o != car and o >= 0 and (_cars[o].root as Node3D).visible:
				prim.append([_car_pos(o) + Vector3(0, 0.4, 0), _car_r(o)])
			max_fov = 68.0
		_:
			return [look, fov]
	if car >= 0 and car < _cars.size() and (_cars[car].root as Node3D).visible:
		prim.append([_car_pos(car) + Vector3(0, 0.4, 0), _car_r(car)])
	if prim.is_empty():
		return [look, fov]
	var c0: Vector3 = prim[0][0]
	var mid := Vector3.ZERO
	var wsum := 0.0
	for pr in prim:
		mid += (pr[0] as Vector3)
		wsum += 1.0
	for o in prm.get("others", []):
		var i := int(o)
		if i < 0 or i >= _cars.size() or not (_cars[i].root as Node3D).visible:
			continue
		var op := _car_pos(i) + Vector3(0, 0.4, 0)
		var w := 1.0 - smoothstep(near * 0.6, near, op.distance_to(c0))
		if w <= 0.0:
			continue
		mid += op * 0.5 * w
		wsum += 0.5 * w
		if w > 0.5:
			sec.append([op, _car_r(i)])
	mid /= wsum
	# lean the look towards the middle of everyone involved
	if not sec.is_empty() or prim.size() > 1:
		look = look.lerp(mid, 0.5)
	var need := _need_fov(eye, look, prim + sec)
	if need > max_fov and not sec.is_empty():
		need = _need_fov(eye, look, prim)
	if need > max_fov:
		look = look.lerp(mid, 0.5)  # (too wide even so: centre on them)
		need = _need_fov(eye, look, prim)
	return [look, clampf(need, fov, max_fov)]


## The vertical field of view (degrees) that shows every [point, radius]
## inside the letterbox with a margin, looking from eye at look.
func _need_fov(eye: Vector3, look: Vector3, pts: Array) -> float:
	var f := look - eye
	if f.length() < 0.01:
		return 0.0
	f = f.normalized()
	var r := f.cross(Vector3.UP)
	r = r.normalized() if r.length() > 0.01 else Vector3.RIGHT
	var u := r.cross(f)
	var vis := float(720 - 2 * LETTERBOX) / 720.0 * 0.86  # (the bars, and a margin)
	var tv := 0.0
	for pr in pts:
		var v: Vector3 = (pr[0] as Vector3) - eye
		var z := v.dot(f)
		if z < 0.4:
			return 180.0
		var x := (absf(v.dot(r)) + float(pr[1])) / z
		var y := (absf(v.dot(u)) + float(pr[1])) / z
		tv = maxf(tv, maxf(y / vis, x / (16.0 / 9.0 * 0.86)))
	return rad_to_deg(2.0 * atan(tv))


## The race HUD and its overlays (kill feed, popups, stage hints) are hidden
## while the highlights play; the replay's own titles stay.
func _overlays_on(on: bool) -> void:
	if on:
		for n in _overlays:
			if is_instance_valid(n):
				(n as CanvasLayer).visible = true
		_overlays.clear()
		return
	var list: Array = [main.get("hud"), main.get("kill_feed"), main.get("defeat_popup")]
	var hint = stage.get("_hint")
	if hint is Node and is_instance_valid(hint) and (hint as Node).get_parent() is CanvasLayer:
		list.append((hint as Node).get_parent())
	for n in list:
		if n is CanvasLayer and is_instance_valid(n) and (n as CanvasLayer).visible:
			(n as CanvasLayer).visible = false
			_overlays.append(n)


static func _cam_name(type: String) -> String:
	return {"chase": "CHASE CAM", "missile": "MISSILE CAM", "mine": "MINE CAM", "trackside": "TRACKSIDE",
		"sweep": "SWEEP CAM", "side": "SIDE CAM", "destruction": "DESTRUCTION CAM"}.get(type, "REPLAY")


# ------------------------------------------------------------ environment

func _env_on(on: bool) -> void:
	var e: Environment = stage.world_env.environment
	if on:
		_saved_env = {"bg": e.background_color, "fog": e.fog_enabled}
		var night: bool = main.lighting != null and main.lighting.enabled
		var haze := Color(0.04, 0.05, 0.09) if night else Color(0.62, 0.74, 0.86)
		e.background_color = haze
		e.fog_enabled = true
		e.fog_mode = Environment.FOG_MODE_DEPTH
		e.fog_light_color = haze
		e.fog_light_energy = 1.0
		e.fog_density = 1.0
		e.fog_depth_begin = 55.0
		e.fog_depth_end = 150.0
		e.fog_sky_affect = 1.0
	elif not _saved_env.is_empty():
		e.background_color = _saved_env.bg
		e.fog_enabled = _saved_env.fog


# ------------------------------------------------------------ overlay

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 60
	_ui.visible = false
	add_child(_ui)
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = VrStyle.INK
		bar.size = Vector2(1280, LETTERBOX)
		bar.position = Vector2(0, 0 if top else 720 - LETTERBOX)
		_ui.add_child(bar)
		_bars.append(bar)
	_wipe = ColorRect.new()
	_wipe.color = Color(1.0, 0.98, 0.92)
	_wipe.size = Vector2(1280, 720)
	_wipe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wipe.modulate.a = 0.0
	_ui.add_child(_wipe)
	_rec = ColorRect.new()
	_rec.color = VrStyle.RED
	_rec.size = Vector2(16, 16)
	_rec.position = Vector2(30, 24)
	_ui.add_child(_rec)
	var tag := _label("ACTION REPLAY", 24, VrStyle.PAPER, "bold")
	tag.position = Vector2(56, 16)
	_ui.add_child(tag)
	_count = _label("", 16, VrStyle.PAPER_DIM, "regular")
	_count.position = Vector2(270, 22)
	_ui.add_child(_count)
	_cam_label = _label("", 16, VrStyle.YELLOW, "bold")
	_cam_label.position = Vector2(1000, 22)
	_cam_label.size = Vector2(252, 24)
	_cam_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ui.add_child(_cam_label)
	_title = _label("", 32, VrStyle.YELLOW, "bold")
	_title.position = Vector2(48, 720 - LETTERBOX - 86)
	_title.add_theme_color_override("font_outline_color", VrStyle.INK)
	_title.add_theme_constant_override("outline_size", 8)
	_ui.add_child(_title)
	_sub = _label("", 16, VrStyle.PAPER, "bold")
	_sub.position = Vector2(50, 720 - LETTERBOX - 44)
	_sub.add_theme_color_override("font_outline_color", VrStyle.INK)
	_sub.add_theme_constant_override("outline_size", 6)
	_ui.add_child(_sub)
	_slowmo = _label("SLOW-MO", 16, VrStyle.TEAL, "bold")
	_slowmo.position = Vector2(1140, 80)
	_slowmo.add_theme_color_override("font_outline_color", VrStyle.INK)
	_slowmo.add_theme_constant_override("outline_size", 6)
	_ui.add_child(_slowmo)
	_hints = _label("", 16, VrStyle.PAPER_DIM, "regular")
	_hints.position = Vector2(0, 720 - LETTERBOX + 22)
	_hints.size = Vector2(1240, 24)
	_hints.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ui.add_child(_hints)


func _label(text: String, size: int, color: Color, kind: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", VrStyle.font(kind))
	l.add_theme_font_size_override("font_size", VrStyle.px(size))
	l.add_theme_color_override("font_color", color)
	return l


func _show_titles(c: Dictionary) -> void:
	var t := moment_titles(c.key, recorder.names)
	# the moment's main actor's colour for the headline (P004)
	var actor := int(c.key.get("by", -1))
	if actor < 0:
		actor = int(c.key.get("car", -1))
	var col := VrStyle.YELLOW
	if actor >= 0:
		col = (VoxelStage.HELMETS[actor % VoxelStage.HELMETS.size()] as Color).lightened(0.15)
	_title.add_theme_color_override("font_color", col)
	# a flash and a whoosh between moments
	_wipe.modulate.a = 0.85
	create_tween().tween_property(_wipe, "modulate:a", 0.0, 0.28)
	SoundKit.play(self, "whoosh", -10.0, 0.05)
	_title.text = t[0]
	_sub.text = t[1]
	_title.modulate.a = 1.0
	_sub.modulate.a = 1.0
	_ui_time = 0.0
	_count.text = "%d / %d" % [_clip + 1, clips.size()]
	_hints.text = PlayerControls.fmt("{confirm} / {fire}: next      {back}: skip all")


func _update_ui(_delta: float) -> void:
	_rec.visible = fmod(_ui_time, 1.0) < 0.6
	var fade := clampf((TITLE_HOLD + 1.0 - _ui_time), 0.0, 1.0)
	_title.modulate.a = fade
	_sub.modulate.a = fade
	_slowmo.visible = _rate < 0.7


## Headline and line beneath for a moment.
static func moment_titles(e: Dictionary, names: PackedStringArray) -> Array:
	var car := int(e.get("car", -1))
	var by := int(e.get("by", -1))
	var victim := names[car] if car >= 0 and car < names.size() else ""
	var hunter := names[by] if by >= 0 and by < names.size() else ""
	var weapon: String = {W.FRONT_MISSILE: "MISSILE", W.REAR_MISSILE: "REAR MISSILE", W.HOMING_MISSILE: "HOMING MISSILE",
		W.SUPER_MISSILE: "SUPER MISSILE", W.MINE: "MINE"}.get(int(e.get("type", -1)), "")
	match String(e.kind):
		"destroyed":
			if by == car or hunter.is_empty():
				return ["OWN GOAL!", "%s FALLS TO THEIR OWN %s" % [victim, weapon]]
			return ["%s TAKES OUT %s" % [hunter, victim], weapon if not weapon.is_empty() else "KNOCKOUT"]
		"hit":
			return ["%s TAGS %s" % [hunter, victim], weapon]
		"wreck":
			return ["%s IS WRECKED" % victim, "ONE BLOW TOO MANY"]
		"pileup":
			return ["PILE-UP!", "%d CARS IN THE MIX" % (e.get("cars", []) as Array).size()]
		"overtake":
			var line := "FOR P%d" % int(e.get("place", 0))
			if bool(e.get("final", false)):
				line = "FINAL LAP  -  " + line
			elif bool(e.get("corner", false)):
				line = "AROUND THE OUTSIDE  -  " + line
			return ["%s PASSES %s" % [hunter, victim], line]
		"finish":
			return ["PHOTO FINISH!" if float(e.get("gap", 1.0)) < 0.5 else "CLOSE FINISH!",
				"%s CROSSES THE LINE %.2f s BEHIND" % [victim, float(e.get("gap", 0.0))]]
		"taunt":
			return ["%s SAYS HI TO %s" % [hunter, victim], "COMPLIMENTS OF THE CAN"]
		"air":
			return ["%s CATCHES AIR" % victim, "%.1f SECONDS OF FLIGHT" % float(e.get("dur", 0.0))]
		"crash":
			return ["BIG HIT!", victim]
	return ["REPLAY", ""]
