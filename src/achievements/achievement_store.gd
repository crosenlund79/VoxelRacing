class_name AchievementStore
extends RefCounted
## Persistent achievement state (M3.5 Stage 4), one small ConfigFile per
## installation: unlocked achievements (with their date), a few cross-race
## progress values, and each rival's career statistics. No race logs.
## Only the achievement tracker writes here; nothing in the race reads it.

signal unlocked(id: String)

const DEFAULT_PATH := "user://achievements.cfg"
const RIVAL_IDS := [1, 2, 3, 4, 5, 6, 7, 8, 9]

var path: String
## id -> unix time of unlock.
var unlocked_at: Dictionary = {}
## Cross-race values (see AchievementTracker): name -> int / bool.
var progress: Dictionary = {}
## racer id -> {races, wins, podiums, positions[10], winless_streak, podiums_since_win, longest_winless}
var rivals: Dictionary = {}


## Where a store without an explicit path saves (tests point this at a
## throw-away file so they never touch the player's own).
static var default_path := DEFAULT_PATH


func _init(p_path: String = "") -> void:
	path = p_path if p_path != "" else default_path
	_clear()


func load_store() -> void:
	_clear()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	for id in cfg.get_section_keys("unlocked") if cfg.has_section("unlocked") else PackedStringArray():
		if not AchievementCatalog.entry(id).is_empty():
			unlocked_at[id] = int(cfg.get_value("unlocked", id, 0))
	for key in cfg.get_section_keys("progress") if cfg.has_section("progress") else PackedStringArray():
		progress[key] = cfg.get_value("progress", key)
	for rid in RIVAL_IDS:
		var saved = cfg.get_value("rivals", str(rid), null)
		if saved is Dictionary:
			var r: Dictionary = rivals[rid]
			for k in r:
				if saved.has(k):
					r[k] = saved[k]
			if not (r.positions is Array) or r.positions.size() != 10:
				r.positions = _zeros(10)


func save() -> void:
	var cfg := ConfigFile.new()
	for id in unlocked_at:
		cfg.set_value("unlocked", id, unlocked_at[id])
	for key in progress:
		cfg.set_value("progress", key, progress[key])
	for rid in rivals:
		cfg.set_value("rivals", str(rid), rivals[rid])
	cfg.save(path)


## Unlocks once; returns true only the first time (and announces it).
func unlock(id: String) -> bool:
	if unlocked_at.has(id) or AchievementCatalog.entry(id).is_empty():
		return false
	unlocked_at[id] = int(Time.get_unix_time_from_system())
	unlocked.emit(id)
	return true


func is_unlocked(id: String) -> bool:
	return unlocked_at.has(id)


func unlocked_count() -> int:
	return unlocked_at.size()


func get_progress(key: String, default: Variant = 0) -> Variant:
	return progress.get(key, default)


func set_progress(key: String, value: Variant) -> void:
	progress[key] = value


## Erases achievements, progress and rival careers (after the player confirms).
func reset() -> void:
	_clear()
	save()


func _clear() -> void:
	unlocked_at = {}
	progress = {}
	rivals = {}
	for rid in RIVAL_IDS:
		rivals[rid] = {"races": 0, "wins": 0, "podiums": 0, "positions": _zeros(10), "winless_streak": 0,
			"podiums_since_win": 0, "longest_winless": 0}


static func _zeros(n: int) -> Array:
	var a := []
	a.resize(n)
	a.fill(0)
	return a
