extends GutTest
## AssetResolver contract (assets/README.md): override precedence, missing and invalid
## fallback, supported format, override-root selection, caching, catalogue coverage.

const BODY := "cars/body_player"

var _root: String


func before_each() -> void:
	CarArt.clear_cache()
	_root = OS.get_user_data_dir().path_join("test_overrides_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(_root.path_join("graphics/cars"))


func after_each() -> void:
	AssetResolver.templates_only = false
	CarArt.clear_cache()
	_remove_dir(_root)


func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_remove_dir(path.path_join(sub))
	for file in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(path)


func _write_png(rel: String, size: Vector2i) -> void:
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color.MAGENTA)
	img.save_png(_root.path_join(rel))


func _write_bytes(rel: String, bytes: PackedByteArray) -> void:
	var f := FileAccess.open(_root.path_join(rel), FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()


func test_valid_png_override_takes_precedence() -> void:
	_write_png("graphics/cars/body_player.png", Vector2i(256, 144))
	var tex := AssetResolver.new(_root).get_texture(BODY)
	assert_eq(tex.get_size(), Vector2(256, 144))


func test_missing_override_uses_template() -> void:
	var tex := AssetResolver.new(_root).get_texture(BODY)
	assert_not_null(tex)
	assert_eq(tex.resource_path, "res://assets/graphics/cars/template_body_player.png")


func test_non_png_content_falls_back_with_warning() -> void:
	_write_bytes("graphics/cars/body_player.png", "not an image".to_utf8_buffer())
	var tex := AssetResolver.new(_root).get_texture(BODY)
	assert_eq(tex.resource_path, "res://assets/graphics/cars/template_body_player.png")
	assert_push_warning_count(1)


func test_corrupt_png_falls_back_with_warning() -> void:
	var bytes := PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3, 4])
	_write_bytes("graphics/cars/body_player.png", bytes)
	var tex := AssetResolver.new(_root).get_texture(BODY)
	assert_eq(tex.resource_path, "res://assets/graphics/cars/template_body_player.png")
	assert_push_warning_count(1)
	# The engine's PNG decoder logs its own error for the corrupt buffer.
	for e in get_errors():
		e.handled = true


func test_unsupported_extension_is_not_used() -> void:
	_write_png("graphics/cars/body_player.jpg", Vector2i(8, 8))
	var tex := AssetResolver.new(_root).get_texture(BODY)
	assert_eq(tex.resource_path, "res://assets/graphics/cars/template_body_player.png")


func test_results_are_cached_for_the_session() -> void:
	var r := AssetResolver.new(_root)
	var first := r.get_texture(BODY)
	_write_png("graphics/cars/body_player.png", Vector2i(16, 16))
	assert_same(r.get_texture(BODY), first, "changes apply after restart only")


func test_override_root_selection() -> void:
	assert_eq(AssetResolver.compute_override_root(true, "/opt/godot/godot", "/proj/custom"), "/proj/custom")
	assert_eq(AssetResolver.compute_override_root(false, "/games/HyperCars/HyperCars.x86_64", "/proj/custom"),
		"/games/HyperCars/custom")
	assert_eq(AssetResolver.compute_override_root(false, "C:/Games/HyperCars/HyperCars.exe", "/proj/custom"),
		"C:/Games/HyperCars/custom")


func test_default_root_in_editor_is_project_custom_folder() -> void:
	if not OS.has_feature("editor"):
		pending("Only meaningful when running with the editor binary")
		return
	assert_eq(AssetResolver.new().override_root, ProjectSettings.globalize_path("res://custom"))


func test_fallback_path_mapping() -> void:
	assert_eq(AssetResolver.fallback_path("track/tarmac"), "res://assets/graphics/track/template_tarmac.png")
	assert_eq(AssetResolver.fallback_path("logo"), "res://assets/graphics/template_logo.png")


func test_every_catalogued_asset_has_a_template_of_declared_size() -> void:
	var r := AssetResolver.new(_root)
	for logical_name in AssetCatalog.SPECS:
		if AssetCatalog.is_legacy(logical_name):
			continue  # (legacy flattened cars: the user's drawings only, no template)
		var template := load(AssetResolver.fallback_path(logical_name)) as Texture2D
		assert_not_null(template, logical_name)
		if template != null:
			assert_eq(Vector2i(template.get_size()), AssetCatalog.SPECS[logical_name].template_size, logical_name)
		var tex := r.get_texture(logical_name)  # (the template, or the user's own drawing: any size, same shape)
		if tex != null and template != null:
			assert_almost_eq(tex.get_size().aspect(), template.get_size().aspect(), 0.02, "%s: same aspect ratio" % logical_name)


func test_override_of_any_resolution_scales_to_display_size() -> void:
	var display: Vector2 = AssetCatalog.SPECS[BODY].display_size
	_write_png("graphics/cars/body_player.png", Vector2i(512, 288))
	var tex := AssetResolver.new(_root).get_texture(BODY)
	assert_eq(Vector2(tex.get_size()) * AssetCatalog.scale_for(tex, display), display)


# --- P2: car bodies, shared wheel and the flattened-car fallback ---

func test_template_cars_use_wheel_free_bodies_with_wheels() -> void:
	var r := AssetResolver.new(_root)
	var look := CarArt.look(r, "cars/car_ai_3")
	assert_true(look.wheels)
	assert_eq(look.body_logical, "cars/body_ai_3")
	assert_eq(look.body, r.get_texture("cars/body_ai_3"))
	var icon := CarArt.icon(r, "cars/car_ai_3")
	assert_ne(icon, r.get_texture("cars/car_ai_3"), "icons: the racing body with its wheels, never the legacy picture")
	assert_eq(icon.get_size(), look.body.get_size())


func test_custom_flattened_car_is_drawn_alone_without_extra_wheels() -> void:
	_write_png("graphics/cars/car_player.png", Vector2i(256, 144))
	var r := AssetResolver.new(_root)
	assert_true(r.has_override("cars/car_player"))
	var look := CarArt.look(r, "cars/car_player")
	assert_false(look.wheels, "wheels are painted in: no duplicates")
	assert_eq(look.body.get_width(), 256, "the user's image")
	assert_eq(CarArt.icon(r, "cars/car_player").get_width(), 256)


func test_custom_body_gets_the_shared_wheels() -> void:
	_write_png("graphics/cars/car_player.png", Vector2i(256, 144))
	_write_png("graphics/cars/body_player.png", Vector2i(512, 288))
	var r := AssetResolver.new(_root)
	var look := CarArt.look(r, "cars/car_player")
	assert_true(look.wheels, "a body takes precedence over a flattened image")
	assert_eq(look.body.get_width(), 512)
	assert_eq(CarArt.icon(r, "cars/car_player").get_width(), 512, "icon: the same body (with wheels), not the older flattened image")


func test_custom_body_only_is_also_the_icon() -> void:
	_write_png("graphics/cars/body_ai_1.png", Vector2i(128, 72))
	var r := AssetResolver.new(_root)
	assert_true(CarArt.look(r, "cars/car_ai_1").wheels)
	var icon := CarArt.icon(r, "cars/car_ai_1")
	assert_eq(icon.get_image().get_pixel(64, 36), Color.MAGENTA, "the user's body (composed with the wheels: test_car_art.gd)")


func test_invalid_custom_body_falls_back_to_the_template_body() -> void:
	var f := FileAccess.open(_root.path_join("graphics/cars/body_ai_2.png"), FileAccess.WRITE)
	f.store_string("not a png")
	f.close()
	var r := AssetResolver.new(_root)
	assert_false(r.has_override("cars/body_ai_2"))
	var look := CarArt.look(r, "cars/car_ai_2")
	assert_true(look.wheels)
	assert_eq(look.body.get_width(), 128, "template body")


func test_users_packaged_drawings_replace_the_templates() -> void:
	# the user's uploads (2026-11-20): stars, crash, tombstone, grid box
	var r := AssetResolver.new(_root)
	for logical in [AssetCatalog.STAR_GOLD, AssetCatalog.STAR_SILVER, AssetCatalog.STAR_BRONZE, AssetCatalog.CRASH,
			AssetCatalog.TOMBSTONE, AssetCatalog.GRID_BOX]:
		assert_eq(r.get_texture(logical).resource_path, "res://assets/graphics/%s.png" % logical, "%s: the user's drawing" % logical)
		assert_true(r.has_user_art(logical))
		assert_false(r.has_override(logical), "(a packaged drawing, not a custom/ override)")
	assert_eq(r.get_texture(AssetCatalog.TICKET).resource_path, "res://assets/graphics/ui/template_ticket.png", "no drawing yet: the template")


func test_a_custom_override_still_beats_a_packaged_drawing() -> void:
	DirAccess.make_dir_recursive_absolute(_root.path_join("graphics/ui"))
	_write_png("graphics/ui/star_gold.png", Vector2i(48, 48))
	var r := AssetResolver.new(_root)
	assert_true(r.has_override(AssetCatalog.STAR_GOLD))
	assert_eq(r.get_texture(AssetCatalog.STAR_GOLD).get_width(), 48, "custom/ first, next to the exported game too")



# --- legacy flattened cars and the Artwork Mode ---

func test_legacy_flattened_cars_have_no_template_and_never_error() -> void:
	var r := AssetResolver.new(_root)
	for name in ["cars/car_player", "cars/car_player_2", "cars/car_junker", "cars/car_ai_1", "cars/car_ai_9"]:
		assert_false(ResourceLoader.exists(AssetResolver.fallback_path(name)), "%s: no packaged picture with painted wheels" % name)
		assert_null(r.get_texture(name), "%s: nothing to show without the user's own drawing" % name)
		assert_false(r.has_user_art(name))
	assert_true(CarArt.look(r, "cars/car_player").wheels, "the race draws the body with its wheels")


func test_original_templates_mode_ignores_every_user_drawing() -> void:
	_write_png("graphics/cars/body_player.png", Vector2i(256, 144))
	DirAccess.make_dir_recursive_absolute(_root.path_join("graphics/ui"))
	_write_png("graphics/ui/ticket.png", Vector2i(96, 96))
	AssetResolver.templates_only = true
	var r := AssetResolver.new(_root)
	assert_eq(r.get_texture(BODY).resource_path, "res://assets/graphics/cars/template_body_player.png", "custom/ ignored")
	assert_eq(r.get_texture(AssetCatalog.STAR_GOLD).resource_path, "res://assets/graphics/ui/template_star_gold.png",
		"the user's packaged drawing ignored")
	assert_false(r.has_user_art(AssetCatalog.STAR_GOLD))
	CarArt.clear_cache()
	assert_eq(CarArt.look(r, AssetCatalog.CAR_PLAYER).body.resource_path, "res://assets/graphics/cars/template_body_player.png")
	AssetResolver.templates_only = false
	var custom := AssetResolver.new(_root)
	assert_eq(custom.get_texture(BODY).get_width(), 256, "Custom mode (default): the user's drawing again")
	assert_eq(custom.get_texture(AssetCatalog.STAR_GOLD).resource_path, "res://assets/graphics/ui/star_gold.png")


func test_artwork_mode_is_a_saved_setting() -> void:
	var path := _root.path_join("settings.cfg")
	var a := AudioSettings.new(path)
	assert_false(a.original_artwork, "Custom by default")
	a.original_artwork = true
	a.save_settings()
	var b := AudioSettings.new(path)
	b.load_settings()
	assert_true(b.original_artwork)
