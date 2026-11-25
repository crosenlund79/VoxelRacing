class_name ArenaLayout
extends RefCounted
## The Scrapyard: the Battle Royale arena's geometry (pure data, no scene). An
## eight-sided yard walled in all round, with a scrap pile in the middle,
## four concrete blocks on the diagonals, two crash barriers that split the
## long sides into lanes, and four tyre posts. Wide open rings around the
## pile for ramming runs, tight gaps between blocks for close fights, and no
## dead ends. Used for the physics bodies, the missiles' "hit something" test
## and the arena AI's look-ahead.

## Outer wall (clockwise).
var boundary := PackedVector2Array([Vector2(-1250, -500), Vector2(-900, -850), Vector2(900, -850),
	Vector2(1250, -500), Vector2(1250, 500), Vector2(900, 850), Vector2(-900, 850), Vector2(-1250, 500)])
## Solid convex obstacles: {kind: "pile" | "block" | "barrier", points}.
var polygons: Array = []
## Round tyre posts: {centre, radius}.
var posts: Array = []
## Where the ten cars start (facing the middle).
var spawns: Array[Transform2D] = []
## Presentation geometry (shared by the arena and its setup-screen preview):
## grandstands outside the long walls (centre; facing the yard), and lamp
## spots on the walls ([position, outward direction]).
var stands: Array[Vector2] = [Vector2(-560, -1010), Vector2(0, -1010), Vector2(560, -1010),
	Vector2(-560, 1010), Vector2(0, 1010), Vector2(560, 1010)]
var lamps: Array = [[Vector2(-1060, -665), Vector2(-1, -1)], [Vector2(1060, -665), Vector2(1, -1)],
	[Vector2(-1060, 665), Vector2(-1, 1)], [Vector2(1060, 665), Vector2(1, 1)],
	[Vector2(0, -838), Vector2(0, -1)], [Vector2(0, 838), Vector2(0, 1)],
	[Vector2(-560, -838), Vector2(0, -1)], [Vector2(560, -838), Vector2(0, -1)],
	[Vector2(-560, 838), Vector2(0, 1)], [Vector2(560, 838), Vector2(0, 1)],
	[Vector2(-1238, 0), Vector2(-1, 0)], [Vector2(1238, 0), Vector2(1, 0)]]


func _init() -> void:
	polygons.append({"kind": "pile", "points": _ngon(Vector2.ZERO, 150.0, 9, 0.2)})
	for spec in [[Vector2(-560, -380), 0.5], [Vector2(560, 380), 0.5], [Vector2(560, -380), -0.5], [Vector2(-560, 380), -0.5]]:
		polygons.append({"kind": "block", "points": _box(spec[0], Vector2(180, 60), spec[1])})
	for x in [-860.0, 860.0]:
		polygons.append({"kind": "barrier", "points": _box(Vector2(x, 0), Vector2(46, 300), 0.0)})
	for c in [Vector2(0, -560), Vector2(0, 560), Vector2(-330, 0), Vector2(330, 0)]:
		posts.append({"centre": c, "radius": 30.0})
	for k in 10:
		var a := TAU * (k + 0.5) / 10.0
		var pos := Vector2(cos(a) * 1000.0, sin(a) * 660.0)
		spawns.append(Transform2D((-pos).angle() + PI * 0.5, pos))  # round the ring, not at each other


## True when a point is inside (or within margin of) a wall or an obstacle.
func blocked(p: Vector2, margin: float = 0.0) -> bool:
	if not Geometry2D.is_point_in_polygon(p, boundary) or _edge_distance(p, boundary) < margin:
		return true
	for o in polygons:
		if Geometry2D.is_point_in_polygon(p, o.points) or (margin > 0.0 and _edge_distance(p, o.points) < margin):
			return true
	for t in posts:
		if p.distance_to(t.centre) < t.radius + margin:
			return true
	return false


## True when the straight line a-b crosses no obstacle (the outer wall is not
## checked: both ends are inside the arena).
func clear_line(a: Vector2, b: Vector2) -> bool:
	for o in polygons:
		var pts: PackedVector2Array = o.points
		if Geometry2D.is_point_in_polygon(b, pts):
			return false
		for i in pts.size():
			if Geometry2D.segment_intersects_segment(a, b, pts[i], pts[(i + 1) % pts.size()]) != null:
				return false
	for t in posts:
		if Geometry2D.get_closest_point_to_segment(t.centre, a, b).distance_to(t.centre) < t.radius:
			return false
	return true


## A rough size for the zone and the cameras.
func radius() -> float:
	return 1250.0


static func _edge_distance(p: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	for i in poly.size():
		best = minf(best, Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()]).distance_to(p))
	return best


static func _box(centre: Vector2, size: Vector2, angle: float) -> PackedVector2Array:
	var h := size * 0.5
	var out := PackedVector2Array()
	for c in [Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)]:
		out.append(centre + c.rotated(angle))
	return out


static func _ngon(centre: Vector2, r: float, n: int, wobble: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in n:
		var rr := r * (1.0 + wobble * (0.5 if k % 2 == 0 else -0.3))
		out.append(centre + Vector2.from_angle(TAU * k / n) * rr)
	return out


## (A flat yard: no bridges, no jumps, no branches; VoxelTrack asks.)
func has_elevation() -> bool:
	return false


func has_jumps() -> bool:
	return false
