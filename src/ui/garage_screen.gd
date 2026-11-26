class_name GarageScreen
extends CanvasLayer
## The garage between garage races (M3.5): buy and sell rounds of the five
## weapons, mount one weapon type in each slot, then race (or go back to the
## grid panel). Shows money, prices, owned rounds and the last race's prize.
## M6: the car row shows its condition, repair prices and armour.
## All rules live in PlayerGarage; this screen only calls it and redraws.
## 2026-11-23: the car being prepared is the centrepiece (the same CarArt
## picture as everywhere: own car, a won rival car, user artwork, Artwork
## Mode), standing in a spotlight with a gentle sway; buying, selling and
## repairing answer with a pulse and the money changing hands.
## 2026-11-26: the garage is a miniature voxel workshop (GarageWorkshop, a 3D
## viewport behind the panels): the car stands on a turntable as its voxel
## model with its current damage, a mechanic potters about, and repairs pop
## the missing voxels back with sparks. Presentation only.

signal race_requested
signal closed

const Workshop := preload("res://src/ui/garage_workshop.gd")
const W := WeaponRules.Weapon
## Disabled buttons (cannot buy / sell): a dimmed plate and faint text.
const DISABLED_PLATE := Color(0.55, 0.5, 0.47, 0.5)
const DISABLED_TEXT := Color(0.95, 0.91, 0.81, 0.32)

var garage: PlayerGarage
var _resolver: AssetResolver
var _icons: Dictionary = {}
var _root: Control
var _money: Label
var _last: Label
var _summary: Label
var _race_button: Button
var _hint: Label
## Weapon cycling: carry every owned type, or the equipped ones only.
var _carry_button: Button
## Vehicle upgrades: the part cards (shown instead of the weapon cards) and the toggle.
var _weapons_row: HBoxContainer
var _upgrades_row: HBoxContainer
var _view_button: Button
var _upgrade_cards: Dictionary = {}
var _cards: Dictionary = {}
var _cond_bar: ColorRect
var _cond_label: Label
var _repair_all: Button
var _repair_some: Button
var _armour_label: Label
var _armour_button: Button
var _car_note: Label
var _sfx: AudioStreamPlayer
## The workshop behind the panels (its own 3D world) and the picture showing it.
var _workshop: Workshop
var _workshop_view: TextureRect
## The car's CarArt picture (kept for car_texture(); the workshop shows the car).
var _car_rect: TextureRect
var _car_name: Label


const VrWidgets := preload("res://src/ui/vr_widgets.gd")
const VrTips := preload("res://src/ui/vr_tips.gd")


func setup(p_garage: PlayerGarage, resolver: AssetResolver) -> void:
	garage = p_garage
	_resolver = resolver
	layer = 20
	_icons = Hud.weapon_icons(resolver)
	_root = Control.new()
	_root.theme = HyperTheme.build(resolver)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	# the workshop: a voxel diorama in its own world, filling the screen
	_workshop = Workshop.new()
	_workshop.name = "Workshop"
	_workshop.setup(resolver)
	add_child(_workshop)
	_workshop_view = TextureRect.new()
	_workshop_view.texture = _workshop.get_texture()
	_workshop_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_workshop_view.stretch_mode = TextureRect.STRETCH_SCALE
	_workshop_view.size = Vector2(1280, 720)
	_workshop_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_workshop_view)
	_root.add_child(_shade())
	visibility_changed.connect(func() -> void: _workshop.set_active(visible))

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.position = Vector2(36, 96)
	head.add_child(VrWidgets.icon("garage", 36))
	head.add_child(VrWidgets.text("Garage", 30, HyperTheme.GOLD, "regular", 2))
	_root.add_child(head)
	_car_rect = TextureRect.new()
	_car_rect.visible = false
	_root.add_child(_car_rect)
	_car_name = VrWidgets.text("", 14, HyperTheme.CREAM, "regular", 2)
	_car_name.position = Vector2(42, 150)
	_root.add_child(_car_name)
	_money = VrWidgets.text("", 30, HyperTheme.CREAM, "regular", 2)
	_money.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_money.size = Vector2(500, 44)
	_money.position = Vector2(700, 96)
	_root.add_child(_money)
	var coin := VrWidgets.icon("money", 36)
	coin.position = Vector2(1208, 98)
	_root.add_child(coin)
	_last = VrWidgets.text("", 13, HyperTheme.CREAM, "regular", 2)
	_last.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_last.size = Vector2(700, 30)
	_last.position = Vector2(540, 150)
	_root.add_child(_last)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.position = Vector2(26, 196)
	_root.add_child(row)
	_weapons_row = row
	for w in WeaponRules.ALL_WEAPONS:
		row.add_child(_card(w))
	_upgrades_row = HBoxContainer.new()
	_upgrades_row.add_theme_constant_override("separation", 12)
	_upgrades_row.position = Vector2(26, 196)
	_upgrades_row.visible = false
	_root.add_child(_upgrades_row)
	for kind in GarageRules.UPGRADES:
		_upgrades_row.add_child(_upgrade_card(kind))
	_root.add_child(_car_row())  # (the footer below holds its hint line)

	var footer := PanelContainer.new()
	footer.add_theme_stylebox_override("panel", VrWidgets.panel(0.86))
	footer.position = Vector2(26, 590)
	footer.custom_minimum_size = Vector2(1228, 0)
	_root.add_child(footer)
	var fbox := HBoxContainer.new()
	fbox.add_theme_constant_override("separation", 24)
	footer.add_child(fbox)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override("separation", 0)
	fbox.add_child(texts)
	_summary = VrWidgets.text("", 15, HyperTheme.CREAM)
	_summary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	texts.add_child(_summary)
	_car_note = VrWidgets.text("", 13, Color("f0b48a"))
	_car_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_car_note.custom_minimum_size = Vector2(680, 0)
	texts.add_child(_car_note)
	_carry_button = _small_button("")
	_carry_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	VrTips.tip(_carry_button, "Weapons carried")
	_carry_button.pressed.connect(func() -> void:
		_play("ui/ui_select" if garage.set_carry_all(not garage.carry_all) else "ui/ui_back")
		refresh())
	fbox.add_child(_carry_button)
	_race_button = VrWidgets.icon_button("start", "Start race", 48, " Race", 20)
	VrWidgets.style_button(_race_button, Color("2f7d4a"))
	_race_button.add_theme_font_size_override("font_size", 20)
	_race_button.custom_minimum_size = Vector2(150, 48)
	_race_button.pressed.connect(func() -> void:
		_play("ui/ui_select")
		race_requested.emit())
	fbox.add_child(_race_button)
	# Controls hint on a soft dark strip so it reads over the workshop floor.
	var strip := ColorRect.new()
	strip.color = Color(0.1, 0.07, 0.06, 0.55)
	strip.size = Vector2(1280, 34)
	strip.position = Vector2(0, 680)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.visible = false  # (Prototype 005: no permanent control instructions)
	_root.add_child(strip)
	_hint = HyperTheme.label("", 17, Color(HyperTheme.CREAM, 0.88), 600)
	_hint.visible = false
	set_back_label("grid panel")
	var hint := _hint
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.size = Vector2(1280, 34)
	hint.position = Vector2(0, 680)
	_root.add_child(hint)
	_sfx = AudioStreamPlayer.new()
	_sfx.bus = "Effects"
	add_child(_sfx)
	visible = false


## What Back returns to, named in the controls hint ("grid panel" before a
## race; "career" when the garage was opened from the career hub).
func set_back_label(back_to: String) -> void:
	_hint.text = PlayerControls.fmt("Arrows: move    {confirm}: choose    {back}: %s    Weapons: price per round, selling pays half    Repairs: $%d per 1 %%" % [back_to, garage.rules.repair_price_per_point])


## Opens the screen (refreshes every number) with RACE! focused, so one press skips shopping.
## Shows another garage (the career's or the standalone garage races').
func set_garage(g: PlayerGarage) -> void:
	garage = g
	refresh()


func open() -> void:
	_workshop.set_condition(garage.condition, false)  # as it is: no repair show on arrival
	visible = true
	refresh()
	HyperTheme.reveal(_root)
	_race_button.grab_focus()


## The car being prepared (its CarArt picture) and its name.
func set_car(texture: Texture2D, car_name: String) -> void:
	_car_rect.texture = texture
	_car_name.text = car_name


## The car's voxel model on the workshop's turntable: its body drawing, body
## logical name and whether it wears the shared wheels (CarArt.look()).
func set_car_model(texture: Texture2D, body_logical: String, wheels: bool = true) -> void:
	_workshop.set_car(texture, body_logical, wheels, garage.condition if garage != null else 100.0)


func car_texture() -> Texture2D:
	return _car_rect.texture


## A soft shade over the workshop so every label reads: darker at the sides
## (behind the title and the money), along the top edge and behind the panels;
## the band where the car stands stays clear.
func _shade() -> Control:
	var holder := Control.new()
	holder.size = Vector2(1280, 720)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ink := VrStyle.INK
	for horizontal in [true, false]:
		var g := Gradient.new()
		if horizontal:
			g.offsets = PackedFloat32Array([0.0, 0.3, 0.66, 1.0])
			g.colors = PackedColorArray([Color(ink, 0.7), Color(ink, 0.0), Color(ink, 0.0), Color(ink, 0.6)])
		else:
			g.offsets = PackedFloat32Array([0.0, 0.07, 0.24, 0.34, 1.0])
			g.colors = PackedColorArray([Color(ink, 0.5), Color(ink, 0.0), Color(ink, 0.0), Color(ink, 0.42), Color(ink, 0.6)])
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.width = 256 if horizontal else 4
		tex.height = 4 if horizontal else 256
		tex.fill_from = Vector2.ZERO
		tex.fill_to = Vector2(1, 0) if horizontal else Vector2(0, 1)
		var r := TextureRect.new()
		r.texture = tex
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_SCALE
		r.size = Vector2(1280, 720)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(r)
	return holder


## A short pulse on a control (a card, the money, the car row).
func _pulse(node: Control) -> void:
	node.pivot_offset = node.size * 0.5
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector2(1.05, 1.05), 0.08)
	tw.tween_property(node, "scale", Vector2.ONE, 0.16)


## The money changing hands: a small "-$40" / "+$20" rising from the total.
func _float_money(amount: int) -> void:
	if amount == 0:
		return
	var l := HyperTheme.label(("-$%d" if amount < 0 else "+$%d") % absi(amount), 30,
		Color("ff8a6a") if amount < 0 else Color("9ad27a"), 700)
	l.position = _money.position + Vector2(_money.size.x - 130, 40)
	_root.add_child(l)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 46, 0.7)
	tw.tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.2)
	tw.chain().tween_callback(l.queue_free)


func close() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_play("ui/ui_back")
		closed.emit()


func refresh() -> void:
	_workshop.set_condition(garage.condition, visible)  # a repair: the workshop's show
	_money.text = "$ %d" % garage.money
	if garage.races_settled == 0:
		_last.text = "Starting money. Top five finishers win prize money; longer races pay more."
	else:
		_last.text = "Last race: %s   prize $%d   car %d%% -> %d%%" % ["DNF" if garage.last_position <= 0 else _ordinal(garage.last_position),
			garage.last_prize, roundi(garage.last_condition_before + garage.last_patch), roundi(garage.condition)] \
			+ ("   pit fine $%d" % garage.last_fine if garage.last_fine > 0 else "")
	_refresh_car()
	_refresh_upgrades()
	var front := garage.equipped[PlayerGarage.FRONT]
	var rear := garage.equipped[PlayerGarage.REAR]
	var extra := garage.race_carried()
	_summary.text = "FRONT: %s x%d%s      REAR: %s x%d%s" % [WeaponRules.weapon_name(front), garage.count(front) if front != W.NONE else 0,
		_extra_text(extra[PlayerGarage.FRONT]), WeaponRules.weapon_name(rear), garage.count(rear) if rear != W.NONE else 0,
		_extra_text(extra[PlayerGarage.REAR])]
	_carry_button.text = "CARRY: ALL OWNED" if garage.carry_all else "CARRY: EQUIPPED ONLY"
	for w in _cards:
		var c: Dictionary = _cards[w]
		if c.icon.texture == null:  # the voxel weapon renders arrive after setup (VoxelIconStudio)
			c.icon.texture = _icons.get(w)
		c.owned.text = "Owned: %d" % garage.count(w)
		c.buy.disabled = not garage.can_buy(w)
		c.sell.disabled = not garage.can_sell(w)
		var slot := WeaponRules.slot_of(w)
		var mounted: bool = garage.equipped[slot] == w
		c.equip.text = "EQUIPPED" if mounted else "EQUIP"
		c.equip.disabled = mounted
		# equipped is a state, not an unavailable action: gold, not greyed out
		c.equip.add_theme_color_override("font_disabled_color", HyperTheme.GOLD if mounted else DISABLED_TEXT)
		c.panel.self_modulate = Color(1.15, 1.05, 0.8) if mounted else Color.WHITE


## " (+ HOMING 4, SUPER 2)": the other types carried for a slot.
static func _extra_text(d: Dictionary) -> String:
	if d.is_empty():
		return ""
	var parts := PackedStringArray()
	for w in WeaponRules.ALL_WEAPONS:
		if d.has(w):
			parts.append("%s %d" % [Hud.short_weapon_name(w), d[w]])
	return " (+ %s)" % ", ".join(parts)


## M6 car row: condition bar, repair buttons, armour grade and upgrade.
func _car_row() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", VrWidgets.panel(0.86))
	panel.position = Vector2(26, 520)
	panel.custom_minimum_size = Vector2(1228, 0)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var car := VrWidgets.icon("car", 24)
	car.mouse_filter = Control.MOUSE_FILTER_PASS
	VrTips.tip(car, "Car condition")
	box.add_child(car)
	var track := ColorRect.new()
	track.color = Color(0, 0, 0, 0.4)
	track.custom_minimum_size = Vector2(170, 16)
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_cond_bar = ColorRect.new()
	_cond_bar.size = Vector2(170, 16)
	track.add_child(_cond_bar)
	box.add_child(track)
	_cond_label = VrWidgets.text("", 16, HyperTheme.CREAM)
	_cond_label.custom_minimum_size = Vector2(62, 0)
	box.add_child(_cond_label)
	_repair_all = _small_button("REPAIR ALL")
	_repair_all.icon = VrWidgets.VrIcons.tex("repair", 18)
	VrTips.tip(_repair_all, func() -> String: return "Repair car  ($%d per 1%%)" % garage.rules.repair_price_per_point)
	_repair_all.pressed.connect(func() -> void:
		var before := garage.money
		var ok := garage.repair_affordable() > 0.0
		_play("ui/shop_buy" if ok else "ui/ui_back")
		refresh()
		if ok:
			_pulse(panel)
			_float_money(garage.money - before))
	box.add_child(_repair_all)
	_repair_some = _small_button("+10 %")
	VrTips.tip(_repair_some, "Repair 10%")
	_repair_some.pressed.connect(func() -> void:
		var before := garage.money
		var ok := garage.repair(10.0)
		_play("ui/shop_buy" if ok else "ui/ui_back")
		refresh()
		if ok:
			_pulse(panel)
			_float_money(garage.money - before))
	box.add_child(_repair_some)
	_armour_label = VrWidgets.text("", 14, HyperTheme.CREAM)
	_armour_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_armour_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_armour_label)
	_armour_button = _small_button("UPGRADE")
	_armour_button.icon = VrWidgets.VrIcons.tex("armour", 18)
	VrTips.tip(_armour_button, "Armour upgrade")
	_armour_button.pressed.connect(func() -> void:
		var before := garage.money
		var ok := garage.buy_armour()
		_play("ui/shop_buy" if ok else "ui/ui_back")
		refresh()
		if ok:
			_pulse(panel)
			_float_money(garage.money - before)
			_workshop.fit_part())
	box.add_child(_armour_button)
	_view_button = _small_button("UPGRADES")
	_view_button.icon = VrWidgets.VrIcons.tex("upgrade", 18)
	VrTips.tip(_view_button, "Car upgrades")
	_view_button.pressed.connect(func() -> void:
		_play("ui/ui_select")
		show_upgrades(not showing_upgrades()))
	box.add_child(_view_button)
	return panel


func _refresh_car() -> void:
	var c := garage.condition
	_cond_bar.size.x = 170.0 * clampf(c / 100.0, 0.0, 1.0)
	_cond_bar.color = Hud.condition_color(c / 100.0)
	_cond_label.text = "%d%%" % roundi(c)
	var missing := garage.damage_points()
	_repair_all.text = "REPAIRED" if missing <= 0.0 else "REPAIR ALL $%d" % garage.full_repair_cost()
	_repair_all.disabled = not garage.can_repair(missing)
	if missing > 0.0 and _repair_all.disabled and garage.money >= garage.rules.repair_price_per_point:
		_repair_all.disabled = false  # partial: as much as the money pays for
		_repair_all.text = "REPAIR $%d" % (int(garage.money / garage.rules.repair_price_per_point) * garage.rules.repair_price_per_point)
	_repair_some.text = "+10 %% $%d" % garage.rules.repair_price(minf(10.0, missing)) if missing > 0.0 else "+10 %"
	_repair_some.disabled = not garage.can_repair(minf(10.0, missing))
	var red := garage.armour_reduction()
	_armour_label.text = "ARMOUR: %s%s" % [garage.armour_name(), "" if red <= 0.0 else "  (-%d%% damage)" % roundi(red * 100.0)]
	if garage.armour < garage.rules.max_armour():
		var next := garage.armour + 1
		_armour_button.text = "%s -%d%%  $%d" % [garage.armour_name(next), roundi(garage.rules.armour_reduction[next] * 100.0), garage.next_armour_price()]
	else:
		_armour_button.text = "BEST FITTED"
	_armour_button.disabled = not garage.can_buy_armour()
	if c < garage.rules.min_start_condition:
		_car_note.text = "Below %d%%: the team patches the car up to %d%% for free before the race - repair more to stand a hit or two." \
			% [roundi(garage.rules.min_start_condition), roundi(garage.rules.min_start_condition)]
	elif c <= 50.0:
		_car_note.text = "Damage carries over to the next race. At 0 % the car is out (DNF): no prize money."
	else:
		_car_note.text = ""


func _card(w: int) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", VrWidgets.panel(0.86))
	panel.custom_minimum_size = Vector2(232, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	var icon := TextureRect.new()
	icon.texture = _icons.get(w)
	icon.flip_h = w == W.REAR_MISSILE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(180, 64)
	box.add_child(icon)
	var name := VrWidgets.text(WeaponRules.weapon_name(w), 15, HyperTheme.GOLD)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name)
	var slot := VrWidgets.text("%s slot" % ("Front" if WeaponRules.slot_of(w) == 0 else "Rear"), 12, HyperTheme.CREAM_DIM)
	slot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(slot)
	var price := VrWidgets.text("$%d  /  $%d" % [garage.rules.price(w), garage.rules.sell_price(w)], 13, HyperTheme.CREAM)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price.mouse_filter = Control.MOUSE_FILTER_PASS
	VrTips.tip(price, "Buy / sell one round")
	box.add_child(price)
	var owned := VrWidgets.text("", 15, HyperTheme.CREAM)
	owned.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(owned)
	var trade := HBoxContainer.new()
	trade.alignment = BoxContainer.ALIGNMENT_CENTER
	trade.add_theme_constant_override("separation", 6)
	box.add_child(trade)
	var buy := _small_button("BUY")
	buy.icon = VrWidgets.VrIcons.tex("money", 18)
	VrTips.tip(buy, "Buy one round")
	buy.pressed.connect(func() -> void: _trade(w, true))
	var sell := _small_button("SELL")
	sell.icon = VrWidgets.VrIcons.tex("sell", 18)
	VrTips.tip(sell, "Sell (half price)")
	sell.pressed.connect(func() -> void: _trade(w, false))
	trade.add_child(buy)
	trade.add_child(sell)
	var equip := _small_button("EQUIP")
	equip.custom_minimum_size = Vector2(180, 36)
	equip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	equip.pressed.connect(func() -> void:
		if garage.equip(WeaponRules.slot_of(w), w):
			_play("ui/ui_select")
		refresh())
	box.add_child(equip)
	_cards[w] = {"panel": panel, "icon": icon, "owned": owned, "buy": buy, "sell": sell, "equip": equip}
	return panel


## Upgrades view (true) or the weapon cards (false).
func show_upgrades(on: bool) -> void:
	_upgrades_row.visible = on
	_weapons_row.visible = not on
	_view_button.text = "WEAPONS" if on else "UPGRADES"
	if on:
		HyperTheme.reveal(_upgrades_row)


func showing_upgrades() -> bool:
	return _upgrades_row.visible


const UPGRADE_NOTES := {
	"engine": "Pulls harder out of the corners, with a little more top speed.",
	"brakes": "Stops sooner: with Fire held (Fire to Brake) and off the throttle (Fire to Accelerate).",
	"chassis": "Holds the road: less sliding in fast corners. Not armour.",
	"steering": "Turns in more quickly.",
}


func _upgrade_card(kind: String) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(284, 280)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var name := HyperTheme.label(GarageRules.upgrade_title(kind), 24, HyperTheme.GOLD, 700)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name)
	var tier := HyperTheme.label("", 30, HyperTheme.CREAM, 700)  # pips: the level at a glance
	tier.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tier)
	var note := HyperTheme.label(UPGRADE_NOTES.get(kind, ""), 15, HyperTheme.CREAM_DIM, 600)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(256, 44)
	box.add_child(note)
	var now := HyperTheme.label("", 16, HyperTheme.CREAM, 600)
	now.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	now.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(now)
	var next := HyperTheme.label("", 16, Color("f0b48a"), 600)
	next.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	next.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(next)
	var buy := _small_button("BUY")
	buy.custom_minimum_size = Vector2(230, 44)
	buy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	buy.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
	buy.pressed.connect(func() -> void:
		var before := garage.money
		var ok := garage.buy_upgrade(kind)
		_play("ui/shop_buy" if ok else "ui/ui_back")
		refresh()
		if ok:
			_pulse(panel)
			_pulse(_money)
			_float_money(garage.money - before)
			_workshop.fit_part())
	box.add_child(buy)
	_upgrade_cards[kind] = {"panel": panel, "tier": tier, "now": now, "next": next, "buy": buy}
	return panel


func _refresh_upgrades() -> void:
	var top := garage.rules.max_upgrade()
	for kind in _upgrade_cards:
		var c: Dictionary = _upgrade_cards[kind]
		var level := garage.upgrade_level(kind)
		c.tier.text = "%s  %s" % ["●".repeat(level) + "○".repeat(top - level), "STOCK" if level == 0 else "TIER %d / %d" % [level, top]]
		c.now.text = "Fitted: " + ("stock" if level == 0 else garage.rules.upgrade_effect(kind, level))
		if level >= top:
			c.next.text = "Best fitted"
			c.buy.text = "MAXED"
			c.buy.disabled = true
		else:
			c.next.text = "Tier %d: %s" % [level + 1, garage.rules.upgrade_effect(kind, level + 1)]
			c.buy.text = "BUY TIER %d  $%d" % [level + 1, garage.next_upgrade_price(kind)]
			c.buy.disabled = not garage.can_buy_upgrade(kind)
		c.panel.self_modulate = Color(1.15, 1.05, 0.8) if level > 0 else Color.WHITE


func _trade(w: int, buying: bool) -> void:
	var before := garage.money
	var ok := garage.buy(w) if buying else garage.sell(w)
	_play(("ui/shop_buy" if buying else "ui/shop_sell") if ok else "ui/ui_back")
	refresh()
	if ok:
		_pulse(_cards[w].panel)
		_pulse(_money)
		_float_money(garage.money - before)


func _small_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	VrWidgets.style_button(b)
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_disabled_color", DISABLED_TEXT)
	b.custom_minimum_size = Vector2(70, 36)
	b.mouse_entered.connect(func() -> void:
		if not b.disabled:
			b.grab_focus())
	return b


func _play(logical: String) -> void:
	_sfx.stream = _resolver.get_audio(logical)
	_sfx.play()


static func _ordinal(n: int) -> String:
	if n <= 0:
		return "-"
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1: suffix = "st"
			2: suffix = "nd"
			3: suffix = "rd"
	return "%d%s" % [n, suffix]
