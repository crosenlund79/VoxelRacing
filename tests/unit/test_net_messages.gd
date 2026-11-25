extends GutTest
## M5.1: network building blocks — snapshot encode / decode, the remote
## driver's exactly-once weapon presses under duplicated, late and lost
## packets, and the ENet link (connect, messages, one client only).

const MAIN_SCENE := preload("res://src/main/main.tscn")


func test_snapshot_round_trip_carries_cars_and_race_state() -> void:
	var m: Node2D = MAIN_SCENE.instantiate()
	m.presentation_enabled = false
	add_child_autofree(m)
	await wait_physics_frames(2)
	m.start_race()
	await wait_physics_frames(90)
	m.session.checkpoint_reached(1, 3)
	var snap := RaceSnapshot.capture(m, 77)
	var back := RaceSnapshot.decode(RaceSnapshot.encode(snap))
	assert_eq(RaceSnapshot.tick_of(back), 77)
	for c in m.cars.size():
		var st := RaceSnapshot.car_state(back, c)
		assert_almost_eq(st.position.distance_to(m.cars[c].global_position), 0.0, 0.01)
		assert_almost_eq(st.heading, m.cars[c].model.heading, 0.0001)
	var other: Node2D = MAIN_SCENE.instantiate()
	other.presentation_enabled = false
	add_child_autofree(other)
	await wait_physics_frames(1)
	RaceSnapshot.apply_race(other, back)
	var again := RaceSnapshot.capture(other, 77)
	assert_eq(other.session.state, RaceSession.State.RACING)
	assert_eq(again[2], back[2], "race clock")
	assert_eq(again[4], back[4], "every racer's laps, checkpoint, progress and finish")
	assert_eq(again[5], back[5], "finishing order")
	assert_eq(other.session.racers[3].tracker.next_checkpoint, 2)


func test_snapshot_decoder_rejects_garbage() -> void:
	assert_eq(RaceSnapshot.decode(PackedByteArray([1, 2, 3])), [])


func _race_stub() -> Node2D:
	var m: Node2D = MAIN_SCENE.instantiate()
	m.presentation_enabled = false
	m.set_weapons_enabled.call_deferred(true)
	add_child_autofree(m)
	return m


func test_remote_presses_fire_exactly_once_despite_duplicates_and_loss() -> void:
	var m := _race_stub()
	await wait_physics_frames(2)
	m.start_race()
	var r := RemoteDriverInput.new(0)
	r.begin_race(0)
	r.receive(1, 1.0, true, 0, 0)
	assert_eq(r.weapons(m, 1.0 / 60.0, []), {"front": false, "rear": false})
	r.receive(2, 1.0, true, 1, 0)    # one front press
	r.receive(2, 1.0, true, 1, 0)    # duplicate packet
	r.receive(1, 0.0, false, 0, 0)   # late, older packet
	assert_eq(r.weapons(m, 1.0 / 60.0, []), {"front": true, "rear": false})
	assert_eq(r.weapons(m, 1.0 / 60.0, []), {"front": false, "rear": false}, "never twice")
	r.receive(5, 0.0, true, 3, 1)    # packets 3-4 lost: two more front presses, one rear
	var shots := 0
	var mines := 0
	for k in 4:
		var w := r.weapons(m, 1.0 / 60.0, [])
		shots += int(w.front)
		mines += int(w.rear)
	assert_eq(shots, 2, "lost presses are not lost")
	assert_eq(mines, 1)
	assert_eq(r.drive(m, 1.0 / 60.0), {"steer": 0.0, "fire": true, "pit_override": false}, "newest command drives")


func test_presses_before_the_start_are_not_carried_into_the_race() -> void:
	var m := _race_stub()
	await wait_physics_frames(2)
	var r := RemoteDriverInput.new(0)
	r.receive(1, 0.0, false, 4, 2)
	r.begin_race(0)
	m.start_race()
	assert_eq(r.weapons(m, 1.0 / 60.0, []), {"front": false, "rear": false})


func test_link_connects_one_client_and_exchanges_messages() -> void:
	var host := NetLink.new()
	var client := NetLink.new()
	var third := NetLink.new()
	for l in [host, client, third]:
		add_child_autofree(l)
	assert_eq(host.host(24701), OK)
	var got := []
	host.message.connect(func(from: int, msg: Array) -> void: got.append(msg))
	var joined := []
	host.peer_joined.connect(func(id: int) -> void: joined.append(id))
	client.join("127.0.0.1", 24701)
	await wait_until(func() -> bool: return joined.size() == 1 and client.peers().size() == 1, 5.0)
	client.send([NetRace.Msg.HELLO, NetRace.PROTOCOL], true)
	await wait_until(func() -> bool: return got.size() == 1, 3.0)
	assert_eq(got, [[NetRace.Msg.HELLO, NetRace.PROTOCOL]])
	var failed := []
	third.connection_failed.connect(func() -> void: failed.append(true))
	third.join("127.0.0.1", 24701)
	await wait_seconds(1.5)
	assert_eq(joined.size(), 1, "a second client cannot join")
	var left := []
	host.peer_left.connect(func(id: int) -> void: left.append(id))
	client.close()
	await wait_until(func() -> bool: return left.size() == 1, 5.0)
	assert_eq(left.size(), 1, "the host notices the client leaving")
	host.close()
	third.close()


func test_combat_state_round_trip() -> void:
	var rules := WeaponRules.new()
	var w := CombatWorld.new(rules, 3)
	w.enabled = true
	w.style = WeaponRules.Style.TACTICAL
	w.set_loadout(1, WeaponRules.Weapon.HOMING_MISSILE, 4, WeaponRules.Weapon.REAR_MISSILE, 2)
	var cars := [{"position": Vector2(0, 0), "heading": 0.0, "present": true},
		{"position": Vector2(400, 0), "heading": PI, "present": true}, {"position": Vector2(-300, 0), "heading": 0.0, "present": true}]
	w.request(0, CombatWorld.FRONT, cars)
	w.request(2, CombatWorld.REAR, cars)
	w.step(1.0 / 60.0, cars)
	w.wreck_left[1] = 2.5
	var data := RaceSnapshot.capture_combat(w)
	var back: Array = bytes_to_var(var_to_bytes(data))
	var copy := CombatWorld.new(rules, 3)
	RaceSnapshot.apply_combat(copy, back)
	assert_eq(copy.ammo, w.ammo)
	assert_eq(copy.loadout, w.loadout)
	assert_almost_eq(copy.wreck_left[1], 2.5, 0.0001)
	assert_true(copy.is_wrecked(1))
	assert_almost_eq(copy.slot_cooldown[0][0], w.slot_cooldown[0][0], 0.0001)
	assert_eq(copy.projectiles.size(), 1)
	assert_almost_eq(copy.projectiles[0].pos.distance_to(w.projectiles[0].pos), 0.0, 0.01)
	assert_eq(copy.mines.size(), 1)
	assert_eq(copy.mines[0].owner, 2)
