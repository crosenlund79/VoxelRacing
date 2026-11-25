extends GutTest
## The artwork inventory agrees with itself (2026-11-23): every catalogued
## picture has its template on disk; every template on disk belongs to a
## catalogued picture (nothing orphaned or loaded around the resolver); every
## plain-named user drawing in assets/graphics matches a catalogued name (so
## it really replaces something); the artist's master list and the asset
## specs name exactly the catalogued pictures. Read-only: nothing is written.

const ROOT := "res://assets/graphics"


## Every PNG under assets/graphics, as paths relative to it ("cars/template_wheel.png").
func _pngs(dir: String = "") -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(ROOT.path_join(dir))
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".png"):
			out.append(dir.path_join(f) if dir != "" else f)
	for sub in d.get_directories():
		out.append_array(_pngs(dir.path_join(sub) if dir != "" else sub))
	return out


## "cars/template_wheel.png" -> "cars/wheel"; "ui/crash.png" -> "ui/crash".
static func _logical(rel: String) -> String:
	var dir := rel.get_base_dir()
	var name := rel.get_file().get_basename().trim_prefix("template_")
	return dir.path_join(name) if dir != "" else name


func test_every_catalogued_picture_has_its_template() -> void:
	for name in AssetCatalog.SPECS:
		if AssetCatalog.is_legacy(name) or not AssetCatalog.SPECS[name].has("template_size"):
			continue
		assert_true(ResourceLoader.exists(AssetResolver.fallback_path(name)), "template for %s" % name)


func test_every_picture_on_disk_is_catalogued() -> void:
	var files := _pngs()
	assert_gt(files.size(), 50)
	for rel in files:
		var logical := _logical(rel)
		assert_true(AssetCatalog.SPECS.has(logical), "%s on disk is catalogued as %s (else nothing would ever load it)" % [rel, logical])
		if not rel.get_file().begins_with("template_"):
			assert_true(AssetCatalog.SPECS.has(logical), "user drawing %s replaces the catalogued %s" % [rel, logical])


func test_master_list_and_specs_match_the_catalogue() -> void:
	var master := FileAccess.get_file_as_string("res://docs/ARTWORK_MASTER_LIST.md")
	var specs := FileAccess.get_file_as_string("res://docs/ASSET_SPECS.md")
	assert_ne(master, "", "the master list is readable")
	for name in AssetCatalog.SPECS:
		assert_string_contains(master, "`%s`" % name, "master list names %s" % name)
		if AssetCatalog.SPECS[name].has("template_size"):
			assert_string_contains(specs, "custom/graphics/%s.png" % name, "asset specs give the override path of %s" % name)
	# and names nothing that is not catalogued (rows start with a backticked logical name)
	var rx := RegEx.new()
	rx.compile("(?m)^\\| `([a-z0-9_]+(?:/[a-z0-9_]+)+)` \\|")
	for m in rx.search_all(master):
		assert_true(AssetCatalog.SPECS.has(m.get_string(1)), "master list row %s is catalogued" % m.get_string(1))


## The new replaceable picture of this pass follows the three-level contract:
## custom/ override > the user's packaged drawing > Claude's template, and the
## Original Templates artwork mode shows the template.
func test_the_wear_picture_follows_the_artwork_contract() -> void:
	var root := ProjectSettings.globalize_path("user://test_run/wear_art_%d" % randi())
	DirAccess.make_dir_recursive_absolute(root.path_join("graphics/fx"))
	var img := Image.create(256, 144, false, Image.FORMAT_RGBA8)  # any resolution, same aspect
	img.fill(Color(0, 1, 0, 0.5))
	img.save_png(root.path_join("graphics/fx/car_wear.png"))
	var with_override := AssetResolver.new(root)
	assert_true(with_override.has_override(AssetCatalog.CAR_WEAR), "custom/graphics/fx/car_wear.png wins")
	assert_eq(with_override.get_texture(AssetCatalog.CAR_WEAR).get_width(), 256)
	var plain := AssetResolver.new(ProjectSettings.globalize_path("user://test_run/no_such_custom_%d" % randi()))
	assert_eq(plain.get_texture(AssetCatalog.CAR_WEAR).resource_path, "res://assets/graphics/fx/template_car_wear.png",
		"no drawing: the template (no packaged user drawing exists for it yet)")
	AssetResolver.templates_only = true
	var original := AssetResolver.new(root)
	assert_eq(original.get_texture(AssetCatalog.CAR_WEAR).resource_path, "res://assets/graphics/fx/template_car_wear.png",
		"Original Templates mode ignores the user's drawing")
	AssetResolver.templates_only = false
	DirAccess.remove_absolute(root.path_join("graphics/fx/car_wear.png"))
