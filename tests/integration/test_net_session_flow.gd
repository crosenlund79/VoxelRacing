extends GutTest
## M5.1 Stage 3: the LAN session flow through the real game root — host waits,
## client joins by IP, both reach the grid with readiness shown, the race
## starts once, a disconnect ends the race with a clear message and both
## return safely to the menu; joining a race in progress is refused; bad
## addresses and unreachable hosts give clear messages.

const GAME_SCENE := preload("res://src/main/game.tscn")
const PORT := 24741

var host_game: Node
var client_game: Node


func before_each() -> void:
	host_game = _make_game(self, "h")
	var vp := SubViewport.new()  # the client gets its own world, like a second computer
	add_child_autofree(vp)
	client_game = _make_game(vp, "c")
	await wait_physics_frames(3)


func after_each() -> void:
	for g in [host_game, client_game]:
		if is_instance_valid(g):
			g.close_lan()
			g.title.stop_audio()
	for t in ["h", "c"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_net_flow_%s.cfg" % t))


func _make_game(parent: Node, tag: String) -> Node:
	var g := GAME_SCENE.instantiate()
	g.achievements_path = "user://test_net_flow_%s.cfg" % tag
	g.lan_port = PORT
	parent.add_child(g)
	if parent == self:
		autofree(g)
	return g


func _real_wait(ms: int, done: Callable) -> void:
	var deadline := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < deadline and not done.call():
		OS.delay_msec(10)
		await wait_physics_frames(1)


func _connect_both() -> void:
	assert_eq(host_game.host_lan(), OK)
	assert_string_contains(host_game.title.lan_panel._status.text, "Waiting for the other player")
	assert_eq(client_game.join_lan("127.0.0.1"), OK)
	await _real_wait(8000, func() -> bool:
		return host_game.race != null and client_game.race != null and client_game.race.is_inside_tree() \
			and host_game.race.is_inside_tree())
	await wait_physics_frames(30)


func _labels(game: Node) -> Array:
	return game.race.hud._message_box.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)


func test_host_join_ready_start_and_disconnect() -> void:
	await _connect_both()
	assert_not_null(host_game.race)
	assert_not_null(client_game.race)
	assert_true(host_game.race.net.is_host())
	assert_true(client_game.race.net.is_client())
	assert_null(host_game.race.garage)
	assert_null(client_game.race.achievements)
	assert_has(_labels(host_game), "Waiting for Player 2 to get ready...")
	assert_has(_labels(client_game), PlayerControls.fmt("{fire}: ready (the host starts the race)"))
	client_game.race.net.local_ready = true
	client_game.race.net._send_ready()
	await _real_wait(3000, func() -> bool: return host_game.race.net.client_ready)
	await wait_physics_frames(3)
	assert_has(_labels(host_game), PlayerControls.fmt("PLAYER 2 READY  -  {fire}: start the race"))
	var host_race: Node2D = host_game.race
	host_race.start_race()
	await _real_wait(3000, func() -> bool: return client_game.race.session.state == RaceSession.State.RACING)
	assert_eq(client_game.race.session.state, RaceSession.State.RACING)
	await wait_physics_frames(60)
	client_game.back_to_title()  # the client leaves mid-race
	await _real_wait(6000, func() -> bool: return host_race.network_lost)
	assert_true(host_race.network_lost, "the host notices")
	assert_has(_labels(host_game), "The other player left the game.")
	for c in host_race.cars:
		assert_false(c.active, "the race stops")
	host_race.exit_requested.emit()  # Fire / Esc on the notice
	await _real_wait(3000, func() -> bool: return host_game.race == null)
	assert_null(host_game.race, "host back at the menu")
	assert_false(host_game.link.is_open(), "connection closed")
	await _real_wait(3000, func() -> bool: return client_game.race == null)
	assert_null(client_game.race, "client back at the menu")


func test_host_leaving_ends_the_clients_race() -> void:
	await _connect_both()
	var client_race: Node2D = client_game.race
	host_game.close_lan()
	await _real_wait(8000, func() -> bool: return client_race.network_lost)
	assert_true(client_race.network_lost)
	assert_has(_labels(client_game), "The host left the game.")


func test_joining_a_race_in_progress_is_refused() -> void:
	await _connect_both()
	client_game.close_lan()  # the slot frees up while the host's race scene is still open
	await _real_wait(6000, func() -> bool: return host_game.race.network_lost)
	var late := NetLink.new()
	add_child_autofree(late)
	var got := []
	late.message.connect(func(_f: int, msg: Array) -> void: got.append(msg[0]))
	late.join("127.0.0.1", PORT)
	await _real_wait(5000, func() -> bool: return got.has(NetRace.Msg.REJECT))
	assert_has(got, NetRace.Msg.REJECT)
	assert_does_not_have(got, NetRace.Msg.WELCOME)
	late.close()


func test_bad_address_and_unreachable_host_give_clear_messages() -> void:
	assert_ne(client_game.join_lan("not an address"), OK)
	assert_string_contains(client_game.title.lan_panel._status.text, "IPv4 address")
	assert_eq(client_game.join_lan("127.0.0.1"), OK)  # nobody hosting on this port
	await _real_wait(25000, func() -> bool: return client_game.title.lan_panel._status.text.begins_with("Could not connect"))
	assert_string_contains(client_game.title.lan_panel._status.text, "Could not connect")
	assert_null(client_game.race)


func test_client_races_on_the_hosts_layout() -> void:
	host_game.title.layout_id = "exp_figure8_01"
	assert_eq(client_game.title.layout_id, DevLayouts.DEFAULT, "the client's own choice is the default circuit")
	await _connect_both()
	assert_not_null(host_game.race)
	assert_not_null(client_game.race)
	if host_game.race == null or client_game.race == null:
		return
	assert_eq(DevLayouts.id_of(host_game.race.track.layout), "exp_figure8_01")
	assert_eq(DevLayouts.id_of(client_game.race.track.layout), "exp_figure8_01", "the client follows the host's layout")
	assert_almost_eq(client_game.race.track.path.length, host_game.race.track.path.length, 0.01)


func test_race_menu_in_a_network_race_keeps_racing_and_leave_disconnects() -> void:
	await _connect_both()
	client_game.race.net.local_ready = true
	client_game.race.net._send_ready()
	await _real_wait(3000, func() -> bool: return host_game.race.net.client_ready)
	var host_race: Node2D = host_game.race
	var client_race: Node2D = client_game.race
	host_race.start_race()
	await _real_wait(3000, func() -> bool: return client_race.session.state == RaceSession.State.RACING)
	await wait_physics_frames(30)
	host_race.open_race_menu()
	assert_true(host_race.menu_open)
	assert_false(host_race.get_tree().paused, "a network race is never paused")
	var t0: float = host_race.session.elapsed
	await wait_physics_frames(30)
	assert_gt(host_race.session.elapsed, t0, "the race goes on for the other player")
	host_race.leave_race()  # LEAVE RACE
	await _real_wait(8000, func() -> bool: return client_race.network_lost)
	assert_true(client_race.network_lost, "the client is told cleanly")
	await _real_wait(3000, func() -> bool: return host_game.race == null)
	assert_null(host_game.race, "host back at the menu")
	assert_false(host_game.link.is_open(), "connection closed")


func test_client_gets_the_hosts_circuit_biome_time_and_the_real_jump() -> void:
	# J5: same circuit, biome (handling), time of day and jump on both computers
	host_game.title.layout_id = "ravenhook"
	host_game.title.track_variant = 3
	host_game.title.night = true
	await _connect_both()
	if host_game.race == null or client_game.race == null:
		fail_test("no race")
		return
	var h: Node2D = host_game.race
	var c: Node2D = client_game.race
	assert_eq(DevLayouts.id_of(c.track.layout), "ravenhook")
	assert_eq(c.track_variant, 3, "the host's biome")
	assert_true(c.night, "the host's time of day")
	assert_eq(c.driving_params.grip, h.driving_params.grip, "the same Winter handling")
	assert_not_null(h.jumps, "the host runs the jump")
	assert_not_null(c.jumps, "the client shows and predicts it")
	assert_true(c.track.has_node("Ravine0"), "the client's track has the real gap")


func test_disconnect_mid_jump_leaves_no_stale_state() -> void:
	host_game.title.layout_id = "kestrel_ridge"
	await _connect_both()
	if host_game.race == null or client_game.race == null:
		fail_test("no race")
		return
	client_game.race.net.local_ready = true
	client_game.race.net._send_ready()
	await _real_wait(3000, func() -> bool: return host_game.race.net.client_ready)
	var host_race: Node2D = host_game.race
	host_race.start_race()
	await _real_wait(3000, func() -> bool: return client_game.race.session.state == RaceSession.State.RACING)
	# the client's car in the air on the host (as after a takeoff)
	RaceSnapshot.set_jump(host_race.jumps, RaceSession.PLAYER_2_ID, {"air": true, "air_time": 0.1, "lift": 250.0, "jump": 0, "down": 0.0})
	host_race.cars[RaceSession.PLAYER_2_ID].airborne = true
	await wait_physics_frames(6)
	client_game.back_to_title()  # leaves in mid-air
	await _real_wait(6000, func() -> bool: return host_race.network_lost)
	assert_true(host_race.network_lost)
	host_race.exit_requested.emit()
	await _real_wait(3000, func() -> bool: return host_game.race == null)
	assert_null(host_game.race)
	host_game.start_race(0)  # an ordinary race afterwards starts clean
	await _real_wait(5000, func() -> bool: return host_game.race != null and host_game.race.is_inside_tree())
	var fresh: Node2D = host_game.race
	assert_null(fresh.net, "no network left over")
	for car in fresh.cars:
		assert_false(car.airborne, "nobody in the air")
	for i in fresh.cars.size():
		assert_false(fresh.jumps.is_airborne(i))
		assert_false(fresh.jumps.is_down(i))
