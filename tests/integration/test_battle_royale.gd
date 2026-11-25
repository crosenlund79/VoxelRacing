extends GutTest
## Battle Royale: the arena, cooldown-only weapons (unlimited, no homing or
## super missiles), permanent eliminations credited in the kill feed and
## K / D / tombstones, the closing zone, personality-driven arena AI, and AI
## matches that end naturally with varied winners.

const W := WeaponRules.Weapon

var _b: BattleRoyale


func after_each() -> void:
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0
	Engine.max_physics_steps_per_frame = 8


func _make(seed_value := 1, player_ai := true) -> void:
	_b = BattleRoyale.new()
	_b.presentation_enabled = false
	_b.player_ai = player_ai
	_b.base_seed = seed_value
	add_child_autofree(_b)
	await wait_physics_frames(2)


func test_arena_weapons_are_unlimited_cooldown_weapons_only() -> void:
	await _make(1, false)
	for i in 10:
		assert_eq(_b.combat.weapon_of(i, CombatWorld.FRONT), W.FRONT_MISSILE)
		assert_eq(_b.combat.weapon_of(i, CombatWorld.REAR), W.MINE)
		for slot in 2:
			assert_false([W.HOMING_MISSILE, W.SUPER_MISSILE].has(_b.combat.weapon_of(i, slot)), "no homing / super missiles")
	await wait_until(func() -> bool: return not _b.combat.locked, 10.0)
	var states := _b._states()
	assert_true(_b.combat.request(0, CombatWorld.FRONT, states))
	assert_eq(_b.combat.ammo[0][CombatWorld.FRONT], 999, "rounds never run out")
	assert_false(_b.combat.request(0, CombatWorld.FRONT, states), "but the front slot cools down")
	assert_true(_b.combat.request(0, CombatWorld.REAR, _b._states()) or _b.combat.cooldown[0] > 0.0, "own cooldown per slot")
	await wait_physics_frames(int(_b.WEAPON_RULES.tactical_front_cooldown * 60.0) + 2)
	assert_true(_b.combat.request(0, CombatWorld.FRONT, _b._states()), "ready again after its cooldown")
	assert_eq(_b.combat.ammo[0][CombatWorld.FRONT], 999)


func test_normal_races_keep_their_ammunition_rules() -> void:
	var rules: WeaponRules = load("res://src/combat/default_weapon_rules.tres")
	var w := CombatWorld.new(rules, 2)
	w.enabled = true
	var before: int = w.ammo[0][0]
	w.request(0, CombatWorld.FRONT, [{"position": Vector2.ZERO, "heading": 0.0, "present": true},
		{"position": Vector2(900, 900), "heading": 0.0, "present": true}])
	assert_eq(w.ammo[0][0], before - 1, "a race still uses up rounds")


func test_ai_match_ends_with_one_winner_and_consistent_statistics() -> void:
	await _make(3)
	await wait_until(func() -> bool: return _b.winner >= 0, 600.0)
	assert_gte(_b.winner, 0, "the match ends")
	assert_eq(_b.alive().size(), 0, "everyone else is out (the winner has finished)")
	assert_eq(_b.session.standings()[0].id, _b.winner)
	var deaths := 0
	var kills := 0
	var tombs := 0
	for i in 10:
		deaths += _b.stats.deaths[i]
		kills += _b.stats.kills[i]
		tombs += _b.stats.tombstones[i]
		if i != _b.winner:
			assert_true(_b.session.racers[i].dnf, "eliminated for good")
			assert_false(_b.cars[i].active, "no respawn")
			assert_eq(_b.cars[i].collision_layer, 0, "an eliminated car no longer blocks anyone")
	assert_eq(deaths, 9, "nine cars destroyed")
	assert_eq(kills, tombs, "every arena kill is permanent: kill = tombstone")
	assert_lte(kills, 9)
	assert_eq(_b.stats.feed.size(), 9, "one kill feed line per elimination")
	assert_lt(_b.session.elapsed, BattleRoyale.ZONE_START + BattleRoyale.ZONE_CLOSE_TIME + 60.0, "no endless stand-off")


func test_ai_matches_vary() -> void:
	var winners := {}
	for seed_value in [11, 12, 13]:
		await _make(seed_value)
		await wait_until(func() -> bool: return _b.winner >= 0, 600.0)
		winners[_b.winner] = true
		var shots := 0
		for a in _b.ais:
			if a != null:
				shots += a.shots
		assert_gt(shots, 10, "rivals engage each other")
		_b.queue_free()
		await wait_physics_frames(2)
	assert_gt(winners.size(), 1, "different winners in different matches")


func test_zone_wears_down_cars_outside() -> void:
	await _make(1, false)
	_b.session.elapsed = BattleRoyale.ZONE_START + BattleRoyale.ZONE_CLOSE_TIME  # fully closed
	var c: Car = _b.cars[4]
	c.global_position = Vector2(900, 0) if not _b.arena.layout.blocked(Vector2(900, 0)) else Vector2(1000, 200)
	var before: float = _b.damage.condition[4]
	_b._zone_step(1.0)
	assert_lt(_b.damage.condition[4], before, "outside the closed zone: damage")
	var inside: float = _b.damage.condition[0]
	_b.cars[0].global_position = Vector2(0, -230) if not _b.arena.layout.blocked(Vector2(0, -230)) else Vector2(0, 200)
	_b._zone_step(1.0)
	assert_eq(_b.damage.condition[0], inside, "inside: none")


func test_personalities_shape_the_arena_ai() -> void:
	var rocco := ArenaAi.new(load(RivalRoster.params_path(2)), 1)
	var victor := ArenaAi.new(load(RivalRoster.params_path(1)), 1)
	var nina := ArenaAi.new(load(RivalRoster.params_path(9)), 1)
	var finn := ArenaAi.new(load(RivalRoster.params_path(8)), 1)
	assert_gt(rocco.aggression, victor.aggression, "Rocco reckless, Victor controlled")
	assert_gt(rocco.aggression, nina.aggression)
	assert_gt(victor.standoff, rocco.standoff, "Victor keeps his distance, Rocco rams")
	assert_lt(victor.aim_tolerance, rocco.aim_tolerance, "Victor waits for cleaner shots")
	assert_gt(finn.wander, victor.wander, "Finn unpredictable")


func test_arena_ai_steers_away_from_a_wall_ahead() -> void:
	var ai := ArenaAi.new(load(RivalRoster.params_path(1)), 2)
	var layout := ArenaLayout.new()
	var me := {"id": 1, "position": Vector2(1150, 0), "heading": 0.0, "velocity": Vector2(300, 0)}  # nose into the east wall
	var other := {"id": 2, "position": Vector2(1150, 0) + Vector2(0, 600), "heading": 0.0, "velocity": Vector2.ZERO, "condition": 1.0}
	var cmd := ai.decide(me, [other], layout, 1.0 / 60.0, false, false)
	assert_ne(cmd.steer, 0.0, "turns away from the wall")


func test_layout_spawns_are_clear_and_inside() -> void:
	var layout := ArenaLayout.new()
	assert_eq(layout.spawns.size(), 10)
	for t in layout.spawns:
		assert_false(layout.blocked(t.origin, 40.0), "spawn %s clear of walls and obstacles" % t.origin)
	assert_true(layout.blocked(Vector2(0, 0)), "the scrap pile is solid")
	assert_false(layout.clear_line(Vector2(-400, 0), Vector2(400, 0)), "no shooting through the pile")
	assert_true(layout.clear_line(Vector2(-400, -700), Vector2(400, -700)))


## A hit only wears a car down in the arena: the rival defeat popup appears
## only for the hit that eliminates the player.
func test_defeat_popup_only_for_the_eliminating_hit() -> void:
	_b = BattleRoyale.new()
	_b.player_ai = false
	_b.base_seed = 2
	add_child_autofree(_b)
	await wait_physics_frames(2)
	assert_not_null(_b.defeat_popup)
	_hit(0, 3)
	await wait_physics_frames(6)
	assert_false(_b.session.racers[0].is_done(), "a hit, not an elimination")
	assert_false(_b.defeat_popup._panel.visible, "no defeat popup for a hit")
	_b.damage.condition[0] = 1.0
	_hit(0, 3)
	await wait_physics_frames(6)
	assert_true(_b.session.racers[0].is_done(), "eliminated")
	assert_true(_b.defeat_popup._panel.visible, "the eliminating rival is shown")


## What the arena does with a missile hit (as in _combat_step), plus its event.
func _hit(car: int, by: int) -> void:
	_b.combat.events.append({"kind": "destroyed", "type": W.FRONT_MISSILE, "pos": _b.cars[car].position, "car": car, "owner": by})
	if _b.damage.damage(car, 20.0):
		_b._eliminate(car, true, by, W.FRONT_MISSILE)
