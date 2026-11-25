extends GutTest
## M5.1: host authority in one process — the client race scene lives in its own
## SubViewport (own physics world) and never simulates: its cars stay inactive,
## its checkpoints are ignored, it cannot start a race; the host starts only
## when the client is ready; the client mirrors grid, state and positions.

const MAIN_SCENE := preload("res://src/main/main.tscn")

var host_link: NetLink
var client_link: NetLink
var host: Node2D
var client: Node2D


func before_each() -> void:
	host_link = NetLink.new()
	client_link = NetLink.new()
	add_child_autofree(host_link)
	add_child_autofree(client_link)
	host_link.host(24721)
	client_link.join("127.0.0.1", 24721)
	await wait_until(func() -> bool: return host_link.peers().size() == 1 and client_link.peers().size() == 1, 5.0)
	host = _make(NetRace.Role.HOST, self)
	var vp := SubViewport.new()
	add_child_autofree(vp)
	client = _make(NetRace.Role.CLIENT, vp)
	await wait_physics_frames(10)


func after_each() -> void:
	host_link.close()
	client_link.close()
	for a in [PlayerControls.FIRE, PlayerControls.FIRE_FRONT]:
		Input.action_release(a)


func _make(role: NetRace.Role, parent: Node) -> Node2D:
	var m: Node2D = MAIN_SCENE.instantiate()
	m.presentation_enabled = false
	m.weapons_lock_enabled = false  # these tests fire at once (the start lock: test_weapons_hot.gd)
	m.human_count = 2
	m.net = NetRace.new(host_link if role == NetRace.Role.HOST else client_link, role)
	parent.add_child(m)
	if parent == self:
		autofree(m)
	return m


func test_roles_cameras_and_inputs() -> void:
	assert_eq(host.local_player_id, RaceSession.PLAYER_ID)
	assert_eq(client.local_player_id, RaceSession.PLAYER_2_ID)
	assert_null(host.player_views, "no split screen in network races")
	assert_eq(client.camera.target, client.cars[RaceSession.PLAYER_2_ID], "each computer follows its own car")
	assert_true(host.inputs[RaceSession.PLAYER_2_ID] is RemoteDriverInput)
	assert_null(host.garage)
	assert_null(host.achievements)


func test_host_waits_for_the_client_then_both_race() -> void:
	Input.action_press(PlayerControls.FIRE)
	await wait_physics_frames(3)
	Input.action_release(PlayerControls.FIRE)
	assert_eq(host.session.state, RaceSession.State.MODE_SELECT, "client not ready yet")
	client.net.local_ready = true
	client.net._send_ready()
	await wait_until(func() -> bool: return host.net.client_ready, 3.0)
	host.start_race()
	await wait_until(func() -> bool: return client.session.state == RaceSession.State.RACING, 3.0)
	assert_eq(client.grid_order, host.grid_order)
	assert_eq(client.session.sitting_out, host.session.sitting_out)
	await wait_physics_frames(120)
	for c in client.cars:
		if c.racer_id != RaceSession.PLAYER_2_ID:
			assert_false(c.active, "client never simulates other cars")
	assert_true(client.cars[RaceSession.PLAYER_2_ID].active, "only its own car is predicted (M5.2)")
	var drift := 0.0
	for id in host.grid_order:
		drift = maxf(drift, client.cars[id].global_position.distance_to(host.cars[id].global_position))
	assert_lt(drift, 80.0, "client shows the host's cars (a few ticks behind)")
	client.session.checkpoint_reached(1, 3)
	client._on_checkpoint_reached(1, client.cars[3])
	await wait_physics_frames(6)
	assert_eq(client.session.racers[3].tracker.next_checkpoint, host.session.racers[3].tracker.next_checkpoint,
		"laps come from the host")


func test_client_input_drives_only_the_clients_car_on_the_host() -> void:
	client.net.local_ready = true
	client.net._send_ready()
	await wait_until(func() -> bool: return host.net.client_ready, 3.0)
	host.start_race()
	await wait_until(func() -> bool: return client.session.state == RaceSession.State.RACING, 3.0)
	client.net.input_source = func() -> Dictionary: return {"steer": 0.0, "fire": true}
	await wait_physics_frames(60)
	assert_gt(host.cars[RaceSession.PLAYER_2_ID].model.forward_speed(), 50.0, "P2 accelerates on the host")
	assert_lt(host.cars[RaceSession.PLAYER_ID].model.forward_speed(), 5.0, "P1 untouched")


func test_client_cannot_start_and_repeated_fire_does_not_restart() -> void:
	client.net.local_ready = true
	client.net._send_ready()
	await wait_until(func() -> bool: return host.net.client_ready, 3.0)
	host.start_race()
	await wait_until(func() -> bool: return client.session.state == RaceSession.State.RACING, 3.0)
	var started: int = host.races_started
	for k in 5:
		Input.action_press(PlayerControls.FIRE)
		await wait_physics_frames(4)
		Input.action_release(PlayerControls.FIRE)
		await wait_physics_frames(4)
	assert_eq(host.races_started, started, "no restart")
	assert_eq(host.session.state, RaceSession.State.RACING)
	assert_eq(client.session.state, RaceSession.State.RACING)


func _start_armed(style: int) -> void:
	host.set_weapons_enabled(true)
	host.set_combat_style(style)
	await wait_physics_frames(4)
	client.net.local_ready = true
	client.net._send_ready()
	await wait_until(func() -> bool: return host.net.client_ready, 3.0)
	host.start_race()
	await wait_until(func() -> bool: return client.session.state == RaceSession.State.RACING, 3.0)


func test_client_press_fires_exactly_once_on_the_host() -> void:
	await _start_armed(WeaponRules.Style.CLASSIC)
	var p2 := RaceSession.PLAYER_2_ID
	var ammo: int = host.combat.ammo[p2][0]
	var presses := [false]
	client.net.input_source = func() -> Dictionary:
		var c := {"steer": 0.0, "fire": false, "front": presses[0]}
		presses[0] = false
		return c
	presses[0] = true
	await wait_physics_frames(30)
	assert_eq(host.combat.ammo[p2][0], ammo - 1, "one press, one shot")
	for k in 5:  # the same total arrives again many times (repeated packets)
		host.net.remote_input.receive(10000 + k, 0.0, false, client.net.front_total, client.net.rear_total)
		await wait_physics_frames(40)
	assert_eq(host.combat.ammo[p2][0], ammo - 1, "duplicates never fire again")
	await wait_physics_frames(10)
	assert_eq(client.combat.ammo[p2][0], ammo - 1, "client shows the host's ammunition")
	var fired: Array = client.combat.events.filter(func(e: Dictionary) -> bool: return e.kind == "fire" and e.car == p2)
	assert_eq(fired.size(), 1, "client shows the shot once")


func test_simultaneous_fire_both_players_tactical() -> void:
	await _start_armed(WeaponRules.Style.TACTICAL)
	var p1_ammo: int = host.combat.ammo[0][0]
	var p2_ammo: int = host.combat.ammo[RaceSession.PLAYER_2_ID][0]
	var once := [true]
	client.net.input_source = func() -> Dictionary:
		var c := {"steer": 0.0, "fire": false, "front": once[0]}
		once[0] = false
		return c
	Input.action_press(PlayerControls.FIRE_FRONT)
	await wait_physics_frames(2)
	Input.action_release(PlayerControls.FIRE_FRONT)
	await wait_physics_frames(30)
	assert_eq(host.combat.ammo[0][0], p1_ammo - 1, "host player fired")
	assert_eq(host.combat.ammo[RaceSession.PLAYER_2_ID][0], p2_ammo - 1, "client player fired")
	assert_gt(host.combat.slot_wait(RaceSession.PLAYER_2_ID, 0), 0.0, "Tactical cooldown applies to the remote player")


func test_wrecks_and_recovery_replicate() -> void:
	await _start_armed(WeaponRules.Style.CLASSIC)
	await wait_physics_frames(30)
	var victim := 5
	var states: Array = host._combat_states()
	host.combat._destroy(victim, 0, host.cars[victim].global_position, WeaponRules.Weapon.FRONT_MISSILE, [] as Array[int])
	await wait_physics_frames(20)
	assert_true(client.combat.is_wrecked(victim), "client sees the wreck")
	var destroyed: Array = client.combat.events.filter(func(e: Dictionary) -> bool: return e.kind == "destroyed" and e.car == victim)
	assert_eq(destroyed.size(), 1)
	await wait_physics_frames(int(host.weapon_rules.wreck_time * 60) + 20)
	assert_false(host.combat.is_wrecked(victim))
	assert_false(client.combat.is_wrecked(victim), "and the recovery")
	assert_eq(states.size(), host.cars.size())


## Protocol 7: the reliable RESULTS carry every racer's final DNF and every
## car's final condition, so the client classifies the race exactly as the host
## even when every snapshot after the retirements is lost (the intermittent
## test_net_lan_race miss of 2026-11-18).
func test_final_results_carry_retirements_when_every_snapshot_is_lost() -> void:
	await _start_armed(WeaponRules.Style.CLASSIC)
	await wait_physics_frames(40)
	var healthy := 3
	host.damage.condition[healthy] = 61.5  # a damaged car that finishes the race damaged
	await wait_physics_frames(10)
	host_link.sim_loss = 1.0  # from here on no snapshot reaches the client
	host.combat.ammo[healthy] = [1, 2]  # rounds spent after the last snapshot that arrived
	# A rival not destroyed so far: retiring a fresh weapon wreck "by fiat" (no
	# weapon, no culprit) cannot happen in a race, and the client would rightly
	# read it as the weapon retirement (2026-11-23: the AI's new timing put a
	# destruction of racer 6 just before this point).
	var rival := 6
	for id in [6, 7, 8, 9, 1, 2, 4, 5]:
		if host.stats.deaths[id] == 0 and not host.combat.is_wrecked(id):
			rival = id
			break
	var out := [rival, RaceSession.PLAYER_2_ID, RaceSession.PLAYER_ID]
	for id in out:
		host.damage.condition[id] = 0.0
		host.damage.retired[id] = 1
		host._retire(id)
	host.session.classify_remaining()  # (the rest of the field: in running order)
	await wait_until(func() -> bool: return client.net._results_final, 5.0)
	assert_true(client.net._results_final, "the reliable result arrived")
	assert_eq(client.session.state, RaceSession.State.FINISHED)
	assert_eq(client.session.finish_order, host.session.finish_order, "same classification")
	for r in host.session.racers:
		var c: RacerState = client.session.racers[r.id]
		assert_eq(c.dnf, r.dnf, "DNF of racer %d" % r.id)
		assert_eq(c.finish_position, r.finish_position, "position of racer %d" % r.id)
		assert_eq(c.finish_time, r.finish_time, "time of racer %d" % r.id)
	for id in out:
		assert_true(client.session.racers[id].dnf, "racer %d retired on the client too" % id)
		assert_eq(client.damage.condition[id], 0.0)
		assert_eq(client.damage.retired[id], 1)
	assert_almost_eq(client.damage.condition[healthy], host.damage.condition[healthy], 0.01, "final condition from the result")
	for c in host.cars.size():
		assert_eq(client.combat.ammo[c], host.combat.ammo[c], "final ammunition of car %d from the result" % c)
	await wait_physics_frames(5)
	for id in out:
		assert_eq(client.stats.deaths[id], host.stats.deaths[id], "D of racer %d agrees (the retirement counts)" % id)
	host_link.sim_loss = 0.0


## 2026-11-22: a collision retirement shows its culprit on the client too (the
## host's "retired" event), whichever arrives first - the event or the DNF.
func test_collision_retirement_culprit_reaches_the_client() -> void:
	await _start_armed(WeaponRules.Style.CLASSIC)
	await wait_physics_frames(30)
	host.stats.on_contact(6, 3, host.session.elapsed)  # car 3 rammed car 6
	host.damage.condition[6] = 0.0
	host.damage.retired[6] = 1
	host._retire(6)
	await wait_until(func() -> bool: return client.stats.tombstones[3] == 1, 5.0)
	var entry: Dictionary = client.stats.feed.filter(func(e: Dictionary) -> bool: return e.victim == 6)[-1]
	assert_eq(entry.attacker, 3, "the culprit in the client's kill feed")
	assert_eq(entry.weapon, CombatStats.COLLISION)
	assert_eq(client.stats.line(3), host.stats.line(3), "same TOMBSTONE | K | D on both computers")
	assert_eq(client.stats.line(6), host.stats.line(6))
	# the other order: the DNF already counted unattributed, then the event
	var s := CombatStats.new(10)
	s.on_retired(7, 1.0, false)
	assert_eq(s.feed[-1].attacker, -1)
	s.attribute_retirement(7, 2)
	assert_eq([s.feed[-1].attacker, s.feed[-1].weapon, s.kills[2], s.tombstones[2]], [2, CombatStats.COLLISION, 1, 1])
	s.attribute_retirement(7, 4)
	assert_eq(s.kills[4], 0, "attributed once")

