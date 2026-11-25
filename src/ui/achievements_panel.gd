class_name AchievementsPanel
extends PanelContainer
## Title-screen catalogue: every achievement (hidden ones as "???" until
## unlocked), the rivals' career statistics ("Living Legends"), and a reset
## that must be confirmed. Reads the AchievementStore; only reset writes it.

signal closed

var store: AchievementStore
var _resolver: AssetResolver
var _count: Label
var _list: VBoxContainer
var _rivals: GridContainer
var _scroll: ScrollContainer
var _back: Button
var _reset: Button
var _confirm_row: HBoxContainer
var _confirm_yes: Button


func setup(p_store: AchievementStore, resolver: AssetResolver) -> void:
	store = p_store
	_resolver = resolver
	custom_minimum_size = Vector2(1180, 640)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := HyperTheme.label("ACHIEVEMENTS", 32, HyperTheme.GOLD, 700)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_count = HyperTheme.label("", 22, HyperTheme.CREAM, 600)
	head.add_child(_count)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 20)
	box.add_child(cols)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(690, 470)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	cols.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 4)
	cols.add_child(right)
	right.add_child(HyperTheme.label("LIVING LEGENDS - rival careers", 20, HyperTheme.GOLD, 700))
	right.add_child(HyperTheme.label("Completed races you raced or watched", 14, HyperTheme.CREAM_DIM, 500))
	_rivals = GridContainer.new()
	_rivals.columns = 5
	_rivals.add_theme_constant_override("h_separation", 14)
	_rivals.add_theme_constant_override("v_separation", 0)
	right.add_child(_rivals)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	box.add_child(buttons)
	_back = Button.new()
	_back.text = "BACK"
	_back.pressed.connect(func() -> void: closed.emit())
	buttons.add_child(_back)
	_reset = Button.new()
	_reset.text = "RESET ACHIEVEMENTS"
	_reset.pressed.connect(_ask_reset)
	buttons.add_child(_reset)
	_confirm_row = HBoxContainer.new()
	_confirm_row.add_theme_constant_override("separation", 12)
	_confirm_row.visible = false
	buttons.add_child(_confirm_row)
	_confirm_row.add_child(HyperTheme.label("Erase all achievements and rival careers?", 18, HyperTheme.RED, 700))
	_confirm_yes = Button.new()
	_confirm_yes.text = "YES, ERASE"
	_confirm_yes.pressed.connect(_do_reset)
	_confirm_row.add_child(_confirm_yes)
	var no := Button.new()
	no.text = "CANCEL"
	no.pressed.connect(func() -> void:
		_cancel_reset()
		_reset.grab_focus())
	_confirm_row.add_child(no)


func refresh() -> void:
	_cancel_reset()
	_count.text = "%d / %d unlocked" % [store.unlocked_count(), AchievementCatalog.ENTRIES.size()]
	for c in _list.get_children():
		c.free()
	var badge := _resolver.get_texture(AssetCatalog.ACHIEVEMENT_BADGE)
	var locked_tex := _resolver.get_texture(AssetCatalog.ACHIEVEMENT_LOCKED)
	for e in AchievementCatalog.ENTRIES:
		var got := store.is_unlocked(e.id)
		var secret: bool = e.hidden and not got
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.focus_mode = Control.FOCUS_ALL
		var icon := TextureRect.new()
		icon.texture = badge if got else locked_tex
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(40, 40)
		row.add_child(icon)
		var text := VBoxContainer.new()
		text.add_theme_constant_override("separation", -6)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		text.add_child(HyperTheme.label("???" if secret else e.name, 19, HyperTheme.GOLD if got else HyperTheme.CREAM, 700))
		var desc := HyperTheme.label("Hidden until unlocked." if secret else e.desc, 15, HyperTheme.CREAM if got else HyperTheme.CREAM_DIM, 500)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(560, 0)
		text.add_child(desc)
		if got:
			var date := Time.get_date_string_from_unix_time(store.unlocked_at[e.id])
			row.add_child(HyperTheme.label(date, 14, HyperTheme.CREAM_DIM, 500))
		_list.add_child(row)
	for c in _rivals.get_children():
		c.free()
	for h in ["RIVAL", "RACES", "WINS", "PODIUMS", "WINLESS"]:
		_rivals.add_child(HyperTheme.label(h, 14, HyperTheme.CREAM_DIM, 700))
	for rid in AchievementStore.RIVAL_IDS:
		var r: Dictionary = store.rivals[rid]
		_rivals.add_child(HyperTheme.label(RivalRoster.short_name(rid), 17, HyperTheme.CREAM, 600))
		for v in [r.races, r.wins, r.podiums, r.winless_streak]:
			var l := HyperTheme.label(str(v), 17, HyperTheme.CREAM, 500)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			_rivals.add_child(l)


func focus_first() -> void:
	_back.grab_focus()


func _ask_reset() -> void:
	_reset.visible = false
	_confirm_row.visible = true
	_confirm_yes.grab_focus()


func _cancel_reset() -> void:
	_confirm_row.visible = false
	_reset.visible = true


func _do_reset() -> void:
	store.reset()
	refresh()
	_reset.grab_focus()
