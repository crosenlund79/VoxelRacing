class_name RacingLine
extends RefCounted
## Racing line for one track: lateral offsets from the centreline that cut
## corners within the road, and a target speed at every sample derived from the
## shared driving parameters (steering-limited corner speed + braking distance).
## Pure data, built once per track; samples match the centreline samples.
##
## Branches (2026-11-17): a track with pit lanes / split sections has three
## routes, each a complete line: ROUTE_MAIN (every split's left lane, the
## racing road past the pit), ROUTE_ALT (every split's right lane) and
## ROUTE_PIT (through the pit lane, at the pit limiter's speed). A driver
## chooses per branch; the routes are identical away from the branches.

const ROUTE_MAIN := 0
const ROUTE_ALT := 1
const ROUTE_PIT := 2

var center: ClosedPath
## Route 0's offsets and speeds (the line every caller used before branches).
var offsets := PackedFloat32Array()
var speeds := PackedFloat32Array()
## Furthest the racing line itself goes from the centreline (px).
var max_lateral := 0.0
var road_half_width := 0.0
## Per sample (narrow sections): half the road width and the line's limit;
## empty = road_half_width / max_lateral everywhere.
var half_widths := PackedFloat32Array()
var _max_lat := PackedFloat32Array()
## Highest target speed on the line (straights).
var top_speed := 0.0
var _normals := PackedVector2Array()
## Branches: the layout (null = none), per route [offsets, speeds], and the
## lateral bounds per route and sample (Vector2 lo, hi).
var layout: TrackLayout = null
var routes: Array = []
var _bounds: Array = []
var _margin := 0.0
## The deceleration the speed profile plans with (px/s^2), for pit stops.
var plan_decel := 150.0


func _init(p_center: ClosedPath, road_width: float, driving: DrivingParams, ai: AiParams,
		p_half_widths: PackedFloat32Array = PackedFloat32Array(), p_layout: TrackLayout = null, pit_cap := 0.0) -> void:
	center = p_center
	road_half_width = road_width * 0.5
	max_lateral = maxf(0.0, road_half_width - ai.line_margin)
	_margin = ai.line_margin
	if p_half_widths.size() == center.points.size():
		half_widths = p_half_widths
		for h in half_widths:
			_max_lat.append(maxf(0.0, h - ai.line_margin))
	var n := center.points.size()
	for i in n:
		var t := (center.points[(i + 1) % n] - center.points[(i - 1 + n) % n]).normalized()
		_normals.append(Vector2(-t.y, t.x))
	if p_layout != null and not p_layout.branches.is_empty():
		layout = p_layout
	var count := 3 if layout != null else 1
	for r in count:
		_bounds.append(_route_bounds(r))
		offsets = PackedFloat32Array()
		offsets.resize(n)
		offsets.fill(0.0)
		_optimise(ai.line_iterations, r)
		speeds = PackedFloat32Array()
		_build_speeds(driving, ai, r, pit_cap if pit_cap > 0.0 else driving.max_speed * 0.5)
		routes.append([offsets, speeds])
	offsets = routes[0][0]
	speeds = routes[0][1]
	top_speed = 0.0
	for v in speeds:
		top_speed = maxf(top_speed, v)


func route_count() -> int:
	return routes.size()


func position(i: int, route: int = 0) -> Vector2:
	return center.points[i] + _normals[i] * routes[route][0][i] if not routes.is_empty() else \
		center.points[i] + _normals[i] * offsets[i]


## Lateral offset of the line at distance s along the centreline.
func offset_at(s: float, route: int = 0) -> float:
	var o: PackedFloat32Array = routes[mini(route, routes.size() - 1)][0]
	var i := center.index_at(s)
	var j := (i + 1) % center.points.size()
	var seg := center.points[i].distance_to(center.points[j])
	var t := 0.0 if seg <= 0.0 else (center.wrap_distance(s) - center.cumulative[i]) / seg
	return lerpf(o[i], o[j], clampf(t, 0.0, 1.0))


## Half the road width at distance s (narrow sections; else road_half_width).
func half_width_at(s: float) -> float:
	if half_widths.is_empty():
		return road_half_width
	return half_widths[center.index_at(s)]


## Lateral room Vector2(lo, hi) of a route at s (the lane it uses in a branch).
func bounds_at(s: float, route: int = 0) -> Vector2:
	if layout == null:
		var h := half_width_at(s)
		return Vector2(-h, h)
	return _bounds[mini(route, _bounds.size() - 1)][center.index_at(s)]


func speed_at(s: float, route: int = 0) -> float:
	return routes[mini(route, routes.size() - 1)][1][center.index_at(s)]


## World point at distance s with a given lateral offset from the centreline.
func point_with_lateral(s: float, lateral: float) -> Vector2:
	var t := center.tangent_at(s)
	return center.point_at(s) + Vector2(-t.y, t.x) * lateral


## Time (s) to drive a branch's stretch on a route at the line's speeds.
func route_time(branch: int, route: int) -> float:
	var b: Dictionary = layout.branches[branch]
	var t := 0.0
	var s: float = b.from
	while s < float(b.to):
		t += 20.0 / maxf(speed_at(s, route), 1.0)
		s += 20.0
	return t


## The lane a route uses in branch b: 1 = a split's right lane / the pit lane.
static func lane_of(route: int, kind: String) -> int:
	if kind == "split":
		return 1 if route == ROUTE_ALT else 0
	return 1 if route == ROUTE_PIT else 0


func _route_bounds(route: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := center.points.size()
	for i in n:
		var s := center.cumulative[i]
		if layout == null:
			var h := half_widths[i] if not half_widths.is_empty() else road_half_width
			out.append(Vector2(-h, h))
			continue
		var k := layout.branch_at(s, center.length)
		var lane := 0 if k < 0 else lane_of(route, layout.branches[k].kind)
		out.append(layout.route_bounds(s, center.length, lane))
	return out


## Repeatedly pulls each point towards the midpoint of its neighbours (shortening
## and straightening the line), clamped inside the route's room.
func _optimise(iterations: int, route: int) -> void:
	var n := offsets.size()
	var bounds: PackedVector2Array = _bounds[route]
	for it in iterations:
		for i in n:
			var mid := (_pos(i - 2) + _pos(i + 2)) * 0.5
			var b := bounds[i]
			var m := minf(_margin, maxf(0.0, (b.y - b.x) * 0.5 - 4.0))
			var lo := b.x + m
			var hi := b.y - m
			if layout == null:  # unchanged maths for tracks without branches
				var lim := max_lateral if _max_lat.is_empty() else _max_lat[i]
				lo = -lim
				hi = lim
			offsets[i] = clampf((mid - center.points[i]).dot(_normals[i]), lo, hi)


func _pos(i: int) -> Vector2:
	var n := offsets.size()
	var k := posmod(i, n)
	return center.points[k] + _normals[k] * offsets[k]


func _build_speeds(driving: DrivingParams, ai: AiParams, route: int, pit_cap: float) -> void:
	var n := offsets.size()
	speeds.resize(n)
	var turn_rate := deg_to_rad(driving.turn_rate_degrees)
	for i in n:
		var r := _radius(i)
		speeds[i] = minf(driving.max_speed, ai.corner_speed_factor * turn_rate * r)
		if route == ROUTE_PIT and layout != null:  # at the limiter's speed before the lane begins
			var s := center.cumulative[i]
			var k := layout.branch_at(s, center.length)
			if k >= 0 and layout.branches[k].kind == "pit":
				var b: Dictionary = layout.branches[k]
				if s >= float(b.from) + float(b.ramp) * 0.4 and s <= float(b.to) - float(b.ramp):
					speeds[i] = minf(speeds[i], pit_cap * 0.95)
	var decel := driving.release_deceleration * ai.brake_planning_factor
	plan_decel = decel
	for pass_index in 2:
		for k in n:
			var i := n - 1 - k
			var j := (i + 1) % n
			var ds := _pos(i).distance_to(_pos(j))
			speeds[i] = minf(speeds[i], sqrt(speeds[j] * speeds[j] + 2.0 * decel * ds))


## Radius of the circle through the line points 3 samples either side (INF on straights).
func _radius(i: int) -> float:
	var a := _pos(i - 3)
	var b := _pos(i)
	var c := _pos(i + 3)
	var cross := absf((b - a).cross(c - a))
	if cross < 0.001:
		return INF
	return a.distance_to(b) * b.distance_to(c) * c.distance_to(a) / (2.0 * cross)
