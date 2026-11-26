class_name CircuitPreview
extends Control
## The race setup screen's centrepiece (P005): a miniature voxel diorama of
## the chosen circuit - or, for Battle Royale, of the Scrapyard arena
## (show_arena) - floating like a model-railway island over the menu.
##
## Built from the real geometry: the centreline and its widths (narrow
## sections, pit lane and split lanes from the branches), bridges lifted on
## pillars, a flyover jump's gap left open, a ground jump's ramp and pit, the
## chequered start line with its gantry and a few cars waiting on the grid.
## The environment (TrackTheme variant 1..5) sets the ground, soil, road and
## kerb colours and the scenery: meadow trees, flowers, a barn and a windmill;
## heather, rocks, dead trees and sheds in the wet Wasteland; snowy pines and
## a cabin; The Raceway's grandstands, pit garages, boards and floodlights;
## the Tabletop's wooden desk with giant pencils, dice, cards and a mug.
## Night: dark blue ambient light, glowing lamps with warm point lights and
## lit windows; day: a warm sun with soft shadows.
##
## Rendered in its own 3D world (a SubViewport with a transparent background
## and MSAA) shown by a TextureRect that follows the control's size; the
## camera frames the whole island at a 3/4 view and sways gently from side to
## side. Rendering stops while the control is hidden. Rebuilt on every show_*
## call, so it is quick: the island is a heightfield meshed with merged faces,
## the per-layout raster and every finished diorama (per layout and
## environment) are cached, and switching day / night or coming back to a
## circuit only recreates a few nodes.

## Island cells across the circuit's longer side (1 cell = 1 world unit).
const TRACK_CELLS := 100.0
## Island cells beyond the circuit's bounding box.
const MARGIN := 7
## The island is at least this deep (z) for its width (x).
const DEPTH := 0.8
## Height of the ground surface (cells): turf, soil, then rock.
const G := 6
## Rock layers that step inwards under the island's rim.
const TAPER := 3
## A bridge deck's height above the ground (cells; exaggerated to read).
const BRIDGE_H := 4
## The road (and its lanes) is drawn this much wider than it really is.
const ROAD_SCALE := 1.15
## Cells beside the road kept clear of scenery.
const CLEAR := 1.5
## Prop voxel edge (world units; half a terrain cell).
const PV := 0.5
## Camera: elevation (rad), vertical field of view, share of the view the
## island may fill, and the gentle side-to-side sway (rad, rad/s).
const PITCH := 0.66
const FOV := 22.0
const FILL := 0.94
const SWAY := 0.12
const SWAY_RATE := 0.21
## Finished dioramas kept (layout x environment).
const CACHE_SIZE := 12
const AO := [0.5, 0.68, 0.85, 1.0]

## Cell classes of the raster.
enum {FREE, VERGE, ROAD, KERB_A, KERB_B, DIVIDER, PIT, APRON, CHECK_A, CHECK_B, HOLE, RAMP, UNDER,
	YARD, WALL_A, WALL_B, PILE, PILE_TOP, BLOCK_A, BLOCK_B, BAR_A, BAR_B, TAKEN}

## Environment looks (variant -> colours).
const LOOKS := {
	1: {"ground": Color("62ae45"), "ground2": Color("559c3c"), "soil": Color("86603e"), "soil2": Color("73512f"),
		"rock": Color("5e5049"), "road": Color("4b4e58"), "pit": Color("5d606b"), "apron": Color("9a9ca2"),
		"kerb": Color("e5432f"), "kerb2": Color("f3eee5"), "rail": Color("ece7dd"), "concrete": Color("b9b3a8"),
		"yard": Color("8f8575"), "wall": Color("8f969e"), "wall2": Color("a35a3a")},
	2: {"ground": Color("7f7650"), "ground2": Color("6e6646"), "soil": Color("6e563a"), "soil2": Color("5d4730"),
		"rock": Color("4f4741"), "road": Color("4f535e"), "pit": Color("5f636d"), "apron": Color("8b887a"),
		"kerb": Color("d2bf96"), "kerb2": Color("77746b"), "rail": Color("d2bf96"), "concrete": Color("a49e90"),
		"yard": Color("837a66"), "wall": Color("7d7f80"), "wall2": Color("94532f")},
	3: {"ground": Color("eef3fa"), "ground2": Color("dde6f2"), "soil": Color("7b6553"), "soil2": Color("675445"),
		"rock": Color("5a5662"), "road": Color("5f6776"), "pit": Color("717988"), "apron": Color("a7afbb"),
		"kerb": Color("3f6fc0"), "kerb2": Color("f6f9ff"), "rail": Color("f2f6fc"), "concrete": Color("c3cbd6"),
		"yard": Color("9aa1ab"), "wall": Color("8d97a6"), "wall2": Color("4f6fa8")},
	4: {"ground": Color("5aa947"), "ground2": Color("4c963b"), "soil": Color("7c5637"), "soil2": Color("6a472c"),
		"rock": Color("584942"), "road": Color("3d3f48"), "pit": Color("50535c"), "apron": Color("a3a5ab"),
		"kerb": Color("e5432f"), "kerb2": Color("f5f2eb"), "rail": Color("f5f2eb"), "concrete": Color("c4c1ba"),
		"yard": Color("8a8478"), "wall": Color("9aa0a8"), "wall2": Color("c8452f")},
	5: {"ground": Color("b48252"), "ground2": Color("a77649"), "soil": Color("8c5b34"), "soil2": Color("7d4f2d"),
		"rock": Color("63402a"), "road": Color("3c4283"), "pit": Color("4d5395"), "apron": Color("cdb88e"),
		"kerb": Color("ebc46c"), "kerb2": Color("c89a52"), "rail": Color("ebc46c"), "concrete": Color("cfa874"),
		"yard": Color("a08a6a"), "wall": Color("c9a26a"), "wall2": Color("e05a3a")},
}

## Scattered scenery (picked at random) and landmarks (one each) per environment.
const SCATTER := {
	1: ["tree", "tree", "tree", "bloom", "bush", "bush", "tree"],
	2: ["heather", "heather", "rock", "dead", "heather", "rock", "bush_dry"],
	3: ["pine_s", "pine_s", "pine_s", "pine", "rock_s", "pine_s", "bush_s"],
	4: ["tree", "bush", "tree", "bush"],
	5: [],
}
const LANDMARKS := {
	1: ["barn", "windmill", "hay", "hay", "hay"],
	2: ["shed", "containers", "drums", "drums"],
	3: ["cabin", "snowman", "snowman", "cabin"],
	4: ["tent", "tent", "tyres", "tyres", "tyres", "tyres"],
	5: ["mug", "pencil:f4c234", "pencil:4a7ad8", "pencil:e8432e", "die", "die", "die", "card", "card", "card", "block", "block"],
}
## Footprint radius (cells) of a prop kind (the part before ":").
const FOOT := {"barn": 3.2, "windmill": 2.0, "hay": 1.0, "shed": 2.6, "containers": 2.4, "drums": 1.0,
	"cabin": 2.6, "snowman": 0.8, "tent": 2.0, "tyres": 0.9, "mug": 2.0, "pencil": 4.8, "die": 1.6,
	"card": 2.6, "block": 1.2}
## Landmarks shown larger than their models (the Tabletop's giant toys).
const BIG := {"pencil": 1.45, "die": 1.35, "mug": 1.35, "card": 1.3, "block": 1.3}
## Rival car colours (the grid, the Scrapyard's wrecks).
const SCRAP_COLORS := [Color("8fae8a"), Color("e6b33a"), Color("4f8fb8"), Color("3aa3a0"), Color("e9e6dc"),
	Color("9a3a5a"), Color("8a8a4a"), Color("3a3a42"), Color("d65aa0"), Color("c84a32")]
const CROWD := [Color("f2efe8"), Color("e2b23c"), Color("74bdf2"), Color("e8432e"), Color("2ec4b6"), Color("f45b9b"), Color("4a5ad8")]

## The island's surface: per-voxel brightness jitter and a bevel that also
## works on merged faces (UV2 counts cells), baked AO in COLOR.a, glossy
## (wet) cells in UV.y. Matches the voxel_model look of the props.
const TERRAIN_SHADER := """
shader_type spatial;
render_mode depth_draw_opaque, cull_back, specular_schlick_ggx;

uniform float bevel = 0.2;
varying vec3 cell;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void vertex() {
	cell = VERTEX - NORMAL * 0.5;
}

void fragment() {
	vec3 c = to_linear(COLOR.rgb);
	c *= 0.95 + 0.1 * hash(floor(cell + 0.001));
	vec2 f = fract(UV2);
	vec2 e2 = min(f, 1.0 - f);
	float edge = min(e2.x, e2.y);
	float px = length(fwidth(UV2));
	float show = 1.0 - smoothstep(0.3, 0.6, px);
	c *= 1.0 - bevel * show * (1.0 - smoothstep(0.0, 0.14, edge));
	c *= 1.0 + 0.06 * show * smoothstep(0.1, 0.18, edge) * (1.0 - smoothstep(0.22, 0.34, edge));
	ALBEDO = c;
	AO = COLOR.a;
	AO_LIGHT_AFFECT = 0.6;
	float wet = step(0.5, UV.y);
	ROUGHNESS = mix(0.86, 0.2, wet);
	SPECULAR = mix(0.3, 0.85, wet);
}
"""

var layout: TrackLayout = null
var arena: ArenaLayout = null
var variant := 1
var night := false
## How long the last show_* call took (ms) and whether its diorama was cached.
var last_build_ms := 0.0
var last_build_cached := false

var _viewport: SubViewport
var _view: TextureRect
var _camera: Camera3D
var _env: Environment
var _sun: DirectionalLight3D
var _diorama: Node3D
var _shown := ""
var _dirty := false
var _rendering := false
var _time := 0.0
var _dist := 200.0
var _target := Vector3.ZERO
var _fit_points := PackedVector3Array()

static var _rasters: Dictionary = {}
static var _dioramas: Dictionary = {}
static var _order: Array[String] = []
static var _props: Dictionary = {}
static var _terrain_material: ShaderMaterial
## Phase timings of the last cold build (ms), for the dev harness.
static var timings: Dictionary = {}


func _ready() -> void:
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(420, 300)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.size = Vector2i(64, 64)
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_env = Environment.new()
	_env.background_mode = Environment.BG_CLEAR_COLOR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.ssao_enabled = true
	_env.ssao_radius = 1.4
	_env.ssao_intensity = 1.3
	_env.glow_hdr_threshold = 0.85
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.08
	_camera = Camera3D.new()
	_camera.fov = FOV
	_camera.environment = _env
	_viewport.add_child(_camera)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.shadow_blur = 1.6
	_sun.shadow_bias = 0.04
	_viewport.add_child(_sun)
	_view = TextureRect.new()
	_view.texture = _viewport.get_texture()
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_SCALE
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_view)
	if layout != null or arena != null:
		_dirty = true


func show_circuit__perf(p_layout: TrackLayout, p_variant: int, p_night: bool) -> void:
	arena = null
	layout = p_layout
	variant = clampi(p_variant, 1, LOOKS.size())
	night = p_night
	_request()


func show_arena(p_arena: ArenaLayout, p_variant: int, p_night: bool) -> void:
	arena = p_arena
	layout = null
	variant = clampi(p_variant, 1, LOOKS.size())
	night = p_night
	_request()


func showing_arena() -> bool:
	return arena != null


func _key() -> String:
	if arena != null:
		return "arena|%d" % variant
	if layout == null:
		return ""
	return "%s|%d" % [_layout_key(layout), variant]


func _request() -> void:
	if "%s|%s" % [_key(), night] == _shown and not _dirty:
		return
	_dirty = true
	if _viewport != null and is_visible_in_tree():
		_apply()


func _process__perf(delta: float) -> void:
	if _viewport == null:
		return
	var on := is_visible_in_tree() and (layout != null or arena != null)
	if on != _rendering:
		_rendering = on
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
		if not on and _diorama != null:
			# hidden (e.g. during a race): let the nodes go, keep the cached
			# meshes; shown again, it comes back from the cache in a moment
			_viewport.remove_child(_diorama)
			_diorama.queue_free()
			_diorama = null
			_dirty = true
	if not on:
		return
	if _dirty:
		_apply()
	_sync_size()
	_time += delta
	_place_camera()


## Builds (or takes from the cache) the diorama and shows it.
func _apply() -> void:
	_dirty = false
	var key := _key()
	if key.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	var d: Dictionary = _dioramas.get(key, {})
	last_build_cached = not d.is_empty()
	if d.is_empty():
		timings.clear()
		d = _build_arena(arena, variant) if arena != null else _build_circuit(layout, variant)
		_dioramas[key] = d
		_order.append(key)
		while _order.size() > CACHE_SIZE:
			_dioramas.erase(_order.pop_front())
	else:
		_order.erase(key)
		_order.append(key)
	_instantiate(d)
	_light()
	_fit_points = d.fit
	_sync_size()
	_frame()
	_place_camera()
	_shown = "%s|%s" % [key, night]
	last_build_ms = (Time.get_ticks_usec() - t0) / 1000.0


func _instantiate(d: Dictionary) -> void:
	if _diorama != null:
		_viewport.remove_child(_diorama)
		_diorama.queue_free()
	_diorama = Node3D.new()
	var dims: Vector2 = d.size
	_diorama.position = Vector3(-dims.x * 0.5, 0.0, -dims.y * 0.5)
	var terrain := MeshInstance3D.new()
	terrain.mesh = d.terrain
	_diorama.add_child(terrain)
	# repeated props (trees, cars ...) share one MultiMesh: few instances, and
	# few of the voxel shader's per-instance slots
	var groups := {}
	for p: Array in d.parts:
		var key: Array = [p[0], p[2]]
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(p[1])
	# lamp posts (by night) and floodlight towers (always), each lit at night
	var lamp_color: Color = d.lamp_color
	for l: Array in d.lamps:
		var flood: bool = l[1]
		if not night and not flood:
			continue
		var key: Array = [VoxelProps.lamp_mesh(flood), 3 if night else 0]
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(l[0])
		if not night:
			continue
		var light := OmniLight3D.new()
		light.position = l[2]
		light.light_color = Color(0.92, 0.96, 1.0) if flood else lamp_color
		light.light_energy = 4.0 if flood else 3.2
		light.omni_range = 12.0 if flood else 8.0
		light.omni_attenuation = 1.2
		_diorama.add_child(light)
	for key: Array in groups:
		var xfs: Array = groups[key]
		var gi: GeometryInstance3D
		if xfs.size() == 1:
			var mi := MeshInstance3D.new()
			mi.mesh = key[0]
			mi.transform = xfs[0]
			gi = mi
		else:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = key[0]
			mm.instance_count = xfs.size()
			for k in xfs.size():
				mm.set_instance_transform(k, xfs[k])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			gi = mmi
		var glow: int = key[1]
		if night and glow == 1:
			gi.set_instance_shader_parameter("lamp_glow", 0.75)
		elif night and glow == 2:
			gi.set_instance_shader_parameter("head_glow", 0.8)
			gi.set_instance_shader_parameter("tail_glow", 0.7)
		elif glow == 3:
			gi.set_instance_shader_parameter("lamp_glow", 1.0)
		_diorama.add_child(gi)
	_viewport.add_child(_diorama)


func _light() -> void:
	var theme := TrackTheme.load_variant(variant)
	_sun.shadow_blur = 1.6
	_env.adjustment_saturation = 1.06
	if night:
		_env.ambient_light_color = theme.night_ambient.lerp(Color(0.2, 0.27, 0.6), 0.5)
		_env.ambient_light_energy = [0.42, 0.42, 0.46, 0.2, 0.42, 0.5][variant]
		_env.glow_enabled = true
		_env.glow_intensity = 0.9
		_env.tonemap_exposure = 1.0 if variant == 3 else 1.15
		_sun.light_color = Color(0.58, 0.68, 1.0)
		_sun.light_energy = 0.2 if variant == 3 else 0.32
		_sun.basis = Basis.looking_at(Vector3(-0.35, -0.8, -0.45).normalized())
		return
	_env.glow_enabled = false
	_env.tonemap_exposure = 1.0
	_sun.basis = Basis.looking_at(Vector3(0.5, -0.78, -0.38).normalized())
	match variant:
		2:  # overcast and wet
			_env.ambient_light_color = Color(0.66, 0.7, 0.78)
			_env.ambient_light_energy = 0.85
			_env.adjustment_saturation = 0.95
			_sun.light_color = Color(0.86, 0.88, 0.94)
			_sun.light_energy = 0.8
			_sun.shadow_blur = 3.0
		3:  # crisp winter light
			_env.ambient_light_color = Color(0.74, 0.82, 1.0)
			_env.ambient_light_energy = 0.6
			_env.tonemap_exposure = 0.94
			_sun.light_color = Color(1.0, 0.96, 0.9)
			_sun.light_energy = 1.2
		5:  # a warm room
			_env.ambient_light_color = Color(0.86, 0.8, 0.74)
			_env.ambient_light_energy = 0.6
			_sun.light_color = Color(1.0, 0.9, 0.76)
			_sun.light_energy = 1.2
		_:
			_env.ambient_light_color = Color(0.74, 0.8, 0.96)
			_env.ambient_light_energy = 0.62
			_sun.light_color = Color(1.0, 0.95, 0.86)
			_sun.light_energy = 1.3


# ------------------------------------------------------------ the camera

func _sync_size() -> void:
	var s := clampf(get_viewport().get_final_transform().get_scale().x, 1.0, 2.0)
	var want := Vector2i((size * s).round()).max(Vector2i(16, 16))
	if _viewport.size != want:
		_viewport.size = want
		_frame()


static func _cam_basis(yaw: float) -> Basis:
	var dir := Vector3(sin(yaw) * cos(PITCH), sin(PITCH), cos(yaw) * cos(PITCH))
	return Basis.looking_at(-dir, Vector3.UP)


## Distance and aim that keep the whole island in view (with a margin) at
## every angle of the sway, centred vertically.
func _frame() -> void:
	if _fit_points.is_empty():
		return
	var aspect := maxf(size.x, 1.0) / maxf(size.y, 1.0)
	var tv := tan(deg_to_rad(FOV) * 0.5)
	var th := tv * aspect
	var target := Vector3(0.0, G * 0.5, 0.0)
	var dist := 100.0
	var b0 := _cam_basis(0.0)
	for it in 3:
		var need := 0.0
		for yaw: float in [-SWAY, 0.0, SWAY]:
			var b := _cam_basis(yaw)
			for p in _fit_points:
				var rel := p - target
				var ahead := -rel.dot(b.z)
				need = maxf(need, absf(rel.dot(b.x)) / (th * FILL) - ahead)
				need = maxf(need, absf(rel.dot(b.y)) / (tv * FILL) - ahead)
		dist = need
		var lo := INF
		var hi := -INF
		for p in _fit_points:
			var rel := p - target
			var y := rel.dot(b0.y) / ((dist - rel.dot(b0.z)) * tv)
			lo = minf(lo, y)
			hi = maxf(hi, y)
		target += b0.y * ((lo + hi) * 0.5 * tv * dist)
	_dist = dist
	_target = target


func _place_camera() -> void:
	var b := _cam_basis(sin(_time * SWAY_RATE) * SWAY)
	_camera.basis = b
	_camera.position = _target + b.z * _dist
	_camera.near = maxf(_dist - 160.0, 1.0)
	_camera.far = _dist + 200.0
	_sun.directional_shadow_max_distance = _dist + 140.0


# ------------------------------------------------------------ circuits

static func _layout_key(lay: TrackLayout) -> String:
	return lay.resource_path if not lay.resource_path.is_empty() else "layout_%d" % lay.get_instance_id()


## Everything about a layout that no environment changes: the cell grid, the
## class of every cell (road, kerb, pit lane, start line ...), the bridge
## decks, the grid slots and where the pit and the start are.
static func _circuit_raster(lay: TrackLayout) -> Dictionary:
	var key := _layout_key(lay)
	if _rasters.has(key):
		return _rasters[key]
	var t0 := Time.get_ticks_usec()
	var c := lay.sample_centerline()
	var path := ClosedPath.new(c)
	var n := c.size()
	var length := path.length
	var tans := TrackLayout.tangents(c)
	var sides := lay.side_widths(c)
	var lw: PackedFloat32Array = sides[0]
	var rw: PackedFloat32Array = sides[1]
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in n:
		var reach := maxf(lw[i], rw[i]) * ROAD_SCALE
		lo = lo.min(c[i] - Vector2(reach, reach))
		hi = hi.max(c[i] + Vector2(reach, reach))
	var cell := maxf(hi.x - lo.x, hi.y - lo.y) / TRACK_CELLS
	var nx := int(ceil((hi.x - lo.x) / cell)) + MARGIN * 2
	var nz := int(ceil((hi.y - lo.y) / cell)) + MARGIN * 2
	var org := lo - Vector2(MARGIN, MARGIN) * cell
	# a little deeper than the circuit needs: room for scenery, and the
	# island fills the (wide) view better
	var deeper := maxi(int(nx * DEPTH) - nz, 0)
	nz += deeper
	org.y -= deeper / 2 * cell
	var pc := PackedVector2Array()
	var hs := PackedInt32Array()
	var gap := PackedByteArray()
	var lip := PackedByteArray()
	var corner := PackedByteArray()
	var div := PackedVector2Array()
	var pit := PackedVector3Array()
	pc.resize(n)
	hs.resize(n)
	gap.resize(n)
	lip.resize(n)
	corner.resize(n)
	div.resize(n)
	pit.resize(n)
	var flyovers: Array[Vector3] = []
	var ground_jumps: Array[Vector3] = []
	for k in lay.jumps.size():
		if lay.is_flyover(k, length):
			flyovers.append(lay.jumps[k])
		else:
			ground_jumps.append(lay.jumps[k])
	for i in n:
		pc[i] = (c[i] - org) / cell
		var s := path.cumulative[i]
		var h := 0.0
		for zr: Vector2 in lay.elevation_zones:
			if s >= zr.x and s < zr.y:
				h = smoothstep(0.0, 1.0, minf(s - zr.x, zr.y - s) / ((zr.y - zr.x) * 0.3))
		hs[i] = int(round(h * BRIDGE_H))
		for j in flyovers:
			if s > j.x and s < j.x + j.z:
				gap[i] = 1
			elif s > j.x - cell * 1.6 and s <= j.x:
				lip[i] = 1
		if absf(tans[(i - 4 + n) % n].angle_to(tans[(i + 4) % n])) > 0.3:
			corner[i] = 1
		var d := Vector2(1.0, -1.0)  # (none)
		var p3 := Vector3.ZERO
		var kb := lay.branch_at(s, length)
		if kb >= 0:
			var dd := lay.divider_at(s, length)
			if dd != Vector2.INF:
				d = dd
				var br: Dictionary = lay.branches[kb]
				if str(br.kind) == "pit":
					var through := lay.half_width_at(s, length) + float(br.divider) + float(br.lane)
					p3 = Vector3(float(br.side), through, 0.0)
		div[i] = d
		pit[i] = p3
	var spread := corner.duplicate()
	for i in n:
		if spread[i] == 1:
			for o in range(-3, 4):
				corner[(i + o + n) % n] = 1
	# ground road: every cell near the road takes its nearest centreline sample
	var best := PackedFloat32Array()
	best.resize(nx * nz)
	best.fill(1e9)
	var near := PackedInt32Array()
	near.resize(nx * nz)
	near.fill(-1)
	var i := 0
	while i < n:
		if hs[i] == 0 and gap[i] == 0:
			var p := pc[i]
			var reach := maxf(lw[i], rw[i]) * ROAD_SCALE / cell + 1.0 + CLEAR
			var r2 := reach * reach
			var x0 := maxi(int(p.x - reach), 0)
			var x1 := mini(int(p.x + reach), nx - 1)
			var z0 := maxi(int(p.y - reach), 0)
			var z1 := mini(int(p.y + reach), nz - 1)
			for z in range(z0, z1 + 1):
				var dz := z + 0.5 - p.y
				var dz2 := dz * dz
				var row := z * nx
				for x in range(x0, x1 + 1):
					var dx := x + 0.5 - p.x
					var d2 := dx * dx + dz2
					if d2 < r2 and d2 < best[row + x]:
						best[row + x] = d2
						near[row + x] = i
		i += 2
	var cls := PackedByteArray()
	cls.resize(nx * nz)
	var kerb_w := cell * 0.95 / ROAD_SCALE
	for k in nx * nz:
		var si := near[k]
		if si < 0:
			continue
		var t := tans[si]
		var dx := (k % nx) + 0.5 - pc[si].x
		var dz := (k / nx) + 0.5 - pc[si].y
		var lat := (dz * t.x - dx * t.y) * cell / ROAD_SCALE
		var s := fposmod(path.cumulative[si] + (dx * t.x + dz * t.y) * cell, length)
		var lo_i := -lw[si]
		var hi_i := rw[si]
		var cl := VERGE
		if lat >= lo_i and lat <= hi_i:
			cl = ROAD
			var d := div[si]
			if d.x <= d.y:
				var pad := maxf(0.0, (cell * 0.95 / ROAD_SCALE - (d.y - d.x)) * 0.5)
				var p3 := pit[si]
				if lat >= d.x - pad and lat <= d.y + pad:
					cl = DIVIDER
				elif p3.x > 0.0 and lat > d.y:
					cl = PIT if lat <= p3.y else APRON
				elif p3.x < 0.0 and lat < d.x:
					cl = PIT if lat >= -p3.y else APRON
			var sw := wrapf(s, -length * 0.5, length * 0.5)
			if absf(sw) < cell * 0.9 and cl == ROAD:
				var a := int(floor(sw / cell + 1.0)) + int(floor((lat - lo_i) * ROAD_SCALE / cell))
				cl = CHECK_A if a % 2 == 0 else CHECK_B
			for j in ground_jumps:
				if s > j.x and s < j.x + j.z:
					cl = HOLE
				elif s > j.x - j.y and s <= j.x:
					cl = RAMP
		elif corner[si] == 1 and ((lat < lo_i and lat >= lo_i - kerb_w) or (lat > hi_i and lat <= hi_i + kerb_w)):
			cl = KERB_A if int(floor(s / (cell * 1.5))) % 2 == 0 else KERB_B
		cls[k] = cl
	# bridges: contiguous runs of lifted samples (and a flyover's gap)
	var runs: Array[PackedInt32Array] = []
	var cur := PackedInt32Array()
	for k in n:
		if hs[k] >= 1 or gap[k] == 1:
			cur.append(k)
		elif not cur.is_empty():
			runs.append(cur)
			cur = PackedInt32Array()
	if not cur.is_empty():
		if not runs.is_empty() and runs[0][0] == 0:
			cur.append_array(runs[0])
			runs[0] = cur
		else:
			runs.append(cur)
	var decks: Array = []
	for run in runs:
		decks.append(_deck_plan(run, pc, tans, lw, rw, hs, gap, lip, cell, nx, nz, cls))
	# the grid's first slots (cells, yaw) and the pit's garage spot
	var grid := PackedVector3Array()
	for slot in 6:
		var gs := lay.grid_slot(slot)
		var behind: float = gs.behind
		var lateral: float = gs.lateral
		var t := path.tangent_at(-behind)
		var p := (path.point_at(-behind) + Vector2(-t.y, t.x) * lateral * ROAD_SCALE - org) / cell
		grid.append(Vector3(p.x, p.y, atan2(-t.y, t.x)))
	var garage := {}
	var pb := lay.pit_branch()
	if pb >= 0:
		var b: Dictionary = lay.branches[pb]
		var at: float = b.box
		var t := path.tangent_at(at)
		var side := float(b.side)
		var out := (lay.half_width_at(at, length) + float(b.divider) + float(b.lane) + float(b.get("bay_depth", 0.0))) * ROAD_SCALE / cell
		var p := (path.point_at(at) - org) / cell + Vector2(-t.y, t.x) * side * (out + 2.4)
		var long := (float(b.to) - float(b.from) - 2.0 * float(b.ramp)) * ROAD_SCALE / cell
		garage = {"at": p, "dir": -Vector2(-t.y, t.x) * side, "length": clampf(long, 6.0, 18.0), "side": side}
	var r := {"nx": nx, "nz": nz, "cell": cell, "org": org, "cls": cls, "pc": pc, "tans": tans, "lw": lw,
		"rw": rw, "hs": hs, "gap": gap, "corner": corner, "decks": decks, "grid": grid, "garage": garage, "n": n}
	_rasters[key] = r
	timings["raster"] = (Time.get_ticks_usec() - t0) / 1000.0
	return r


## A bridge run's deck as cells: [x, z, kind, height] (kind 0 road, 1 lip,
## 2 rail) and pillars [x, z, height]; marks the ground beneath it.
static func _deck_plan(run: PackedInt32Array, pc: PackedVector2Array, tans: PackedVector2Array, lw: PackedFloat32Array,
		rw: PackedFloat32Array, hs: PackedInt32Array, gap: PackedByteArray, lip: PackedByteArray, cell: float,
		nx: int, nz: int, cls: PackedByteArray) -> Dictionary:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var reach_max := 0.0
	for i: int in run:
		var reach := maxf(lw[i], rw[i]) * ROAD_SCALE / cell + 1.4
		reach_max = maxf(reach_max, reach)
		lo = lo.min(pc[i] - Vector2(reach, reach))
		hi = hi.max(pc[i] + Vector2(reach, reach))
	var x0 := maxi(int(floor(lo.x)), 0)
	var z0 := maxi(int(floor(lo.y)), 0)
	var bx := mini(int(ceil(hi.x)), nx - 1) - x0 + 1
	var bz := mini(int(ceil(hi.y)), nz - 1) - z0 + 1
	var best := PackedFloat32Array()
	best.resize(bx * bz)
	best.fill(1e9)
	var near := PackedInt32Array()
	near.resize(bx * bz)
	near.fill(-1)
	for idx in run.size():
		var p := pc[run[idx]] - Vector2(x0, z0)
		var r2 := reach_max * reach_max
		for z in range(maxi(int(p.y - reach_max), 0), mini(int(p.y + reach_max), bz - 1) + 1):
			var dz := z + 0.5 - p.y
			for x in range(maxi(int(p.x - reach_max), 0), mini(int(p.x + reach_max), bx - 1) + 1):
				var dx := x + 0.5 - p.x
				var d2 := dx * dx + dz * dz
				if d2 < r2 and d2 < best[z * bx + x]:
					best[z * bx + x] = d2
					near[z * bx + x] = idx
	var cells := PackedInt32Array()
	var rail_w := cell * 0.95 / ROAD_SCALE
	var last := run.size() - 1
	for k in bx * bz:
		var idx := near[k]
		if idx < 0:
			continue
		var i := run[idx]
		var t := tans[i]
		var dx := (k % bx) + 0.5 - (pc[i].x - x0)
		var dz := (k / bx) + 0.5 - (pc[i].y - z0)
		var along := dx * t.x + dz * t.y
		if (idx == 0 and along < -0.4) or (idx == last and along > 0.4):
			continue
		var lat := (dz * t.x - dx * t.y) * cell / ROAD_SCALE
		var wx := x0 + k % bx
		var wz := z0 + k / bx
		var g := wz * nx + wx
		if absf(lat) <= maxf(lw[i], rw[i]) + rail_w and (cls[g] == FREE or cls[g] == VERGE):
			cls[g] = UNDER
		if gap[i] == 1:
			continue
		var kind := -1
		if lat >= -lw[i] and lat <= rw[i]:
			kind = 1 if lip[i] == 1 else 0
		elif (lat < -lw[i] and lat >= -lw[i] - rail_w) or (lat > rw[i] and lat <= rw[i] + rail_w):
			kind = 2
		if kind >= 0:
			cells.append_array([wx, wz, kind, maxi(hs[i], 1)])
	var pillars := PackedInt32Array()
	for idx in range(2, run.size() - 2, 4):
		var i := run[idx]
		if hs[i] < 3 or gap[i] == 1:
			continue
		var t := tans[i]
		var rn := Vector2(-t.y, t.x)
		for side in [-1.0, 1.0]:
			var off: float = (rw[i] if side > 0.0 else lw[i]) * ROAD_SCALE / cell + 0.3
			var p: Vector2 = pc[i] + rn * side * off
			var px := int(floor(p.x))
			var pz := int(floor(p.y))
			if px < 0 or pz < 0 or px >= nx or pz >= nz:
				continue
			var cl := cls[pz * nx + px]
			if cl == FREE or cl == VERGE or cl == UNDER:
				pillars.append_array([px, pz, hs[i]])
	return {"x0": x0, "z0": z0, "bx": bx, "bz": bz, "cells": cells, "pillars": pillars}


static func _deck_mesh(plan: Dictionary, look: Dictionary) -> ArrayMesh:
	var x0: int = plan.x0
	var z0: int = plan.z0
	var bx: int = plan.bx
	var bz: int = plan.bz
	var g := VoxelGrid.new(Vector3i(bx, BRIDGE_H + 2, bz), 1.0, Vector3(x0, G, z0))
	var road: Color = look.road
	var concrete: Color = look.concrete
	var rail: Color = look.rail
	var cells: PackedInt32Array = plan.cells
	for q in range(0, cells.size(), 4):
		var x := cells[q] - x0
		var z := cells[q + 1] - z0
		var kind := cells[q + 2]
		var h := cells[q + 3]
		if kind == 2:
			var low := 0 if h <= 2 else h - 2
			for y in range(low, h):
				g.set_v(x, y, z, Vox.SOLID, concrete)
			if h >= 2:
				g.set_v(x, h, z, Vox.SOLID, rail if (x + z) % 4 < 2 or rail == concrete else rail.darkened(0.12))
			continue
		var top := road
		if kind == 1:
			top = Color("f2c23a") if (x + z) % 2 == 0 else Color("2a2a30")
		if h <= 2:
			for y in h - 1:
				g.set_v(x, y, z, Vox.SOLID, concrete)
		else:
			g.set_v(x, h - 2, z, Vox.SOLID, concrete.darkened(0.08))
		g.set_v(x, h - 1, z, Vox.SOLID, top)
	var pillars: PackedInt32Array = plan.pillars
	for q in range(0, pillars.size(), 3):
		for y in pillars[q + 2] - 2:
			g.set_v(pillars[q] - x0, y, pillars[q + 1] - z0, Vox.SOLID, concrete.darkened(0.14 if y % 2 == 0 else 0.08))
	return VoxelMesher.build_mesh(g, VoxelCars.material(), Vector3.ZERO, 0.05)


static func _build_circuit(lay: TrackLayout, v: int) -> Dictionary:
	var r := _circuit_raster(lay)
	var t0 := Time.get_ticks_usec()
	var look: Dictionary = LOOKS[v]
	var nx: int = r.nx
	var nz: int = r.nz
	var cls: PackedByteArray = (r.cls as PackedByteArray).duplicate()
	var col := _columns(nx, nz, cls, v, look)
	var t1 := Time.get_ticks_usec()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_layout_key(lay)) + v * 7919
	var parts: Array = []
	var lamps: Array = []
	for plan: Dictionary in r.decks:
		parts.append([_deck_mesh(plan, look), Transform3D.IDENTITY, 0])
	_start_props(r, v, cls, parts)
	if v == 4:
		_raceway_props(r, cls, parts, lamps)
	else:
		_track_lamps(r, cls, lamps, clampi(TrackTheme.load_variant(v).lamp_count, 8, 12))
	_landmarks(LANDMARKS[v], nx, nz, cls, parts, rng)
	if v == 1 or v == 3 or v == 4:
		_pond(col, cls, nx, nz, v, rng)
	_scatter(SCATTER[v], nx, nz, cls, parts, rng)
	var t2 := Time.get_ticks_usec()
	var terrain := _mesh_terrain(col)
	var t3 := Time.get_ticks_usec()
	timings["columns"] = (t1 - t0) / 1000.0
	timings["props"] = (t2 - t1) / 1000.0
	timings["mesh"] = (t3 - t2) / 1000.0
	return {"terrain": terrain, "parts": parts, "lamps": lamps, "size": Vector2(nx, nz),
		"fit": _fit_for(nx, nz, v == 5, parts, lamps), "lamp_color": TrackTheme.load_variant(v).lamp_color}


static func _xf(p: Vector2, yaw: float, s: float, y: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), Vector3(p.x, y, p.y))


## Is every cell of a w x d rectangle (cells; centre c, long axis along `along`)
## one of the allowed classes? Marks it TAKEN when it is.
static func _claim(cls: PackedByteArray, nx: int, nz: int, c: Vector2, along: Vector2, w: float, d: float, allow_verge: bool) -> bool:
	var across := Vector2(-along.y, along.x)
	var cells := PackedInt32Array()
	var a := -w * 0.5
	while a <= w * 0.5 + 0.01:
		var b := -d * 0.5
		while b <= d * 0.5 + 0.01:
			var p := c + along * a + across * b
			var x := int(floor(p.x))
			var z := int(floor(p.y))
			if x < 0 or z < 0 or x >= nx or z >= nz:
				return false
			var cl := cls[z * nx + x]
			if not (cl == FREE or (allow_verge and cl == VERGE)):
				return false
			cells.append(z * nx + x)
			b += 0.7
		a += 0.7
	for k in cells:
		cls[k] = TAKEN
	return true


## The start: a gantry over the line, cars on the grid and a grandstand.
static func _start_props(r: Dictionary, v: int, cls: PackedByteArray, parts: Array) -> void:
	var nx: int = r.nx
	var nz: int = r.nz
	var cell: float = r.cell
	var pc: PackedVector2Array = r.pc
	var tans: PackedVector2Array = r.tans
	var lw: PackedFloat32Array = r.lw
	var rw: PackedFloat32Array = r.rw
	var t0 := tans[0]
	var r0 := Vector2(-t0.y, t0.x)
	var width := (lw[0] + rw[0]) * ROAD_SCALE / cell + 1.6
	var centre := pc[0] + r0 * ((rw[0] - lw[0]) * 0.5 * ROAD_SCALE / cell)
	parts.append([_prop("gantry:%d" % int(round(width / PV))), _xf(centre, atan2(-r0.y, r0.x), 1.0, G), 1])
	var grid: PackedVector3Array = r.grid
	for k in grid.size():
		var g := grid[k]
		var colour: Color = SCRAP_COLORS[(k * 3 + v) % SCRAP_COLORS.size()]
		parts.append([_prop("car:" + colour.to_html(false)), _xf(Vector2(g.x, g.y), g.z, 1.0, G), 2])
	if v == 5 or v == 4:
		return
	# one grandstand beside the start straight, away from the pit
	var garage: Dictionary = r.garage
	var first := -1.0 if garage.is_empty() else -float(garage.side)
	for side in [first, -first]:
		var edge: float = (rw[0] if side > 0.0 else lw[0]) * ROAD_SCALE / cell
		var at: Vector2 = pc[0] - t0 * 3.0 + r0 * side * (edge + 3.2)
		if _claim(cls, nx, nz, at, t0, 10.0, 3.6, true):
			var d: Vector2 = -r0 * side
			parts.append([_prop("stand:20:%d" % v), _xf(at, atan2(d.x, d.y), 1.0, G), 1])
			return


## The Raceway: grandstands along the main straight, the pit garages, boards
## and floodlight towers (standing by day, lit at night).
static func _raceway_props(r: Dictionary, cls: PackedByteArray, parts: Array, lamps: Array) -> void:
	var nx: int = r.nx
	var nz: int = r.nz
	var n: int = r.n
	var cell: float = r.cell
	var pc: PackedVector2Array = r.pc
	var tans: PackedVector2Array = r.tans
	var lw: PackedFloat32Array = r.lw
	var rw: PackedFloat32Array = r.rw
	var hs: PackedInt32Array = r.hs
	var corner: PackedByteArray = r.corner
	var garage: Dictionary = r.garage
	if not garage.is_empty():
		var along := Vector2(-(garage.dir as Vector2).y, (garage.dir as Vector2).x)
		var length: float = garage.length
		var at: Vector2 = garage.at
		if _claim(cls, nx, nz, at, along, length, 3.2, true):
			var d: Vector2 = garage.dir
			parts.append([_prop("garages:%d" % int(round(length / PV))), _xf(at, atan2(d.x, d.y), 1.0, G), 1])
	var t0 := tans[0]
	var r0 := Vector2(-t0.y, t0.x)
	var stand_side := -1.0 if garage.is_empty() else -float(garage.side)
	for off in [-12.0, 0.0, 12.0, -24.0]:
		for side in [stand_side, -stand_side]:
			var edge: float = (rw[0] if side > 0.0 else lw[0]) * ROAD_SCALE / cell
			var at: Vector2 = pc[0] + t0 * off + r0 * side * (edge + 3.4)
			if _claim(cls, nx, nz, at, t0, 11.0, 4.0, true):
				var d: Vector2 = -r0 * side
				parts.append([_prop("stand:22:4"), _xf(at, atan2(d.x, d.y), 1.0, G), 1])
				break
	# advertising boards on the straights, floodlights round the lap
	var boards := 0
	var step := maxi(n / 14, 1)
	for k in range(step, n, step):
		if boards >= 7 or corner[k] == 1 or hs[k] > 0:
			continue
		var t := tans[k]
		var rn := Vector2(-t.y, t.x)
		var side := 1.0 if k % 2 == 0 else -1.0
		var edge: float = (rw[k] if side > 0.0 else lw[k]) * ROAD_SCALE / cell
		var at: Vector2 = pc[k] + rn * side * (edge + 1.6)
		if _claim(cls, nx, nz, at, t, 4.0, 1.0, true):
			var d: Vector2 = -rn * side
			parts.append([_prop("adboard"), _xf(at, atan2(d.x, d.y), 1.0, G), 0])
			boards += 1
	var floods := 0
	var fstep := maxi(n / 7, 1)
	for k in range(fstep / 2, n, fstep):
		if floods >= 7:
			break
		for side in [1.0, -1.0]:
			var kk := (k + int(side) * 2 + n) % n
			if hs[kk] > 0:
				continue
			var t := tans[kk]
			var rn := Vector2(-t.y, t.x)
			var edge: float = (rw[kk] if side > 0.0 else lw[kk]) * ROAD_SCALE / cell
			var at: Vector2 = pc[kk] + rn * side * (edge + 2.6)
			if _claim(cls, nx, nz, at, t, 1.4, 1.4, true):
				_add_lamp(lamps, at, -rn * side, true)
				floods += 1
				break


## Night lamps along the circuit (the arm reaches over the road).
static func _track_lamps(r: Dictionary, cls: PackedByteArray, lamps: Array, count: int) -> void:
	var nx: int = r.nx
	var nz: int = r.nz
	var n: int = r.n
	var cell: float = r.cell
	var pc: PackedVector2Array = r.pc
	var tans: PackedVector2Array = r.tans
	var lw: PackedFloat32Array = r.lw
	var rw: PackedFloat32Array = r.rw
	var hs: PackedInt32Array = r.hs
	var step := maxi(n / count, 1)
	for k in range(step / 3, n, step):
		for side in [1.0 if k % 2 == 0 else -1.0, -1.0 if k % 2 == 0 else 1.0]:
			if hs[k] > 0:
				break
			var t := tans[k]
			var rn := Vector2(-t.y, t.x)
			var edge: float = (rw[k] if side > 0.0 else lw[k]) * ROAD_SCALE / cell
			var at: Vector2 = pc[k] + rn * side * (edge + 1.3)
			if _claim(cls, nx, nz, at, t, 0.8, 0.8, true):
				_add_lamp(lamps, at, -rn * side, false)
				break


## A lamp post (or floodlight tower) at `at` (cells) with its head towards `towards`.
static func _add_lamp(lamps: Array, at: Vector2, towards: Vector2, flood: bool) -> void:
	var s := 0.85 if flood else 0.68
	var yaw := atan2(-towards.y, towards.x)
	var head := VoxelProps.lamp_head(flood) * Vox.PX * s
	var xf := _xf(at, yaw, s, G)
	lamps.append([xf, flood, xf.origin + Basis(Vector3.UP, yaw) * Vector3(head.x, head.y, 0.0)])


static func _landmarks(kinds: Array, nx: int, nz: int, cls: PackedByteArray, parts: Array, rng: RandomNumberGenerator) -> void:
	for kind: String in kinds:
		var base := kind.get_slice(":", 0)
		var foot: float = FOOT.get(base, 1.5) * BIG.get(base, 1.0)
		var long := base == "pencil"
		for attempt in 120:
			var at := Vector2(rng.randf_range(2.0, nx - 2.0), rng.randf_range(2.0, nz - 2.0))
			var yaw := rng.randf_range(-0.6, 0.6) if not long and base != "die" and base != "card" else rng.randf() * TAU
			var along := Vector2(cos(yaw), -sin(yaw))
			var w := foot * 2.0
			var d := 1.6 if long else foot * 2.0
			if _claim(cls, nx, nz, at, along, w, d, false):
				var glow := 1 if base in ["barn", "cabin", "shed", "tent"] else 0
				parts.append([_prop(kind), _xf(at, yaw, BIG.get(base, 1.0), G), glow])
				break


## Clumps of trees (bushes, rocks ...) in the free ground.
static func _scatter(kinds: Array, nx: int, nz: int, cls: PackedByteArray, parts: Array, rng: RandomNumberGenerator) -> void:
	if kinds.is_empty():
		return
	var free := 0
	for k in range(0, nx * nz, 3):
		if cls[k] == FREE:
			free += 3
	var want := clampi(free / 70, 10, 70)
	var placed := 0
	var tries := 0
	while placed < want and tries < want * 6:
		tries += 1
		var c := Vector2(rng.randf_range(2.0, nx - 2.0), rng.randf_range(2.0, nz - 2.0))
		var x := int(c.x)
		var z := int(c.y)
		if cls[z * nx + x] != FREE:
			continue
		for m in rng.randi_range(2, 6):
			var at := c + Vector2(rng.randfn(0.0, 2.4), rng.randfn(0.0, 2.4))
			var kind: String = kinds[rng.randi() % kinds.size()]
			if _claim(cls, nx, nz, at, Vector2.RIGHT, 1.2, 1.2, false):
				var s := rng.randf_range(0.8, 1.15)
				parts.append([_prop(kind), _xf(at, rng.randf() * TAU, s, G), 0])
				placed += 1


## Points the camera must keep in view: the island's outline (top and
## underside) and the top of every tall thing on it (island-centred).
static func _fit_for(nx: int, nz: int, desk: bool, parts: Array, lamps: Array) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var hx := nx * 0.5
	var hz := nz * 0.5
	for k in 32:
		var a := TAU * k / 32.0
		var cx := cos(a)
		var sz := sin(a)
		var rr := 0.0
		if desk:
			rr = minf(hx / maxf(absf(cx), 0.0001), hz / maxf(absf(sz), 0.0001))
		else:
			rr = pow(pow(absf(cx) / hx, 6.0) + pow(absf(sz) / hz, 6.0), -1.0 / 6.0)
		var p := Vector3(cx * rr, 0.0, sz * rr)
		pts.append(p + Vector3(0.0, G + 0.5, 0.0))
		if desk:
			pts.append(p * 0.94)
		else:
			pts.append(p * 0.9 + Vector3(0.0, 0.5, 0.0))
	var centre := Vector3(hx, 0.0, hz)
	for p: Array in parts:
		var m: Mesh = p[0]
		var xf: Transform3D = p[1]
		var bb := xf * m.get_aabb()
		pts.append(bb.get_center() + Vector3(0.0, bb.size.y * 0.5, 0.0) - centre)
	for l: Array in lamps:
		var xf: Transform3D = l[0]
		pts.append(xf.origin + Vector3(0.0, 6.0, 0.0) - centre)
	return pts


# ------------------------------------------------------------ the island

## The bare ground of every cell (meadow with flower patches, wet moor with
## heather and puddles, snow, mown stripes, desk planks) and its glossy flag.
static func _ground(v: int, nx: int, nz: int, look: Dictionary) -> Array:
	var g1: Color = look.ground
	var g2: Color = look.ground2
	var out := PackedColorArray()
	out.resize(nx * nz)
	var wet := PackedByteArray()
	wet.resize(nx * nz)
	var noise := _noise(nx, nz, 6, 31 + v) if v <= 3 else PackedFloat32Array()
	var flowers := [Color("f7b731"), Color("f45b9b"), Color("fff4de"), Color("ff8c2e")]
	var heather := Color("6a4664")
	var mud := Color("655b3d")
	var puddle := Color("566070")
	var k := 0
	for z in nz:
		for x in nx:
			var h := fposmod(sin(x * 12.9898 + z * 78.233) * 43758.5453, 1.0)
			var c := g1
			match v:
				1:
					var n := noise[k]
					c = g2 if n > 0.6 else g1
					if (n < 0.3 and h > 0.88) or h > 0.995:
						c = flowers[int(h * 1000.0) % 4]
				2:
					var n := noise[k]
					c = g2 if n > 0.55 else g1
					if n > 0.76 and h > 0.7:
						c = heather
					elif n < 0.1:
						c = puddle
						wet[k] = 1
					elif n < 0.17:
						c = mud
				3:
					c = g2 if noise[k] > 0.62 else g1
				4:
					c = g2 if int(floor((x + z * 0.35) / 4.0)) % 2 == 0 else g1
				5:
					c = g1.lerp(g2, Vox.hash3(0, 5, z / 3))
					if h > 0.988:
						c = c.darkened(0.14)
			out[k] = c
			k += 1
	return [out, wet]


## Smooth value noise (0..1) over the cells, one lattice point every `step` cells.
static func _noise(nx: int, nz: int, step: int, seed: int) -> PackedFloat32Array:
	var lx := nx / step + 2
	var lz := nz / step + 2
	var lat := PackedFloat32Array()
	lat.resize(lx * lz)
	for j in lz:
		for i in lx:
			lat[j * lx + i] = Vox.hash3(i, seed, j)
	var out := PackedFloat32Array()
	out.resize(nx * nz)
	var inv := 1.0 / step
	var k := 0
	for z in nz:
		var fz := z * inv
		var jz := int(fz)
		var tz := fz - jz
		tz = tz * tz * (3.0 - 2.0 * tz)
		var r0 := jz * lx
		var r1 := r0 + lx
		for x in nx:
			var fx := x * inv
			var ix := int(fx)
			var tx := fx - ix
			tx = tx * tx * (3.0 - 2.0 * tx)
			var a := lerpf(lat[r0 + ix], lat[r0 + ix + 1], tx)
			out[k] = lerpf(a, lerpf(lat[r1 + ix], lat[r1 + ix + 1], tx), tz)
			k += 1
	return out


## A pond (frozen on the snow) in a free patch of ground, painted straight
## into the island's columns: water one step down, a ring of stones round it.
static func _pond(col: Dictionary, cls: PackedByteArray, nx: int, nz: int, v: int, rng: RandomNumberGenerator) -> void:
	var w: int = col.w
	var top: PackedInt32Array = col.top
	var tc: PackedColorArray = col.tc
	var sc: PackedColorArray = col.sc
	var gl: PackedByteArray = col.gl
	var ice := v == 3
	for attempt in 60:
		var r := rng.randf_range(3.4, 4.8)
		var c := Vector2(rng.randf_range(r + 3.0, nx - r - 3.0), rng.randf_range(r + 3.0, nz - r - 3.0))
		if not _claim(cls, nx, nz, c, Vector2.RIGHT, (r + 1.0) * 2.6, (r + 1.0) * 1.7, false):
			continue
		for z in range(int(c.y - r) - 2, int(c.y + r) + 3):
			for x in range(int(c.x - r * 1.3) - 2, int(c.x + r * 1.3) + 3):
				var d := Vector2((x + 0.5 - c.x) / 1.3, (z + 0.5 - c.y) / 0.85).length() + Vox.hash3(x, 9, z) * 0.7
				var kk := (z + 1) * w + x + 1
				if d < r:
					var deep := d < r - 1.5
					var water := Color("3f86c8").darkened(0.12) if deep else Color("4f9ad4")
					if ice:
						water = Color("c6e2f2") if deep else Color("d8ecf8")
					top[kk] = G if ice else G - 1
					tc[kk] = water
					sc[kk] = water
					gl[kk] = 1
				elif d < r + 0.9 and not ice:
					tc[kk] = Color("a39e92") if Vox.hash3(x, 4, z) > 0.55 else Color("d6c79a")
					sc[kk] = tc[kk]
		return


## The island as columns: top / bottom height, top colour, side colour above
## the ground, glossy flag (padded by one empty cell all round). Cells off the
## island or on its rim are marked TAKEN (no scenery there).
static func _columns(nx: int, nz: int, cls: PackedByteArray, v: int, look: Dictionary) -> Dictionary:
	var w := nx + 2
	var hgt := nz + 2
	var top := PackedInt32Array()
	top.resize(w * hgt)
	var bot := PackedInt32Array()
	bot.resize(w * hgt)
	var tc := PackedColorArray()
	tc.resize(w * hgt)
	var sc := PackedColorArray()
	sc.resize(w * hgt)
	var gl := PackedByteArray()
	gl.resize(w * hgt)
	var gr := _ground(v, nx, nz, look)
	var gnd: PackedColorArray = gr[0]
	var gwet: PackedByteArray = gr[1]
	var road: Color = look.road
	var pit_c: Color = look.pit
	var apron: Color = look.apron
	var kerb: Color = look.kerb
	var kerb2: Color = look.kerb2
	var rail: Color = look.rail
	var yard: Color = look.yard
	var wall: Color = look.wall
	var wall2: Color = look.wall2
	var wet := 1 if v == 2 else 0
	var desk := v == 5
	var hx := nx * 0.5
	var hz := nz * 0.5
	var hmin := minf(hx, hz)
	for z in nz:
		var qz := absf(z + 0.5 - hz) / hz
		var qz6 := qz * qz * qz * qz * qz * qz
		var ez := mini(z, nz - 1 - z)
		for x in nx:
			var k := z * nx + x
			var kk := k + w + 1 + 2 * z
			var c := cls[k]
			var b := 0
			if desk:
				var ex := mini(x, nx - 1 - x)
				b = 0 if (ex >= 2 and ex <= 4 and ez >= 2 and ez <= 4) else G - 2
				if (ex < 2 or ez < 2) and c == FREE:
					cls[k] = TAKEN
			else:
				var qx := absf(x + 0.5 - hx) / hx
				var e := qx * qx * qx * qx * qx * qx + qz6
				if e > 0.4:
					if e > 0.88 + 0.1 * Vox.hash3(x / 3, 0, z / 3) and (c == FREE or c == VERGE):
						cls[k] = TAKEN
						continue
					var de := (1.0 - pow(e, 1.0 / 6.0)) * hmin
					b = clampi(TAPER - int(de / 1.4 + Vox.hash3(x, 3, z) * 0.6), 0, TAPER)
					if de < 2.0 and c == FREE:
						cls[k] = TAKEN
			bot[kk] = b
			if c == FREE or c == VERGE or c == UNDER or c == TAKEN:
				var t0 := gnd[k]
				top[kk] = G
				tc[kk] = t0
				sc[kk] = t0
				gl[kk] = gwet[k]
				continue
			var t := Color()
			var s := Color()
			var up := 0
			var shine := 0
			match c:
				ROAD:
					t = road
					shine = wet
				PIT:
					t = pit_c
					shine = wet
				APRON:
					t = apron
				KERB_A:
					t = kerb
				KERB_B:
					t = kerb2
				CHECK_A:
					t = Color("f4f2ee")
				CHECK_B:
					t = Color("26262c")
				DIVIDER:
					t = rail
					s = rail.darkened(0.1)
					up = 1
				HOLE:
					t = Color("2a2420")
					up = -2
				RAMP:
					t = Color("f2c23a") if (x + z) % 2 == 0 else road.lightened(0.15)
					s = road
					up = 1
				YARD:
					var h := Vox.hash3(x, 7, z)
					t = yard.darkened(0.25) if h > 0.94 else (yard if (x / 5 + z / 5) % 2 == 0 else yard.darkened(0.05))
				WALL_A, WALL_B:
					t = wall if c == WALL_A else wall2
					s = t
					up = 2
				PILE:
					t = Color("6a5644")
					s = t
					up = 1
				PILE_TOP:
					t = Color("5a493a")
					s = t
					up = 2
				BLOCK_A, BLOCK_B:
					t = Color("f2c23a") if c == BLOCK_A else Color("2e2a28")
					s = Color("a9a49a")
					up = 2
				BAR_A, BAR_B:
					t = Color("e5432f") if c == BAR_A else Color("f3eee5")
					s = t
					up = 1
			if up == 0:
				s = t
			top[kk] = G + up
			tc[kk] = t
			sc[kk] = s
			gl[kk] = shine
	var layers := PackedColorArray()
	var soil: Color = look.soil
	var rock: Color = look.rock
	for y in G:
		if desk:
			layers.append(rock if y < G - 2 else soil)
		else:
			layers.append(soil if y >= G - 3 else rock)
	return {"w": w, "h": hgt, "top": top, "bot": bot, "tc": tc, "sc": sc, "gl": gl, "layers": layers}


## Meshes the island's columns: merged top faces where nothing shades them,
## single faces with baked AO next to anything raised, and side faces where
## a column stands higher (or reaches lower) than its neighbour.
class TerrainMesher:
	var w := 0
	var top: PackedInt32Array
	var bot: PackedInt32Array
	var tc: PackedColorArray
	var sc: PackedColorArray
	var gl: PackedByteArray
	var layers: PackedColorArray
	var ground := 6
	var ao: PackedFloat32Array
	var vs := PackedVector3Array()
	var ns := PackedVector3Array()
	var cs := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var ix := PackedInt32Array()

	func solid(k: int, y: int) -> int:
		return 1 if y >= bot[k] and y < top[k] else 0

	func quad(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n: Vector3, c: Color, a0: int, a1: int, a2: int, a3: int, ext: Vector2, gloss: float) -> void:
		var base := vs.size()
		vs.append(p0)
		vs.append(p1)
		vs.append(p2)
		vs.append(p3)
		ns.append(n)
		ns.append(n)
		ns.append(n)
		ns.append(n)
		cs.append(Color(c.r, c.g, c.b, ao[a0]))
		cs.append(Color(c.r, c.g, c.b, ao[a1]))
		cs.append(Color(c.r, c.g, c.b, ao[a2]))
		cs.append(Color(c.r, c.g, c.b, ao[a3]))
		var g := Vector2(0.0, gloss)
		uv.append(g)
		uv.append(g)
		uv.append(g)
		uv.append(g)
		uv2.append(Vector2.ZERO)
		uv2.append(Vector2(ext.x, 0.0))
		uv2.append(ext)
		uv2.append(Vector2(0.0, ext.y))
		ix.append(base)
		if a0 + a2 >= a1 + a3:
			ix.append(base + 2)
			ix.append(base + 1)
			ix.append(base)
		else:
			ix.append(base + 3)
			ix.append(base + 1)
			ix.append(base + 1)
		ix.append(base + 3)
		ix.append(base + 2)

	static func corner_ao(s1: int, s2: int, c: int) -> int:
		return 0 if s1 == 1 and s2 == 1 else 3 - (s1 + s2 + c)

	## The side of column k (padded index; cell x, z) facing d (0 +X, 1 -X,
	## 2 +Z) from y0 to y1, split where the colour changes: rock, soil, turf
	## (the top colour), then whatever stands above the ground.
	func side_run(x: int, y0: int, y1: int, z: int, k: int, d: int) -> void:
		var y := y0
		while y < y1:
			var e := y1
			var c := sc[k]
			if y < ground - 3:
				e = mini(ground - 3, y1)
				c = layers[y]
			elif y < ground - 1:
				e = mini(ground - 1, y1)
				c = layers[y]
			elif y == ground - 1:
				e = y + 1
				c = tc[k]
			side(x, y, e, z, k, d, c)
			y = e

	## One side quad of voxels y0 .. y1 - 1, with AO from the cells around the
	## air in front of it (bottom corners from the lowest voxel, top corners
	## from the highest).
	func side(x: int, y0: int, y1: int, z: int, k: int, d: int, col: Color) -> void:
		var ka := k + 1
		var hd := w
		var sh := 0.9
		var n := Vector3.RIGHT
		if d == 1:
			ka = k - 1
			n = Vector3.LEFT
		elif d == 2:
			ka = k + w
			hd = 1
			n = Vector3.BACK
			sh = 0.86
		var c := Color(col.r * sh, col.g * sh, col.b * sh)
		var yt := y1 - 1
		var hm_b := solid(ka - hd, y0)
		var hp_b := solid(ka + hd, y0)
		var hm_t := solid(ka - hd, yt)
		var hp_t := solid(ka + hd, yt)
		var vm := solid(ka, y0 - 1)
		var vp := solid(ka, y1)
		var mm := solid(ka - hd, y0 - 1)
		var pm := solid(ka + hd, y0 - 1)
		var mp := solid(ka - hd, y1)
		var pp := solid(ka + hd, y1)
		var fx := float(x)
		var fz := float(z)
		var fy0 := float(y0)
		var fy1 := float(y1)
		var hgt := float(y1 - y0)
		if d == 0:  # u = +Y, v = +Z
			quad(Vector3(fx + 1, fy0, fz), Vector3(fx + 1, fy1, fz), Vector3(fx + 1, fy1, fz + 1), Vector3(fx + 1, fy0, fz + 1), n, c,
				corner_ao(vm, hm_b, mm), corner_ao(vp, hm_t, mp), corner_ao(vp, hp_t, pp), corner_ao(vm, hp_b, pm), Vector2(hgt, 1.0), 0.0)
		elif d == 1:  # u = +Z, v = +Y
			quad(Vector3(fx, fy0, fz), Vector3(fx, fy0, fz + 1), Vector3(fx, fy1, fz + 1), Vector3(fx, fy1, fz), n, c,
				corner_ao(hm_b, vm, mm), corner_ao(hp_b, vm, pm), corner_ao(hp_t, vp, pp), corner_ao(hm_t, vp, mp), Vector2(1.0, hgt), 0.0)
		else:  # +Z: u = +X, v = +Y
			quad(Vector3(fx, fy0, fz + 1), Vector3(fx + 1, fy0, fz + 1), Vector3(fx + 1, fy1, fz + 1), Vector3(fx, fy1, fz + 1), n, c,
				corner_ao(hm_b, vm, mm), corner_ao(hp_b, vm, pm), corner_ao(hp_t, vp, pp), corner_ao(hm_t, vp, mp), Vector2(1.0, hgt), 0.0)


static func _mesh_terrain(col: Dictionary) -> ArrayMesh:
	var m := TerrainMesher.new()
	m.w = col.w
	m.top = col.top
	m.bot = col.bot
	m.tc = col.tc
	m.sc = col.sc
	m.gl = col.gl
	m.layers = col.layers
	m.ground = G
	m.ao = PackedFloat32Array(AO)
	var w: int = col.w
	var h: int = col.h
	var top := m.top
	var bot := m.bot
	var tc := m.tc
	var gl := m.gl
	# cells next to something raised are shaded: no merging there
	var busy := PackedByteArray()
	busy.resize(w * h)
	for k in range(w, w * (h - 1)):
		var t := top[k]
		if t == 0 or t == G:
			continue
		busy[k] = 1
		if t > G:
			for o in [-w - 1, -w, -w + 1, -1, 1, w - 1, w, w + 1]:
				busy[k + o] = 1
	for z in range(1, h - 1):
		var x := 1
		var fz := float(z - 1)
		while x < w - 1:
			var k := z * w + x
			var t := top[k]
			if t == 0:
				x += 1
				continue
			var c := tc[k]
			var g := gl[k]
			var fy := float(t)
			if busy[k] == 0:
				var e := x + 1
				while e < w - 1:
					var k2 := k + e - x
					if busy[k2] != 0 or top[k2] != t or tc[k2] != c or gl[k2] != g:
						break
					e += 1
				var x0 := float(x - 1)
				var x1 := float(e - 1)
				m.quad(Vector3(x0, fy, fz), Vector3(x0, fy, fz + 1), Vector3(x1, fy, fz + 1), Vector3(x1, fy, fz), Vector3.UP, c,
					3, 3, 3, 3, Vector2(1.0, e - x), float(g))
				x = e
				continue
			# u = +Z, v = +X; a neighbour shades this top if it stands higher
			var um := 1 if top[k - w] > t else 0
			var up := 1 if top[k + w] > t else 0
			var vm := 1 if top[k - 1] > t else 0
			var vp := 1 if top[k + 1] > t else 0
			var mm := 1 if top[k - w - 1] > t else 0
			var pm := 1 if top[k + w - 1] > t else 0
			var pp := 1 if top[k + w + 1] > t else 0
			var mp := 1 if top[k - w + 1] > t else 0
			var fx := float(x - 1)
			m.quad(Vector3(fx, fy, fz), Vector3(fx, fy, fz + 1), Vector3(fx + 1, fy, fz + 1), Vector3(fx + 1, fy, fz), Vector3.UP, c,
				TerrainMesher.corner_ao(um, vm, mm), TerrainMesher.corner_ao(up, vm, pm), TerrainMesher.corner_ao(up, vp, pp),
				TerrainMesher.corner_ao(um, vp, mp), Vector2.ONE, float(g))
			x += 1
	# side faces: none face down or away (-Z): the camera is always above, in front
	for z in range(1, h - 1):
		for x in range(1, w - 1):
			var k := z * w + x
			var t := top[k]
			if t == 0:
				continue
			var b := bot[k]
			if top[k + 1] != t or bot[k + 1] != b:
				_sides(m, x, z, k, k + 1, 0)
			if top[k - 1] != t or bot[k - 1] != b:
				_sides(m, x, z, k, k - 1, 1)
			if top[k + w] != t or bot[k + w] != b:
				_sides(m, x, z, k, k + w, 2)
	var mesh := ArrayMesh.new()
	if m.vs.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = m.vs
	arrays[Mesh.ARRAY_NORMAL] = m.ns
	arrays[Mesh.ARRAY_COLOR] = m.cs
	arrays[Mesh.ARRAY_TEX_UV] = m.uv
	arrays[Mesh.ARRAY_TEX_UV2] = m.uv2
	arrays[Mesh.ARRAY_INDEX] = m.ix
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _terrain_mat())
	timings["quads"] = m.vs.size() / 4
	return mesh


## The faces of column k where its neighbour kn leaves it exposed.
static func _sides(m: TerrainMesher, x: int, z: int, k: int, kn: int, d: int) -> void:
	var t := m.top[k]
	var b := m.bot[k]
	var tn := m.top[kn]
	if tn == 0:
		m.side_run(x - 1, b, t, z - 1, k, d)
		return
	var bn := m.bot[kn]
	if bn > b:
		m.side_run(x - 1, b, mini(t, bn), z - 1, k, d)
	if tn < t:
		m.side_run(x - 1, maxi(b, tn), t, z - 1, k, d)


static func _terrain_mat() -> ShaderMaterial:
	if _terrain_material == null:
		var sh := Shader.new()
		sh.code = TERRAIN_SHADER
		_terrain_material = ShaderMaterial.new()
		_terrain_material.shader = sh
	return _terrain_material


# ------------------------------------------------------------ the Scrapyard

## The arena's raster: the yard inside the octagon, its walls, the scrap pile,
## the concrete blocks and the crash barriers; plus where the stands, tyre
## posts, lamps and wrecks go (cells).
static func _arena_raster(a: ArenaLayout) -> Dictionary:
	if _rasters.has("arena"):
		return _rasters["arena"]
	var t0 := Time.get_ticks_usec()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in a.boundary:
		lo = lo.min(p)
		hi = hi.max(p)
	for st in a.stands:
		lo = lo.min(st - Vector2(240.0, 70.0))
		hi = hi.max(st + Vector2(240.0, 70.0))
	var cell := maxf(hi.x - lo.x, hi.y - lo.y) / 90.0
	var nx := int(ceil((hi.x - lo.x) / cell)) + MARGIN * 2
	var nz := int(ceil((hi.y - lo.y) / cell)) + MARGIN * 2
	var org := lo - Vector2(MARGIN, MARGIN) * cell
	var cls := PackedByteArray()
	cls.resize(nx * nz)
	for z in nz:
		for x in nx:
			if Geometry2D.is_point_in_polygon(org + Vector2(x + 0.5, z + 0.5) * cell, a.boundary):
				cls[z * nx + x] = YARD
	for o: Dictionary in a.polygons:
		var pts: PackedVector2Array = o.points
		var kind: String = o.kind
		var blo := Vector2(INF, INF)
		var bhi := Vector2(-INF, -INF)
		var centre := Vector2.ZERO
		for p in pts:
			blo = blo.min(p)
			bhi = bhi.max(p)
			centre += p
		centre /= pts.size()
		var inner := PackedVector2Array()
		for p in pts:
			inner.append(centre + (p - centre) * 0.6)
		for z in range(int((blo.y - org.y) / cell) - 1, int((bhi.y - org.y) / cell) + 2):
			for x in range(int((blo.x - org.x) / cell) - 1, int((bhi.x - org.x) / cell) + 2):
				var p := org + Vector2(x + 0.5, z + 0.5) * cell
				if x < 0 or z < 0 or x >= nx or z >= nz or not Geometry2D.is_point_in_polygon(p, pts):
					continue
				var cl := PILE
				match kind:
					"pile":
						cl = PILE_TOP if Geometry2D.is_point_in_polygon(p, inner) else PILE
					"block":
						cl = BLOCK_A if ((x + z) / 2) % 2 == 0 else BLOCK_B
					_:
						cl = BAR_A if (z / 2) % 2 == 0 else BAR_B
				cls[z * nx + x] = cl
	# the walls: rasterised along the boundary
	var nb := a.boundary.size()
	for i in nb:
		var pa := (a.boundary[i] - org) / cell
		var pb := (a.boundary[(i + 1) % nb] - org) / cell
		var steps := int(pa.distance_to(pb) / 0.35) + 1
		for s in steps + 1:
			var p := pa.lerp(pb, float(s) / steps)
			var panel := WALL_A if int(s * 0.35 / 3.0) % 2 == 0 else WALL_B
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var x := int(floor(p.x)) + dx
					var z := int(floor(p.y)) + dz
					if x < 0 or z < 0 or x >= nx or z >= nz:
						continue
					if Vector2(x + 0.5, z + 0.5).distance_to(p) < 0.75:
						cls[z * nx + x] = panel
	var posts := PackedVector2Array()
	for t: Dictionary in a.posts:
		posts.append(((t.centre as Vector2) - org) / cell)
	var stands := PackedVector3Array()
	for st in a.stands:
		var p := (st - org) / cell
		var d := -st.normalized()  # facing the yard
		d = Vector2(0.0, signf(d.y)) if absf(d.y) > 0.3 else d
		stands.append(Vector3(p.x, p.y, atan2(d.x, d.y)))
	var lamps: Array = []
	for l: Array in a.lamps:
		var at: Vector2 = l[0]
		var out: Vector2 = l[1]
		lamps.append([(at - org) / cell - out.normalized() * 1.2, -out.normalized()])
	var wrecks: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 1991
	var pile: PackedVector2Array = a.polygons[0].points
	for k in 16:
		var c := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 115.0)
		var yaw := rng.randf() * TAU
		var tilt := Vector2(rng.randf_range(-0.35, 0.35), rng.randf_range(-0.3, 0.3))
		var lift := rng.randf()
		if not Geometry2D.is_point_in_polygon(c, pile):
			continue
		wrecks.append([(c - org) / cell, yaw, tilt, SCRAP_COLORS[k % SCRAP_COLORS.size()], lift])
	var r := {"nx": nx, "nz": nz, "cell": cell, "org": org, "cls": cls, "posts": posts, "stands": stands,
		"lamps": lamps, "wrecks": wrecks}
	_rasters["arena"] = r
	timings["raster"] = (Time.get_ticks_usec() - t0) / 1000.0
	return r


static func _build_arena(a: ArenaLayout, v: int) -> Dictionary:
	var r := _arena_raster(a)
	var t0 := Time.get_ticks_usec()
	var look: Dictionary = LOOKS[v]
	var nx: int = r.nx
	var nz: int = r.nz
	var cls: PackedByteArray = (r.cls as PackedByteArray).duplicate()
	var col := _columns(nx, nz, cls, v, look)
	var t1 := Time.get_ticks_usec()
	var parts: Array = []
	var lamps: Array = []
	var stands: PackedVector3Array = r.stands
	for st in stands:
		parts.append([_prop("stand:26:%d" % v), _xf(Vector2(st.x, st.y), st.z, 1.0, G), 1])
		_claim(cls, nx, nz, Vector2(st.x, st.y), Vector2(cos(st.z), -sin(st.z)), 13.0, 3.6, true)
	var posts: PackedVector2Array = r.posts
	for p in posts:
		parts.append([_prop("tyres"), _xf(p, 0.4, 1.3, G), 0])
	for wr: Array in r.wrecks:
		var p: Vector2 = wr[0]
		var tilt: Vector2 = wr[2]
		var colour: Color = wr[3]
		var lift: float = wr[4]
		var x := clampi(int(p.x), 0, nx - 1)
		var z := clampi(int(p.y), 0, nz - 1)
		var base := G + (2 if cls[z * nx + x] == PILE_TOP else 1)
		var y := base + (1.4 if lift > 0.62 else 0.0) - 0.3
		var yaw: float = wr[1]
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt.x) * Basis(Vector3.BACK, tilt.y)
		parts.append([_prop("wreck:" + colour.to_html(false)), Transform3D(basis.scaled(Vector3.ONE * 1.5), Vector3(p.x, y, p.y)), 0])
	for l: Array in r.lamps:
		_add_lamp(lamps, l[0], l[1], false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242 + v
	_scatter(SCATTER[v], nx, nz, cls, parts, rng)
	var t2 := Time.get_ticks_usec()
	var terrain := _mesh_terrain(col)
	timings["columns"] = (t1 - t0) / 1000.0
	timings["props"] = (t2 - t1) / 1000.0
	timings["mesh"] = (Time.get_ticks_usec() - t2) / 1000.0
	var lamp_color: Color = TrackTheme.load_variant(v).lamp_color
	return {"terrain": terrain, "parts": parts, "lamps": lamps, "size": Vector2(nx, nz),
		"fit": _fit_for(nx, nz, v == 5, parts, lamps), "lamp_color": lamp_color}


# ------------------------------------------------------------ props
# Little voxel models (PV voxels, half a terrain cell), built once from code
# and cached; they stand on y = 0, centred, their front facing +Z.

static func _prop(kind: String) -> ArrayMesh:
	if not _props.has(kind):
		_props[kind] = _build_prop(kind)
	return _props[kind]


static func _pg(sx: int, sy: int, sz: int) -> VoxelGrid:
	return VoxelGrid.new(Vector3i(sx, sy, sz), PV, Vector3.ZERO)


static func _pdone(g: VoxelGrid) -> ArrayMesh:
	var s := g.size()
	return VoxelMesher.build_mesh(g, VoxelCars.material(), Vector3(s.x * 0.5, 0.0, s.z * 0.5) * PV, 0.05)


## An ellipsoid of voxels: lower / middle / upper colour bands, a few voxels
## missing near the surface (holes: share).
static func _blob(g: VoxelGrid, c: Vector3, r: Vector3, cols: Array, holes: float = 0.0) -> void:
	var s := g.size()
	for y in range(maxi(0, int(floor(c.y - r.y))), mini(s.y, int(ceil(c.y + r.y)) + 1)):
		for z in range(maxi(0, int(floor(c.z - r.z))), mini(s.z, int(ceil(c.z + r.z)) + 1)):
			for x in range(maxi(0, int(floor(c.x - r.x))), mini(s.x, int(ceil(c.x + r.x)) + 1)):
				var d := Vector3((x - c.x) / r.x, (y - c.y) / r.y, (z - c.z) / r.z).length_squared()
				if d > 1.0 or (holes > 0.0 and d > 0.5 and Vox.hash3(x, y + 17, z) < holes):
					continue
				var f := (y - (c.y - r.y)) / (2.0 * r.y)
				var col: Color = cols[0] if f < 0.34 else (cols[1] if f < 0.68 else cols[2])
				g.set_v(x, y, z, Vox.SOLID, col)


## A gable roof along X over [x0, x1] x [z0, z1] from height y0.
static func _roof(g: VoxelGrid, x0: int, x1: int, z0: int, z1: int, y0: int, c: Color, ridge: Color) -> void:
	var k := 0
	while z0 + k <= z1 - k:
		g.box(Vector3i(x0, y0 + k, z0 + k), Vector3i(x1, y0 + k, z1 - k), Vox.SOLID, c if z0 + k < z1 - k - 1 else ridge)
		k += 1


static func _build_prop(kind: String) -> ArrayMesh:
	var bits := kind.split(":")
	var g: VoxelGrid
	var trunk := Color("6b4a33")
	match bits[0]:
		"tree", "bloom":
			g = _pg(7, 10, 7)
			for y in 4:
				g.set_v(3, y, 3, Vox.SOLID, trunk)
			var cols := [Color("2f7a33"), Color("3f9a3c"), Color("63b84b")]
			if bits[0] == "bloom":
				cols = [Color("c45a8c"), Color("e27aa9"), Color("f6a8c8")]
			_blob(g, Vector3(3, 6, 3), Vector3(3.4, 3.0, 3.4), cols, 0.3)
		"bush", "bush_dry", "bush_s":
			g = _pg(5, 3, 5)
			var cols := [Color("2f7a33"), Color("3f9a3c"), Color("5cb04a")]
			if bits[0] == "bush_dry":
				cols = [Color("5e6a32"), Color("74803e"), Color("8a9450")]
			elif bits[0] == "bush_s":
				cols = [Color("2f5d4a"), Color("3a6e56"), Color("f2f6fc")]
			_blob(g, Vector3(2, 1, 2), Vector3(2.5, 1.8, 2.5), cols, 0.25)
		"heather":
			g = _pg(5, 2, 5)
			_blob(g, Vector3(2, 0.4, 2), Vector3(2.6, 1.5, 2.6), [Color("553852"), Color("744a6e"), Color("8e5e88")], 0.3)
		"rock", "rock_s":
			g = _pg(5, 3, 4)
			var cols := [Color("6f6e74"), Color("85848a"), Color("9c9ba2")]
			if bits[0] == "rock_s":
				cols[2] = Color("f2f6fc")
			_blob(g, Vector3(2, 0.6, 1.5), Vector3(2.6, 2.2, 2.1), cols, 0.2)
		"dead":
			g = _pg(5, 8, 5)
			var bark := Color("5e4c40")
			for y in 6:
				g.set_v(2, y, 2, Vox.SOLID, bark)
			for p in [Vector3i(1, 4, 2), Vector3i(0, 5, 2), Vector3i(3, 5, 2), Vector3i(4, 6, 2), Vector3i(2, 6, 1), Vector3i(2, 7, 0), Vector3i(2, 6, 3)]:
				g.set_v(p.x, p.y, p.z, Vox.SOLID, bark.lightened(0.1))
		"pine", "pine_s":
			g = _pg(7, 13, 7)
			g.box(Vector3i(3, 0, 3), Vector3i(3, 1, 3), Vox.SOLID, trunk)
			for y in range(2, 13):
				var rr := lerpf(3.3, 0.3, (y - 2) / 10.0) + (0.6 if y % 3 == 2 else 0.0)
				var green := Color("2c6248") if y % 3 == 0 else Color("357052")
				for z in 7:
					for x in 7:
						if (x - 3) * (x - 3) + (z - 3) * (z - 3) <= rr * rr:
							g.set_v(x, y, z, Vox.SOLID, green)
			if bits[0] == "pine_s":
				for y in range(2, 13):
					for z in 7:
						for x in 7:
							if g.get_m(x, y, z) != 0 and g.get_m(x, y + 1, z) == 0:
								g.set_v(x, y, z, Vox.SOLID, Color("f2f6fc"))
		"hay":
			g = _pg(3, 3, 3)
			_blob(g, Vector3(1, 1, 1), Vector3(1.6, 1.6, 1.6), [Color("c9a440"), Color("dcb752"), Color("e8c968")])
		"barn":
			g = _pg(11, 10, 8)
			var red := Color("b83a2e")
			g.box(Vector3i(1, 0, 1), Vector3i(9, 4, 6), Vox.SOLID, red)
			for x in range(1, 10, 2):
				g.box(Vector3i(x, 0, 6), Vector3i(x, 4, 6), Vox.SOLID, red.darkened(0.12))
			g.box(Vector3i(4, 0, 6), Vector3i(6, 3, 7), Vox.SOLID, Color("f2eee6"))
			g.box(Vector3i(5, 0, 7), Vector3i(5, 2, 7), Vox.SOLID, red.darkened(0.3))
			g.box(Vector3i(1, 5, 0), Vector3i(9, 5, 7), Vox.SOLID, Color("4a4f5c"))
			_roof(g, 0, 10, 0, 7, 5, Color("4a4f5c"), Color("3a3e48"))
			g.box(Vector3i(5, 6, 7), Vector3i(5, 6, 7), Vox.GLOW, Color(1.0, 0.82, 0.45))
		"windmill":
			g = _pg(13, 19, 7)
			for y in 11:
				var r := 2 if y < 7 else 1
				g.box(Vector3i(6 - r, y, 3 - r), Vector3i(6 + r, y, 3 + r), Vox.SOLID, Color("efe9df") if y % 4 != 3 else Color("d8d0c4"))
			g.box(Vector3i(5, 11, 2), Vector3i(7, 12, 4), Vox.SOLID, Color("8a3a2e"))
			g.box(Vector3i(6, 0, 5), Vector3i(6, 1, 5), Vox.SOLID, Color("6b4a33"))
			g.box(Vector3i(5, 6, 5), Vector3i(5, 6, 5), Vox.GLOW, Color(1.0, 0.82, 0.45))
			var hub := Vector2i(6, 12)
			for k in range(1, 7):
				var cloth := Color("f4efe6") if k > 1 else Color("6b4a33")
				for p in [Vector2i(k, 0), Vector2i(k, 1), Vector2i(-k, 0), Vector2i(-k, -1), Vector2i(0, k), Vector2i(-1, k), Vector2i(0, -k), Vector2i(1, -k)]:
					var edge: bool = p.x == 0 or p.y == 0
					g.set_v(hub.x + p.x, hub.y + p.y, 5, Vox.SOLID, Color("6b4a33") if edge else cloth)
			g.set_v(hub.x, hub.y, 5, Vox.SOLID, Color("4a3426"))
		"shed":
			g = _pg(9, 6, 7)
			for x in range(1, 8):
				g.box(Vector3i(x, 0, 1), Vector3i(x, 3, 5), Vox.SOLID, Color("a8643a") if x % 2 == 0 else Color("8e5230"))
			g.box(Vector3i(0, 4, 0), Vector3i(8, 4, 6), Vox.SOLID, Color("4e535e"))
			g.box(Vector3i(3, 0, 5), Vector3i(4, 2, 6), Vox.SOLID, Color("3a3d44"))
			g.box(Vector3i(6, 2, 6), Vector3i(6, 2, 6), Vox.GLOW, Color(1.0, 0.8, 0.45))
		"containers":
			g = _pg(9, 5, 5)
			for x in 9:
				g.box(Vector3i(x, 0, 0), Vector3i(x, 1, 4), Vox.SOLID, Color("2b7fb8") if x % 2 == 0 else Color("246c9c"))
				if x < 7:
					g.box(Vector3i(x + 1, 2, 0), Vector3i(x + 1, 3, 4), Vox.SOLID, Color("d8642a") if x % 2 == 0 else Color("bc5524"))
		"drums":
			g = _pg(3, 2, 3)
			for p in [Vector2i(0, 0), Vector2i(2, 0), Vector2i(1, 2)]:
				g.box(Vector3i(p.x, 0, p.y), Vector3i(p.x, 1, p.y), Vox.SOLID, Color("3f6e8c") if p.y == 0 else Color("a8492e"))
		"cabin":
			g = _pg(10, 9, 8)
			for y in 4:
				g.box(Vector3i(1, y, 1), Vector3i(8, y, 6), Vox.SOLID, Color("8a5a36") if y % 2 == 0 else Color("74482a"))
			g.box(Vector3i(4, 0, 6), Vector3i(5, 2, 7), Vox.SOLID, Color("4a2e1c"))
			for wx in [2, 7]:
				g.box(Vector3i(wx, 1, 7), Vector3i(wx, 2, 7), Vox.GLOW, Color(1.0, 0.78, 0.42))
			_roof(g, 0, 9, 0, 7, 4, Color("f2f6fc"), Color("ffffff"))
			g.box(Vector3i(7, 5, 2), Vector3i(7, 7, 2), Vox.SOLID, Color("6a5a52"))
		"snowman":
			g = _pg(3, 7, 3)
			g.box(Vector3i(0, 0, 0), Vector3i(2, 2, 2), Vox.SOLID, Color("f6f9ff"))
			g.box(Vector3i(1, 3, 1), Vector3i(1, 4, 1), Vox.SOLID, Color("f6f9ff"))
			g.box(Vector3i(0, 3, 1), Vector3i(2, 3, 1), Vox.SOLID, Color("f6f9ff"))
			g.set_v(1, 5, 1, Vox.SOLID, Color("f6f9ff"))
			g.set_v(1, 5, 2, Vox.SOLID, Color("ff8c2e"))
			g.set_v(1, 6, 1, Vox.SOLID, Color("26262c"))
			g.set_v(1, 4, 2, Vox.SOLID, Color("e8432e"))
		"tent":
			g = _pg(8, 7, 8)
			g.box(Vector3i(1, 0, 1), Vector3i(6, 2, 6), Vox.SOLID, Color("f2efe8"))
			g.box(Vector3i(3, 0, 6), Vector3i(4, 1, 7), Vox.GLOW, Color(1.0, 0.88, 0.6))
			for k in 4:
				for x in range(k, 8 - k):
					for z in range(k, 8 - k):
						if x == k or x == 7 - k or z == k or z == 7 - k:
							g.set_v(x, 3 + k, z, Vox.SOLID, Color("e5432f") if (x + z) % 4 < 2 else Color("f5f2eb"))
		"tyres":
			g = _pg(3, 3, 3)
			for y in 3:
				for z in 3:
					for x in 3:
						if x != 1 or z != 1:
							g.set_v(x, y, z, Vox.SOLID, Color("1f1f24") if y != 1 else Color("e5432f"))
		"adboard":
			g = _pg(8, 4, 1)
			g.box(Vector3i(0, 1, 0), Vector3i(7, 3, 0), Vox.SOLID, Color("1f2a5a"))
			g.box(Vector3i(1, 2, 0), Vector3i(6, 2, 0), Vox.SOLID, Color("f4c234"))
			g.box(Vector3i(1, 0, 0), Vector3i(1, 0, 0), Vox.METAL, Color("8a8f98"))
			g.box(Vector3i(6, 0, 0), Vector3i(6, 0, 0), Vox.METAL, Color("8a8f98"))
		"stand":
			var length := int(bits[1])
			var v := int(bits[2])
			g = _pg(length, 9, 7)
			var frame: Color = [Color("b9b3a8"), Color("8a6a4a"), Color("8a8580"), Color("b9b3a8"), Color("c4c1ba"), Color("8a6a4a")][v % 6]
			for x in length:
				for z in 7:
					var th := 1 + (6 - z) / 2
					g.box(Vector3i(x, 0, z), Vector3i(x, th - 1, z), Vox.SOLID, frame.darkened(0.06 * (z % 2)))
					if x > 0 and x < length - 1 and z < 7:
						var hh := Vox.hash3(x, z, length)
						if hh > 0.2:
							g.set_v(x, th, z, Vox.SOLID, CROWD[int(hh * 97.0) % CROWD.size()])
				g.box(Vector3i(x, 4, 0), Vector3i(x, 5, 0), Vox.SOLID, frame.darkened(0.1))
				if v == 4:  # The Raceway: a striped roof over the back rows
					g.box(Vector3i(x, 7, 0), Vector3i(x, 7, 3), Vox.SOLID, Color("e5432f") if (x / 2) % 2 == 0 else Color("f5f2eb"))
					if x % 4 == 1:
						g.set_v(x, 6, 3, Vox.GLOW, Color(1.0, 0.95, 0.85))
				elif v == 3:
					g.box(Vector3i(x, 6, 0), Vector3i(x, 6, 1), Vox.SOLID, Color("f2f6fc"))
			if v == 4:
				for x in [0, length - 1]:
					g.box(Vector3i(x, 4, 3), Vector3i(x, 6, 3), Vox.METAL, Color("8a8f98"))
		"garages":
			var length := int(bits[1])
			g = _pg(length, 6, 6)
			g.box(Vector3i(0, 0, 0), Vector3i(length - 1, 3, 4), Vox.SOLID, Color("e8e6e0"))
			var teams := [Color("e5432f"), Color("2e6fd0"), Color("f4c234"), Color("2ec4b6"), Color("3a3a42")]
			for x in range(1, length - 1, 3):
				g.box(Vector3i(x, 0, 5), Vector3i(mini(x + 1, length - 2), 2, 5), Vox.SOLID, teams[(x / 3) % teams.size()])
			g.box(Vector3i(0, 3, 5), Vector3i(length - 1, 3, 5), Vox.GLOW, Color(0.85, 0.92, 1.0))
			g.box(Vector3i(0, 4, 0), Vector3i(length - 1, 4, 5), Vox.SOLID, Color("4e535e"))
			g.box(Vector3i(0, 4, 5), Vector3i(length - 1, 4, 5), Vox.SOLID, Color("e5432f"))
		"gantry":
			var width := int(bits[1])
			g = _pg(width, 7, 1)
			for x in [0, width - 1]:
				g.box(Vector3i(x, 0, 0), Vector3i(x, 4, 0), Vox.METAL, Color("c9ccd2"))
			for x in width:
				g.set_v(x, 5, 0, Vox.SOLID, Color("f4f2ee") if x % 2 == 0 else Color("26262c"))
				g.set_v(x, 6, 0, Vox.SOLID, Color("26262c") if x % 2 == 0 else Color("f4f2ee"))
			for x in range(2, width - 2, 3):
				g.set_v(x, 4, 0, Vox.GLOW, Color(1.0, 0.25, 0.15))
		"car", "wreck":
			var paint := Color(bits[1])
			var broken := bits[0] == "wreck"
			g = _pg(6, 3, 3)
			if broken:
				paint = paint.darkened(0.25)
			g.box(Vector3i(0, 0, 0), Vector3i(5, 1, 2), Vox.SOLID, paint)
			for p in [Vector3i(1, 0, 0), Vector3i(4, 0, 0), Vector3i(1, 0, 2), Vector3i(4, 0, 2)]:
				g.set_v(p.x, p.y, p.z, Vox.SOLID, Color("1d1d22"))
			g.box(Vector3i(3, 2, 0), Vector3i(3, 2, 2), Vox.GLASS, Color("2a3040"))
			g.box(Vector3i(1, 2, 0), Vector3i(2, 2, 2), Vox.SOLID, paint.lightened(0.08))
			if broken:
				for p in [Vector3i(5, 1, 0), Vector3i(0, 1, 2), Vector3i(2, 2, 1), Vector3i(3, 2, 2)]:
					g.set_v(p.x, p.y, p.z, Vox.AIR, Color())
				g.set_v(2, 1, 0, Vox.SOLID, Color("8a5a3a"))
				g.set_v(1, 1, 2, Vox.SOLID, Color("7a4a2a"))
			else:
				g.box(Vector3i(1, 2, 1), Vector3i(2, 2, 1), Vox.SOLID, Color("f4f2ee"))
				g.set_v(5, 1, 0, Vox.HEAD, Color("fff4d8"))
				g.set_v(5, 1, 2, Vox.HEAD, Color("fff4d8"))
				g.set_v(0, 1, 0, Vox.TAIL, Color("c8302a"))
				g.set_v(0, 1, 2, Vox.TAIL, Color("c8302a"))
		"pencil":
			var body := Color(bits[1])
			g = _pg(19, 3, 3)
			for x in 19:
				for y in 3:
					for z in 3:
						if (y == 0 or y == 2) and (z == 0 or z == 2):
							continue
						var c := body if (y + z) % 2 == 1 else body.darkened(0.1)
						if x < 2:
							c = Color("e88c9c")
						elif x == 2:
							c = Color("c9ccd2")
						elif x >= 15:
							if x >= 17 and (y != 1 or z != 1):
								continue
							c = Color("e8c890") if x < 18 else Color("33333a")
						g.set_v(x, y, z, Vox.METAL if x == 2 else Vox.SOLID, c)
		"die":
			g = _pg(5, 5, 5)
			g.box(Vector3i(0, 0, 0), Vector3i(4, 4, 4), Vox.SOLID, Color("f6f3ec"))
			for p in [Vector3i(0, 0, 0), Vector3i(4, 0, 0), Vector3i(0, 4, 0), Vector3i(4, 4, 0), Vector3i(0, 0, 4), Vector3i(4, 0, 4), Vector3i(0, 4, 4), Vector3i(4, 4, 4)]:
				g.set_v(p.x, p.y, p.z, Vox.AIR, Color())
			var pip := Color("2a2a30")
			for p in [Vector2i(1, 1), Vector2i(1, 3), Vector2i(3, 1), Vector2i(3, 3), Vector2i(2, 2)]:
				g.set_v(p.x, 4, p.y, Vox.SOLID, pip)
			for p in [Vector2i(1, 3), Vector2i(2, 2), Vector2i(3, 1)]:
				g.set_v(p.x, p.y, 4, Vox.SOLID, pip)
			for p in [Vector2i(1, 3), Vector2i(3, 1)]:
				g.set_v(4, p.y, p.x, Vox.SOLID, pip)
				g.set_v(0, p.x, p.y, Vox.SOLID, pip)
		"mug":
			g = _pg(9, 6, 7)
			var glaze := Color("e5432f")
			for y in 6:
				for z in 7:
					for x in 7:
						var d := Vector2(x - 3, z - 3).length()
						if d <= 3.2 and (y == 0 or d > 2.1):
							g.set_v(x, y, z, Vox.SOLID, glaze if y != 4 else Color("f6f3ec"))
						elif d <= 2.1 and y == 4:
							g.set_v(x, y, z, Vox.SOLID, Color("4a2c1c"))
			for p in [Vector2i(7, 1), Vector2i(8, 2), Vector2i(8, 3), Vector2i(7, 4)]:
				g.set_v(p.x, p.y, 3, Vox.SOLID, glaze)
		"card":
			g = _pg(6, 1, 9)
			g.box(Vector3i(0, 0, 0), Vector3i(5, 0, 8), Vox.SOLID, Color("f6f3ec"))
			for p in [Vector2i(2, 3), Vector2i(3, 3), Vector2i(1, 4), Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4), Vector2i(2, 5), Vector2i(3, 5), Vector2i(1, 3), Vector2i(4, 3)]:
				g.set_v(p.x, 0, p.y, Vox.SOLID, Color("d8303a"))
			g.set_v(0, 0, 0, Vox.SOLID, Color("d8303a"))
			g.set_v(5, 0, 8, Vox.SOLID, Color("d8303a"))
		"block":
			g = _pg(4, 4, 4)
			g.box(Vector3i(0, 0, 0), Vector3i(3, 3, 3), Vox.SOLID, Color("3a6ad8"))
			g.box(Vector3i(0, 3, 0), Vector3i(3, 3, 3), Vox.SOLID, Color("f4c234"))
			for p in [Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2), Vector2i(2, 1)]:
				g.set_v(p.x, p.y, 3, Vox.SOLID, Color("e5432f"))
		_:
			g = _pg(2, 2, 2)
			g.box(Vector3i(0, 0, 0), Vector3i(1, 1, 1), Vox.SOLID, Color.MAGENTA)
	return _pdone(g)


## DIAGNOSTIC probe (Performance Investigation 001)
func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process__perf(delta)
	PerfProbe.add(&"menu.preview", __t)


## DIAGNOSTIC probe (Performance Investigation 001)
func show_circuit(p_layout: TrackLayout, p_variant: int, p_night: bool) -> void:
	var __t := Time.get_ticks_usec()
	show_circuit__perf(p_layout, p_variant, p_night)
	PerfProbe.add(&"menu.preview_show", __t)
