extends GutTest
## Race variety: each new race scene gets its own AI seed from the session
## seed; a given --seed=N reproduces a whole session; race scenes built
## directly (tests, probes) keep the fixed default seed.

const GAME_SCENE := preload("res://src/main/game.tscn")
const MAIN_SCRIPT := preload("res://src/main/main.gd")


func test_seed_from_arguments() -> void:
	assert_eq(GameSeed.from_args(PackedStringArray(["--seed=42"])), 42)
	assert_eq(GameSeed.from_args(PackedStringArray(["--layout=ravenhook", "--seed=7"])), 7)
	var a := GameSeed.from_args(PackedStringArray())
	var b := GameSeed.from_args(PackedStringArray())
	assert_ne(a, b, "random sessions differ")


func _race_seeds(session: int) -> Array:
	var game := GAME_SCENE.instantiate()
	game.session_seed = session
	add_child_autofree(game)
	await wait_physics_frames(2)
	var seeds := []
	for k in 2:
		game.start_race(0)
		for i in 300:
			if game.race != null and not game._starting:
				break
			await wait_process_frames(1)
		seeds.append(game.race.base_seed)
		game.back_to_title()
		for i in 300:
			if game.race == null and not game._starting:
				break
			await wait_process_frames(1)
	game.title.stop_audio()
	return seeds


func test_new_races_get_new_seeds_and_a_session_seed_reproduces_them() -> void:
	var one: Array = await _race_seeds(1234)
	assert_ne(one[0], one[1], "the next race differs from the last")
	assert_ne(one[0], 1991, "not the fixed default")
	var again: Array = await _race_seeds(1234)
	assert_eq(again, one, "same session seed, same races")
	var other: Array = await _race_seeds(99)
	assert_ne(other, one, "another session, other races")


func test_race_scene_keeps_its_fixed_default() -> void:
	var main: Node2D = load("res://src/main/main.tscn").instantiate()
	assert_eq(main.base_seed, 1991, "tests and probes stay deterministic")
	main.free()


func test_shuffled_rivals_keep_the_humans_and_every_rival() -> void:
	var grid: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0]
	var a := MAIN_SCRIPT.shuffled_rivals(grid, 11)
	assert_eq(a[9], 0, "the player still starts last")
	var sorted := a.duplicate()
	sorted.sort()
	assert_eq(sorted, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9] as Array[int], "every rival once")
	assert_eq(MAIN_SCRIPT.shuffled_rivals(grid, 11), a, "seeded")
	assert_ne(MAIN_SCRIPT.shuffled_rivals(grid, 12), a)
	var two: Array[int] = [1, 2, 10, 3, 0]
	var b := MAIN_SCRIPT.shuffled_rivals(two, 5)
	assert_eq([b[2], b[4]], [10, 0], "both humans keep their slots")


## A new race from the game starts from a shuffled first grid (Rocco is not
## always second behind Victor); championship round 1 too.
func test_game_races_start_from_a_varied_first_grid() -> void:
	var game := GAME_SCENE.instantiate()
	game.session_seed = 5
	add_child_autofree(game)
	await wait_physics_frames(2)
	var grids := {}
	for k in 3:
		game.start_race(0)
		for i in 300:
			if game.race != null and not game._starting:
				break
			await wait_process_frames(1)
		var g: Array[int] = game.race.grid_order
		assert_eq(g[g.size() - 1], RaceSession.PLAYER_ID, "player last")
		grids[str(g)] = true
		game.back_to_title()
		for i in 300:
			if game.race == null and not game._starting:
				break
			await wait_process_frames(1)
	assert_gt(grids.size(), 1, "first grids vary between races")
	assert_false(grids.has(str([1, 2, 3, 4, 5, 6, 7, 8, 9, 0])) and grids.size() == 1)
	game.title.championship_rounds = 3
	game.start_championship(0)
	for i in 300:
		if game.race != null and not game._starting:
			break
		await wait_process_frames(1)
	assert_ne(game.race.grid_order, [1, 2, 3, 4, 5, 6, 7, 8, 9, 0] as Array[int], "championship round 1 varies too")
	assert_eq(game.race.grid_order[9], RaceSession.PLAYER_ID)
	game.title.stop_audio()
