class_name VoxelRaceFx
extends Node3D
## VoxelRacing: what a race does to its world, all in voxels. Reads the race
## (DamageWorld, CombatWorld, car signals, jumps) and never changes it.
##   * bodywork breaks off progressively with the car's condition, on the side
##     that was hit (VoxelCarDamage), and lies on the track as debris;
##   * a wrecked / retired car blows apart into chunks of its own colours,
##     with fire, sparks, smoke, a flash and a burn mark; a burnt hull is left
##     until the car respawns (then it is whole again);
##   * collisions throw voxel sparks and little voxel stars by their force;
##   * missiles and mines are voxel models; their blasts are voxel bursts
##     that scorch the road;
##   * wheel smoke, dust, landings and damage smoke are voxel puffs;
##   * cars driving through debris kick it about;
##   * a fresh race clears debris and burn marks.

const SCORCH_SIZE := 118.0
const MISSILE_SPEED_TRAIL := 0.05

var stage: VoxelStage
var fx: VoxelFx
var damage: Array[VoxelCarDamage] = []
var _main: Node2D
var _burns: Node2D
var _scorch_tex: Texture2D
var _last_dir: Array[Vector3] = []
var _last_hit_time := PackedFloat32Array()
var _was_wrecked := PackedByteArray()
var _was_air := PackedByteArray()
var _smoke_clock := PackedFloat32Array()
var _cursor := 0
var _race_number := -1
var _state := -1
var _time := 0.0
var _rng := RandomNumberGenerator.new()
var _missiles: Array[MeshInstance3D] = []
var _mines: Array[MeshInstance3D] = []
var _trail_clock := 0.0
var _rebuilds_left := 0
## Overtaking taunts (P003): how likely each driver is to throw a can at the
## car they just passed (index = racer id: the player never does). Scaled by
## TAUNT_SCALE for tuning.
const TAUNT_CHANCE := [0.0, 0.06, 0.55, 0.25, 0.18, 0.15, 0.6, 0.08, 0.45, 0.3]
const TAUNT_SCALE := 1.0
const TAUNT_TIME := 1.45
const TAUNT_GAP := 9.0
const TAUNT_COOLDOWN := 25.0
var _taunts: Array = []
var _taunt_cool := PackedFloat32Array()
var _taunt_last := -100.0
var cans: Array = []
## Backfire chance on a lift-off at speed, by racer id (show-offs pop more).
const BACKFIRE := [0.3, 0.12, 0.55, 0.25, 0.2, 0.15, 0.6, 0.1, 0.4, 0.3]
## Turbo spit (Audio Integration 001): anti-lag bangs when a car lifts off
## after a long pull - chance by racer id; these drivers' cars favour the
## anti-lag bangs over a plain backfire (Maya's turbo coupe, Dante's exotic,
## Greta's single-seater, Finn's rally car, Nina's supercar, a little for the
## player's GT). 0: never. Purely sound and sparks; nothing about the engine.
const TURBO_SPIT := [0.18, 0.0, 0.0, 0.0, 0.0, 0.45, 0.4, 0.3, 0.6, 0.45]
## Seconds of hard acceleration before a lift-off can spit, and the quiet
## time per car afterwards.
const SPIT_PULL := 1.1
const SPIT_COOLDOWN := 3.5
var _last_accel := PackedFloat32Array()
var _pull := PackedFloat32Array()
var _spit_ready := PackedFloat32Array()
## Pending anti-lag bangs: [time, car index].
var _spits: Array = []
## Own generator for the exhaust sounds (never the race's randomness).
var _ex_rng := RandomNumberGenerator.new()
const SoundKit := preload("res://src/audio/sound_kit.gd")
var _last_rattle := -10.0


## A procedural sound (SoundKit), quieter the further from the view's centre.
func _sound(name: String, at: Vector3, db: float, jitter: float = 0.08) -> void:
	if _main.get("race_audio") != null and _main.race_audio != null and _main.race_audio.fast:
		return  # (fast-forward / replay: the live race is quiet)
	var cam2: Camera2D = _main.camera
	var d := (Vector2(at.x, at.z) / Vox.PX).distance_to(cam2.get_screen_center_position())
	if d > 900.0:
		return
	SoundKit.play(self, name, db - d / 900.0 * 14.0, jitter)
signal backfired(i: int)


func setup(p_stage: VoxelStage) -> void:
	stage = p_stage
	_main = stage.main
	name = "RaceFx"
	_rng.seed = 41
	fx = VoxelFx.new()
	fx.name = "VoxelFx"
	add_child(fx)
	fx.ground = func(x: float, z: float) -> float:
		return stage.vtrack.height_px_at(Vector2(x, z) / Vox.PX) * Vox.PX if stage.vtrack != null and stage.vtrack.nx > 0 else 0.0
	_burns = Node2D.new()
	_burns.name = "BurnMarks"
	var decals := _main.get_node_or_null("Decals") as Node2D
	if decals != null:
		decals.add_child(_burns)
		decals.move_child(_burns, 0)  # under the tyre marks
	_burns.visibility_layer = VoxelStage.DECAL_LAYER
	_scorch_tex = _make_scorch()
	for i in stage.cars3d.size():
		var c: Car = _main.cars[i]
		var d: Dictionary = stage.cars3d[i]
		var dmg := VoxelCarDamage.new(d.model, d.body, 1000 + i)
		dmg.dirty = false  # the shared pristine mesh is already shown
		damage.append(dmg)
		_last_dir.append(Vector3.ZERO)
		c.wall_hit.connect(_on_wall_hit.bind(i))
		c.car_hit.connect(_on_car_hit.bind(i))
	_last_hit_time.resize(damage.size())
	_last_hit_time.fill(-10.0)
	_was_wrecked.resize(damage.size())
	_was_air.resize(damage.size())
	_smoke_clock.resize(damage.size())
	_last_accel.resize(damage.size())
	_pull.resize(damage.size())
	_spit_ready.resize(damage.size())
	_ex_rng.randomize()
	_taunt_cool.resize(damage.size())
	_taunt_cool.fill(-100.0)


## Called every frame by VoxelStage after the cars were placed.
func sync(delta: float) -> void:
	_time += delta
	_check_new_race()
	_read_combat_events()
	_rebuilds_left = 3
	for i in damage.size():
		_sync_car(i, delta)
	_sync_spits()
	_sync_weapons(delta)
	_sync_taunts(delta)
	step_cans(cans, delta, fx.ground)


# ------------------------------------------------------------ fresh races

func _check_new_race() -> void:
	var state: int = _main.session.state
	var n: int = _main.races_started
	var fresh := (n != _race_number) or (state == RaceSession.State.MODE_SELECT and _state != RaceSession.State.MODE_SELECT)
	_race_number = n
	_state = state
	if not fresh:
		return
	_spits.clear()
	fx.clear()
	for b in _burns.get_children():
		b.queue_free()
	for can in cans:
		(can.node as Node3D).queue_free()
	cans.clear()
	for tt in _taunts:
		stage.pose_head(stage.cars3d[tt.car], 0.0)
		stage.cars3d[tt.car].head = 0.0
	_taunts.clear()
	_taunt_cool.fill(-100.0)
	_taunt_last = -100.0
	for i in damage.size():
		if damage[i].loss() > 0.0 or damage[i].wrecked:
			damage[i].restore()
		_was_wrecked[i] = 0
		_set_wheels(i, true)


# ------------------------------------------------------------ cars

func _sync_car(i: int, delta: float) -> void:
	var c: Car = _main.cars[i]
	var d: Dictionary = stage.cars3d[i]
	var dmg := damage[i]
	var root: Node3D = d.root
	var combat: CombatWorld = _main.combat
	var dw: DamageWorld = _main.damage
	var wrecked := (combat != null and combat.enabled and combat.is_wrecked(i)) or (dw != null and dw.is_retired(i))
	if wrecked and _was_wrecked[i] == 0 and c.visible:
		_explode(i)
	elif not wrecked and _was_wrecked[i] == 1:
		dmg.restore(true)  # respawned: a fresh body, then the damage it still carries
		_set_wheels(i, true)
	_was_wrecked[i] = 1 if wrecked else 0
	if not wrecked and dw != null and c.visible:
		var target := VoxelCarDamage.target_loss(dw.fraction(i))
		if target < dmg.loss() - 0.03:  # repaired
			dmg.restore(true)
		if target > dmg.loss() + 0.003:
			var dir := _last_dir[i] if _time - _last_hit_time[i] < 0.6 else Vector3.ZERO
			var pieces := dmg.break_to(target, dir)
			_spawn_bits(i, pieces, dir)
	if dmg.dirty:
		dmg.rebuild()
	# smoke: heavy damage, and the burning wreck
	if c.visible and root.visible:
		var share: float = dw.fraction(i) if dw != null else 1.0
		var rate := 0.0
		if wrecked:
			rate = 9.0
		elif share < 0.5:
			rate = lerpf(1.5, 7.0, clampf((0.5 - share) / 0.4, 0.0, 1.0))
		_smoke_clock[i] += delta * rate
		while _smoke_clock[i] >= 1.0:
			_smoke_clock[i] -= 1.0
			var g := _rng.randf_range(0.12, 0.22) if wrecked or share < 0.25 else _rng.randf_range(0.42, 0.55)
			var at: Vector3 = root.global_position + Vector3(_rng.randf_range(-0.6, 0.6), 0.8, _rng.randf_range(-0.6, 0.6))
			fx.puff(at, Vector3(_rng.randf_range(-0.3, 0.3), 1.3, _rng.randf_range(-0.3, 0.3)), Color(g, g * 0.97, g * 0.95),
				_rng.randf_range(0.35, 0.6), _rng.randf_range(1.0, 1.8), 0.6)
		# wheelspin: smoke from under the rear wheels (a burnout off the line)
		var ws: float = d.get("wheelspin", 0.0)
		if ws > 0.06 and _rng.randf() < delta * 30.0 * ws:
			for side in [-0.8, 0.8]:
				# behind the rear wheels (not hidden under the body), rolling back
				var at: Vector3 = root.global_transform * Vector3(-2.3, 0.4, side)
				fx.puff(at, Vector3(_rng.randf_range(-0.7, 0.7), 0.5, _rng.randf_range(-0.7, 0.7)) - root.global_transform.basis.x * 1.6,
					Color(0.97, 0.96, 0.94), _rng.randf_range(0.45, 0.7) * (0.8 + ws * 0.4), _rng.randf_range(0.55, 0.95), 0.45 + 0.35 * ws)
		# P004: exhausts - idle puffs, a dark cough under hard throttle,
		# bursts when the drivers blip on the grid, pops lifting off at speed
		var exs: Array = d.get("exhausts", [])
		if not exs.is_empty() and not wrecked and c.model != null:
			var a_long: float = d.get("acc_long", 0.0)
			var spd := c.model.velocity.length()
			var revving: bool = float(d.get("rev", 0.0)) > 0.0
			var ex_rate := 0.0
			if revving:
				ex_rate = 26.0
			elif a_long > 150.0:
				ex_rate = 7.0
			elif spd < 30.0:
				ex_rate = 1.3
			var back: Vector3 = -root.global_transform.basis.x
			if ex_rate > 0.0 and _rng.randf() < delta * ex_rate:
				var ex: Node3D = exs[_rng.randi() % exs.size()]
				var g := 0.32 if (revving or a_long > 150.0) else 0.62
				fx.puff(ex.global_transform * Vector3(-0.2, 0.06, 0.0), back * 0.9 + Vector3(0, 0.35, 0), Color(g, g, g * 1.03),
					_rng.randf_range(0.13, 0.2), _rng.randf_range(0.5, 0.8), 0.5)
			var rid := c.racer_id % TURBO_SPIT.size()
			_pull[i] = _pull[i] + delta if a_long > 120.0 else maxf(0.0, _pull[i] - delta * 3.0)
			var lift := _last_accel[i] > 120.0 and a_long < -80.0 and spd > 150.0
			var spat := false
			if lift and _pull[i] >= SPIT_PULL and _time >= _spit_ready[i] and _ex_rng.randf() < TURBO_SPIT[rid]:
				spat = true
				_spit_ready[i] = _time + SPIT_COOLDOWN + _ex_rng.randf_range(0.0, 2.0)
				var at_t := _time
				for k in _ex_rng.randi_range(1, 3):  # a short, irregular burst
					_spits.append([at_t, i])
					at_t += _ex_rng.randf_range(0.07, 0.19)
			if lift:
				_pull[i] = 0.0
			if lift and not spat and _rng.randf() < BACKFIRE[i % BACKFIRE.size()]:
				for ex in exs:
					var at: Vector3 = (ex as Node3D).global_transform * Vector3(-0.25, 0.06, 0.0)
					for k in 3:
						fx.spark(at, back * _rng.randf_range(2.0, 3.5) + Vector3(_rng.randf_range(-0.4, 0.4), _rng.randf_range(0.1, 0.5), _rng.randf_range(-0.4, 0.4)),
							Color(1.0, _rng.randf_range(0.45, 0.7), 0.15), 0.1, 0.16, 1.6, 0.0)
				backfired.emit(i)
				_sound("backfire", root.global_position, -10.0, 0.12)
			_last_accel[i] = a_long
		# tyre smoke and dust from RaceEffects' own rules
		var eff: RaceEffects = _main.effects
		if eff != null and i < eff.smoking.size():
			var rear: Vector3 = root.global_transform * Vector3(-1.4, 0.15, 0.0)
			if eff.smoking[i] == 1 and _rng.randf() < delta * 26.0:
				fx.puff(rear + Vector3(0, 0, _rng.randf_range(-0.6, 0.6)), Vector3(_rng.randf_range(-0.4, 0.4), 0.5, _rng.randf_range(-0.4, 0.4)),
					Color(0.92, 0.9, 0.86), _rng.randf_range(0.28, 0.45), _rng.randf_range(0.5, 0.9), 0.55)
			if eff.dusting[i] == 1 and _rng.randf() < delta * 18.0:
				var dc: Color = _main.track_theme.dust_color if _main.track_theme != null else Color(0.75, 0.66, 0.5)
				fx.puff(rear, Vector3(_rng.randf_range(-0.5, 0.5), 0.4, _rng.randf_range(-0.5, 0.5)), dc, _rng.randf_range(0.25, 0.4), 0.6, 0.5)
	# jumps: dust on take-off and landing
	if _main.get("jumps") != null:
		var air: bool = _main.get("jumps").is_airborne(i)
		if air != (_was_air[i] == 1) and c.visible:
			var dust := Color(0.85, 0.78, 0.62)
			for k in (8 if air else 18):
				var a := _rng.randf() * TAU
				fx.puff(root.global_position + Vector3(cos(a), 0.1, sin(a)) * 0.8, Vector3(cos(a), 0.5, sin(a)) * _rng.randf_range(1.0, 3.0),
					dust, _rng.randf_range(0.3, 0.5), 0.8, 0.6)
		_was_air[i] = 1 if air else 0
	# cars kick the debris they drive through (and it rattles, P004)
	if c.visible and not wrecked and c.model != null:
		var v := c.model.velocity
		var kicked := fx.scatter_near(root.global_position, Vector3(v.x, 0.0, v.y) * Vox.PX, 1.9)
		if kicked >= 5 and _time - _last_rattle > 0.35:
			_last_rattle = _time
			_sound("debris_rattle", root.global_position, -6.0)


## Anti-lag bangs that are due: a sharp crack and a spit of flame from the
## exhausts (Audio Integration 001).
func _sync_spits() -> void:
	if _spits.is_empty():
		return
	var keep: Array = []
	for sp in _spits:
		if float(sp[0]) > _time:
			keep.append(sp)
			continue
		var i := int(sp[1])
		if i >= stage.cars3d.size() or _was_wrecked[i] == 1:
			continue
		var d: Dictionary = stage.cars3d[i]
		var root: Node3D = d.root
		if not root.visible:
			continue
		var back: Vector3 = -root.global_transform.basis.x
		for ex in (d.get("exhausts", []) as Array):
			var at: Vector3 = (ex as Node3D).global_transform * Vector3(-0.25, 0.06, 0.0)
			for k in 4:
				fx.spark(at, back * _ex_rng.randf_range(2.5, 4.5) + Vector3(_ex_rng.randf_range(-0.4, 0.4), _ex_rng.randf_range(0.1, 0.5), _ex_rng.randf_range(-0.4, 0.4)),
					Color(1.0, _ex_rng.randf_range(0.5, 0.8), 0.2), 0.1, 0.14, 1.8, 0.0)
		_sound("turbo_spit", root.global_position, -11.0, 0.1)
	_spits = keep


## Voxels that broke off a car fly away from the hit (and keep some of the
## car's speed), then lie on the track.
func _spawn_bits(i: int, pieces: Array, dir: Vector3) -> void:
	if pieces.is_empty():
		return
	var d: Dictionary = stage.cars3d[i]
	var body: MeshInstance3D = d.body
	var xf := body.global_transform
	var c: Car = _main.cars[i]
	var v := c.model.velocity if c.model != null else Vector2.ZERO
	var carv := Vector3(v.x, 0.0, v.y) * Vox.PX
	var out_dir := (xf.basis.orthonormalized() * dir).normalized() if dir.length() > 0.01 else Vector3.ZERO
	var floor_y: float = (d.root as Node3D).global_position.y if d.h > 2.0 else -INF
	fx.throw_parts(d.model, pieces, xf, carv, out_dir, floor_y, false)
	var at: Vector3 = xf * (d.model.parts[int(pieces[0])].centre as Vector3)
	fx.impact(at, out_dir, 0.25 + 0.1 * pieces.size())


## The car blows apart: its remaining components thrown outward, wheels
## flying, fire, smoke, a flash, and a burn mark under it; the charred crash
## cell stays.
func _explode(i: int) -> void:
	var d: Dictionary = stage.cars3d[i]
	var dmg := damage[i]
	var body: MeshInstance3D = d.body
	var xf := body.global_transform
	var root: Node3D = d.root
	var centre := root.global_position + Vector3(0, 0.5, 0)
	var c: Car = _main.cars[i]
	var v := c.model.velocity if c.model != null else Vector2.ZERO
	var carv := Vector3(v.x, 0.0, v.y) * Vox.PX
	var floor_y: float = root.global_position.y if d.h > 2.0 else -INF
	var pieces := dmg.explode()
	fx.throw_parts(d.model, pieces, xf, carv, Vector3.ZERO, floor_y, true)
	fx.throw_wheels(d.wheels, centre, carv, floor_y)
	_set_wheels(i, false)
	fx.explosion(centre, 1.0)
	dmg.rebuild()
	_burn(c.global_position, 1.0)


func _set_wheels(i: int, on: bool) -> void:
	for w in (stage.cars3d[i].wheels as Array):
		(w as Node3D).visible = on and stage.cars3d[i].show_wheels


# ------------------------------------------------------------ collisions

## A wall knock: `normal` points from the wall to the car (2D).
func _on_wall_hit(normal: Vector2, speed: float, i: int) -> void:
	_knock(i, -normal, speed)


func _on_car_hit(other: Car, speed: float, i: int) -> void:
	var c: Car = _main.cars[i]
	_knock(i, (other.global_position - c.global_position).normalized(), speed)


## Remembers which side was hit (damage carving) and shows the knock.
func _knock(i: int, toward_2d: Vector2, speed: float) -> void:
	var c: Car = _main.cars[i]
	if not c.visible or speed < 40.0:
		return
	var local := toward_2d.rotated(-c.global_rotation)  # car space: +x nose, +y right
	_last_dir[i] = Vector3(local.x, 0.2, local.y).normalized()
	_last_hit_time[i] = _time
	if speed < 70.0:
		return
	var root: Node3D = stage.cars3d[i].root
	var at: Vector3 = root.global_position + Vector3(toward_2d.x, 0.0, toward_2d.y) * 1.6 + Vector3(0, 0.5, 0)
	var severity := clampf((speed - 70.0) / 260.0, 0.0, 1.0)
	fx.impact(at, Vector3(-toward_2d.x, 0.3, -toward_2d.y), severity)


# ------------------------------------------------------------ weapons

func _read_combat_events() -> void:
	var combat: CombatWorld = _main.combat
	if combat == null:
		return
	if _cursor > combat.events.size():
		_cursor = 0
	while _cursor < combat.events.size():
		var e: Dictionary = combat.events[_cursor]
		_cursor += 1
		match e.kind:
			"explode", "mine_blast":
				var big: bool = e.kind == "mine_blast"
				var p: Vector2 = e.pos
				fx.explosion(_ground3(p) + Vector3(0, 0.4, 0), 0.75 if big else 0.5)
				_burn(p, 0.55 if big else 0.4)
				var car: int = e.car
				if car >= 0 and car < damage.size():
					var c: Car = _main.cars[car]
					var local := (p - c.global_position).rotated(-c.global_rotation)
					_last_dir[car] = Vector3(local.x, 0.3, local.y).normalized()
					_last_hit_time[car] = _time


func _ground3(p: Vector2) -> Vector3:
	return Vox.to3(p, stage.vtrack.height_px_at(p) if stage.vtrack != null else 0.0)


func _sync_weapons(delta: float) -> void:
	var combat: CombatWorld = _main.combat
	if combat == null:
		return
	_trail_clock += delta
	var trail := _trail_clock > MISSILE_SPEED_TRAIL
	if trail:
		_trail_clock = 0.0
	while _missiles.size() < combat.projectiles.size():
		var m := MeshInstance3D.new()
		m.mesh = VoxelWeapons.missile_mesh()
		add_child(m)
		_missiles.append(m)
	for k in _missiles.size():
		var on := k < combat.projectiles.size()
		_missiles[k].visible = on
		if not on:
			continue
		var p: Dictionary = combat.projectiles[k]
		var h := 10.0 + (VoxelTrack.DECK_H_PX if int(p.get("level", 0)) == 1 else 0.0)
		_missiles[k].position = Vox.to3(p.pos, h)
		var ang: float = (p.dir as Vector2).angle() if p.has("dir") else 0.0
		_missiles[k].rotation = Vector3(0, Vox.yaw(ang), 0)
		var big: bool = int(p.type) == WeaponRules.Weapon.SUPER_MISSILE
		var kind := "super" if big else ("homing" if int(p.type) == WeaponRules.Weapon.HOMING_MISSILE else "missile")
		if _missiles[k].get_meta("kind", "") != kind:
			_missiles[k].mesh = VoxelWeapons.missile_mesh(kind)
			_missiles[k].set_meta("kind", kind)
			_missiles[k].set_instance_shader_parameter("lamp_glow", 1.0)
		_missiles[k].scale = Vector3.ONE * (1.35 if big else 1.0)
		if trail:
			var back: Vector3 = _missiles[k].global_transform * Vector3(-0.7, 0, 0)
			fx.puff(back, Vector3(0, 0.3, 0), Color(0.95, 0.9, 0.8), 0.22, 0.45, 0.6)
			fx.spark(back, Vector3(_rng.randf_range(-0.5, 0.5), 0.5, _rng.randf_range(-0.5, 0.5)), Color(1, 0.6, 0.2), 0.1, 0.15, 1.2, 0.0)
	while _mines.size() < combat.mines.size():
		var mm := MeshInstance3D.new()
		mm.mesh = VoxelWeapons.mine_mesh()
		add_child(mm)
		_mines.append(mm)
	for k in _mines.size():
		var on := k < combat.mines.size()
		_mines[k].visible = on
		if not on:
			continue
		var m: Dictionary = combat.mines[k]
		var h := VoxelTrack.DECK_H_PX if int(m.get("level", 0)) == 1 else 0.0
		_mines[k].position = Vox.to3(m.pos, h)
		var fast: bool = m.age > combat.rules.mine_fuse - 1.0
		var blink := 0.5 + 0.5 * sin(float(m.age) * TAU * (4.0 if fast else 1.5))
		_mines[k].set_instance_shader_parameter("lamp_glow", 0.2 + blink)


# ------------------------------------------------------------ burn marks

## A scorch on the ground (HyperCars' decal layer, projected onto the voxel
## road like the tyre marks), for the rest of the race.
func _burn(p: Vector2, scale: float) -> void:
	var s := Sprite2D.new()
	s.texture = _scorch_tex
	s.position = p
	s.rotation = _rng.randf() * TAU
	var px := SCORCH_SIZE * scale * _rng.randf_range(0.9, 1.15)
	s.scale = Vector2.ONE * px / _scorch_tex.get_width()
	s.visibility_layer = VoxelStage.DECAL_LAYER
	_burns.add_child(s)


func burns_visible(on: bool) -> void:
	if _burns != null:
		_burns.visible = on


func burn_count() -> int:
	return _burns.get_child_count()


## A ragged, sooty scorch (generated once).
static func _make_scorch() -> Texture2D:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 77
	noise.frequency = 0.09
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5) / n * 2.0 - Vector2.ONE
			var r := p.length() + noise.get_noise_2d(x, y) * 0.35
			var a := clampf(1.0 - smoothstep(0.35, 0.95, r), 0.0, 1.0)
			var core := clampf(1.0 - r / 0.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(0.05 + 0.05 * core, 0.04, 0.035, a * 0.92))
	return ImageTexture.create_from_image(img)


# ------------------------------------------------------------ taunts

## A rival just passed another car (ReplayRecorder spots it): sometimes,
## by temperament, the driver leans out and lobs a soda can back at them.
func on_overtake(a: int, b: int) -> void:
	var session: RaceSession = _main.session
	if session.human_ids.has(a) and not session.spectator:
		return  # the player's own driver keeps both hands on the wheel
	if _time - _taunt_last < TAUNT_GAP or _time - _taunt_cool[a] < TAUNT_COOLDOWN:
		return
	var chance: float = TAUNT_CHANCE[a % TAUNT_CHANCE.size()] * TAUNT_SCALE
	if session.human_ids.has(b) and not session.spectator:
		chance *= 1.4  # they love doing it to you
	if _rng.randf() > chance:
		return
	_taunt_last = _time
	_taunt_cool[a] = _time
	var ca: Car = _main.cars[a]
	var cb: Car = _main.cars[b]
	var local := (cb.global_position - ca.global_position).rotated(-ca.global_rotation)
	stage.cars3d[a].head_side = 1.0 if local.y >= 0.0 else -1.0
	_taunts.append({"car": a, "victim": b, "t": 0.0, "thrown": false})


func _sync_taunts(delta: float) -> void:
	for k in range(_taunts.size() - 1, -1, -1):
		var tt: Dictionary = _taunts[k]
		var d: Dictionary = stage.cars3d[tt.car]
		var c: Car = _main.cars[tt.car]
		tt.t = float(tt.t) + delta
		var v := float(tt.t) / TAUNT_TIME
		if v >= 1.0 or not c.visible or (_main.combat != null and _main.combat.enabled and _main.combat.is_wrecked(tt.car)):
			d.head = 0.0
			stage.pose_head(d, 0.0)
			_taunts.remove_at(k)
			continue
		d.head = v
		stage.pose_head(d, v)
		if not tt.thrown and v >= 0.42:
			tt.thrown = true
			_throw(tt.car, tt.victim)


func _throw(a: int, b: int) -> void:
	var d: Dictionary = stage.cars3d[a]
	var head: Node3D = d.head_node
	var ca: Car = _main.cars[a]
	var cb: Car = _main.cars[b]
	var at := head.global_position + Vector3(0, 0.35, 0)
	var carv := Vector3(ca.model.velocity.x, 0.0, ca.model.velocity.y) * Vox.PX if ca.model != null else Vector3.ZERO
	var to_b := Vox.to3(cb.global_position) - Vox.to3(ca.global_position)
	to_b.y = 0.0
	var back := to_b.normalized() if to_b.length() > 0.1 else -Vector3(cos(ca.global_rotation), 0, sin(ca.global_rotation))
	var vel := carv * 0.55 + back * _rng.randf_range(4.5, 6.0) + Vector3(0, _rng.randf_range(5.0, 6.5), 0)
	var spin := Vector3(_rng.randf_range(-9, 9), _rng.randf_range(-4, 4), _rng.randf_range(-9, 9))
	var node := MeshInstance3D.new()
	node.mesh = VoxelWeapons.can_mesh()
	add_child(node)
	node.position = at
	cans.append({"node": node, "vel": vel, "spin": spin, "rest": false, "life": 14.0})
	if stage.recorder != null:
		stage.recorder.add_event({"kind": "taunt", "score": 6.5, "pos": ca.global_position, "car": b, "by": a,
			"can_pos": at, "can_vel": vel, "can_spin": spin})


## Soda cans in flight: tumble, bounce, roll a little, lie there a while,
## then shrink away. Cosmetic only.
static func step_cans(list: Array, dt: float, ground: Callable) -> void:
	for k in range(list.size() - 1, -1, -1):
		var can: Dictionary = list[k]
		var node: Node3D = can.node
		can.life = float(can.life) - dt
		if can.life <= 0.0:
			node.queue_free()
			list.remove_at(k)
			continue
		if can.life < 0.6:
			node.scale = Vector3.ONE * maxf(0.01, can.life / 0.6)
		if can.rest:
			continue
		var v: Vector3 = can.vel
		v.y -= 30.0 * dt
		var p := node.position + v * dt
		var g: float = ground.call(p.x, p.z) if ground.is_valid() else 0.0
		var spin: Vector3 = can.spin
		if p.y < g + 0.22:
			p.y = g + 0.22
			if v.y < 0.0:
				v.y = -v.y * 0.38
			v.x *= 0.72
			v.z *= 0.72
			spin *= 0.6
			if v.length() < 0.9:
				can.rest = true
				node.rotation = Vector3(PI * 0.5, node.rotation.y, 0.0)  # on its side
		can.vel = v
		can.spin = spin
		node.position = p
		if not can.rest:
			node.rotation += spin * dt
