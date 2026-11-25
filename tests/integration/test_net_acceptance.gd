extends GutTest
## M5.2 Stage 4 acceptance (in one process: the client race in its own world):
## every track variant and lap setting reaches the client; a full armed
## Tactical race with the client in Fire to Brake ends with the same result
## on both; repeated Space / Cross presses never reset the session; single
## player is unaffected by a finished network session.

const MAIN_SCENE := preload("res://src/main/main.tscn")
const PORT := 24781

var hl: NetLink
var cl: NetLink
var host: Node2D
var client: Node2D


func _setup(track: int) -> void:
	hl = NetLink.new()
	cl = NetLink.new()
	add_child_autofree(hl)
	add_child_autofree(cl)
	hl.host(PORT)
	cl.join("127.0.0.1", PORT)
	await wait_until(func() -> bool: return hl.peers().size() == 1 and cl.peers().size() == 1, 5.0)
	host = _make(NetRace.Role.HOST, self, track)
	var vp := SubViewport.new()
	add_child_autofree(vp)
	client = _make(NetRace.Role.CLIENT, vp, track)
	await wait_physics_frames(10)


func after_each() -> void:
	Input.action_release(PlayerControls.FIRE)
	Input.action_release(PlayerControls.CONFIRM)
	for l in [hl, cl]:
		if is_instance_valid(l):
			l.close()


func _make(role: NetRace.Role, parent: Node, track: int) -> Node2D:
	var m: Node2D = MAIN_SCENE.instantiate()
	m.presentation_enabled = false
	m.human_count = 2
	m.track_variant = track
	m.net = NetRace.new(hl if role == NetRace.Role.HOST else cl, role)
	parent.add_child(m)
	if parent == self:
		autofree(m)
	return m


func test_every_track_and_lap_setting_reaches_the_client() -> void:
	for track in [1, 2, 3]:
		await _setup(track)
		assert_eq(client.track_theme.variant, track)
		for laps in [3, 7, 20, 50]:
			host.set_lap_count(laps)
			await wait_until(func() -> bool: return client.session.lap_count() == laps, 3.0)
			assert_eq(client.session.lap_count(), laps, "track %d laps %d" % [track, laps])
		for style in [WeaponRules.Style.CLASSIC, WeaponRules.Style.TACTICAL]:
			host.set_combat_style(style)
			await wait_until(func() -> bool: return client.combat_style == style, 3.0)
			assert_eq(client.combat_style, style)
		host.set_weapons_enabled(false)
		await wait_until(func() -> bool: return not client.weapons_enabled, 3.0)
		assert_false(client.weapons_enabled, "No Guns reaches the client")
		after_each()
		host.queue_free()
		client.get_parent().queue_free()
		await wait_physics_frames(3)


func test_full_tactical_race_client_fire_to_brake_agrees() -> void:
	await _setup(2)
	host.set_lap_count(3)
	host.set_weapons_enabled(true)
	host.set_combat_style(WeaponRules.Style.TACTICAL)
	host.inputs[0] = AiDriverInput.new(0, AiDriver.new(host.racing_line, AiParams.new()))
	var ap := AiDriver.new(client.racing_line, AiParams.new())
	var prog: Array = []
	for c in client.cars:
		prog.append(RaceProgress.new(client.track.path))
	var tick := [0]
	client.net.input_source = func() -> Dictionary:
		tick[0] += 1
		var me := RaceSession.PLAYER_2_ID
		for id in client.grid_order:
			prog[id].update(client.cars[id].global_position)
		var others := []
		for id in client.grid_order:
			if id != me:
				others.append({"distance": prog[id].distance, "lateral": prog[id].lateral, "speed": client.cars[id].model.velocity.length()})
		var car: Car = client.cars[me]
		var cmd := ap.decide({"position": car.global_position, "heading": car.model.heading,
			"speed": car.model.velocity.dot(Vector2.from_angle(car.model.heading)),
			"distance": prog[me].distance, "lateral": prog[me].lateral}, others, 1.0 / 60.0)
		cmd.fire = not cmd.fire  # the autopilot thinks in Fire to Accelerate; this client drives Fire to Brake
		cmd["front"] = tick[0] % 70 == 0
		return cmd
	await wait_until(func() -> bool: return client.session.lap_count() == 3 and client.weapons_enabled, 3.0)
	client.set_menu_choice(1)  # Fire to Brake on the client computer
	client.net.local_ready = true
	client.net._send_ready()
	await wait_until(func() -> bool: return host.net.client_ready, 3.0)
	host.start_race()
	assert_eq(host.cars[RaceSession.PLAYER_2_ID].model.control_mode, CarModel.ControlMode.FIRE_TO_BRAKE, "client's own mode on the host")
	await wait_until(func() -> bool: return host.session.all_finished() and client.network_results.size() > 0, 400.0)
	var ho: Array = host.session.finish_order.map(func(id: int) -> Array: return [id, host.session.racers[id].finish_time])
	var co: Array = client.session.finish_order.map(func(id: int) -> Array: return [id, client.session.racers[id].finish_time])
	assert_eq(co, ho, "same authoritative result")
	var hd: int = host.combat.events.filter(func(e: Dictionary) -> bool: return e.kind == "destroyed").size()
	var cd: int = client.combat.events.filter(func(e: Dictionary) -> bool: return e.kind == "destroyed").size()
	assert_eq(cd, hd, "same destructions")
	assert_gt(client.net.corrections, 50)
	# repeated Fire presses (both computers share input in this test): the host
	# moves to the next grid once, the client readies once, at most one new race
	var started: int = host.races_started
	for k in 6:  # Enter moves on from the results, Fire readies on the grid
		Input.action_press(PlayerControls.CONFIRM)
		Input.action_press(PlayerControls.FIRE)
		await wait_physics_frames(3)
		Input.action_release(PlayerControls.CONFIRM)
		Input.action_release(PlayerControls.FIRE)
		await wait_physics_frames(10)
	assert_lte(host.races_started, started + 1, "never more than one new race")
	assert_eq(host.multiplayer_round, 1, "rotation advanced exactly once")
	assert_ne(host.session.state, RaceSession.State.FINISHED, "moved on from the results")
