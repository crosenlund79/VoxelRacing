extends GutTest
## M6 over the network: the host alone decides damage, condition, DNF and the
## final classification; the client shows the same values (snapshots) and
## never counts damage itself (also not for its own predicted car).

const MAIN_SCENE := preload("res://src/main/main.tscn")
const P2 := RaceSession.PLAYER_2_ID

var host_link: NetLink
var client_link: NetLink
var host: Node2D
var client: Node2D


func before_each() -> void:
	host_link = NetLink.new()
	client_link = NetLink.new()
	add_child_autofree(host_link)
	add_child_autofree(client_link)
	host_link.host(24751)
	client_link.join("127.0.0.1", 24751)
	await wait_until(func() -> bool: return host_link.peers().size() == 1 and client_link.peers().size() == 1, 5.0)
	host = _make(NetRace.Role.HOST, self)
	var vp := SubViewport.new()
	add_child_autofree(vp)
	client = _make(NetRace.Role.CLIENT, vp)
	await wait_physics_frames(10)


func after_each() -> void:
	host_link.close()
	client_link.close()


func _make(role: NetRace.Role, parent: Node) -> Node2D:
	var m: Node2D = MAIN_SCENE.instantiate()
	m.presentation_enabled = false
	m.human_count = 2
	m.net = NetRace.new(host_link if role == NetRace.Role.HOST else client_link, role)
	parent.add_child(m)
	if parent == self:
		autofree(m)
	return m


func _race(weapons := true) -> void:
	host.set_weapons_enabled(weapons)
	await wait_physics_frames(4)
	client.net.local_ready = true
	client.net._send_ready()
	await wait_until(func() -> bool: return host.net.client_ready, 3.0)
	host.start_race()
	await wait_until(func() -> bool: return client.session.state == RaceSession.State.RACING, 3.0)


func _mine_on(id: int) -> void:
	host.combat.mines.append({"owner": 9 if id != 9 else 8, "pos": host.cars[id].global_position,
		"age": host.combat.rules.mine_fuse - 0.01})


func test_client_shows_the_hosts_condition_and_dnf() -> void:
	await _race()
	var victim := -1
	for id in host.grid_order:
		if id != P2 and id != RaceSession.PLAYER_ID and not host.combat.is_wrecked(id):
			victim = id
			break
	_mine_on(victim)
	_mine_on(P2)
	await wait_physics_frames(3)
	var hurt: float = host.damage.condition[P2]
	assert_lt(hurt, 100.0, "the host damaged the client's car")
	await wait_until(func() -> bool: return client.damage.condition[P2] == hurt, 2.0)
	assert_eq(client.damage.condition[P2], hurt, "the client shows its own car's condition")
	assert_eq(client.damage.condition[victim], host.damage.condition[victim])
	# the host retires a rival: the client sees the DNF
	host.damage.condition[victim] = 1.0
	host.combat.wreck_left[victim] = 0.0
	host.combat.grace_left[victim] = 0.0
	_mine_on(victim)
	await wait_physics_frames(3)
	assert_true(host.session.racers[victim].dnf)
	await wait_until(func() -> bool: return client.session.racers[victim].dnf, 2.0)
	assert_true(client.session.racers[victim].dnf, "the client agrees")
	assert_eq(client.damage.condition[victim], 0.0)
	await wait_physics_frames(int(host.damage_rules.retired_show_time * 60.0) + 20)
	assert_false(host.cars[victim].visible, "taken off the road on the host")
	assert_false(client.cars[victim].visible, "and on the client")


func test_client_never_counts_damage_itself() -> void:
	await _race(false)
	client._queue_impact(P2, -1, 900.0)  # a hard predicted wall hit on the client
	await wait_physics_frames(2)
	assert_eq(client._impacts.size(), 0, "ignored: the host decides")
	assert_eq(host.damage.condition[P2], client.damage.condition[P2])


func test_final_classification_agrees_with_a_dnf() -> void:
	await _race()
	host.damage.condition[P2] = 1.0
	_mine_on(P2)
	await wait_physics_frames(3)
	assert_true(host.session.racers[P2].dnf, "the client's player is out")
	assert_eq(host.session.state, RaceSession.State.RACING, "the host player is still racing")
	await wait_until(func() -> bool: return client.session.racers[P2].dnf, 2.0)
	var cps: int = host.track.checkpoint_count()
	for id in host.grid_order:
		if id == P2:
			continue
		for lap in host.session.lap_count():
			for i in range(1, cps):
				host.session.checkpoint_reached(i, id)
			host.session.checkpoint_reached(0, id)
	await wait_physics_frames(2)
	assert_true(host.session.all_finished())
	await wait_until(func() -> bool: return client.network_results.size() == host.session.finish_order.size(), 3.0)
	assert_eq(client.network_results, host.session.finish_order, "same order on both computers")
	assert_eq(client.network_results[-1], P2, "the DNF classified last")
	assert_true(client.session.racers[P2].dnf)
