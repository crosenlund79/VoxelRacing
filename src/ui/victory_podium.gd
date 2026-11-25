extends Control
## The victory podium (VictoryScreen): a drawn trophy over three podium steps
## (2nd left, 1st centre, 3rd right) with the cars as they raced standing on
## them and their drivers' names below. Drawn with plain shapes in the game's
## palette (no new artwork needed; replaceable later like any procedural
## visual). Presentation only.

const STEP_W := 180.0
## Step heights for places 1, 2, 3.
const STEP_H: Array[float] = [150.0, 110.0, 80.0]
## Step x positions (left edges) for places 1, 2, 3.
const STEP_X: Array[float] = [220.0, 30.0, 410.0]
const FLOOR_Y := 470.0

var _ids: Array = []


func setup(top3: Array, icons: Dictionary) -> void:
	_ids = top3
	for k in mini(3, top3.size()):
		var id: int = top3[k]
		var car := TextureRect.new()
		car.texture = icons.get(id)
		car.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		car.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		car.custom_minimum_size = Vector2(160, 90)
		car.size = car.custom_minimum_size
		car.position = Vector2(STEP_X[k] + 10.0, FLOOR_Y - STEP_H[k] - 92.0)
		add_child(car)
		var name := HyperTheme.label("YOU" if id == RaceSession.PLAYER_ID else RivalRoster.full_name(id), 17,
			HyperTheme.GOLD if id == RaceSession.PLAYER_ID else HyperTheme.CREAM, 700)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name.size = Vector2(STEP_W, 44)
		name.position = Vector2(STEP_X[k], FLOOR_Y + 6.0)
		add_child(name)
	queue_redraw()


func _draw() -> void:
	# the trophy above the winner's step
	var c := Vector2(STEP_X[0] + STEP_W * 0.5, 70.0)
	var gold := HyperTheme.GOLD
	var dark := gold.darkened(0.35)
	draw_circle(c + Vector2(0, -4), 46.0, Color(gold, 0.18))
	draw_colored_polygon(PackedVector2Array([c + Vector2(-38, -40), c + Vector2(38, -40), c + Vector2(28, 6),
		c + Vector2(10, 22), c + Vector2(-10, 22), c + Vector2(-28, 6)]), gold)
	draw_arc(c + Vector2(-38, -22), 14.0, PI * 0.5, PI * 1.5, 12, dark, 6.0)
	draw_arc(c + Vector2(38, -22), 14.0, -PI * 0.5, PI * 0.5, 12, dark, 6.0)
	draw_rect(Rect2(c + Vector2(-6, 22), Vector2(12, 22)), dark)
	draw_rect(Rect2(c + Vector2(-26, 44), Vector2(52, 12)), gold)
	draw_rect(Rect2(c + Vector2(-32, 56), Vector2(64, 10)), dark)
	draw_line(c + Vector2(-26, -30), c + Vector2(-16, 2), Color(1, 1, 1, 0.45), 4.0)  # a soft highlight
	# the steps
	var colors: Array[Color] = [Color("8a6a3a"), Color("6f6a66"), Color("6a4a32")]
	var font := HyperTheme.font(700)
	for k in 3:
		var r := Rect2(Vector2(STEP_X[k], FLOOR_Y - STEP_H[k]), Vector2(STEP_W, STEP_H[k]))
		draw_rect(r, colors[k])
		draw_rect(Rect2(r.position, Vector2(STEP_W, 8)), colors[k].lightened(0.25))
		draw_rect(r, colors[k].darkened(0.4), false, 3.0)
		var label := str(k + 1)
		var size := 64 if k == 0 else 52
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		draw_string(font, Vector2(r.position.x + (STEP_W - w) * 0.5, r.position.y + 20.0 + size * 0.8), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, HyperTheme.CREAM)
	draw_rect(Rect2(Vector2(0, FLOOR_Y), Vector2(620, 4)), Color(HyperTheme.CREAM, 0.35))
