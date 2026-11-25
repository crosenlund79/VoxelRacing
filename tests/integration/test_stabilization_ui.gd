extends GutTest
## Stabilization 2026-11-22, two overlaps: (1) a couch pit-ticket banner shows in
## the offending player's own view only, inside that view and clear of its HUD
## elements and of the other player's view; (2) achievement toasts wait while the
## championship standings are up and are all shown once they close.

const MAIN_SCENE := preload("res://src/main/main.tscn")
const P1 := RaceSession.PLAYER_ID
const P2 := RaceSession.PLAYER_2_ID


func test_couch_pit_ticket_banner_in_the_offenders_view() -> void:
	var m: Node2D = MAIN_SCENE.instantiate()
	m.presentation_enabled = true
	m.human_count = 2
	m.player_devices = [3, 4] as Array[int]
	add_child_autofree(m)
	await wait_physics_frames(2)
	m.start_race()
	await wait_physics_frames(2)
	var h1: Hud = m.player_views.view_for(P1).hud
	var h2: Hud = m.player_views.view_for(P2).hud
	m._ticket_banner(P2, 0)
	await wait_process_frames(2)
	assert_true(h2.banner_showing(), "in player 2's view")
	assert_false(h1.banner_showing(), "not in player 1's view")
	assert_false(m.hud._banner.text.contains("PIT LANE"), "not on the shared screen (race banners such as GO! stay there)")
	assert_string_contains(h2._banner.text, "PIT LANE VIOLATION")
	var width: float = m.player_views.view_for(P2).base_size.x
	var b := Rect2(h2._banner.position, h2._banner.size)
	assert_lte(b.end.x, width + 0.5, "inside the view")
	assert_gte(b.position.x, 0.0)
	assert_lte(h2._banner.get_theme_font_size("font_size") * 2.6, b.size.y + 10.0, "two lines fit")
	for other in [h2._wreck_label, h2._out_label, h2._pit_box]:
		assert_false(b.intersects(Rect2(other.position, Vector2(width, 40))), "clear of %s" % other.name)
	m._ticket_banner(P1, 100)
	await wait_process_frames(2)
	assert_true(h1.banner_showing(), "player 1's own ticket in player 1's view")
	assert_false(m.hud._banner.text.contains("PIT LANE"))


func test_toasts_wait_while_the_standings_are_up() -> void:
	var toast := AchievementToast.new()
	add_child_autofree(toast)
	toast.setup(AssetResolver.new())
	var ids := AchievementCatalog.ids()
	toast.show_unlock(ids[0])
	await wait_process_frames(5)
	assert_true(toast.showing(), "a toast slides in")
	toast.set_held(true)  # the championship standings open
	toast.show_unlock(ids[1])
	await wait_seconds(0.4)
	assert_false(toast.showing(), "it leaves at once and nothing new appears")
	assert_eq(toast.pending(), 2, "both kept for later")
	await wait_seconds(1.0)
	assert_false(toast.showing())
	toast.set_held(false)  # standings closed
	await wait_process_frames(5)
	assert_true(toast.showing(), "the first comes back in full")
	assert_eq(toast._current, ids[0])
	await wait_seconds(AchievementToast.SHOW_TIME + 1.0)
	assert_eq(toast._current, ids[1], "then the second")
