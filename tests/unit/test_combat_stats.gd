extends GutTest
## Kills, deaths, tombstones and the kill feed's attribution (CombatStats).

const MISSILE := WeaponRules.Weapon.FRONT_MISSILE
const MINE := WeaponRules.Weapon.MINE


func test_a_destruction_is_a_kill_and_a_death() -> void:
	var s := CombatStats.new(10)
	s.on_destroyed(4, 2, MISSILE, 10.0)  # Rocco's missile destroys Hank (he respawns)
	assert_eq(s.line(2), [0, 1, 0], "Rocco: one kill")
	assert_eq(s.line(4), [0, 0, 1], "Hank: one death")
	assert_eq(s.feed.size(), 1)
	assert_eq(s.feed[0].attacker, 2)
	assert_eq(s.feed[0].victim, 4)
	assert_eq(s.feed[0].weapon, MISSILE)
	assert_false(s.feed[0].tombstone)


func test_a_final_destruction_adds_a_tombstone_without_a_second_kill() -> void:
	var s := CombatStats.new(10)
	s.on_destroyed(1, 9, MINE, 20.0)
	s.on_retired(1, 20.0, true)  # that destruction retired Victor
	assert_eq(s.line(9), [1, 1, 0], "Nina: kill + tombstone, not two kills")
	assert_eq(s.line(1), [0, 0, 1], "Victor: one death")
	assert_true(s.feed[0].tombstone, "the feed entry carries the tombstone")
	assert_eq(s.feed.size(), 1, "one feed entry")


func test_own_weapon_is_a_death_without_a_kill() -> void:
	var s := CombatStats.new(10)
	s.on_destroyed(3, 3, MINE, 5.0)
	s.on_retired(3, 5.0, true)
	assert_eq(s.line(3), [0, 0, 1])
	assert_eq(s.feed[0].attacker, -1, "nobody credited")
	assert_false(s.feed[0].tombstone, "no tombstone for anyone")


func test_collision_retirement_is_credited_only_within_the_window() -> void:
	var s := CombatStats.new(10)
	s.on_contact(5, 2, 30.0)  # Rocco rams Maya
	s.on_retired(5, 31.5, false)
	assert_eq(s.line(2), [1, 1, 0], "Rocco: kill and tombstone by collision")
	assert_eq(s.line(5), [0, 0, 1])
	assert_eq(s.feed[-1].weapon, CombatStats.COLLISION)
	var t := CombatStats.new(10)
	t.on_contact(5, 2, 30.0)
	t.on_retired(5, 30.0 + CombatStats.ATTRIBUTION_TIME + 0.5, false)  # wore out much later (wall)
	assert_eq(t.line(2), [0, 0, 0], "an uninvolved driver is never credited")
	assert_eq(t.line(5), [0, 0, 1])
	assert_eq(t.feed[-1].attacker, -1)
	assert_true(t.feed[-1].tombstone, "still shown as out for good")


func test_knockout_eliminations_give_no_statistics() -> void:
	var s := CombatStats.new(10)
	s.on_contact(7, 1, 3.0)
	s.on_eliminated(7, 4.0)
	for id in 10:
		assert_eq(s.line(id), [0, 0, 0])
	assert_eq(s.feed[-1].weapon, CombatStats.ELIMINATED)


func test_ai_against_ai_and_reset() -> void:
	var s := CombatStats.new(10)
	s.on_destroyed(6, 8, MISSILE, 1.0)
	s.on_destroyed(8, 6, MISSILE, 2.0)
	assert_eq(s.line(6), [0, 1, 1])
	assert_eq(s.line(8), [0, 1, 1])
	s.reset()
	assert_eq(s.line(6), [0, 0, 0])
	assert_true(s.feed.is_empty())
