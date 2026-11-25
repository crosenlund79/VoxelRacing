class_name CombatView
extends Node2D
## Combat presentation: draws missiles, blinking mines and explosions from the
## CombatWorld state, darkens and smokes wrecked cars, plays weapon sounds.
## P1 readability: a short smoke trail behind each missile (the existing smoke
## particle) and a restrained red halo under each mine, pulsing with its blink.
## Read-only: it reads the combat state and its append-only event log through
## its own cursor, and never changes combat, cars or the race.

const W := WeaponRules.Weapon
const TEXTURES := {W.HOMING_MISSILE: AssetCatalog.HOMING_MISSILE, W.SUPER_MISSILE: AssetCatalog.SUPER_MISSILE}
## Missile trail and mine halo look (presentation only).
const TRAIL_PARTICLES := 14
const TRAIL_LIFETIME := 0.32
const MINE_HALO_RADIUS := 17.0
const MINE_HALO_COLOR := Color(0.95, 0.22, 0.12)
const LAUNCH_SOUNDS := {W.MINE: "weapons/mine_drop", W.HOMING_MISSILE: "weapons/homing_launch",
	W.SUPER_MISSILE: "weapons/super_launch"}

var enabled := true
## Racer ids whose empty-weapon clicks are heard (the humans).
var human_ids: Array[int] = [RaceSession.PLAYER_ID]
var _combat: CombatWorld
var _cars: Array[Car] = []
var _resolver: AssetResolver
var _audio: RaceAudio
var _missiles: Array[Sprite2D] = []
var _mines: Array[Sprite2D] = []
## One short trail per missile sprite (same index).
var _trails: Array[CPUParticles2D] = []
## Mine halos are drawn on this node, under the mine sprites.
var _halos: Node2D
## J2 (elevated layouts): road level of a racer (Callable(int) -> int); halos
## of mines on the bridge; levels of live projectiles / mines, kept by identity.
var level_of: Callable
var _halos_upper: Node2D = null
var _proj_refs: Array = []
var _proj_levels: Array[int] = []
var _mine_refs: Array = []
var _mine_levels: Array[int] = []
var _smoke: Array[CPUParticles2D] = []
var _cursor := 0
var _time := 0.0
var _rng := RandomNumberGenerator.new()


func setup(combat: CombatWorld, cars: Array[Car], resolver: AssetResolver, audio: RaceAudio) -> void:
	_combat = combat
	_cars = cars
	_resolver = resolver
	_audio = audio
	z_index = 3
	_halos = Node2D.new()
	_halos.name = "MineHalos"
	_halos.z_index = -2
	_halos.draw.connect(_draw_halos.bind(0))
	add_child(_halos)
	for c in cars:
		var p := CPUParticles2D.new()
		p.texture = resolver.get_texture(AssetCatalog.SMOKE)
		p.amount = 14
		p.lifetime = 1.4
		p.local_coords = false
		p.emitting = false
		p.direction = Vector2.UP
		p.spread = 35.0
		p.gravity = Vector2.ZERO
		p.initial_velocity_min = 20.0
		p.initial_velocity_max = 50.0
		p.color = Color(0.25, 0.22, 0.2, 0.8)
		var fade := Gradient.new()
		fade.set_color(0, Color(1, 1, 1, 1))
		fade.set_color(1, Color(1, 1, 1, 0))
		p.color_ramp = fade
		p.scale_amount_min = 0.8
		p.scale_amount_max = 1.6
		add_child(p)
		_smoke.append(p)


## Elevated layouts: bridge-level weapons and wreck smoke draw above the deck.
func setup_levels(p_level_of: Callable) -> void:
	level_of = p_level_of
	_halos_upper = Node2D.new()
	_halos_upper.name = "MineHalosUpper"
	_halos_upper.z_index = -2 + Track.UPPER_Z_OFFSET
	_halos_upper.draw.connect(_draw_halos.bind(1))
	add_child(_halos_upper)
	move_child(_halos_upper, 1)


func _car_level(id: int) -> int:
	return level_of.call(id) if level_of.is_valid() and id >= 0 and id < _cars.size() else 0


## Level of each live projectile / mine: kept from when it was first seen (the
## same dictionary while it lives), else its owner's current level.
func _levels_of(items: Array, refs: Array, levels: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for item in items:
		var level := -1
		for k in refs.size():
			if is_same(refs[k], item):
				level = levels[k]
				break
		if item.has("level"):  # J4: the host's own level (bridge ends: drawn above the deck)
			level = 1 if item.level == 1 or item.get("band", false) else 0
		out.append(level if level >= 0 else _car_level(item.owner))
	return out


func set_enabled(on: bool) -> void:
	enabled = on
	visible = on
	if not on:
		for p in _smoke + _trails:
			p.emitting = false
		_cursor = _combat.events.size()


func _process(delta: float) -> void:
	_time += delta
	if not enabled or _combat == null:
		return
	if _cursor > _combat.events.size():
		_cursor = 0  # combat was reset for a new race
	while _cursor < _combat.events.size():
		_show_event(_combat.events[_cursor])
		_cursor += 1
	_sync_missiles()
	_sync_mines()
	for i in _cars.size():
		var wrecked := _combat.enabled and _combat.is_wrecked(i) and _cars[i].visible
		_cars[i].modulate = Color(0.35, 0.32, 0.3) if wrecked else (Color(1, 1, 1, 0.6 + 0.4 * absf(sin(_time * 12.0)))
			if _combat.enabled and _combat.grace_left[i] > 0.0 else Color.WHITE)
		_smoke[i].global_position = _cars[i].global_position
		_smoke[i].emitting = wrecked
		if level_of.is_valid():
			_smoke[i].z_index = Track.UPPER_Z_OFFSET * _car_level(i)


func _sync_missiles() -> void:
	while _missiles.size() < _combat.projectiles.size():
		_trails.append(_trail())
		var s := Sprite2D.new()
		add_child(s)
		_missiles.append(s)
	var levels: Array[int] = []
	if level_of.is_valid():
		levels = _levels_of(_combat.projectiles, _proj_refs, _proj_levels)
		_proj_refs = _combat.projectiles.duplicate()
		_proj_levels = levels
	for i in _missiles.size():
		var on := i < _combat.projectiles.size()
		_missiles[i].visible = on
		_trails[i].emitting = on
		if on and not levels.is_empty():
			_missiles[i].z_index = Track.UPPER_Z_OFFSET * levels[i]
			_trails[i].z_index = -1 + _missiles[i].z_index
		if on:
			var p: Dictionary = _combat.projectiles[i]
			var logical: String = TEXTURES.get(p.type, AssetCatalog.MISSILE)
			var tex := _resolver.get_texture(logical)
			if _missiles[i].texture != tex:
				_missiles[i].texture = tex
				_missiles[i].scale = AssetCatalog.scale_for(tex, AssetCatalog.SPECS[logical].display_size)
			_missiles[i].position = p.pos
			_missiles[i].rotation = (p.angle + PI * 0.5) if p.type == W.SUPER_MISSILE else p.dir.angle()
			_trails[i].global_position = p.pos


## Short, faint smoke trail (the replaceable smoke particle, its catalogue size).
func _trail() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	var tex := _resolver.get_texture(AssetCatalog.SMOKE)
	p.texture = tex
	p.amount = TRAIL_PARTICLES
	p.lifetime = TRAIL_LIFETIME
	p.local_coords = false
	p.emitting = false
	p.direction = Vector2.ZERO
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 14.0
	var size := AssetCatalog.scale_for(tex, AssetCatalog.SPECS[AssetCatalog.SMOKE].display_size).x
	p.scale_amount_min = size * 0.5
	p.scale_amount_max = size * 0.7
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.6))
	grow.add_point(Vector2(1, 1.3))
	p.scale_amount_curve = grow
	p.color = Color(0.97, 0.9, 0.78, 0.75)
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	p.z_index = -1
	add_child(p)
	return p


func _sync_mines() -> void:
	var tex := _resolver.get_texture(AssetCatalog.MINE)
	while _mines.size() < _combat.mines.size():
		var s := Sprite2D.new()
		s.texture = tex
		s.hframes = AssetCatalog.SPECS[AssetCatalog.MINE].frames
		var frame := Vector2(tex.get_width() / float(s.hframes), tex.get_height())
		s.scale = AssetCatalog.SPECS[AssetCatalog.MINE].display_size / frame
		s.z_index = -2
		add_child(s)
		_mines.append(s)
	var levels: Array[int] = []
	if level_of.is_valid():
		levels = _levels_of(_combat.mines, _mine_refs, _mine_levels)
		_mine_refs = _combat.mines.duplicate()
		_mine_levels = levels
	for i in _mines.size():
		var on := i < _combat.mines.size()
		_mines[i].visible = on
		if on and not levels.is_empty():
			_mines[i].z_index = -2 + Track.UPPER_Z_OFFSET * levels[i]
		if on:
			var m: Dictionary = _combat.mines[i]
			_mines[i].position = m.pos
			var fast_blink: bool = m.age > _combat.rules.mine_fuse - 1.0
			_mines[i].frame = int(m.age * (8.0 if fast_blink else 3.0)) % 2
	_halos.queue_redraw()
	if _halos_upper != null:
		_halos_upper.queue_redraw()


## Red halo under each mine, pulsing in step with its blink (faster before it blows).
func _draw_halos(level: int) -> void:
	var canvas := _halos if level == 0 else _halos_upper
	for k in _combat.mines.size():
		var m: Dictionary = _combat.mines[k]
		if (_mine_levels[k] if k < _mine_levels.size() else 0) != level:
			continue
		var fast_blink: bool = m.age > _combat.rules.mine_fuse - 1.0
		var pulse := 0.5 + 0.5 * sin(m.age * TAU * (4.0 if fast_blink else 1.5))
		canvas.draw_circle(m.pos, MINE_HALO_RADIUS, Color(MINE_HALO_COLOR, lerpf(0.12, 0.3, pulse)))
		canvas.draw_arc(m.pos, MINE_HALO_RADIUS, 0.0, TAU, 28, Color(MINE_HALO_COLOR, lerpf(0.45, 0.85, pulse)), 2.0, true)


func _show_event(e: Dictionary) -> void:
	match e.kind:
		"fire":
			_play(LAUNCH_SOUNDS.get(e.type, "weapons/missile_launch"), e.pos)
		"empty":
			if human_ids.has(e.car):
				_play("weapons/empty", e.pos)
		"switch":  # weapon cycling (only a human cycles): a soft click at the car
			if human_ids.has(e.car):
				_play("ui/ui_move", _cars[e.car].global_position)
		"explode", "mine_blast":
			_blast(e.pos, 1.4 if e.kind == "mine_blast" else 0.8)
			_play("weapons/explosion", e.pos)
		"destroyed":
			_blast(_cars[e.car].global_position, 1.2)


func _blast(pos: Vector2, size: float) -> void:
	var s := Sprite2D.new()
	s.texture = _resolver.get_texture(AssetCatalog.BLAST)
	var base := AssetCatalog.scale_for(s.texture, AssetCatalog.SPECS[AssetCatalog.BLAST].display_size) * size
	s.position = pos
	s.rotation = _rng.randf_range(0, TAU)
	s.scale = base * 0.4
	add_child(s)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(s, "scale", base, 0.18).set_ease(Tween.EASE_OUT)
	tw.tween_property(s, "modulate:a", 0.0, 0.5).set_delay(0.12)
	tw.chain().tween_callback(s.queue_free)


func _play(logical: String, pos: Vector2) -> void:
	if _audio != null:
		_audio.play_at(logical, pos)
