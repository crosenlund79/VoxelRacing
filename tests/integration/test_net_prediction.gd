extends GutTest
## M5.2 Stage 2: client-side prediction of the local car with reconciliation.
## The client's own car answers its input at once (unchanged Car / CarModel,
## walls only); host snapshots correct it (small errors blended, large ones
## applied at once, each correction counted once); remote cars stay
## interpolated; no prediction while wrecked; the host stays authoritative.

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
	host_link.host(24761)
	client_link.join("127.0.0.1", 24761)
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


func _start(fire: bool) -> void:
	client.net.input_source = func() -> Dictionary: return {"steer": 0.0, "fire": fire}
	client.net.local_ready = true
	client.net._send_ready()
	await wait_until(func() -> bool: return host.net.client_ready, 3.0)
	host.start_race()
	await wait_until(func() -> bool: return client.session.state == RaceSession.State.RACING, 3.0)


func test_own_car_answers_input_at_once_despite_latency() -> void:
	client_link.sim_latency_ms = 150
	host_link.sim_latency_ms = 150
	await _start(false)
	await wait_physics_frames(10)
	var p0: Vector2 = client.cars[P2].global_position
	client.net.input_source = func() -> Dictionary: return {"steer": 0.0, "fire": true}
	await wait_physics_frames(4)
	assert_gt(client.cars[P2].global_position.distance_to(p0), 0.5, "predicted: moves within a few ticks")
	assert_true(client.cars[P2].active)
	assert_eq(client.cars[P2].collision_mask, 1, "predicted car only collides with walls")
	assert_false(client.cars[3].active, "remote cars are not simulated on the client")


func test_without_prediction_the_car_waits_for_the_host() -> void:
	client.net.predict = false
	client_link.sim_latency_ms = 150
	host_link.sim_latency_ms = 150
	await _start(false)
	await wait_physics_frames(10)
	var p0: Vector2 = client.cars[P2].global_position
	client.net.input_source = func() -> Dictionary: return {"steer": 0.0, "fire": true}
	await wait_physics_frames(4)
	assert_almost_eq(client.cars[P2].global_position.distance_to(p0), 0.0, 0.5, "no prediction: still where the host last said")


func test_prediction_tracks_the_host_closely_without_latency() -> void:
	await _start(true)
	await wait_physics_frames(180)
	var n: NetRace = client.net
	assert_gt(n.corrections, 20)
	assert_lt(n.correction_sum / n.corrections, 8.0, "average correction small (same car model on both)")
	assert_lt(client.cars[P2].global_position.distance_to(host.cars[P2].global_position), 40.0)


func test_small_errors_blend_large_errors_snap_and_count_once() -> void:
	await _start(true)
	await wait_physics_frames(60)
	var n: NetRace = client.net
	n.predict = true
	var ack: int = n.input_tick - 3
	assert_true(n._history.has(ack))
	var rec: Array = n._history[ack]
	var before: Vector2 = client.cars[P2].global_position
	n._last_ack = ack - 1
	n._reconcile(_snap_with_p2(rec[0] + Vector2(0, 10), rec[1], rec[2]), ack)
	var moved: Vector2 = client.cars[P2].global_position - before
	assert_almost_eq(moved.y, 10.0 * NetRace.BLEND, 0.01, "small error: blended")
	var after_first: Vector2 = client.cars[P2].global_position
	n._reconcile(_snap_with_p2(rec[0] + Vector2(0, 10), rec[1], rec[2]), ack)
	assert_eq(client.cars[P2].global_position, after_first, "the same ack is not applied twice")
	var ack2: int = n.input_tick - 1
	var rec2: Array = n._history[ack2]
	assert_almost_eq((rec2[0] - (n._history[ack2][0])).length(), 0.0, 0.001)
	var snaps: int = n.hard_snaps
	var b2: Vector2 = client.cars[P2].global_position
	n._reconcile(_snap_with_p2(rec2[0] + Vector2(200, 0), rec2[1], rec2[2]), ack2)
	assert_almost_eq((client.cars[P2].global_position - b2).x, 200.0, 0.01, "large error: applied at once")
	assert_eq(n.hard_snaps, snaps + 1)


func test_no_prediction_while_wrecked() -> void:
	host.set_weapons_enabled(true)
	await wait_physics_frames(3)
	await _start(true)
	await wait_physics_frames(30)
	host.combat._destroy(P2, 3, host.cars[P2].global_position, WeaponRules.Weapon.FRONT_MISSILE, [] as Array[int])
	host.cars[P2].active = false  # as the race scene does for a destroyed car
	host.cars[P2].model.velocity = Vector2.ZERO
	await wait_physics_frames(20)
	assert_true(client.combat.is_wrecked(P2))
	assert_false(client.cars[P2].active, "wrecked: not predicted")
	await wait_physics_frames(15)  # the shown position settles on the host's wreck spot
	var p: Vector2 = client.cars[P2].global_position
	await wait_physics_frames(10)
	assert_almost_eq(client.cars[P2].global_position.distance_to(p), 0.0, 1.0, "stays put like on the host")


## A snapshot of the current race with Player 2's state replaced.
func _snap_with_p2(pos: Vector2, heading: float, vel: Vector2) -> Array:
	var snap := RaceSnapshot.capture(host, 99999)
	var cars: PackedFloat32Array = snap[3]
	var k := P2 * RaceSnapshot.CAR_FIELDS
	cars[k] = pos.x
	cars[k + 1] = pos.y
	cars[k + 2] = heading
	cars[k + 3] = vel.x
	cars[k + 4] = vel.y
	snap[3] = cars
	return snap
