class_name AchievementTracker
extends Node
## Watches completed races and unlocks achievements (M3.5 Stage 4). Read-only:
## it reads the race scene (session, grid, combat event log, car contact
## signals, drivers' counters) and writes only to its AchievementStore. It uses
## no randomness and nothing in the race reads it, so races are identical with
## or without it (proved by tests/support/sim_probe.gd achievements=1).
## A race counts once, when the race scene reports it concluded (completed
## races only); normal races and spectator races alike, at any simulation speed.

const W := WeaponRules.Weapon
const PLAYER := 0
const ROCCO := 2
const ELLIE := 3
const HANK := 4
const MAYA := 5
const DANTE := 6
const GRETA := 7
const FINN := 8
const NINA := 9
## Minimum contact speed that counts as a touch (same as the M2 validation).
const CONTACT_SPEED := 60.0
## Lead changes only count once the start has settled.
const LEAD_SETTLE_TIME := 5.0

var store: AchievementStore
var _main: Node
var _open := false
var _cursor := 0
var _grid: Array[int] = []
var _walls: Dictionary = {}
var _contacts: Dictionary = {}
var _lead_changes := 0
var _leader := -1
var _kills: Dictionary = {}
var _kill_types: Dictionary = {}
var _player_destroyed := 0
var _player_empty := 0
var _own_mine := false
var _best_mine_multi := 0
var _blast_owner := -1
var _blast_pos := Vector2.INF
var _blast_kills := 0


func setup(main: Node, p_store: AchievementStore) -> void:
	_main = main
	store = p_store
	for c in main.cars:
		var id: int = c.racer_id
		c.wall_hit.connect(func(_n: Vector2, speed: float) -> void:
			if _open and speed > CONTACT_SPEED:
				_walls[id] = _walls.get(id, 0) + 1)
		c.car_hit.connect(func(_o: Car, speed: float) -> void:
			if _open and speed > CONTACT_SPEED:
				_contacts[id] = _contacts.get(id, 0) + 1)
	main.race_began.connect(_on_race_began)
	main.race_concluded.connect(_on_race_concluded)


func _on_race_began() -> void:
	_open = true
	_cursor = 0
	_grid = _main.grid_order.duplicate()
	_walls = {}
	_contacts = {}
	_lead_changes = 0
	_leader = -1
	_kills = {}
	_kill_types = {}
	_player_destroyed = 0
	_player_empty = 0
	_own_mine = false
	_best_mine_multi = 0
	_blast_owner = -1
	_blast_kills = 0


func _physics_process(_delta: float) -> void:
	if not _open:
		return
	_read_events()
	var session: RaceSession = _main.session
	if session.state == RaceSession.State.RACING and session.elapsed > LEAD_SETTLE_TIME:
		var standings := session.standings()
		if not standings.is_empty() and not standings[0].is_finished():
			var lead := standings[0].id
			if _leader >= 0 and lead != _leader:
				_lead_changes += 1
			_leader = lead


func _read_events() -> void:
	var events: Array = _main.combat.events
	if _cursor > events.size():
		_cursor = 0
	while _cursor < events.size():
		var e: Dictionary = events[_cursor]
		_cursor += 1
		match e.kind:
			"mine_blast":
				_close_blast()
				_blast_owner = e.owner
				_blast_pos = e.pos
				_blast_kills = 0
			"destroyed":
				var from_blast: bool = e.type == W.MINE and e.owner == _blast_owner and e.pos == _blast_pos
				if not from_blast:
					_close_blast()
				if e.car == PLAYER:
					_player_destroyed += 1
					if e.owner == PLAYER and e.type == W.MINE:
						_own_mine = true
				if e.owner != e.car:
					_kills[e.owner] = _kills.get(e.owner, 0) + 1
					var types: Dictionary = _kill_types.get(e.owner, {})
					types[e.type] = types.get(e.type, 0) + 1
					_kill_types[e.owner] = types
					if from_blast:
						_blast_kills += 1
			"empty":
				if e.car == PLAYER:
					_player_empty += 1
			_:
				_close_blast()
	_close_blast()


func _close_blast() -> void:
	if _blast_owner == PLAYER:
		_best_mine_multi = maxi(_best_mine_multi, _blast_kills)
	_blast_owner = -1
	_blast_pos = Vector2.INF
	_blast_kills = 0


func _on_race_concluded(order: Array) -> void:
	if not _open:
		return
	_read_events()
	_open = false
	var session: RaceSession = _main.session
	var finish_time := {}
	var lap_times := {}
	for r in session.participants():
		finish_time[r.id] = r.finish_time
		lap_times[r.id] = r.lap_times.duplicate()
	var defends := {}
	var flusters := {}
	for id in order:
		var d: AiDriver = _main.drivers[id]
		if d != null:
			defends[id] = d.defends
			flusters[id] = d.flusters
	var summary := {
		"spectator": session.spectator, "control_mode": session.control_mode, "weapons": _main.weapons_enabled,
		"laps": session.lap_count(), "grid": _grid, "order": order, "finish_time": finish_time, "lap_times": lap_times,
		"walls": _walls, "contacts": _contacts, "lead_changes": _lead_changes, "kills": _kills, "kill_types": _kill_types,
		"player_shots": _main.combat.shots_fired[PLAYER], "player_destroyed": _player_destroyed,
		"player_empty": _player_empty, "own_mine": _own_mine, "mine_multi": _best_mine_multi,
		"defends": defends, "flusters": flusters,
	}
	for id in evaluate(summary, store):
		store.unlock(id)
	store.save()


## Applies one completed race to the store's progress and rival careers and
## returns the achievements it earns. Pure function of the summary + store.
static func evaluate(s: Dictionary, st: AchievementStore) -> Array[String]:
	var out: Array[String] = []
	var order: Array = s.order
	var grid: Array = s.grid
	var winner: int = order[0] if not order.is_empty() else -1
	var pos_of := func(id: int) -> int: return order.find(id) + 1
	var last_slot: int = grid[-1] if not grid.is_empty() else -1
	var kills: Dictionary = s.kills
	var kill_types: Dictionary = s.kill_types
	var contacts: Dictionary = s.contacts
	var walls: Dictionary = s.walls

	# --- Rival careers and witness streaks (normal and spectator races).
	for rid in AchievementStore.RIVAL_IDS:
		var p: int = pos_of.call(rid)
		if p <= 0:
			continue
		var r: Dictionary = st.rivals[rid]
		r.races += 1
		r.positions[mini(p, 10) - 1] += 1
		if p == 1:
			if r.winless_streak >= 50:
				out.append("curse_is_broken")
			r.wins += 1
			r.winless_streak = 0
			r.podiums_since_win = 0
		else:
			r.winless_streak += 1
			r.longest_winless = maxi(r.longest_winless, r.winless_streak)
		if p <= 3:
			r.podiums += 1
			if p > 1:
				r.podiums_since_win += 1
				if r.podiums_since_win >= 25:
					out.append("eternal_contender")
	var rocco_pos: int = pos_of.call(ROCCO)
	var streak: int = st.get_progress("rocco_second_streak", 0)
	streak = streak + 1 if rocco_pos == 2 else 0
	st.set_progress("rocco_second_streak", streak)
	if streak >= 3:
		out.append("always_bridesmaid")
	if winner == ROCCO:
		out.append("dog_has_its_day")
	if winner == MAYA and contacts.get(MAYA, 0) == 0:
		out.append("ghost_line")
	if winner == FINN and last_slot == FINN:
		out.append("wildcard_played")
	if winner == NINA and grid.find(NINA) >= 5:
		out.append("the_hunt")
	if winner == ELLIE and s.flusters.get(ELLIE, 0) >= 3:
		out.append("sparrow_under_fire")
	var hank_pos: int = pos_of.call(HANK)
	if hank_pos >= 1 and hank_pos <= 3 and s.defends.get(HANK, 0) >= 20:
		out.append("the_wall_holds")
	if kills.get(DANTE, 0) >= 3:
		out.append("showtime")
	if s.laps >= 7 and not s.weapons and _steady_laps(s.lap_times.get(GRETA, []), 0.15) and pos_of.call(GRETA) > 0 \
			and s.finish_time.get(GRETA, -1.0) >= 0.0:
		out.append("like_clockwork")
	if s.lead_changes >= 12:
		out.append("lead_carousel")

	if s.spectator:
		var watched: int = st.get_progress("spectator_races", 0) + 1
		st.set_progress("spectator_races", watched)
		if watched >= 10:
			out.append("armchair_expert")
		return out

	# --- The player's own race.
	var me: int = pos_of.call(PLAYER)
	var won := me == 1
	var win_streak: int = st.get_progress("player_win_streak", 0)
	win_streak = win_streak + 1 if won else 0
	st.set_progress("player_win_streak", win_streak)
	if won:
		out.append("first_flag")
		var key := "won_fire_to_brake" if s.control_mode == CarModel.ControlMode.FIRE_TO_BRAKE else "won_fire_to_accelerate"
		st.set_progress(key, true)
		if st.get_progress("won_fire_to_brake", false) and st.get_progress("won_fire_to_accelerate", false):
			out.append("both_hands")
		if last_slot == PLAYER:
			out.append("back_row_hero")
		if win_streak >= 2:
			out.append("upside_down_grid")
		if rocco_pos == 2:
			out.append("so_close_mad_dog")
		if s.weapons and s.player_shots == 0:
			out.append("pacifist")
		if s.player_destroyed >= 2:
			out.append("phoenix")
	if me >= 1 and me <= 3:
		if walls.get(PLAYER, 0) == 0 and contacts.get(PLAYER, 0) == 0:
			out.append("not_a_scratch")
		var key3 := "top3_laps_%d" % s.laps
		st.set_progress(key3, true)
		var all := true
		for laps in [3, 7, 20, 50]:
			all = all and st.get_progress("top3_laps_%d" % laps, false)
		if all:
			out.append("all_distances")
	if me >= 1 and _photo_finish(order, s.finish_time, me):
		out.append("photo_finish")
	if me >= 1 and s.laps >= 50:
		out.append("marathon")
	if me >= 1 and s.weapons and s.laps >= 20 and s.player_destroyed == 0:
		out.append("iron_will")
	var mine: Dictionary = kill_types.get(PLAYER, {})
	if mine.get(W.FRONT_MISSILE, 0) > 0:
		out.append("opening_salvo")
	if mine.get(W.MINE, 0) > 0:
		out.append("rear_view_diplomacy")
	if s.mine_multi >= 2:
		out.append("two_for_one")
	if s.own_mine:
		out.append("own_goal")
	if s.player_empty >= 5:
		out.append("click_click")
	return out


## Every flying lap (all but the first) within `spread` seconds of each other.
static func _steady_laps(laps: Array, spread: float) -> bool:
	if laps.size() < 3:
		return false
	var flying := laps.slice(1)
	return flying.max() - flying.min() <= spread


static func _photo_finish(order: Array, times: Dictionary, me: int) -> bool:
	var mine: float = times.get(PLAYER, -1.0)
	if mine < 0.0:
		return false
	for k in [me - 2, me]:
		if k >= 0 and k < order.size():
			var other: float = times.get(order[k], -1.0)
			if other >= 0.0 and absf(other - mine) <= 0.10:
				return true
	return false
