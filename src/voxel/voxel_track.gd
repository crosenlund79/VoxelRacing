class_name VoxelTrack
extends Node3D
## Converts a built HyperCars Track (2D) into a voxel diorama.
##
## Conversion, not redesign: the circuit's own 2D nodes (ground, road, barrier
## lines, dividers, pit markings, start line, jump paint, ravines, kerb / grid
## box / road wear decals) are duplicated into an offscreen viewport and
## rendered twice at voxel resolution (Vox.CELL_PX per cell):
##   * a colour pass: the biome's own artwork, one colour per voxel column,
##   * a class pass: flat colours that say what each cell is (grass, road,
##     barrier, divider, kerb, pit).
## Heights come from the class (barriers stand BARRIER_H voxels tall, kerbs
## one, the flyover ravine sinks), grass gets gentle terraced hills away from
## the road and the odd flower / tuft voxel. The heightfield is greedy-meshed
## in chunks. Elevated stretches (bridges) are built as real decks with
## railings, embankments and pillars over the road below; the flyover jump's
## gap is an actual gap.
## Presentation only: physics, collision and race rules stay in the 2D Track.

signal built

const CELL := Vox.CELL_PX
const SS := 2
const CHUNK := 128
const BARRIER_H := 3
const DIVIDER_H := 2
const KERB_H := 1
const PIT_H := -3
## Bridges (px): full deck height above the ground, deck slab thickness,
## railing height; below EMBANK_PX the ramp is a solid embankment.
const DECK_H_PX := 44.0
const DECK_T_PX := 10.0
const RAIL_H_PX := 12.0
const EMBANK_PX := 22.0
const PILLAR_SPACING := 100.0

const C_GRASS := 0
const C_ROAD := 1
const C_BARRIER := 2
const C_DIVIDER := 3
const C_KERB := 4
const C_PIT := 5
## P003: a flower voxel on the grass (scenery, never drivable).
const C_FLOWER := 6

const TERRAIN_SHADER := preload("res://src/voxel/shaders/voxel_terrain.gdshader")
const FLAT_SHADER_CODE := "shader_type canvas_item;\nuniform vec4 flat_color;\nvoid fragment() {\n\tfloat a = texture(TEXTURE, UV).a * COLOR.a;\n\tCOLOR = vec4(flat_color.rgb, step(0.5, a));\n}\n"

## Terrain hills per biome (variant 1..5): amplitude in voxels.
const HILLS := [0, 6, 4, 5, 0, 0]

var track: Node2D  ## a Track, or the Battle Royale Arena
var theme: TrackTheme
var origin_px := Vector2.ZERO
var nx := 0
var nz := 0
var heights := PackedInt32Array()
var classes := PackedByteArray()
var terrain_material: ShaderMaterial
var deck_material: ShaderMaterial
var build_msec := 0
## Build progress 0..1 (the loading screen's race follows it).
var progress := 0.0
## The build gives the frame back after this long, so loading animates.
const SLICE_USEC := 20000
var _slice_start := 0


func _over_budget() -> bool:
	return Time.get_ticks_usec() - _slice_start > SLICE_USEC


func _yield_frame() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	_slice_start = Time.get_ticks_usec()
var _flat_shader: Shader
var _decal_sources: Array[Node] = []


## Terrain top height (px) at a 2D point (0 off the map).
func height_px_at(p: Vector2) -> float:
	var c := Vector2i(((p - origin_px) / CELL).floor())
	if c.x < 0 or c.y < 0 or c.x >= nx or c.y >= nz or heights.size() < nx * nz:
		return 0.0
	return heights[c.y * nx + c.x] * CELL


## Deck (bridge level) classes, where the circuit has elevation.
var deck_classes := PackedByteArray()


## True where cars drive: road, kerbs, pit lane - at ground level or on a
## bridge deck. Scenery never stands there.
func drivable_at(p: Vector2) -> bool:
	var c := Vector2i(((p - origin_px) / CELL).floor())
	if c.x < 0 or c.y < 0 or c.x >= nx or c.y >= nz:
		return false
	var i := c.y * nx + c.x
	for arr in [classes, deck_classes]:
		if (arr as PackedByteArray).size() == nx * nz:
			var k: int = arr[i]
			if k == C_ROAD or k == C_KERB or k == C_PIT:
				return true
	return false


func class_at(p: Vector2) -> int:
	var c := Vector2i(((p - origin_px) / CELL).floor())
	if c.x < 0 or c.y < 0 or c.x >= nx or c.y >= nz or classes.size() < nx * nz:
		return C_GRASS
	return classes[c.y * nx + c.x]


## decal_layer: HyperCars' decals node (grid boxes, road wear, kerbs are
## painted into the voxels; tyre marks stay dynamic, see VoxelStage).
func build(p_track: Node2D, decal_layer: Node2D) -> void:
	var t0 := Time.get_ticks_msec()
	track = p_track
	theme = track.theme if track.theme != null else TrackTheme.load_variant(1)
	_flat_shader = Shader.new()
	_flat_shader.code = FLAT_SHADER_CODE
	if decal_layer != null:
		for d in decal_layer.get_children():
			if d is Sprite2D:
				_decal_sources.append(d)
	var ground := track.get_node_or_null("Ground") as Polygon2D
	var bounds := Rect2()
	if ground != null:
		bounds = Rect2(ground.polygon[0], Vector2.ZERO)
		for p in ground.polygon:
			bounds = bounds.expand(p)
	else:
		bounds = Rect2(track.centerline[0], Vector2.ZERO)
		for p in track.centerline:
			bounds = bounds.expand(p)
		bounds = bounds.grow(Track.GROUND_MARGIN)
	origin_px = (bounds.position / CELL).floor() * CELL
	nx = int(ceil((bounds.end.x - origin_px.x) / CELL))
	nz = int(ceil((bounds.end.y - origin_px.y) / CELL))
	var passes := 4 if track.layout.has_elevation() else 2
	var color := await _render(_items("color"), SS)
	progress = 0.3 / passes
	color.resize(nx, nz, Image.INTERPOLATE_BILINEAR)
	var cls := await _render(_items("class"), 1)
	progress = 0.3 * 2.0 / passes
	var deck_color: Image = null
	var deck_cls: Image = null
	if track.layout.has_elevation():
		deck_color = await _render(_items("deck_color"), SS)
		progress = 0.3 * 3.0 / passes
		deck_color.resize(nx, nz, Image.INTERPOLATE_BILINEAR)
		deck_cls = await _render(_items("deck_class"), 1)
		progress = 0.3
	if not is_inside_tree():
		return  # the race was left while the world was being built
	_slice_start = Time.get_ticks_usec()
	var t1 := Time.get_ticks_msec()
	await _classify(cls)
	progress = 0.36
	await _compute_heights(color)
	progress = 0.62
	var t2 := Time.get_ticks_msec()
	terrain_material = await _make_material(color, _class_image(classes), true)
	await _build_terrain()
	var t3 := Time.get_ticks_msec()
	if deck_color != null and is_inside_tree():
		var dcls := PackedByteArray()
		dcls.resize(nx * nz)
		var data := deck_cls.get_data()
		for i in nx * nz:
			dcls[i] = _class_of(data[i * 4], data[i * 4 + 1], data[i * 4 + 2], data[i * 4 + 3])
			if (i & 16383) == 0 and _over_budget():
				await _yield_frame()
		deck_classes = dcls
		deck_material = await _make_material(deck_color, _class_image(dcls), false)
		_build_decks()
	progress = 1.0
	build_msec = Time.get_ticks_msec() - t0
	print("VoxelTrack: %dx%d cells, render %d ms, heights %d ms, mesh %d ms, total %d ms" % [nx, nz, t1 - t0, t2 - t1, t3 - t2, build_msec])
	built.emit()


# ------------------------------------------------------------ render passes

## Copies of the track's visual nodes for one pass: "color" / "class" (ground
## level) or "deck_color" / "deck_class" (the elevated stretches).
func _items(mode: String) -> Array[Node]:
	var out: Array[Node] = []
	var deck := mode.begins_with("deck")
	var flat := mode.ends_with("class")
	for child in track.get_children():
		if not (child is CanvasItem) or child is CollisionObject2D:
			continue
		var ci := child as CanvasItem
		if String(child.name).begins_with("Prop"):
			continue  # arena props become voxel models (VoxelStage)
		if ci.z_index == Track.BRIDGE_SHADOW_Z or String(child.name).begins_with("BridgeShadow"):
			continue
		if (ci.z_index >= Track.BRIDGE_DECK_Z) != deck:
			continue
		var d: Node = child.duplicate(0)
		if flat:
			if not _flatten(d):
				d.free()
				continue
		out.append(d)
	if not deck:
		for s in _decal_sources:
			var kerb := _is_kerb(s)
			if flat and not kerb:
				continue
			var d: Sprite2D = s.duplicate(0)
			d.visible = true
			if flat:
				_flat(d, Color(1, 1, 0))
			out.append(d)
	return out


func _is_kerb(s: Node) -> bool:
	var spr := s as Sprite2D
	return spr != null and spr.texture != null and spr.texture.resource_path.contains("kerb")


## Class pass: flat colour per node by role; false = leave it out.
func _flatten(n: Node) -> bool:
	var nm := String(n.name)
	if nm == "Ground":
		_flat(n, Color(0, 0, 0))
		return true
	if nm == "Road" or nm == "BridgeDeck":
		_flat(n, Color(1, 0, 0))
		return true
	if nm.begins_with("Barrier"):
		_flat(n, Color(0, 1, 0))
		return true
	if nm.begins_with("Divider"):  # raised islands (arena blocks and scrap piles)
		_flat(n, Color(0, 0, 1))
		return true
	if nm.begins_with("Ravine"):
		_flat(n, Color(1, 0, 1))
		return true
	if nm == "Branches":
		for c in n.get_children():
			var cn := String(c.name)
			if cn.begins_with("DividerWall"):
				_flat(c, Color(0, 1, 0))
			elif cn.begins_with("Divider"):
				_flat(c, Color(0, 0, 1))
			else:
				n.remove_child(c)
				c.free()
		return true
	return false


func _flat(n: Node, c: Color) -> void:
	var m := ShaderMaterial.new()
	m.shader = _flat_shader
	m.set_shader_parameter("flat_color", c)
	(n as CanvasItem).material = m
	if n is Polygon2D:
		(n as Polygon2D).color = Color.WHITE
	elif n is Line2D:
		(n as Line2D).default_color = Color.WHITE


func _render(items: Array[Node], scale: int) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(nx * scale, nz * scale)
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.position = origin_px - Vector2(64, 64)
	bg.size = Vector2(nx, nz) * CELL + Vector2(128, 128)
	vp.add_child(bg)
	var holder := Node2D.new()
	vp.add_child(holder)
	for it in items:
		holder.add_child(it)
	var s := float(scale) / CELL
	add_child(vp)
	vp.canvas_transform = Transform2D(0.0, Vector2(s, s), 0.0, -origin_px * s)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if not is_instance_valid(vp) or not is_inside_tree():
		return Image.create(maxi(1, nx), maxi(1, nz), false, Image.FORMAT_RGBA8)
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	vp.queue_free()
	return img


static func _class_of(r: int, g: int, b: int, _a: int) -> int:
	if r > 128 and g > 128:
		return C_KERB
	if r > 128 and b > 128:
		return C_PIT
	if r > 128:
		return C_ROAD
	if g > 128:
		return C_BARRIER
	if b > 128:
		return C_DIVIDER
	return C_GRASS


func _classify(cls: Image) -> void:
	classes.resize(nx * nz)
	var data := cls.get_data()
	for i in nx * nz:
		classes[i] = _class_of(data[i * 4], data[i * 4 + 1], data[i * 4 + 2], data[i * 4 + 3])
		if (i & 16383) == 0 and _over_budget():
			await _yield_frame()


func _class_image(c: PackedByteArray) -> Image:
	return Image.create_from_data(nx, nz, false, Image.FORMAT_R8, c)


# ------------------------------------------------------------ heights

## P003 meadow (Green Valley, The Raceway): the menu island's grass green,
## how much of it is mixed into the circuit's own grass, and the flowers.
const MEADOW := Color("7bc950")
const MEADOW_BLEND := 0.55
const FLOWER_SHARE := 0.06
const FLOWERS := [Color("f7b731"), Color("f45b9b"), Color("fff4de"), Color("ff8c2e")]


func is_meadow() -> bool:
	return theme != null and (theme.variant == 1 or theme.variant == 4)


## Flower voxels like the menu island's: a share of the open grass (away from
## the road) gets a raised cell in a flower colour (class C_FLOWER, so the
## terrain shader leaves its colour alone). The grass itself is tinted
## towards the menu's green in the terrain shader.
func _plant_flowers(color: Image, near: PackedByteArray) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242 + theme.variant
	var tries := int(nx * nz * FLOWER_SHARE)
	for k in tries:
		var i := rng.randi_range(0, nx * nz - 1)
		if classes[i] != C_GRASS or near[i] >= 24 or heights[i] >= 2:
			continue
		classes[i] = C_FLOWER
		heights[i] += 1
		color.set_pixel(i % nx, i / nx, FLOWERS[rng.randi_range(0, FLOWERS.size() - 1)])
		if (k & 8191) == 0 and _over_budget():
			await _yield_frame()


func _compute_heights(color: Image) -> void:
	heights.resize(nx * nz)
	var amp: int = HILLS[clampi(theme.variant, 0, HILLS.size() - 1)]
	# how near the road / barriers each cell is (blurred mask, 0 = far)
	var mask_data := PackedByteArray()
	mask_data.resize(nx * nz)
	for i in nx * nz:
		mask_data[i] = 0 if classes[i] == C_GRASS else 255
		if (i & 16383) == 0 and _over_budget():
			await _yield_frame()
	var near := _blurred(Image.create_from_data(nx, nz, false, Image.FORMAT_L8, mask_data), 5).get_data()
	var hills := PackedByteArray()
	if amp > 0:
		var noise := FastNoiseLite.new()
		noise.seed = 1991 + theme.variant * 7
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.0065
		noise.fractal_octaves = 3
		hills = noise.get_image(nx, nz, false, false, true).get_data()
	# flowers / tufts: grass cells whose colour stands out from the local mean
	var meadow := is_meadow()
	var cdata := color.get_data()
	var mean := color.duplicate() as Image
	mean = _blurred(mean, 2)
	var mdata := mean.get_data()
	var cstride := 4 if color.get_format() == Image.FORMAT_RGBA8 else 3
	var mstride := 4 if mean.get_format() == Image.FORMAT_RGBA8 else 3
	for i in nx * nz:
		var c := classes[i]
		var h := 0
		match c:
			C_BARRIER:
				h = BARRIER_H
			C_DIVIDER:
				h = DIVIDER_H
			C_KERB:
				h = KERB_H
			C_PIT:
				h = PIT_H
			C_GRASS:
				if amp > 0 and near[i] < 3:
					var v := (float(hills[i]) / 255.0 - 0.5) / 0.5
					if v > 0.0:
						h = int(v * (amp + 0.99) * (1.0 - float(near[i]) / 3.0))
				var dr := absi(cdata[i * cstride] - mdata[i * mstride])
				var dg := absi(cdata[i * cstride + 1] - mdata[i * mstride + 1])
				var db := absi(cdata[i * cstride + 2] - mdata[i * mstride + 2])
				if dr + dg + db > 70 and near[i] < 200:
					h += 1
		heights[i] = h
		if (i & 8191) == 0 and _over_budget():
			progress = 0.36 + 0.26 * float(i) / (nx * nz)
			await _yield_frame()
	if meadow:
		await _plant_flowers(color, near)


## Box-blurred copy by repeated halving, scaled back to the map size.
func _blurred(img: Image, levels: int) -> Image:
	var small := img.duplicate() as Image
	for _k in levels:
		small.resize(maxi(1, small.get_width() / 2), maxi(1, small.get_height() / 2), Image.INTERPOLATE_BILINEAR)
	small.resize(nx, nz, Image.INTERPOLATE_BILINEAR)
	return small


func _make_material(color: Image, cls_img: Image, with_heights: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TERRAIN_SHADER
	var c := color.duplicate() as Image
	c.convert(Image.FORMAT_RGB8)
	m.set_shader_parameter("color_map", ImageTexture.create_from_image(c))
	m.set_shader_parameter("class_map", ImageTexture.create_from_image(cls_img))
	if with_heights:
		var hb := PackedByteArray()
		hb.resize(nx * nz)
		for i in nx * nz:
			hb[i] = clampi(heights[i] + 64, 0, 255)
			if (i & 16383) == 0 and _over_budget():
				await _yield_frame()
		m.set_shader_parameter("height_map", ImageTexture.create_from_image(Image.create_from_data(nx, nz, false, Image.FORMAT_R8, hb)))
	m.set_shader_parameter("use_heights", with_heights)
	m.set_shader_parameter("map_origin", Vector2(origin_px.x, origin_px.y) * Vox.PX)
	m.set_shader_parameter("cell", CELL * Vox.PX)
	m.set_shader_parameter("map_cells", Vector2(nx, nz))
	m.set_shader_parameter("decal_px", 1.0 / Vox.PX)
	var soil := Color(0.5, 0.37, 0.25)
	if theme.variant == 3:
		soil = Color(0.62, 0.6, 0.62)
	elif theme.variant == 5:
		soil = Color(0.55, 0.37, 0.22)
	if is_meadow():
		m.set_shader_parameter("meadow_on", 1.0)
		m.set_shader_parameter("meadow_col", MEADOW)
		m.set_shader_parameter("meadow_blend", MEADOW_BLEND)
	m.set_shader_parameter("soil_color", soil)
	m.set_shader_parameter("soil_dark", soil.darkened(0.3))
	return m


# ------------------------------------------------------------ terrain mesh

func _build_terrain() -> void:
	var holder := Node3D.new()
	holder.name = "Terrain"
	add_child(holder)
	var cz0 := 0
	var chunks := ceili(float(nx) / CHUNK) * ceili(float(nz) / CHUNK)
	var done := 0
	while cz0 < nz:
		var cx0 := 0
		while cx0 < nx:
			var mesh := _mesh_chunk(cx0, cz0, mini(cx0 + CHUNK, nx), mini(cz0 + CHUNK, nz))
			if mesh != null:
				var mi := MeshInstance3D.new()
				mi.mesh = mesh
				mi.material_override = terrain_material
				holder.add_child(mi)
			cx0 += CHUNK
			done += 1
			progress = 0.66 + 0.3 * float(done) / chunks
			if _over_budget():
				await _yield_frame()
				if not is_inside_tree():
					return
		cz0 += CHUNK


func _mesh_chunk(x0: int, z0: int, x1: int, z1: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var inds := PackedInt32Array()
	var c := CELL * Vox.PX
	var ox := origin_px.x * Vox.PX
	var oz := origin_px.y * Vox.PX
	var w := x1 - x0
	var done := PackedByteArray()
	done.resize(w * (z1 - z0))
	var H := heights
	# top faces, greedy rectangles of equal height
	for z in range(z0, z1):
		var row := z * nx
		for x in range(x0, x1):
			if done[(z - z0) * w + x - x0] == 1:
				continue
			var h := H[row + x]
			var rw := 1
			while x + rw < x1 and done[(z - z0) * w + x + rw - x0] == 0 and H[row + x + rw] == h:
				rw += 1
			var rd := 1
			var grow := true
			while grow and z + rd < z1:
				var r2 := (z + rd) * nx
				for k in rw:
					if done[(z + rd - z0) * w + x + k - x0] == 1 or H[r2 + x + k] != h:
						grow = false
						break
				if grow:
					rd += 1
			for dz in rd:
				for k in rw:
					done[(z + dz - z0) * w + x + k - x0] = 1
			var y := h * c
			_quad(verts, norms, inds, Vector3(ox + x * c, y, oz + z * c), Vector3(rw * c, 0, 0), Vector3(0, 0, rd * c), Vector3.UP)
	# side faces between columns of different height (x boundaries)
	for x in range(x0, x1):
		var z := z0
		while z < z1:
			var a := H[z * nx + x]
			var b := H[z * nx + x + 1] if x + 1 < nx else -12
			if a == b:
				z += 1
				continue
			var z2 := z + 1
			var b2 := 0
			while z2 < z1:
				b2 = H[z2 * nx + x + 1] if x + 1 < nx else -12
				if H[z2 * nx + x] != a or b2 != b:
					break
				z2 += 1
			var px := ox + (x + 1) * c
			var lo := mini(a, b) * c
			var hi := maxi(a, b) * c
			if a > b:  # face points +X
				_quad(verts, norms, inds, Vector3(px, lo, oz + z * c), Vector3(0, 0, (z2 - z) * c), Vector3(0, hi - lo, 0), Vector3.RIGHT)
			else:
				_quad(verts, norms, inds, Vector3(px, lo, oz + z2 * c), Vector3(0, 0, -(z2 - z) * c), Vector3(0, hi - lo, 0), Vector3.LEFT)
			z = z2
		if x == 0:  # the map's west edge
			var zz := z0
			while zz < z1:
				var a := H[zz * nx]
				var z2 := zz + 1
				while z2 < z1 and H[z2 * nx] == a:
					z2 += 1
				_quad(verts, norms, inds, Vector3(ox, -12 * c, oz + z2 * c), Vector3(0, 0, -(z2 - zz) * c), Vector3(0, (a + 12) * c, 0), Vector3.LEFT)
				zz = z2
	# z boundaries
	for z in range(z0, z1):
		var x := x0
		while x < x1:
			var a := H[z * nx + x]
			var b := H[(z + 1) * nx + x] if z + 1 < nz else -12
			if a == b:
				x += 1
				continue
			var x2 := x + 1
			while x2 < x1:
				var b2 := H[(z + 1) * nx + x2] if z + 1 < nz else -12
				if H[z * nx + x2] != a or b2 != b:
					break
				x2 += 1
			var pz := oz + (z + 1) * c
			var lo := mini(a, b) * c
			var hi := maxi(a, b) * c
			if a > b:  # face points +Z
				_quad(verts, norms, inds, Vector3(ox + x2 * c, lo, pz), Vector3(-(x2 - x) * c, 0, 0), Vector3(0, hi - lo, 0), Vector3.BACK)
			else:
				_quad(verts, norms, inds, Vector3(ox + x * c, lo, pz), Vector3((x2 - x) * c, 0, 0), Vector3(0, hi - lo, 0), Vector3.FORWARD)
			x = x2
		if z == 0:  # the map's north edge
			var xx := x0
			while xx < x1:
				var a := H[xx]
				var x2 := xx + 1
				while x2 < x1 and H[x2] == a:
					x2 += 1
				_quad(verts, norms, inds, Vector3(ox + xx * c, -12 * c, oz), Vector3((x2 - xx) * c, 0, 0), Vector3(0, (a + 12) * c, 0), Vector3.FORWARD)
				xx = x2
	if verts.is_empty():
		return null
	var cols := PackedColorArray()
	cols.resize(verts.size())
	cols.fill(Color(1, 1, 1, 1))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = inds
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## A quad from corner p spanned by edges u and v; front face along `normal`
## (winding chosen from u x v so it is always visible from the normal side).
static func _quad(verts: PackedVector3Array, norms: PackedVector3Array, inds: PackedInt32Array, p: Vector3, u: Vector3, v: Vector3, normal: Vector3) -> void:
	var b := verts.size()
	verts.append(p)
	verts.append(p + u)
	verts.append(p + u + v)
	verts.append(p + v)
	for k in 4:
		norms.append(normal)
	if u.cross(v).dot(normal) > 0.0:
		inds.append_array([b, b + 2, b + 1, b, b + 3, b + 2])
	else:
		inds.append_array([b, b + 1, b + 2, b, b + 2, b + 3])


# ------------------------------------------------------------ bridges

## Height of the deck (px) at arc distance s (0 off the bridge).
func deck_height_px(s: float) -> float:
	if not track.layout.has_elevation():
		return 0.0
	return track.bridge_height(s) * DECK_H_PX


func _build_decks() -> void:
	var holder := Node3D.new()
	holder.name = "Bridges"
	add_child(holder)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var inds := PackedInt32Array()
	var c: PackedVector2Array = track.centerline
	var n := c.size()
	var tans := TrackLayout.tangents(c)
	var wall_w: float = AssetCatalog.SPECS[theme.asset(AssetCatalog.WALL)].display_size.y
	var concrete := Color(0.62, 0.6, 0.57)
	if theme.variant == 5:
		concrete = Color(0.7, 0.55, 0.36)
	var pillar_spots: Array = []
	for run in track._deck_runs():
		if run.level != 1:
			continue
		var prev := {}
		var last_pillar := -INF
		for k in range(run.from, run.to + 1):
			var i: int = k % n
			var s: float = track.path.cumulative[i]
			var h := maxf(deck_height_px(s), 1.0)
			var r := Vector2(-tans[i].y, tans[i].x)
			var lw: float = track.left_widths[i]
			var rw: float = track.right_widths[i]
			var bottom := 0.0 if h < EMBANK_PX else h - DECK_T_PX
			var cur := {
				"ol": c[i] - r * (lw + wall_w), "il": c[i] - r * lw,
				"ir": c[i] + r * rw, "or": c[i] + r * (rw + wall_w),
				"h": h, "b": bottom, "r": r,
			}
			if not prev.is_empty():
				_deck_segment(verts, norms, cols, inds, prev, cur, concrete)
			else:
				_deck_cap(verts, norms, cols, inds, cur, -tans[i], concrete)
			prev = cur
			if bottom > 0.0 and s - last_pillar > PILLAR_SPACING:
				last_pillar = s
				for off in [0.0, -lw * 0.75, rw * 0.75]:
					var p: Vector2 = c[i] + r * off
					if class_at(p) == C_GRASS:
						pillar_spots.append([p, bottom, tans[i].angle()])
						break
		if not prev.is_empty():
			var i_end: int = run.to % n
			_deck_cap(verts, norms, cols, inds, prev, tans[i_end], concrete)
	if verts.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = inds
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "Decks"
	mi.mesh = mesh
	mi.material_override = deck_material
	holder.add_child(mi)
	for spot in pillar_spots:
		var pil := MeshInstance3D.new()
		pil.mesh = _pillar_mesh(spot[1], concrete)
		pil.position = Vox.to3(spot[0])
		pil.rotation.y = Vox.yaw(spot[2])
		holder.add_child(pil)


func _deck_segment(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray, inds: PackedInt32Array,
		a: Dictionary, b: Dictionary, concrete: Color) -> void:
	var paint := Color(1, 1, 1, 1)
	var plain := Color(concrete, 0.0)
	var top_a: float = a.h + RAIL_H_PX
	var top_b: float = b.h + RAIL_H_PX
	# road surface
	_strip(verts, norms, cols, inds, a.il, b.il, a.ir, b.ir, a.h, b.h, a.h, b.h, Vector3.UP, paint)
	# railing tops
	_strip(verts, norms, cols, inds, a.ol, b.ol, a.il, b.il, top_a, top_b, top_a, top_b, Vector3.UP, paint)
	_strip(verts, norms, cols, inds, a.ir, b.ir, a["or"], b["or"], top_a, top_b, top_a, top_b, Vector3.UP, paint)
	# railing inner faces (towards the road)
	_wall(verts, norms, cols, inds, a.il, b.il, a.h, b.h, top_a, top_b, Vox.to3(a.r), paint)
	_wall(verts, norms, cols, inds, a.ir, b.ir, a.h, b.h, top_a, top_b, -Vox.to3(a.r), paint)
	# outer faces: railing, then the slab / embankment in concrete
	_wall(verts, norms, cols, inds, a.ol, b.ol, a.h - 1.0, b.h - 1.0, top_a, top_b, -Vox.to3(a.r), paint)
	_wall(verts, norms, cols, inds, a["or"], b["or"], a.h - 1.0, b.h - 1.0, top_a, top_b, Vox.to3(a.r), paint)
	_wall(verts, norms, cols, inds, a.ol, b.ol, a.b, b.b, a.h - 1.0, b.h - 1.0, -Vox.to3(a.r), plain)
	_wall(verts, norms, cols, inds, a["or"], b["or"], a.b, b.b, a.h - 1.0, b.h - 1.0, Vox.to3(a.r), plain)
	# underside of the slab
	if a.b > 0.0 and b.b > 0.0:
		_strip(verts, norms, cols, inds, a.ol, b.ol, a["or"], b["or"], a.b, b.b, a.b, b.b, Vector3.DOWN, Color(concrete.darkened(0.3), 0.0))


func _deck_cap(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray, inds: PackedInt32Array,
		e: Dictionary, outward: Vector2, concrete: Color) -> void:
	var n3 := Vox.to3(outward).normalized()
	_wall(verts, norms, cols, inds, e.ol, e["or"], e.b, e.b, e.h + RAIL_H_PX, e.h + RAIL_H_PX, n3, Color(concrete, 0.0))


## Horizontal-ish strip: left edge a0 -> b0, right edge a1 -> b1 (2D px), heights per corner.
static func _strip(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray, inds: PackedInt32Array,
		a0: Vector2, b0: Vector2, a1: Vector2, b1: Vector2, ha0: float, hb0: float, ha1: float, hb1: float, normal: Vector3, col: Color) -> void:
	var p := [Vox.to3(a0, ha0), Vox.to3(b0, hb0), Vox.to3(b1, hb1), Vox.to3(a1, ha1)]
	_poly(verts, norms, cols, inds, p, normal, col)


## Vertical wall along a -> b from heights lo to hi, facing `normal`.
static func _wall(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray, inds: PackedInt32Array,
		a: Vector2, b: Vector2, lo_a: float, lo_b: float, hi_a: float, hi_b: float, normal: Vector3, col: Color) -> void:
	if hi_a <= lo_a and hi_b <= lo_b:
		return
	var p := [Vox.to3(a, lo_a), Vox.to3(b, lo_b), Vox.to3(b, hi_b), Vox.to3(a, hi_a)]
	_poly(verts, norms, cols, inds, p, normal, col)


static func _poly(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray, inds: PackedInt32Array,
		p: Array, normal: Vector3, col: Color) -> void:
	var b := verts.size()
	for k in 4:
		verts.append(p[k])
		norms.append(normal)
		cols.append(col)
	var face: Vector3 = (p[1] - p[0]).cross(p[3] - p[0])
	if face.dot(normal) > 0.0:
		inds.append_array([b, b + 2, b + 1, b, b + 3, b + 2])
	else:
		inds.append_array([b, b + 1, b + 2, b, b + 2, b + 3])


static var _pillars: Dictionary = {}


## A voxel pillar (CELL px voxels) from the ground to `top_px`, with a cap.
func _pillar_mesh(top_px: float, concrete: Color) -> ArrayMesh:
	var hc := maxi(1, int(round(top_px / CELL)))
	var key := "%d|%s" % [hc, concrete.to_html()]
	if _pillars.has(key):
		return _pillars[key]
	var g := VoxelGrid.new(Vector3i(8, hc, 6), CELL * Vox.PX, Vector3.ZERO)
	for y in hc:
		for z in 6:
			for x in 8:
				var cap := y >= hc - 2
				if not cap and (x == 0 or x == 7):
					continue
				var c := concrete.darkened(0.08 * float((x + y + z) % 3) * 0.5)
				if not cap and y % 5 == 0:
					c = c.darkened(0.12)
				g.set_v(x, y, z, Vox.SOLID, c)
	var mesh := VoxelMesher.build_mesh(g, VoxelCars.material(), Vector3(4, 0, 3) * CELL * Vox.PX, 0.04)
	_pillars[key] = mesh
	return mesh
