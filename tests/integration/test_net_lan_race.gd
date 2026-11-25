extends GutTest
## M5.1 Stage 1: two separate Godot processes (host and client) race over
## localhost through the real ENet transport; both humans are autopilots that
## steer through the normal input paths (the client's car only through INPUT
## messages). Both processes must show the same authoritative result, also
## with simulated latency and packet loss, and keep the reversed grid with the
## rival rotation across consecutive races.

const OUT := "user://net_probe_%s.json"


## Waits in real time (the suite runs with --fixed-fps, where GUT's waits are
## simulated time; the two child processes run in real time).
func _real_wait(ms: int, done: Callable) -> void:
	var deadline := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < deadline and not done.call():
		OS.delay_msec(20)
		await wait_physics_frames(1)


func _run(port: int, args: Array) -> Array:
	var h := ProjectSettings.globalize_path(OUT % ("host_%d" % port))
	var c := ProjectSettings.globalize_path(OUT % ("client_%d" % port))
	for f in [h, c]:
		DirAccess.remove_absolute(f)
	var base := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://tests/support/net_probe.gd", "--"]
	var common := ["port=%d" % port] + args
	var hp := OS.create_process(OS.get_executable_path(), PackedStringArray(base + ["role=host", "out=" + h] + common))
	await _real_wait(500, func() -> bool: return false)
	var cp := OS.create_process(OS.get_executable_path(), PackedStringArray(base + ["role=client", "out=" + c] + common))
	await _real_wait(150000, func() -> bool: return FileAccess.file_exists(h) and FileAccess.file_exists(c))
	await _real_wait(500, func() -> bool: return false)
	for pid in [hp, cp]:
		if OS.is_process_running(pid):
			OS.kill(pid)
	var out := []
	for f in [h, c]:
		out.append(JSON.parse_string(FileAccess.get_file_as_string(f)) if FileAccess.file_exists(f) else {})
		DirAccess.remove_absolute(f)
	return out


func test_host_and_client_agree_on_the_result() -> void:
	var r := await _run(24711, ["laps=1"])
	assert_true(r[0].has("results"), str(r[0]))
	assert_true(r[1].has("results"), str(r[1]))
	if not r[0].has("results") or not r[1].has("results"):
		return
	var host: Dictionary = r[0].results[0]
	assert_eq(r[1].results[0], host, "client shows the host's authoritative result")
	assert_eq(host.order.size(), 10, "two humans and eight rivals")
	assert_has(host.order, float(RaceSession.PLAYER_2_ID), "the client's car finished, driven only by network input")
	assert_eq(host.sitting_out, [1.0], "Victor sits out the first race")


func test_two_races_with_latency_and_loss_keep_agreeing_and_rotate() -> void:
	var r := await _run(24712, ["laps=1", "races=2", "latency=60", "loss=0.1"])
	if not r[0].has("results") or not r[1].has("results"):
		fail_test("no results: %s / %s" % [str(r[0]), str(r[1])])
		return
	assert_eq(r[1].results, r[0].results, "both races agree")
	var first: Dictionary = r[0].results[0]
	var second: Dictionary = r[0].results[1]
	var expected: Array = first.order.duplicate()
	expected.reverse()
	expected[expected.find(2.0)] = 1.0
	assert_eq(second.grid, expected, "reversed grid; returning Victor takes Rocco's slot")
	assert_eq(second.sitting_out, [2.0])


func test_armed_races_agree_classic_and_tactical() -> void:
	for style in [0, 1]:
		var r := await _run(24713 + style, ["laps=1", "weapons=1", "style=%d" % style, "fire_every=45", "latency=30", "loss=0.05"])
		if not r[0].has("results") or not r[1].has("results"):
			fail_test("style %d no results: %s / %s" % [style, str(r[0]), str(r[1])])
			continue
		var host: Dictionary = r[0].results[0]
		var client: Dictionary = r[1].results[0]
		for k in host:
			if k in ["variant", "night", "handling"]:
				continue  # each side's own environment report (test_new_environments_agree_over_the_network)
			if k in ["takeoffs", "falls"]:
				_assert_jumps_agree(host, client, k, "style %d" % style)
				continue
			assert_eq(client.get(k), host[k], "style %d: %s agrees on both" % [style, k])
		assert_gt(host.fired, 0.0)
		assert_gt(r[0].client_shots, 0.0, "the client's player fired through the network")


func test_internet_like_conditions_with_prediction() -> void:
	# ~80-120 ms round trip (40 ms + 0-20 ms jitter each way) and 3 % loss.
	var r := await _run(24716, ["laps=1", "weapons=1", "style=1", "fire_every=60", "latency=40", "jitter=20", "loss=0.03", "predict=1"])
	if not r[0].has("results") or not r[1].has("results"):
		fail_test("no results: %s / %s" % [str(r[0]), str(r[1])])
		return
	assert_eq(r[1].results, r[0].results, "authoritative result, shots and destructions agree")
	assert_gt(r[1].corrections, 100.0, "client reconciled continuously")
	assert_lt(r[1].avg_error, 20.0, "average correction stays small")


func test_high_latency_and_loss_fire_to_brake() -> void:
	# ~150-180 ms round trip (75 ms + 0-15 ms jitter each way), 5 % loss, the
	# client in Fire to Brake: still one authoritative result on both.
	var r := await _run(24717, ["laps=1", "weapons=1", "style=0", "fire_every=60", "latency=75", "jitter=15", "loss=0.05",
		"predict=1", "mode=1"])
	if not r[0].has("results") or not r[1].has("results"):
		fail_test("no results: %s / %s" % [str(r[0]), str(r[1])])
		return
	assert_eq(r[1].results, r[0].results)
	assert_has(r[0].results[0].order, float(RaceSession.PLAYER_2_ID), "the client's car finished")


func test_experimental_crossing_layout_agrees_with_prediction() -> void:
	# J1: the figure-eight with an elevated crossing; the client predicts its own
	# car through both levels (level-aware walls), the host stays authoritative.
	var r := await _run(24741, ["laps=1", "layout=exp_figure8_01", "latency=40"])
	assert_true(r[0].has("results") and r[1].has("results"), str(r))
	if not r[0].has("results") or not r[1].has("results"):
		return
	assert_eq(r[1].results[0], r[0].results[0], "client shows the host's result")
	assert_eq(r[0].results[0].order.size(), 10)


func test_experimental_crossing_armed_race_agrees() -> void:
	# J4: elevation-aware combat stays host-authoritative; the client shows the
	# host's result and the same destructions
	var r := await _run(24743, ["laps=1", "layout=exp_figure8_01", "weapons=1", "style=1", "latency=30"])
	assert_true(r[0].has("results") and r[1].has("results"), str(r))
	if not r[0].has("results") or not r[1].has("results"):
		return
	for k in r[0].results[0]:  # (key by key: a failure names the field)
		if k in ["takeoffs", "falls"]:
			continue  # observed per computer: compared like every jump race below
		assert_eq(r[1].results[0].get(k), r[0].results[0][k], "same result, same destructions: %s" % k)
	for k in ["takeoffs", "falls"]:  # (the figure-eight has the J3 jump)
		_assert_jumps_agree(r[0].results[0], r[1].results[0], k, "crossing armed")


## J5: real jumps over the network. The client's car crawls up to the lip
## (fall=1) so it falls into the gap: takeoff, failed landing, the fall's
## damage and the recovery all go through prediction and the host's
## corrections. Both computers must agree on everything, jumps included.
## Jump outcomes: every car exactly; the client's own car may show one
## predicted takeoff / fall more that the host corrected (contacts are not
## predicted on the client), never fewer.
func _assert_jumps_agree(host: Dictionary, client: Dictionary, k: String, label: String) -> void:
	var me := str(RaceSession.PLAYER_2_ID)
	for id in host[k]:
		if id != me:
			assert_eq(client[k].get(id, 0.0), host[k][id], "%s: %s of car %s agree" % [label, k, id])
	var extra: float = client[k].get(me, 0.0) - host[k].get(me, 0.0)
	assert_true(extra >= 0.0 and extra <= 1.0, "%s: own-car %s %s vs host %s" % [label, k, client[k].get(me, 0.0), host[k].get(me, 0.0)])


func _assert_jump_race(r: Array, label: String) -> void:
	assert_true(r[0].has("results") and r[1].has("results"), "%s: %s" % [label, str(r)])
	if not r[0].has("results") or not r[1].has("results"):
		return
	var host: Dictionary = r[0].results[0]
	var client: Dictionary = r[1].results[0]
	for k in ["order", "times", "positions", "condition", "ammo", "dnf", "destroyed"]:
		assert_eq(client[k], host[k], "%s: %s agree" % [label, k])
	for k in ["takeoffs", "falls"]:
		_assert_jumps_agree(host, client, k, label)
	assert_gt(int(host.falls.get(str(RaceSession.PLAYER_2_ID), 0)), 0, label + ": the client's car fell in")
	assert_lt(host.condition[RaceSession.PLAYER_2_ID], 100.0, label + ": the fall damaged it")


func test_jumps_with_falls_agree_with_latency_jitter_and_loss() -> void:
	var r := await _run(24751, ["laps=2", "layout=kestrel_ridge", "latency=100", "jitter=30", "loss=0.03", "fall=1", "timeout=140"])
	_assert_jump_race(r, "Kestrel Ridge 100 ms")


func test_armed_jump_race_at_170_ms_agrees() -> void:
	var r := await _run(24752, ["laps=2", "layout=ravenhook", "latency=170", "jitter=40", "loss=0.05", "fall=1",
		"weapons=1", "style=1", "fire_every=45", "timeout=220"])  # (140 s: too tight for a slow field under full-suite load)
	_assert_jump_race(r, "Ravenhook 170 ms Tactical")
	if r[1].has("jump_corrections"):
		assert_lt(int(r[1].jump_corrections), 5, "jump predictions rarely need correcting")


## The Raceway (night) and Tabletop Mayhem over the network: both computers
## race the same environment with its own handling (Raceway top speed and
## grip, Tabletop acceleration), with real jumps, falls, weapons and damage,
## and agree on the result.
func test_new_environments_agree_over_the_network() -> void:
	var base: DrivingParams = load("res://src/driving/default_driving_params.tres")
	var r := await _run(24761, ["laps=2", "layout=kestrel_ridge", "track=4", "night=1", "latency=80", "jitter=20",
		"loss=0.02", "fall=1", "weapons=1", "fire_every=60", "timeout=140"])
	_assert_jump_race(r, "Raceway night 80 ms")
	if r[0].has("results") and r[1].has("results"):
		assert_eq(r[1].results[0].handling, r[0].results[0].handling, "identical handling on both computers")
	for side in r:
		side = side.results[0] if side.has("results") else {"variant": 0, "night": false, "handling": [0, 0, 0]}
		assert_eq(int(side.variant), 4, "The Raceway on both computers")
		assert_true(bool(side.night))
		assert_almost_eq(float(side.handling[0]), base.max_speed * 1.05, 0.01, "Raceway top speed")
	var t := await _run(24762, ["laps=2", "layout=ravenhook", "track=5", "latency=60", "fall=1", "weapons=1",
		"style=1", "fire_every=45", "timeout=140"])
	_assert_jump_race(t, "Tabletop 60 ms Tactical")
	for side in t:
		side = side.results[0] if side.has("results") else {"variant": 0, "handling": [0, 0, 0]}
		assert_eq(int(side.variant), 5, "Tabletop Mayhem on both computers")
		assert_almost_eq(float(side.handling[1]), base.acceleration * 1.28, 0.01, "Tabletop acceleration")


## Pit lanes over the network: the host decides the pit stop (a damaged rival
## drives into the box, stops and gets +30); the client sees the service in
## the snapshots and both computers agree on condition and the result.
func test_pit_stop_is_host_authoritative_and_agrees() -> void:
	var r := await _run(24771, ["laps=3", "layout=kestrel_ridge", "latency=80", "jitter=20", "loss=0.02", "pit=1", "timeout=200"])
	assert_true(r[0].has("results") and r[1].has("results"), str(r))
	if not r[0].has("results") or not r[1].has("results"):
		return
	var host: Dictionary = r[0].results[0]
	var client: Dictionary = r[1].results[0]
	assert_eq(int(client.pit_car), int(host.pit_car), "the same rival on both computers")
	assert_gte(int(host.pit_stops[int(host.pit_car)]), 1, "the damaged rival made a pit stop on the host")
	assert_gt(int(client.pit_progress_seen), 20, "the client saw the service progress in the snapshots")
	assert_gte(int(host.pit_bay_seen), 0, "the host gave it a service bay")
	assert_eq(int(client.pit_bay_seen), int(host.pit_bay_seen), "the client sees the same bay held")
	for k in ["order", "times", "condition", "dnf"]:
		assert_eq(client[k], host[k], "pit race: %s agree" % k)
