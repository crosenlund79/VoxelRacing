class_name Career
extends RefCounted
## The single-player career (2026-11-22, "The Road to 1.0"): three championship
## stages raced in order - Rookie Cup, Pro Series, HyperCars Grand Championship.
## Winning a stage unlocks the next; winning the Grand Championship completes
## the career. Pure progress and records (no scenes): the races, the
## championship rules (points, countback, reversed grids), the garage and the
## car rewards are the existing systems, driven by the game root.
##
## Saved in user://career.cfg (atomically, SafeSave) at every boundary: a stage
## started, a career race started, a round finished, a stage decided. Rules:
## - Between rounds the championship is saved: quit and come back any time.
## - Leaving a career race before the flag (the race menu, or closing the game
##   while it runs: `in_race` is still set at the next start) forfeits that
##   championship attempt - no quit-and-retry of a bad race.
## - Losing (or forfeiting) a stage costs nothing else: try it again.
## - Stage bonuses are paid once, when a stage is decided (never twice).
## - NEW CAREER clears the progress and records of this career only; the
##   lifetime champion titles (Hall of Fame) remain.

const STAGES: Array[String] = [
	"res://src/career/rookie_cup.tres",
	"res://src/career/pro_series.tres",
	"res://src/career/grand_championship.tres",
]
const FINAL_STAGE := 2
const DEFAULT_PATH := "user://career.cfg"
const PLAYER := RaceSession.PLAYER_ID

## Where a career without an explicit path saves (tests: a throw-away file).
static var default_path := DEFAULT_PATH

var path: String
## A career has been started (CAREER shows CONTINUE rather than START).
var started := false
## Stages won at least once (index = stage).
var stage_won: Array[bool] = [false, false, false]
## The career is complete (the Grand Championship won), and when (YYYY-MM-DD).
var completed := false
var completed_on := ""
## The running championship (null between attempts) and its stage (-1 none).
var champ: Championship = null
var active_stage := -1
## The car the running championship was entered with (0 = the own car).
var player_car := 0
## A career race is running: still set at the next start = the game closed
## mid-race, so the attempt is forfeited (see load_from_disk).
var in_race := false
## Set by load_from_disk when an attempt was forfeited that way (-1 none).
var forfeited_on_load := -1

## Records of this career (from real results only).
var attempts: Array[int] = [0, 0, 0]
var titles: Array[int] = [0, 0, 0]
var races := 0
var race_wins := 0
var podiums := 0
var dnfs := 0
var money_won := 0
## Rival id -> career rounds won / career championships won.
var rival_wins := {}
var rival_titles := {}
## The final standings of the championship that completed the career
## (racer ids, champion first) for the Hall of Fame.
var final_standings: Array[int] = []

## Lifetime (kept through NEW CAREER): careers completed and the first date.
var careers_completed := 0
var first_completed_on := ""


func _init(p_path: String = "") -> void:
	path = p_path if p_path != "" else default_path


static func schedule(stage: int) -> ChampionshipSchedule:
	return load(STAGES[clampi(stage, 0, STAGES.size() - 1)])


static func stage_title(stage: int) -> String:
	return schedule(stage).title


## A stage can be entered once the one before it is won (the first always).
func unlocked(stage: int) -> bool:
	return stage >= 0 and stage < STAGES.size() and (stage == 0 or stage_won[stage - 1])


## The stage the career is at: the first one not yet won (the final stage once
## the career is complete).
func current_stage() -> int:
	for i in STAGES.size():
		if not stage_won[i]:
			return i
	return FINAL_STAGE


func in_championship() -> bool:
	return champ != null and not champ.finished()


## Enters a stage's championship (a new attempt). False when locked or when
## another championship is still running.
func start_stage(stage: int, car: int = 0) -> bool:
	if not unlocked(stage) or in_championship():
		return false
	started = true
	champ = Championship.new(schedule(stage))
	active_stage = stage
	player_car = car
	attempts[stage] += 1
	in_race = false
	save()
	return true


## A career race starts: from now until its result, closing the game forfeits.
func begin_race() -> void:
	if not in_championship():
		return
	in_race = true
	save()


## A round's result. Returns what it decided:
## {recorded, finished, won, stage, bonus, completed_now, champion}.
## Rewards are decided here exactly once per championship.
func record_round(order: Array, dnf: Array) -> Dictionary:
	var out := {"recorded": false, "finished": false, "won": false, "stage": active_stage, "bonus": 0,
		"completed_now": false, "champion": -1}
	if not in_championship() or order.size() != 10:
		return out
	champ.record(order, dnf)
	in_race = false
	out.recorded = true
	races += 1
	var pos := order.find(PLAYER) + 1
	if dnf.has(PLAYER):
		dnfs += 1
	elif pos == 1:
		race_wins += 1
	if not dnf.has(PLAYER) and pos >= 1 and pos <= 3:
		podiums += 1
	if not order.is_empty() and order[0] != PLAYER and not dnf.has(order[0]):
		rival_wins[int(order[0])] = int(rival_wins.get(int(order[0]), 0)) + 1
	if champ.finished():
		out.finished = true
		out.champion = champ.champion()
		var stage := active_stage
		if out.champion == PLAYER:
			out.won = true
			titles[stage] += 1
			var first := not stage_won[stage]
			stage_won[stage] = true
			out.bonus = schedule(stage).career_bonus
			money_won += out.bonus
			if stage == FINAL_STAGE and first and not completed:
				completed = true
				completed_on = Time.get_date_string_from_system()
				out.completed_now = true
				careers_completed += 1
				if first_completed_on == "":
					first_completed_on = completed_on
				final_standings = champ.standings()
		else:
			rival_titles[out.champion] = int(rival_titles.get(out.champion, 0)) + 1
		active_stage = -1  # decided: the next attempt starts from round 1
	save()
	return out


## Prize money a career race paid (garage settlement), for the records.
func add_prize(amount: int) -> void:
	money_won += maxi(0, amount)
	save()


## Gives up the running attempt (leaving a career race, or a confirmed forfeit).
## Returns the stage given up (-1: nothing was running).
func forfeit() -> int:
	if not in_championship():
		in_race = false
		return -1
	var stage := active_stage
	champ = null
	active_stage = -1
	in_race = false
	save()
	return stage


## The championship screen is done with a decided championship.
func close_championship() -> void:
	if champ != null and champ.finished():
		champ = null
		active_stage = -1
		save()


## Starts over (confirmed by the player): progress and this career's records
## go; lifetime titles stay. Achievements, won cars and the standalone garage
## are not touched (they are not career data).
func reset() -> void:
	var lifetime := [careers_completed, first_completed_on]
	_clear()
	careers_completed = lifetime[0]
	first_completed_on = lifetime[1]
	save()


func _clear() -> void:
	started = false
	stage_won = [false, false, false]
	completed = false
	completed_on = ""
	champ = null
	active_stage = -1
	player_car = 0
	in_race = false
	attempts = [0, 0, 0]
	titles = [0, 0, 0]
	races = 0
	race_wins = 0
	podiums = 0
	dnfs = 0
	money_won = 0
	rival_wins = {}
	rival_titles = {}
	final_standings = []


## The rival with the most career round wins (-1: none yet), from real results.
func top_rival() -> int:
	var best := -1
	for id in rival_wins:
		if best < 0 or int(rival_wins[id]) > int(rival_wins[best]) or (int(rival_wins[id]) == int(rival_wins[best]) and int(id) < best):
			best = int(id)
	return best


func save() -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value("career", "version", 1)
	cfg.set_value("career", "started", started)
	cfg.set_value("career", "stage_won", stage_won)
	cfg.set_value("career", "completed", completed)
	cfg.set_value("career", "completed_on", completed_on)
	cfg.set_value("career", "active_stage", active_stage if in_championship() else -1)
	cfg.set_value("career", "player_car", player_car)
	cfg.set_value("career", "in_race", in_race and in_championship())
	if in_championship():
		var r := champ.saved_rounds()
		cfg.set_value("championship", "orders", r[0])
		cfg.set_value("championship", "dnfs", r[1])
	cfg.set_value("records", "attempts", attempts)
	cfg.set_value("records", "titles", titles)
	cfg.set_value("records", "races", races)
	cfg.set_value("records", "race_wins", race_wins)
	cfg.set_value("records", "podiums", podiums)
	cfg.set_value("records", "dnfs", dnfs)
	cfg.set_value("records", "money_won", money_won)
	cfg.set_value("records", "rival_wins", rival_wins)
	cfg.set_value("records", "rival_titles", rival_titles)
	cfg.set_value("records", "final_standings", final_standings)
	cfg.set_value("lifetime", "careers_completed", careers_completed)
	cfg.set_value("lifetime", "first_completed_on", first_completed_on)
	return SafeSave.save(cfg, path)


## Loads the saved career. Missing or broken data loads as a fresh career (a
## broken running championship is dropped, never guessed). A career race that
## was running when the game closed forfeits its attempt (forfeited_on_load).
func load_from_disk() -> void:
	_clear()
	careers_completed = 0
	first_completed_on = ""
	forfeited_on_load = -1
	var cfg := ConfigFile.new()
	if SafeSave.load(cfg, path) != OK:
		return
	started = _flag(cfg.get_value("career", "started", false))
	var won = cfg.get_value("career", "stage_won", [])
	if won is Array:
		for i in mini(won.size(), STAGES.size()):
			stage_won[i] = _flag(won[i])
	completed = _flag(cfg.get_value("career", "completed", false)) and stage_won[FINAL_STAGE]
	completed_on = str(cfg.get_value("career", "completed_on", ""))
	player_car = clampi(int(cfg.get_value("career", "player_car", 0)), 0, 9)
	attempts = _ints(cfg.get_value("records", "attempts", []), 3)
	titles = _ints(cfg.get_value("records", "titles", []), 3)
	races = maxi(0, int(cfg.get_value("records", "races", 0)))
	race_wins = maxi(0, int(cfg.get_value("records", "race_wins", 0)))
	podiums = maxi(0, int(cfg.get_value("records", "podiums", 0)))
	dnfs = maxi(0, int(cfg.get_value("records", "dnfs", 0)))
	money_won = maxi(0, int(cfg.get_value("records", "money_won", 0)))
	rival_wins = _rival_counts(cfg.get_value("records", "rival_wins", {}))
	rival_titles = _rival_counts(cfg.get_value("records", "rival_titles", {}))
	var fs = cfg.get_value("records", "final_standings", [])
	if fs is Array:
		for id in fs:
			if int(id) >= 0 and int(id) <= 9:
				final_standings.append(int(id))
	careers_completed = maxi(0, int(cfg.get_value("lifetime", "careers_completed", 0)))
	first_completed_on = str(cfg.get_value("lifetime", "first_completed_on", ""))
	var stage := int(cfg.get_value("career", "active_stage", -1))
	if stage >= 0 and stage < STAGES.size() and unlocked(stage):
		var c := Championship.new(schedule(stage))
		if c.restore(cfg.get_value("championship", "orders", []), cfg.get_value("championship", "dnfs", [])) and not c.finished():
			champ = c
			active_stage = stage
	if in_championship() and _flag(cfg.get_value("career", "in_race", false)):
		forfeited_on_load = forfeit()  # the game closed during a career race


static func _flag(v: Variant) -> bool:
	return typeof(v) == TYPE_BOOL and v


static func _ints(v: Variant, n: int) -> Array[int]:
	var out: Array[int] = []
	for i in n:
		out.append(maxi(0, int(v[i])) if v is Array and i < v.size() else 0)
	return out


static func _rival_counts(v: Variant) -> Dictionary:
	var out := {}
	if v is Dictionary:
		for k in v:
			if int(k) >= 1 and int(k) <= 9:
				out[int(k)] = maxi(0, int(v[k]))
	return out
