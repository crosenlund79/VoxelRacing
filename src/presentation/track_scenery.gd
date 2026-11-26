class_name TrackScenery
extends Node2D
## Decorative trackside scenery and road decals. Visual only: no collision
## shapes, no physics, its own random generator (never the race seeds), and it
## only reads the track's geometry. Ambient animation: trees sway, flags wave.
## The props and every asset follow the track's theme variant (TrackTheme).

const SEED := 4242
## Minimum distance from any decoration's centre to the barrier face (px).
const CLEARANCE := 70.0

var _sway: Array[Sprite2D] = []
var _flags: Array[Sprite2D] = []
var _time := 0.0
var _theme: TrackTheme


## decals go on the road under the cars; props sit on the grass.
func build(track: Track, resolver: AssetResolver, decal_layer: Node2D) -> void:
	_theme = track.theme if track.theme != null else TrackTheme.load_variant(1)
	_landmarks.clear()
	_extra = PackedFloat32Array()
	if not track.layout.branches.is_empty():
		for i in track.centerline.size():
			var widen := maxf(track.left_widths[i], track.right_widths[i]) - track.layout.road_width * 0.5
			_extra.append(widen + 24.0 if widen > 0.5 else 0.0)  # (a margin only where the road really widens)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var c := track.centerline
	var half := track.layout.road_width * 0.5
	var tans := TrackLayout.tangents(c)
	var n := c.size()
	# Grid boxes on the start grid.
	for slot in 10:
		var g := track.grid_transform(slot)
		_sprite(decal_layer, resolver, AssetCatalog.GRID_BOX, g.origin + Vector2.from_angle(g.get_rotation()) * 4.0, g.get_rotation(), Color(1, 1, 1, 0.75))
	# Road wear where the track turns most (corner apexes).
	var curvature := PackedFloat32Array()
	for i in n:
		curvature.append(absf(tans[i].angle_to(tans[(i + 6) % n])))
	for i in n:
		if curvature[i] > 0.35 and i % 7 == 0:
			var side := signf(tans[i].cross(tans[(i + 6) % n]))
			var right := Vector2(-tans[i].y, tans[i].x)
			_sprite(decal_layer, resolver, AssetCatalog.ROAD_WEAR, c[i] + right * side * half * 0.35, tans[i].angle(), Color(1, 1, 1, 0.55))
	# Grandstands along the main straight, on the outside, crowd facing the track.
	var start_dir := tans[0]
	var start_out := -Vector2(-start_dir.y, start_dir.x)  # outside of a clockwise lap = left
	for k in ([-2, -1, 0, 1, 2] if _theme.grandstands else []):
		var s := fposmod(k * 320.0 + 160.0, track.path.length)
		var p := track.path.point_at(s) + start_out * (half + 150.0)
		if _clear(p, c, half + 90.0):
			var st := _sprite(self, resolver, AssetCatalog.GRANDSTAND, p, start_dir.angle())
			st.z_index = 1
			_landmarks.append([p, _radius(AssetCatalog.GRANDSTAND)])
	# Props scattered around the circuit, clear of the barriers.
	var kinds := []
	for k in _theme.scenery.size():
		kinds.append([_theme.scenery[k], _theme.scenery_weights[k], _theme.scenery_sway[k]])
	var placed := 0
	var attempts := 0
	_add_landmarks(track, resolver, rng, c, tans, half)
	while placed < _theme.scenery_count and attempts < 2000:
		attempts += 1
		var i := rng.randi_range(0, n - 1)
		var right := Vector2(-tans[i].y, tans[i].x)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var p := c[i] + right * side * (half + rng.randf_range(CLEARANCE + 30.0, 520.0)) + Vector2(rng.randf_range(-40, 40), rng.randf_range(-40, 40))
		var kind: Array = _pick(kinds, rng)
		if not _clear(p, c, half + maxf(CLEARANCE, _radius(kind[0])) + 30.0) or _overlaps_landmark(p, _radius(kind[0])):
			continue
		var spr := _sprite(self, resolver, kind[0], p, rng.randf_range(0, TAU))
		var scale_jitter := rng.randf_range(0.8, 1.2)
		spr.scale *= scale_jitter
		spr.z_index = 2 if kind[2] else 0
		if kind[2]:
			spr.set_meta("phase", rng.randf_range(0, TAU))
			spr.set_meta("base_rot", spr.rotation)
			_sway.append(spr)
		placed += 1
	if _theme.kerbs:
		_add_kerbs(track, resolver, decal_layer, c, tans, curvature)
	# Tyre stacks and waving flags on the outside of the corners.
	for i in n:
		if curvature[i] > 0.45 and i % 11 == 0:
			var side := signf(tans[i].cross(tans[(i + 6) % n]))
			var right := Vector2(-tans[i].y, tans[i].x)
			var outside := -right * side
			var p := c[i] + outside * (half + 60.0)
			if _clear(p, c, half + 45.0):
				_sprite(self, resolver, AssetCatalog.TYRE_STACK, p, rng.randf_range(0, TAU))
				var fp := p + tans[i] * 50.0 + outside * 10.0
				if _clear(fp, c, half + 45.0):
					_flags.append(_flag(resolver, fp))


## Big environment props (The Raceway's boards and pit building, Tabletop
## Mayhem's giant pencils, cards and paperclips): each keeps its whole display
## size clear of every road and of the other landmarks, so nothing hides the
## road or looks like a barrier that is not there.
var _landmarks: Array = []  # [position, radius]


func _add_landmarks(track: Track, resolver: AssetResolver, rng: RandomNumberGenerator, c: PackedVector2Array, tans: PackedVector2Array, half: float) -> void:
	var n := c.size()
	if _theme.pit_building:
		var r := _radius("scenery/pit_building")
		var spots: Array = [[-600.0, 1.0], [-900.0, 1.0], [-300.0, 1.0], [-1200.0, 1.0]]
		var pb := track.layout.pit_branch()
		if pb >= 0:  # beside the pit lane's service box, behind its outer wall
			var b: Dictionary = track.layout.branches[pb]
			spots.push_front([float(b.box), float(b.side)])
		for spot in spots:
			var at := fposmod(spot[0], track.path.length)
			var tan := track.path.tangent_at(at)
			var right := Vector2(-tan.y, tan.x) * float(spot[1])
			var pit_size: Vector2 = AssetCatalog.SPECS[_theme.asset("scenery/pit_building")].display_size
			var widen: float = _extra[track.path.index_at(at)] if not _extra.is_empty() else 0.0
			var p: Vector2 = track.path.point_at(at) + right * (half + widen + 30.0 + pit_size.y * 0.5)
			if _clear(p, c, half + 40.0) and _clear_of_box(p, tan, "scenery/pit_building", c, half):
				var pit := _sprite(self, resolver, "scenery/pit_building", p, tan.angle() + (PI if spot[1] > 0.0 else 0.0))
				pit.z_index = 1
				_landmarks.append([p, r])
				break
	for k in _theme.landmarks.size():
		var logical: String = _theme.landmarks[k]
		var facing: bool = k < _theme.landmark_facing.size() and _theme.landmark_facing[k]
		var want: int = _theme.landmark_counts[k] if k < _theme.landmark_counts.size() else 4
		var r := _radius(logical)
		var size: Vector2 = AssetCatalog.SPECS[_theme.asset(logical)].display_size
		var done := 0
		var tries := 0
		while done < want and tries < 600:
			tries += 1
			var i := rng.randi_range(0, n - 1)
			var right := Vector2(-tans[i].y, tans[i].x)
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			var p: Vector2
			var rot: float
			if facing:  # boards stand just behind the barrier, text towards the road
				p = c[i] + right * side * (half + 40.0 + size.y * 0.5)
				rot = tans[i].angle() + (PI if side > 0.0 else 0.0)
				if not _clear(p, c, half + 30.0 + size.y * 0.5 - 2.0) or not _clear_of_box(p, Vector2.from_angle(rot), logical, c, half):
					continue
			else:
				p = c[i] + right * side * (half + r + rng.randf_range(40.0, 420.0))
				rot = rng.randf_range(0, TAU)
				if not _clear(p, c, half + r + 24.0):
					continue
			if _overlaps_landmark(p, r if not facing else size.y * 0.5):
				continue
			var spr := _sprite(self, resolver, logical, p, rot)
			spr.z_index = 1
			_landmarks.append([p, r if not facing else size.x * 0.5])
			done += 1


## Kerbs (decals) along the road edges where the circuit turns.
func _add_kerbs(track: Track, resolver: AssetResolver, decal_layer: Node2D, c: PackedVector2Array, tans: PackedVector2Array, curvature: PackedFloat32Array) -> void:
	var n := c.size()
	var halves := track.half_widths
	var length: float = AssetCatalog.SPECS[_theme.asset("decals/kerb")].display_size.x
	var last := {-1.0: Vector2.INF, 1.0: Vector2.INF}
	for i in n:
		if curvature[i] < 0.3:
			last = {-1.0: Vector2.INF, 1.0: Vector2.INF}
			continue
		var right := Vector2(-tans[i].y, tans[i].x)
		var h: float = halves[i] if i < halves.size() else track.layout.road_width * 0.5
		for side in [-1.0, 1.0]:
			var p: Vector2 = c[i] + right * side * (h - 7.0)
			if last[side] != Vector2.INF and p.distance_to(last[side]) < length * 0.92:
				continue  # one piece per kerb length: no bunching on the inside of tight corners
			var from: Vector2 = last[side]
			if from == Vector2.INF or p.distance_to(from) > length * 1.5:
				_sprite(decal_layer, resolver, "decals/kerb", p, tans[i].angle())
			else:  # the next piece in the chain, laid along the edge between the anchors
				_sprite(decal_layer, resolver, "decals/kerb", (p + from) * 0.5, (p - from).angle())
			last[side] = p
			_kerb_count += 1


var _kerb_count := 0


func kerb_count() -> int:
	return _kerb_count


func landmark_count() -> int:
	return _landmarks.size()


## Radius that keeps the whole prop clear (half its display diagonal).
func _radius(logical: String) -> float:
	var key := _theme.asset(logical)
	if not AssetCatalog.SPECS.has(key):
		return 0.0
	var size: Vector2 = AssetCatalog.SPECS[key].display_size
	return size.length() * 0.5


func _overlaps_landmark(p: Vector2, r: float) -> bool:
	for l in _landmarks:
		if p.distance_to(l[0]) < r + l[1] + 16.0:
			return true
	return false


## A rotated rectangular prop: every corner and edge midpoint clear of the road.
func _clear_of_box(p: Vector2, along: Vector2, logical: String, c: PackedVector2Array, half: float) -> bool:
	var size: Vector2 = AssetCatalog.SPECS[_theme.asset(logical)].display_size
	var ax := along.normalized() * size.x * 0.5
	var ay := Vector2(-along.y, along.x).normalized() * size.y * 0.5
	for fx in [-1.0, 0.0, 1.0]:
		for fy in [-1.0, 0.0, 1.0]:
			if not _clear(p + ax * fx + ay * fy, c, half + 14.0):
				return false
	return true


## Branches widen the road (pit lanes, split sections): per centreline sample,
## how much wider than the plain half width it is on its wider side.
var _extra := PackedFloat32Array()


## Clear of the road by min_distance from the centreline, plus any widening.
func _clear(p: Vector2, centerline: PackedVector2Array, min_distance: float) -> bool:
	if _extra.is_empty():
		return _clear_of_track(p, centerline, min_distance)
	for i in centerline.size():
		var d := min_distance + _extra[i]
		if p.distance_squared_to(centerline[i]) < d * d:
			return false
	return true


func _process__perf(delta: float) -> void:
	_time += delta
	for s in _sway:
		s.rotation = s.get_meta("base_rot") + sin(_time * 0.9 + s.get_meta("phase")) * 0.035
	var frame := int(_time * 4.0) % 2
	for f in _flags:
		f.frame = (frame + int(f.get_meta("offset"))) % 2


func sway_count() -> int:
	return _sway.size()


func flag_count() -> int:
	return _flags.size()


static func _clear_of_track(p: Vector2, centerline: PackedVector2Array, min_distance: float) -> bool:
	var d2 := min_distance * min_distance
	for q in centerline:
		if p.distance_squared_to(q) < d2:
			return false
	return true


static func _pick(kinds: Array, rng: RandomNumberGenerator) -> Array:
	var total := 0.0
	for k in kinds:
		total += k[1]
	var r := rng.randf() * total
	for k in kinds:
		r -= k[1]
		if r <= 0.0:
			return k
	return kinds[0]


func _sprite(parent: Node, resolver: AssetResolver, shared_logical: String, pos: Vector2, rot: float, tint: Color = Color.WHITE) -> Sprite2D:
	var logical := _theme.asset(shared_logical)
	var spr := Sprite2D.new()
	spr.texture = resolver.get_texture(logical)
	spr.position = pos
	spr.rotation = rot
	spr.modulate = tint
	spr.scale = AssetCatalog.scale_for(spr.texture, AssetCatalog.SPECS[logical].display_size)
	parent.add_child(spr)
	return spr


func _flag(resolver: AssetResolver, pos: Vector2) -> Sprite2D:
	var spr := Sprite2D.new()
	var logical := _theme.asset(AssetCatalog.FLAG)
	spr.texture = resolver.get_texture(logical)
	spr.hframes = AssetCatalog.SPECS[logical].frames
	spr.position = pos
	var frame_size := Vector2(spr.texture.get_width() / float(spr.hframes), spr.texture.get_height())
	spr.scale = AssetCatalog.SPECS[logical].display_size / frame_size
	spr.offset = Vector2(0, -frame_size.y * 0.4)
	spr.z_index = 2
	spr.set_meta("offset", _flags.size() % 2)
	add_child(spr)
	return spr


## DIAGNOSTIC probe (Performance Investigation 001)
func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process__perf(delta)
	PerfProbe.add(&"legacy2d.track_scenery", __t)
