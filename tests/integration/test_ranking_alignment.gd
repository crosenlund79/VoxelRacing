extends GutTest
## TOMBSTONE | K | D: every column head sits centred over its numbers, in the
## standings tower and on the results board, with room for double digits.

const MAIN_SCENE := preload("res://src/main/main.tscn")


func _race() -> Node2D:
	var main: Node2D = MAIN_SCENE.instantiate()
	main.use_command_line_layout = false
	main.layout_override = load(DevLayouts.LAYOUTS["kestrel_ridge"])
	add_child_autofree(main)
	await wait_physics_frames(2)
	main.set_weapons_enabled(true)
	main.set_menu_choice(2)  # spectate: the tower with statistics
	main.start_race()
	await wait_physics_frames(20)
	return main


func _centre_x(c: Control) -> float:
	return c.get_global_rect().get_center().x


func _assert_columns(heads: Array, cells: Array, what: String) -> void:
	assert_eq(heads.size(), 3, what)
	assert_eq(cells.size(), 3, what)
	for k in 3:
		assert_almost_eq(_centre_x(cells[k]), _centre_x(heads[k]), 1.5, "%s column %d" % [what, k])


func test_tower_heads_line_up_with_double_digit_numbers() -> void:
	var main: Node2D = await _race()
	var hud: Hud = main.hud
	main.stats.kills[1] = 12
	main.stats.deaths[1] = 10
	main.stats.tombstones[1] = 11
	hud.update_tower(main.session.standings())
	await wait_process_frames(3)
	assert_not_null(hud._tower_header, "column heads above the rows")
	var heads: Array = hud._tower_header.get_child(0).get_children()
	for parts in hud._tower_rows:
		if not parts[0].visible:
			continue
		var cells: Array = parts[4]
		_assert_columns(heads, cells, "tower")
		for c in cells:
			var l := c as Label
			assert_lte(l.get_theme_font("font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x, l.size.x, "room for '%s'" % l.text)


func test_results_heads_line_up() -> void:
	var main: Node2D = await _race()
	var hud: Hud = main.hud
	main.stats.kills[2] = 15
	hud.show_results(main.session.standings())
	await wait_process_frames(3)
	var header: HBoxContainer = null
	var rows: VBoxContainer = null
	for c in hud._message_box.get_children():
		if c is PanelContainer and header == null and c.get_child(0) is HBoxContainer:
			header = c.get_child(0)
		if c is VBoxContainer and rows == null:
			rows = c
	assert_not_null(header)
	assert_not_null(rows)
	var heads: Array = header.get_children().slice(0, 3)
	for panel in rows.get_children():
		var grid: HBoxContainer = panel.get_child(0)
		var n := grid.get_child_count()
		_assert_columns(heads, grid.get_children().slice(n - 3, n), "results")


## The achievement toast slides in below the kill feed's tallest stack.
func test_toast_clears_the_kill_feed() -> void:
	var main: Node2D = await _race()
	for k in KillFeed.MAX_ROWS + 2:
		main.stats.feed.append({"attacker": 1 + k % 8, "victim": 2 + k % 7, "weapon": 0, "tombstone": k % 2 == 0, "time": 1.0})
	await wait_process_frames(5)
	var feed: KillFeed = main.kill_feed
	var bottom: float = feed._box.get_global_rect().end.y
	assert_gt(bottom, 60.0, "the feed is showing")
	assert_lt(bottom, AchievementToast.TOP, "the toast starts below the feed")
	assert_lt(AchievementToast.TOP + 80.0, 720.0, "and stays on screen")
