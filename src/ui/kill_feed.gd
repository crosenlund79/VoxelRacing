class_name KillFeed
extends CanvasLayer
## CS-style kill feed in the top-right corner: "ROCCO [missile] VICTOR",
## "NINA [missile] [tombstone] ELLIE", "[crash] [tombstone] FINN". Reads
## CombatStats.feed (the race scene's statistics), so it shows exactly the
## attribution the K / D / tombstone columns use: AI against AI as well as the
## humans, never a bystander. Recent entries stay for a few seconds, then fade.

const MAX_ROWS := 5
const SHOW_TIME := 6.0
const FADE_TIME := 0.8
const ICON := Vector2(30, 18)

var stats: CombatStats
var _names := {}
var _colors := {}
var _icons := {}
var _tomb: Texture2D
var _crash: Texture2D
var _ticket: Texture2D
var _box: VBoxContainer
var _index := 0
## Shown rows: [HBoxContainer, seconds shown].
var _rows: Array = []
var _theme: Theme


## names: racer id -> short name ("YOU" for the local player); colors: racer
## id -> name colour (humans gold / blue).
func setup(p_stats: CombatStats, resolver: AssetResolver, names: Dictionary, colors: Dictionary) -> void:
	stats = p_stats
	_names = names
	_colors = colors
	_icons = Hud.weapon_icons(resolver)
	_tomb = resolver.get_texture(AssetCatalog.TOMBSTONE)
	_crash = resolver.get_texture(AssetCatalog.CRASH)
	_ticket = resolver.get_texture(AssetCatalog.TICKET)
	layer = 11
	_theme = HyperTheme.build(resolver)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 3)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)


func _process(delta: float) -> void:
	if stats == null:
		return
	if stats.feed.size() < _index:  # a new race: start over
		_index = 0
		for r in _rows:
			r[0].queue_free()
		_rows.clear()
	for k in range(_index, stats.feed.size()):
		_add(stats.feed[k])
	_index = stats.feed.size()
	for r in _rows:
		r[1] += delta
		var left: float = SHOW_TIME - r[1]
		r[0].modulate.a = clampf(left / FADE_TIME, 0.0, 1.0)
	while not _rows.is_empty() and _rows[0][1] >= SHOW_TIME:
		_rows.pop_front()[0].queue_free()
	_box.reset_size()
	_box.position = Vector2(1280.0 - _box.get_combined_minimum_size().x - 14.0, 12.0)


## Rows currently on screen (oldest first), as plain text (tests, logs).
func lines() -> Array[String]:
	var out: Array[String] = []
	for r in _rows:
		out.append(r[0].get_meta("text"))
	return out


func _add(e: Dictionary) -> void:
	var panel := PanelContainer.new()
	panel.theme = _theme
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.09, 0.08, 0.62)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	panel.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_END
	panel.add_child(row)
	var text := PackedStringArray()
	if e.attacker >= 0:
		row.add_child(_name(e.attacker))
		text.append(str(_names.get(e.attacker, "?")))
	var weapon: int = e.weapon
	var icon: Texture2D = _crash if weapon == CombatStats.COLLISION else _icons.get(weapon)
	if weapon == CombatStats.TICKET:  # a pit collision ticket: the offender only, no victim
		row.add_child(_icon(_ticket))
		row.add_child(HyperTheme.label("PIT COLLISION", 16, HyperTheme.GOLD, 700))
		panel.set_meta("text", " ".join(text + PackedStringArray(["[ticket]", "PIT COLLISION"])))
		_box.add_child(panel)
		_rows.append([panel, 0.0])
		while _rows.size() > MAX_ROWS:
			_rows.pop_front()[0].queue_free()
		return
	if weapon == CombatStats.ELIMINATED:
		var out := HyperTheme.label("OUT", 16, HyperTheme.RED, 700)
		row.add_child(out)
		text.append("[OUT]")
	elif icon != null:
		row.add_child(_icon(icon))
		text.append("[%s]" % ("crash" if weapon == CombatStats.COLLISION else WeaponRules.weapon_name(weapon).to_lower()))
	if e.tombstone:
		row.add_child(_icon(_tomb, Vector2(18, 18)))
		text.append("[tombstone]")
	row.add_child(_name(e.victim))
	text.append(str(_names.get(e.victim, "?")))
	panel.set_meta("text", " ".join(text))
	_box.add_child(panel)
	_rows.append([panel, 0.0])
	while _rows.size() > MAX_ROWS:
		_rows.pop_front()[0].queue_free()


func _name(id: int) -> Label:
	var l := HyperTheme.label(str(_names.get(id, "?")).to_upper(), 16, _colors.get(id, HyperTheme.CREAM), 700)
	return l


func _icon(tex: Texture2D, size: Vector2 = ICON) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = size
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t
