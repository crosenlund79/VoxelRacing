class_name DefeatPopup
extends CanvasLayer
## Rival taunt (presentation only, read-only on the race): when a rival's
## weapon destroys a human's car on this computer, a short card shows the
## rival's car, name and a line in their personality (RivalTaunts). Credits
## the actual attacker (the combat event's owner). Silent: the Voice Director
## stays the only voice, so popup and commentary never compete for audio. No
## duplicates (one card per destruction, a minimum gap between cards, each
## rival's lines in turn); nothing when spectating or when your own weapon or
## another human destroyed you.

## Seconds a card stays up, and the minimum gap between two cards.
const SHOW_TIME := 3.2
const MIN_GAP := 6.0

signal shown(rival: int, text: String)

var race: Node
var icons := {}
var time := 0.0
var _event_index := 0
var _race_number := -1
var _last_shown := -INF
var _next_line := {}
var _panel: PanelContainer
var _icon: TextureRect
var _name: Label
var _text: Label
var _tween: Tween
## The current card: rival id (0 = none) and text (tests read these).
var current_rival := 0
var current_text := ""


func setup(p_race: Node, resolver: AssetResolver, car_icons: Dictionary) -> void:
	race = p_race
	icons = car_icons
	layer = 12
	var root := Control.new()
	root.theme = HyperTheme.build(resolver)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_panel)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	_panel.add_child(h)
	_icon = TextureRect.new()
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.custom_minimum_size = Vector2(96, 54)
	h.add_child(_icon)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	h.add_child(v)
	_name = HyperTheme.label("", 20, HyperTheme.GOLD, 700)
	v.add_child(_name)
	_text = HyperTheme.label("", 22, HyperTheme.CREAM, 600)
	v.add_child(_text)
	_panel.visible = false


func _process(delta: float) -> void:
	time += delta
	if race == null or race.combat == null:
		return
	if race.races_started != _race_number:
		_race_number = race.races_started
		_event_index = race.combat.events.size()
		_hide()
	var events: Array = race.combat.events
	if events.size() < _event_index:
		_event_index = 0
	var mine: Array[int] = _local_humans()
	for k in range(_event_index, events.size()):
		var e: Dictionary = events[k]
		if e.kind != "destroyed" or not mine.has(int(e.car)):
			continue
		if race.get("eliminations_only") == true and not race.session.racers[int(e.car)].is_done():
			continue  # Battle Royale: a hit is not a defeat, only the eliminating one
		var rival := int(e.get("owner", -1))
		if rival < 1 or rival > 9 or race.session.human_ids.has(rival):
			continue  # own weapon, another human, unknown
		if time - _last_shown < MIN_GAP:
			continue
		_show(rival, int(e.car))
	_event_index = events.size()


func _local_humans() -> Array[int]:
	var out: Array[int] = []
	if race.session.spectator:
		return out
	if race.net != null:
		out.append(race.local_player_id)
		return out
	for id in race.session.human_ids:
		out.append(id)
	return out


func _show(rival: int, victim: int) -> void:
	var k: int = _next_line.get(rival, 0)
	_next_line[rival] = (k + 1) % RivalTaunts.count(rival)
	current_rival = rival
	current_text = RivalTaunts.line(rival, k)
	_last_shown = time
	_icon.texture = icons.get(rival)
	var who := RivalRoster.full_name(rival).to_upper()
	if race.is_two_player() and race.net == null:
		who += "  got  P%d" % (1 if victim == RaceSession.PLAYER_ID else 2)
	_name.text = who
	_text.text = '"%s"' % current_text
	_panel.visible = true
	_panel.reset_size()
	var w := _panel.get_combined_minimum_size().x
	_panel.position = Vector2((1280.0 - w) * 0.5, 190)  # below the GO! / FINISH! banners
	var views: PlayerViews = race.player_views
	if views != null and not views.view_for(victim).is_empty():
		# split-screen: in the victim's own view, below their info panel
		var c: SubViewportContainer = views.view_for(victim).container
		var centre: float = c.position.x + c.size.x * c.scale.x * 0.5
		_panel.position = Vector2(clampf(centre - w * 0.5, c.position.x + 8.0, c.position.x + c.size.x * c.scale.x - w - 8.0), 250)
	_panel.modulate.a = 0.0
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_panel, "modulate:a", 1.0, 0.15)
	_tween.tween_interval(SHOW_TIME)
	_tween.tween_property(_panel, "modulate:a", 0.0, 0.4)
	_tween.tween_callback(_hide)
	shown.emit(rival, current_text)


func _hide() -> void:
	_panel.visible = false
	current_rival = 0
