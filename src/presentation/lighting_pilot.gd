class_name LightingPilot
extends Node2D
## Night racing (TIME: NIGHT; started as the lighting pilot). A night presentation:
## the world is tinted darker, ten trackside lamps light the road, every car
## (rivals, junkers and won cars alike) carries vehicle lights, and weapon
## explosions flash briefly. Toggle with L.
##
## Vehicle lights (2026-11-17): two headlight beams and two red taillights per
## car. The taillights brighten into brake lights while the car slows hard; the
## headlights switch to high beam on a clear straight at speed and dip near
## another car ahead or a bend. DYNAMIC VEHICLE LIGHTS (setting) chooses real
## 2D lights (one twin-beam headlight light and one twin-lamp tail light per
## car) or the cheap fallback: additive glow sprites, no light passes. The lamp
## lenses are small additive sprites in both modes.
## Presentation only: reads car transforms and the combat event log; no physics,
## no collision, no gameplay writes. The HUD is on its own canvas layer and is
## not darkened.

const AMBIENT := Color(0.42, 0.44, 0.58)
const LAMP_COLOR := Color(1.0, 0.86, 0.6)
const HEADLIGHT_COLOR := Color(1.0, 0.95, 0.82)
const TAIL_COLOR := Color(1.0, 0.12, 0.08)
## Headlight colours (2026-11-23, Settings: HEADLIGHTS; cosmetic, the player's
## own car only): subtle tints that keep a near-white core, so the road stays
## readable. Index 0 is the standard warm white. Rear lights always stay red.
const HEADLIGHT_PALETTE := [
	["WARM WHITE", HEADLIGHT_COLOR],
	["COOL WHITE", Color(0.84, 0.92, 1.0)],
	["ICE BLUE", Color(0.56, 0.76, 1.0)],
	["AMBER", Color(1.0, 0.72, 0.38)],
	["MINT", Color(0.6, 1.0, 0.72)],
	["VIOLET", Color(0.8, 0.66, 1.0)],
]


## The front lamp lenses: the beam colour around a near-white core.
static func lens_color(beam: Color) -> Color:
	return Color.WHITE.lerp(beam, 0.55)
## Taillight energy: running and braking (brake lights brighter).
const TAIL_ENERGY := 0.45
const BRAKE_ENERGY := 1.25
## Braking = slowing faster than this (px/s^2) above BRAKE_MIN_SPEED.
const BRAKE_DECEL := 110.0
const BRAKE_MIN_SPEED := 30.0
## High beam: above this share of top speed, nothing within HIGH_BEAM_CLEAR px
## ahead (cars within the beam) and the road ahead straight (< HIGH_BEAM_BEND).
const HIGH_BEAM_SPEED := 0.55
const HIGH_BEAM_CLEAR := 560.0
const HIGH_BEAM_LOOKAHEAD := 520.0
const HIGH_BEAM_BEND := deg_to_rad(14.0)
## High beam reach and brightness (multipliers of the dipped beam).
const HIGH_BEAM_SCALE := 1.45
const HIGH_BEAM_ENERGY := 1.25
## Lamp anchors (body-relative, never read from the drawing). Every car shares
## one logical outline: CAR_SIZE display px, nose pointing +X, centred (the
## car art contract, AssetCatalog car display size). The game places the four
## lamps a little in from the outline's corners, so any body drawing (any
## resolution, painted lamps or none) gets the same lights; only the nose
## direction of the drawing matters (+X, as for steering and wheels).
const CAR_SIZE := Vector2(64.0, 36.0)
const HEAD_INSET := Vector2(3.0, 8.0)
const TAIL_INSET := Vector2(2.0, 7.0)
const HEAD_LAMP := Vector2(CAR_SIZE.x * 0.5 - HEAD_INSET.x, CAR_SIZE.y * 0.5 - HEAD_INSET.y)
const TAIL_LAMP := Vector2(-(CAR_SIZE.x * 0.5 - TAIL_INSET.x), CAR_SIZE.y * 0.5 - TAIL_INSET.y)
## Front-left, front-right, rear-left, rear-right (car space: +X ahead, +Y the
## car's right-hand side).
const LAMP_ANCHORS: Array[Vector2] = [Vector2(HEAD_LAMP.x, -HEAD_LAMP.y), HEAD_LAMP,
	Vector2(TAIL_LAMP.x, -TAIL_LAMP.y), TAIL_LAMP]
const LAMP_NAMES: Array[String] = ["front-left", "front-right", "rear-left", "rear-right"]
## The headlight texture's origin (the car centre) is this many px from its
## left edge; the beams start at the head lamps, ahead of it.
const BEAM_ORIGIN_X := 40.0
const LAMP_COUNT := 10
const FLASHES := 4

var enabled := false
var _ambient: CanvasModulate
var _lamps: Array[PointLight2D] = []
var _lamp_sprites: Array[Sprite2D] = []
var _car_lights: Array[PointLight2D] = []
var _tail_lights: Array[PointLight2D] = []
## Fallback (dynamic lights off): additive beam / tail glow sprites per car.
var _beam_sprites: Array[Sprite2D] = []
var _tail_sprites: Array[Sprite2D] = []
## Lamp lenses per car, in LAMP_ANCHORS order.
var _lenses: Array = []
## Real 2D vehicle lights (DYNAMIC VEHICLE LIGHTS on) or the sprite fallback.
var dynamic_lights := true
## Per car: braking (brake lights), high beam blend 0 .. 1, measured speed.
var braking := PackedByteArray()
var high_beam := PackedFloat32Array()
var _speed := PackedFloat32Array()
var _last_pos := PackedVector2Array()
var _path: ClosedPath
var _path_hint := PackedInt32Array()
var _frame := 0
## Top speed for the high-beam threshold (px/s).
var max_speed := 300.0
## J2 (elevated layouts): road level of a racer; a car's light only lights its own level.
var level_of: Callable
var _flashes: Array[PointLight2D] = []
var _flash_age := PackedFloat32Array()
var _next_flash := 0
var _cars: Array[Car] = []
var _combat: CombatWorld
var _cursor := 0


var lamp_color := LAMP_COLOR
## The player's headlight colour (HEADLIGHT_PALETTE) and the cars it applies
## to (the car(s) controlled on this computer).
var own_headlight := HEADLIGHT_COLOR
var _own_ids: Array[int] = []


static func headlight_color(index: int) -> Color:
	return HEADLIGHT_PALETTE[clampi(index, 0, HEADLIGHT_PALETTE.size() - 1)][1]


static func headlight_name(index: int) -> String:
	return HEADLIGHT_PALETTE[clampi(index, 0, HEADLIGHT_PALETTE.size() - 1)][0]


## Which cars carry own_headlight (every other car keeps the standard colour).
## Only the beams and the two front lenses change: anchors, direction, high
## beams and the red rear lights are the same for every colour.
func set_own_headlights(ids: Array[int], color: Color) -> void:
	_own_ids = ids.duplicate()
	own_headlight = color
	for i in _cars.size():
		var col := head_color_of(_cars[i].racer_id)
		if dynamic_lights:
			if i < _car_lights.size():
				_car_lights[i].color = col
		elif i < _beam_sprites.size():
			_beam_sprites[i].modulate = Color(col, _beam_sprites[i].modulate.a)
		if i < _lenses.size():
			for k in 2:
				_lenses[i][k].modulate = lens_color(col)


func head_color_of(racer_id: int) -> Color:
	return own_headlight if _own_ids.has(racer_id) else HEADLIGHT_COLOR
var lamp_energy := 1.15
var lamp_count := LAMP_COUNT
var headlight_energy := 0.95


## theme: the biome's night mood (ambient tint, lamps, headlights); null = the pilot's.
func setup(track: Track, cars: Array[Car], combat: CombatWorld, resolver: AssetResolver, theme: TrackTheme = null,
		p_dynamic_lights := true, p_max_speed := 300.0) -> void:
	_cars = cars
	dynamic_lights = p_dynamic_lights
	max_speed = p_max_speed
	if track != null:
		_path = track.path
	_combat = combat
	var ambient := AMBIENT
	if theme != null:
		ambient = theme.night_ambient
		lamp_color = theme.lamp_color
		lamp_energy = theme.lamp_energy
		lamp_count = theme.lamp_count
		headlight_energy = theme.headlight_energy
	_ambient = CanvasModulate.new()
	_ambient.color = ambient
	add_child(_ambient)
	var radial := _radial_texture(256)
	_light_texture = radial
	if track != null:  # (the Battle Royale arena places its own lamps: add_lamp)
		_place_lamps(track, resolver, radial)
	var head_tex := _car_light_texture()
	var tail_tex := _tail_light_texture()
	var lens_tex := _radial_texture(32)
	for c in cars:
		if dynamic_lights:
			var l := PointLight2D.new()
			l.texture = head_tex
			l.color = HEADLIGHT_COLOR
			l.energy = headlight_energy
			l.offset = beam_offset(head_tex, 1.0)
			add_child(l)
			_car_lights.append(l)
			var t := PointLight2D.new()
			t.texture = tail_tex
			t.color = TAIL_COLOR
			t.energy = TAIL_ENERGY
			add_child(t)
			_tail_lights.append(t)
		else:  # the cheap fallback: additive glows, no light passes
			var b := Sprite2D.new()
			b.texture = head_tex
			b.material = _additive()
			b.modulate = Color(HEADLIGHT_COLOR, 0.32)
			b.offset = Vector2(head_tex.get_width() * 0.5 - BEAM_ORIGIN_X, 0)
			b.z_index = 3
			add_child(b)
			_beam_sprites.append(b)
			var ts := Sprite2D.new()
			ts.texture = tail_tex
			ts.material = _additive()
			ts.modulate = Color(TAIL_COLOR, 0.5)
			ts.z_index = 3
			add_child(ts)
			_tail_sprites.append(ts)
		var lenses: Array[Sprite2D] = []
		for k in 4:
			var lens := Sprite2D.new()
			lens.texture = lens_tex
			lens.material = _additive()
			lens.scale = Vector2.ONE * (0.42 if k < 2 else 0.36)
			lens.modulate = HEADLIGHT_COLOR if k < 2 else TAIL_COLOR
			lens.z_index = 4
			add_child(lens)
			lenses.append(lens)
		_lenses.append(lenses)
	braking.resize(cars.size())
	high_beam.resize(cars.size())
	_speed.resize(cars.size())
	_last_pos.resize(cars.size())
	_path_hint.resize(cars.size())
	_path_hint.fill(-1)
	_high_beam_target.resize(cars.size())
	for i in cars.size():
		_last_pos[i] = cars[i].global_position
	for k in FLASHES:
		var f := PointLight2D.new()
		f.texture = radial
		f.color = Color(1.0, 0.7, 0.35)
		f.texture_scale = 1.3
		f.energy = 0.0
		add_child(f)
		_flashes.append(f)
	_flash_age.resize(FLASHES)
	_flash_age.fill(1.0)
	set_enabled(false)


func set_enabled__perf(on: bool) -> void:
	enabled = on
	_ambient.visible = on
	for l in _lamps + _car_lights + _tail_lights + _flashes:
		l.enabled = on
	for s in _lamp_sprites + _beam_sprites + _tail_sprites:
		s.visible = on
	for lenses in _lenses:
		for lens in lenses:
			lens.visible = on
	if _combat != null:
		_cursor = _combat.events.size()


func light_count() -> int:
	return _lamps.size() + _car_lights.size() + _tail_lights.size() + _flashes.size()


func _process__perf(delta: float) -> void:
	if not enabled:
		return
	_frame += 1
	for i in _cars.size():
		var c := _cars[i]
		_update_car_state(i, c, delta)
		var head := _car_lights[i] if dynamic_lights else null
		var tail := _tail_lights[i] if dynamic_lights else null
		var hb := high_beam[i]
		var brake := braking[i] == 1
		var xf := c.global_transform.orthonormalized()
		if dynamic_lights:
			head.enabled = c.visible
			tail.enabled = c.visible
			head.global_transform = xf
			tail.global_transform = xf.translated_local(Vector2(TAIL_LAMP.x - 6.0, 0))
			head.texture_scale = lerpf(1.0, HIGH_BEAM_SCALE, hb)
			head.offset = beam_offset(head.texture, head.texture_scale)
			head.energy = headlight_energy * lerpf(1.0, HIGH_BEAM_ENERGY, hb)
			tail.energy = BRAKE_ENERGY if brake else TAIL_ENERGY
			if level_of.is_valid():
				var upper: bool = level_of.call(c.racer_id) == 1
				for l in [head, tail]:
					l.range_z_min = Track.BRIDGE_DECK_Z if upper else RenderingServer.CANVAS_ITEM_Z_MIN
					l.range_z_max = RenderingServer.CANVAS_ITEM_Z_MAX if upper else Track.BRIDGE_SHADOW_Z - 1
		else:
			var b := _beam_sprites[i]
			var ts := _tail_sprites[i]
			b.visible = c.visible
			ts.visible = c.visible
			b.global_transform = xf.scaled_local(Vector2.ONE * lerpf(1.0, HIGH_BEAM_SCALE, hb))
			b.modulate.a = 0.3 * lerpf(1.0, HIGH_BEAM_ENERGY, hb)
			ts.global_transform = xf.translated_local(Vector2(TAIL_LAMP.x - 6.0, 0))
			ts.modulate.a = 0.85 if brake else 0.35
			if level_of.is_valid():
				var z := Track.BRIDGE_DECK_Z + 3 if level_of.call(c.racer_id) == 1 else 3
				b.z_index = z
				ts.z_index = z
		var lenses: Array = _lenses[i]
		for k in 4:
			var lens: Sprite2D = lenses[k]
			lens.visible = c.visible
			lens.global_position = xf * LAMP_ANCHORS[k]
			if k >= 2:
				lens.modulate = Color(TAIL_COLOR.lightened(0.35 if brake else 0.0), 1.0 if brake else 0.7)
				lens.scale = Vector2.ONE * (0.5 if brake else 0.36)
			if level_of.is_valid():
				lens.z_index = Track.BRIDGE_DECK_Z + 4 if level_of.call(c.racer_id) == 1 else 4
	if _combat != null:
		if _cursor > _combat.events.size():
			_cursor = 0
		while _cursor < _combat.events.size():
			var e: Dictionary = _combat.events[_cursor]
			_cursor += 1
			if e.kind == "explode" or e.kind == "mine_blast":
				var f := _flashes[_next_flash]
				f.global_position = e.pos
				_flash_age[_next_flash] = 0.0
				_next_flash = (_next_flash + 1) % FLASHES
	for k in FLASHES:
		_flash_age[k] = minf(1.0, _flash_age[k] + delta / 0.45)
		_flashes[k].energy = 1.6 * (1.0 - _flash_age[k])


## Headlight offset that keeps the beam's origin (BEAM_ORIGIN_X of the texture)
## on the car centre at any texture scale. A PointLight2D draws its texture
## scaled about the texture centre but does NOT scale its offset, so the offset
## must grow with the scale: with a fixed offset the high beam (scale 1.45)
## slid about 58 px backwards and started behind the car (the "headlights from
## the wrong end" report, 2026-11-22).
static func beam_offset(tex: Texture2D, texture_scale: float) -> Vector2:
	return Vector2((tex.get_width() * 0.5 - BEAM_ORIGIN_X) * texture_scale, 0.0)


## The four lamp anchors in car space (LAMP_ANCHORS order).
static func lamp_anchors() -> Array[Vector2]:
	return LAMP_ANCHORS


## Brake lights and high beams from what the car visibly does (works for every
## car, also a network client's interpolated ones: speed from its movement).
func _update_car_state(i: int, c: Car, delta: float) -> void:
	var pos := c.global_position
	var v := pos.distance_to(_last_pos[i]) / maxf(delta, 0.0001)
	_last_pos[i] = pos
	if v > max_speed * 3.0:  # a teleport (respawn, reset): not a speed
		v = _speed[i]
	var prev := _speed[i]
	var sp := lerpf(prev, v, clampf(delta * 10.0, 0.0, 1.0))
	_speed[i] = sp
	var decel := (prev - sp) / maxf(delta, 0.0001)
	braking[i] = 1 if c.visible and sp > BRAKE_MIN_SPEED and decel > BRAKE_DECEL else 0
	if (_frame + i) % 6 == 0:  # (high beam re-evaluated ten times a second per car)
		_high_beam_target[i] = 1.0 if _clear_ahead(i, c, sp) else 0.0
	high_beam[i] = move_toward(high_beam[i], _high_beam_target[i], delta * 3.0)


var _high_beam_target := PackedFloat32Array()


## High beam: fast, no car in the beam and the road ahead straight.
func _clear_ahead(i: int, c: Car, sp: float) -> bool:
	if not c.visible or sp < max_speed * HIGH_BEAM_SPEED:
		return false
	var fwd := Vector2.from_angle(c.global_rotation)
	for o in _cars:
		if o == c or not o.visible:
			continue
		var d := o.global_position - c.global_position
		var dist := d.length()
		if dist < HIGH_BEAM_CLEAR and d.dot(fwd) > dist * 0.6:
			return false  # dip for a car ahead
	if _path != null:  # dip for a bend (geometry ahead)
		var p := _path.project(c.global_position, _path_hint[i], 12)
		if p.distance < 0.0 or absf(p.lateral) > 400.0:
			p = _path.project(c.global_position)
		_path_hint[i] = p.index
		var s: float = p.distance
		var t0 := _path.tangent_at(s)
		for k in 3:
			if absf(t0.angle_to(_path.tangent_at(s + HIGH_BEAM_LOOKAHEAD * (k + 1) / 3.0))) > HIGH_BEAM_BEND:
				return false
	return true


static func _additive() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m


## The environment's lamps (ten by default): on the outside of the sharpest corners and along the main straight.
func _place_lamps(track: Track, resolver: AssetResolver, tex: Texture2D) -> void:
	var c := track.centerline
	var n := c.size()
	var tans := TrackLayout.tangents(c)
	var half := track.layout.road_width * 0.5
	var spots: Array = []
	for i in range(0, n, 3):
		spots.append([absf(tans[i].angle_to(tans[(i + 6) % n])), i])
	spots.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var chosen: Array[int] = [0]
	for s in spots:
		if chosen.size() >= lamp_count:
			break
		var ok := true
		for j in chosen:
			if c[j].distance_to(c[s[1]]) < 500.0:
				ok = false
		if ok:
			chosen.append(s[1])
	var lamp_tex := resolver.get_texture(AssetCatalog.LAMP_POST)
	for i in chosen:
		var right := Vector2(-tans[i].y, tans[i].x)
		var turn := signf(tans[i].cross(tans[(i + 6) % n]))
		var outside := -right * (turn if turn != 0.0 else 1.0)
		var pos := c[i] + outside * (half + 34.0)
		if track.layout.has_elevation() and not _clear_of_roads(pos, c, half + 20.0):
			continue  # J2: never on the other road of a crossing layout
		add_lamp(pos, outside, lamp_tex, tex)


var _light_texture: Texture2D


## One lamp post at pos, its light thrown towards -outside (the arena uses this).
func add_lamp(pos: Vector2, outside: Vector2, lamp_tex: Texture2D, tex: Texture2D = null) -> void:
	if tex == null:
		tex = _light_texture
	var spr := Sprite2D.new()
	spr.texture = lamp_tex
	spr.scale = AssetCatalog.scale_for(lamp_tex, AssetCatalog.SPECS[AssetCatalog.LAMP_POST].display_size)
	spr.position = pos
	spr.rotation = (-outside).angle() + PI * 0.5
	spr.z_index = 2
	add_child(spr)
	_lamp_sprites.append(spr)
	var l := PointLight2D.new()
	l.texture = tex
	l.color = lamp_color
	l.energy = lamp_energy
	l.texture_scale = 2.2
	l.position = pos - outside * 40.0
	l.enabled = enabled
	spr.visible = enabled
	add_child(l)
	_lamps.append(l)


static func _clear_of_roads(pos: Vector2, c: PackedVector2Array, min_distance: float) -> bool:
	for p in c:
		if p.distance_to(pos) < min_distance:
			return false
	return true


static func _radial_texture(size: int) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.45, Color(1, 1, 1, 0.55))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = size
	t.height = size
	return t


## Headlights: two beams from the lamps (y = +-HEAD_LAMP.y, a little apart)
## merging ahead, plus a faint pool so the car's own nose stays readable.
## Origin (the car centre) at x = BEAM_ORIGIN_X of the texture.
static func _car_light_texture() -> ImageTexture:
	var w := 340
	var h := 200
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var origin := Vector2(BEAM_ORIGIN_X, h * 0.5)
	for y in h:
		for x in w:
			var p := Vector2(x, y) - origin
			var glow := clampf(1.0 - p.length() / 40.0, 0.0, 1.0) * 0.3
			var cone := 0.0
			for side in [-1.0, 1.0]:
				var q := p - Vector2(HEAD_LAMP.x - 4.0, HEAD_LAMP.y * side)
				if q.x > 0.0:
					var ang := absf(atan2(q.y, q.x))
					var spread := clampf(1.0 - ang / deg_to_rad(19.0), 0.0, 1.0)
					var falloff := clampf(1.0 - q.x / 270.0, 0.0, 1.0)
					var near := clampf(q.x / 10.0, 0.0, 1.0)
					cone = maxf(cone, spread * spread * falloff * near * 0.85)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(glow + cone, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


## Taillights: two small red glows behind the car (centred on the rear bumper).
static func _tail_light_texture() -> ImageTexture:
	var w := 64
	var h := 72
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var c := Vector2(w * 0.5, h * 0.5)
	for y in h:
		for x in w:
			var a := 0.0
			for side in [-1.0, 1.0]:
				var d := (Vector2(x, y) - (c + Vector2(0, TAIL_LAMP.y * side))).length()
				a = maxf(a, clampf(1.0 - d / 26.0, 0.0, 1.0))
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)


## DIAGNOSTIC probe (Performance Investigation 001)
func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process__perf(delta)
	PerfProbe.add(&"pres.lighting", __t)


## DIAGNOSTIC probe (Performance Investigation 001)
func set_enabled(on: bool) -> void:
	var __t := Time.get_ticks_usec()
	set_enabled__perf(on)
	PerfProbe.add(&"pres.lighting_set", __t)
