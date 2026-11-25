extends GutHookScript
## Runs once before the suite: every store the game writes without an explicit
## path (settings, controls, achievements, car collection, garage) goes to a
## throw-away test folder, so running the tests never touches the player's own
## files. The folder starts empty each run.

const DIR := "user://test_run/"


func run() -> void:
	var abs_dir := ProjectSettings.globalize_path(DIR)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	for f in DirAccess.get_files_at(abs_dir):
		DirAccess.remove_absolute(abs_dir.path_join(f))
	AudioSettings.default_path = DIR + "settings.cfg"
	ControlBindings.path = DIR + "controls.cfg"
	AchievementStore.default_path = DIR + "achievements.cfg"
	CarCollection.default_path = DIR + "car_collection.cfg"
	RivalMemory.default_path = DIR + "rival_memory.cfg"
	PlayerGarage.default_path = ""  # garage careers are not saved unless a test asks
