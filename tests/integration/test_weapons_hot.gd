extends GutTest
## Weapons Hot: weapons stay locked for everyone until every car in the race
## has crossed the start line for the first time; then they unlock together,
## once, with the announcer's "Weapons hot". No Guns races never lock or
## announce. Retired cars cannot hold the field, a car that never leaves the
## grid only until the timeout. Network clients follow the host.

const MAIN_SCENE := preload("res://src/main/main.tscn")
const P := RaceSession.PLAYER_ID

var _main: Node2D
var _lines: Array = []


func after_each() -> void:
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0
	Engine.max_physics_steps_per_frame = 8
	for a in [PlayerControls.FIRE, PlayerControls.FIRE_FRONT, PlayerControls.FIRE_REAR]:
		Input.action_release(a)
	_lines.clear()


func _make(weapons := true, spectate := false, presentation := false, style := WeaponRules.Style.CLASSIC) -> void:
	_main = MAIN_SCENE.instantiate()
	_main.presentation_enabled = presentation
	add_child_autofree(_main)
	await wait_physics_frames(2)
	if _main.voice != null:
		_main.voice.line_started.connect(func(id: String) -> void: _lines.append(id))
	if spectate:
		_main.set_menu_choice(2)
	_main.set_combat_style(style)
	_main.set_weapons_enabled(weapons)


func _fires() -> Array:
	return _main.combat.events.filter(func(e: Dictionary) -> bool: return e.kind == "fire" or e.kind == "empty")


## Shots and empty clicks logged before the unlock event.
func _fires_before_unlock() -> Array:
	var out := []
	for e in _main.combat.events:
		if e.kind == "unlock":
			break
		if e.kind == "fire" or e.kind == "empty":
			out.append(e)
	return out


func _unlocks() -> int:
	return _main.combat.events.filter(func(e: Dictionary) -> bool: return e.kind == "unlock").size()


func test_nobody_fires_before_the_field_is_through_then_everyone_can() -> void:
	await _make(true, false, false, WeaponRules.Style.TACTICAL)
	var ammo_before: Array = _main.combat.ammo.duplicate(true)
	var at_unlock := {}
	_main.weapons_unlocked.connect(func() -> void: at_unlock["ammo"] = _main.combat.ammo.duplicate(true))
	_main.start_race()
	Input.action_press(PlayerControls.FIRE)
	assert_true(_main.combat.locked, "locked at the start")
	var unlocked_at := -1.0
	var t := 0
	while _main.combat.locked and t < 60 * 20:
		Input.action_press(PlayerControls.FIRE_FRONT)  # the player keeps trying
		await wait_physics_frames(1)
		Input.action_release(PlayerControls.FIRE_FRONT)
		await wait_physics_frames(1)
		t += 2
		assert_false(_main.combat.can_fire(P, CombatWorld.FRONT) and _main.combat.locked)
	unlocked_at = _main.session.elapsed
	assert_false(_main.combat.locked, "unlocked")
	assert_eq(_fires_before_unlock(), [], "no shot and no empty click from anyone while locked")
	assert_eq(at_unlock.get("ammo"), ammo_before, "no ammunition used before the unlock")
	for id in _main.grid_order:
		assert_gte(_main.progress[id].distance, 0.0, "every car is through the start line")
	assert_lt(unlocked_at, _main.weapons_lock_timeout, "the field got through (not the timeout)")
	assert_eq(_unlocks(), 1)
	await wait_seconds(4.0)
	assert_gt(_fires().size(), 0, "rivals fire once weapons are live, with no extra delay")
	assert_eq(_unlocks(), 1, "unlocked once per race")


func test_presses_during_the_lock_are_never_fired_later() -> void:
	await _make()
	_main.start_race()
	Input.action_press(PlayerControls.FIRE_FRONT)
	await wait_physics_frames(1)
	Input.action_release(PlayerControls.FIRE_FRONT)
	while _main.combat.locked:
		await wait_physics_frames(1)
	await wait_physics_frames(10)
	var mine: Array = _main.combat.events.filter(func(e: Dictionary) -> bool: return e.kind == "fire" and e.car == P)
	assert_eq(mine.size(), 0, "the early press did not fire at the unlock")


func test_no_guns_never_locks_or_shows_the_warning() -> void:
	await _make(false, false, true)
	_main.start_race()
	await wait_process_frames(2)
	assert_false(_main.combat.locked)
	assert_false(_main.hud.weapons_locked_shown())
	await wait_seconds(4.0)
	assert_eq(_unlocks(), 0)
	assert_false(_lines.has("announcer_weapons_hot"), "never announced without weapons")


func test_hud_warning_and_the_announcement_once() -> void:
	await _make(true, false, true)
	_main.start_race()
	await wait_process_frames(2)
	assert_true(_main.hud.weapons_locked_shown(), "WEAPONS LOCKED on the HUD")
	assert_string_contains(_main.hud._lock_label.text, "WEAPONS LOCKED")
	await wait_until(func() -> bool: return not _main.combat.locked, 20.0)
	await wait_process_frames(3)
	assert_false(_main.hud.weapons_locked_shown())
	assert_eq(_lines.filter(func(l: String) -> bool: return l == "announcer_weapons_hot").size(), 1, "Weapons hot!")
	await wait_seconds(5.0)
	assert_eq(_lines.filter(func(l: String) -> bool: return l == "announcer_weapons_hot").size(), 1, "never again this race")


func test_each_race_locks_again() -> void:
	await _make(true, true)
	_main.set_sim_speed(8)
	_main.start_race()
	await wait_until(func() -> bool: return not _main.combat.locked, 20.0)
	var first: int = _main.races_started
	await wait_until(func() -> bool: return _main.races_started > first, 120.0)  # the spectator's next race
	assert_true(_main.combat.locked, "locked again on the next grid")
	assert_eq(_unlocks(), 0, "fresh events")
	await wait_until(func() -> bool: return not _main.combat.locked, 20.0)
	assert_eq(_unlocks(), 1)


func test_a_retired_car_never_holds_the_field_and_a_stuck_one_only_until_the_timeout() -> void:
	await _make(true, true)  # spectating: the nine rivals
	_main.start_race()
	await wait_physics_frames(2)
	_main.damage.condition[9] = 0.0
	_main._retire(9)  # out before crossing the line
	await wait_until(func() -> bool: return not _main.combat.locked, 20.0)
	assert_false(_main.combat.locked, "the others got through: unlocked")
	assert_lt(_main.session.elapsed, _main.weapons_lock_timeout)
	_main.queue_free()
	await wait_physics_frames(2)
	await _make()
	_main.weapons_lock_timeout = 4.0
	_main.start_race()  # the player never accelerates: stuck on the grid
	await wait_seconds(3.0)
	assert_true(_main.combat.locked, "still waiting for the player")
	await wait_seconds(1.5)
	assert_false(_main.combat.locked, "the timeout never lets one car lock the race")


func test_spectators_hear_the_announcement_too() -> void:
	await _make(true, true, true)
	_main.start_race()
	await wait_until(func() -> bool: return not _main.combat.locked, 20.0)
	await wait_process_frames(3)
	assert_has(_lines, "announcer_weapons_hot")


func test_network_client_follows_the_hosts_lock() -> void:
	var host_link := NetLink.new()
	var client_link := NetLink.new()
	add_child_autofree(host_link)
	add_child_autofree(client_link)
	host_link.host(24781)
	client_link.join("127.0.0.1", 24781)
	await wait_until(func() -> bool: return host_link.peers().size() == 1 and client_link.peers().size() == 1, 5.0)
	var host: Node2D = MAIN_SCENE.instantiate()
	host.presentation_enabled = false
	host.human_count = 2
	host.net = NetRace.new(host_link, NetRace.Role.HOST)
	add_child_autofree(host)
	var vp := SubViewport.new()
	add_child_autofree(vp)
	var client: Node2D = MAIN_SCENE.instantiate()
	client.presentation_enabled = false
	client.human_count = 2
	client.net = NetRace.new(client_link, NetRace.Role.CLIENT)
	vp.add_child(client)
	await wait_physics_frames(10)
	host.set_weapons_enabled(true)
	await wait_physics_frames(4)
	client.net.local_ready = true
	client.net._send_ready()
	await wait_until(func() -> bool: return host.net.client_ready, 3.0)
	host.start_race()
	await wait_until(func() -> bool: return client.session.state == RaceSession.State.RACING, 3.0)
	await wait_physics_frames(20)
	assert_true(host.combat.locked)
	assert_true(client.combat.locked, "the client shows the lock")
	for c in [host.cars[RaceSession.PLAYER_ID], host.cars[RaceSession.PLAYER_2_ID]]:  # the humans drive through
		c.model.velocity = Vector2.from_angle(c.model.heading) * 300.0
	host.inputs[RaceSession.PLAYER_ID] = Push.new()
	client.net.input_source = func() -> Dictionary: return {"steer": 0.0, "fire": true}
	await wait_until(func() -> bool: return not host.combat.locked, 20.0)
	assert_false(host.combat.locked)
	await wait_until(func() -> bool: return not client.combat.locked, 3.0)
	assert_false(client.combat.locked, "the client agrees")
	await wait_until(func() -> bool: return client.combat.events.any(func(e: Dictionary) -> bool: return e.kind == "unlock"), 3.0)
	assert_eq(client.combat.events.filter(func(e: Dictionary) -> bool: return e.kind == "unlock").size(), 1, "the unlock reaches the client once")
	host_link.close()
	client_link.close()
	client.queue_free()


class Push extends DriverInput:
	func drive(_r: Node, _s: float) -> Dictionary:
		return {"steer": 0.0, "fire": true}
