class_name TrackLayout
extends Resource
## Data for one closed circuit built from straights and circular corners:
## each control point is a corner whose radius is given in corner_radii, and the
## centreline runs straight between corners. Sampling is pure (no scene), so
## geometry and checkpoints can be unit-tested.

## Corner points of the closed centreline (where straights would meet), in driving order.
@export var control_points: PackedVector2Array
## Centreline radius of the corner at each control point (px). Large = sweeping, small = tight.
@export var corner_radii: PackedFloat32Array
## Drivable width between the barrier faces (px). PROVISIONAL (original: ~3 cars wide).
@export var road_width := 150.0
## Maximum distance between centreline samples (px).
@export var sample_spacing := 20.0
## Number of checkpoints including the start/finish line (checkpoint 0).
@export var checkpoint_count := 12
## Laps per race. PROVISIONAL: the original's lap count per track is unverified.
@export var lap_count := 3
## Starting grid: two staggered columns behind the start/finish line.
## Formation and spacing are PROVISIONAL (the original's grid layout is unverified).
## Distance of the pole position behind the line (px).
@export var grid_first_offset := 60.0
## Distance between grid rows (px).
@export var grid_row_spacing := 80.0
## Lateral distance of each column from the centreline (px).
@export var grid_column_offset := 37.0
## Extra distance the second column starts behind the first (px).
@export var grid_stagger := 40.0
## Optional (J0, experimental): elevated stretches of road (level 1, a bridge),
## each an arc-length interval Vector2(start, end) in px along the sampled
## centreline from the start/finish line, in driving direction. Where the
## centreline crosses itself one branch must be elevated. Empty (every normal
## circuit) = a flat circuit, unchanged behaviour.
@export var elevation_zones: PackedVector2Array = PackedVector2Array()

## Optional (J3, experimental): jumps, each Vector3(lip, ramp_length, gap_length)
## in px along the centreline: a ramp rises over ramp_length up to the lip at
## arc distance `lip`; the gap_length after it has no road (a pit) and must be
## flown over. Empty (every normal circuit) = no jumps.
## A jump on the ground needs its own straight away from every crossing. A
## FLYOVER jump sits on an elevated stretch (inside an elevation zone) whose
## gap spans the road crossing underneath: cars fly over the traffic below.
@export var jumps: PackedVector3Array = PackedVector3Array()
## Optional jump physics for this layout (null = res://src/race/default_jump_rules.tres).
@export var jump_rules: JumpRules = null
## Optional narrower stretches of road, each Vector3(start, end, width) in px
## along the centreline; the road tapers from road_width to `width` over
## NARROW_TAPER at either end. Empty = the same width everywhere.
@export var narrow_sections: PackedVector3Array = PackedVector3Array()
## Optional branches (2026-11-17): stretches where the road divides around a
## solid divider and rejoins, all in the driving direction. Each Dictionary:
##   kind "pit": a pit lane beside the racing road (side +1 right / -1 left of
##     the driving direction): keys from, to (px along the centreline: where
##     the road starts to widen and where it is back to normal), ramp (widening
##     length at either end), side, lane (the through-lane width), divider
##     (divider width), box (centre of the middle service bay, px), box_length
##     (one bay's length), bays (service bays side by side along the lane),
##     bay_depth (how far the bays reach beyond the through-lane), bay_gap
##     (between two bays). The bays sit on an apron that bulges out of the
##     outer edge around them (BAY_TAPER at either end).
##   kind "split": two racing lanes, keys from, to, ramp, lanes [left width,
##     right width], divider.
## Lap progress is the centreline projection, so every lane counts the same.
@export var branches: Array[Dictionary] = []
## Display name of the circuit (empty = unnamed; DevLayouts names legacy ones).
@export var display_name := ""

## Room beyond the road edge (px) that crossings, zone ends, checkpoint gates
## and the grid keep from the other road (barrier + a car length + margin).
const CROSSING_CLEARANCE := 120.0
## Gates keep at least this far (px along the road) from a zone end.
const GATE_ZONE_MARGIN := 120.0
## A jump needs this much straight road before its ramp (to line up) and after
## its gap (to land and recover), and keeps gates this far away (px).
const JUMP_RUNWAY := 200.0
## Within this distance (px along the road) of a zone end a car belongs to both
## levels (collides with cars and barriers of either), so two cars on the same
## road are never on different levels while they touch. Must stay below
## GATE_ZONE_MARGIN; zone ends are validated to be far from the other road.
const TRANSITION_BAND := 80.0
## Length over which a narrow section tapers from / to the full width (px).
const NARROW_TAPER := 120.0
## Narrowest road a layout may use (px): two cars side by side.
const MIN_NARROW_WIDTH := 96.0
## A flyover jump's gap must span the road below plus its barriers and this margin (px).
const FLYOVER_MARGIN := 20.0
## Barrier strip width assumed by validation (px; the template barrier is 20).
const BARRIER_ALLOWANCE := 20.0
## A flyover jump keeps this much elevated road after its gap to land on (px).
const FLYOVER_LANDING := 120.0


## Grid slot (0 = pole) as {distance_behind_line, lateral}; lateral > 0 = right.
func grid_slot(slot: int) -> Dictionary:
	var row := slot / 2
	var column := slot % 2
	return {
		"behind": grid_first_offset + row * grid_row_spacing + column * grid_stagger,
		"lateral": grid_column_offset * (-1.0 if column == 0 else 1.0),
	}


## Problems that make the layout unbuildable (empty when valid).
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	var n := control_points.size()
	if n < 3:
		errors.append("need at least 3 control points")
		return errors
	if corner_radii.size() != n:
		errors.append("corner_radii must have one radius per control point")
		return errors
	for i in n:
		if corner_radii[i] <= road_width * 0.5:
			errors.append("corner %d radius %.0f must exceed half the road width" % [i, corner_radii[i]])
		var j := (i + 1) % n
		var room := control_points[i].distance_to(control_points[j])
		if _tangent_length(i) + _tangent_length(j) > room:
			errors.append("corners %d and %d overlap (no room for a straight)" % [i, j])
	if errors.is_empty():
		errors.append_array(validate_elevation())
		errors.append_array(validate_jumps())
		errors.append_array(validate_narrow_sections())
		errors.append_array(validate_branches())
	return errors


# ------------------------------------------------------------- branches

## A divider ends in a point over this length (px) at either end.
const DIVIDER_NOSE := 70.0
## The bay apron widens out of the pit lane over this length (px) at either end.
const BAY_TAPER := 110.0
## Room kept between a branch's outer edge and any other stretch of road.
const BRANCH_CLEARANCE := 80.0


## Index of the branch covering arc distance s (from .. to), -1 if none.
func branch_at(s: float, lap_length: float) -> int:
	var w := fposmod(s, lap_length)
	for k in branches.size():
		var b: Dictionary = branches[k]
		if w >= float(b.from) and w <= float(b.to):
			return k
	return -1


## How far the road has opened up at s within branch b (0 .. 1).
func branch_open(b: Dictionary, s: float, lap_length: float) -> float:
	var w := fposmod(s, lap_length)
	var from: float = b.from
	var to: float = b.to
	var ramp: float = b.ramp
	if w <= from or w >= to:
		return 0.0
	return smoothstep(0.0, 1.0, clampf(minf(w - from, to - w) / ramp, 0.0, 1.0))


## Extra width a pit branch adds on [left, right] when fully open.
static func branch_extra(b: Dictionary) -> Vector2:
	var add: float = float(b.divider) + float(b.lane)
	return Vector2(add, 0.0) if int(b.side) < 0 else Vector2(0.0, add)


## Service bays of a pit branch: their count (0 = none).
static func bay_count(b: Dictionary) -> int:
	return int(b.get("bays", 0))


## Arc-distance centre of service bay k (0-based; PIT 1 = k 0, nearest the entry).
static func bay_centre(b: Dictionary, k: int) -> float:
	var n := bay_count(b)
	return float(b.box) + (k - (n - 1) * 0.5) * (float(b.box_length) + float(b.get("bay_gap", 0.0)))


## Arc span Vector2(start, end) of the bay apron (all bays, without tapers).
static func bay_span(b: Dictionary) -> Vector2:
	var n := bay_count(b)
	var half: float = float(b.box_length) * 0.5
	return Vector2(bay_centre(b, 0) - half, bay_centre(b, n - 1) + half)


## How deep the bay apron is at arc distance w within pit branch b (0 .. bay_depth).
static func bay_apron(b: Dictionary, w: float) -> float:
	if bay_count(b) == 0:
		return 0.0
	var span := bay_span(b)
	var o := clampf(minf(w - (span.x - BAY_TAPER), (span.y + BAY_TAPER) - w) / BAY_TAPER, 0.0, 1.0)
	return float(b.bay_depth) * smoothstep(0.0, 1.0, o)


## Lateral offsets Vector2(inner, outer) of the bays' strip (beyond the
## through-lane, towards the outer wall), signed like any lateral offset.
func bay_strip(b: Dictionary, lap_length: float) -> Vector2:
	var d := _divider_full(b, lap_length)
	var lane: float = b.lane
	var depth: float = b.get("bay_depth", 0.0)
	if int(b.side) > 0:
		return Vector2(d.y + lane, d.y + lane + depth)
	return Vector2(d.x - lane, d.x - lane - depth)


## Half widths [left, right] of the drivable road at s (narrow sections and
## branches included).
func side_widths_at(s: float, lap_length: float) -> Vector2:
	var h := half_width_at(s, lap_length)
	var k := branch_at(s, lap_length)
	if k < 0:
		return Vector2(h, h)
	var b: Dictionary = branches[k]
	var o := branch_open(b, s, lap_length)
	if b.kind == "pit":
		var apron := bay_apron(b, fposmod(s, lap_length))
		return Vector2(h, h) + branch_extra(b) * o + (Vector2(apron, 0.0) if int(b.side) < 0 else Vector2(0.0, apron))
	var full := (float(b.lanes[0]) + float(b.divider) + float(b.lanes[1])) * 0.5
	return Vector2.ONE * lerpf(h, maxf(h, full), o)


## The divider at s as lateral offsets Vector2(from, to) (negative = left), or
## Vector2.INF where there is none. It runs where the road is fully open and
## narrows to a point (its nose) over DIVIDER_NOSE at either end.
func divider_at(s: float, lap_length: float) -> Vector2:
	var k := branch_at(s, lap_length)
	if k < 0:
		return Vector2.INF
	var b: Dictionary = branches[k]
	var w := fposmod(s, lap_length)
	var start: float = float(b.from) + float(b.ramp)
	var end: float = float(b.to) - float(b.ramp)
	if w < start or w > end:
		return Vector2.INF
	var full := _divider_full(b, lap_length)
	var nose := clampf(minf(w - start, end - w) / DIVIDER_NOSE, 0.0, 1.0)
	var mid := (full.x + full.y) * 0.5
	var half_w := (full.y - full.x) * 0.5 * nose
	return Vector2(mid - half_w, mid + half_w)


func _divider_full(b: Dictionary, lap_length: float) -> Vector2:
	var h := half_width_at(float(b.from), lap_length)
	if b.kind == "pit":
		return Vector2(h, h + float(b.divider)) if int(b.side) > 0 else Vector2(-h - float(b.divider), -h)
	var full := (float(b.lanes[0]) + float(b.divider) + float(b.lanes[1])) * 0.5
	var d0 := -full + float(b.lanes[0])
	return Vector2(d0, d0 + float(b.divider))


## Lateral bounds Vector2(lo, hi) of one route at s: route 0 = the racing
## road (a split's left lane), route 1 = a split's right lane or the pit lane.
## Outside branches (and in the ramps, before the divider) the whole road.
func route_bounds(s: float, lap_length: float, route: int) -> Vector2:
	var sw := side_widths_at(s, lap_length)
	var lo := -sw.x
	var hi := sw.y
	var k := branch_at(s, lap_length)
	if k < 0:
		return Vector2(lo, hi)
	var b: Dictionary = branches[k]
	var d := _divider_full(b, lap_length)
	var o := branch_open(b, s, lap_length)
	if b.kind == "pit":
		var h := half_width_at(s, lap_length)
		if route == 0:  # the racing road never opens up on the pit side
			return Vector2(lo, h) if int(b.side) > 0 else Vector2(-h, hi)
		# the pit route moves over steadily along the whole entry ramp (and back
		# along the exit ramp), not in a late swerve at the divider's nose
		# (the through-lane: the bay apron beyond it is for stopping, not driving past)
		var w := fposmod(s, lap_length)
		var lin := clampf(minf(w - float(b.from), float(b.to) - w) / float(b.ramp), 0.0, 1.0)
		var through := h + float(b.divider) + float(b.lane)
		return Vector2(lerpf(-h, d.y, lin), minf(hi, through)) if int(b.side) > 0 \
			else Vector2(maxf(lo, -through), lerpf(h, d.x, lin))
	if route == 0:
		return Vector2(lo, lerpf(hi, d.x, o))
	return Vector2(lerpf(lo, d.y, o), hi)


## Is a point (arc distance s, lateral offset) inside the pit lane proper (the
## stretch beside the divider, where the limiter applies)?
func in_pit_lane(s: float, lap_length: float, lateral: float) -> bool:
	var k := branch_at(s, lap_length)
	if k < 0 or branches[k].kind != "pit":
		return false
	var d := divider_at(s, lap_length)
	if d == Vector2.INF:
		return false
	var mid := (d.x + d.y) * 0.5
	return lateral > mid if int(branches[k].side) > 0 else lateral < mid


## The service bay (0-based) a point is in, -1 if none: within the bay's
## length and with its centre at least 15 % of the way into the bay (a car
## stopped there leaves the through-lane practically clear).
func bay_at(s: float, lap_length: float, lateral: float) -> int:
	if not in_pit_lane(s, lap_length, lateral):
		return -1
	var b: Dictionary = branches[branch_at(s, lap_length)]
	var strip := bay_strip(b, lap_length)
	var into := (lateral - strip.x) * signf(float(b.side))
	if into < float(b.bay_depth) * 0.15:
		return -1
	var w := fposmod(s, lap_length)
	for k in bay_count(b):
		if absf(w - bay_centre(b, k)) <= float(b.box_length) * 0.5:
			return k
	return -1


## Is the point in any service bay?
func in_service_box(s: float, lap_length: float, lateral: float) -> bool:
	return bay_at(s, lap_length, lateral) >= 0


## Is a point off the drivable road or on a divider (missiles stop there)?
func road_blocked(s: float, lap_length: float, lateral: float) -> bool:
	var sw := side_widths_at(s, lap_length)
	if lateral < -sw.x or lateral > sw.y:
		return true
	var d := divider_at(s, lap_length)
	return d != Vector2.INF and lateral > d.x and lateral < d.y


## Index of the pit branch (-1 = this circuit has no pit lane).
func pit_branch() -> int:
	for k in branches.size():
		if branches[k].kind == "pit":
			return k
	return -1


## Problems with the branches (empty when valid): on the ground, within the
## lap and clear of the grid, away from jumps, crossings, narrow sections, each
## other and every other stretch of road.
func validate_branches() -> PackedStringArray:
	var errors := PackedStringArray()
	if branches.is_empty():
		return errors
	var c := sample_centerline()
	var path := ClosedPath.new(c)
	var tans := tangents(c)
	for k in branches.size():
		var b: Dictionary = branches[k]
		var from: float = b.get("from", -1.0)
		var to: float = b.get("to", -1.0)
		if not ["pit", "split"].has(b.get("kind", "")):
			errors.append("branch %d: kind must be pit or split" % k)
			continue
		if from < 0.0 or to > path.length - grid_extent() or to - from < 2.0 * float(b.ramp) + 2.0 * DIVIDER_NOSE + 100.0:
			errors.append("branch %d must lie within the lap, clear of the grid, longer than its ramps" % k)
		if b.kind == "pit":
			var span := bay_span(b) if bay_count(b) > 0 else Vector2(float(b.box) - float(b.box_length) * 0.5, float(b.box) + float(b.box_length) * 0.5)
			if span.x - BAY_TAPER < from + float(b.ramp) or span.y + BAY_TAPER > to - float(b.ramp) \
					or span.x < from + float(b.ramp) + DIVIDER_NOSE or span.y > to - float(b.ramp) - DIVIDER_NOSE:
				errors.append("branch %d: the service bays must lie beside the divider" % k)
		for m in range(k + 1, branches.size()):
			if from < float(branches[m].to) and float(branches[m].from) < to:
				errors.append("branches %d and %d overlap" % [k, m])
		for n in narrow_sections:
			if from < n.y + NARROW_TAPER and n.x - NARROW_TAPER < to:
				errors.append("branch %d overlaps a narrow section" % k)
		for j in jumps:
			if from < j.x + j.z + JUMP_RUNWAY and j.x - j.y - JUMP_RUNWAY < to:
				errors.append("branch %d overlaps a jump" % k)
		var s := from
		while s <= to:
			if level_at(s, path.length) != 0:
				errors.append("branch %d must be on the ground level" % k)
				break
			# the opened road keeps clear of every other stretch of road
			var sw := side_widths_at(s, path.length)
			var i := path.index_at(s)
			var right := Vector2(-tans[i].y, tans[i].x)
			for edge in [path.point_at(s) - right * sw.x, path.point_at(s) + right * sw.y]:
				for q in c.size():
					var ds := absf(wrapf(path.cumulative[q] - s, -path.length * 0.5, path.length * 0.5))
					if ds > 900.0 and edge.distance_to(c[q]) < road_width * 0.5 + BRANCH_CLEARANCE:
						errors.append("branch %d at %.0f comes too close to the road at %.0f" % [k, s, path.cumulative[q]])
						s = to + 1.0
						break
				if s > to:
					break
			s += sample_spacing * 2.0
	return errors


## Half the drivable width at arc distance s (road_width / 2 except in a
## narrow section, which tapers smoothly in and out).
func half_width_at(s: float, lap_length: float) -> float:
	var width := road_width
	if narrow_sections.is_empty():
		return width * 0.5
	var w := fposmod(s, lap_length)
	for n in narrow_sections:
		if w > n.x and w < n.y:
			var k := smoothstep(0.0, 1.0, clampf(minf(w - n.x, n.y - w) / NARROW_TAPER, 0.0, 1.0))
			width = minf(width, lerpf(road_width, n.z, k))
	return width * 0.5


## side_widths_at for every centreline sample: [left widths, right widths].
func side_widths(centerline: PackedVector2Array) -> Array[PackedFloat32Array]:
	var left := PackedFloat32Array()
	var right := PackedFloat32Array()
	var path := ClosedPath.new(centerline)
	for i in centerline.size():
		var w := side_widths_at(path.cumulative[i], path.length)
		left.append(w.x)
		right.append(w.y)
	return [left, right]


## half_width_at for every centreline sample.
func half_widths(centerline: PackedVector2Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var path := ClosedPath.new(centerline)
	for i in centerline.size():
		out.append(half_width_at(path.cumulative[i], path.length))
	return out


## Problems with the narrow sections (empty when valid): on the ground, away
## from crossings, the grid and jumps, not overlapping, wide enough for two cars.
func validate_narrow_sections() -> PackedStringArray:
	var errors := PackedStringArray()
	if narrow_sections.is_empty():
		return errors
	var c := sample_centerline()
	var path := ClosedPath.new(c)
	var crossings := find_crossings(c)
	for k in narrow_sections.size():
		var n := narrow_sections[k]
		if n.z < MIN_NARROW_WIDTH or n.z >= road_width:
			errors.append("narrow section %d: width must be %.0f..%.0f px" % [k, MIN_NARROW_WIDTH, road_width])
		if n.x < 0.0 or n.y > path.length - grid_extent() or n.y - n.x < 2.0 * NARROW_TAPER:
			errors.append("narrow section %d must lie within the lap, clear of the grid, longer than its tapers" % k)
		var s := n.x
		while s <= n.y:
			if level_at(s, path.length) != 0:
				errors.append("narrow section %d must be on the ground level" % k)
				break
			s += sample_spacing
		for x in crossings:
			var reach := crossing_reach(x.angle)
			for s_branch in [x.s_a, x.s_b]:
				if s_branch > n.x - reach and s_branch < n.y + reach:
					errors.append("narrow section %d is too close to a crossing" % k)
		for j in jumps:
			if n.x < j.x + j.z + JUMP_RUNWAY and j.x - j.y - JUMP_RUNWAY < n.y:
				errors.append("narrow section %d overlaps a jump" % k)
		for m in range(k + 1, narrow_sections.size()):
			var o := narrow_sections[m]
			if n.x < o.y and o.x < n.y:
				errors.append("narrow sections %d and %d overlap" % [k, m])
	return errors


## A flyover jump: on an elevated stretch, flying over the road below.
func is_flyover(k: int, lap_length: float) -> bool:
	return level_at(jumps[k].x, lap_length) == 1


func has_elevation() -> bool:
	return not elevation_zones.is_empty()


func has_jumps() -> bool:
	return not jumps.is_empty()


## The jump whose ramp-to-gap span contains arc distance s (index), or -1.
func jump_at(s: float, lap_length: float) -> int:
	var w := fposmod(s, lap_length)
	for k in jumps.size():
		var j := jumps[k]
		if w >= j.x - j.y and w < j.x + j.z:
			return k
	return -1


## Problems with the jumps (empty when valid): each on one straight with room
## to line up and to land, on the ground level, clear of bridge ends,
## crossings and the starting grid, not overlapping another.
func validate_jumps() -> PackedStringArray:
	var errors := PackedStringArray()
	if jumps.is_empty():
		return errors
	var c := sample_centerline()
	var path := ClosedPath.new(c)
	var tans := tangents(c)
	var crossings := find_crossings(c)
	for k in jumps.size():
		var j := jumps[k]
		if j.y <= 0.0 or j.z <= 0.0:
			errors.append("jump %d needs a ramp and a gap" % k)
			continue
		var from := j.x - j.y - JUMP_RUNWAY
		var to := j.x + j.z + JUMP_RUNWAY
		if from < 0.0 or to > path.length - grid_extent():
			errors.append("jump %d is too close to the start line / grid" % k)
		var dir := path.tangent_at(from)
		var s := from
		while s <= to:
			var i := path.index_at(s)
			if absf(tans[i].angle_to(dir)) > 0.02:
				errors.append("jump %d must be on one straight (with %.0f px either side)" % [k, JUMP_RUNWAY])
				break
			s += sample_spacing
		if is_flyover(k, path.length):
			errors.append_array(_validate_flyover(k, path, crossings))
		else:
			s = from
			while s <= to:
				if level_at(s, path.length) != 0 or in_transition(s, path.length):
					errors.append("jump %d must be on the ground, clear of bridge ends" % k)
					break
				s += sample_spacing
			for x in crossings:
				for s_branch in [x.s_a, x.s_b]:
					if s_branch > from - crossing_reach(x.angle) and s_branch < to + crossing_reach(x.angle):
						errors.append("jump %d is too close to a crossing" % k)
		for m in range(k + 1, jumps.size()):
			var o := jumps[m]
			if from < o.x + o.z + JUMP_RUNWAY and o.x - o.y - JUMP_RUNWAY < to:
				errors.append("jumps %d and %d overlap" % [k, m])
	var gates := checkpoint_sample_indices(c.size(), c)
	for g in range(1, gates.size()):
		if not _gate_allowed(path.cumulative[gates[g]], c[gates[g]], path, crossings):
			errors.append("checkpoint %d could not be placed clear of the jumps" % g)
	return errors


## A flyover jump: ramp, gap and landing on the elevated level (clear of the
## zone ends), and the gap spans exactly one crossing: the whole road below
## with its barriers (and a margin), so nothing below is under the deck.
func _validate_flyover(k: int, path: ClosedPath, crossings: Array[Dictionary]) -> PackedStringArray:
	var errors := PackedStringArray()
	var j := jumps[k]
	var s := j.x - j.y
	while s <= j.x + j.z + FLYOVER_LANDING:
		if level_at(s, path.length) != 1 or in_transition(s, path.length):
			errors.append("flyover jump %d: ramp, gap and landing must be on the elevated road, clear of its ends" % k)
			break
		s += sample_spacing
	var spanned := 0
	for x in crossings:
		var s_up: float = x.s_a if level_at(x.s_a, path.length) == 1 else x.s_b
		var foot := (road_width * 0.5 + BARRIER_ALLOWANCE + FLYOVER_MARGIN) / maxf(sin(x.angle), 0.2)
		if s_up > j.x - j.y - JUMP_RUNWAY and s_up < j.x + j.z + JUMP_RUNWAY:
			if s_up - foot >= j.x and s_up + foot <= j.x + j.z:
				spanned += 1
			else:
				errors.append("flyover jump %d: the gap must span the whole road below (%.0f px either side)" % [k, foot])
	if spanned != 1:
		errors.append("flyover jump %d must fly over exactly one crossing" % k)
	return errors


## True within TRANSITION_BAND of either end of an elevation zone.
func in_transition(s: float, lap_length: float) -> bool:
	var w := fposmod(s, lap_length)
	for z in elevation_zones:
		for s_end in [z.x, z.y]:
			if absf(wrapf(w - s_end, -lap_length * 0.5, lap_length * 0.5)) < TRANSITION_BAND:
				return true
	return false


## Road level at arc distance s (any value; wrapped onto the lap):
## 1 inside an elevation zone, otherwise 0.
func level_at(s: float, lap_length: float) -> int:
	if elevation_zones.is_empty():
		return 0
	var w := fposmod(s, lap_length)
	for z in elevation_zones:
		if w >= z.x and w < z.y:
			return 1
	return 0


## Where the centreline crosses itself: [{point, s_a, s_b, angle}] with
## s_a < s_b the arc distances of the two branches and angle (radians, 0..PI/2)
## between them. Touching neighbouring segments do not count.
static func find_crossings(c: PackedVector2Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var path := ClosedPath.new(c)
	var n := c.size()
	for i in n:
		var a0 := c[i]
		var a1 := c[(i + 1) % n]
		for j in range(i + 2, n):
			if i == 0 and j == n - 1:
				continue
			var hit = Geometry2D.segment_intersects_segment(a0, a1, c[j], c[(j + 1) % n])
			if hit == null:
				continue
			var dup := false
			for o in out:
				if o.point.distance_to(hit) < 5.0:
					dup = true
			if dup:
				continue
			var sa: float = path.cumulative[i] + a0.distance_to(hit)
			var sb: float = path.cumulative[j] + c[j].distance_to(hit)
			var ang := absf((a1 - a0).angle_to(c[(j + 1) % n] - c[j]))
			if ang > PI * 0.5:
				ang = PI - ang
			out.append({"point": hit, "s_a": sa, "s_b": sb, "angle": ang})
	return out


## Half the stretch of a branch (px) that lies over / under the other road at
## a crossing of the given angle, plus clearance.
func crossing_reach(angle: float) -> float:
	return (road_width * 0.5 + CROSSING_CLEARANCE) / maxf(sin(angle), 0.2)


## Problems with crossings and elevation zones (empty when valid). A flat
## circuit with no crossing has none.
func validate_elevation() -> PackedStringArray:
	var errors := PackedStringArray()
	var c := sample_centerline()
	var path := ClosedPath.new(c)
	var crossings := find_crossings(c)
	if crossings.is_empty() and elevation_zones.is_empty():
		return errors
	if crossings.is_empty():
		errors.append("elevation zones but no crossing")
	if TRANSITION_BAND >= GATE_ZONE_MARGIN:
		errors.append("transition band must be narrower than the gate margin")
	for k in elevation_zones.size():
		var z := elevation_zones[k]
		if z.x < 0.0 or z.y > path.length or z.x >= z.y:
			errors.append("zone %d must lie within the lap (0..%.0f) with start < end" % [k, path.length])
		for m in range(k + 1, elevation_zones.size()):
			var o := elevation_zones[m]
			if z.x < o.y and o.x < z.y:
				errors.append("zones %d and %d overlap" % [k, m])
	var away := road_width * 0.5 + CROSSING_CLEARANCE
	for x in crossings:
		var reach := crossing_reach(x.angle)
		var up_a := level_at(x.s_a, path.length) == 1
		var up_b := level_at(x.s_b, path.length) == 1
		if up_a == up_b:
			errors.append("crossing at %s needs exactly one elevated branch" % x.point)
			continue
		var s_up: float = x.s_a if up_a else x.s_b
		if level_at(s_up - reach, path.length) != 1 or level_at(s_up + reach, path.length) != 1:
			errors.append("zone must cover %.0f px either side of the crossing at %s" % [reach, x.point])
		for s_branch in [x.s_a, x.s_b]:
			if minf(s_branch, path.length - s_branch) < away + grid_extent():
				errors.append("crossing at %s is too close to the start line / grid" % x.point)
	# Zone ends (where cars change level) must be clear of the other road.
	for z in elevation_zones:
		for s_end in [z.x, z.y]:
			var p := path.point_at(s_end)
			for i in c.size():
				var gap := absf(wrapf(path.cumulative[i] - s_end, -path.length * 0.5, path.length * 0.5))
				if gap > road_width * 3.0 and c[i].distance_to(p) < away + road_width * 0.5:
					errors.append("zone end at %.0f px is too close to another part of the road" % s_end)
					break
	# The grid and the start line stay on level 0.
	for s_grid in [0.0, path.length - grid_extent()]:
		if level_at(s_grid, path.length) != 0:
			errors.append("start line and grid must be on the ground level")
	for z in elevation_zones:
		if z.y > path.length - grid_extent():
			errors.append("a zone reaches into the starting grid")
	# Checkpoint gates: off the bridge, clear of crossings and zone ends.
	var gates := checkpoint_sample_indices(c.size(), c)
	for g in gates.size():
		var sg := path.cumulative[gates[g]]
		if not _gate_allowed(sg, c[gates[g]], path, crossings):
			errors.append("checkpoint %d could not be placed clear of the crossing" % g)
	return errors


## How far behind the start line the starting grid reaches (px).
func grid_extent() -> float:
	return grid_first_offset + 4 * grid_row_spacing + grid_stagger + 40.0


func _gate_allowed(s: float, at: Vector2, path: ClosedPath, crossings: Array[Dictionary]) -> bool:
	if level_at(s, path.length) != 0:
		return false
	for j in jumps:  # never on a jump, nor where cars line up for it or land
		if s > j.x - j.y - JUMP_RUNWAY and s < j.x + j.z + JUMP_RUNWAY:
			return false
	for z in elevation_zones:
		for s_end in [z.x, z.y]:
			if absf(wrapf(s - s_end, -path.length * 0.5, path.length * 0.5)) < GATE_ZONE_MARGIN:
				return false
	for x in crossings:
		if at.distance_to(x.point) < road_width + CROSSING_CLEARANCE:
			return false
	return true


## Closed centreline sampled at most sample_spacing apart. Index 0 is the
## start/finish line: the middle of the straight leading into control point 0.
func sample_centerline() -> PackedVector2Array:
	var n := control_points.size()
	var pts := PackedVector2Array()
	var last := n - 1
	var start := (_corner_exit(last) + _corner_entry(0)) * 0.5
	_sample_straight(pts, start, _corner_entry(0))
	for i in n:
		_sample_arc(pts, i)
		var next_entry := _corner_entry((i + 1) % n) if i < last else start
		_sample_straight(pts, _corner_exit(i), next_entry)
	return pts


func _direction_in(i: int) -> Vector2:
	var n := control_points.size()
	return (control_points[i] - control_points[(i - 1 + n) % n]).normalized()


func _direction_out(i: int) -> Vector2:
	return (control_points[(i + 1) % control_points.size()] - control_points[i]).normalized()


func _turn_angle(i: int) -> float:
	return _direction_in(i).angle_to(_direction_out(i))


func _tangent_length(i: int) -> float:
	return corner_radii[i] * tan(absf(_turn_angle(i)) * 0.5)


func _corner_entry(i: int) -> Vector2:
	return control_points[i] - _direction_in(i) * _tangent_length(i)


func _corner_exit(i: int) -> Vector2:
	return control_points[i] + _direction_out(i) * _tangent_length(i)


func _sample_straight(pts: PackedVector2Array, from: Vector2, to: Vector2) -> void:
	var steps := maxi(1, ceili(from.distance_to(to) / sample_spacing))
	for s in steps:
		pts.append(from.lerp(to, float(s) / steps))


func _sample_arc(pts: PackedVector2Array, i: int) -> void:
	var turn := _turn_angle(i)
	if is_zero_approx(turn):
		return
	var r := corner_radii[i]
	var inward := _direction_in(i).rotated(signf(turn) * PI * 0.5)
	var centre := _corner_entry(i) + inward * r
	var a0 := (_corner_entry(i) - centre).angle()
	var steps := maxi(1, ceili(absf(turn) * r / sample_spacing))
	for s in steps:
		pts.append(centre + Vector2.from_angle(a0 + turn * float(s) / steps) * r)


## Unit tangent (driving direction) at each centreline sample.
static func tangents(centerline: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := centerline.size()
	for i in n:
		out.append((centerline[(i + 1) % n] - centerline[(i - 1 + n) % n]).normalized())
	return out


## Centreline offset sideways by distance (positive = right of driving direction).
static func offset_line(centerline: PackedVector2Array, distance: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var tans := tangents(centerline)
	for i in centerline.size():
		var right := Vector2(-tans[i].y, tans[i].x)
		out.append(centerline[i] + right * distance)
	return out


## Centreline offset sideways per sample: distances[i] * side (side +1 = right).
static func offset_line_by(centerline: PackedVector2Array, distances: PackedFloat32Array, side: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var tans := tangents(centerline)
	for i in centerline.size():
		var right := Vector2(-tans[i].y, tans[i].x)
		out.append(centerline[i] + right * distances[i] * side)
	return out


## Sample indices of the checkpoints, evenly spaced, index 0 = start/finish.
## With elevation zones or jumps (and the centreline given), a gate that would
## sit on the bridge, at a crossing, by a zone end or on a jump moves forward
## to the first clear sample (or back, when there is no room before the next).
func checkpoint_sample_indices(sample_count: int, centerline: PackedVector2Array = PackedVector2Array()) -> PackedInt32Array:
	var out := PackedInt32Array()
	for c in checkpoint_count:
		out.append(int(round(float(c) * sample_count / checkpoint_count)) % sample_count)
	if (elevation_zones.is_empty() and jumps.is_empty()) or centerline.size() != sample_count:
		return out
	var path := ClosedPath.new(centerline)
	var crossings := find_crossings(centerline)
	for g in range(1, out.size()):
		var target := out[g]
		var limit := out[g + 1] if g + 1 < out.size() else sample_count
		var i := target
		while i < limit - 1 and not _gate_allowed(path.cumulative[i], centerline[i], path, crossings):
			i += 1
		if not _gate_allowed(path.cumulative[i], centerline[i], path, crossings):
			# no room ahead before the next gate: move back instead (still after the previous one)
			i = target
			while i > out[g - 1] + 1 and not _gate_allowed(path.cumulative[i], centerline[i], path, crossings):
				i -= 1
		out[g] = i
	return out
