extends GutTest
## M5.2 Stage 1: internet-ready host / join on the existing ENet layer —
## address parsing (LAN, localhost, public IPv4, :port), the version handshake
## in both directions, a silent visitor being dropped, unexpected senders and
## malformed messages ignored, and the host's track / laps / weapons / style
## applied on both computers.

const GAME_SCENE := preload("res://src/main/game.tscn")
const PORT := 24751

var host_game: Node
var client_game: Node


func before_each() -> void:
	host_game = _make_game(self, "h")
	var vp := SubViewport.new()
	add_child_autofree(vp)
	client_game = _make_game(vp, "c")
	await wait_physics_frames(3)


func after_each() -> void:
	for g in [host_game, client_game]:
		if is_instance_valid(g):
			g.close_lan()
			g.title.stop_audio()
	for t in ["h", "c"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_net_inet_%s.cfg" % t))


func _make_game(parent: Node, tag: String) -> Node:
	var g := GAME_SCENE.instantiate()
	g.achievements_path = "user://test_net_inet_%s.cfg" % tag
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


func test_address_parsing() -> void:
	assert_eq(NetLink.parse_address("192.168.1.20"), {"ok": true, "ip": "192.168.1.20", "port": 24680, "error": ""})
	assert_eq(NetLink.parse_address(" 203.0.113.7:30000 ").port, 30000, "public address with a port")
	assert_eq(NetLink.parse_address("localhost").ip, "127.0.0.1")
	assert_false(NetLink.parse_address("203.0.113.7:abc").ok)
	assert_false(NetLink.parse_address("203.0.113.7:70000").ok)
	assert_false(NetLink.parse_address("my friend's pc").ok)
	assert_false(NetLink.parse_address("").ok)
	assert_false(NetLink.parse_address("2001:db8::1").ok, "IPv6 not supported in this prototype")


func test_message_validation() -> void:
	assert_true(NetRace.valid([NetRace.Msg.INPUT, 5, 1.0, true, 0, 0], [TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_INT, TYPE_INT]))
	assert_true(NetRace.valid([NetRace.Msg.INPUT, 5, 1, true, 0, 0], [TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_INT, TYPE_INT]), "int steer accepted")
	assert_false(NetRace.valid([NetRace.Msg.INPUT, "5", 1.0, true, 0, 0], [TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_INT, TYPE_INT]))
	assert_false(NetRace.valid([NetRace.Msg.INPUT, 5, 1.0, true, 0], [TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_INT, TYPE_INT]), "too short")
	var ok := {"laps": 3, "weapons": true, "style": 1, "round": 0, "grid": [2, 3, 4, 5, 6, 7, 8, 9, 10, 0], "races": 0}
	assert_true(NetRace.valid_setup(ok, 11))
	for bad in [{"laps": 0}, {"style": 7}, {"grid": [1, 1, 2, 3, 4, 5, 6, 7, 8, 9]}, {"grid": [2, 3]}, {"weapons": "yes"}, {"grid": [2, 3, 4, 5, 6, 7, 8, 9, 10, 44]}]:
		var cfg := ok.duplicate()
		cfg.merge(bad, true)
		assert_false(NetRace.valid_setup(cfg, 11), str(bad))
	assert_false(NetRace.valid_setup("not a dict", 11))
	assert_false(RaceSnapshot.is_valid([1, 1, 0.0, PackedFloat32Array(), PackedFloat32Array(), PackedInt32Array()], 11, 11))


func test_join_with_port_and_host_settings_apply_on_both() -> void:
	host_game.title.track_variant = 3
	host_game.title.laps = 7
	host_game.title.weapons_on = true
	host_game.title.combat_style = WeaponRules.Style.TACTICAL
	assert_eq(host_game.host_lan(), OK)
	assert_string_contains(host_game.title.lan_panel._status.text, "UDP port %d" % PORT)
	assert_eq(client_game.join_lan("127.0.0.1:%d" % PORT), OK)
	await _real_wait(10000, func() -> bool:
		return host_game.race != null and client_game.race != null and client_game.race.is_inside_tree() \
			and host_game.race.is_inside_tree() and client_game.race.session.lap_count() == 7)
	var h: Node2D = host_game.race
	var c: Node2D = client_game.race
	assert_not_null(c)
	if c == null:
		return
	assert_eq(c.track_variant, 3, "host's track")
	assert_eq(c.track_theme.display_name, h.track_theme.display_name)
	assert_eq(c.session.lap_count(), 7, "host's laps")
	assert_true(c.weapons_enabled, "host's weapons")
	assert_eq(c.combat_style, WeaponRules.Style.TACTICAL, "host's combat style")
	assert_eq(c.grid_order, h.grid_order)


func test_host_refuses_a_different_version() -> void:
	assert_eq(host_game.host_lan(), OK)
	var visitor := NetLink.new()
	add_child_autofree(visitor)
	var got := []
	visitor.message.connect(func(_f: int, msg: Array) -> void:
		got.append(msg[0])
		if msg[0] == NetRace.Msg.WELCOME:
			visitor.send([NetRace.Msg.HELLO, NetRace.PROTOCOL, "some-other-build"], true))
	visitor.join("127.0.0.1", PORT)
	await _real_wait(6000, func() -> bool: return got.has(NetRace.Msg.REJECT))
	assert_has(got, NetRace.Msg.WELCOME)
	assert_has(got, NetRace.Msg.REJECT)
	assert_null(host_game.race, "no session with a different version")
	visitor.close()


func test_client_refuses_a_host_with_a_different_version() -> void:
	var fake_host := NetLink.new()
	add_child_autofree(fake_host)
	fake_host.host(PORT)
	fake_host.peer_joined.connect(func(id: int) -> void:
		fake_host.send([NetRace.Msg.WELCOME, NetRace.PROTOCOL, "older-build", {"track_variant": 1}], true, id))
	client_game.join_lan("127.0.0.1")
	await _real_wait(6000, func() -> bool: return client_game.title.lan_panel._status.text.contains("different version"))
	assert_string_contains(client_game.title.lan_panel._status.text, "different version")
	assert_null(client_game.race)
	fake_host.close()


func test_a_silent_visitor_is_dropped_and_the_host_keeps_waiting() -> void:
	assert_eq(host_game.host_lan(), OK)
	var silent := NetLink.new()
	add_child_autofree(silent)
	var closed := []
	silent.server_closed.connect(func() -> void: closed.append(true))
	silent.join("127.0.0.1", PORT)
	await _real_wait(15000, func() -> bool: return closed.size() > 0)
	assert_eq(closed.size(), 1, "dropped after the HELLO timeout")
	assert_null(host_game.race)
	assert_true(host_game.link.is_open(), "still hosting")
	silent.close()


func test_messages_from_unexpected_senders_are_ignored() -> void:
	assert_eq(host_game.host_lan(), OK)
	assert_eq(client_game.join_lan("127.0.0.1"), OK)
	await _real_wait(10000, func() -> bool: return host_game.race != null and client_game.race != null)
	await wait_physics_frames(20)
	var c: Node2D = client_game.race
	var laps: int = c.session.lap_count()
	var net: NetRace = c.net
	net._on_message(77, [NetRace.Msg.SETUP, {"laps": 50, "weapons": true, "style": 1, "round": 0,
		"grid": c.grid_order.duplicate(), "races": 0}])
	assert_eq(c.session.lap_count(), laps, "a SETUP not from the host is ignored")
	net._on_message(1, [NetRace.Msg.SETUP, "garbage"])
	net._on_message(1, [NetRace.Msg.START])
	net._on_message(1, ["not a type"])
	assert_eq(c.session.state, RaceSession.State.MODE_SELECT, "malformed messages change nothing")
	var h: Node2D = host_game.race
	h.net._on_message(99, [NetRace.Msg.READY, true, 0])
	assert_false(h.net.client_ready, "READY from a stranger is ignored")
