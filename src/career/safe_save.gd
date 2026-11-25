class_name SafeSave
extends RefCounted
## Durable ConfigFile saving for progress that must survive a crash or power
## loss mid-write: the file is written to "<path>.tmp" first and then renamed
## over the real one, so the real file is always either the old or the new
## version, never half written. load() falls back to the temporary file when
## the real one is missing or unreadable (a crash between writing and renaming).


static func save(cfg: ConfigFile, path: String) -> Error:
	var tmp := path + ".tmp"
	var err := cfg.save(tmp)
	if err != OK:
		return err
	var real := ProjectSettings.globalize_path(path)
	var tmp_real := ProjectSettings.globalize_path(tmp)
	err = DirAccess.rename_absolute(tmp_real, real)
	if err != OK:  # (a platform that will not rename over an existing file)
		DirAccess.remove_absolute(real)
		err = DirAccess.rename_absolute(tmp_real, real)
	return err


## OK when the file (or its leftover temporary copy) loaded.
static func load(cfg: ConfigFile, path: String) -> Error:
	if cfg.load(path) == OK:
		return OK
	cfg.clear()
	return cfg.load(path + ".tmp")


static func remove(path: String) -> void:
	for p in [path, path + ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
