class_name RivalMemory
extends RefCounted
## The game remembers a few memorable moments between the player and each
## rival (Nemesis Welcome, 2026-11-17), so a rival can occasionally greet the
## player at the title with a short taunt about something that really
## happened. Only facts from authoritative results are recorded (the race's
## own combat statistics and finishing times, the championship car
## collection); nothing is ever invented or reconstructed from older saves.
## Bounded: the newest MAX_EVENTS events are kept.
##
## Saved in user://rival_memory.cfg (tests: a scratch path). A missing or
## unreadable file is simply an empty memory.

const DEFAULT_PATH := "user://rival_memory.cfg"
const MAX_EVENTS := 24
## Event kinds (the rival's point of view decides the mood).
const TOOK_YOU_OUT := "took_you_out"          ## the rival caused the player's DNF
const YOU_TOOK_ME_OUT := "you_took_me_out"    ## the player caused the rival's DNF
const BEAT_YOU_CLOSE := "beat_you_close"      ## the rival won, the player second by < CLOSE_GAP
const YOU_BEAT_ME_CLOSE := "you_beat_me_close"  ## the player won, the rival second by < CLOSE_GAP
const WON_MY_CAR := "won_my_car"              ## the player won the rival's car (championship)
const TOOK_CAR_BACK := "took_car_back"        ## the rival reclaimed its car (Racing for Keeps)
const KINDS := [TOOK_YOU_OUT, YOU_TOOK_ME_OUT, BEAT_YOU_CLOSE, YOU_BEAT_ME_CLOSE, WON_MY_CAR, TOOK_CAR_BACK]
const SMUG := [TOOK_YOU_OUT, BEAT_YOU_CLOSE, TOOK_CAR_BACK]
## A finish this close (s) between first and second counts as memorable.
const CLOSE_GAP := 1.0
## Weight of each kind when choosing a greeting.
const SIGNIFICANCE := {TOOK_YOU_OUT: 3.0, TOOK_CAR_BACK: 3.0, WON_MY_CAR: 3.0,
	YOU_TOOK_ME_OUT: 2.0, BEAT_YOU_CLOSE: 2.0, YOU_BEAT_ME_CLOSE: 2.0}
## Greetings: the chance on a launch, never two launches in a row, and the
## last few greeted events are not used again.
const GREET_CHANCE := 0.35
const NO_REPEAT := 3
## Older events count less: weight x RECENCY per newer event.
const RECENCY := 0.8

## Where a memory without an explicit path saves (tests point it elsewhere).
static var default_path := DEFAULT_PATH

var path: String
## Oldest first. Each: {id, kind, rival, weapon, circuit, lap, laps, mode, gap, time, test}.
var events: Array = []
var _next_id := 1
## Event ids greeted recently (newest last), and whether the last launch greeted.
var greeted: Array = []
var greeted_last_launch := false


func _init(p_path: String = "") -> void:
	path = p_path if p_path != "" else default_path


func load_from_disk() -> void:
	events = []
	greeted = []
	_next_id = 1
	greeted_last_launch = false
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	var saved: Variant = cfg.get_value("memory", "events", [])
	if saved is Array:
		for e in saved:
			if e is Dictionary and KINDS.has(e.get("kind", "")) and int(e.get("rival", 0)) >= 1 \
					and int(e.get("rival", 0)) <= RivalRoster.count():
				events.append(e)
				_next_id = maxi(_next_id, int(e.get("id", 0)) + 1)
	var g: Variant = cfg.get_value("memory", "greeted", [])
	greeted = g if g is Array else []
	greeted_last_launch = bool(cfg.get_value("memory", "greeted_last_launch", false))


func save() -> Error:
	if path.is_empty():
		return OK
	var cfg := ConfigFile.new()
	cfg.set_value("memory", "events", events)
	cfg.set_value("memory", "greeted", greeted)
	cfg.set_value("memory", "greeted_last_launch", greeted_last_launch)
	return cfg.save(path)


## Records one event (bounded: the oldest goes when full). context keys:
## weapon (WeaponRules.Weapon, or CombatStats.COLLISION), circuit, lap, laps,
## mode, gap. test: seeded test data (screenshots), never written by the game.
func add(kind: String, rival: int, context: Dictionary = {}, test := false) -> Dictionary:
	if not KINDS.has(kind) or rival < 1 or rival > RivalRoster.count():
		return {}
	var e := {"id": _next_id, "kind": kind, "rival": rival, "weapon": int(context.get("weapon", WeaponRules.Weapon.NONE)),
		"circuit": String(context.get("circuit", "")), "lap": int(context.get("lap", 0)),
		"laps": int(context.get("laps", 0)), "mode": String(context.get("mode", "")),
		"gap": snappedf(float(context.get("gap", 0.0)), 0.1), "time": int(Time.get_unix_time_from_system())}
	if test:
		e["test"] = true
	_next_id += 1
	events.append(e)
	while events.size() > MAX_EVENTS:
		events.pop_front()
	return e


## The memorable moments of one finished race, from its own results:
## feed: CombatStats.feed (tombstones = DNFs caused, with attacker and weapon);
## finish: [[id, finish_time, finished, dnf], ...] in finishing order (first =
## the winner); laps_at_out: per car, laps completed when it retired.
## player: the human's racer id. Returns the events added.
func record_race(feed: Array, finish: Array, laps_at_out: Dictionary, player: int, context: Dictionary) -> Array:
	var added: Array = []
	for f in feed:
		if not f.get("tombstone", false):
			continue
		var attacker: int = f.get("attacker", -1)
		var victim: int = f.get("victim", -1)
		var ctx := context.duplicate()
		ctx["weapon"] = f.get("weapon", WeaponRules.Weapon.NONE)
		ctx["lap"] = int(laps_at_out.get(victim, 0)) + 1
		if victim == player and attacker >= 1:
			added.append(add(TOOK_YOU_OUT, attacker, ctx))
		elif attacker == player and victim >= 1:
			added.append(add(YOU_TOOK_ME_OUT, victim, ctx))
	if finish.size() >= 2:
		var first: Array = finish[0]
		var second: Array = finish[1]
		if first[2] and second[2] and not first[3] and not second[3]:
			var gap: float = float(second[1]) - float(first[1])
			if gap >= 0.0 and gap < CLOSE_GAP:
				var ctx := context.duplicate()
				ctx["gap"] = gap
				if first[0] >= 1 and second[0] == player:
					added.append(add(BEAT_YOU_CLOSE, first[0], ctx))
				elif first[0] == player and second[0] >= 1:
					added.append(add(YOU_BEAT_ME_CLOSE, second[0], ctx))
	return added.filter(func(e: Dictionary) -> bool: return not e.is_empty())


## A greeting for this launch, or {} (most launches). Chooses among the
## remembered events by significance and recency, never the last few greeted
## ones, and never on two launches in a row. Marks the choice as greeted.
func pick_greeting(rng: RandomNumberGenerator) -> Dictionary:
	var candidates: Array = []
	var weights: Array = []
	var n := events.size()
	for i in n:
		var e: Dictionary = events[i]
		if greeted.has(int(e.id)):
			continue
		candidates.append(e)
		weights.append(float(SIGNIFICANCE.get(e.kind, 1.0)) * pow(RECENCY, n - 1 - i))
	var greet := not greeted_last_launch and not candidates.is_empty() and rng.randf() < GREET_CHANCE
	greeted_last_launch = greet
	if not greet:
		return {}
	var total := 0.0
	for w in weights:
		total += w
	var pick := rng.randf() * total
	var chosen: Dictionary = candidates[candidates.size() - 1]
	for k in candidates.size():
		pick -= weights[k]
		if pick <= 0.0:
			chosen = candidates[k]
			break
	greeted.append(int(chosen.id))
	while greeted.size() > NO_REPEAT:
		greeted.pop_front()
	return chosen


static func is_smug(kind: String) -> bool:
	return SMUG.has(kind)
