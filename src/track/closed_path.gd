class_name ClosedPath
extends RefCounted
## A closed polyline with arc-length lookup and projection. Used for race
## progress (distance along the centreline) and by the AI to follow lines.

var points: PackedVector2Array
## cumulative[i] = distance from point 0 to point i along the path.
var cumulative: PackedFloat32Array
var length := 0.0


func _init(p_points: PackedVector2Array) -> void:
	points = p_points
	cumulative = PackedFloat32Array()
	var total := 0.0
	for i in points.size():
		cumulative.append(total)
		total += points[i].distance_to(points[(i + 1) % points.size()])
	length = total


## Wraps any distance into [0, length).
func wrap_distance(s: float) -> float:
	return fposmod(s, length)


## Index of the segment containing distance s.
func index_at(s: float) -> int:
	s = wrap_distance(s)
	var lo := 0
	var hi := points.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if cumulative[mid] <= s:
			lo = mid
		else:
			hi = mid - 1
	return lo


func point_at(s: float) -> Vector2:
	s = wrap_distance(s)
	var i := index_at(s)
	var a := points[i]
	var b := points[(i + 1) % points.size()]
	var seg := a.distance_to(b)
	return a if seg <= 0.0 else a.lerp(b, (s - cumulative[i]) / seg)


## Unit driving direction at distance s.
func tangent_at(s: float) -> Vector2:
	var i := index_at(s)
	return (points[(i + 1) % points.size()] - points[i]).normalized()


## Closest point on the path. Searches +-window segments around hint_index, or
## the whole path when hint_index < 0. Returns {index, distance, lateral, point};
## lateral > 0 means right of the driving direction.
func project(pos: Vector2, hint_index: int = -1, window: int = 12) -> Dictionary:
	var n := points.size()
	var first := 0
	var count := n
	if hint_index >= 0 and window * 2 + 1 < n:
		first = hint_index - window
		count = window * 2 + 1
	var best := {"index": 0, "distance": 0.0, "lateral": 0.0, "point": points[0]}
	var best_d2 := INF
	for k in count:
		var i := posmod(first + k, n)
		var a := points[i]
		var b := points[(i + 1) % n]
		var ab := b - a
		var t := 0.0 if ab.length_squared() == 0.0 else clampf((pos - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var q := a + ab * t
		var d2 := pos.distance_squared_to(q)
		if d2 < best_d2:
			best_d2 = d2
			var dir := ab.normalized()
			var right := Vector2(-dir.y, dir.x)
			best = {"index": i, "distance": cumulative[i] + ab.length() * t,
				"lateral": (pos - q).dot(right), "point": q}
	return best
