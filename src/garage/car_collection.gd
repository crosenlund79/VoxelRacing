class_name CarCollection
extends RefCounted
## Rival cars the player has won (Championship reward), kept between game
## sessions (user://car_collection.cfg). A won car belongs to the player: its
## original owner races a battered junker from then on. All cars perform the
## same; this is about ownership and looks only.

const DEFAULT_PATH := "user://car_collection.cfg"
## The player's own (original) car.
const OWN_CAR := 0

var path: String
## Rival racer ids (1..9) whose cars the player owns, in the order won.
var owned: Array[int] = []
## Championships started so far (the next one's schedule rotates with it).
var championships_run := 0
## Racing for Keeps: the won car the player entered the running championship
## with (0 = none / the own car, which is never at stake). Saved, so quitting
## the game does not escape it: an open stake found at the next start is a
## forfeit (forfeited_on_load says which car went back).
var stake := 0
var forfeited_on_load := 0
## Racing for Keeps in the career: the won car its running championship was
## entered with. Kept across launches while the career championship is saved
## between rounds; the career decides when it is lost (a lost or forfeited
## attempt, including closing the game mid-race: Career.forfeited_on_load).
var career_stake := 0


## Where a store without an explicit path saves (tests point this at a
## throw-away file so they never touch the player's own).
static var default_path := DEFAULT_PATH


func _init(p_path: String = "") -> void:
	path = p_path if p_path != "" else default_path
	load_from_disk()


func load_from_disk() -> void:
	owned.clear()
	championships_run = 0
	stake = 0
	career_stake = 0
	var cfg := ConfigFile.new()
	if SafeSave.load(cfg, path) != OK:
		return
	championships_run = maxi(0, int(cfg.get_value("cars", "championships_run", 0)))
	for id in cfg.get_value("cars", "owned", []):
		if int(id) >= 1 and int(id) <= 9 and not owned.has(int(id)):
			owned.append(int(id))
	stake = int(cfg.get_value("cars", "stake", 0))
	career_stake = int(cfg.get_value("cars", "career_stake", 0))
	if not owned.has(career_stake):
		career_stake = 0
	if stake > 0:  # a championship for keeps was left unfinished (game closed): forfeited
		forfeited_on_load = stake
		lose(stake)


func save() -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value("cars", "owned", owned)
	cfg.set_value("cars", "championships_run", championships_run)
	cfg.set_value("cars", "stake", stake)
	cfg.set_value("cars", "career_stake", career_stake)
	return SafeSave.save(cfg, path)


func owns(rival_id: int) -> bool:
	return owned.has(rival_id)


## A rival now drives the junker (the player won their car).
func displaced(rival_id: int) -> bool:
	return owned.has(rival_id)


func all_owned() -> bool:
	return owned.size() >= 9


## Cars the player can choose: the own car first, then the won ones.
func choices() -> Array[int]:
	var out: Array[int] = [OWN_CAR]
	out.append_array(owned)
	return out


## Championship reward: one random rival car the player does not own yet
## (saved at once). Returns its racer id, or -1 when all nine are owned.
## Championship reward (2026-11-23): the car of the lowest-ranked rival in the
## final standings (championship order, best first) whose car is not owned
## yet - deterministic, never a duplicate. A rival missing from the standings
## counts as below everyone. -1 when all nine are owned (collection complete).
func claim_lowest(standings: Array) -> int:
	var order: Array[int] = []
	for id in range(1, 10):
		if not standings.has(id):
			order.append(id)  # (not ranked: below every ranked rival)
	var ranked := standings.duplicate()
	ranked.reverse()
	for id in ranked:
		if int(id) >= 1 and int(id) <= 9:
			order.append(int(id))
	for id in order:
		if not owned.has(id):
			owned.append(id)
			save()
			return id
	return -1


## A championship started: the next one uses the next schedule (saved).
func count_championship() -> void:
	championships_run += 1
	save()


## Racing for Keeps: enter a championship with this car (0: nothing at stake).
func put_at_stake(car: int) -> void:
	stake = car if owns(car) else 0
	save()


## The championship ended without losing the car (won, or entered with the own car).
func clear_stake() -> void:
	stake = 0
	save()


## The player loses a won car: it goes back to its rival (who drops the
## junker) and can be won again later. The own car (0) can never be lost.
func lose(car: int) -> void:
	owned.erase(car)
	if stake == car:
		stake = 0
	if career_stake == car:
		career_stake = 0
	save()


## Career: enter a championship with this car (0 / not owned: nothing at stake).
func put_career_stake(car: int) -> void:
	career_stake = car if owns(car) else 0
	save()


func clear_career_stake() -> void:
	career_stake = 0
	save()


## Forget everything (tests, a reset).
func clear() -> void:
	owned.clear()
	championships_run = 0
	stake = 0
	career_stake = 0
	forfeited_on_load = 0
	save()
