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
		var grid: VoxelGrid = d.grid
		var dmg := VoxelCarDamage.new(grid, d.body, 1000 + i)
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


## Called every frame by VoxelStage after the cars were placed.
func sync(delta: float) -> void:
	_time += delta
	_check_new_race()
	_read_combat_events()
	_rebuilds_left = 3
	for i in damage.size():
		_sync_car(i, delta)
	_sync_weapons(delta)


# ------------------------------------------------------------ fresh races

func _check_new_race() -> void:
	var state: int = _main.session.state
	var n: int = _main.races_started
	var fresh := (n != _race_number) or (state == RaceSession.State.MODE_SELECT and _state != RaceSession.State.MODE_SELECT)
	_race_number = n
	_state = state
	if not fresh:
		return
	fx.clear()
	for b in _burns.get_children():
		b.queue_free()
	for i in damage.size():
		if damage[i].removed > 0 or damage[i].wrecked:
			damage[i].restore()
			damage[i].dirty = false
			(stage.cars3d[i].body as MeshInstance3D).mesh = stage.cars3d[i].pristine_mesh
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
		dmg.restore()  # respawned: a fresh body, then the damage it still carries
		dmg.dirty = false
		(d.body as MeshInstance3D).mesh = d.pristine_mesh
		_set_wheels(i, true)
	_was_wrecked[i] = 1 if wrecked else 0
	if not wrecked and dw != null and c.visible:
		var target := VoxelCarDamage.target_loss(dw.fraction(i))
		if target < dmg.loss() - 0.03:  # repaired
			dmg.restore()
		if target > dmg.loss() + 0.003:
			var dir := _last_dir[i] if _time - _last_hit_time[i] < 0.6 else Vector3.ZERO
			var pieces := dmg.break_to(target, dir)
			_spawn_bits(i, pieces, dir)
	if dmg.dirty and _rebuilds_left > 0:
		_rebuilds_left -= 1
		dmg.rebuild()
		if not wrecked and dmg.removed == 0:
			(d.body as MeshInstance3D).mesh = d.pristine_mesh
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
	# cars kick the debris they drive through
	if c.visible and not wrecked and c.model != null:
		var v := c.model.velocity
		fx.scatter_near(root.global_position, Vector3(v.x, 0.0, v.y) * Vox.PX, 1.9)


## Voxels that broke off a car fly away from the hit (and keep some of the
## car's speed), then lie on the track.
func _spawn_bits(i: int, pieces: Array, dir: Vector3) -> void:
	if pieces.is_empty():
		return
	var d: Dictionary = stage.cars3d[i]
	var body: MeshInstance3D = d.body
	var xf := body.global_transform
	var basis := xf.basis.orthonormalized()
	var c: Car = _main.cars[i]
	var v := c.model.velocity if c.model != null else Vector2.ZERO
	var carv := Vector3(v.x, 0.0, v.y) * Vox.PX
	var out_dir := (basis * dir).normalized() if dir.length() > 0.01 else Vector3.ZERO
	var floor_y: float = (d.root as Node3D).global_position.y if d.h > 2.0 else -INF
	for p in pieces:
		var wp: Vector3 = xf * (p[0] as Vector3)
		var away: Vector3 = (wp - (d.root as Node3D).global_position)
		away.y = 0.0
		away = away.normalized()
		var vel := carv * _rng.randf_range(0.5, 0.85) + (away * 0.6 + out_dir) * _rng.randf_range(1.5, 4.0) + Vector3(0, _rng.randf_range(1.5, 4.0), 0)
		fx.debris(wp, vel, p[1], VoxelCars.voxel_size() * _rng.randf_range(0.9, 1.15), floor_y)
	if pieces.size() >= 3:
		fx.impact(xf * (pieces[0][0] as Vector3), out_dir, 0.2)


## The car blows apart: chunks of its own model, wheels flying, fire, smoke,
## a flash, and a burn mark under it.
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
	for p in pieces:
		var wp: Vector3 = xf * (p[0] as Vector3)
		var out := (wp - centre)
		out.y = maxf(out.y, 0.0) + 0.35
		var vel := carv * 0.35 + out.normalized() * _rng.randf_range(3.0, 9.0) + Vector3(0, _rng.randf_range(3.0, 8.0), 0)
		var glow := 0.0
		if _rng.randf() < 0.12:
			glow = 0.8  # embers
		fx.debris(wp, vel, p[1], VoxelCars.voxel_size() * float(p[2]) * _rng.randf_range(0.9, 1.1), floor_y, glow)
	# the wheels come off
	var wheels: Array = d.wheels
	for w in wheels:
		var wn := w as Node3D
		var wp := wn.global_position
		for k in 3:
			var out := (wp - centre)
			out.y = 0.6
			fx.debris(wp + Vector3(0, k * 0.1, 0), carv * 0.3 + out.normalized() * _rng.randf_range(3.0, 6.0) + Vector3(0, _rng.randf_range(3, 6), 0),
				Color(0.1, 0.1, 0.11), VoxelCars.voxel_size() * 2.0, floor_y)
	_set_wheels(i, false)
	fx.explosion(centre, 1.0)
	dmg.dirty = true
	dmg.rebuild()  # the burnt hull
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
