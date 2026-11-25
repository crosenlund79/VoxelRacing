extends GutTest
## Track theme variants: three generic variants (1 = baseline), per-variant
## ground / road / barrier / props with fallback to the shared assets, visual
## only (races bit-identical on every variant), title selection.

const MAIN_SCENE := preload("res://src/main/main.tscn")
const SETTINGS := "user://test_track_theme_settings.cfg"


func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func test_three_generic_variants() -> void:
	var names := {}
	for n in range(1, TrackTheme.VARIANT_COUNT + 1):
		var t := TrackTheme.load_variant(n)
		assert_eq(t.variant, n)
		assert_false(t.display_name.is_empty())
		names[t.display_name] = true
		assert_gt(t.scenery.size(), 0)
		assert_eq(t.scenery_weights.size(), t.scenery.size())
		assert_eq(t.scenery_sway.size(), t.scenery.size())
		for logical in t.scenery:
			assert_true(AssetCatalog.SPECS.has(t.asset(logical)), "variant %d prop %s" % [n, logical])
	assert_eq(names.size(), 5, "distinct display names")
	assert_eq(TrackTheme.load_variant(99).variant, 5, "clamped")
	for k in range(1, 6):
		var t := TrackTheme.load_variant(k)
		for logical in t.landmarks:
			assert_true(AssetCatalog.SPECS.has(t.asset(logical)), "variant %d landmark %s" % [k, logical])


func test_variant_assets_fall_back_to_shared_ones() -> void:
	assert_eq(AssetCatalog.themed("track/grass", 1), "track/grass", "Variant 1 = shared baseline")
	assert_eq(AssetCatalog.themed("track/grass", 2), "variant_2/track/grass")
	assert_eq(AssetCatalog.themed("track/wall", 3), "variant_3/track/wall")
	assert_eq(AssetCatalog.themed("track/start_line", 3), "track/start_line", "not overridden: shared")
	assert_eq(AssetCatalog.themed(AssetCatalog.CAR_PLAYER, 2), AssetCatalog.CAR_PLAYER)


func test_variant_assets_keep_the_shared_contract_and_load() -> void:
	var r := AssetResolver.new("user://no_overrides_here")
	for v in [2, 3, 4, 5]:
		for base in ["track/grass", "track/tarmac", "track/wall"]:
			var key := AssetCatalog.themed(base, v)
			assert_ne(key, base)
			assert_eq(AssetCatalog.SPECS[key].template_size, AssetCatalog.SPECS[base].template_size, key)
			assert_eq(AssetCatalog.SPECS[key].get("tile_world_size"), AssetCatalog.SPECS[base].get("tile_world_size"), key)
			assert_eq(AssetCatalog.SPECS[key].get("display_size"), AssetCatalog.SPECS[base].get("display_size"), key)
		for p in ["scenery/prop_1", "scenery/prop_2", "scenery/prop_3"]:
			var key2 := AssetCatalog.themed(p, v)
			var tex := r.get_texture(key2)
			assert_not_null(tex, key2)
			assert_eq(Vector2i(tex.get_width(), tex.get_height()), AssetCatalog.SPECS[key2].template_size, key2)
	assert_eq(AssetResolver.fallback_path("variant_2/track/grass"), "res://assets/graphics/variant_2/track/template_grass.png")


func test_track_uses_the_variant_art_with_identical_geometry() -> void:
	var r := AssetResolver.new("user://no_overrides_here")
	var built := []
	for v in [1, 2, 3]:
		var m: Node2D = MAIN_SCENE.instantiate()
		m.presentation_enabled = false
		m.track_variant = v
		add_child_autofree(m)
		await wait_physics_frames(1)
		var ground: Polygon2D = m.track.get_node("Ground")
		assert_eq(ground.texture, r.get_texture(AssetCatalog.themed("track/grass", v)), "variant %d ground" % v)
		var shapes := []
		for c in m.track.get_children():
			if c is CollisionObject2D:
				for s in c.get_children():
					if s is CollisionPolygon2D:
						shapes.append(s.polygon)
					elif s is CollisionShape2D:
						shapes.append([s.position, s.shape])
		built.append([m.track.centerline, m.track.checkpoint_samples, shapes.size(), m.grid_order])
		if v == 3:
			assert_string_contains(m.hud._message_box.get_child(0).text, "WINTER")
	assert_eq(built[1], built[0], "same geometry and grid")
	assert_eq(built[2], built[0])


## Biomes (2026-11-16) change handling for every car alike, so races on
## Wasteland and Winter differ from Green Valley on purpose; each biome stays
## deterministic (same race twice in fresh processes, same result).
func test_biomes_change_races_deterministically() -> void:
	var args := ["mode=race", "ticks=1800", "weapons=1"]
	var base := ProbeRunner.run(PackedStringArray(args + ["theme=1"]))
	assert_eq(base.length(), 32, base)
	for v in ["2", "3", "4", "5"]:
		var a := ProbeRunner.run(PackedStringArray(args + ["theme=" + v]))
		assert_ne(a, base, "biome %s handles differently" % v)
		assert_eq(ProbeRunner.run(PackedStringArray(args + ["theme=" + v])), a, "biome %s deterministic" % v)


func test_variant_props_stay_clear_of_the_track() -> void:
	var m: Node2D = MAIN_SCENE.instantiate()
	m.track_variant = 3
	add_child_autofree(m)
	await wait_physics_frames(1)
	var half: float = m.track.layout.road_width * 0.5
	var props := 0
	for s in m.scenery.get_children():
		if s is Sprite2D and s.texture == m.resolver.get_texture("variant_3/scenery/prop_1"):
			props += 1
			assert_true(TrackScenery._clear_of_track(s.position, m.track.centerline, half + 60.0))
	assert_gt(props, 10, "variant props placed")
	assert_gt(m.scenery.sway_count(), 0, "tall props sway")


## The Raceway and Tabletop Mayhem: big props (boards, pit building, giant
## pencils, cards, paperclips) keep their whole display size off every road.
func test_new_environment_landmarks_stay_off_the_road() -> void:
	for layout_id in DevLayouts.PLAYER_LAYOUTS:
		for v in [4, 5]:
			var m: Node2D = MAIN_SCENE.instantiate()
			m.track_variant = v
			m.use_command_line_layout = false
			m.layout_override = DevLayouts.load_layout(layout_id)
			add_child_autofree(m)
			await wait_physics_frames(1)
			var theme: TrackTheme = m.track.theme
			var half_max := 0.0
			for h in m.track.half_widths:
				half_max = maxf(half_max, h)
			assert_gt(m.scenery.landmark_count(), 10, "%s / %d landmarks" % [layout_id, v])
			for s in m.scenery.get_children():
				if not (s is Sprite2D):
					continue
				var size: Vector2 = s.texture.get_size() * s.scale
				# every corner of the sprite stays off the road surface
				for fx in [-0.5, 0.5]:
					for fy in [-0.5, 0.5]:
						var corner: Vector2 = s.position + Vector2(size.x * fx, size.y * fy).rotated(s.rotation)
						assert_true(TrackScenery._clear_of_track(corner, m.track.centerline, half_max - 2.0),
							"%s / %d: %s at %s overlaps the road" % [layout_id, v, s.texture.resource_path, s.position])
			if theme.kerbs:
				assert_gt(m.scenery.kerb_count(), 20, "kerbs on the corners")
			m.queue_free()
			await wait_physics_frames(1)


func test_title_cycles_and_remembers_the_track() -> void:
	var settings := AudioSettings.new(SETTINGS)
	var title := TitleScreen.new()
	add_child_autofree(title)
	title.setup(AssetResolver.new("user://no_overrides_here"), settings)
	assert_eq(title.track_variant, 1)
	assert_string_contains(title._track_button.text, TrackTheme.load_variant(1).display_name.to_upper())
	title._cycle_track()
	assert_eq(title.track_variant, 2)
	var track: Track = title._backdrop.get_child(0)
	assert_eq(track.theme.variant, 2, "backdrop shows the chosen variant")
	for k in TrackTheme.VARIANT_COUNT - 1:
		title._cycle_track()
	assert_eq(title.track_variant, 1, "wraps")
	title._cycle_track()
	var again := TitleScreen.new()
	add_child_autofree(again)
	again.setup(AssetResolver.new("user://no_overrides_here"), settings)
	assert_eq(again.track_variant, 2, "saved")
	title.stop_audio()
	again.stop_audio()


func test_experimental_layout_builds_with_any_theme() -> void:
	for variant in [1, 2, 3]:
		var m: Node2D = MAIN_SCENE.instantiate()
		m.presentation_enabled = false
		m.track_variant = variant
		m.layout_override = load("res://src/track/layouts/exp_figure8_01.tres")
		add_child_autofree(m)
		await wait_physics_frames(1)
		assert_eq(m.track.layout, m.layout_override)
		assert_almost_eq(m.track.path.length, 7358.0, 2.0)
		assert_string_contains(m.hud_track_name, "Experimental")
		assert_eq(m.track.theme.variant, variant, "visual theme independent of the layout")
	assert_false(FileAccess.get_file_as_string("res://src/track/track_theme.gd").contains("DevLayouts"), "layouts are not themes")
