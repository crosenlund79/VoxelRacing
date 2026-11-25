class_name NetRace
extends Node
## Network side of one race scene (M5.1, host-authoritative, LAN).
## HOST: runs the normal race; the client's driver is a RemoteDriverInput fed
## by INPUT messages; sends SETUP (grid and settings), START, a SNAP every
## SNAP_INTERVAL ticks and RESULTS. CLIENT: never simulates the race; it sends
## its player's commands every tick, readies up on the grid, and shows the
## host's snapshots, interpolating car movement. Lives as a child of the race
## scene; the NetLink (connection) is owned by whoever created the session.

enum Role { HOST, CLIENT }
## Message types ([type, ...] arrays over NetLink).
enum Msg { WELCOME, HELLO, SETUP, READY, START, SNAP, INPUT, RESULTS, EVENTS, BYE, REJECT, JOINED }

## Wire protocol version and game build: both must match before a session starts.
const PROTOCOL := 7  # 3: M6 condition / DNF in snapshots; 4: Weapons Hot lock; 5: J5 jumps; 6: pit lanes, proportional steering; 7: RESULTS carry final DNF / condition / ammunition
const GAME_BUILD := "hypercars-r2"


## Build string exchanged in WELCOME / HELLO. The track layout is not part of
## it: the host sends its layout (and theme) in WELCOME and the client uses it.
static func build_id() -> String:
	return GAME_BUILD
const SNAP_INTERVAL := 2
## Client renders this many ticks behind the newest snapshot (smoothness vs delay).
const INTERP_DELAY := 4.0
const BUFFER := 24

var link: NetLink
var role: Role
var race: Node
var peer_id := 0
## HOST: the client's driver and readiness.
var remote_input: RemoteDriverInput
var client_ready := false
var client_mode: CarModel.ControlMode = CarModel.ControlMode.FIRE_TO_ACCELERATE
## CLIENT: own readiness, press totals, snapshot buffer and render clock.
var local_ready := false
var front_total := 0
var rear_total := 0
var input_tick := 0
var snapshots: Array = []
var render_tick := -1.0
## CLIENT prediction (M5.2): the local car is driven at once by this computer's
## input with the unchanged Car / CarModel (walls only; other cars and all
## combat stay host-authoritative). Each snapshot says which of our input ticks
## the host had applied; the host's car state for that tick is compared with
## our record of the same tick and the difference is corrected: blended when
## small, applied at once when large. Corrections also shift the recorded
## history so they are never applied twice.
var predict := true
## Fraction of a small error corrected per snapshot, and the error (px) above
## which the correction is applied at once.
const BLEND := 0.3
const SNAP_DISTANCE := 64.0
const HISTORY := 180
var _history := {}
var _last_ack := -1
## Correction statistics for tests / reports: count, total and max error (px), hard snaps.
var corrections := 0
var correction_sum := 0.0
var correction_max := 0.0
var hard_snaps := 0
## J5: times the host's jump outcome replaced our prediction (takeoff / landing / fall).
var jump_corrections := 0
var _was_predicting := false
## A fall into a jump's gap we predicted (input tick, -1 none) and whether
## the host has shown it yet; the newest input tick the host has applied.
var _fall_tick := -1
var _fall_confirmed := false
var _snap_ack := -1
## CLIENT: optional source of the local player's command (tests use an autopilot);
## default reads the single-player actions on this computer.
var input_source: Callable
var _tick := 0
var _last_rx_ms := -1
## CLIENT: the host's final result arrived; later snapshots must not overwrite it
## (snapshots carry times at lower precision).
var _results_final := false
## The host's final ammunition from RESULTS (2 per car).
var _final_ammo := PackedByteArray()
## HOST: combat events already sent for the current race.
var _sent_events := 0
var _events_race := -1


func _init(p_link: NetLink, p_role: Role) -> void:
	link = p_link
	role = p_role
	name = "NetRace"
	if role == Role.HOST:
		remote_input = RemoteDriverInput.new(RaceSession.PLAYER_2_ID)


func is_host() -> bool:
	return role == Role.HOST


func is_client() -> bool:
	return role == Role.CLIENT


## Called by the race scene once its cars and session exist.
func attach(p_race: Node) -> void:
	race = p_race
	link.message.connect(_on_message)
	link.peer_left.connect(_on_peer_left)
	link.server_closed.connect(_on_server_closed)
	if is_client():
		link.send([Msg.JOINED], true)  # ask for the grid (covers either scene being ready first)
	else:
		var p := link.peers()
		peer_id = p[0] if p.size() > 0 else 0
		send_setup()
	race._show_menu()


func _exit_tree() -> void:
	if link != null and link.message.is_connected(_on_message):
		link.message.disconnect(_on_message)
	if link != null and link.peer_left.is_connected(_on_peer_left):
		link.peer_left.disconnect(_on_peer_left)
		link.server_closed.disconnect(_on_server_closed)


## The other computer is gone: the race ends gracefully (no AI takeover).
func _on_peer_left(_peer: int) -> void:
	if race != null:
		race.on_network_lost("The other player left the game.")


func _on_server_closed() -> void:
	if race != null:
		race.on_network_lost("The host left the game.")


# ------------------------------------------------------------------ host side

## Current grid and settings, sent whenever they change (reliable).
func send_setup() -> void:
	if not is_host() or race == null or race.session.state != RaceSession.State.MODE_SELECT:
		return  # the grid and settings only change before a race
	link.send([Msg.SETUP, {"laps": race.session.lap_count(), "weapons": race.weapons_enabled,
		"style": race.combat_style, "round": race.multiplayer_round, "grid": race.grid_order.duplicate(),
		"races": race.races_started}], true)


func can_start() -> bool:
	return client_ready and link.peers().size() > 0


func on_race_started() -> void:
	if is_host():
		client_ready = false
		remote_input.begin_race(0)
		link.send([Msg.START, race.races_started], true)


## After each simulated tick: snapshot every SNAP_INTERVAL ticks.
func host_after_tick() -> void:
	_tick += 1
	_send_events()
	if _tick % SNAP_INTERVAL == 0:
		link.send([Msg.SNAP, RaceSnapshot.encode(RaceSnapshot.capture(race, _tick)), remote_input.last_tick()], false)


## New combat events (shots, explosions, destructions, respawns), reliably and
## in order, so the client shows every effect exactly once.
func _send_events() -> void:
	var combat: CombatWorld = race.combat
	if _events_race != race.races_started or combat.events.size() < _sent_events:
		_events_race = race.races_started
		_sent_events = 0
	if combat.events.size() > _sent_events:
		link.send([Msg.EVENTS, race.races_started, _sent_events, combat.events.slice(_sent_events)], true)
		_sent_events = combat.events.size()


## Authoritative final result (reliable, so both computers agree): the
## finishing order and times, plus every racer's final DNF flag and every car's
## final condition and ammunition (protocol 7). The classification never depends on the last,
## unreliable snapshot: a car that retires just before the flag is a DNF on the
## client even when the snapshot carrying it was lost.
func send_results(order: Array) -> void:
	if not is_host():
		return
	_send_events()  # every event of the race reaches the client before its result
	var times := PackedFloat64Array()
	for id in order:
		times.append(race.session.racers[id].finish_time)
	var dnf := PackedByteArray()
	for r in race.session.racers:
		dnf.append(1 if r.dnf else 0)
	var condition := PackedFloat32Array()
	for c in race.damage.car_count():
		condition.append(race.damage.condition[c])
	var ammo := PackedByteArray()
	for c in race.combat.car_count():
		ammo.append_array([clampi(race.combat.ammo[c][0], 0, 255), clampi(race.combat.ammo[c][1], 0, 255)])
	link.send([Msg.RESULTS, PackedInt32Array(order), times, dnf, condition, ammo], true)


# ---------------------------------------------------------------- client side

## Replaces the race simulation on the client, one physics tick.
func client_tick(_step: float) -> void:
	var state: int = race.session.state
	if state == RaceSession.State.MODE_SELECT:
		if race._menu_pressed(PlayerControls.FIRE) and not local_ready:
			local_ready = true  # Fire only readies: repeated presses change nothing
			_send_ready()
	else:
		var cmd := _local_command()
		_record_prediction()
		input_tick += 1
		if cmd.get("pit_override", false):
			pit_total += 1
		link.send([Msg.INPUT, input_tick, cmd.steer, cmd.fire, front_total, rear_total, pit_total], false)
		_drive_local_car(cmd)
	_interpolate_cars()


func _local_car() -> Car:
	return race.cars[race.local_player_id]


## Whether the local car is simulated here this tick (racing, not wrecked,
## not down in a jump's gap).
func _predicting() -> bool:
	return predict and race.session.state != RaceSession.State.MODE_SELECT \
		and not race.combat.is_wrecked(race.local_player_id) and not race.session.racers[race.local_player_id].dnf \
		and not (race.jumps != null and race.jumps.is_down(race.local_player_id))


## The local car's jump phase on this computer: 0 road, 1 flying, 2 down.
func _local_phase() -> int:
	var j: JumpWorld = race.jumps
	if j == null:
		return 0
	var id: int = race.local_player_id
	return 1 if j.is_airborne(id) else (2 if j.is_down(id) else 0)


## The state reached after the previous input tick, kept for reconciliation.
func _record_prediction() -> void:
	if input_tick <= 0:
		return
	var c := _local_car()
	_history[input_tick] = [c.global_position, c.model.heading, c.model.velocity, _local_phase()]
	_history.erase(input_tick - HISTORY)


## Applies this tick's own command to the local car (or keeps it parked when
## it is wrecked / not predicting: then it follows the host's snapshots).
func _drive_local_car(cmd: Dictionary) -> void:
	var c := _local_car()
	var predicting := _predicting()
	if predicting and not _was_predicting and not snapshots.is_empty():
		_resume_from_host(c)
	_was_predicting = predicting
	_predict_jump(c)
	if not _predicting():
		c.active = false
		return
	# walls of its own road level only: other cars are shown in the past, contacts come from the host
	var walls := Track.WALL_LAYER if race.level_of(race.local_player_id) == 0 else Track.WALL_UPPER_LAYER
	if race.track.layout.has_elevation() and race.track.in_transition(race.session.racers[race.local_player_id].progress):
		walls = Track.WALL_LAYER | Track.WALL_UPPER_LAYER  # near a bridge end: both levels' barriers
	if c.collision_mask != walls:
		c.collision_mask = walls
	c.active = true
	# the pit limiter as the host has it (limiter on, or a penalty being served)
	var st: int = race.pit_state[race.local_player_id] if race.local_player_id < race.pit_state.size() else 0
	c.model.speed_cap = race.driving_params.max_speed * race.pit_rules.limiter_share if st & 1 != 0 else INF
	if race.session.racers[race.local_player_id].is_finished():
		c.steer = 0.0
		c.fire = c.model.control_mode == CarModel.ControlMode.FIRE_TO_BRAKE
	else:
		c.steer = cmd.steer
		c.fire = cmd.fire


## Compares the host's state of our car (after input tick `ack`) with our own
## record of that tick and corrects the difference.
func _reconcile(snap: Array, ack: int) -> void:
	if not _predicting() or ack <= _last_ack:
		return
	_last_ack = ack
	var auth := RaceSnapshot.car_state(snap, race.local_player_id)
	var c := _local_car()
	if not _history.has(ack):
		if c.global_position.distance_to(auth.position) > 400.0:
			_set_car(c, auth.position, auth.heading, auth.velocity)  # far off and nothing to compare: take the host's
			hard_snaps += 1
		return
	var rec: Array = _history[ack]
	if race.jumps != null:
		var host_jump := RaceSnapshot.jump_state(snap, race.local_player_id)
		var phase := RaceSnapshot.jump_phase(host_jump)
		if phase != rec[3] and not _phase_near(ack, phase):
			_adopt_jump(host_jump, (input_tick - ack) * Car.FIXED_STEP)
			for t in _history:  # what we recorded since then followed the wrong jump
				if t >= ack:
					_history[t][3] = phase
	var dpos: Vector2 = auth.position - rec[0]
	var dhead := wrapf(auth.heading - rec[1], -PI, PI)
	var dvel: Vector2 = auth.velocity - rec[2]
	var err := dpos.length()
	corrections += 1
	correction_sum += err
	correction_max = maxf(correction_max, err)
	var k := BLEND
	if err > SNAP_DISTANCE or absf(dhead) > 0.6:
		k = 1.0
		hard_snaps += 1
	elif err < 0.5 and absf(dhead) < 0.002:
		return
	_set_car(c, c.global_position + dpos * k, c.model.heading + dhead * k, c.model.velocity + dvel * k)
	for t in _history:
		if t > ack:
			var h: Array = _history[t]
			_history[t] = [h[0] + dpos * k, h[1] + dhead * k, h[2] + dvel * k, h[3]]


## Prediction starts again (after a wreck or a fall, or at the start): from
## the host's newest state of our car, not the interpolated past (which can
## still be down in a jump's gap or at the wreck).
func _resume_from_host(c: Car) -> void:
	var auth := RaceSnapshot.car_state(snapshots[-1], race.local_player_id)
	if auth.present:
		_set_car(c, auth.position, auth.heading, auth.velocity)
	var id: int = race.local_player_id
	race.progress[id].reset(c.global_position)
	race.progress[id].distance = race.session.racers[id].progress  # keep the lap count of the race distance
	if race.jumps != null:
		race.jumps.place(id, fposmod(race.progress[id].distance, race.track.path.length))
	_history.clear()


## J5: the local car's jump, predicted with the same JumpWorld the host runs
## (takeoff from its own speed, flight, landing or a fall); the host's state
## corrects it in _reconcile. Not predicting (wrecked, down): only tracks.
func _predict_jump(c: Car) -> void:
	var j: JumpWorld = race.jumps
	if j == null:
		return
	var id: int = race.local_player_id
	var p: RaceProgress = race.progress[id]
	p.update(c.global_position)
	if not _predicting():
		j.place(id, fposmod(p.distance, race.track.path.length))
		return
	var along := c.model.velocity.dot(race.track.path.tangent_at(p.distance))
	match j.step(id, Car.FIXED_STEP, p.distance, along, c.active):
		"takeoff":
			c.airborne = true
		"landed":
			c.airborne = false
		"fell":
			c.airborne = false
			c.model.velocity = Vector2.ZERO
			c.active = false  # down in the gap until the host confirms it (see _follow_host_jump)
			_fall_tick = input_tick
			_fall_confirmed = false


## Our prediction reached the host's phase a tick or two before or after
## `ack` (takeoff / landing timing within rounding): not a real difference.
func _phase_near(ack: int, phase: int) -> bool:
	for t in [ack - 2, ack - 1, ack + 1, ack + 2]:
		if _history.has(t) and _history[t][3] == phase:
			return true
	return false


## While our car is not predicted, its jump state follows the host's newest
## snapshot (not the interpolated past). A fall we predicted is held until the
## host shows it; if the host has applied our inputs past it without a fall,
## it was a misprediction and the host's state wins.
func _follow_host_jump(snap: Array) -> void:
	var j: JumpWorld = race.jumps
	if j == null or _predicting():
		return
	var id: int = race.local_player_id
	var host := RaceSnapshot.jump_state(snap, id)
	if _fall_tick >= 0 and not _fall_confirmed:
		if host.down > 0.0:
			_fall_confirmed = true
		elif _snap_ack > _fall_tick + 2:
			_fall_tick = -1
			_adopt_jump(host, 0.0)
			return
		else:
			return  # the host has not reached that tick yet
	RaceSnapshot.set_jump(j, id, host)
	_local_car().airborne = host.air
	if host.down <= 0.0:
		_fall_tick = -1


## Our car waits in the gap for the host to confirm a predicted fall.
func _holding_fall() -> bool:
	return _fall_tick >= 0 and not _fall_confirmed


## Takes the host's jump state for our car (it differs in phase from what we
## predicted for that tick): ahead = how far our prediction is past it.
func _adopt_jump(state: Dictionary, ahead: float) -> void:
	var id: int = race.local_player_id
	RaceSnapshot.set_jump(race.jumps, id, state, ahead)
	var c := _local_car()
	c.airborne = state.air
	race.jumps.place(id, fposmod(race.progress[id].distance, race.track.path.length))
	jump_corrections += 1


func _set_car(c: Car, pos: Vector2, heading: float, vel: Vector2) -> void:
	c.global_position = pos
	c.global_rotation = heading
	c.model.position = pos
	c.model.heading = heading
	c.model.velocity = vel


func _send_ready() -> void:
	link.send([Msg.READY, local_ready, race.session.control_mode], true)
	race._show_menu()


## Grid panel line about readiness (whose turn it is).
func status_text() -> String:
	if is_host():
		return PlayerControls.fmt("PLAYER 2 READY  -  {fire}: start the race") if client_ready else "Waiting for Player 2 to get ready..."
	return "YOU ARE READY  -  waiting for the host to start" if local_ready else PlayerControls.fmt("{fire}: ready (the host starts the race)")


## Control mode chosen on this computer's grid panel (sent with READY).
## Control mode changed on this computer's grid panel: ready again with it.
func on_local_mode_changed() -> void:
	if is_client() and local_ready:
		local_ready = false
		_send_ready()


# ------------------------------------------------------ connection quality

## Milliseconds since anything was last received from the other computer.
func silence_ms() -> int:
	return Time.get_ticks_msec() - _last_rx_ms if _last_rx_ms >= 0 else 0


## True when the connection looks troubled (nothing heard for 1.5 s, or heavy loss).
func connection_bad() -> bool:
	return silence_ms() > 1500 or link.packet_loss() > 0.05


## Small status for the HUD, e.g. "PING 84 ms" or "CONNECTION PROBLEMS - PING 310 ms".
func quality_text() -> String:
	var ping := link.ping_ms()
	var p := "PING %d ms" % ping if ping >= 0 else "PING -"
	if silence_ms() > 1500:
		return "CONNECTION PROBLEMS - no data for %.1f s" % (silence_ms() / 1000.0)
	if link.packet_loss() > 0.05:
		return "CONNECTION PROBLEMS - %d%% loss - %s" % [int(link.packet_loss() * 100.0), p]
	return p


func _local_command() -> Dictionary:
	if race.menu_open:  # the Esc menu is open on this computer: brake, no weapons
		var car := _local_car()
		return {"steer": 0.0, "fire": car.model.control_mode == CarModel.ControlMode.FIRE_TO_BRAKE}
	if input_source.is_valid():
		var c: Dictionary = input_source.call()
		if c.get("front", false):
			front_total += 1
		if c.get("rear", false):
			rear_total += 1
		return c
	if Input.is_action_just_pressed(PlayerControls.FIRE_FRONT):
		front_total += 1
	if Input.is_action_just_pressed(PlayerControls.FIRE_REAR):
		rear_total += 1
	var car := _local_car()
	var share := car.model.velocity.length() / maxf(car.model.params.max_speed, 1.0) if car != null else 0.0
	var fire := PlayerControls.fire_held()
	var over := false
	if car != null and race.track.layout.pit_branch() >= 0:
		var p: Dictionary = race.track.path.project(car.global_position)
		over = _pit_taps.step(fire, race.track.layout.in_pit_lane(p.distance, race.track.path.length, p.lateral),
			Car.FIXED_STEP, race.pit_rules.double_tap_window)
	return {"steer": _shaper.step(PlayerControls.steer(), share, Car.FIXED_STEP), "fire": fire, "pit_override": over}


## The client's own steering shaping (as for local players), sent as is.
var _shaper := SteerShaper.new()
## The client's pit-limiter override gesture, sent as a running total (like
## weapon presses: exactly once on the host).
var _pit_taps := PitTapDetector.new()
var pit_total := 0


func _push_snapshot(snap: Array) -> void:
	var t := RaceSnapshot.tick_of(snap)
	if not snapshots.is_empty() and t <= RaceSnapshot.tick_of(snapshots[-1]):
		return  # late or duplicate
	snapshots.append(snap)
	while snapshots.size() > BUFFER:
		snapshots.pop_front()
	if not _results_final:
		RaceSnapshot.apply_race(race, snap)


func _apply_final_ammo() -> void:
	for c in mini(race.combat.car_count(), _final_ammo.size() >> 1):
		race.combat.ammo[c] = [int(_final_ammo[c * 2]), int(_final_ammo[c * 2 + 1])]


## Cars shown INTERP_DELAY ticks behind the newest snapshot, blended between
## the two snapshots around that moment (smooth despite 30 Hz / jitter / loss).
func _interpolate_cars() -> void:
	if snapshots.is_empty():
		return
	var newest := float(RaceSnapshot.tick_of(snapshots[-1]))
	var target := newest - INTERP_DELAY
	if render_tick < 0.0 or absf(render_tick - target) > 30.0:
		render_tick = target
	else:
		render_tick += 1.0 + clampf((target - render_tick) * 0.1, -0.5, 0.5)
	render_tick = minf(render_tick, newest)
	var a: Array = snapshots[0]
	var b: Array = snapshots[0]
	for s in snapshots:
		if RaceSnapshot.tick_of(s) <= render_tick:
			a = s
		else:
			b = s
			break
	if RaceSnapshot.tick_of(b) < RaceSnapshot.tick_of(a):
		b = a
	if not b[6].is_empty():
		RaceSnapshot.apply_combat(race.combat, b[6])  # weapons and wrecks at the moment shown
		if _results_final:
			_apply_final_ammo()  # the result's ammunition stays (older snapshots may still be shown)
	var span := float(RaceSnapshot.tick_of(b) - RaceSnapshot.tick_of(a))
	var t := 0.0 if span <= 0.0 else clampf((render_tick - RaceSnapshot.tick_of(a)) / span, 0.0, 1.0)
	for c in race.cars.size():
		if c == race.local_player_id and (_predicting() or _holding_fall()):
			continue  # our own car is predicted, not interpolated
		if race.jumps != null and c != race.local_player_id:  # ours: _follow_host_jump
			var js := RaceSnapshot.jump_state(b, c)
			# flight time at the moment shown (b is up to one snapshot ahead of it)
			RaceSnapshot.set_jump(race.jumps, c, js, (render_tick - RaceSnapshot.tick_of(b)) * Car.FIXED_STEP)
			race.cars[c].airborne = js.air
		var sa := RaceSnapshot.car_state(a, c)
		var sb := RaceSnapshot.car_state(b, c)
		var car: Car = race.cars[c]
		if race.session.racers[c].dnf:
			car.visible = sb.present  # a retired car leaves the road when the host takes it off
		if not sb.present:
			continue
		var pos: Vector2 = sa.position.lerp(sb.position, t)
		var heading := lerp_angle(sa.heading, sb.heading, t)
		car.global_position = pos
		car.global_rotation = heading
		car.model.position = pos
		car.model.heading = heading
		car.model.velocity = sa.velocity.lerp(sb.velocity, t)


# ------------------------------------------------------------------ messages

## Expected sender: the host only listens to its client, the client only to the host.
func _from_expected(from: int) -> bool:
	if is_client():
		return from == 1
	if peer_id == 0:
		var p := link.peers()
		peer_id = p[0] if p.size() > 0 else 0
	return from == peer_id


## Shape check for a received message: msg[k + 1] must have type types[k]
## (TYPE_FLOAT also accepts ints).
static func valid(msg: Array, types: Array) -> bool:
	if msg.size() != types.size() + 1:
		return false
	for k in types.size():
		var t: int = typeof(msg[k + 1])
		if t != types[k] and not (types[k] == TYPE_FLOAT and t == TYPE_INT):
			return false
	return true


static func valid_setup(cfg: Variant, car_count: int) -> bool:
	if not cfg is Dictionary:
		return false
	for k in ["laps", "weapons", "style", "round", "grid", "races"]:
		if not cfg.has(k):
			return false
	if typeof(cfg.laps) != TYPE_INT or cfg.laps < 1 or cfg.laps > 99 or typeof(cfg.weapons) != TYPE_BOOL:
		return false
	if typeof(cfg.style) != TYPE_INT or cfg.style < 0 or cfg.style > 1 or typeof(cfg.round) != TYPE_INT or cfg.round < 0:
		return false
	if typeof(cfg.races) != TYPE_INT or cfg.races < 0 or not cfg.grid is Array or cfg.grid.size() != 10:
		return false
	var seen := {}
	for id in cfg.grid:
		if typeof(id) != TYPE_INT or id < 0 or id >= car_count or seen.has(id):
			return false
		seen[id] = true
	return true


func _on_message(from: int, msg: Array) -> void:
	if typeof(msg[0]) != TYPE_INT or not _from_expected(from):
		return  # unknown sender or malformed: ignored
	_last_rx_ms = Time.get_ticks_msec()
	var state: int = race.session.state
	match msg[0]:
		Msg.INPUT:
			if is_host() and valid(msg, [TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_INT, TYPE_INT, TYPE_INT]) \
					and state != RaceSession.State.MODE_SELECT:
				# presses can only grow, and by a plausible amount per message
				var f := clampi(msg[4], 0, remote_input._front_total + 20)
				var r := clampi(msg[5], 0, remote_input._rear_total + 20)
				var p := clampi(msg[6], 0, remote_input._pit_total + 2)
				remote_input.receive(msg[1], msg[2], msg[3], f, r, p)
		Msg.READY:
			if is_host() and valid(msg, [TYPE_BOOL, TYPE_INT]) and state == RaceSession.State.MODE_SELECT \
					and msg[2] >= 0 and msg[2] <= 1:
				client_ready = msg[1]
				client_mode = msg[2]
				race.set_player_control_mode(RaceSession.PLAYER_2_ID, client_mode)
				race.on_network_peer_ready(client_ready)
		Msg.JOINED:
			if is_host():
				send_setup()
		Msg.SETUP:
			if is_client() and state != RaceSession.State.RACING and msg.size() == 2 \
					and valid_setup(msg[1], race.cars.size()):
				local_ready = false
				snapshots.clear()
				render_tick = -1.0
				_history.clear()
				_last_ack = -1
				_fall_tick = -1
				_was_predicting = false
				_results_final = false
				_final_ammo = PackedByteArray()
				race.apply_network_setup(msg[1])
		Msg.START:
			# a newer race number only (a snapshot may already have shown RACING:
			# snapshots travel unreliably and can overtake this message)
			if is_client() and valid(msg, [TYPE_INT]) and msg[1] > race.races_started:
				race.on_network_start(msg[1])
		Msg.SNAP:
			if is_client() and valid(msg, [TYPE_PACKED_BYTE_ARRAY, TYPE_INT]):
				var snap := RaceSnapshot.decode(msg[1])
				if RaceSnapshot.is_valid(snap, race.cars.size(), race.session.racers.size()):
					var newer := snapshots.is_empty() or RaceSnapshot.tick_of(snap) > RaceSnapshot.tick_of(snapshots[-1])
					_push_snapshot(snap)
					if newer:
						_snap_ack = maxi(_snap_ack, msg[2])
						_reconcile(snap, msg[2])
						_follow_host_jump(snap)
		Msg.EVENTS:
			if is_client() and valid(msg, [TYPE_INT, TYPE_INT, TYPE_ARRAY]) and msg[1] == race.races_started:
				var events: Array = race.combat.events
				if msg[2] == events.size():  # in order, no gaps or repeats
					events.append_array(msg[3])
		Msg.RESULTS:
			if is_client() and valid(msg, [TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY,
					TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_BYTE_ARRAY]) \
					and msg[1].size() == msg[2].size() and msg[1].size() <= race.session.racers.size() \
					and msg[3].size() == race.session.racers.size() and msg[4].size() == race.damage.car_count() \
					and msg[5].size() == race.combat.car_count() * 2 \
					and state != RaceSession.State.MODE_SELECT:
				for id in msg[1]:
					if id < 0 or id >= race.session.racers.size():
						return
				race.apply_network_results(msg[1], msg[2], msg[3], msg[4])
				_final_ammo = msg[5]
				_apply_final_ammo()
				_results_final = true
