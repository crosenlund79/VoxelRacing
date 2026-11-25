extends SceneTree
## Test helper: one side of a LAN race, run as its own Godot process.
##   godot --headless --path <project> -s res://tests/support/net_probe.gd -- \
##         role=host|client port=24690 laps=1 weapons=0 style=0 out=<file> \
##         latency=0 loss=0 races=1 fire_every=0 layout=<id> jitter=0 fall=0 pit=0
## pit=1: the host damages the first racing rival on the grid at the start so
## it makes a pit stop (pit_car: the same car on both computers).
## Both humans are driven by an autopilot (an AiDriver steering the human's
## car through the normal input path: the host's local player input, and the
## client's INPUT messages). Each side writes the final result it shows
## (finishing order, positions, times) and its own counters to `out`.

var opts := {"role": "host", "port": "24690", "laps": "1", "weapons": "0", "style": "0", "out": "",
	"latency": "0", "loss": "0", "races": "1", "fire_every": "0", "timeout": "120", "track": "1", "night": "0", "jitter": "0",
	"mode": "0", "predict": "1", "fall": "0", "shots": "", "pit": "0"}
var link: NetLink
var main: Node2D
var autopilot: AiDriver
var progress: Array[RaceProgress] = []
var races_done := 0
var results: Array = []
var t0 := 0
var finished_at := -1
var shots := 0
var tick := 0
var waiting_next := false
## pit=1: the damage was applied (host) / the highest service progress of rival 1 seen (client, 0 .. 31).
var _pit_damaged := false
var pit_progress_seen := 0
var pit_car := -1
var pit_bay_seen := -1
## J5: per car, takeoffs and falls into a jump's gap seen on this computer.
var takeoffs := {}
var falls := {}
var _was_air := {}
var _was_down := {}


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.split("=")
		if kv.size() == 2:
			opts[kv[0]] = kv[1]
	link = NetLink.new()
	link.sim_latency_ms = int(opts.latency)
	link.sim_loss = float(opts.loss)
	link.sim_jitter_ms = int(opts.jitter)
	root.add_child(link)
	t0 = Time.get_ticks_msec()
	if opts.role == "host":
		link.host(int(opts.port))
		link.peer_joined.connect(_on_joined)
		link.message.connect(_on_host_message)
	else:
		link.message.connect(_on_client_message)
		_try_join()
	physics_frame.connect(_tick)


func _try_join() -> void:
	link.join("127.0.0.1", int(opts.port))
	link.connection_failed.connect(func() -> void:
		await create_timer(0.3).timeout
		_try_join(), CONNECT_ONE_SHOT)


func _on_joined(_id: int) -> void:
	link.send([NetRace.Msg.WELCOME, NetRace.PROTOCOL, NetRace.GAME_BUILD, {"track_variant": int(opts.track)}], true)


func _on_host_message(_from: int, msg: Array) -> void:
	if msg[0] != NetRace.Msg.HELLO or main != null:
		return
	main = _make_race(NetRace.Role.HOST)
	main.set_lap_count(int(opts.laps))
	main.set_weapons_enabled(opts.weapons == "1")
	main.set_combat_style(int(opts.style))
	main.inputs[0] = AiDriverInput.new(0, AiDriver.new(main.racing_line, AiParams.new()))


func _on_client_message(_from: int, msg: Array) -> void:
	if msg[0] == NetRace.Msg.WELCOME and main == null:
		link.send([NetRace.Msg.HELLO, NetRace.PROTOCOL, NetRace.GAME_BUILD], true)
		main = _make_race(NetRace.Role.CLIENT, int(msg[3].track_variant))
		autopilot = AiDriver.new(main.racing_line, AiParams.new())
		for c in main.cars:
			progress.append(RaceProgress.new(main.track.path))
		main.net.input_source = _client_autopilot
		main.net.predict = opts.predict == "1"


func _make_race(role: NetRace.Role, track: int = int(opts.track)) -> Node2D:
	var m: Node2D = load("res://src/main/main.tscn").instantiate()
	m.presentation_enabled = opts.shots != ""  # shots=<dir>: screenshots of jumps (needs a display)
	if DevLayouts.LAYOUTS.has(opts.get("layout", "")):
		m.layout_override = load(DevLayouts.LAYOUTS[opts.layout])
	m.human_count = 2
	m.track_variant = track
	m.night = opts.night == "1"
	m.net = NetRace.new(link, role)
	root.add_child(m)
	return m


## Client: the autopilot reads the replicated cars like a player reads the screen.
func _client_autopilot() -> Dictionary:
	var me_id := RaceSession.PLAYER_2_ID
	for id in main.grid_order:
		progress[id].update(main.cars[id].global_position)
	var others: Array = []
	for id in main.grid_order:
		if id != me_id:
			others.append({"distance": progress[id].distance, "lateral": progress[id].lateral,
				"speed": main.cars[id].model.velocity.length()})
	var c: Car = main.cars[me_id]
	var cmd := autopilot.decide({"position": c.global_position, "heading": c.model.heading,
		"speed": c.model.velocity.dot(Vector2.from_angle(c.model.heading)),
		"distance": progress[me_id].distance, "lateral": progress[me_id].lateral}, others, 1.0 / 60.0)
	if opts.fall == "1" and main.track.layout.has_jumps():
		# J5 test: crawl up to the jump's lip, so the car is too slow and falls in
		var lip: float = main.track.layout.jumps[0].x
		var d := fposmod(progress[me_id].distance, main.track.path.length)
		if d > lip - 420.0 and d < lip:
			cmd.fire = main.cars[me_id].model.velocity.length() < 140.0  # crawl up to the lip: too slow to clear the gap
	if opts.mode == "1":
		cmd.fire = not cmd.fire  # the autopilot thinks in Fire to Accelerate; in Fire to Brake, fire means brake
	var fe := int(opts.fire_every)
	cmd["front"] = fe > 0 and tick % fe == 0
	return cmd


func _tick() -> void:
	tick += 1
	if Time.get_ticks_msec() - t0 > int(opts.timeout) * 1000:
		_write({"error": "timeout", "state": main.session.state if main != null else -1})
		quit(1)
		return
	if main == null or not main.is_inside_tree():
		return
	var s: RaceSession = main.session
	_count_jumps()
	_jump_shots()
	if opts.pit == "1" and s.state == RaceSession.State.RACING:
		if pit_car < 0:
			for id in main.grid_order:
				if id != RaceSession.PLAYER_ID and id != RaceSession.PLAYER_2_ID:
					pit_car = id
					break
		if opts.role == "host" and not _pit_damaged:
			_pit_damaged = true
			main.damage.condition[pit_car] = 10.0  # (below every rival's pit threshold)
		if main.pit_state.size() > pit_car:
			pit_progress_seen = maxi(pit_progress_seen, (main.pit_state[pit_car] >> 3) & 31)
			pit_bay_seen = maxi(pit_bay_seen, PitWorld.packed_bay(main.pit_state[pit_car]))
	if opts.role == "host":
		if waiting_next and s.state == RaceSession.State.MODE_SELECT:
			waiting_next = false
			Input.action_release(PlayerControls.CONFIRM)
		if s.state == RaceSession.State.MODE_SELECT and main.net.can_start():
			for id in main.grid_order:
				progress.resize(main.cars.size())
			main.start_race()
		if s.state == RaceSession.State.FINISHED and s.all_finished() and finished_at < 0 and not waiting_next:
			finished_at = tick
			results.append(_result())
			takeoffs = {}
			falls = {}
		if finished_at > 0 and tick - finished_at == 30:
			races_done += 1
			if races_done < int(opts.races):
				finished_at = -1
				waiting_next = true
				Input.action_press(PlayerControls.CONFIRM)
			else:
				_write({"results": results, "client_shots": main.combat.shots_fired[RaceSession.PLAYER_2_ID]})
				quit()
	else:
		if s.state == RaceSession.State.MODE_SELECT and not main.net.local_ready and main.races_started == races_done:
			main.set_menu_choice(int(opts.mode))  # 0 Fire to Accelerate, 1 Fire to Brake
			main.net.local_ready = true
			main.net._send_ready()
		if main.network_results.size() > 0 and finished_at < 0:
			finished_at = tick
			results.append(_result())
			takeoffs = {}
			falls = {}
			races_done += 1
			main.network_results = [] as Array[int]
			if races_done >= int(opts.races):
				var n: NetRace = main.net
				_write({"results": results, "client_shots": main.combat.shots_fired[RaceSession.PLAYER_2_ID],
					"corrections": n.corrections, "avg_error": n.correction_sum / maxf(1.0, n.corrections),
					"max_error": n.correction_max, "hard_snaps": n.hard_snaps, "ping": link.ping_ms(),
					"jump_corrections": n.jump_corrections})
				quit()
		if finished_at > 0 and main.session.state == RaceSession.State.MODE_SELECT:
			finished_at = -1


var _shot_taken := {}


## shots=<dir>: the first moment this computer shows its own car, and then a
## rival, high in the air.
func _jump_shots() -> void:
	if opts.shots == "" or main.jumps == null:
		return
	var me: int = main.local_player_id
	for id in main.cars.size():
		var key := "own" if id == me else "rival"
		if _shot_taken.has(key) or not main.jumps.is_airborne(id) or main.jumps.height(id) < 12.0:
			continue
		if key == "rival" and main.cars[me].global_position.distance_to(main.cars[id].global_position) > 500.0:
			continue
		_shot_taken[key] = true
		root.get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [opts.shots, opts.role, key])


func _count_jumps() -> void:
	var j: JumpWorld = main.jumps
	if j == null or main.session.state == RaceSession.State.MODE_SELECT:
		return
	for id in main.cars.size():
		var air := j.is_airborne(id)
		var down := j.is_down(id)
		if air and not _was_air.get(id, false):
			takeoffs[str(id)] = takeoffs.get(str(id), 0) + 1
		if down and not _was_down.get(id, false):
			falls[str(id)] = falls.get(str(id), 0) + 1
		_was_air[id] = air
		_was_down[id] = down


func _result() -> Dictionary:
	var s: RaceSession = main.session
	var times := []
	var positions := []
	for id in s.finish_order:
		times.append(snappedf(s.racers[id].finish_time, 0.0001))
		positions.append(s.racers[id].finish_position)
	var fired := 0
	var destroyed := 0
	for e in main.combat.events:
		fired += int(e.kind == "fire")
		destroyed += int(e.kind == "destroyed")
	var condition := []
	var ammo := []
	var dnf := []
	for id in main.cars.size():
		condition.append(snappedf(main.damage.condition[id], 0.1))
		ammo.append(main.combat.ammo[id].duplicate())
		if s.racers[id].dnf:
			dnf.append(id)
	return {"order": s.finish_order.duplicate(), "times": times, "positions": positions, "grid": main.grid_order.duplicate(),
		"sitting_out": s.sitting_out.duplicate(), "fired": fired, "destroyed": destroyed,
		"condition": condition, "ammo": ammo, "dnf": dnf, "takeoffs": takeoffs.duplicate(), "falls": falls.duplicate(),
		"variant": main.track_variant, "night": main.night,
		"pit_stops": Array(main.pits.stops) if main.pits != null and opts.role == "host" else [],
		"pit_progress_seen": pit_progress_seen, "pit_car": pit_car, "pit_bay_seen": pit_bay_seen,
		"handling": [main.driving_params.max_speed, main.driving_params.acceleration, main.driving_params.grip]}


func _write(data: Dictionary) -> void:
	var f := FileAccess.open(opts.out, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
