extends GutTest
## J4: elevation-aware combat on the experimental figure-eight. A missile, mine,
## super missile or homing missile never touches a car on the other road level
## at the crossing; on the same level everything works as before; near a bridge
## end (transition band) both levels meet; a missile leaving the bridge comes
## down with the road. Flat circuits never use these rules (layout = null).

const FIGURE8 := "res://src/track/layouts/exp_figure8_01.tres"
const DT := 1.0 / 60.0
const W := WeaponRules.Weapon

var _layout: TrackLayout
var _path: ClosedPath
var _x: Dictionary
var _rules: WeaponRules


func before_each() -> void:
	_layout = load(FIGURE8)
	_path = ClosedPath.new(_layout.sample_centerline())
	_x = TrackLayout.find_crossings(_path.points)[0]  # s_a on the bridge, s_b underneath
	_rules = WeaponRules.new()


func _world(count: int) -> CombatWorld:
	var w := CombatWorld.new(_rules, count, _path, _layout.road_width * 0.5)
	w.enabled = true
	w.layout = _layout
	return w


## A car state at arc distance s on its own branch, facing along the road.
func _car(s: float, offset := 0.0) -> Dictionary:
	var tan := _path.tangent_at(s)
	return {"position": _path.point_at(s) + tan * offset, "heading": tan.angle(), "present": true,
		"level": _layout.level_at(s, _path.length), "band": _layout.in_transition(s, _path.length),
		"index": _path.index_at(s)}


func _run(w: CombatWorld, cars: Array, seconds: float) -> Array[int]:
	var out: Array[int] = []
	for i in int(round(seconds / DT)):
		out.append_array(w.step(DT, cars).destroyed)
	return out


func test_level_rule() -> void:
	assert_true(CombatWorld.levels_meet(0, false, 0, false))
	assert_true(CombatWorld.levels_meet(1, false, 1, false))
	assert_false(CombatWorld.levels_meet(1, false, 0, false), "bridge and road underneath")
	assert_true(CombatWorld.levels_meet(1, true, 0, false), "a bridge end belongs to both")
	assert_true(CombatWorld.levels_meet(0, false, 1, true))


func test_missile_from_the_bridge_flies_over_the_car_below() -> void:
	var w := _world(2)
	var cars := [_car(_x.s_a - 160.0), _car(_x.s_b)]  # shooter on the bridge, target below at the crossing
	assert_eq(cars[0].level, 1)
	assert_eq(cars[1].level, 0)
	assert_true(w.request(0, CombatWorld.FRONT, cars))
	assert_eq(_run(w, cars, 1.2).size(), 0, "passes over the car underneath")


func test_missile_from_below_passes_under_the_bridge_car() -> void:
	var w := _world(2)
	var cars := [_car(_x.s_b - 160.0), _car(_x.s_a)]
	assert_true(w.request(0, CombatWorld.FRONT, cars))
	assert_eq(_run(w, cars, 1.2).size(), 0)


func test_same_level_still_hits_on_the_bridge_and_below() -> void:
	for s in [_x.s_a, _x.s_b]:
		var w := _world(2)
		var cars := [_car(s - 160.0), _car(s)]
		assert_true(w.request(0, CombatWorld.FRONT, cars))
		assert_eq(_run(w, cars, 1.2), [1] as Array[int], "hit on level %d" % cars[1].level)


func test_mines_stay_on_their_level() -> void:
	# a mine dropped on the bridge right over the crossing, a car below, a car on the bridge
	var w := _world(3)
	var cars := [_car(_x.s_a + 34.0), _car(_x.s_b), _car(_x.s_a - 20.0)]
	cars[2].position = cars[0].position - Vector2.from_angle(cars[0].heading) * 34.0 + Vector2(0, 8)
	assert_true(w.request(0, CombatWorld.REAR, cars))
	cars[0].position += Vector2(5000, 0)  # the dropper drives away
	var destroyed := _run(w, cars, _rules.mine_fuse + 0.2)
	assert_false(destroyed.has(1), "the car underneath survives the bridge mine")
	assert_true(destroyed.has(2), "the car on the bridge does not")
	# and a mine dropped below never touches the bridge car above it
	var w2 := _world(2)
	var cars2 := [_car(_x.s_b + 34.0), _car(_x.s_a)]
	cars2[1].position = cars2[0].position - Vector2.from_angle(cars2[0].heading) * 34.0
	assert_true(w2.request(0, CombatWorld.REAR, cars2))
	cars2[0].position += Vector2(5000, 0)
	assert_eq(_run(w2, cars2, _rules.mine_fuse + 0.2).size(), 0, "the bridge car survives a mine below")


func test_super_missile_orbits_its_own_level() -> void:
	var w := _world(3)
	var cars := [_car(_x.s_a), _car(_x.s_b), _car(_x.s_a + 30.0)]
	_rules.super_duration = 1.2
	w.set_loadout(0, W.SUPER_MISSILE, 1, W.MINE, 0)
	cars[1].position = cars[0].position + Vector2(0, _rules.super_orbit_radius)  # below, in the orbit
	cars[2].position = cars[0].position + Vector2(_rules.super_orbit_radius, 0)  # on the bridge, in the orbit
	assert_true(w.request(0, CombatWorld.FRONT, cars))
	var destroyed := _run(w, cars, 1.3)
	assert_false(destroyed.has(1), "orbit passes over the car below")
	assert_true(destroyed.has(2), "and destroys the one beside it on the bridge")


func test_homing_never_locks_onto_the_other_level() -> void:
	var w := _world(3)
	var cars := [_car(_x.s_a - 60.0), _car(_x.s_b), _car(_x.s_a + 260.0)]  # car 1 below is nearer
	assert_lt(cars[0].position.distance_to(cars[1].position), cars[0].position.distance_to(cars[2].position))
	assert_eq(w.nearest_car(0, cars), 2, "nearest car on its own level")
	var below := [_car(_x.s_a - 60.0), _car(_x.s_b)]
	assert_eq(_world(2).nearest_car(0, below), -1, "nothing to lock onto when only the car below is near")


func test_missile_leaving_the_bridge_comes_down_with_the_road() -> void:
	var zone: Vector2 = _layout.elevation_zones[0]
	var w := _world(2)
	var cars := [_car(zone.y - 150.0), _car(zone.y + 150.0)]  # shooter on the bridge, target on the road beyond
	assert_eq(cars[0].level, 1)
	assert_eq(cars[1].level, 0)
	assert_true(w.request(0, CombatWorld.FRONT, cars))
	assert_eq(w.projectiles[0].level, 1, "fired on the bridge")
	assert_eq(_run(w, cars, 1.2), [1] as Array[int], "hits the car past the bridge end")


func test_bridge_ends_belong_to_both_levels() -> void:
	var zone: Vector2 = _layout.elevation_zones[0]
	var w := _world(2)
	var cars := [_car(zone.x - 200.0), _car(zone.x + 20.0)]  # target just onto the bridge: in the band
	assert_true(cars[1].band)
	assert_true(w.request(0, CombatWorld.FRONT, cars))
	assert_eq(_run(w, cars, 1.2), [1] as Array[int])


func test_flat_circuits_never_use_levels() -> void:
	var w := CombatWorld.new(_rules, 2)
	w.enabled = true
	assert_null(w.layout)
	var cars := [{"position": Vector2.ZERO, "heading": 0.0, "present": true, "level": 1},
		{"position": Vector2(200, 0), "heading": 0.0, "present": true, "level": 0}]
	assert_true(w.request(0, CombatWorld.FRONT, cars))
	assert_eq(_run(w, cars, 1.0), [1] as Array[int], "levels ignored without elevation")
	assert_false(w.projectiles.size() > 0 and w.projectiles[0].has("level"))
