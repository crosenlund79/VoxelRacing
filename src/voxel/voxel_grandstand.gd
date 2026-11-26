extends RefCounted
## VoxelRacing (P005): the grandstand, built procedurally instead of from the
## red / white top-down drawing (strong red and white belong to the kerbs and
## the barriers). A recognisable circuit stand in muted, structural colours:
##
##   * a concrete plinth with a galvanised railing along the front walkway
##   * stepped tiers (concrete risers and walkways) with rows of individual
##     seats in a desaturated blue / teal / grey, a shade apart per row
##   * stair aisles splitting it into sections, a dark steel column behind
##     every aisle carrying a thin cantilever roof over the upper rows
##   * a neutral corrugated roof with steel ribs, a dark fascia with a muted
##     banner and lamps under its edge (they glow at night when the stand is
##     in VoxelStage._glowing), two small flags in muted accents on top
##   * an enclosed concrete back (entrances, a window band) and stepped end
##     walls, so every side reads well from the race camera
##
## The footprint (nx * nz world cells) and facing match the old stand: the
## crowd side (+Z, the drawing's bottom edge) looks at the track. `people`
## fills about two thirds of the seats with little static voxel spectators (menu
## diorama, Battle Royale); on the circuits VoxelLife seats its animated crowd
## instead, in the seats listed in the mesh's "seats" meta. One mesh per
## (size, theme, people, style), shared by every placement.
##
## Mesh metadata: "grandstand" true, "cells" Vector2i(nx, nz), "seats"
## PackedVector3Array of the free seats (local, the top of the seat cushion
## under the middle of the sitter), "front" Vector3 local facing (+Z).

const VS := Vox.CELL_PX
const TIER_D := 5   ## cells per tier, front to back: 2 legroom, 2 seat, 1 backrest
const RISE := 3     ## cells each tier climbs
const FRONT := 2    ## front wall + walkway
const AISLE := 2

## Structural colours (sRGB): weathered concrete, steel, roof sheeting.
const PLINTH := Color(0.53, 0.52, 0.5)
const CONCRETE := Color(0.64, 0.63, 0.6)
const WALK := Color(0.71, 0.7, 0.67)
const STAIR := Color(0.77, 0.76, 0.72)
const CAP := Color(0.75, 0.74, 0.7)
const STEEL := Color(0.2, 0.22, 0.25)
const RAIL := Color(0.4, 0.42, 0.46)
const ROOF := Color(0.6, 0.62, 0.64)
const FASCIA := Color(0.23, 0.26, 0.3)
const DOOR := Color(0.13, 0.14, 0.16)
const LAMP := Color(1.0, 0.92, 0.72)
const SNOW := Color(0.93, 0.95, 0.98)

## Seat colour per track theme (0: neutral - the menu, the arena).
const SEATS := {
	0: Color(0.33, 0.43, 0.55),  # slate blue
	1: Color(0.33, 0.43, 0.55),  # Green Valley: slate blue against the meadow
	2: Color(0.37, 0.45, 0.42),  # the wasteland: weathered grey-green
	3: Color(0.26, 0.42, 0.5),   # snow: deep teal
	4: Color(0.29, 0.34, 0.47),  # The Raceway: navy grey
}
## Muted accents for the banners and the flags (ochre, teal, slate, sage);
## a stand's `style` picks the pair, so a row of stands is not all alike.
const ACCENTS := [Color(0.74, 0.58, 0.3), Color(0.24, 0.5, 0.5), Color(0.33, 0.39, 0.53), Color(0.5, 0.58, 0.42)]
const STYLES := 3
## Static spectators: shirts (the crowd's own bright, individual colours),
## trousers, heads (skin tones, hair, caps).
const SHIRTS := [Color("f7b731"), Color("e8e8f0"), Color("e8432e"), Color("59c3f2"), Color("7bc950"),
	Color("f45b9b"), Color("2ec4b6"), Color("a37ef0"), Color("ff8c2e"), Color("3d4a8a"),
	Color("f2efe6"), Color("3f6b4a"), Color("8a4a3a"), Color("5a6a8a")]
const TROUSERS := [Color(0.16, 0.18, 0.28), Color(0.22, 0.2, 0.18), Color(0.42, 0.38, 0.3)]
const HEADS := [Color(0.93, 0.72, 0.56), Color(0.78, 0.55, 0.38), Color(0.5, 0.33, 0.22),
	Color(0.24, 0.17, 0.12), Color(0.12, 0.1, 0.09), Color(0.85, 0.7, 0.4)]

## Roles of a column of cells along x.
const R_END := 0
const R_AISLE := 1
const R_SEAT := 2
const R_GAP := 3

static var _meshes: Dictionary = {}


## The grandstand for a footprint of nx * nz world cells (Vox.CELL_PX each);
## style 0 .. STYLES - 1 (banner and flag colours).
static func mesh(nx: int, nz: int, variant: int = 0, people: bool = true, style: int = 0) -> ArrayMesh:
	style = posmod(style, STYLES)
	var key := "%d|%d|%d|%d|%d" % [nx, nz, variant, int(people), style]
	if _meshes.has(key):
		return _meshes[key]
	var m := _build(maxi(nx, 24), maxi(nz, 16), variant, people, style)
	_meshes[key] = m
	return m


static func _build(nx: int, nz: int, variant: int, people: bool, style: int) -> ArrayMesh:
	var tiers := maxi(1, (nz - FRONT - 3) / TIER_D)
	var d_conc := FRONT + tiers * TIER_D          # the top concourse (depth from the front)
	var fc := 2 + RISE * tiers                    # its floor
	var y_roof := fc + 6
	var d_roof := FRONT + TIER_D * maxi(0, tiers - 2) + 2  # the roof's front edge
	var ny := y_roof + 9
	var g := VoxelGrid.new(Vector3i(nx, ny, nz), VS * Vox.PX, Vector3.ZERO)
	var seat_col: Color = SEATS.get(variant, SEATS[0])
	var snow := variant == 3
	var accent_a: Color = ACCENTS[style % ACCENTS.size()]
	var accent_b: Color = ACCENTS[(style + 1) % ACCENTS.size()]

	# --- along x: end walls, sections of seats (2 cells + a gap), aisles
	var inner := nx - 2
	var nsec := maxi(1, int(round(inner / 18.0)))
	var sw := (inner - (nsec - 1) * AISLE) / nsec
	var spare := inner - nsec * sw - (nsec - 1) * AISLE
	var x0 := 1 + spare / 2
	var role := PackedInt32Array()
	var section := PackedInt32Array()
	role.resize(nx)
	section.resize(nx)
	role.fill(R_END)
	section.fill(-1)
	var columns: Array = [0, 1, nx - 2, nx - 1]
	var seat_x := PackedInt32Array()  # the left cell of every seat (two cells wide)
	var nseat := maxi(1, (sw - 1) / 3)
	var off := (sw - (nseat * 3 - 1)) / 2
	for s in nsec:
		var xs := x0 + s * (sw + AISLE)
		for u in sw:
			var x := xs + u
			section[x] = s
			var k := u - off
			role[x] = R_SEAT if (k >= 0 and k < nseat * 3 - 1 and k % 3 != 2) else R_GAP
			if role[x] == R_SEAT and k % 3 == 0:
				seat_x.append(x)
		if s < nsec - 1:
			for a in AISLE:
				role[xs + sw + a] = R_AISLE
				columns.append(xs + sw + a)

	# --- the body: plinth, tiers, aisles' stairs, end walls, back wall
	for d in nz:
		var z := nz - 1 - d
		for x in nx:
			var r := role[x]
			var top := 0
			var surf := WALK
			if d >= nz - 1:
				continue  # (the column row behind the back wall)
			if d >= nz - 2:
				top = y_roof  # the enclosed back wall
				surf = CONCRETE
			elif d < FRONT:
				top = 2
				surf = CAP if d == 0 else WALK
			elif d < d_conc:
				var i := (d - FRONT) / TIER_D
				var j := (d - FRONT) % TIER_D
				var f := 2 + RISE * i
				top = f
				if r == R_AISLE:
					var step: int = [0, 0, 1, 2, 2][j]
					top = f + step
					surf = STAIR.darkened(0.05 * ((i * 3 + step) % 2))
				elif r == R_END:
					top = f + 3
					surf = CAP
			else:
				top = fc
				if r == R_END:
					top = fc + 3
					surf = CAP
			if d < FRONT and r == R_END:
				top = 4
				surf = CAP
			for y in top:
				var c := CONCRETE
				if y == top - 1:
					c = surf
				elif y < 2:
					c = PLINTH
				if d >= nz - 2:
					c = _back_wall(x, y, fc, role, section, sw, x0)
				elif r == R_END and y >= 2:
					c = CONCRETE.darkened(0.06) if y < top - 1 else CAP
				elif d == 0 and y < 2 and x % 6 == 0:
					c = PLINTH.darkened(0.08)  # expansion joints in the front wall
				var w := 1.0 + (Vox.hash3(x / 2, y, z / 2) - 0.5) * 0.05  # weathering
				g.set_v(x, y, z, Vox.SOLID, Color(c.r * w, c.g * w, c.b * w))

	# --- seats, row by row (and the static spectators)
	var free := PackedVector3Array()
	var cs := VS * Vox.PX
	for i in tiers:
		var f := 2 + RISE * i
		var d0 := FRONT + i * TIER_D
		for x in seat_x:
			var tone := seat_col.lightened(0.07) if i % 2 == 0 else seat_col.darkened(0.04)
			if section[x] % 2 == 1:
				tone = tone.lerp(Color(0.5, 0.52, 0.55), 0.22)  # the sections a shade apart
			var back := tone.darkened(0.16)
			for dx in 2:
				for j in [2, 3]:
					g.set_v(x + dx, f, nz - 1 - (d0 + j), Vox.SOLID, tone)
				g.set_v(x + dx, f, nz - 1 - (d0 + 4), Vox.SOLID, back)
				g.set_v(x + dx, f + 1, nz - 1 - (d0 + 4), Vox.SOLID, back)
			var zc := nz - 1 - (d0 + 3)
			var h := Vox.hash3(x, i, 991)
			if people and h < 0.66:
				var shirt: Color = SHIRTS[int(Vox.hash3(x, i, 17) * SHIRTS.size()) % SHIRTS.size()]
				var legs: Color = TROUSERS[int(Vox.hash3(x, i, 23) * TROUSERS.size()) % TROUSERS.size()]
				var head: Color = HEADS[int(Vox.hash3(x, i, 29) * HEADS.size()) % HEADS.size()]
				if Vox.hash3(x, i, 31) < 0.18:
					head = shirt.darkened(0.25)  # a cap in the team colour
				for dx in 2:
					# knees / forearms on the knees (the shirt shows from above)
					g.set_v(x + dx, f + 1, nz - 1 - (d0 + 2), Vox.SOLID, legs if dx == 0 else shirt.darkened(0.12))
					g.set_v(x + dx, f + 1, zc, Vox.SOLID, shirt)
					g.set_v(x + dx, f + 2, zc, Vox.SOLID, shirt.darkened(0.06))
					g.set_v(x + dx, f + 3, zc, Vox.SOLID, head)
			else:
				free.append(Vector3((x + 1.0 - nx * 0.5) * cs, (f + 1) * cs, (zc + 0.5 - nz * 0.5) * cs))

	# --- the front railing (galvanised posts and a top rail)
	for x in nx:
		if role[x] == R_END:
			continue
		if x % 3 == 1:
			g.set_v(x, 2, nz - 1, Vox.METAL, RAIL)
		g.set_v(x, 3, nz - 1, Vox.METAL, RAIL)

	# --- steel columns behind every aisle and at the ends, up to the roof
	for x in columns:
		for y in y_roof:
			g.set_v(x, y, 0, Vox.METAL, STEEL.lightened(0.04 * (y % 2)))

	# --- the cantilever roof: sheeting, fascia + banner, ribs, lamps
	var banner_secs: Array = [nsec / 2 - 1, nsec / 2] if nsec >= 3 else [0]
	for d in range(d_roof, nz):
		var z := nz - 1 - d
		for x in nx:
			var c := ROOF.darkened(0.06) if x % 2 == 0 else ROOF
			if snow:
				c = SNOW.darkened(0.04 * Vox.hash3(x, 3, z))
			if d == d_roof:
				c = FASCIA
			g.set_v(x, y_roof, z, Vox.SOLID, c)
			if d == d_roof:
				var fc2 := FASCIA
				if section[x] in banner_secs and role[x] != R_AISLE:
					fc2 = accent_a.darkened(0.08) if section[x] == banner_secs[0] else accent_b.darkened(0.08)
				g.set_v(x, y_roof - 1, z, Vox.SOLID, fc2)
				g.set_v(x, y_roof - 2, z, Vox.SOLID, fc2.darkened(0.08))
			elif d == d_roof + 1 and x % 4 == 2 and role[x] != R_AISLE:
				g.set_v(x, y_roof - 1, z, Vox.GLOW, LAMP)
	var mid := (d_roof + nz - 1) / 2
	for x in columns:
		if x == 1 or x == nx - 2:
			continue
		for d in range(d_roof + 1, nz):
			g.set_v(x, y_roof + 1, nz - 1 - d, Vox.METAL, STEEL)
			if d >= mid:
				g.set_v(x, y_roof + 2, nz - 1 - d, Vox.METAL, STEEL)

	# --- two small flags on the back corners of the roof
	for k in 2:
		var px := 1 if k == 0 else nx - 2
		var dir := 1 if k == 0 else -1
		for y in range(y_roof + 1, y_roof + 9):
			g.set_v(px, y, 0, Vox.METAL, Color(0.78, 0.79, 0.8))
		var cloth: Color = accent_a if k == 0 else accent_b
		for row in 3:
			for u in range(1, 5):
				g.set_v(px + u * dir, y_roof + 8 - row, 0, Vox.SOLID, cloth if row != 1 else cloth.lightened(0.12))

	var pivot := Vector3(nx * 0.5, 0.0, nz * 0.5) * cs
	var mesh := VoxelMesher.build_mesh(g, VoxelCars.material(), pivot, 0.035)
	mesh.set_meta("grandstand", true)
	mesh.set_meta("cells", Vector2i(nx, nz))
	mesh.set_meta("seats", free)
	mesh.set_meta("front", Vector3(0, 0, 1))
	return mesh


## The enclosed back wall, seen from behind: a darker base course, an
## entrance in the middle of every section, a band of small windows.
static func _back_wall(x: int, y: int, fc: int, role: PackedInt32Array, section: PackedInt32Array, sw: int, x0: int) -> Color:
	if section[x] >= 0:
		var mid := x0 + section[x] * (sw + AISLE) + sw / 2
		if absi(x - mid) <= 2 and y < 4:
			return DOOR
		if y >= fc - 6 and y <= fc - 5 and x % 4 != 0 and role[x] != R_AISLE:
			return Color(0.2, 0.24, 0.29)  # the window band
	if y < 2:
		return PLINTH
	if y == fc:
		return CONCRETE.darkened(0.08)
	return CONCRETE
