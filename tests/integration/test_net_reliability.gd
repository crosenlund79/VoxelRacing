extends GutTest
## M5.2 Stage 3: session reliability through the real game root — clean
## consecutive sessions (no stale scenes, snapshots or events), readiness that
## repeated Fire presses cannot toggle, a mode change un-readying, guards
## against repeated host / join, a visitor leaving the lobby, a disconnect on
## the results screen, and the connection-quality indicator.

const GAME_SCENE := preload("res://src/main/game.tscn")
const PORT := 24771

var host_game: Node
var client_game: Node


func before_each() -> void:
	host_game = _make_game(self, "h")
	var vp := SubViewport.new()
	add_child_autofree(vp)
	client_game = _make_game(vp, "c")
	await wait_physics_frames(3)


func after_each() -> void:
	Input.action_release(PlayerControls.FIRE)
	for g in [host_game, client_game]:
		if is_instance_valid(g):
			g.close_lan()
			g.title.stop_audio()
	for t in ["h", "c"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_net_rel_%s.cfg" % t))


func _make_game(parent: Node, tag: String) -> Node:
	var g := GAME_SCENE.instantiate()
	g.achievements_path = "user://test_net_rel_%s.cfg" % tag
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
	assert_eq(client_game.join_lan("127.0.0.1"), OK)
	await _real_wait(10000, func() -> bool:
		return host_game.race != null and client_game.race != null and client_game.race.is_inside_tree() \
			and host_game.race.is_inside_tree() and client_game.race.net.race != null)
	await wait_physics_frames(20)


func _ready_and_start() -> void:
	client_game.race.net.local_ready = true
	client_game.race.net._send_ready()
	await _real_wait(3000, func() -> bool: return host_game.race.net.client_ready)
	host_game.race.start_race()
	await _real_wait(3000, func() -> bool: return client_game.race.session.state == RaceSession.State.RACING)


func _races_in(game: Node) -> int:
	return game.get_children().filter(func(n: Node) -> bool: return n.has_method("start_race") and n != game).size()


func test_two_sessions_in_a_row_start_clean() -> void:
	for round in 2:
		await _connect_both()
		assert_eq(_races_in(host_game), 1, "one race scene on the host (session %d)" % round)
		assert_eq(_races_in(client_game), 1, "one race scene on the client")
		var c: Node2D = client_game.race
		assert_eq(c.races_started, 0, "fresh session")
		assert_eq(c.combat.events.size(), 0, "no stale events")
		assert_true(c.net.snapshots.is_empty() or RaceSnapshot.tick_of(c.net.snapshots[0]) < 200, "no stale snapshots")
		assert_eq(c.session.sitting_out, [1] as Array[int], "rotation starts again with Victor")
		await _ready_and_start()
		assert_eq(host_game.race.races_started, 1)
		await wait_physics_frames(30)
		client_game.back_to_title()
		await _real_wait(8000, func() -> bool: return host_game.race != null and host_game.race.network_lost)
		host_game.race.exit_requested.emit()
		await _real_wait(4000, func() -> bool: return host_game.race == null and client_game.race == null)
		assert_null(host_game.race)
		assert_null(client_game.race)
		assert_false(host_game.link.is_open())
		await wait_physics_frames(5)


func test_repeated_fire_readies_once_and_mode_change_unreadies() -> void:
	await _connect_both()
	var h: Node2D = host_game.race
	var c: Node2D = client_game.race
	for k in 3:  # both computers' Fire pressed repeatedly (shared input in this test)
		Input.action_press(PlayerControls.FIRE)
		await wait_physics_frames(3)
		Input.action_release(PlayerControls.FIRE)
		await wait_physics_frames(3)
		await _real_wait(300, func() -> bool: return false)
	assert_true(c.net.local_ready or c.session.state == RaceSession.State.RACING, "Fire readies, never toggles back")
	assert_lte(h.races_started, 1, "the race starts at most once")
	if h.session.state == RaceSession.State.MODE_SELECT:
		c.set_menu_choice(1)
		c.net.on_local_mode_changed()
		await _real_wait(2000, func() -> bool: return not h.net.client_ready)
		assert_false(h.net.client_ready, "a control-mode change needs a fresh ready")


func test_repeated_host_and_join_are_ignored() -> void:
	assert_eq(host_game.host_lan(), OK)
	assert_eq(host_game.host_lan(), ERR_ALREADY_IN_USE)
	assert_eq(client_game.join_lan("127.0.0.1"), OK)
	assert_eq(client_game.join_lan("127.0.0.1"), ERR_ALREADY_IN_USE)
	await _real_wait(10000, func() -> bool: return host_game.race != null and client_game.race != null)
	assert_eq(_races_in(host_game), 1)


func test_visitor_leaving_the_lobby_keeps_the_host_waiting() -> void:
	assert_eq(host_game.host_lan(), OK)
	var visitor := NetLink.new()
	add_child_autofree(visitor)
	visitor.join("127.0.0.1", PORT)
	await _real_wait(4000, func() -> bool: return host_game._pending_peer != 0)
	visitor.close()
	await _real_wait(15000, func() -> bool: return host_game._pending_peer == 0)
	assert_eq(host_game._pending_peer, 0)
	assert_null(host_game.race)
	await _real_wait(500, func() -> bool: return false)
	assert_eq(client_game.join_lan("127.0.0.1"), OK)
	await _real_wait(10000, func() -> bool: return host_game.race != null and client_game.race != null)
	assert_not_null(client_game.race, "a real player can still join")


func test_disconnect_on_the_results_screen() -> void:
	await _connect_both()
	await _ready_and_start()
	var h: Node2D = host_game.race
	var cps: int = h.track.checkpoint_count()
	for id in [RaceSession.PLAYER_ID, RaceSession.PLAYER_2_ID]:
		for lap in h.session.lap_count():
			for i in range(1, cps):
				h.session.checkpoint_reached(i, id)
			h.session.checkpoint_reached(0, id)
	await _real_wait(3000, func() -> bool: return client_game.race.session.state == RaceSession.State.FINISHED)
	assert_eq(client_game.race.session.state, RaceSession.State.FINISHED)
	client_game.close_lan()
	await _real_wait(8000, func() -> bool: return h.network_lost)
	assert_true(h.network_lost, "results screen also ends cleanly")


func test_connection_quality_indicator() -> void:
	await _connect_both()
	var c: Node2D = client_game.race
	await wait_physics_frames(5)
	assert_true(c.hud._net_label.visible)
	assert_string_contains(c.hud._net_label.text, "PING")
	host_game.close_lan()  # the host goes silent (and away)
	await _real_wait(2500, func() -> bool: return c.network_lost or c.net.silence_ms() > 1600)
	assert_true(c.network_lost or c.net.connection_bad(), "silence is reported")
