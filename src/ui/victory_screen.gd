class_name VictoryScreen
extends CanvasLayer
## The career's ending (2026-11-22): after winning the HyperCars Grand
## Championship. A short celebration, skippable at once with Confirm or Back:
## "HYPERCARS CHAMPION", a podium with the top three cars as they raced (the
## player's chosen car, rivals in their own colours or the junker; user
## artwork applies through CarArt), a drawn trophy, confetti and the final
## standings with points. No portraits, no voice: the cars are the characters.
## Presentation only.

signal done

## Input is ignored for this long, so the Confirm that closed the standings
## does not skip the ceremony unseen.
const INPUT_DELAY := 0.8

var _root: Control
var _podium: Control
var _hint: Label
var _age := 0.0
var _confetti: CPUParticles2D
var _shown := false


func setup(resolver: AssetResolver) -> void:
	layer = 30
	_root = Control.new()
	_root.theme = HyperTheme.build(resolver)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	visible = false


## champ: the decided Grand Championship; icons: racer id -> car picture.
func show_victory(champ: Championship, icons: Dictionary, career: Career) -> void:
	for c in _root.get_children():
		c.queue_free()
	var bg := ColorRect.new()
	bg.color = Color("1c1614")
	bg.size = Vector2(1280, 720)
	_root.add_child(bg)
	var glow := ColorRect.new()  # a warm stage light behind the podium
	glow.color = Color(0.89, 0.7, 0.24, 0.12)
	glow.position = Vector2(300, 90)
	glow.size = Vector2(680, 560)
	_root.add_child(glow)
	var title := HyperTheme.label("HYPERCARS CHAMPION", 64, HyperTheme.GOLD, 700)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(1280, 80)
	title.position = Vector2(0, 18)
	title.pivot_offset = Vector2(640, 40)
	_root.add_child(title)
	var order := champ.standings()
	var sub := HyperTheme.label("%s  -  %d points, %d wins in %d rounds" % [champ.schedule.title.to_upper(),
		champ.points[order[0]], champ.wins(order[0]), champ.schedule.round_count()], 22, HyperTheme.CREAM, 600)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.size = Vector2(1280, 30)
	sub.position = Vector2(0, 98)
	_root.add_child(sub)

	_podium = Control.new()
	_podium.set_script(preload("res://src/ui/victory_podium.gd"))
	_podium.position = Vector2(330, 130)
	_podium.size = Vector2(620, 520)
	_root.add_child(_podium)
	_podium.setup(order.slice(0, 3), icons)

	var table := VBoxContainer.new()
	table.position = Vector2(980, 150)
	table.add_theme_constant_override("separation", 2)
	_root.add_child(table)
	table.add_child(HyperTheme.label("FINAL STANDINGS", 18, HyperTheme.GOLD, 700))
	for k in order.size():
		var id: int = order[k]
		var row := HyperTheme.label("%2d.  %s  %d" % [k + 1, "YOU" if id == RaceSession.PLAYER_ID else RivalRoster.short_name(id),
			champ.points[id]], 18, HyperTheme.GOLD if id == RaceSession.PLAYER_ID else HyperTheme.CREAM, 600)
		table.add_child(row)

	var record := HyperTheme.label("Career: %d races, %d wins, %d podiums. Rookie Cup, Pro Series and Grand Championship won." % [
		career.races, career.race_wins, career.podiums], 18, HyperTheme.CREAM, 600)
	record.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	record.custom_minimum_size = Vector2(270, 0)
	record.position = Vector2(24, 160)
	record.size = Vector2(270, 300)
	_root.add_child(record)

	_confetti = CPUParticles2D.new()
	_confetti.position = Vector2(640, -10)
	_confetti.amount = 160
	_confetti.lifetime = 4.0
	_confetti.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_confetti.emission_rect_extents = Vector2(660, 4)
	_confetti.direction = Vector2(0, 1)
	_confetti.spread = 25.0
	_confetti.gravity = Vector2(0, 120)
	_confetti.initial_velocity_min = 60.0
	_confetti.initial_velocity_max = 160.0
	_confetti.angular_velocity_min = -300.0
	_confetti.angular_velocity_max = 300.0
	_confetti.scale_amount_min = 4.0
	_confetti.scale_amount_max = 7.0
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	ramp.colors = PackedColorArray([HyperTheme.GOLD, Color("e0533a"), Color("74bdf2"), Color("7cc46a"), HyperTheme.CREAM])
	_confetti.color_initial_ramp = ramp
	_root.add_child(_confetti)
	_confetti.emitting = true

	_hint = HyperTheme.label(PlayerControls.fmt("{confirm}: continue to the Hall of Fame"), 18, HyperTheme.CREAM, 600)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.size = Vector2(1280, 30)
	_hint.position = Vector2(0, 680)
	_root.add_child(_hint)
	title.scale = Vector2(0.4, 0.4)
	create_tween().tween_property(title, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_age = 0.0
	_shown = true
	visible = true


func showing() -> bool:
	return visible and _shown


func close() -> void:
	_shown = false
	visible = false
	if _confetti != null:
		_confetti.emitting = false


func _process(delta: float) -> void:
	if visible:
		_age += delta


func _unhandled_input(event: InputEvent) -> void:
	if not showing():
		return
	if event.is_action_pressed(PlayerControls.CONFIRM) or event.is_action_pressed(PlayerControls.BACK):
		get_viewport().set_input_as_handled()
		if _age >= INPUT_DELAY:
			close()
			done.emit()
