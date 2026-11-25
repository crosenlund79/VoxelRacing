class_name CircuitPreview
extends Control
## A small rotating diorama of a circuit (or, for Battle Royale, of the
## Scrapyard arena: show_arena) for the race setup screen: a
## low-poly plate in the environment's colours with the real centreline on it,
## bridges lifted on pillars, the jump's gap left open, the start line and a
## few faceted trees. Procedural 2.5D (tilted projection, custom drawing); no
## 3D scene, no artwork. Rebuilt whenever the circuit, environment or time changes.

const TILT := 0.5
const LIFT := 16.0
const PLATE_SIDES := 18
const SPIN := 0.22  # rad/s
## Pit lanes and split lanes are drawn this much further from the centreline
## than they really are, so they read at preview size.
const BRANCH_SPREAD := 3.0

## Environment palettes (variant -> colours): plate top, plate side, road, barrier, trees.
const PALETTES := {
	1: {"top": Color("6f9a52"), "side": Color("46623a"), "road": Color("707177"), "edge": Color("c84a3a"), "tree": Color("3f7a3a"), "tip": Color("5d9a4f")},
	2: {"top": Color("86724f"), "side": Color("5a4b35"), "road": Color("5b5e68"), "edge": Color("bfae92"), "tree": Color("7a4f6f"), "tip": Color("a2709a")},
	3: {"top": Color("e6edf5"), "side": Color("9fb0c6"), "road": Color("6d7684"), "edge": Color("3a64a8"), "tree": Color("2f5d4a"), "tip": Color("f4f8ff")},
	4: {"top": Color("5f9a4e"), "side": Color("3c5f34"), "road": Color("4a4c54"), "edge": Color("d8423a"), "edge2": Color("f2efe8"), "tree": Color("8a8f9a"), "tip": Color("f6f4dc"), "props": "flood"},
	5: {"top": Color("b47c48"), "side": Color("7a5030"), "road": Color("5e6380"), "edge": Color("e8c068"), "tree": Color("f4c234"), "tip": Color("e88c9c"), "props": "desk"},
}

var angle := 0.0
var layout: TrackLayout
var variant := 1
var night := false
var _pts := PackedVector2Array()   # centred, scaled centreline (decimated)
var _lift := PackedFloat32Array()  # 0..1 height per point
var _gap := PackedByteArray()       # 1 = in a flyover jump's gap (no road)
var _trees := PackedVector2Array()
## Branches from the real geometry: [lane points (preview space), is_pit, box point].
var _branches: Array = []
var _radius := 1.0
## Fits the plate into the control (set each frame from its size).
var _zoom := 1.0


func _ready() -> void:
	custom_minimum_size = Vector2(420, 300)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# ------------------------------------------------ The Scrapyard (2026-11-23)
# Battle Royale's arena as a rotating diorama from the real ArenaLayout: the
# octagonal yard and its walls, the scrap pile (stacked wrecks in the rivals'
# colours), the four concrete blocks with hazard stripes, the two crash
# barriers, the tyre posts, the grandstands and - at night - the lamps.
# Procedural like the circuits (no new artwork).

var arena: ArenaLayout = null
var _arena_scale := 1.0
## The pile's wrecks: [centre, half size, angle, colour, height] (preview space).
var _wrecks: Array = []

## Rival car colours for the scrap (1..9, from the template bodies' paint).
const SCRAP_COLORS := [Color("8fae8a"), Color("e6b33a"), Color("4f8fb8"), Color("3aa3a0"), Color("e9e6dc"),
	Color("9a3a5a"), Color("8a8a4a"), Color("3a3a42"), Color("d65aa0"), Color("c84a32")]


func show_arena(p_arena: ArenaLayout, p_variant: int, p_night: bool) -> void:
	arena = p_arena
	layout = null
	variant = clampi(p_variant, 1, PALETTES.size())
	night = p_night
	_arena_scale = 300.0 / 2500.0  # (the yard is 2500 px across)
	_radius = 0.0
	for p in arena.boundary:
		_radius = maxf(_radius, (p * _arena_scale).length())
	for st in arena.stands:
		_radius = maxf(_radius, (st * _arena_scale).length() + 10.0)
	_radius += 14.0
	_wrecks.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1991
	var pile: PackedVector2Array = arena.polygons[0].points
	for k in 13:
		var c := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 105.0)
		if not Geometry2D.is_point_in_polygon(c, pile):
			continue
		_wrecks.append([c * _arena_scale, Vector2(rng.randf_range(7, 10), rng.randf_range(4, 5.5)), rng.randf() * TAU,
			SCRAP_COLORS[k % SCRAP_COLORS.size()], rng.randf_range(0.3, 1.3)])
	queue_redraw()


func showing_arena() -> bool:
	return arena != null


## A box standing on the plate: its sides (front faces) and its top, at
## height h (in LIFT units).
func _prism(pts: PackedVector2Array, h: float, top: Color, side: Color) -> void:
	var n := pts.size()
	var centre := Vector2.ZERO
	for p in pts:
		centre += p
	centre /= n
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var m := (a + b) * 0.5
		if _project(m + (m - centre).normalized()).y > _project(m).y:  # faces the viewer
			draw_colored_polygon(PackedVector2Array([_project(a, h), _project(b, h), _project(b), _project(a)]), side)
	var t := PackedVector2Array()
	for p in pts:
		t.append(_project(p, h))
	draw_colored_polygon(t, top)


func _draw_arena() -> void:
	var pal: Dictionary = PALETTES[variant]
	_zoom = minf(size.x * 0.94 / (2.0 * _radius), (size.y - 40.0) / (2.0 * _radius * TILT + 20.0))
	var w := clampf(_zoom, 1.0, 1.8)
	var k := _arena_scale
	# the plate (the biome's ground) with a visible side
	var top := PackedVector2Array()
	var bottom := PackedVector2Array()
	for i in PLATE_SIDES:
		var p := Vector2.from_angle(TAU * i / PLATE_SIDES) * _radius
		top.append(_project(p))
		bottom.append(_project(p) + Vector2(0, 14 * w))
	for i in PLATE_SIDES:
		var a := top[i]
		var b := top[(i + 1) % PLATE_SIDES]
		if (a.y + b.y) * 0.5 > size.y * 0.5 - 2.0:
			draw_colored_polygon(PackedVector2Array([a, b, bottom[(i + 1) % PLATE_SIDES], bottom[i]]), _shade(pal.side))
	draw_colored_polygon(top, _shade(pal.top))
	# the yard floor: dusty tarmac inside the octagon
	var yard := PackedVector2Array()
	for p in arena.boundary:
		yard.append(_project(p * k))
	draw_colored_polygon(yard, _shade(Color(pal.road).lerp(Color("b8a88a"), 0.35)))
	# everything standing, back to front: walls (as short segments), stands,
	# obstacles, posts
	var items: Array = []
	var nb := arena.boundary.size()
	for i in nb:
		var a := arena.boundary[i] * k
		var b := arena.boundary[(i + 1) % nb] * k
		for s in 4:  # (short pieces sort well against the obstacles)
			var pa := a.lerp(b, s / 4.0)
			var pb := a.lerp(b, (s + 1) / 4.0)
			items.append(["wall", (pa + pb) * 0.5, [pa, pb]])
	for st in arena.stands:
		items.append(["stand", st * k, st * k])
	for o in arena.polygons:
		var pts := PackedVector2Array()
		var c := Vector2.ZERO
		for p in o.points:
			pts.append(p * k)
			c += p * k
		items.append([o.kind, c / pts.size(), pts])
	for t in arena.posts:
		items.append(["post", t.centre * k, t.radius * k])
	items.sort_custom(func(x: Array, y: Array) -> bool: return _project(x[1]).y < _project(y[1]).y)
	var wall_col: Color = pal.edge
	for it in items:
		match it[0]:
			"wall":
				var pa: Vector2 = it[2][0]
				var pb: Vector2 = it[2][1]
				draw_colored_polygon(PackedVector2Array([_project(pa, 0.55), _project(pb, 0.55), _project(pb), _project(pa)]),
					_shade(wall_col.darkened(0.15)))
				draw_line(_project(pa, 0.55), _project(pb, 0.55), _shade(wall_col.lightened(0.2)), 2.0 * w)
			"stand":
				var c: Vector2 = it[2]
				var half := Vector2(26, 6)
				var box := PackedVector2Array([c + Vector2(-half.x, -half.y), c + Vector2(half.x, -half.y),
					c + Vector2(half.x, half.y), c + Vector2(-half.x, half.y)])
				_prism(box, 1.0, _shade(Color("b8463a")), _shade(Color("7a3a32")))
				for s in 5:  # the crowd, a row of dots
					draw_circle(_project(c + Vector2(-20 + s * 10, 0), 1.0) + Vector2(0, -2), 1.6 * w,
						_shade([Color("f2efe8"), Color("e2b23c"), Color("74bdf2")][s % 3]))
			"block":
				var pts: PackedVector2Array = it[2]
				_prism(pts, 0.8, _shade(Color("d8c048")), _shade(Color("8a8478")))
				for s in 3:  # hazard stripes across the top
					var f := (s + 1) / 4.0
					draw_line(_project(pts[0].lerp(pts[1], f), 0.8), _project(pts[3].lerp(pts[2], f), 0.8), _shade(Color("2e2a28")), 2.0 * w)
			"barrier":
				var pts: PackedVector2Array = it[2]
				_prism(pts, 0.6, _shade(Color("e8e4dc")), _shade(Color("b8463a")))
			"pile":
				var pts: PackedVector2Array = it[2]
				_prism(pts, 0.25, _shade(Color("6a5a48")), _shade(Color("4a3e32")))
				var wrecks := _wrecks.duplicate()
				wrecks.sort_custom(func(x: Array, y: Array) -> bool: return _project(x[0]).y < _project(y[0]).y)
				for wr in wrecks:
					var c: Vector2 = wr[0]
					var h: Vector2 = wr[1]
					var box := PackedVector2Array()
					for corner in [Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)]:
						box.append(c + corner.rotated(wr[2]))
					var col: Color = wr[3]
					_prism(box, 0.25 + wr[4] * 0.5, _shade(col.darkened(0.15)), _shade(col.darkened(0.5)))
			"post":
				var c: Vector2 = it[1]
				var r: float = it[2]
				for s in 3:  # a stack of three tyres
					draw_circle(_project(c, 0.18 + s * 0.2), r * _zoom * 1.05, _shade(Color("26221f")))
					draw_circle(_project(c, 0.18 + s * 0.2), r * _zoom * 0.45, _shade(Color("4a4440")))
	if night:  # the lamps on the walls
		for l in arena.lamps:
			var at: Vector2 = l[0] * k
			draw_circle(_project(at, 0.9), 2.4, Color(1.0, 0.82, 0.45))
			draw_circle(_project(at, 0.9), 7.0, Color(1.0, 0.82, 0.45, 0.2))


func show_circuit(p_layout: TrackLayout, p_variant: int, p_night: bool) -> void:
	arena = null
	layout = p_layout
	variant = clampi(p_variant, 1, PALETTES.size())
	night = p_night
	var c := layout.sample_centerline()
	var path := ClosedPath.new(c)
	var bounds := Rect2(c[0], Vector2.ZERO)
	for p in c:
		bounds = bounds.expand(p)
	var centre := bounds.get_center()
	var scale_k := 300.0 / maxf(bounds.size.x, bounds.size.y)
	_pts.clear()
	_lift.clear()
	_gap.clear()
	_radius = 0.0
	for i in range(0, c.size(), 3):
		var q := (c[i] - centre) * scale_k
		_pts.append(q)
		_radius = maxf(_radius, q.length())
		var s := path.cumulative[i]
		var h := 0.0
		for z in layout.elevation_zones:
			if s >= z.x and s < z.y:
				var ramp := (z.y - z.x) * 0.3
				h = smoothstep(0.0, 1.0, minf(s - z.x, z.y - s) / ramp)
		_lift.append(h)
		var in_gap := 0
		for k in layout.jumps.size():
			var j := layout.jumps[k]
			if s > j.x and s < j.x + j.z and layout.is_flyover(k, path.length):
				in_gap = 1
		_gap.append(in_gap)
	_radius += 26.0
	_branches.clear()
	for k in layout.branches.size():
		var b: Dictionary = layout.branches[k]
		var lanes := [1] if b.kind == "pit" else [0, 1]
		for lane in lanes:
			var pts := PackedVector2Array()
			var at: float = b.from
			while at <= float(b.to) + 0.1:
				var bd := layout.route_bounds(at, path.length, lane)
				var t := path.tangent_at(at)
				var q := path.point_at(at) + Vector2(-t.y, t.x) * (bd.x + bd.y) * 0.5 * BRANCH_SPREAD
				pts.append((q - centre) * scale_k)
				at += 40.0
			var box := Vector2.INF
			if b.kind == "pit":
				var bb := layout.route_bounds(float(b.box), path.length, 1)
				var tb := path.tangent_at(float(b.box))
				box = (path.point_at(float(b.box)) + Vector2(-tb.y, tb.x) * (bb.x + bb.y) * 0.5 * BRANCH_SPREAD - centre) * scale_k
			_branches.append([pts, b.kind == "pit", box])
	_trees.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(layout.resource_path) + variant
	var tries := 0
	while _trees.size() < 14 and tries < 400:
		tries += 1
		var p := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.2, 0.93) * _radius
		var clear := true
		for q in _pts:
			if q.distance_to(p) < 22.0:
				clear = false
				break
		if clear:
			_trees.append(p)
	queue_redraw()


func _process(delta: float) -> void:
	if not is_visible_in_tree() or (layout == null and arena == null):
		return
	angle = fposmod(angle + delta * SPIN, TAU)
	queue_redraw()


func _project(p: Vector2, h: float = 0.0) -> Vector2:
	var r := p.rotated(angle) * _zoom
	return size * 0.5 + Vector2(0, 6) + Vector2(r.x, r.y * TILT) - Vector2(0, h * LIFT * _zoom)


func _shade(c: Color) -> Color:
	return c.darkened(0.55).lerp(Color(0.25, 0.32, 0.6), 0.25) if night else c


func _draw() -> void:
	if arena != null:
		_draw_arena()
		return
	if layout == null:
		return
	var pal: Dictionary = PALETTES[variant]
	_zoom = minf(size.x * 0.94 / (2.0 * _radius), (size.y - 40.0) / (2.0 * _radius * TILT + 20.0))
	var w := clampf(_zoom, 1.0, 1.8)  # line widths grow a little with the plate
	# the plate: a low-poly disc with a visible side
	var top := PackedVector2Array()
	var bottom := PackedVector2Array()
	for k in PLATE_SIDES:
		var p := Vector2.from_angle(TAU * k / PLATE_SIDES) * _radius
		top.append(_project(p))
		bottom.append(_project(p) + Vector2(0, 14 * w))
	for k in PLATE_SIDES:
		var a := top[k]
		var b := top[(k + 1) % PLATE_SIDES]
		if (a.y + b.y) * 0.5 > size.y * 0.5 - 2.0:  # front faces only
			draw_colored_polygon(PackedVector2Array([a, b, bottom[(k + 1) % PLATE_SIDES], bottom[k]]), _shade(pal.side))
	draw_colored_polygon(top, _shade(pal.top))
	# road on the ground, then the raised parts (bridges) with pillars
	var n := _pts.size()
	for pass_index in 2:
		for i in n:
			var j := (i + 1) % n
			if _gap[i] == 1 or _gap[j] == 1:
				continue
			var raised := _lift[i] > 0.05 or _lift[j] > 0.05
			if raised != (pass_index == 1):
				continue
			var a := _project(_pts[i], _lift[i])
			var b := _project(_pts[j], _lift[j])
			if raised and i % 2 == 0 and _lift[i] > 0.5:
				draw_line(_project(_pts[i]), a, _shade(pal.side), 3.0 * w)
			draw_line(a + Vector2(0, 2 * w), b + Vector2(0, 2 * w), _shade(pal.side), 9.0 * w)
			var edge: Color = pal.edge if not pal.has("edge2") or (i / 2) % 2 == 0 else pal.edge2
			draw_line(a, b, _shade(edge), 9.0 * w)
			draw_line(a, b, _shade(pal.road), 6.0 * w)
	# the jump's gap edges and the start line
	for i in n:
		if _gap[i] == 1 and _gap[(i - 1 + n) % n] == 0:
			draw_circle(_project(_pts[i], _lift[i]), 4.0, Color("f0c040"))
	# pit lanes (thin) and split lanes, from the real geometry; the service box in gold
	for br in _branches:
		var pts: PackedVector2Array = br[0]
		var lw := (3.0 if br[1] else 5.0) * w
		for i in pts.size() - 1:
			var a := _project(pts[i])
			var b := _project(pts[i + 1])
			draw_line(a, b, _shade(Color("f0c040") if br[1] else pal.edge), lw + 2.0 * w)
			draw_line(a, b, _shade(pal.road), lw)
		if br[1] and br[2] != Vector2.INF:
			draw_circle(_project(br[2]), 2.6 * w, Color("f0c040"))
	draw_circle(_project(_pts[0]), 3.5, Color.WHITE)
	# faceted trees (drawn back to front)
	var order := Array(_trees)
	order.sort_custom(func(a: Vector2, b: Vector2) -> bool: return _project(a).y < _project(b).y)
	var props: String = pal.get("props", "trees")
	for k in order.size():
		var p: Vector2 = order[k]
		var base := _project(p)
		if props == "flood":  # floodlight masts with a bright lamp bank
			draw_line(base, base - Vector2(0, 22 * w), _shade(pal.tree), 2.0 * w)
			draw_rect(Rect2(base - Vector2(5 * w, 26 * w), Vector2(10 * w, 5 * w)), _shade(pal.tip))
			continue
		if props == "desk":  # giant pencils and dice
			if k % 2 == 0:
				var d := Vector2(14, -4) * w
				draw_line(base - d, base + d, _shade(Color("7a5030")), 7.0 * w)
				draw_line(base - d, base + d, _shade(pal.tree), 5.0 * w)
				draw_circle(base + d, 2.6 * w, _shade(pal.tip))
			else:
				draw_rect(Rect2(base - Vector2(5, 10) * w, Vector2(10, 10) * w), _shade(Color("f6f4ec")))
				draw_rect(Rect2(base - Vector2(5, 10) * w, Vector2(10, 10) * w), _shade(Color("3a3440")), false, 1.0)
				draw_circle(base - Vector2(0, 5) * w, 1.3 * w, _shade(Color("3a3440")))
			continue
		var tip := base - Vector2(0, 16 * w)
		draw_colored_polygon(PackedVector2Array([base + Vector2(-6 * w, 0), tip, base + Vector2(6 * w, 0)]), _shade(pal.tree))
		draw_colored_polygon(PackedVector2Array([base, tip, base + Vector2(6 * w, 0)]), _shade(pal.tree).darkened(0.25))
		draw_circle(tip + Vector2(0, 2 * w), 1.6 * w, _shade(pal.tip))
	if night:  # a few lamps along the road (cool floodlights on The Raceway)
		var lamp := Color(0.9, 0.95, 1.0) if variant == 4 else Color(1.0, 0.82, 0.45)
		for i in range(0, n, maxi(1, n / (12 if variant == 4 else 7))):
			draw_circle(_project(_pts[i], _lift[i]) + Vector2(0, -3), 2.4, lamp)
			draw_circle(_project(_pts[i], _lift[i]) + Vector2(0, -3), 6.0, Color(lamp, 0.18))
