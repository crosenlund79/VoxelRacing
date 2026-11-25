extends SceneTree
## Writes the artwork catalogue (AssetCatalog.SPECS) as JSON for
## make_reference.py (docs/ARTWORK_MASTER_LIST.md and the reference sheets).
##   godot --headless --path . -s docs/artwork/dump_catalog.gd -- <out.json>
func _initialize() -> void:
	var out := {}
	for k in AssetCatalog.SPECS:
		var s: Dictionary = AssetCatalog.SPECS[k]
		out[k] = {"template_size": [s.template_size.x, s.template_size.y],
			"display_size": [s.display_size.x, s.display_size.y] if s.has("display_size") else null,
			"frames": s.get("frames", 1), "notes": s.get("notes", ""),
			"template": AssetResolver.fallback_path(k).replace("res://", "") if ResourceLoader.exists(AssetResolver.fallback_path(k)) else "",
			"user_drawing": AssetResolver.packaged_art_path(k).replace("res://", "")}
	var args := OS.get_cmdline_user_args()
	var f := FileAccess.open(args[0] if args.size() > 0 else "user://catalog.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "\t"))
	f.close()
	quit()
