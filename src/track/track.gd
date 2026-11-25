class_name Track
extends Node2D
## Builds one circuit from a TrackLayout: ground, road surface, barrier walls
## (visual + collision), start/finish line and invisible checkpoint gates.

signal checkpoint_reached(index: int, body: Node2D)

const WALL_LAYER := 1
const CAR_LAYER := 2
## J1 (elevated layouts only): barriers of the elevated road and cars on it
## use their own collision layers, so the two levels never touch.
const WALL_UPPER_LAYER := 4
const CAR_UPPER_LAYER := 8
## J3: cars in the air (over a jump) meet barriers and other flying cars only.
const CAR_AIR_LAYER := 16
## J2 draw order on elevated layouts: everything on the bridge level draws
## UPPER_Z_OFFSET above its ground-level counterpart (cars 0 -> 6, mines 1 -> 7,
## missiles 3 -> 9); the bridge's shadow and deck sit in between.
const UPPER_Z_OFFSET := 6
const BRIDGE_SHADOW_Z := 4
const BRIDGE_DECK_Z := 5
## Shadow of the deck at full height (px, light from the top left), and the
## share of each zone at either end over which the bridge rises / falls.
const BRIDGE_SHADOW_OFFSET := Vector2(18, 26)
const BRIDGE_RAMP_SHARE := 0.3
const BRIDGE_SHADOW_COLOR := Color(0.05, 0.04, 0.08, 0.36)
const CHECKPOINT_DEPTH := 30.0
const GROUND_MARGIN := 900.0

@export var layout: TrackLayout
## Visual theme variant (ground, road, barrier). Geometry and collision are
## the same for every variant. Null = Variant 1.
var theme: TrackTheme
## J3: build the layout's jumps (ramp and gap). Off in network races until J5,
## where the layout is driven as a plain road.
var jumps_enabled := true

var centerline := PackedVector2Array()
var checkpoint_samples := PackedInt32Array()
## Half the drivable width at each centreline sample (narrow sections).
var half_widths := PackedFloat32Array()
## Branches (pit lanes, split sections): the road's half width on either side
## per sample (equal to half_widths without branches).
var left_widths := PackedFloat32Array()
var right_widths := PackedFloat32Array()
## Centreline as a measurable path (race progress, AI navigation).
var path: ClosedPath


var _resolver: AssetResolver


func build(resolver: AssetResolver, p_theme: TrackTheme = null) -> void:
	_resolver = resolver
	theme = p_theme if p_theme != null else TrackTheme.load_variant(1)
	for child in get_children():
		child.free()
	centerline = layout.sample_centerline()
	path = ClosedPath.new(centerline)
	checkpoint_samples = layout.checkpoint_sample_indices(centerline.size(), centerline)
	var half := layout.road_width * 0.5
	half_widths = layout.half_widths(centerline)
	var sides := layout.side_widths(centerline)
	left_widths = sides[0]
	right_widths = sides[1]
	var left_edge := TrackLayout.offset_line(centerline, -half)
	var right_edge := TrackLayout.offset_line(centerline, half)
	if not layout.narrow_sections.is_empty() or not layout.branches.is_empty():
		left_edge = TrackLayout.offset_line_by(centerline, left_widths, -1.0)
		right_edge = TrackLayout.offset_line_by(centerline, right_widths, 1.0)
	_build_ground(resolver.get_texture(theme.asset(AssetCatalog.GRASS)))
	_build_road(resolver.get_texture(theme.asset(AssetCatalog.TARMAC)), left_edge, right_edge)
	for node_name in ["Ground", "Road", "BridgeDeck"]:  # biome tints (white = unchanged)
		var poly := get_node_or_null(node_name) as Polygon2D
		if poly != null:
			poly.color = theme.ground_tint if node_name == "Ground" else theme.road_tint
	_build_start_line(resolver.get_texture(theme.asset(AssetCatalog.START_LINE)))
	_build_walls(resolver.get_texture(theme.asset(AssetCatalog.WALL)), half, left_edge, right_edge)
	if layout.has_elevation():
		_build_bridge_shadow(half + AssetCatalog.SPECS[theme.asset(AssetCatalog.WALL)].display_size.y)
	if jumps_enabled and layout.has_jumps():
		_build_jumps(half)
	if not layout.branches.is_empty():
		_build_branches(resolver.get_texture(theme.asset(AssetCatalog.WALL)))
	_build_checkpoints()


func checkpoint_count() -> int:
	return checkpoint_samples.size()


## Centre point and driving direction of checkpoint gate i.
func checkpoint_transform(index: int) -> Transform2D:
	var s := checkpoint_samples[index]
	var tan := TrackLayout.tangents(centerline)[s]
	return Transform2D(tan.angle(), centerline[s])


## Starting grid slot (0 = pole) behind the start/finish line, facing along the track.
func grid_transform(slot: int) -> Transform2D:
	var g := layout.grid_slot(slot)
	var s: float = path.length - g.behind
	var tan := path.tangent_at(s)
	var right := Vector2(-tan.y, tan.x)
	return Transform2D(tan.angle(), path.point_at(s) + right * g.lateral)


func _build_ground(texture: Texture2D) -> void:
	var bounds := Rect2(centerline[0], Vector2.ZERO)
	for p in centerline:
		bounds = bounds.expand(p)
	bounds = bounds.grow(GROUND_MARGIN)
	var corners := PackedVector2Array([bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end,
		Vector2(bounds.position.x, bounds.end.y)])
	var poly := _textured_polygon("Ground", texture, corners, AssetCatalog.SPECS[theme.asset(AssetCatalog.GRASS)].tile_world_size)
	add_child(poly)


func _build_road(texture: Texture2D, left_edge: PackedVector2Array, right_edge: PackedVector2Array) -> void:
	var n := left_edge.size()
	var verts := PackedVector2Array(left_edge)
	verts.append_array(right_edge)
	var poly := _textured_polygon("Road", texture, verts, AssetCatalog.SPECS[theme.asset(AssetCatalog.TARMAC)].tile_world_size)
	var quads: Array = []
	var deck_quads: Array = []
	for i in n:
		var j := (i + 1) % n
		var quad := PackedInt32Array([i, j, n + j, n + i])
		if layout.has_elevation() and level_of_sample(i) == 1:
			if not in_flyover_gap(i):  # a flyover jump's gap has no deck
				deck_quads.append(quad)
		else:
			quads.append(quad)
	poly.polygons = quads
	_build_flyover_ravines()  # under the road crossing below
	add_child(poly)
	if not deck_quads.is_empty():
		# J2: the elevated road is its own surface above the ground level
		var deck := _textured_polygon("BridgeDeck", texture, verts, AssetCatalog.SPECS[theme.asset(AssetCatalog.TARMAC)].tile_world_size)
		deck.polygons = deck_quads
		deck.z_index = BRIDGE_DECK_Z
		add_child(deck)


func _textured_polygon(node_name: String, texture: Texture2D, verts: PackedVector2Array, tile_world: float) -> Polygon2D:
	var poly := Polygon2D.new()
	poly.name = node_name
	poly.polygon = verts
	poly.texture = texture
	poly.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var uv_scale := AssetCatalog.uv_per_world_pixel(texture, tile_world)
	var uvs := PackedVector2Array()
	for v in verts:
		uvs.append(v * uv_scale)
	poly.uv = uvs
	return poly


func _build_walls(texture: Texture2D, half: float, left_edge: PackedVector2Array, right_edge: PackedVector2Array) -> void:
	var wall_spec: Dictionary = AssetCatalog.SPECS[theme.asset(AssetCatalog.WALL)]
	var wall_width: float = wall_spec.display_size.y
	if layout.has_elevation():
		_build_level_walls(left_edge, right_edge)
	else:
		var body := StaticBody2D.new()
		body.name = "Walls"
		body.collision_layer = WALL_LAYER
		body.collision_mask = 0
		add_child(body)
		for edge in [left_edge, right_edge]:
			var segments := PackedVector2Array()
			for i in edge.size():
				segments.append(edge[i])
				segments.append(edge[(i + 1) % edge.size()])
			var shape := ConcavePolygonShape2D.new()
			shape.segments = segments
			var cs := CollisionShape2D.new()
			cs.shape = shape
			body.add_child(cs)
	# Visual barriers sit just outside the collision faces so the car meets their inner edge.
	for side in [-1.0, 1.0]:
		var points := TrackLayout.offset_line(centerline, side * (half + wall_width * 0.5))
		if not layout.narrow_sections.is_empty() or not layout.branches.is_empty():
			var out := PackedFloat32Array()
			for h in (left_widths if side < 0 else right_widths):
				out.append(h + wall_width * 0.5)
			points = TrackLayout.offset_line_by(centerline, out, side)
		var line_name := "Barrier%s" % ("Left" if side < 0 else "Right")
		if not layout.has_elevation():
			add_child(_barrier_line(line_name, points, true, wall_width, texture))
			continue
		# J2: one open line per run of road on one level; bridge railings above the deck
		for run in _deck_runs():
			var pts := PackedVector2Array()
			for k in range(run.from, run.to + 1):  # one shared point joins the runs
				pts.append(points[k % points.size()])
			var line := _barrier_line("%s%s%d" % [line_name, "Upper" if run.level == 1 else "", run.from], pts, false, wall_width, texture)
			if run.level == 1:
				line.z_index = BRIDGE_DECK_Z
			add_child(line)


## Elevated layouts: each barrier segment belongs to the level of its stretch
## of road ("Walls" ground, "WallsUpper" bridge), so a car only meets the
## barriers of its own level where the roads cross.
func _build_level_walls(left_edge: PackedVector2Array, right_edge: PackedVector2Array) -> void:
	var segments := [PackedVector2Array(), PackedVector2Array()]
	for edge in [left_edge, right_edge]:
		for i in edge.size():
			var level := level_of_sample(i)
			segments[level].append(edge[i])
			segments[level].append(edge[(i + 1) % edge.size()])
	for level in 2:
		var body := StaticBody2D.new()
		body.name = "Walls" if level == 0 else "WallsUpper"
		body.collision_layer = WALL_LAYER if level == 0 else WALL_UPPER_LAYER
		body.collision_mask = 0
		add_child(body)
		var shape := ConcavePolygonShape2D.new()
		shape.segments = segments[level]
		var cs := CollisionShape2D.new()
		cs.shape = shape
		body.add_child(cs)


## Road level of centreline sample i (0 ground, 1 elevated).
func level_of_sample(i: int) -> int:
	return layout.level_at(path.cumulative[i], path.length)


## Road level at a car's progress (arc distance along its branch).
func level_at_distance(s: float) -> int:
	return layout.level_at(s, path.length)


## Road level at a car's progress is changing (near a zone end, both levels).
func in_transition(s: float) -> bool:
	return layout.in_transition(s, path.length)


## Collision layer / mask of a present car on a road level; in a transition
## band (near a bridge end) it belongs to both levels; in the air (J3) it meets
## only the barriers and other flying cars.
static func car_collision(level: int, transition: bool = false, airborne: bool = false) -> Vector2i:
	if airborne:  # over a flyover jump: the barriers of its own (elevated) road
		return Vector2i(CAR_AIR_LAYER, (WALL_LAYER if level == 0 else WALL_UPPER_LAYER) | CAR_AIR_LAYER)
	if transition:
		return Vector2i(CAR_LAYER | CAR_UPPER_LAYER, WALL_LAYER | WALL_UPPER_LAYER | CAR_LAYER | CAR_UPPER_LAYER)
	if level == 0:
		return Vector2i(CAR_LAYER, WALL_LAYER | CAR_LAYER)
	return Vector2i(CAR_UPPER_LAYER, WALL_UPPER_LAYER | CAR_UPPER_LAYER)


func _barrier_line(line_name: String, points: PackedVector2Array, closed: bool, width: float, texture: Texture2D) -> Line2D:
	var line := Line2D.new()
	line.name = line_name
	line.points = points
	line.closed = closed
	line.width = width
	line.texture = texture
	line.texture_mode = Line2D.LINE_TEXTURE_TILE
	line.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	return line


## Consecutive centreline sample runs on one level: [{level, from, to}] with
## unwrapped sample indices (use index % size); `to` is the first sample of the
## next run, so neighbouring runs share one point and join seamlessly.
func _level_runs() -> Array:
	var n := centerline.size()
	var start := -1
	for i in n:
		if level_of_sample(i) != level_of_sample((i - 1 + n) % n):
			start = i
			break
	if start < 0:
		return [{"level": level_of_sample(0), "from": 0, "to": n}]
	var runs: Array = []
	var from := start
	for k in range(1, n + 1):
		var i := start + k
		if k == n or level_of_sample(i % n) != level_of_sample(from % n):
			runs.append({"level": level_of_sample(from % n), "from": from, "to": i})
			from = i
	return runs


## _level_runs with the elevated runs broken where a flyover jump's gap has no
## deck (no railings or shadow over the gap). Without flyovers: _level_runs.
func _deck_runs() -> Array:
	var runs := _level_runs()
	if not _has_flyover():
		return runs
	var out: Array = []
	var n := centerline.size()
	for run in runs:
		if run.level != 1:
			out.append(run)
			continue
		var from: int = run.from
		var k: int = run.from
		while k < run.to:
			if in_flyover_gap(k % n):
				if k > from:
					out.append({"level": 1, "from": from, "to": k})
				while k < run.to and in_flyover_gap(k % n):
					k += 1
				from = k
			else:
				k += 1
		if run.to > from:
			out.append({"level": 1, "from": from, "to": run.to})
	return out


func _has_flyover() -> bool:
	if not jumps_enabled or not layout.has_jumps() or not layout.has_elevation():
		return false
	for k in layout.jumps.size():
		if layout.is_flyover(k, path.length):
			return true
	return false


## Centreline sample i lies in the gap of a flyover jump (built only with jumps on).
func in_flyover_gap(i: int) -> bool:
	if not jumps_enabled or not layout.has_jumps():
		return false
	var s := path.cumulative[i]
	for k in layout.jumps.size():
		var j := layout.jumps[k]
		if s > j.x and s < j.x + j.z and layout.is_flyover(k, path.length):
			return true
	return false


## The ravine of each flyover jump: earth across the gap, drawn under the road
## that crosses it (procedural, no artwork).
func _build_flyover_ravines() -> void:
	if not _has_flyover():
		return
	var half: float = layout.road_width * 0.5 + AssetCatalog.SPECS[theme.asset(AssetCatalog.WALL)].display_size.y + 16.0
	for k in layout.jumps.size():
		if not layout.is_flyover(k, path.length):
			continue
		var j := layout.jumps[k]
		var pit := _strip(j.x, j.x + j.z, half, GAP_COLOR)
		pit.name = "Ravine%d" % k
		add_child(pit)
		var depth := _strip(j.x + 18.0, j.x + j.z - 18.0, half - 14.0, GAP_DEPTH)
		depth.name = "RavineDepth%d" % k
		add_child(depth)


## How high the road is at arc distance s (0 ground .. 1 full bridge height):
## the bridge rises over the first and falls over the last part of its zone.
func bridge_height(s: float) -> float:
	var w := fposmod(s, path.length)
	for z in layout.elevation_zones:
		if w >= z.x and w < z.y:
			var ramp := (z.y - z.x) * BRIDGE_RAMP_SHARE
			return smoothstep(0.0, 1.0, minf(w - z.x, z.y - w) / ramp)
	return 0.0


## Soft shadow of the deck and its railings on the ground below, offset by the
## bridge's height (none where it meets the ground). Procedural, no artwork.
func _build_bridge_shadow(half_outer: float) -> void:
	var tans := TrackLayout.tangents(centerline)
	for run in _deck_runs():
		if run.level != 1:
			continue
		var left := PackedVector2Array()
		var right := PackedVector2Array()
		for k in range(run.from, run.to + 1):
			var i := k % centerline.size()
			var lift := BRIDGE_SHADOW_OFFSET * bridge_height(path.cumulative[i])
			var r := Vector2(-tans[i].y, tans[i].x)
			left.append(centerline[i] - r * half_outer + lift)
			right.append(centerline[i] + r * half_outer + lift)
		right.reverse()
		var shadow := Polygon2D.new()
		shadow.name = "BridgeShadow%d" % run.from
		shadow.polygon = left + right
		shadow.color = BRIDGE_SHADOW_COLOR
		shadow.z_index = BRIDGE_SHADOW_Z
		add_child(shadow)


## J3 jump visuals (procedural, no artwork): warning chevrons on the approach,
## a lighter ramp rising to a bright lip, the dark gap with its far edge, and a
## striped landing zone. Gameplay comes from JumpWorld, not from these shapes.
const RAMP_COLOR := Color(0.93, 0.78, 0.42, 0.55)
const RAMP_EDGE := Color(1.0, 0.93, 0.62, 0.95)
const JUMP_CHEVRON := Color(1.0, 0.86, 0.3, 0.8)
const GAP_COLOR := Color(0.33, 0.24, 0.17, 1.0)
const GAP_DEPTH := Color(0.19, 0.13, 0.1, 1.0)
const GAP_RIM := Color(0.36, 0.27, 0.22, 1.0)
const LANDING_COLOR := Color(1.0, 1.0, 1.0, 0.28)


func _build_jumps(half: float) -> void:
	for k in layout.jumps.size():
		var j := layout.jumps[k]
		var lip := j.x
		var ramp_from := lip - j.y
		var gap_end := lip + j.z
		var node := Node2D.new()
		node.name = "Jump%d" % k
		add_child(node)
		var flyover := layout.is_flyover(k, path.length)
		if flyover:
			node.z_index = BRIDGE_DECK_Z  # painted on the elevated deck (the ravine is under the road below)
		for c in 3:  # approach chevrons (a flyover: only where the deck is)
			var at := ramp_from - 70.0 - c * 55.0
			if not flyover or (layout.level_at(at - 40.0, path.length) == 1 and not layout.in_transition(at - 40.0, path.length)):
				node.add_child(_chevron(at, half * 0.55, JUMP_CHEVRON))
		var ramp := _strip(ramp_from, lip, half - 4.0, RAMP_COLOR)
		ramp.name = "Ramp"
		node.add_child(ramp)
		for c in 2:
			node.add_child(_chevron(ramp_from + j.y * (0.3 + 0.35 * c), half * 0.45, RAMP_EDGE))
		if flyover:
			node.add_child(_strip(lip - 7.0, lip, half - 2.0, RAMP_EDGE))  # the lip
			node.add_child(_strip(gap_end, gap_end + 9.0, half + 2.0, GAP_RIM))  # far edge of the gap
			for stripe in 4:  # landing zone
				var a := gap_end + 30.0 + stripe * 34.0
				node.add_child(_strip(a, a + 14.0, half - 10.0, LANDING_COLOR))
			continue
		var pit := _strip(lip, gap_end, half + 14.0, GAP_COLOR)
		pit.name = "Gap"
		node.add_child(pit)
		node.add_child(_strip(lip + 22.0, gap_end - 14.0, half - 18.0, GAP_DEPTH))
		node.add_child(_strip(lip - 7.0, lip, half - 2.0, RAMP_EDGE))  # the lip
		node.add_child(_strip(gap_end, gap_end + 9.0, half + 14.0, GAP_RIM))  # far edge
		for stripe in 4:  # landing zone
			var a := gap_end + 30.0 + stripe * 34.0
			node.add_child(_strip(a, a + 14.0, half - 10.0, LANDING_COLOR))


## A polygon across the road between arc distances s0 and s1.
func _strip(s0: float, s1: float, half_width: float, color: Color) -> Polygon2D:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var steps := maxi(1, int(ceil((s1 - s0) / 8.0)))
	for i in steps + 1:
		var s := lerpf(s0, s1, float(i) / steps)
		var t := path.tangent_at(s)
		var r := Vector2(-t.y, t.x)
		left.append(path.point_at(s) - r * half_width)
		right.append(path.point_at(s) + r * half_width)
	right.reverse()
	var poly := Polygon2D.new()
	poly.polygon = left + right
	poly.color = color
	return poly


## A forward-pointing chevron painted on the road at arc distance s.
func _chevron(s: float, half_width: float, color: Color) -> Line2D:
	var t := path.tangent_at(s)
	var r := Vector2(-t.y, t.x)
	var tip := path.point_at(s) + t * 18.0
	var line := Line2D.new()
	line.points = PackedVector2Array([tip - t * 30.0 - r * half_width, tip, tip - t * 30.0 + r * half_width])
	line.width = 9.0
	line.default_color = color
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	return line


func _build_start_line(texture: Texture2D) -> void:
	var t := checkpoint_transform(0)
	var sprite := Sprite2D.new()
	sprite.name = "StartLine"
	sprite.texture = texture
	sprite.position = t.origin
	sprite.rotation = t.get_rotation()
	var display := Vector2(AssetCatalog.SPECS[theme.asset(AssetCatalog.START_LINE)].display_size.x, layout.road_width)
	sprite.scale = AssetCatalog.scale_for(texture, display)
	add_child(sprite)


func _build_checkpoints() -> void:
	for c in checkpoint_samples.size():
		var t := checkpoint_transform(c)
		var area := Area2D.new()
		area.name = "Checkpoint%d" % c
		area.collision_layer = 0
		area.collision_mask = CAR_LAYER
		area.monitorable = false
		# the gate spans the whole road here, every lane of a branch included
		var i := checkpoint_samples[c]
		var lw: float = left_widths[i] if not left_widths.is_empty() else layout.road_width * 0.5
		var rw: float = right_widths[i] if not right_widths.is_empty() else layout.road_width * 0.5
		var right := Vector2(-sin(t.get_rotation()), cos(t.get_rotation()))
		area.position = t.origin + right * (rw - lw) * 0.5
		area.rotation = t.get_rotation()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(CHECKPOINT_DEPTH, maxf(layout.road_width, lw + rw) + 40.0)
		var cs := CollisionShape2D.new()
		cs.shape = shape
		area.add_child(cs)
		area.body_entered.connect(func(body: Node2D) -> void: checkpoint_reached.emit(c, body))
		add_child(area)


# ------------------------------------------------------------- branches

const DIVIDER_FILL := Color(0.42, 0.4, 0.37)
const PIT_MARK := Color(1.0, 0.86, 0.3, 0.9)
const PIT_LINE := Color(1.0, 1.0, 1.0, 0.75)


## Dividers (solid islands, collision on the ground level) and the pit lane's
## markings: entry / exit lines, the PIT lettering and the service box.
func _build_branches(wall_tex: Texture2D) -> void:
	var node := Node2D.new()
	node.name = "Branches"
	node.z_index = 0
	add_child(node)
	var body := StaticBody2D.new()
	body.name = "Dividers"
	body.collision_layer = WALL_LAYER
	body.collision_mask = 0
	add_child(body)
	var wall_width: float = AssetCatalog.SPECS[theme.asset(AssetCatalog.WALL)].display_size.y
	for k in layout.branches.size():
		var b: Dictionary = layout.branches[k]
		var outline := divider_outline(k)
		if outline.size() < 3:
			continue
		var segs := PackedVector2Array()
		for i in outline.size():
			segs.append(outline[i])
			segs.append(outline[(i + 1) % outline.size()])
		var shape := ConcavePolygonShape2D.new()
		shape.segments = segs
		var cs := CollisionShape2D.new()
		cs.shape = shape
		body.add_child(cs)
		var fill := Polygon2D.new()
		fill.name = "Divider%d" % k
		fill.polygon = outline
		fill.color = DIVIDER_FILL * theme.road_tint
		node.add_child(fill)
		var edge := _barrier_line("DividerWall%d" % k, outline, true, wall_width * 0.6, wall_tex)
		node.add_child(edge)
		if b.kind == "pit":
			_build_pit_marks(node, b)


## Closed outline of branch k's divider (world points), empty if none.
func divider_outline(k: int) -> PackedVector2Array:
	var b: Dictionary = layout.branches[k]
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var s: float = float(b.from) + float(b.ramp)
	var end: float = float(b.to) - float(b.ramp)
	while s <= end + 0.01:
		var d := layout.divider_at(s, path.length)
		if d != Vector2.INF:
			var t := path.tangent_at(s)
			var r := Vector2(-t.y, t.x)
			left.append(path.point_at(s) + r * d.x)
			right.append(path.point_at(s) + r * d.y)
		s += 10.0
	var out := PackedVector2Array(left)
	right.reverse()
	out.append_array(right)
	return out


## The pit's service bay frames (PIT 1, 2, 3), for occupancy colours.
var bay_frames: Array[Line2D] = []


func _build_pit_marks(node: Node2D, b: Dictionary) -> void:
	var side := float(b.side)
	# the PIT sign beside the entrance, behind the barrier on the pit side
	var sign_tex: Texture2D = _resolver.get_texture(theme.asset(AssetCatalog.PIT_SIGN)) if _resolver != null else null
	if sign_tex != null:
		var at: float = float(b.from) - 60.0
		var st := path.tangent_at(at)
		var sr := Vector2(-st.y, st.x) * side
		var sign := Sprite2D.new()
		sign.name = "PitSign"
		sign.texture = sign_tex
		sign.scale = AssetCatalog.scale_for(sign_tex, AssetCatalog.SPECS[theme.asset(AssetCatalog.PIT_SIGN)].display_size)
		var wall_w: float = AssetCatalog.SPECS[theme.asset(AssetCatalog.WALL)].display_size.y
		sign.position = path.point_at(at) + sr * (layout.side_widths_at(at, path.length).y if side > 0 else layout.side_widths_at(at, path.length).x) + sr * (wall_w + 34.0)
		sign.rotation = st.angle()
		sign.z_index = 2
		node.add_child(sign)
	var lane_w: float = float(b.lane)
	var lane_mid := func(s: float) -> float:  # the middle of the through-lane
		var d := layout.divider_at(s, path.length)
		return (d.y + lane_w * 0.5) if side > 0 else (d.x - lane_w * 0.5)
	# the service bays: numbered frames on the apron beside the through-lane
	var half_len: float = float(b.box_length) * 0.5
	var strip := layout.bay_strip(b, path.length)
	bay_frames.clear()
	for k in TrackLayout.bay_count(b):
		var c := TrackLayout.bay_centre(b, k)
		var frame := Line2D.new()
		frame.name = "ServiceBay%d" % (k + 1)
		frame.width = 5.0
		frame.default_color = PIT_MARK
		frame.closed = true
		var pts := PackedVector2Array()
		for corner in [[-1, 0], [1, 0], [1, 1], [-1, 1]]:
			var s: float = c + corner[0] * (half_len - 3.0)
			var t := path.tangent_at(s)
			var r := Vector2(-t.y, t.x)
			pts.append(path.point_at(s) + r * lerpf(strip.x + 2.0 * side, strip.y - 6.0 * side, corner[1]))
		frame.points = pts
		node.add_child(frame)
		bay_frames.append(frame)
		var num := Label.new()
		num.name = "BayNumber%d" % (k + 1)
		num.text = "PIT %d" % (k + 1)
		num.add_theme_font_size_override("font_size", 22)
		num.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
		num.size = Vector2(80, 28)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.pivot_offset = num.size * 0.5
		var ct := path.tangent_at(c)
		num.position = path.point_at(c) + Vector2(-ct.y, ct.x) * (strip.y - 18.0 * side) - num.pivot_offset
		num.rotation = ct.angle()
		node.add_child(num)
	# PIT lettering on the lane just after the divider's nose, and the limiter lines
	var start: float = float(b.from) + float(b.ramp) + TrackLayout.DIVIDER_NOSE + 40.0
	var end: float = float(b.to) - float(b.ramp) - TrackLayout.DIVIDER_NOSE
	for at in [start - 30.0, end]:
		var t := path.tangent_at(at)
		var r := Vector2(-t.y, t.x)
		var m: float = lane_mid.call(at)
		var line := Line2D.new()
		line.width = 6.0
		line.default_color = PIT_LINE
		line.points = PackedVector2Array([path.point_at(at) + r * (m - lane_w * 0.5 + 4.0), path.point_at(at) + r * (m + lane_w * 0.5 - 4.0)])
		node.add_child(line)
	var label := Label.new()
	label.name = "PitLettering"
	label.text = "PIT"
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	var lt := path.tangent_at(start + 40.0)
	label.position = path.point_at(start + 40.0) + Vector2(-lt.y, lt.x) * lane_mid.call(start + 40.0)
	label.rotation = lt.angle() + PI * 0.5 * -side
	label.pivot_offset = Vector2(24, 20)
	label.position -= label.pivot_offset
	node.add_child(label)
