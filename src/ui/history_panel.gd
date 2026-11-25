class_name HistoryPanel
extends NinePatchRect
## Spectator race history for the current session: fixed driver rows, one
## column per completed race (stars for 1st-3rd, numbers for 4th-9th), or the
## Position Counts view (finishes in each position). Race columns scroll
## horizontally as races accumulate; rows are striped and the latest race
## column is highlighted.

enum View { HISTORY, COUNTS }

const CELL := Vector2(36, 26)
const NAME_WIDTH := 150.0
const TEXT_COLOR := Color("ead9b8")
const DIM_COLOR := Color("ead9b8", 0.55)
const OUTLINE_COLOR := Color("2a2220")

var view: View = View.HISTORY
var _history: RaceHistory
var _stars: Array[Texture2D] = []
var _title: Label
var _hint: Label
var _scroll: ScrollContainer
var _grid: GridContainer
var _name_rows: Array[Control] = []
var _weapons_name: Label
var _laps_name: Label


## driver_ids in row order; car_textures/names keyed by driver id.
func setup(resolver: AssetResolver, history: RaceHistory, car_textures: Dictionary, names: Dictionary) -> void:
	_history = history
	texture = VrStyle.panel_texture()
	patch_margin_left = 8
	patch_margin_right = 12
	patch_margin_top = 8
	patch_margin_bottom = 20
	_stars = [resolver.get_texture(AssetCatalog.STAR_GOLD), resolver.get_texture(AssetCatalog.STAR_SILVER),
		resolver.get_texture(AssetCatalog.STAR_BRONZE)]

	var box := VBoxContainer.new()
	box.position = Vector2(18, 12)
	box.size = size - Vector2(36, 24)
	add_child(box)
	_title = _label(18, TEXT_COLOR)
	box.add_child(_title)
	_hint = _label(13, DIM_COLOR)
	_hint.text = PlayerControls.fmt("{history_view}: view   {steer_left} / {steer_right}: scroll   {toggle_panel}: hide   {sim_speed}: speed   {back}: menu")
	box.add_child(_hint)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(row)

	var names_col := VBoxContainer.new()
	names_col.custom_minimum_size.x = NAME_WIDTH
	names_col.add_theme_constant_override("separation", 0)
	row.add_child(names_col)
	names_col.add_child(_cell_spacer())
	_weapons_name = _label(14, DIM_COLOR)
	_weapons_name.text = "  weapons"
	_weapons_name.custom_minimum_size = Vector2(NAME_WIDTH, CELL.y)
	names_col.add_child(_weapons_name)
	_laps_name = _label(14, DIM_COLOR)
	_laps_name.text = "  laps"
	_laps_name.custom_minimum_size = Vector2(NAME_WIDTH, CELL.y)
	names_col.add_child(_laps_name)
	for id in history.driver_ids:
		var r := HBoxContainer.new()
		r.custom_minimum_size.y = CELL.y
		var icon := TextureRect.new()
		icon.texture = car_textures[id]
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(34, CELL.y)
		r.add_child(icon)
		var n := _label(16, TEXT_COLOR)
		n.text = names[id]
		r.add_child(n)
		names_col.add_child(r)
		_name_rows.append(r)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 0)
	_grid.add_theme_constant_override("v_separation", 0)
	_scroll.add_child(_grid)
	_scroll.get_h_scroll_bar().value_changed.connect(func(_v: float) -> void: queue_redraw())
	refresh()


func toggle_view() -> void:
	view = View.COUNTS if view == View.HISTORY else View.HISTORY
	refresh()


## Scrolls the race columns by a number of columns (negative = left).
func scroll_columns(columns: int) -> void:
	_scroll.scroll_horizontal += int(columns * CELL.x)


func refresh() -> void:
	for child in _grid.get_children():
		child.free()
	if view == View.HISTORY:
		_title.text = "RACE HISTORY  (%d races, %d with weapons)" % [_history.race_count(), _history.weapon_race_count()]
		_weapons_name.visible = true
		_laps_name.visible = true
		_grid.columns = maxi(1, _history.race_count())
		if _history.race_count() == 0:
			_grid.add_child(_text_cell("-", DIM_COLOR))
			queue_redraw()
			return
		for r in _history.race_count():
			_grid.add_child(_text_cell("R%d" % (r + 1), DIM_COLOR))
		for r in _history.race_count():
			var armed: bool = _history.weapons[r]
			var mark := _text_cell("ON" if armed else "off", HyperTheme.RED if armed else DIM_COLOR)
			mark.tooltip_text = "Weapons ON" if armed else "No Guns"
			_grid.add_child(mark)
		for r in _history.race_count():
			var lap_cell := _text_cell(str(_history.laps[r]), DIM_COLOR)
			lap_cell.tooltip_text = "%d laps" % _history.laps[r]
			_grid.add_child(lap_cell)
		for id in _history.driver_ids:
			for r in _history.race_count():
				_grid.add_child(_position_cell(_history.position_in(r, id)))
		_scroll_to_end.call_deferred()
	else:
		_title.text = "POSITION COUNTS  (%d races, %d with weapons)" % [_history.race_count(), _history.weapon_race_count()]
		_weapons_name.visible = false
		_laps_name.visible = false
		var positions := _history.driver_ids.size()
		_grid.columns = positions
		for p in positions:
			_grid.add_child(_text_cell(_ordinal(p + 1), DIM_COLOR))
		for id in _history.driver_ids:
			var counts := _history.position_counts(id)
			for p in positions:
				_grid.add_child(_text_cell(str(counts[p]) if counts[p] > 0 else "-", TEXT_COLOR if counts[p] > 0 else DIM_COLOR))
		queue_redraw.call_deferred()


func _scroll_to_end() -> void:
	_scroll.scroll_horizontal = int(_grid.size.x)
	queue_redraw()


## Row stripes and the latest-race highlight, drawn under the cells.
func _draw() -> void:
	var right := size.x - 16.0
	for i in _name_rows.size():
		var r := _name_rows[i].get_global_rect()
		var top := r.position.y - global_position.y
		if i % 2 == 0:
			draw_rect(Rect2(16.0, top, right - 16.0, r.size.y), Color(1, 1, 1, 0.05))
	if view == View.HISTORY and _history != null and _history.race_count() > 0 and _grid.get_child_count() > 0:
		var header := _grid.get_child(_history.race_count() - 1) as Control
		var col := header.get_global_rect()
		var area := _scroll.get_global_rect()
		var x0 := maxf(col.position.x, area.position.x) - global_position.x
		var x1 := minf(col.end.x, area.end.x) - global_position.x
		if x1 > x0:
			draw_rect(Rect2(x0, area.position.y - global_position.y, x1 - x0, area.size.y), Color(0.89, 0.7, 0.24, 0.16))


func _position_cell(position: int) -> Control:
	if position >= 1 and position <= 3:
		var star := TextureRect.new()
		star.texture = _stars[position - 1]
		star.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		star.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		star.custom_minimum_size = CELL
		star.tooltip_text = _ordinal(position)
		return star
	return _text_cell(str(position) if position > 0 else "-", TEXT_COLOR)


func _text_cell(text: String, color: Color) -> Label:
	var l := _label(15, color)
	l.text = text
	l.custom_minimum_size = CELL
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _cell_spacer() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(NAME_WIDTH, CELL.y)
	return c


func _label(font_size: int, color: Color) -> Label:
	return HyperTheme.label("", font_size, color, 600 if font_size >= 16 else 500)


static func _ordinal(n: int) -> String:
	match n:
		1: return "1st"
		2: return "2nd"
		3: return "3rd"
	return "%dth" % n
