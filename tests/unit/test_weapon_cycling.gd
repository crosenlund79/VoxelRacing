extends GutTest
## Weapon cycling (2026-11-23): a car keeps one FRONT and one REAR slot and may
## carry several owned types per slot; cycling switches the active type without
## firing, using rounds, or touching the cooldowns / shared lock. The garage
## decides what is carried (every owned type, or the equipped ones only) and
## settles every carried type's rounds after the race. Pure logic.

const W := WeaponRules.Weapon
const F := CombatWorld.FRONT
const R := CombatWorld.REAR

var _rules: WeaponRules


func before_each() -> void:
	_rules = load("res://src/combat/default_weapon_rules.tres").duplicate()


func _world(style := WeaponRules.Style.CLASSIC) -> CombatWorld:
	var c := CombatWorld.new(_rules, 2)
	c.enabled = true
	c.style = style
	return c


func _cars() -> Array:
	return [{"position": Vector2(0, 0), "heading": 0.0, "present": true},
		{"position": Vector2(5000, 0), "heading": 0.0, "present": true}]


func test_nothing_carried_means_no_cycling_and_the_old_loadout() -> void:
	var c := _world()
	assert_false(c.cycle(0, F), "nothing else carried: the classic single-weapon loadout")
	assert_eq(c.loadout[0], [W.FRONT_MISSILE, W.MINE])
	assert_eq(c.slot_types(0, F), [[W.FRONT_MISSILE, _rules.front_ammo, true]])


func test_cycle_switches_type_and_keeps_every_rounds_count() -> void:
	var c := _world()
	c.set_loadout(0, W.FRONT_MISSILE, 5, W.MINE, 5)
	c.set_carried(0, F, {W.HOMING_MISSILE: 3, W.SUPER_MISSILE: 1, W.MINE: 9, W.FRONT_MISSILE: 7})
	assert_eq(c.carried[0][F], {W.HOMING_MISSILE: 3, W.SUPER_MISSILE: 1}, "only other types that fit the slot")
	assert_true(c.cycle(0, F))
	assert_eq(c.weapon_of(0, F), W.HOMING_MISSILE)
	assert_eq(c.ammo[0][F], 3)
	assert_true(c.cycle(0, F))
	assert_eq(c.weapon_of(0, F), W.SUPER_MISSILE)
	assert_true(c.cycle(0, F))
	assert_eq(c.weapon_of(0, F), W.FRONT_MISSILE, "wraps round in shop order")
	assert_eq(c.ammo[0][F], 5)
	assert_eq(c.rounds_by_type(0), {W.FRONT_MISSILE: 5, W.HOMING_MISSILE: 3, W.SUPER_MISSILE: 1, W.MINE: 5}, "no round gained or lost")
	assert_eq(c.weapon_of(0, R), W.MINE, "the other slot is untouched")
	assert_eq(c.shots_fired[0], 0, "cycling never fires")


func test_empty_types_are_skipped_and_never_give_free_ammo() -> void:
	var c := _world()
	c.set_loadout(0, W.FRONT_MISSILE, 1, W.MINE, 0)
	c.set_carried(0, F, {W.HOMING_MISSILE: 1})
	c.set_carried(0, R, {W.REAR_MISSILE: 0})
	assert_false(c.cycle(0, R), "the only other rear type is empty: no switch")
	assert_true(c.request(0, F, _cars()))
	c.step(1.0, _cars())
	assert_true(c.cycle(0, F))
	assert_true(c.request(0, F, _cars()))
	assert_eq(c.rounds_by_type(0)[W.HOMING_MISSILE], 0)
	assert_false(c.cycle(0, F), "both front types empty: nothing to switch to")
	assert_eq(c.slot_types(0, F), [[W.FRONT_MISSILE, 0, false], [W.HOMING_MISSILE, 0, true]])


func test_cycling_never_bypasses_cooldowns_or_the_shared_lock() -> void:
	for style in [WeaponRules.Style.CLASSIC, WeaponRules.Style.TACTICAL]:
		var c := _world(style)
		c.set_loadout(0, W.FRONT_MISSILE, 5, W.MINE, 5)
		c.set_carried(0, F, {W.HOMING_MISSILE: 5})
		assert_true(c.request(0, F, _cars()))
		var lock := c.cooldown[0]
		var slot: float = c.slot_cooldown[0][F]
		assert_true(c.cycle(0, F))
		assert_eq(c.cooldown[0], lock, "shared lock kept")
		assert_eq(c.slot_cooldown[0][F], slot, "slot cooldown kept")
		assert_false(c.request(0, F, _cars()), "the new type waits for the same cooldown")
		assert_eq(c.ammo[0][F], 5)


func test_garage_carries_owned_types_or_only_the_equipped_ones() -> void:
	var g := PlayerGarage.new(load("res://src/garage/default_garage_rules.tres"))
	assert_eq(g.race_carried(), [{}, {}], "starting supplies: one type per slot")
	g.money = 5000
	g.buy(W.HOMING_MISSILE, 4)
	g.buy(W.REAR_MISSILE, 2)
	assert_true(g.carry_all, "carrying every owned type is the default")
	assert_eq(g.race_carried(), [{W.HOMING_MISSILE: 4}, {W.REAR_MISSILE: 2}])
	assert_true(g.set_carry_all(false))
	assert_eq(g.race_carried(), [{}, {}], "the simple single-weapon loadout")
	g.begin_race()
	assert_false(g.set_carry_all(true), "not during a race")


func test_settlement_counts_every_carried_type_once() -> void:
	var g := PlayerGarage.new(load("res://src/garage/default_garage_rules.tres"))
	g.money = 5000
	g.buy(W.HOMING_MISSILE, 4)
	g.begin_race()
	g.settle_race(3, 0, 0, 100.0, 3, 0, {W.FRONT_MISSILE: 2, W.HOMING_MISSILE: 1, W.MINE: 5})
	assert_eq(g.count(W.FRONT_MISSILE), 2)
	assert_eq(g.count(W.HOMING_MISSILE), 1)
	assert_eq(g.count(W.MINE), 5)
	g.begin_race()
	g.settle_race(3, 0, 0, 100.0, 3, 0, {W.HOMING_MISSILE: 50})
	assert_eq(g.count(W.HOMING_MISSILE), 1, "rounds are never gained in a race")


func test_carry_setting_is_saved_and_old_saves_carry_everything() -> void:
	var path := "user://test_run/cycling_garage_%d.cfg" % randi()
	var rules: GarageRules = load("res://src/garage/default_garage_rules.tres")
	var g := PlayerGarage.load_or_new(rules, path)
	g.set_carry_all(false)
	assert_false(PlayerGarage.load_or_new(rules, path).carry_all)
	var old := ConfigFile.new()  # a save from before weapon cycling
	old.set_value("garage", "money", 123)
	old.save(path)
	var loaded := PlayerGarage.load_or_new(rules, path)
	assert_eq(loaded.money, 123)
	assert_true(loaded.carry_all)
	SafeSave.remove(path)


func test_cycle_controls_are_remappable_and_clash_free() -> void:
	PlayerControls.ensure_actions()
	for a in [PlayerControls.CYCLE_FRONT, PlayerControls.CYCLE_REAR]:
		assert_true(ControlBindings.is_remappable(a), a)
		assert_false(ControlBindings.events(a, ControlBindings.KEYBOARD).is_empty(), "%s has a key" % a)
		assert_false(ControlBindings.events(a, ControlBindings.PAD).is_empty(), "%s has a pad input" % a)
		for e in InputMap.action_get_events(a):
			for other in PlayerControls.PLAYER_ACTIONS + [PlayerControls.SIM_SPEED, PlayerControls.TOGGLE_PANEL, PlayerControls.TOGGLE_LIGHTING]:
				if other != a:
					assert_false(InputMap.event_is_action(e, other, true), "%s's default is not also %s" % [a, other])
	assert_true(PlayerControls.CYCLE_FRONT in PlayerControls.PLAYER_ACTIONS, "couch copies too")


func test_hud_lists_the_other_types_and_marks_empty_ones() -> void:
	var text := Hud.carried_text([[W.FRONT_MISSILE, 2, true], [W.HOMING_MISSILE, 0, false], [W.SUPER_MISSILE, 1, false]],
		PlayerControls.CYCLE_FRONT)
	assert_string_contains(text, "HOMING EMPTY")
	assert_string_contains(text, "SUPER 1")
	assert_false(text.contains("FRONT 2"), "the active type is shown in the slot itself")
	assert_eq(Hud.carried_text([[W.MINE, 3, true]], PlayerControls.CYCLE_REAR), "", "nothing else carried: no line")


## A controls.cfg saved before weapon cycling: the old layout loads unchanged;
## the new actions keep their defaults unless the old layout uses them.
func test_an_older_controls_file_keeps_working() -> void:
	var saved := ControlBindings.path
	ControlBindings.path = "user://test_run/old_controls_%d.cfg" % randi()
	var cfg := ConfigFile.new()
	var q := InputEventKey.new()
	q.physical_keycode = KEY_Q
	cfg.set_value("bindings", PlayerControls.FIRE, [ControlBindings._to_dict(q)])
	cfg.save(ControlBindings.path)
	ControlBindings.load_saved()
	assert_true(InputMap.event_is_action(q, PlayerControls.FIRE), "the saved layout: Q fires")
	assert_false(InputMap.event_is_action(q, PlayerControls.CYCLE_FRONT, true), "so Q no longer cycles")
	assert_false(ControlBindings.events(PlayerControls.CYCLE_FRONT, ControlBindings.PAD).is_empty(), "the pad default stays")
	var e := InputEventKey.new()
	e.physical_keycode = KEY_E
	assert_true(InputMap.event_is_action(e, PlayerControls.CYCLE_REAR), "an unused default stays")
	ControlBindings.restore_defaults()
	SafeSave.remove(ControlBindings.path)
	ControlBindings.path = saved
