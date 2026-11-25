extends GutTest
## M3.5 Stage 1 in the full scene: the combat style option, Classic reproducing
## M3 combat exactly, Tactical cooldowns for the player and the rivals, the HUD
## cooldown indicators, and armed Tactical / Classic / No Guns spectating.

const MAIN_SCENE := preload("res://src/main/main.tscn")
## Probe hashes of commit 18fb978 (M3 combat + lighting pilot), weapons ON.
## Classic must reproduce them exactly. Update only for an approved gameplay change.
## Re-recorded 2026-11-16 (race experience: rival lines and ammo pacing change races).
## Re-recorded 2026-11-17 for the human (race-mode) probes only: the approved
## steering precision change ramps the scripted player's key steering. Spectator
## hashes, pit lanes, split sections and lighting change nothing here.
## Re-recorded 2026-11-23: the approved AI ammunition pacing (when rivals fire).
const M3_CLASSIC_RACE_HASH := "3fc4c4820475e95e2e11a7cc529f69d4"
const M3_CLASSIC_SPECTATE_HASH := "972801697bd102240dcbc052ed8cd287"

var _main: Node2D


func before_each() -> void:
	_main = MAIN_SCENE.instantiate()
	_main.presentation_enabled = false
	_main.weapons_lock_enabled = false  # these tests fire at once (the start lock: test_weapons_hot.gd)
	add_child_autofree(_main)
	await wait_physics_frames(2)


func after_each() -> void:
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0
	Engine.max_physics_steps_per_frame = 8
	for a in [PlayerControls.FIRE, PlayerControls.FIRE_FRONT, PlayerControls.FIRE_REAR, PlayerControls.TOGGLE_STYLE]:
		Input.action_release(a)


func _tap(action: String) -> void:
	Input.action_press(action)
	await wait_physics_frames(2)
	Input.action_release(action)
	await wait_physics_frames(1)


func test_classic_reproduces_m3_combat_exactly() -> void:
	assert_eq(ProbeRunner.run(["mode=race", "ticks=1800", "weapons=1", "damage=0", "lock=0", "contact=0"]), M3_CLASSIC_RACE_HASH)
	assert_eq(ProbeRunner.run(["mode=spectate", "ticks=1800", "weapons=1", "damage=0", "lock=0", "contact=0"]), M3_CLASSIC_SPECTATE_HASH)


func test_tactical_is_identical_at_normal_and_fast_speed() -> void:
	var normal := ProbeRunner.run(["mode=spectate", "speed=1", "ticks=1500", "weapons=1", "style=1"])
	var fast := ProbeRunner.run(["mode=spectate", "speed=8", "ticks=1500", "weapons=1", "style=1"])
	assert_eq(normal.length(), 32, normal)
	assert_eq(fast, normal)
	assert_ne(normal, M3_CLASSIC_SPECTATE_HASH)


func test_c_on_the_grid_toggles_the_combat_style() -> void:
	assert_eq(_main.combat_style, WeaponRules.Style.CLASSIC)
	await _tap(PlayerControls.TOGGLE_STYLE)
	assert_eq(_main.combat_style, WeaponRules.Style.TACTICAL)
	assert_eq(_main.combat.style, WeaponRules.Style.TACTICAL)
	await _tap(PlayerControls.TOGGLE_STYLE)
	assert_eq(_main.combat_style, WeaponRules.Style.CLASSIC)


func test_style_cannot_change_during_a_race() -> void:
	_main.start_race()
	_main.set_combat_style(WeaponRules.Style.TACTICAL)
	assert_eq(_main.combat.style, WeaponRules.Style.CLASSIC)


func test_no_guns_disables_weapons_in_either_style() -> void:
	_main.set_combat_style(WeaponRules.Style.TACTICAL)
	_main.set_weapons_enabled(false)
	_main.set_menu_choice(2)
	_main.set_sim_speed(4)
	_main.start_race()
	await wait_physics_frames(900)
	assert_eq(_main.combat.events.size(), 0)


func test_tactical_player_front_cooldown_and_hud_bar() -> void:
	_main.set_weapons_enabled(true)
	_main.set_combat_style(WeaponRules.Style.TACTICAL)
	await _tap(PlayerControls.FIRE)
	await _tap(PlayerControls.FIRE_FRONT)
	var after_one: int = _main.combat.ammo[0][0]
	assert_eq(after_one, _main.combat.start_ammo[0][0] - 1)
	assert_gt(_main._cooldown_fraction(CombatWorld.FRONT), 0.5, "HUD bar shows the front cooldown")
	await wait_physics_frames(30)  # 0.5 s: past the shared lock, not the 1.5 s front cooldown
	await _tap(PlayerControls.FIRE_FRONT)
	assert_eq(_main.combat.ammo[0][0], after_one, "front slot still cooling down (1.5 s)")
	await _tap(PlayerControls.FIRE_REAR)
	assert_eq(_main.combat.ammo[0][1], _main.combat.start_ammo[0][1] - 1, "rear slot is independent")
	await wait_physics_frames(80)
	assert_eq(_main._cooldown_fraction(CombatWorld.FRONT), 0.0)
	await _tap(PlayerControls.FIRE_FRONT)
	assert_eq(_main.combat.ammo[0][0], after_one - 1)


func test_tactical_spectator_race_completes_and_rivals_respect_cooldowns() -> void:
	_main.set_menu_choice(2)
	_main.set_weapons_enabled(true)
	_main.set_combat_style(WeaponRules.Style.TACTICAL)
	_main.set_sim_speed(8)
	_main.start_race()
	var last_fire := {}
	var min_gap := {CombatWorld.FRONT: INF, CombatWorld.REAR: INF}
	var cursor := 0
	while _main.history.race_count() < 1:
		await wait_physics_frames(1)
		while cursor < _main.combat.events.size():
			var e: Dictionary = _main.combat.events[cursor]
			cursor += 1
			if e.kind != "fire":
				continue
			var slot := WeaponRules.slot_of(e.type)
			var key := "%d:%d" % [e.car, slot]
			var t: float = _main.session.elapsed
			if last_fire.has(key):
				min_gap[slot] = minf(min_gap[slot], t - last_fire[key])
			last_fire[key] = t
		if _main.session.elapsed > 400.0:
			break
	assert_eq(_main.history.race_count(), 1)
	assert_eq(_main.history.results[0].size(), 9)
	assert_gt(last_fire.size(), 0, "rivals fired")
	assert_true(min_gap[CombatWorld.FRONT] >= 1.5 - 0.02, "front gap %.3f" % min_gap[CombatWorld.FRONT])
	assert_true(min_gap[CombatWorld.REAR] >= 3.0 - 0.02 or min_gap[CombatWorld.REAR] == INF, "rear gap %.3f" % min_gap[CombatWorld.REAR])
