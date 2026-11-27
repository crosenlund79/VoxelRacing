class_name GraphicsSettings
extends RefCounted
## Graphics & display settings (Settings screen): a quality preset (Low,
## Medium, High, Ultra), the window resolution and the display mode
## (Windowed, Fullscreen = exclusive, Borderless = Godot's borderless
## WINDOW_MODE_FULLSCREEN). Saved in user://settings.cfg [graphics] and applied
## at game start (game.gd) and whenever Settings changes them.
##
## Ultra is the game's own look, untouched: every value comes from
## project.godot or from the scene that built the light / environment. The
## lower presets only turn down costs measured in docs/perf (investigation
## 001: the sun's shadow pass, SSAO, glow, pixels); they keep the voxel look,
## the colours, the lighting, the tilt-shift miniature blur and the night
## lights (glow stays on, the meshes have their own baked ambient occlusion).
##
## How it reaches the 3D views without touching their builders: viewport-level
## settings go to the root viewport (where the race and the menu diorama
## render), renderer-wide ones to the RenderingServer, and every
## WorldEnvironment / DirectionalLight3D that enters the tree (race stage, menu
## diorama, garage, podium, loading screen) is adjusted from its own original
## values, which are remembered so a later preset (Ultra included) restores
## them exactly. The small icon / logo / circuit-preview studios keep their look.

const SETTINGS_PATH := "user://settings.cfg"
const BASE := Vector2i(1280, 720)

const PRESETS: Array[String] = ["low", "medium", "high", "ultra"]
const PRESET_NAMES := {"low": "Low", "medium": "Medium", "high": "High", "ultra": "Ultra"}
## What each preset changes; a missing key keeps the game's own value.
##   scale: 3D render scale (FSR 1 upscaling below 1; never under 720 lines)
##   msaa / fxaa: anti-aliasing of the 3D view
##   shadow_atlas / shadow_filter: sun shadow map size, soft-shadow filter
##   shadow_splits / shadow_distance: sun shadow cascades (max), distance factor
##   ssao / ssao_quality: screen-space ambient occlusion on / its quality
##   glow_bicubic: smooth (bicubic) glow upscaling
const QUALITY := {
	"low": {"scale": 0.75, "msaa": Viewport.MSAA_DISABLED, "fxaa": true, "shadow_atlas": 2048, "shadow_filter": 0,
		"shadow_splits": 1, "shadow_distance": 0.8, "ssao": false, "glow_bicubic": false},
	"medium": {"msaa": Viewport.MSAA_DISABLED, "fxaa": true, "shadow_filter": 1, "shadow_splits": 2,
		"shadow_distance": 0.9, "ssao_quality": RenderingServer.ENV_SSAO_QUALITY_VERY_LOW, "glow_bicubic": false},
	"high": {"shadow_filter": 1, "ssao_quality": RenderingServer.ENV_SSAO_QUALITY_LOW},
	"ultra": {},
}

const MODES: Array[String] = ["windowed", "fullscreen", "borderless"]
const MODE_NAMES := {"windowed": "Windowed", "fullscreen": "Fullscreen", "borderless": "Borderless"}
const MODE_ICONS := {"windowed": "windowed", "fullscreen": "fullscreen", "borderless": "borderless"}
## Common 16:9 and 16:10 window sizes (the list keeps those that fit the screen).
const COMMON_SIZES: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1280, 800), Vector2i(1366, 768), Vector2i(1440, 900),
	Vector2i(1600, 900), Vector2i(1680, 1050), Vector2i(1920, 1080), Vector2i(1920, 1200),
	Vector2i(2560, 1440), Vector2i(2560, 1600), Vector2i(3200, 1800), Vector2i(3840, 2160),
]
## These build their own small 3D pictures and keep their look whatever the preset.
const EXEMPT_SCRIPTS: Array[String] = [
	"res://src/ui/voxel_icon_studio.gd", "res://src/ui/voxel_logo.gd", "res://src/ui/circuit_preview.gd",
]

static var quality := "ultra"
static var mode := "windowed"
## The window size in windowed mode (ZERO: the project's own 1280 x 720).
static var resolution := Vector2i.ZERO
static var _loaded := false
static var _watch: GraphicsSettings


static func load_prefs(path: String = SETTINGS_PATH) -> void:
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	var q := String(cfg.get_value("graphics", "quality", quality))
	quality = q if q in PRESETS else "ultra"
	var m := String(cfg.get_value("graphics", "display_mode", mode))
	mode = m if m in MODES else "windowed"
	resolution = parse_size(String(cfg.get_value("graphics", "resolution", "")))


static func save_prefs(path: String = SETTINGS_PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)  # keep the other sections
	cfg.set_value("graphics", "quality", quality)
	cfg.set_value("graphics", "display_mode", mode)
	cfg.set_value("graphics", "resolution", size_text(resolution) if resolution != Vector2i.ZERO else "")
	cfg.save(path)


## Everything: the display (mode, window size) and the quality preset.
static func apply_all() -> void:
	if not _loaded:
		load_prefs()
	apply_display()
	apply_quality()


# ------------------------------------------------------------ display

static func _has_window() -> bool:
	return DisplayServer.get_name() != "headless"


static func screen_size() -> Vector2i:
	if not _has_window():
		return BASE
	var s := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	return s if s.x > 0 and s.y > 0 else BASE


## The window sizes offered: the common ones that fit the screen, plus the
## screen's own size, smallest first.
static func resolutions() -> Array[Vector2i]:
	var screen := screen_size()
	var out: Array[Vector2i] = []
	for s in COMMON_SIZES:
		if s.x <= screen.x and s.y <= screen.y:
			out.append(s)
	if not out.has(screen):
		out.append(screen)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x * a.y < b.x * b.y or (a.x * a.y == b.x * b.y and a.x < b.x))
	return out


## The windowed size in use (the saved one, else the project's 1280 x 720),
## never larger than the screen.
static func window_size() -> Vector2i:
	var want := resolution if resolution != Vector2i.ZERO else BASE
	var screen := screen_size()
	return Vector2i(mini(want.x, screen.x), mini(want.y, screen.y))


static func fullscreen() -> bool:
	return mode != "windowed"


static func apply_display() -> void:
	if not _has_window():
		return
	match mode:
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		"borderless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			_size_window()
			_hook()._size_window_later()  # some platforms settle the mode change a frame later
	_apply_scale()


static func _size_window() -> void:
	if mode != "windowed" or DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		return
	var s := window_size()
	var area := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	if DisplayServer.window_get_size() != s:
		DisplayServer.window_set_size(s)
	if area.size.x > 0:
		var pos := area.position + (area.size - s) / 2
		DisplayServer.window_set_position(Vector2i(maxi(pos.x, area.position.x), maxi(pos.y, area.position.y)))


static func parse_size(t: String) -> Vector2i:
	var p := t.to_lower().split("x")
	if p.size() != 2 or not p[0].is_valid_int() or not p[1].is_valid_int():
		return Vector2i.ZERO
	var s := Vector2i(int(p[0]), int(p[1]))
	return s if s.x >= 320 and s.y >= 200 else Vector2i.ZERO


static func size_text(s: Vector2i) -> String:
	return "%dx%d" % [s.x, s.y]


# ------------------------------------------------------------ quality

static func _q() -> Dictionary:
	return QUALITY.get(quality, {})


static func _ps(key: String, fallback: Variant) -> Variant:
	return ProjectSettings.get_setting(key, fallback)


static func apply_quality() -> void:
	var q := _q()
	# renderer-wide: the sun's shadow map, soft-shadow filters, SSAO quality, glow upscaling
	RenderingServer.directional_shadow_atlas_set_size(
		int(q.get("shadow_atlas", _ps("rendering/lights_and_shadows/directional_shadow/size", 4096))),
		bool(_ps("rendering/lights_and_shadows/directional_shadow/16_bits", true)))
	RenderingServer.directional_soft_shadow_filter_set_quality(int(q.get("shadow_filter",
		_ps("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality", 2))))
	RenderingServer.positional_soft_shadow_filter_set_quality(int(q.get("shadow_filter",
		_ps("rendering/lights_and_shadows/positional_shadow/soft_shadow_filter_quality", 2))))
	RenderingServer.environment_set_ssao_quality(
		int(q.get("ssao_quality", _ps("rendering/environment/ssao/quality", 2))),
		bool(_ps("rendering/environment/ssao/half_size", true)),
		float(_ps("rendering/environment/ssao/adaptive_target", 0.5)),
		int(_ps("rendering/environment/ssao/blur_passes", 2)),
		float(_ps("rendering/environment/ssao/fadeout_from", 50.0)),
		float(_ps("rendering/environment/ssao/fadeout_to", 300.0)))
	RenderingServer.environment_glow_set_use_bicubic_upscale(bool(q.get("glow_bicubic",
		int(_ps("rendering/environment/glow/upscale_mode", 1)) > 0)))
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	# the root viewport (race, menu diorama): anti-aliasing and render scale
	var vp := tree.root
	vp.msaa_3d = int(q.get("msaa", _ps("rendering/anti_aliasing/quality/msaa_3d", Viewport.MSAA_2X))) as Viewport.MSAA
	vp.screen_space_aa = (Viewport.SCREEN_SPACE_AA_FXAA if bool(q.get("fxaa", false))
		else int(_ps("rendering/anti_aliasing/quality/screen_space_aa", 0))) as Viewport.ScreenSpaceAA
	_apply_scale()
	_hook()
	# the lights and environments already built
	for n in vp.find_children("*", "WorldEnvironment", true, false):
		_apply_node(n)
	for n in vp.find_children("*", "DirectionalLight3D", true, false):
		_apply_node(n)


## The 3D render scale: the preset's, but never fewer than 720 rendered lines.
static func _apply_scale() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var vp := tree.root
	var q := _q()
	var scale := float(_ps("rendering/scaling_3d/scale", 1.0))
	var scale_mode := int(_ps("rendering/scaling_3d/mode", 0))
	if q.has("scale"):
		var h := DisplayServer.window_get_size().y if _has_window() else BASE.y
		scale = clampf(maxf(float(q.scale), float(BASE.y) / float(maxi(h, 1))), 0.25, 1.0)
		scale_mode = Viewport.SCALING_3D_MODE_BILINEAR
		if scale < 0.999 and RenderingServer.get_current_rendering_method() != "gl_compatibility":
			scale_mode = Viewport.SCALING_3D_MODE_FSR
	vp.scaling_3d_mode = scale_mode as Viewport.Scaling3DMode
	vp.scaling_3d_scale = scale
	vp.fsr_sharpness = float(_ps("rendering/scaling_3d/fsr_sharpness", 0.2))


## One WorldEnvironment or DirectionalLight3D: the preset applied to the values
## its builder gave it (remembered on first sight).
static func _apply_node(n: Node) -> void:
	if not is_instance_valid(n) or not n.is_inside_tree() or _exempt(n):
		return
	var q := _q()
	if n is WorldEnvironment:
		var e := (n as WorldEnvironment).environment
		if e == null:
			return
		if not e.has_meta("vr_gfx"):
			e.set_meta("vr_gfx", {"ssao": e.ssao_enabled})
		var o: Dictionary = e.get_meta("vr_gfx")
		e.ssao_enabled = bool(o.ssao) and bool(q.get("ssao", true))
	elif n is DirectionalLight3D:
		var l := n as DirectionalLight3D
		if not l.has_meta("vr_gfx"):
			l.set_meta("vr_gfx", {"mode": l.directional_shadow_mode, "dist": l.directional_shadow_max_distance})
		var o: Dictionary = l.get_meta("vr_gfx")
		var m := int(o.mode)
		var splits := int(q.get("shadow_splits", 4))
		if splits <= 1:
			m = DirectionalLight3D.SHADOW_ORTHOGONAL
		elif splits <= 2 and m == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS:
			m = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		l.directional_shadow_mode = m as DirectionalLight3D.ShadowMode
		l.directional_shadow_max_distance = float(o.dist) * float(q.get("shadow_distance", 1.0))


static func _exempt(n: Node) -> bool:
	var p: Node = n
	while p != null:
		var s: Variant = p.get_script()
		if s is Script and (s as Script).resource_path in EXEMPT_SCRIPTS:
			return true
		p = p.get_parent()
	return false


## The watcher: adjusts lights and environments as scenes create them, and the
## render scale when the window is resized.
static func _hook() -> GraphicsSettings:
	if _watch != null:
		return _watch
	_watch = GraphicsSettings.new()
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.node_added.connect(_watch._on_node_added)
		tree.root.size_changed.connect(_watch._on_resized)
	return _watch


func _on_node_added(n: Node) -> void:
	if n is WorldEnvironment or n is DirectionalLight3D:
		_apply_later.call_deferred(n)  # after its builder has set it up


func _apply_later(n: Variant) -> void:  # untyped: it may have been freed meanwhile
	if is_instance_valid(n):
		GraphicsSettings._apply_node(n as Node)


func _on_resized() -> void:
	GraphicsSettings._apply_scale()


func _size_window_later() -> void:
	(func() -> void: GraphicsSettings._size_window()).call_deferred()
