class_name ProvisionalPanel
extends PanelContainer
## While the player watches the rest of a championship round: the
## championship standings as they would be with the race as it stands now -
## points before the round plus the round's points for the current position
## (the schedule's points; a DNF scores nothing). Cars already in are FINAL,
## the others PROVISIONAL (their points can still change). No prediction:
## only the live race order and the existing scoring.

var _rows: VBoxContainer
var _title: Label


func setup(theme: Theme) -> void:
	self.theme = theme
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	self_modulate = Color(1, 1, 1, 0.95)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	add_child(box)
	_title = HyperTheme.label("CHAMPIONSHIP  -  IF IT ENDED NOW", 15, HyperTheme.GOLD, 700)
	box.add_child(_title)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 0)
	box.add_child(_rows)
	visible = false


## points_before: racer id -> championship points before this round;
## scoring: points for 1st, 2nd, ...; standings: the live race order.
## Returns the rows shown as [id, total, race points, final] (tests).
func refresh(points_before: Dictionary, scoring: PackedInt32Array, standings: Array[RacerState],
		names: Dictionary, player_id: int) -> Array:
	var lines: Array = []
	for k in standings.size():
		var r := standings[k]
		var pts := 0 if r.dnf or k >= scoring.size() else scoring[k]
		lines.append([r.id, int(points_before.get(r.id, 0)) + pts, pts, r.is_done()])
	var final := lines.all(func(l: Array) -> bool: return l[3])
	_title.text = "CHAMPIONSHIP  -  AFTER THIS ROUND" if final else "CHAMPIONSHIP  -  IF IT ENDED NOW"
	lines.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1] if a[1] != b[1] else a[0] < b[0])
	for c in _rows.get_children():
		_rows.remove_child(c)  # (now: the panel's size must not count the old rows)
		c.queue_free()
	for k in lines.size():
		var l: Array = lines[k]
		var color := HyperTheme.GOLD if l[0] == player_id else HyperTheme.CREAM
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		for cell in [[str(k + 1), 22], [str(names.get(l[0], "?")), 74], [str(l[1]), 30],
				["+%d %s" % [l[2], "FINAL" if l[3] else "now"], 76]]:
			var lab := HyperTheme.label(cell[0], 15, color if cell[1] != 76 or l[3] else Color("bcd7ff"), 600)
			lab.custom_minimum_size = Vector2(cell[1], 0)
			row.add_child(lab)
		_rows.add_child(row)
	return lines
